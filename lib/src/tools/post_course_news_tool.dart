import 'package:dart_mcp/server.dart';

import '../courses/courses.dart';
import '../messages/markdown_to_html.dart';
import '../session.dart';
import 'server_tool.dart';

/// `post_course_news`: posts a news item in a course
/// (`CourseService.postNews`), sent once. The
/// message is written as the Markdown of an info (`infoMarkdownToHtml`).
ServerTool postCourseNewsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'post_course_news',
    title: 'Post news in a Smartschool course',
    description:
        'Posts a news item ("Vaknieuws") in one of the user\'s courses: the '
        'pupils of the course see its title and message on the course\'s '
        'news page, unless visible is false; notify true also sends them a '
        'notification ("Opslaan en melden"). Write the message as plain text '
        'or simple Markdown: a blank line between paragraphs; lines starting '
        'with "- " or "1. " for a list; **bold**, *italic*, ++underlined++; '
        '{red}text{/} or {#1a7f37}text{/} for coloured text (red, dark red, '
        'orange, yellow, green, dark green, blue, dark blue, purple, dark '
        'purple, gray, dark gray, black, or a hex code); [text](https://...) '
        'for a link. HTML in it is not interpreted. Before calling this '
        'tool, show the user the course, the title, the message and whether '
        'pupils see it and get a notification, and only call it after the '
        'user has explicitly confirmed it; then call it once. If the result '
        'says it may or may not have been posted, do not call this tool '
        'again: check with list_course_news and tell the user. For requests '
        'like "zet in het vaknieuws van testvak dat de toets verschoven is".',
    inputSchema: Schema.object(
      properties: {
        'course': Schema.string(description: courseArgumentDescription),
        'title': Schema.string(
          description: 'The title, as the user confirmed it.',
          minLength: 1,
        ),
        'message': Schema.string(
          description:
              'The message, in the formatting the tool description gives.',
          minLength: 1,
        ),
        'visible': Schema.bool(
          description: 'Whether pupils see it. Default: true.',
        ),
        'notify': Schema.bool(
          description:
              'Whether pupils get a notification, as "Opslaan en melden" '
              'sends. Default: false.',
        ),
      },
      required: ['course', 'title', 'message'],
    ),
    annotations: ToolAnnotations(
      title: 'Post news in a Smartschool course',
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final arguments = request.arguments ?? const {};
    final title = (arguments['title'] as String? ?? '').trim();
    final html = infoMarkdownToHtml(arguments['message'] as String? ?? '');
    if (title.isEmpty || html.isEmpty) {
      throw const ToolError(
        'title and message must not be empty. Nothing was sent.',
      );
    }
    final notify = arguments['notify'] as bool? ?? false;
    final (course, item) = await withCourseWrite(
      session,
      (courses) async {
        final course = findCourse(
          await courses.getCourses(),
          arguments['course'],
        );
        final item = await courses.postNews(
          course,
          title: title,
          html: html,
          visible: arguments['visible'] as bool? ?? true,
          notify: notify,
        );
        return (course, item);
      },
      what: 'the news item "$title"',
      checkWith: 'list_course_news',
    );
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Posted the news item in ${formatCourse(course)}'
              '${notify ? ', with a notification to the pupils' : ''}:\n'
              '${formatCourseNews(item)}',
        ),
      ],
    );
  },
);
