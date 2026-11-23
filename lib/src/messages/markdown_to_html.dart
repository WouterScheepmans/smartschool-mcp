/// Converts the text of a message Claude writes, plain text or simple
/// Markdown, to the HTML body Smartschool sends.
///
/// Every character of [text] is escaped, so HTML in it shows as text and
/// never becomes markup: the text cannot add tags, attributes or scripts to
/// the message. Only this converter writes tags:
///
/// - a blank line starts a new paragraph (`<p>`), a single line break becomes
///   `<br>`;
/// - lines starting with `- `, `* ` or `+ ` become a bulleted list, lines
///   starting with `1. ` or `1) ` a numbered list (an indented line that
///   follows an item continues it);
/// - `**bold**` and `__bold__` become `<strong>`, `*italic*` and `_italic_`
///   `<em>` (not inside a word for `_`, and not with a space right inside
///   the markers, so `5 * 3` and `file_name` stay as written);
/// - `[text](https://...)` becomes a link for `http`, `https` and `mailto`
///   addresses; any other link is left as written.
///
/// Anything else (headings, code, tables) is kept as the text it is.
String markdownToHtml(String text) => _convert(text, _Flavor.message);

/// Converts an info text of the planner or the Lesfiches module that Claude
/// writes (what pupils see, or the private info), plain text or simple
/// Markdown with colours, to the HTML the module's own editor makes.
///
/// As [markdownToHtml], with these differences:
///
/// - a single line break becomes `<br />` and the blocks follow each other
///   without a line break in between, as the editor writes them; so plain
///   text gives one `<p>` per paragraph;
/// - only `&`, `<` and `>` are escaped: quotes are not markup in text, and
///   the module keeps them as quotes;
/// - `++underlined++` becomes `<u>`;
/// - `{red}coloured text{/}` becomes
///   `<span style="color: #e03e2d;">coloured text</span>`: the colour is one
///   of [infoColors] by name, or `#rrggbb` / `#rgb`. A colour that is not
///   known is left as written. Colours do not nest (the first `{/}` ends
///   the colour), but may hold and be held by bold, italic and underline.
///
/// Text that is empty or white space only is `""`: no info.
String infoMarkdownToHtml(String text) => _convert(text, _Flavor.info);

/// The colours an info text can name, `{name}...{/}`, with the hex code
/// written: the text colours of the web editor's palette. `htmlToText` with
/// `markup` names a colour of this list by its name, any other by its hex
/// code.
const infoColors = {
  'red': '#e03e2d',
  'dark red': '#ba372a',
  'orange': '#e67e23',
  'yellow': '#f1c40f',
  'green': '#2dc26b',
  'dark green': '#169179',
  'blue': '#3598db',
  'dark blue': '#236fa1',
  'purple': '#b96ad9',
  'dark purple': '#843fa1',
  'gray': '#95a5a6',
  'dark gray': '#7e8c8d',
  'black': '#000000',
};

/// How [_convert] writes HTML for a kind of text.
enum _Flavor {
  /// A message body: `<br>`, blocks on lines of their own, all of `&<>"'`
  /// escaped, no underline or colours.
  message(lineBreak: '<br>', blockSeparator: '\n', rich: false),

  /// An info of the planner or Lesfiches module: as its editor writes it.
  info(lineBreak: '<br />', blockSeparator: '', rich: true);

  const _Flavor({
    required this.lineBreak,
    required this.blockSeparator,
    required this.rich,
  });

  final String lineBreak;
  final String blockSeparator;

  /// Whether underline and colours are markup, and quotes are left as they
  /// are.
  final bool rich;

  String escape(String text) => rich ? _escapeText(text) : escapeHtml(text);
}

String _convert(String text, _Flavor flavor) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final blocks = <String>[];
  final paragraph = <String>[];
  final items = <String>[];
  _ListKind? list;
  int? listStart;
  String inline(String line) => _inline(line, flavor);

  void endParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add('<p>${paragraph.map(inline).join(flavor.lineBreak)}</p>');
    paragraph.clear();
  }

  void endList() {
    if (list == null) return;
    final start = listStart != null && listStart != 1
        ? ' start="$listStart"'
        : '';
    blocks.add(
      '<${list!.tag}$start>'
      '${items.map((item) => '<li>$item</li>').join()}'
      '</${list!.tag}>',
    );
    items.clear();
    list = null;
    listStart = null;
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      endParagraph();
      endList();
      continue;
    }
    if (_bullet.firstMatch(line) case final match?) {
      endParagraph();
      if (list != _ListKind.bulleted) endList();
      list = _ListKind.bulleted;
      items.add(inline(match[1]!.trim()));
    } else if (_numbered.firstMatch(line) case final match?) {
      endParagraph();
      if (list != _ListKind.numbered) {
        endList();
        listStart = int.tryParse(match[1]!);
      }
      list = _ListKind.numbered;
      items.add(inline(match[2]!.trim()));
    } else if (list != null && line.startsWith(RegExp(r'\s'))) {
      items.add(
        '${items.removeLast()}${flavor.lineBreak}${inline(line.trim())}',
      );
    } else {
      endList();
      paragraph.add(line.trim());
    }
  }
  endParagraph();
  endList();
  return blocks.join(flavor.blockSeparator);
}

