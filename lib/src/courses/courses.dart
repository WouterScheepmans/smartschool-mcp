import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/html_to_text.dart';
import '../session.dart';
import '../tools/server_tool.dart';

// The management of a course ("vak") by its teacher: the courses of the
// course menu, and per course its documents, upload zones and news, read
// and written with the library's `CourseService`.
//
// The tools name a course by its id, as list_courses shows it in
// `(course <id>)`, or by its name when no other course of the menu has it;
// a course the menu does not have, or a name several courses have, is
// refused with the courses there are ([findCourse]), before anything is
// sent.

/// Runs the read [action] with the session's logged-in client and a
/// [CourseService] of it: the library's [SmartschoolCourseError] becomes a
/// [ToolError]; login and connection failures stay [SmartschoolProblem]s.
Future<T> withCourses<T>(
  SmartschoolSession session,
  Future<T> Function(CourseService courses) action,
) async {
  try {
    return await session.run(
      (client) => action(CourseService(client)),
      describeError: _describe,
    );
  } on SmartschoolCourseError catch (error) {
    throw ToolError(
      'Smartschool answered with something the server cannot read: '
      '${error.message}',
    );
  }
}

/// Runs the write [action] with the session's logged-in client and a
/// [CourseService] of it; [what] names the write (like `the folder
/// "Hoofdstuk 1"`).
///
/// An [ArgumentError] of the library (it refused the write before sending
/// it) and a [SmartschoolCourseError] (a read before the write) become
/// [ToolError]s that say nothing was sent; a
/// [SmartschoolCourseWriteUnconfirmedError] (the write went out, and may or
/// may not have been made) becomes a [ToolError] that says to check the
/// list with [checkWith] before trying again. The library sends a write
/// once, never again after logging in: [SmartschoolSession.run] may run
/// [action] again after Smartschool refused the session, with its reads.
Future<T> withCourseWrite<T>(
  SmartschoolSession session,
  Future<T> Function(CourseService courses) action, {
  required String what,
  required String checkWith,
}) async {
  try {
    return await session.run(
      (client) => action(CourseService(client)),
      describeError: _describe,
    );
  } on SmartschoolCourseWriteUnconfirmedError catch (error) {
    log('courses: write not confirmed (${error.runtimeType})');
    throw ToolError(
      'The save of $what went out to Smartschool, but it did not confirm '
      'it: it may or may not have been made. Do not call this tool again for '
      'it: check with $checkWith and tell the user.',
    );
  } on ToolError {
    rethrow;
  } on ArgumentError catch (error) {
    if (error is RangeError) rethrow;
    throw ToolError(
      '${_capital(what)} was refused before it was sent: '
      '${error.message}. Nothing was sent.',
    );
  } on SmartschoolAttachmentUploadError catch (error) {
    throw ToolError(
      'The upload for $what failed, so nothing was saved: ${error.message}',
    );
  } on SmartschoolCourseError catch (error) {
    throw ToolError(
      'Smartschool answered with something the server cannot read before '
      '$what was sent: ${error.message} Nothing was saved.',
    );
  }
}

String _describe(Object error) => switch (error) {
  SmartschoolCourseError() ||
  SmartschoolCourseWriteUnconfirmedError() ||
  SmartschoolSessionExpiredError() ||
  SmartschoolConnectionError() => '$error',
  DioException(:final type) => 'DioException [$type]',
  _ => '${error.runtimeType}',
};

