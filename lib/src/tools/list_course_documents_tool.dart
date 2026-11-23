import 'package:dart_mcp/server.dart';

import '../courses/courses.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `list_course_documents`: the items of a folder of a course's documents
/// (`CourseService.getDocuments`). Only reads.
ServerTool listCourseDocumentsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_course_documents',
    title: 'List the documents of a Smartschool course',
    description:
        'Lists the folders and files of the documents ("Documenten") of one '
        'of the user\'s courses, the top or one folder, each with its id and '
        'whether pupils see it (from and until when, if set). Give the '
        'course id from list_courses, and folder_id to list a folder (its '
        'id as this tool shows it). Listing changes nothing. For requests '
        'like "welke documenten staan er bij testvak?".',
    inputSchema: Schema.object(
      properties: {
        'course': Schema.string(description: courseArgumentDescription),
        'folder_id': Schema.int(
          description:
              'The id of the folder to list, as this tool shows it. Default: '
              'the top of the documents.',
          minimum: 0,
        ),
      },
      required: ['course'],
    ),
    annotations: ToolAnnotations(
      title: 'List the documents of a Smartschool course',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final arguments = request.arguments ?? const {};
    final folderId = intArgument(arguments, 'folder_id') ?? 0;
    final (course, documents) = await withCourses(session, (courses) async {
      final course = findCourse(
        await courses.getCourses(),
        arguments['course'],
      );
      return (course, await courses.getDocuments(course, folderId: folderId));
    });
    final where = folderId == 0
        ? 'the top of the documents'
        : 'folder $folderId of the documents';
    return CallToolResult(
      content: [
        TextContent(
          text: [
            '${documents.isEmpty ? 'Nothing is in' : 'In'} $where of '
                '${formatCourse(course)}${documents.isEmpty ? '.' : ':'}',
            for (final document in documents) formatCourseDocument(document),
          ].join('\n'),
        ),
      ],
    );
  },
);
