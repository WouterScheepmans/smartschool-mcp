import 'package:dart_mcp/server.dart';

import '../courses/courses.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `create_course_folder`: makes a folder in a course's documents
/// (`CourseService.createFolder`), sent once.
ServerTool createCourseFolderTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'create_course_folder',
    title: 'Make a folder in the documents of a Smartschool course',
    description:
        'Makes a folder in the documents ("Documenten") of one of the user\'s '
        'courses, at the top or in a folder (folder_id, as '
        'list_course_documents shows it). Pupils of the course see it unless '
        'visible is false, and only from visible_from and until '
        'visible_until when those are given. Before calling this tool, show '
        'the user the course, where the folder goes, its name and when '
        'pupils see it, and only call it after the user has explicitly '
        'confirmed it; then call it once. A name may not hold / : * ? " \\ < '
        '> | nor start or end with a dot. The result gives the folder with '
        'its id, for upload_course_documents. If the result says it may or '
        'may not have been made, do not call this tool again: check with '
        'list_course_documents and tell the user. For requests like "maak een '
        'map Hoofdstuk 3 bij de documenten van testvak".',
    inputSchema: Schema.object(
      properties: {
        'course': Schema.string(description: courseArgumentDescription),
        'name': Schema.string(
          description: 'The name of the folder, as the user confirmed it.',
          minLength: 1,
        ),
        'folder_id': Schema.int(
          description:
              'The id of the folder to make it in, as list_course_documents '
              'shows it. Default: the top of the documents.',
          minimum: 0,
        ),
        'description': Schema.string(
          description: 'A description of the folder. Default: none.',
        ),
        'visible': Schema.bool(
          description: 'Whether pupils see the folder. Default: true.',
        ),
        'visible_from': Schema.string(
          description:
              'From when pupils see it: 2026-12-01 or 2026-12-01 08:30. '
              'Default: at once.',
        ),
        'visible_until': Schema.string(
          description:
              'Until when pupils see it: 2026-12-20 (the end of that day) or '
              '2026-12-20 16:00. Default: no end.',
        ),
      },
      required: ['course', 'name'],
    ),
    annotations: ToolAnnotations(
      title: 'Make a folder in the documents of a Smartschool course',
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
    final parentId = intArgument(arguments, 'folder_id') ?? 0;
    final from = courseDateArgument(arguments, 'visible_from');
    final until = courseDateArgument(
      arguments,
      'visible_until',
      endOfDay: true,
    );
    final what = 'the folder "$name"';
    final (course, folder) = await withCourseWrite(
      session,
      (courses) async {
        final course = findCourse(
          await courses.getCourses(),
          arguments['course'],
        );
        final folder = await courses.createFolder(
          course,
          name: name,
          parentId: parentId,
          description: arguments['description'] as String? ?? '',
          visible: arguments['visible'] as bool? ?? true,
          visibleFrom: from,
          visibleUntil: until,
        );
        return (course, folder);
      },
      what: what,
      checkWith: 'list_course_documents',
    );
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Made the folder in the documents of ${formatCourse(course)}:\n'
              '${formatCourseDocument(folder)}',
        ),
      ],
    );
  },
);
