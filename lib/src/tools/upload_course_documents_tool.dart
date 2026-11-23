import 'package:dart_mcp/server.dart';

import '../courses/courses.dart';
import '../intradesk/intradesk_format.dart' show formatFileSize;
import '../session.dart';
import '../uploads/local_files.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `upload_course_documents`: uploads files from this computer to a
/// course's documents (`CourseService.uploadDocuments`),
/// saved once.
ServerTool uploadCourseDocumentsTool(
  SmartschoolSession session, {
  int maxBytes = maxLocalFileBytes,
}) {
  final local = LocalPaths(session.source.platform);
  return ServerTool(
    definition: Tool(
      name: 'upload_course_documents',
      title: 'Upload files to the documents of a Smartschool course',
      description:
          'Uploads 1 to $maxLocalFiles files from ${local.computer} to the '
          'documents ("Documenten") of one of the user\'s courses, at the top '
          'or in a folder (folder_id, as list_course_documents or '
          'create_course_folder shows it), each under its own file name. '
          'Pupils of the course see them unless visible is false, and only '
          'from visible_from and until visible_until when those are given; '
          'notify true also sends them a notification ("Opslaan en melden"). '
          'Give the full paths of the files, like ${local.example()}: files '
          'you made for the user or that the user names. The server reads '
          'any file ${local.readableBy} can read, up to '
          '${formatFileSize(maxBytes)} each. Before calling this tool, show '
          'the user every file with its name and size, the course and folder '
          'it goes to, when pupils see it and whether they get a '
          'notification, and only call it after the user has explicitly '
          'confirmed it; then call it once. If the result says the files may '
          'or may not have been saved, do not call this tool again for them: '
          'check with list_course_documents and tell the user. For requests '
          'like "zet dit werkblad bij de documenten van 5 Wiskunde".',
      inputSchema: Schema.object(
        properties: {
          'course': Schema.string(description: courseArgumentDescription),
          'paths': Schema.list(
            description:
                'The full paths of the files on ${local.computer}, like '
                '${local.example()}. Each goes in under its own name.',
            items: Schema.string(minLength: 1),
            minItems: 1,
            maxItems: maxLocalFiles,
          ),
          'folder_id': Schema.int(
            description:
                'The id of the folder to upload to, as list_course_documents '
                'shows it. Default: the top of the documents.',
            minimum: 0,
          ),
          'visible': Schema.bool(
            description: 'Whether pupils see the files. Default: true.',
          ),
          'visible_from': Schema.string(
            description:
                'From when pupils see them: 2026-12-01 or 2026-12-01 08:30. '
                'Default: at once.',
          ),
          'visible_until': Schema.string(
            description:
                'Until when pupils see them: 2026-12-20 (the end of that day) '
                'or 2026-12-20 16:00. Default: no end.',
          ),
          'notify': Schema.bool(
            description:
                'Whether pupils get a notification of the new files, as '
                '"Opslaan en melden" sends. Default: false.',
          ),
        },
        required: ['course', 'paths'],
      ),
      annotations: ToolAnnotations(
        title: 'Upload files to the documents of a Smartschool course',
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true,
      ),
    ),
    handler: (request) async {
      final arguments = request.arguments ?? const {};
      final files = localFilesArgument(
        arguments['paths'],
        argument: 'paths',
        platform: session.source.platform,
        maxBytes: maxBytes,
      );
      final folderId = intArgument(arguments, 'folder_id') ?? 0;
      final from = courseDateArgument(arguments, 'visible_from');
      final until = courseDateArgument(
        arguments,
        'visible_until',
        endOfDay: true,
      );
      final what = files.length == 1
          ? 'the file ${describeLocalFiles(files)}'
          : 'the files ${describeLocalFiles(files)}';
      final (course, documents) = await withCourseWrite(
        session,
        (courses) async {
          final course = findCourse(
            await courses.getCourses(),
            arguments['course'],
          );
          final documents = await courses.uploadDocuments(
            course,
            [for (final file in files) file.path],
            folderId: folderId,
            visible: arguments['visible'] as bool? ?? true,
            visibleFrom: from,
            visibleUntil: until,
            notify: arguments['notify'] as bool? ?? false,
          );
          return (course, documents);
        },
        what: what,
        checkWith: 'list_course_documents',
      );
      return CallToolResult(
        content: [
          TextContent(
            text: [
              'Uploaded ${documents.length} '
                  'file${documents.length == 1 ? '' : 's'} to '
                  '${folderId == 0 ? 'the top' : 'folder $folderId'} of the '
                  'documents of ${formatCourse(course)}'
                  '${arguments['notify'] == true ? ', with a notification to the pupils' : ''}:',
              for (final document in documents) formatCourseDocument(document),
            ].join('\n'),
          ),
        ],
      );
    },
  );
}
