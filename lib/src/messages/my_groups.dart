import 'package:dart_mcp/server.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../tools/server_tool.dart';

// The user's own mail groups (#231): "Mijn groepen" in the Smartschool
// profile, each a group of people the user keeps, which the search of the
// compose form finds by name, as a group, so that a message to one goes to
// all its members. Read with the library's `MyGroupsService`
// (flutter_smartschool 0.4.6, yvanvds/dartschool#251). Shared by
// `list_my_groups` and `read_my_group`, and by the writes that follow
// (#232: make, rename and delete a group; #233: its members).
//
// The tools name a group by its id, as `list_my_groups` shows it in
// `(group <id>)`: the id the compose search gives the group, so that a line
// of `list_my_groups` goes into `send_message` as a line of
// `search_recipients` does. A group the list of own groups does not have is
// refused with the groups there are ([unknownMyGroup]), before anything is
// sent.
//
// The members of a group are mostly pupils: the log never names a group or
// a member, only ids and error types.

/// Runs [action] with the session's logged-in client and a
/// [MyGroupsService] of it, for the tools of the own mail groups: the
/// errors of the service become [ToolError]s ([myGroupsToolError]); login
/// and connection failures stay [SmartschoolProblem]s.
///
/// The action may run more than once ([SmartschoolSession.run]): the reads
/// are safe to repeat.
Future<T> withMyGroups<T>(
  SmartschoolSession session,
  Future<T> Function(MyGroupsService groups, SmartschoolClient client) action,
) async {
  try {
    return await session.run(
      (client) => action(MyGroupsService(client), client),
      describeError: _describe,
    );
  } catch (error) {
    final toolError = myGroupsToolError(error);
    if (toolError == null) rethrow;
    throw toolError;
  }
}

/// [error] for the log: the library's errors of the own groups name a
/// group by its id only, and a session or connection problem names a
/// request by its path; anything else by its type only, since an answer it
/// quotes can name people.
String _describe(Object error) => switch (error) {
  SmartschoolMyGroupsError() ||
  SmartschoolMyGroupSaveUnconfirmedError() ||
  SmartschoolSessionExpiredError() ||
  SmartschoolConnectionError() => '$error',
  DioException(:final type) => 'DioException [$type]',
  _ => '${error.runtimeType}',
};

/// The [ToolError] for [error], an error of [MyGroupsService], or null for
/// anything else (a [ToolError] of the action itself, a login or connection
/// failure), which the caller passes on as it is.
///
/// - [SmartschoolMyGroupNotFoundError]: the user has no own group with that
///   id (any more). The tools check the id against the list first
///   ([findMyGroup]), so this is a group deleted meanwhile; they list the
///   groups there are themselves when they can.
/// - Any other [SmartschoolMyGroupsError]: an answer the server cannot use
///   (another status, another page, a members page and a picker selection
///   that do not list the same members). Its message names a group by its
///   id only, so it goes to the log as it is.
/// - [SmartschoolParsingError]: the member picker did not answer with XML.
///   Its message can quote the answer, so only the type goes to the log.
///
/// The picker answering with an HTML page, a
/// [SmartschoolUnexpectedPageError], is a [SmartschoolAuthenticationError]:
/// [SmartschoolSession.run] reports it as an unexpected problem, and logs
/// it as [withMyGroups] describes it, by its type.
///
/// A write that went out without Smartschool confirming it
/// ([SmartschoolMyGroupSaveUnconfirmedError], #232, #233) is not a
/// [ToolError]: the write tools report it themselves.
ToolError? myGroupsToolError(Object error) {
  switch (error) {
    case SmartschoolMyGroupNotFoundError(:final groupId):
      log('my groups: $error');
      return ToolError(
        'You have no own group with id $groupId (any more): it was deleted, '
        'or the id is wrong. List your own groups again with list_my_groups '
        'and take the id from there.',
      );
    case SmartschoolMyGroupsError(:final statusCode):
      log('my groups: $error');
      return ToolError(_unusable(statusCode));
    case SmartschoolParsingError():
      log('my groups: ${error.runtimeType}');
      return ToolError(_unusable(null));
  }
  return null;
}

String _unusable(int? statusCode) =>
    'Smartschool gave an answer about your own groups ("Mijn groepen") that '
    'the server could not use${statusCode == null ? '' : ' (HTTP $statusCode)'}. '
    'Try again in a moment. If it keeps happening, look at the groups in '
    'Smartschool itself, under "Mijn groepen" in your profile; the details '
    'are in the server log.';

/// The input schema of a tool's `group_id` argument: an own group by its
/// id from `list_my_groups`.
Schema myGroupIdSchema() => Schema.int(
  description:
      'The id of the own group, as list_my_groups shows it in '
      '"(group <id>)".',
  minimum: 1,
);

