import 'package:dart_mcp/server.dart';

import '../courses/courses.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_course_news`: the news items of a course
/// (`CourseService.getNews`). Only reads.
ServerTool listCourseNewsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_course_news',
    title: 'List the news of a Smartschool course',
    description:
        'Lists the news items ("Vaknieuws") of one of the user\'s courses, '
        'each with its id, whether pupils see it, and its message as text in '
        'the formatting post_course_news takes (bold, italic, colours, '
        'lists). Give the course id from list_courses. Listing changes '
        'nothing. For requests like "wat staat er in het vaknieuws van '
        'testvak?".',
    inputSchema: Schema.object(
      properties: {
        'course': Schema.string(description: courseArgumentDescription),
      },
      required: ['course'],
    ),
    annotations: ToolAnnotations(
      title: 'List the news of a Smartschool course',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final arguments = request.arguments ?? const {};
    final (course, news) = await withCourses(session, (courses) async {
      final course = findCourse(
        await courses.getCourses(),
        arguments['course'],
      );
      return (course, await courses.getNews(course));
    });
    return CallToolResult(
      content: [
        TextContent(
          text: [
            news.isEmpty
                ? '${formatCourse(course)} has no news items.'
                : 'The news of ${formatCourse(course)}:',
            for (final item in news) formatCourseNews(item),
          ].join('\n'),
        ),
      ],
    );
  },
);
