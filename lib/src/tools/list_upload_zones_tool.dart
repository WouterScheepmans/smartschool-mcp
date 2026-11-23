import 'package:dart_mcp/server.dart';

import '../courses/courses.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_upload_zones`: the upload zones of a course
/// (`CourseService.getUploadZones`). Only reads.
ServerTool listUploadZonesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_upload_zones',
    title: 'List the upload zones of a Smartschool course',
    description:
        'Lists the upload zones ("Uploadzone") of one of the user\'s courses: '
        'the folders pupils upload their work into, each with its id and the '
        'folders of the module it is in. Give the course id from '
        'list_courses. Listing changes nothing; what pupils uploaded is not '
        'read. For requests like "welke uploadzones heeft testvak?".',
    inputSchema: Schema.object(
      properties: {
        'course': Schema.string(description: courseArgumentDescription),
      },
      required: ['course'],
    ),
    annotations: ToolAnnotations(
      title: 'List the upload zones of a Smartschool course',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final arguments = request.arguments ?? const {};
    final (course, zones) = await withCourses(session, (courses) async {
      final course = findCourse(
        await courses.getCourses(),
        arguments['course'],
      );
      return (course, await courses.getUploadZones(course));
    });
    return CallToolResult(
      content: [
        TextContent(
          text: [
            zones.isEmpty
                ? '${formatCourse(course)} has no upload zones.'
                : 'The upload zones of ${formatCourse(course)}:',
            for (final zone in zones)
              '- "${zone.name}" (upload zone ${zone.id})'
                  '${zone.path.isEmpty ? '' : ' | in ${zone.path.join(' > ')}'}',
          ].join('\n'),
        ),
      ],
    );
  },
);
