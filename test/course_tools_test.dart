/// The course tools (dartschool's `CourseService`): `list_courses`,
/// `list_course_documents`, `create_course_folder`,
/// `upload_course_documents`, `list_upload_zones`, `create_upload_zone`,
/// `list_course_news` and `post_course_news`, called over MCP on the real
/// server, session and library, against the fake Smartschool's course
/// modules (`test/support/fake_courses.dart`). Made-up courses and items.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/create_course_folder_tool.dart';
import 'package:smartschool_mcp/src/tools/create_upload_zone_tool.dart';
import 'package:smartschool_mcp/src/tools/list_course_documents_tool.dart';
import 'package:smartschool_mcp/src/tools/list_course_news_tool.dart';
import 'package:smartschool_mcp/src/tools/list_courses_tool.dart';
import 'package:smartschool_mcp/src/tools/list_upload_zones_tool.dart';
import 'package:smartschool_mcp/src/tools/post_course_news_tool.dart';
import 'package:smartschool_mcp/src/tools/upload_course_documents_tool.dart';
import 'package:test/test.dart';

import 'support/fake_courses.dart';
import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

void main() {
  late FakeSmartschool server;
  late FakeCourses fake;
  late SmartschoolSession session;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    fake = server.courses;
    fake.courses.addAll([
      FakeCourse(813, 'testvak')
        ..folders[0]!.addAll([
          FakeCourseDocument(900001, 'Hoofdstuk 1', folder: true),
          FakeCourseDocument(
            900002,
            'les1.pdf',
            visible: false,
            from: '2026-12-01 08:00',
          ),
        ])
        ..folders[900001] = []
        ..zones.add((900010, 'Taak 1'))
        ..news.addAll([
          FakeCourseNews(
            900020,
            'Welkom',
            '<p>Hallo <strong>allen</strong></p>',
          ),
          FakeCourseNews(900021, 'Verborgen', '<p>x</p>', visible: false),
        ]),
      FakeCourse(731, '5 Wiskunde', description: '5A'),
      FakeCourse(733, '5 Wiskunde', description: '5B'),
      FakeCourse(900, 'Klas 6C', kind: 'titu'),
    ]);
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listCoursesTool(session),
        listCourseDocumentsTool(session),
        createCourseFolderTool(session),
        uploadCourseDocumentsTool(session),
        listUploadZonesTool(session),
        createUploadZoneTool(session),
        listCourseNewsTool(session),
        postCourseNewsTool(session),
      ],
    );
  });

  Future<String> ok(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  test('the reads only read, the writes are not idempotent', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    for (final name in [
      'list_courses',
      'list_course_documents',
      'list_upload_zones',
      'list_course_news',
    ]) {
      expect(tools[name]!.toolAnnotations!.readOnlyHint, isTrue, reason: name);
    }
    for (final name in [
      'create_course_folder',
      'upload_course_documents',
      'create_upload_zone',
      'post_course_news',
    ]) {
      final annotations = tools[name]!.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse, reason: name);
      expect(annotations.idempotentHint, isFalse, reason: name);
      expect(
        tools[name]!.description,
        contains('explicitly confirmed'),
        reason: name,
      );
    }
  });

  test('list_courses lists the courses by group, with their ids', () async {
    expect(
      await ok('list_courses'),
      'Own courses:\n'
      '- testvak (course 813)\n'
      '- 5 Wiskunde (course 731) | 5A\n'
      '- 5 Wiskunde (course 733) | 5B\n'
      'Courses of the classes of which the user is the titular:\n'
      '- Klas 6C (course 900)',
    );
  });

  test('a course is found by id or by a name only one course has; another '
      'is refused with the courses', () async {
    expect(
      await ok('list_course_documents', {'course': 'TESTVAK'}),
      startsWith('In the top of the documents of testvak (course 813):'),
    );
    expect(
      await ok('list_course_documents', {'course': '731'}),
      'Nothing is in the top of the documents of 5 Wiskunde (course 731) | '
      '5A.',
    );
    expect(
      await error('list_course_documents', {'course': '5 wiskunde'}),
      'Several courses are named "5 wiskunde": 5 Wiskunde (course 731) | 5A; '
      '5 Wiskunde (course 733) | 5B. Pass the id of the one meant. Nothing '
      'was sent.',
    );
    expect(
      await error('list_upload_zones', {'course': 'Fysica'}),
      startsWith('No course of the user is "Fysica". The courses are: '),
    );
  });

  test('list_course_documents shows folders and files with their '
      'visibility', () async {
    expect(
      await ok('list_course_documents', {'course': '813'}),
      'In the top of the documents of testvak (course 813):\n'
      '- folder "Hoofdstuk 1" (folder id 900001) | visible to pupils\n'
      '- file "les1.pdf" (file id 900002) | hidden from pupils',
    );
  });

  test('create_course_folder makes the folder once, with its dates', () async {
    final text = await ok('create_course_folder', {
      'course': '813',
      'name': 'Hoofdstuk 2',
      'folder_id': 900001,
      'visible_from': '2026-12-01',
      'visible_until': '2026-12-20',
    });
    expect(
      text,
      'Made the folder in the documents of testvak (course 813):\n'
      '- folder "Hoofdstuk 2" (folder id 900700) | visible to pupils from '
      '2026-12-01 00:00 until 2026-12-20 23:59',
    );
    expect(fake.writes, hasLength(1));
    expect(fake.writes.single.$2['parentID'], '900001');
  });

  test('create_course_folder refuses a bad date and a bad name before '
      'anything is sent', () async {
    expect(
      await error('create_course_folder', {
        'course': '813',
        'name': 'X',
        'visible_from': '1 december',
      }),
      contains('visible_from must be a date like 2026-12-01'),
    );
    expect(
      await error('create_course_folder', {'course': '813', 'name': 'a/b'}),
      allOf(contains('was refused before it was sent'), contains('Nothing')),
    );
    expect(fake.writes, isEmpty);
  });

  test('a write Smartschool does not confirm is reported as maybe '
      'made', () async {
    fake.ignoreWrites = true;
    expect(
      await error('post_course_news', {
        'course': '813',
        'title': 'Toets',
        'message': 'Vrijdag',
      }),
      contains('may or may not have been made. Do not call this tool again'),
    );
    expect(fake.writes, hasLength(1), reason: 'sent once');
  });

  test('upload_course_documents uploads the files in the form\'s session '
      'and saves them once', () async {
    final dir = Directory.systemTemp.createTempSync('course_tools_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}werkblad.txt')
      ..writeAsStringSync('oefening');
    final text = await ok('upload_course_documents', {
      'course': '813',
      'paths': [file.path],
      'folder_id': 900001,
      'notify': true,
    });
    expect(
      text,
      'Uploaded 1 file to folder 900001 of the documents of testvak (course '
      '813), with a notification to the pupils:\n'
      '- file "werkblad.txt" (file id 900700) | visible to pupils',
    );
    expect(fake.writes.single.$2['sendNotification'], '1');
  });

  test('list_upload_zones and create_upload_zone', () async {
    expect(
      await ok('list_upload_zones', {'course': '813'}),
      'The upload zones of testvak (course 813):\n'
      '- "Taak 1" (upload zone 900010)',
    );
    expect(
      await error('create_upload_zone', {
        'course': '813',
        'name': 'Taak 2',
        'open_from': '2026-12-01',
      }),
      contains('Give both open_from and open_until'),
    );
    expect(
      await ok('create_upload_zone', {
        'course': '813',
        'name': 'Taak 2',
        'open_from': '2026-12-01 08:00',
        'open_until': '2026-12-15',
        'max_files': 1,
      }),
      'Made the upload zone "Taak 2" (upload zone 900700) in testvak (course '
      '813): pupils can upload from 2026-12-01 08:00 until 2026-12-15 23:59.',
    );
    final command = fake.writes.single.$2['command']!;
    expect(command, contains('<param name="aantal"><![CDATA[1]]></param>'));
    expect(command, contains('<param name="tijd"><![CDATA[1]]></param>'));
  });

  test('list_course_news shows the messages with their formatting, and '
      'post_course_news writes the formatting as HTML', () async {
    expect(
      await ok('list_course_news', {'course': '813'}),
      'The news of testvak (course 813):\n'
      '- "Welkom" (news id 900020) | visible to pupils\n'
      '  Hallo **allen**\n'
      '- "Verborgen" (news id 900021) | hidden from pupils\n'
      '  (the message is not shown: pupils do not see the item)',
    );
    final text = await ok('post_course_news', {
      'course': '813',
      'title': 'Toets',
      'message': 'De toets is **vrijdag**.\n\n- {red}hoofdstuk 3{/}',
    });
    expect(
      fake.writes.single.$2['message'],
      '<p>De toets is <strong>vrijdag</strong>.</p>'
      '<ul><li><span style="color:#e03e2d;">hoofdstuk 3</span></li></ul>',
    );
    expect(fake.writes.single.$2['visible'], '1');
    expect(
      text,
      'Posted the news item in testvak (course 813):\n'
      '- "Toets" (news id 900700) | visible to pupils\n'
      '  De toets is **vrijdag**.\n'
      '  \n'
      '  - {red}hoofdstuk 3{/}',
    );
  });
}