String _capital(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// The input schema text of the `course` argument.
const courseArgumentDescription =
    'The course, by its id as list_courses shows it (like 813), or by its '
    'name when no other course has that name.';

/// The course [value] names among [courses]: its id (`813`, or
/// `course 813`), or its name (ignoring case and extra white space) when
/// only one course has it.
///
/// Throws a [ToolError], before anything is sent, for a value that names no
/// course, or a name several courses have, listing the courses.
ManagedCourse findCourse(List<ManagedCourse> courses, Object? value) {
  final text = value is String
      ? value.trim()
      : value is num
      ? '${value.toInt()}'
      : '';
  if (text.isEmpty) {
    throw const ToolError(
      'course is required: pass a course id from list_courses.',
    );
  }
  final id = int.tryParse(
    text.replaceFirst(RegExp(r'^course\s+', caseSensitive: false), ''),
  );
  if (id != null) {
    final byId = courses.where((c) => c.id == id).firstOrNull;
    if (byId != null) return byId;
  }
  String normal(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final byName = courses.where((c) => normal(c.name) == normal(text)).toList();
  if (byName.length == 1) return byName.single;
  if (byName.length > 1) {
    throw ToolError(
      'Several courses are named "$text": '
      '${byName.map(formatCourse).join('; ')}. Pass the id of the one meant. '
      'Nothing was sent.',
    );
  }
  throw ToolError(
    'No course of the user is "$text". The courses are: '
    '${courses.map(formatCourse).join('; ')}. Nothing was sent.',
  );
}

/// A course as the tools name it: `testvak (course 813) | 5A`.
String formatCourse(ManagedCourse course) => [
  '${course.name} (course ${course.id})',
  if (course.description.isNotEmpty) course.description,
].join(' | ');

/// [value], the date argument [name]: `YYYY-MM-DD` (from 00:00) or
/// `YYYY-MM-DD HH:MM`, in the user's local time; `null` when absent or
/// empty. With [endOfDay], a day without a time is until 23:59 of it.
///
/// Throws a [ToolError], before anything is sent, for another value.
DateTime? courseDateArgument(
  Map<String, Object?> arguments,
  String name, {
  bool endOfDay = false,
}) {
  final value = arguments[name];
  if (value == null || (value is String && value.trim().isEmpty)) return null;
  final match = value is String
      ? RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?$',
        ).firstMatch(value.trim())
      : null;
  if (match == null) {
    throw ToolError(
      '$name must be a date like 2026-12-01, or a date and time like '
      '2026-12-01 08:30. Nothing was sent.',
    );
  }
  int part(int i) => int.parse(match[i]!);
  final hasTime = match[4] != null;
  final date = DateTime(
    part(1),
    part(2),
    part(3),
    hasTime ? part(4) : (endOfDay ? 23 : 0),
    hasTime ? part(5) : (endOfDay ? 59 : 0),
  );
  if (date.month != part(2) || date.day != part(3)) {
    throw ToolError('$name is not a valid date. Nothing was sent.');
  }
  return date;
}

/// [date] as the tools show it: `2026-12-01 08:30`.
String formatCourseDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

/// When pupils see an item, from the list's dates and visibility.
String formatCourseVisibility({bool? visible, String? from, String? until}) {
  final window = [
    if (from != null) 'from $from',
    if (until != null) 'until $until',
  ].join(' ');
  return switch (visible) {
    false => 'hidden from pupils',
    _ when window.isNotEmpty => 'visible to pupils $window',
    true => 'visible to pupils',
    null => window.isEmpty ? 'visibility not shown' : 'pupils see it $window',
  };
}

/// A document of a course as the tools show it.
String formatCourseDocument(CourseDocument document) {
  final kind = switch (document.kind) {
    CourseDocumentKind.folder => 'folder',
    CourseDocumentKind.file => 'file',
    CourseDocumentKind.other => 'item',
  };
  return '- $kind "${document.name}" ($kind id ${document.id}) | '
      '${formatCourseVisibility(visible: document.isVisible, from: document.visibleFrom, until: document.visibleUntil)}';
}

/// A news item as the tools show it, with its message as text with its
/// formatting.
String formatCourseNews(CourseNewsItem item) {
  final message = item.html == null
      ? '(the message is not shown: pupils do not see the item)'
      : htmlToText(item.html!, markup: true).trim();
  return [
    '- "${item.title}" (news id ${item.id}) | '
        '${formatCourseVisibility(visible: item.isVisible, from: item.visibleFrom, until: item.visibleUntil)}',
    for (final line in (message.isEmpty ? '(empty)' : message).split('\n'))
      '  $line',
  ].join('\n');
}