/// Where the user makes and changes their own groups in Smartschool.
const myGroupsInProfile = 'in their Smartschool profile, under "Mijn groepen"';

/// The own group of [groups] (the user's own groups,
/// [MyGroupsService.list]) with the id [id].
///
/// Throws the [ToolError] of [unknownMyGroup] when none has that id.
MyGroup findMyGroup(List<MyGroup> groups, int id) {
  for (final group in groups) {
    if (group.id == id) return group;
  }
  throw unknownMyGroup(groups, id);
}

/// The [ToolError] for the id [id], which none of the user's own groups
/// [groups] has: with those groups, each as `list_my_groups` lists it.
ToolError unknownMyGroup(List<MyGroup> groups, int id) => ToolError(
  'You have no own group with id $id (any more). Nothing was sent. '
  '${groups.isEmpty ? 'You have no own groups: the user makes them $myGroupsInProfile.' : 'Your own groups:\n${[for (final group in groups) '- ${myGroupListing(group)}'].join('\n')}'}',
);

/// [group] as `send_message` takes it, as `search_recipients` names a
/// group: its name and `(group <id>)`.
String myGroupReference(MyGroup group) =>
    '${group.name.trim()} (group ${group.id})';

/// [group] as `list_my_groups` lists it: [myGroupReference], then after a
/// `|` its description, when it has one.
String myGroupListing(MyGroup group) {
  final description = group.description.trim();
  return description.isEmpty
      ? myGroupReference(group)
      : '${myGroupReference(group)} | $description';
}

/// What `list_my_groups` answers: [groups], the user's own groups, one per
/// line in Smartschool's order (by name).
String formatMyGroups(List<MyGroup> groups) {
  if (groups.isEmpty) {
    return 'You have no own groups ("Mijn groepen"). The user makes them '
        '$myGroupsInProfile.';
  }
  final count = groups.length == 1
      ? '1 own group'
      : '${groups.length} own groups';
  return [
    'You have $count ("Mijn groepen"); a message to one goes to all its '
        'members:',
    for (final group in groups) '- ${myGroupListing(group)}',
  ].join('\n');
}

/// [member] as `read_my_group` lists it: the name as Smartschool shows it
/// (last name first) and `(user <id>)`; for a person of another school of
/// the school group (a platform other than [ownPlatform]), also the
/// platform in the brackets and their school after a `|`, as
/// `search_recipients` lists such a person.
///
/// With [ownPlatform] null (not known), every member is listed as one of
/// the own school.
String myGroupMemberLine(MyGroupMember member, {required int? ownPlatform}) {
  final name = member.name.trim();
  final otherSchool = ownPlatform != null && member.ssId != ownPlatform;
  // Not seen live (a class or a group added with the picker's tabs): said
  // as it is, never taken for a person.
  if (!member.isUser) {
    return '$name (not a person: type ${member.type}, id ${member.userId})';
  }
  if (!otherSchool) return '$name (user ${member.userId})';
  final school = member.schoolName?.trim() ?? '';
  return '$name (user ${member.userId}, platform ${member.ssId})'
      '${school.isEmpty ? '' : ' | school: $school'}';
}

/// What `read_my_group` answers: [group] with its [members], in the order
/// of its members page (by name), each as [myGroupMemberLine] gives it.
String formatMyGroupMembers(
  MyGroup group,
  List<MyGroupMember> members, {
  required int? ownPlatform,
}) {
  final header = 'Own group ${myGroupListing(group)}';
  if (members.isEmpty) {
    return '$header\nIt has no members: the user adds people '
        '$myGroupsInProfile.';
  }
  final count = members.length == 1 ? '1 member' : '${members.length} members';
  return [
    '$header\n$count:',
    for (final member in members)
      '- ${myGroupMemberLine(member, ownPlatform: ownPlatform)}',
  ].join('\n');
}

/// The platform (`ssID`) of the user's own school, as the compose form of
/// Messages gives it ([MessagesService.getCurrentUserAsRecipient]): the
/// one the library compares a person's platform with to tell a person of
/// another school of the school group ([MessageSearchUser.otherSchool],
/// yvanvds/dartschool#246). Loads a compose form and leaves it unused, as
/// the recipient search does.
///
/// Null when Smartschool does not open its compose form to the account
/// (a [SmartschoolComposeError]): then it is not known.
Future<int?> ownPlatform(SmartschoolClient client) async {
  final messages = MessagesService(client);
  try {
    return (await messages.getCurrentUserAsRecipient()).ssId;
  } on SmartschoolComposeError catch (error) {
    log('my groups: own platform not known: ${error.runtimeType}');
    return null;
  } finally {
    await messages.dispose();
  }
}
