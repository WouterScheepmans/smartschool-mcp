import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../courses/courses.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_courses`: the courses of the course menu in Smartschool's top bar
/// (`CourseService.getCourses`), which the other
/// course tools take by their id. Only reads.
ServerTool listCoursesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_courses',
    title: 'List the Smartschool courses',
    description:
        'Lists the user\'s courses ("vakken") of the course menu in '
        'Smartschool\'s top bar, each as "name (course <id>) | description" '
        '(the description is often its classes), grouped as the menu groups '
        'them: own courses, courses of the classes the user is the titular '
        'of, and courses of the school community. Pass the id to '
        'list_course_documents, create_course_folder, '
        'upload_course_documents, list_upload_zones, create_upload_zone, '
        'list_course_news and post_course_news. Several courses can have the '
        'same name (one per group of classes): use the id. Listing changes '
        'nothing. For requests like "welke vakken heb ik?" or "zet dit '
        'bestand bij de documenten van 5 Wiskunde".',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(
      title: 'List the Smartschool courses',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final courses = await withCourses(session, (c) => c.getCourses());
    return CallToolResult(content: [TextContent(text: formatCourses(courses))]);
  },
);

/// [courses] as `list_courses` shows them, by kind.
String formatCourses(List<ManagedCourse> courses) {
  if (courses.isEmpty) return 'The course menu has no courses.';
  const titles = {
    ManagedCourseKind.own: 'Own courses',
    ManagedCourseKind.titular:
        'Courses of the classes of which the user is '
        'the titular',
    ManagedCourseKind.community: 'Courses of the school community',
  };
  return [
    for (final kind in ManagedCourseKind.values)
      if (courses.where((c) => c.kind == kind).toList() case final list
          when list.isNotEmpty) ...[
        '${titles[kind]}:',
        for (final course in list) '- ${formatCourse(course)}',
      ],
  ].join('\n');
}
