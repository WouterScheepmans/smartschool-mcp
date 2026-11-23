import 'package:dart_mcp/server.dart';

import '../courses/courses.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `create_upload_zone`: makes an upload zone in a course
/// (`CourseService.createUploadZone`), sent once.
ServerTool createUploadZoneTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'create_upload_zone',
    title: 'Make an upload zone in a Smartschool course',
    description:
        'Makes an upload zone ("Uploadzone") in one of the user\'s courses: a '
        'folder the pupils of the course upload their work into, at the top '
        'of the module. By default pupils can upload at any time, see and '
        'read only their own files, and see the zone. open_from and '
        'open_until (both or neither) limit when they can upload; max_files '
        'limits how many files a pupil uploads; classmates_see lets pupils '
        'see who uploaded what, classmates_read read it; visible false hides '
        'the zone. Before calling this tool, show the user the course, the '
        'name, the description and these settings, and only call it after '
        'the user has explicitly confirmed it; then call it once. If the '
        'result says it may or may not have been made, do not call this tool '
        'again: check with list_upload_zones and tell the user. For requests '
        'like "maak een uploadzone Taak 1 voor testvak tot vrijdag".',
    inputSchema: Schema.object(
      properties: {
        'course': Schema.string(description: courseArgumentDescription),
        'name': Schema.string(
          description: 'The name of the upload zone, as the user confirmed it.',
          minLength: 1,
        ),
        'description': Schema.string(
          description: 'What pupils read with it. Default: none.',
        ),
        'open_from': Schema.string(
          description:
              'From when pupils can upload: 2026-12-01 or 2026-12-01 08:30. '
              'Only with open_until. Default: always.',
        ),
        'open_until': Schema.string(
          description:
              'Until when pupils can upload: 2026-12-20 (the end of that '
              'day) or 2026-12-20 16:00. Only with open_from. Default: '
              'always.',
        ),
        'max_files': Schema.int(
          description: 'The most files a pupil uploads. Default: no limit.',
          minimum: 1,
        ),
        'visible': Schema.bool(
          description: 'Whether pupils see the zone. Default: true.',
        ),
        'classmates_see': Schema.bool(
          description:
              'Whether pupils see the files of their classmates. Default: '
              'false.',
        ),
        'classmates_read': Schema.bool(
          description:
              'Whether pupils can open the files of their classmates. '
              'Default: false.',
        ),
      },
      required: ['course', 'name'],
    ),
    annotations: ToolAnnotations(
      title: 'Make an upload zone in a Smartschool course',
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final arguments = request.arguments ?? const {};
    final name = (arguments['name'] as String? ?? '').trim();
    if (name.isEmpty) {
      throw const ToolError('name is empty. Nothing was sent.');
    }
    final from = courseDateArgument(arguments, 'open_from');
    final until = courseDateArgument(arguments, 'open_until', endOfDay: true);
    if ((from == null) != (until == null)) {
      throw const ToolError(
        'Give both open_from and open_until, or neither (then pupils can '
        'always upload). Nothing was sent.',
      );
    }
    final (course, zone) = await withCourseWrite(
      session,
      (courses) async {
        final course = findCourse(
          await courses.getCourses(),
          arguments['course'],
        );
        final zone = await courses.createUploadZone(
          course,
          name: name,
          description: arguments['description'] as String? ?? '',
          visibleFrom: from,
          visibleUntil: until,
          maxFiles: intArgument(arguments, 'max_files'),
          visible: arguments['visible'] as bool? ?? true,
          classmatesSee: arguments['classmates_see'] as bool? ?? false,
          classmatesRead: arguments['classmates_read'] as bool? ?? false,
        );
        return (course, zone);
      },
      what: 'the upload zone "$name"',
      checkWith: 'list_upload_zones',
    );
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Made the upload zone "${zone.name}" (upload zone ${zone.id}) '
              'in ${formatCourse(course)}: pupils can upload '
              '${from == null ? 'at any time' : 'from ${formatCourseDate(from)} until ${formatCourseDate(until!)}'}.',
        ),
      ],
    );
  },
);
