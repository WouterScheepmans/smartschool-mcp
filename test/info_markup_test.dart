/// The formatting of an info of the planner and the Lesfiches module: the
/// Markdown Claude writes as the web editor's HTML (`infoMarkdownToHtml`),
/// and that HTML shown back as the same Markdown (`htmlToText` with
/// `markup`).
library;

import 'package:smartschool_mcp/src/messages/html_to_text.dart';
import 'package:smartschool_mcp/src/messages/markdown_to_html.dart';
import 'package:test/test.dart';

void main() {
  group('infoMarkdownToHtml', () {
    test('lists, as the editor writes them', () {
      expect(
        infoMarkdownToHtml(
          'Breng mee:\n- laptop\n- lader\n\n1. lezen\n2. doen',
        ),
        '<p>Breng mee:</p><ul><li>laptop</li><li>lader</li></ul>'
        '<ol><li>lezen</li><li>doen</li></ol>',
      );
    });

    test('bold, italic and underline', () {
      expect(
        infoMarkdownToHtml('**vet**, *schuin* en ++onderlijnd++'),
        '<p><strong>vet</strong>, <em>schuin</em> en <u>onderlijnd</u></p>',
      );
    });

    test('colours by name and by hex code, with formatting inside and '
        'around them', () {
      expect(
        infoMarkdownToHtml('{red}let op{/} en {Dark Blue}**Taak**{/}'),
        '<p><span style="color: #e03e2d;">let op</span> en '
        '<span style="color: #236fa1;"><strong>Taak</strong></span></p>',
      );
      expect(
        infoMarkdownToHtml('**{#1A7F37}groen{/}** en {#f00}rood{/}'),
        '<p><strong><span style="color: #1a7f37;">groen</span></strong> en '
        '<span style="color: #ff0000;">rood</span></p>',
      );
    });

    test('an unknown colour stays as written, its text still formatted', () {
      expect(
        infoMarkdownToHtml('{fuchsia}**x**{/}'),
        '<p>{fuchsia}<strong>x</strong>{/}</p>',
      );
    });

    test('HTML is never markup, also not in a colour or a style', () {
      expect(
        infoMarkdownToHtml('{red}<script>x</script>{/} <span style="x">'),
        '<p><span style="color: #e03e2d;">&lt;script&gt;x&lt;/script&gt;'
        '</span> &lt;span style="x"&gt;</p>',
      );
      expect(
        infoMarkdownToHtml('{red;background:url(x)}a{/}'),
        '<p>{red;background:url(x)}a{/}</p>',
      );
    });

    test('plain text is as before: no quotes escaped, <br /> per line', () {
      expect(
        infoMarkdownToHtml('a "b"\nc 5 * 3 = 15 en 1 + 1'),
        '<p>a "b"<br />c 5 * 3 = 15 en 1 + 1</p>',
      );
    });
  });

  group('htmlToText with markup', () {
    String show(String html) => htmlToText(html, markup: true);

    test('shows tags and styles of the editor as Markdown', () {
      expect(
        show(
          '<p><strong>vet</strong> <b>ook</b> <em>schuin</em> <i>ook</i> '
          '<u>onder</u> <span style="text-decoration: underline;">ook</span> '
          '<span style="font-weight: bold">vet</span> '
          '<span style="font-style:italic">schuin</span></p>',
        ),
        '**vet** **ook** *schuin* *ook* ++onder++ ++ook++ **vet** *schuin*',
      );
    });

    test('names a colour of the palette, gives another its hex code', () {
      expect(
        show(
          '<p><span style="color: #E03E2D;">rood</span>, '
          '<span style="color: rgb(53, 152, 219)">blauw</span>, '
          '<font color="#123">anders</font>, '
          '<span style="color: inherit">gewoon</span></p>',
        ),
        '{red}rood{/}, {blue}blauw{/}, {#112233}anders{/}, gewoon',
      );
    });

    test('nests markers in the order the writer reads them back', () {
      expect(
        show(
          '<p><span style="color: #e03e2d; font-weight: bold;">'
          'Let <em>op</em></span>!</p>',
        ),
        '{red}**Let *op***{/}!',
      );
    });

    test('keeps spaces outside the markers and leaves out empty ones', () {
      expect(
        show('<p>a<strong> b </strong>c<em> </em>d<u></u></p>'),
        'a **b** c d',
      );
    });

    test('round trip: what it shows converts back to the same HTML', () {
      const html =
          '<p>Intro <strong>vet</strong> en '
          '<span style="color: #e03e2d;"><em>rood</em></span></p>'
          '<ul><li><u>een</u></li><li>twee</li></ul>';
      expect(infoMarkdownToHtml(show(html)), html);
    });

    test('without markup, formatting is dropped as before', () {
      expect(htmlToText('<p><strong>vet</strong> <u>x</u></p>'), 'vet x');
    });
  });
}
