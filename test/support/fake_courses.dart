import 'package:dio/dio.dart';

import 'fake_messages.dart' show sessionOf;
import 'fake_uploads.dart';

/// An item of a course's documents in [FakeCourses].
class FakeCourseDocument {
  FakeCourseDocument(
    this.id,
    this.name, {
    this.folder = false,
    this.visible = true,
    this.from,
    this.until,
  });

  final int id;
  final String name;
  final bool folder;
  final bool visible;
  final String? from;
  final String? until;
}

/// A news item of a course in [FakeCourses].
class FakeCourseNews {
  FakeCourseNews(this.id, this.title, this.html, {this.visible = true});

  final int id;
  final String title;
  final String html;
  final bool visible;
}

/// A course of the course menu in [FakeCourses].
class FakeCourse {
  FakeCourse(this.id, this.name, {this.description = '', this.kind = 'own'});

  final int id;
  final String name;
  final String description;

  /// The key of the course menu's answer: `own`, `titu` or `community`.
  final String kind;

  /// The documents, by folder id (`0` is the top).
  final Map<int, List<FakeCourseDocument>> folders = {0: []};

  /// The upload zones, `(id, name)`.
  final List<(int, String)> zones = [];

  final List<FakeCourseNews> news = [];
}

/// The course modules of Smartschool as `CourseService` reads and writes
/// them (dartschool's `CourseService`, seen live on 2026-11-23): the course menu
/// (`POST /Topnav/getCourseConfig`), the documents' management pages and
/// their saves (`/Documents/...`, a save answered `302`), the upload zones'
/// tree and dispatcher command `saveuploadmap`, and the news' management
/// list, news page and form (`?module=News`). The upload form's
/// `randomDir` is opened in [uploads] for the session that loaded it.
class FakeCourses {
  FakeCourses({required this.uploads});

  final FakeUploads uploads;

  static const platform = 6161;

  final List<FakeCourse> courses = [];

  /// The writes, as `METHOD path` with their fields.
  final List<(String, Map<String, String>)> writes = [];

  /// Whether a save is answered without changing anything.
  bool ignoreWrites = false;

  int _next = 900700;
  int _forms = 0;

  FakeCourse? _course(String? id) =>
      courses.where((c) => '${c.id}' == id).firstOrNull;

  /// Answers [options] if it is a request of the course modules.
  ResponseBody? respond(RequestOptions options) {
    final uri = options.uri;
    final path = uri.path;
    final query = uri.queryParameters;
    final fields = options.data is Map
        ? (options.data as Map).map((k, v) => MapEntry('$k', '$v'))
        : <String, String>{};

    if (path == '/Topnav/getCourseConfig') return _html(_menu());

    final documents = RegExp(
      r'^/Documents/(Admin/Index|Map/Save|Multiupload/Index|Multiupload/Save)'
      r'/courseID/(\d+)(?:/parentID/(\d+))?/ssID/6161$',
    ).firstMatch(path);
    if (documents != null) {
      final course = _course(documents[2]);
      if (course == null) return _html('<html>Geen toegang</html>');
      final parent = int.tryParse(documents[3] ?? '');
      switch (documents[1]) {
        case 'Admin/Index':
          final items = course.folders[parent];
          return _html(
            items == null ? '<html>Geen toegang</html>' : _documents(items),
          );
        case 'Map/Save':
          return _write(path, fields, () {
            final folder = FakeCourseDocument(
              _next++,
              fields['name']!,
              folder: true,
              visible: fields['visible'] == '1',
              from: fields['fromdatecheck'] == '1' ? fields['fromdate'] : null,
              until: fields['untildatecheck'] == '1'
                  ? fields['untildate']
                  : null,
            );
            course.folders[int.parse(fields['parentID']!)]!.add(folder);
            course.folders[folder.id] = [];
          });
        case 'Multiupload/Index':
          final dir = 'courseDir${++_forms}';
          uploads.openDirectory(dir, session: sessionOf(options));
          return _html(
            '<form><input type="hidden" name="randomDir" value="$dir">'
            '</form>',
          );
        case 'Multiupload/Save':
          return _write(path, fields, () {
            for (final file in uploads.directories[fields['randomDir']]!) {
              course.folders[parent]!.add(
                FakeCourseDocument(
                  _next++,
                  file.name,
                  visible: fields['visible'] == '1',
                  from: fields['fromdatecheck'] == '1'
                      ? fields['fromdate']
                      : null,
                  until: fields['untildatecheck'] == '1'
                      ? fields['untildate']
                      : null,
                ),
              );
            }
          });
      }
    }

    if (path == '/' && query['module'] == 'Uploadzone') {
      final course = _course(query['courseID']);
      if (query['file'] == 'tree') return _html(_tree(course!));
      final command = fields['command'] ?? '';
      final courseId = RegExp(
        r'<param name="courseID"><!\[CDATA\[(\d+)\]\]>',
      ).firstMatch(command)?[1];
      return _write('uploadzone saveuploadmap', {'command': command}, () {
        final name = RegExp(
          r'<param name="naam"><!\[CDATA\[(.*?)\]\]>',
        ).firstMatch(command)![1]!;
        _course(courseId)!.zones.add((_next++, name));
      }, answer: '<server><response><status>ok</status></response></server>');
    }

    if (path == '/' && query['module'] == 'News') {
      final course = _course(query['courseID']);
      if (course == null) return null;
      switch (query['file']) {
        case 'coursenews_admin':
          return _html(_newsAdmin(course));
        case 'coursenews':
          return _html(_newsPage(course));
        case 'addNews':
          return _write('addNews', fields, () {
            course.news.add(
              FakeCourseNews(
                _next++,
                fields['title']!,
                fields['message']!,
                visible: fields['visible'] == '1',
              ),
            );
          });
      }
    }
    return null;
  }