enum _ListKind {
  bulleted('ul'),
  numbered('ol');

  const _ListKind(this.tag);

  final String tag;
}

final _bullet = RegExp(r'^\s*[-*+]\s+(\S.*)$');
final _numbered = RegExp(r'^\s*(\d{1,9})[.)]\s+(\S.*)$');

/// One line of text with its inline markup converted and everything else
/// escaped.
String _inline(String text, _Flavor flavor) => text.splitMapJoin(
  flavor.rich ? _richMarkup : _inlineMarkup,
  onMatch: (found) {
    final match = found as RegExpMatch;
    String inner(String text) => _inline(text, flavor);
    if (match.namedGroup('linkText') case final linkText?) {
      final url = match.namedGroup('url')!;
      if (!_allowedUrl.hasMatch(url)) return flavor.escape(match[0]!);
      return '<a href="${escapeHtml(url)}">${inner(linkText)}</a>';
    }
    if (flavor.rich) {
      if (match.namedGroup('color') case final color?) {
        final hex = _colorHex(color);
        // A colour that is not known stays as written; its text is still
        // converted.
        if (hex == null) {
          return '${flavor.escape('{$color}')}'
              '${inner(match.namedGroup('colored')!)}'
              '${flavor.escape('{/}')}';
        }
        return '<span style="color: $hex;">'
            '${inner(match.namedGroup('colored')!)}</span>';
      }
      if (match.namedGroup('underline') case final underlined?) {
        return '<u>${inner(underlined)}</u>';
      }
    }
    if (match.namedGroup('boldItalic') case final both?) {
      return '<strong><em>${inner(both)}</em></strong>';
    }
    if (match.namedGroup('bold') ?? match.namedGroup('bold2')
        case final bold?) {
      return '<strong>${inner(bold)}</strong>';
    }
    final italic = match.namedGroup('italic') ?? match.namedGroup('italic2');
    return '<em>${inner(italic!)}</em>';
  },
  onNonMatch: flavor.escape,
);

/// The hex code of [color], a name of [infoColors] or `#rrggbb` / `#rgb`, in
/// lower case and with six digits; `null` when it is neither.
String? _colorHex(String color) {
  final name = color.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (infoColors[name] case final hex?) return hex;
  if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(name)) return name;
  if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(name)) {
    return '#${name.substring(1).split('').map((d) => '$d$d').join()}';
  }
  return null;
}

const _link = r'\[(?<linkText>[^\]\n]+)\]\((?<url>[^()\s]+)\)';
const _emphasis =
    r'|\*\*\*(?<boldItalic>[^\s*](?:.*?[^\s*])?)\*\*\*'
    r'|\*\*(?<bold>\S(?:.*?\S)?)\*\*'
    r'|(?<![\p{L}\p{N}_])__(?<bold2>\S(?:.*?\S)?)__(?![\p{L}\p{N}_])'
    r'|\*(?<italic>[^\s*](?:[^*]*?[^\s*])?)\*'
    r'|(?<![\p{L}\p{N}_])_(?<italic2>[^\s_](?:[^_]*?[^\s_])?)_(?![\p{L}\p{N}_])';

/// Links, bold and italic, leftmost first. Bold and italic together
/// (`***x***`) come before bold, and bold before italic, so `**x**` is not
/// read as italic `*` around `*x*`.
final _inlineMarkup = RegExp('$_link$_emphasis', unicode: true);

/// [_inlineMarkup] with colours (`{red}x{/}`) and underline (`++x++`), which
/// come first, so a colour can hold bold text and the other way round.
final _richMarkup = RegExp(
  '$_link'
  r'|\{(?<color>#[0-9A-Fa-f]{3,6}|[A-Za-z]+(?: [A-Za-z]+)?)\}'
  r'(?<colored>.+?)\{/\}'
  r'|\+\+(?<underline>\S(?:.*?\S)?)\+\+'
  '$_emphasis',
  unicode: true,
);

final _allowedUrl = RegExp(r'^(https?://|mailto:)\S+$', caseSensitive: false);

/// [text] with every character that is markup in HTML escaped (`&`, `<`,
/// `>` and both quotes), so that it shows as the text it is, also inside an
/// attribute.
String escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// [text] with `&`, `<` and `>` escaped: enough for text content, which is
/// never inside an attribute.
String _escapeText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
