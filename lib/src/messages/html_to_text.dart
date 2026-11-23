import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'markdown_to_html.dart' show infoColors;

/// Converts an HTML message body to readable plain text with light Markdown.
///
/// Meant for text Claude reads (to summarise or search a message), not for
/// display. The result keeps the structure that carries meaning and drops the
/// rest:
///
/// - paragraphs and other blocks are separated by a blank line, `<br>` by a
///   line break;
/// - headings become `#` lines, list items `- ` or `1. ` lines (nested lists
///   indented), blockquotes `> ` lines, table rows one line with the cells
///   joined by ` | `, and `<hr>` a `---` line;
/// - links become `[text](url)`: just the address when the text is the
///   address, just the text when the link is not absolute (`http(s):`,
///   `mailto:` or `tel:`);
/// - images become `[image: alt]`, or `[image]` without alt text;
/// - scripts, styles, the document head and comments are dropped;
/// - character references are decoded, runs of whitespace (including
///   non-breaking spaces) collapse to one space outside `<pre>`, and there is
///   never more than one blank line in a row.
///
/// A body without any HTML tags is treated as plain text: its line breaks are
/// kept.
///
/// With [markup], inline formatting is kept too, in the Markdown that
/// `infoMarkdownToHtml` reads back: bold (`<strong>`, `<b>`, a bold
/// `font-weight`) as `**bold**`, italic (`<em>`, `<i>`, `font-style:
/// italic`) as `*italic*`, underline (`<u>`, `text-decoration: underline`)
/// as `++underlined++`, and a text colour (a `color` style or `<font
/// color>`) as `{name}text{/}` for a colour of `infoColors`, `{#rrggbb}text{/}`
/// for another. Formatting without visible text leaves no markers.
String htmlToText(String html, {bool markup = false}) {
  if (!_tag.hasMatch(html)) {
    // Plain text: parse it as preformatted, which decodes character
    // references but keeps the line breaks. Without tags it cannot close the
    // <pre>.
    html = '<pre>$html</pre>';
  }
  final document = html_parser.parse(html);
  final root = document.body ?? document.documentElement;
  if (root == null) return '';
  return (_TextWriter(markup: markup)..children(root)).result();
}

/// Something that starts an HTML tag, comment or doctype.
final _tag = RegExp(r'<[a-zA-Z/!]');

/// Elements whose content is never text for the reader.
const _dropped = {
  'head',
  'script',
  'style',
  'template',
  'noscript',
  'title',
  'meta',
  'link',
  'iframe',
  'object',
  'embed',
  'svg',
  'canvas',
  'xml',
  'select',
  'input',
  'textarea',
};

/// Elements that start after a blank line and are followed by one.
const _paragraphs = {'p', 'table', 'figure', 'address', 'fieldset', 'form'};

/// Elements that start on a line of their own.
const _lines = {
  'div',
  'section',
  'article',
  'header',
  'footer',
  'main',
  'nav',
  'aside',
  'center',
  'dl',
  'dt',
  'dd',
  'figcaption',
  'caption',
  'tbody',
  'thead',
  'tfoot',
  'details',
  'summary',
  'legend',
};

const _headings = {'h1': 1, 'h2': 2, 'h3': 3, 'h4': 4, 'h5': 5, 'h6': 6};

/// Whitespace that collapses to a single space outside `<pre>`, including
/// non-breaking spaces.
final _whitespace = RegExp(r'[ \t\r\n\f   ]+');

/// Invisible characters that only get in the way of reading and searching.
final _invisible = RegExp(r'[​‌‍­﻿]');

final _absoluteLink = RegExp(r'^(https?:|mailto:|tel:)', caseSensitive: false);
final _addressScheme = RegExp(r'^(mailto:|tel:)', caseSensitive: false);

/// A line prefix: [first] on the first line written inside the element that
/// added it, [rest] on the lines after that.
final class _Prefix {
  _Prefix(this.first, this.rest);

  final String first;
  final String rest;
  bool used = false;
}

/// Writes the text of a DOM tree the way a browser lays it out.
///
/// Line breaks and gaps (a space, or a table cell separator) are kept pending
/// and only written in front of the next visible text, so empty elements and
/// trailing whitespace leave no trace.
final class _TextWriter {
  _TextWriter({required this.markup});

  /// Whether inline formatting is written as Markdown markers.
  final bool markup;

  final StringBuffer _out = StringBuffer();

  /// Opening markers of formatting that has no visible text yet: written in
  /// front of the next text, dropped when the formatting ends first.
  String _pendingOpen = '';

  /// Line breaks to write before the next text; 2 means a blank line.
  int _pendingBreaks = 0;

  /// What to write between the previous text and the next on the same line.
  String? _pendingGap;

  /// Whether any text was written yet.
  bool _written = false;