  ResponseBody _write(
    String what,
    Map<String, String> fields,
    void Function() apply, {
    String? answer,
  }) {
    writes.add((what, fields));
    if (!ignoreWrites) apply();
    return answer != null
        ? _html(answer)
        : ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['/Documents/Admin/Index'],
            },
          );
  }

  String _menu() {
    String list(String kind) => courses
        .where((c) => c.kind == kind)
        .map(
          (c) =>
              '{"id":${c.id},"platformId":$platform,"name":"${c.name}",'
              '"descr":"${c.description}","teacher":"Leerkracht"}',
        )
        .join(',');
    return '{"own":[${list('own')}],"titu":[${list('titu')}],'
        '"community":[${list('community')}]}';
  }

  static String _visible(int id, bool visible) =>
      '<div class="ico ${visible ? 'visible' : 'not_visible'}" '
      'id="visibleImg$id"></div>';

  String _documents(List<FakeCourseDocument> items) {
    final rows = items.map((d) {
      final href = d.folder
          ? '/Documents/Admin/Index/courseID/1/parentID/${d.id}/ssID/6161'
          : '/Documents/Download/Index/htm/0/courseID/1/docID/${d.id}/ssID/6161';
      return '<li itemID="${d.id}"><div class="name">'
          '<a class="smsc_cm_link" href="$href">${d.name}</a></div>'
          '${_visible(d.id, d.visible)}'
          '<div class="until"> ${d.until ?? '-'} </div>'
          '<div class="from"> ${d.from ?? '-'} </div></li>';
    }).join();
    return '<html><body><ul id="list">$rows</ul></body></html>';
  }

  String _tree(FakeCourse course) =>
      '[{"attributes":{"id":"tree_0","rel":"tree"},"data":{"title":'
      '"Uploadzone"},"children":[${course.zones.map((z) => '{"attributes":'
          '{"id":"uploadmap_${z.$1}","rel":"uploadmap"},"data":{"title":'
          '"${z.$2}"}}').join(',')}]}]';

  String _newsAdmin(FakeCourse course) =>
      '<html><body><ul id="list">${course.news.map((n) => '<li itemID="${n.id}">'
          '<div class="name tekst" title="${n.title}">${n.title}</div>'
          '${_visible(n.id, n.visible)}<div class="until">-</div>'
          '<div class="from">-</div></li>').join()}</ul></body></html>';

  String _newsPage(FakeCourse course) =>
      '<html><body>${course.news.where((n) => n.visible).map((n) => '<div class="smsc_cm_body_row">'
          '<div class="smsc_quick_edit" onclick="window.location=\'/?module=News&file=addNews&newsID=${n.id}\';"></div>'
          '<div class="smsc_cm_body_row_block_desc">${n.html}</div></div>').join()}'
      '</body></html>';

  static ResponseBody _html(String body) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
    },
  );
}