  /// How many visible characters were written; lets a table row see whether
  /// a cell had any content.
  int _visible = 0;

  int _preDepth = 0;
  final List<_Prefix> _prefixes = [];

  String result() => _out
      .toString()
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  void children(Node node) {
    for (final child in node.nodes) {
      _node(child);
    }
  }

  void _node(Node node) {
    switch (node) {
      case Text(:final data):
        _text(data);
      case Element():
        _element(node);
      default:
      // Comments and doctypes carry no text.
    }
  }

  void _element(Element element) {
    final name = element.localName ?? '';
    if (_dropped.contains(name)) return;
    if (_headings[name] case final level?) {
      if (element.text.replaceAll(_whitespace, '').isEmpty) return;
      _break(2);
      _emit('#' * level);
      _pendingGap = ' ';
      children(element);
      _break(2);
      return;
    }
    switch (name) {
      case 'br':
        if (_written) _pendingBreaks++;
        _pendingGap = null;
      case 'hr':
        _break(2);
        _emit('---');
        _break(2);
      case 'img':
        final alt = _collapse(element.attributes['alt'] ?? '');
        _emit(alt.isEmpty ? '[image]' : '[image: $alt]');
      case 'a':
        _link(element);
      case 'ul' || 'ol':
        _list(element, ordered: name == 'ol');
      case 'li':
        // A list item outside a list.
        _listItem(element, '- ');
      case 'blockquote':
        _break(2);
        _prefixes.add(_Prefix('> ', '> '));
        children(element);
        _prefixes.removeLast();
        _break(2);
      case 'pre':
        _break(2);
        _preDepth++;
        children(element);
        _preDepth--;
        _break(2);
      case 'tr':
        _row(element);
      default:
        if (_paragraphs.contains(name)) {
          _break(2);
          children(element);
          _break(2);
        } else if (_lines.contains(name)) {
          _break(1);
          children(element);
          _break(1);
        } else if (markup && _preDepth == 0) {
          _formatted(element);
        } else {
          // Inline elements (span, strong, font, td outside a row, ...) and
          // unknown ones.
          children(element);
        }
    }
  }

  /// The children of [element], an inline element, between the markers of
  /// its formatting ([_markers]).
  void _formatted(Element element) {
    final markers = _markers(element);
    for (final (open, _) in markers) {
      _pendingOpen += open;
    }
    children(element);
    for (final (open, close) in markers.reversed) {
      if (_pendingOpen.endsWith(open)) {
        // No visible text inside: no markers either.
        _pendingOpen = _pendingOpen.substring(
          0,
          _pendingOpen.length - open.length,
        );
      } else {
        _out.write(close);
      }
    }
  }

  /// The opening and closing markers of the formatting of [element], the
  /// outermost first: its colour, then bold, italic and underline.
  static List<(String, String)> _markers(Element element) {
    final name = element.localName ?? '';
    final style = _styles(element.attributes['style'] ?? '');
    final weight = style['font-weight'] ?? '';
    final bold =
        name == 'strong' ||
        name == 'b' ||
        weight == 'bold' ||
        weight == 'bolder' ||
        (int.tryParse(weight) ?? 0) >= 600;
    final italic =
        name == 'em' ||
        name == 'i' ||
        (style['font-style'] ?? '').startsWith('italic');
    final underline =
        name == 'u' ||
        (style['text-decoration'] ?? '').contains('underline') ||
        (style['text-decoration-line'] ?? '').contains('underline');
    final color = _colorName(
      style['color'] ?? (name == 'font' ? element.attributes['color'] : null),
    );
    return [
      if (color != null) ('{$color}', '{/}'),
      if (bold) ('**', '**'),
      if (italic) ('*', '*'),
      if (underline) ('++', '++'),
    ];
  }

  /// The declarations of a `style` attribute, by lower-case property name.
  static Map<String, String> _styles(String style) => {
    for (final declaration in style.split(';'))
      if (declaration.indexOf(':') case final colon when colon > 0)
        declaration.substring(0, colon).trim().toLowerCase(): declaration
            .substring(colon + 1)
            .replaceAll(RegExp(r'!important', caseSensitive: false), '')
            .trim()
            .toLowerCase(),
  };

  /// [color], a CSS colour (`#rgb`, `#rrggbb` or `rgb(r, g, b)`), as an
  /// info text names it: the name of a colour of [infoColors], or its hex
  /// code. `null` for no colour, black's `inherit` and the like, and a
  /// colour it cannot read.
  static String? _colorName(String? color) {
    if (color == null) return null;
    var value = color.trim().toLowerCase();
    if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(value)) {
      value = '#${value.substring(1).split('').map((d) => '$d$d').join()}';
    } else if (RegExp(
          r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*[\d.]+\s*)?\)$',
        ).firstMatch(value)
        case final rgb?) {
      value =
          '#${[1, 2, 3].map((i) => int.parse(rgb[i]!).clamp(0, 255).toRadixString(16).padLeft(2, '0')).join()}';
    }
    if (!RegExp(r'^#[0-9a-f]{6}$').hasMatch(value)) return null;
    for (final MapEntry(:key, value: hex) in infoColors.entries) {
      if (hex == value) return key;
    }
    return value;
  }

  void _link(Element link) {
    final href = (link.attributes['href'] ?? '').trim();
    if (!_absoluteLink.hasMatch(href)) {
      children(link);
      return;
    }
    final text = _collapse(link.text);
    final address = href.replaceFirst(_addressScheme, '');
    if (text.isEmpty) {
      // Usually a linked image: its alt text, then the address.
      children(link);
      if (_written && _pendingBreaks == 0) _pendingGap ??= ' ';
      _emit(address);
    } else if (text == href || text == address) {
      _emit(text);
    } else {
      _emit('[$text]($href)');
    }
  }

  void _list(Element list, {required bool ordered}) {
    // A nested list starts on the next line, a top-level one after a blank
    // line.
    final nested = _prefixes.isNotEmpty;
    _break(nested ? 1 : 2);
    var number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    for (final child in list.nodes) {
      if (child is Element && child.localName == 'li') {
        _listItem(child, ordered ? '${number++}. ' : '- ');
      } else {
        _node(child);
      }
    }
    _break(nested ? 1 : 2);
  }

  void _listItem(Element item, String marker) {
    _break(1);
    _prefixes.add(_Prefix(marker, ' ' * marker.length));
    children(item);
    _prefixes.removeLast();
    // Items stay on consecutive lines, even when they hold paragraphs.
    if (_pendingBreaks > 1) _pendingBreaks = 1;
    _break(1);
  }

  void _row(Element row) {
    _break(1);
    var cellsWithContent = 0;
    for (final child in row.nodes) {
      if (child is Element &&
          (child.localName == 'td' || child.localName == 'th')) {
        if (cellsWithContent > 0 && _pendingBreaks == 0) _pendingGap = ' | ';
        final before = _visible;
        children(child);
        if (_visible > before) {
          cellsWithContent++;
        } else if (_pendingGap == ' | ') {
          _pendingGap = null;
        }
      } else {
        _node(child);
      }
    }
    _break(1);
  }

  /// Asks for (at least) [count] line breaks before the next text.
  void _break(int count) {
    if (!_written) return;
    // The first block inside a list item or quote starts right after its
    // marker, without a blank line of its own.
    if (_prefixes.isNotEmpty && !_prefixes.last.used && count > 1) {
      count = 1;
    }
    if (count > _pendingBreaks) _pendingBreaks = count;
    _pendingGap = null;
  }

  void _text(String data) {
    data = data.replaceAll(_invisible, '');
    if (_preDepth > 0) {
      _preformatted(data);
      return;
    }
    final collapsed = data.replaceAll(_whitespace, ' ');
    if (collapsed.isEmpty) return;
    if (collapsed.startsWith(' ') && _written && _pendingBreaks == 0) {
      _pendingGap ??= ' ';
    }
    final words = collapsed.trim();
    if (words.isEmpty) return;
    _emit(words);
    if (collapsed.endsWith(' ')) _pendingGap ??= ' ';
  }

  /// Writes preformatted text, keeping its line breaks and indentation.
  void _preformatted(String data) {
    final lines = data.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0 && _written) {
        _pendingBreaks++;
        _pendingGap = null;
      }
      final line = lines[i].trimRight();
      if (line.trim().isNotEmpty) _emit(line);
    }
  }

  /// Writes visible [text], preceded by the pending line breaks (with the
  /// line prefixes) or gap.
  void _emit(String text) {
    if (!_written || _pendingBreaks > 0) {
      if (_written) {
        // A blank line inside a quote keeps its `>`.
        final blank = _prefixes
            .where((p) => p.used)
            .map((p) => p.rest)
            .join()
            .trimRight();
        for (var i = 0; i < _pendingBreaks; i++) {
          _out.write(i == 0 ? '\n' : '$blank\n');
        }
      }
      for (final prefix in _prefixes) {
        _out.write(prefix.used ? prefix.rest : prefix.first);
        prefix.used = true;
      }
      _pendingBreaks = 0;
    } else if (_pendingGap case final gap?) {
      _out.write(gap);
    }
    _pendingGap = null;
    _out.write(_pendingOpen);
    _pendingOpen = '';
    _out.write(text);
    _visible += text.length;
    _written = true;
  }

  static String _collapse(String text) =>
      text.replaceAll(_invisible, '').replaceAll(_whitespace, ' ').trim();
}
