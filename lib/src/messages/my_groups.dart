import 'package:dart_mcp/server.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:html/parser.dart' as html_parser;

import '../log.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import 'recipient_search.dart';

// The user's own mail groups (#231): "Mijn groepen" in the Smartschool
// profile, each a group of people the user keeps, which the search of the
// compose form finds by name, as a group, so that a message to one goes to
// all its members. Read with the library's `MyGroupsService`
// (flutter_smartschool 0.4.6, yvanvds/dartschool#251). Shared by
// `list_my_groups` and `read_my_group`, by the writes of the groups
// themselves (#232, dartschool#252: `create_my_group`, `edit_my_group`,
// `delete_my_group`, [withMyGroupWrite]), and by those of their members
// (#233, dartschool#253: `add_my_group_members`, `remove_my_group_members`).
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
/// [nothingDone] says what did not happen: by default that nothing was
/// sent, for a refusal before any write went out.
ToolError unknownMyGroup(
  List<MyGroup> groups,
  int id, {
  String nothingDone = myGroupNothingSent,
}) => ToolError(
  'You have no own group with id $id (any more). $nothingDone '
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
    return '$header\nIt has no members: add people with '
        'add_my_group_members.';
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

// ---------------------------------------------------------------------------
// The writes of a group (#232)
// ---------------------------------------------------------------------------

/// What a write of an own group says when it refused before sending.
const myGroupNothingSent = 'Nothing was sent.';

/// Runs the write [action] of an own group (`create_my_group`,
/// `edit_my_group`, `delete_my_group`, and those of its members, #233) with
/// the session's logged-in client and a [MyGroupsService] of it; [what]
/// names the write (like `the new own group "Reis Parijs"`) for its errors.
///
/// The library's errors before the write went out become [ToolError]s that
/// end in [nothingDone]: an [ArgumentError] (the library refused the write
/// before sending it: a blank name, or one another own group has, which
/// the tools check first themselves), and the errors of [myGroupsToolError]
/// (a read before the save that Smartschool answered with something the
/// library cannot use). A [ToolError] of [action] itself (a check before
/// sending) is thrown as it is, and so is a
/// [SmartschoolMyGroupSaveUnconfirmedError]: the write went out, and may or
/// may not have been made ([myGroupWriteNotConfirmed]). Login and
/// connection failures stay [SmartschoolProblem]s.
///
/// The library sends a save and a delete once ("Sent once" in its
/// `doc/my-groups.md`), and a change of the members too (the picker's new
/// selection and the members form, "One session, sent once"): Smartschool
/// refusing the session for it means it was not handled. So
/// [SmartschoolSession.run] may run [action] again, with the reads before
/// the write. The removal of a member goes out again after logging in
/// (dartschool#253): removing someone twice removes no one else.
Future<T> withMyGroupWrite<T>(
  SmartschoolSession session,
  Future<T> Function(MyGroupsService groups, SmartschoolClient client) action, {
  required String what,
  required String nothingDone,
}) async {
  try {
    return await session.run(
      (client) => action(MyGroupsService(client), client),
      describeError: _describe,
    );
  } on SmartschoolMyGroupSaveUnconfirmedError {
    rethrow;
  } on ToolError {
    rethrow;
  } on ArgumentError catch (error) {
    if (error is RangeError) rethrow;
    // Its message can quote the name: the log gets the argument's name.
    log('my groups: refused before sending (${error.name ?? 'no name'})');
    final message = '${error.message ?? ''}'.trim();
    final startsLower =
        message.isNotEmpty && message[0] != message[0].toUpperCase();
    throw ToolError(
      '${what[0].toUpperCase()}${what.substring(1)} was refused before it '
      'was sent: ${startsLower && error.name != null ? '${error.name} ' : ''}'
      '${message.endsWith('.') ? message : '$message.'} $nothingDone',
    );
  } catch (error) {
    final toolError = myGroupsToolError(error);
    if (toolError == null) rethrow;
    throw ToolError('${toolError.message} $nothingDone');
  }
}

/// [value], the `name` argument of `create_my_group` or `edit_my_group`,
/// trimmed.
///
/// Throws a [ToolError], before anything is sent, when it is empty, or has
/// no text outside its tags: Smartschool removes tags from a name, and
/// refuses an own group without a name without saying why.
String myGroupNameArgument(Object? value) {
  final name = value is String ? value.trim() : '';
  if (name.isEmpty) {
    throw const ToolError(
      'name is empty: an own group needs a name, and Smartschool refuses one '
      'without. Ask the user for a name. $myGroupNothingSent',
    );
  }
  if (myGroupTextAsListed(name).isEmpty) {
    throw ToolError(
      'name "$name" has no text outside its tags, which Smartschool removes: '
      'an own group needs a name. Ask the user for a name in plain text. '
      '$myGroupNothingSent',
    );
  }
  return name;
}

/// [value], the `description` argument of `create_my_group` or
/// `edit_my_group`, trimmed: `''` empties the description, `null` (absent)
/// leaves it as it is.
String? myGroupDescriptionArgument(Object? value) =>
    value is String ? value.trim() : null;

/// [text], a name or a description sent in a save, as the list of own
/// groups shows it after Smartschool saved it: without its tags, which
/// Smartschool strips, read as the text of HTML (the list does not escape
/// it), and trimmed. The library compares a name with the names of the
/// list so (`MyGroupsService`, "Plain text" in its `doc/my-groups.md`).
String myGroupTextAsListed(String text) =>
    (html_parser.parseFragment(text).text ?? '').trim();

/// Throws a [ToolError], naming the group, when an own group of [groups]
/// other than the one with the id [except] has the name [name] already, as
/// the list shows it ([myGroupTextAsListed]): two own groups with one name
/// cannot be told apart in the compose search, so neither in
/// `search_recipients` nor in `send_message`. The library refuses such a
/// name too, but names the group by its id only.
void checkMyGroupNameFree(List<MyGroup> groups, String name, {int? except}) {
  final listed = myGroupTextAsListed(name);
  for (final group in groups) {
    if (group.id != except && group.name == listed) {
      throw ToolError(
        'Your own group ${myGroupReference(group)} has that name already: '
        'two own groups with one name cannot be told apart in '
        'search_recipients and send_message. Ask the user for another name. '
        '$myGroupNothingSent',
      );
    }
  }
}

/// The result of a write of an own group that went out without Smartschool
/// confirming it ([error]): [what] (like `Your own group "Reis Parijs"`)
/// may or may not have been [done] (a past participle). Claude must not
/// call [tool] again for it, but list the groups first ([check] says what
/// to look for, like `to see whether it is there`) and tell the user.
/// [checkWith] says what to read instead of the list: for a change of the
/// members, the members ([readMyGroupToCheck], #233).
///
/// The log gets the status or the type of the failure, never the library's
/// message.
CallToolResult myGroupWriteNotConfirmed({
  required String tool,
  required String what,
  required String done,
  required String check,
  required SmartschoolMyGroupSaveUnconfirmedError error,
  String checkWith = 'list your own groups with list_my_groups',
}) => CallToolResult(
  isError: true,
  content: [
    TextContent(
      text: myGroupNotConfirmedText(
        tool: tool,
        what: what,
        done: done,
        check: check,
        error: error,
        checkWith: checkWith,
      ),
    ),
  ],
);

/// The text of [myGroupWriteNotConfirmed], which it logs as that does;
/// also for `remove_my_group_members`, which says it after the members it
/// did remove (#233).
String myGroupNotConfirmedText({
  required String tool,
  required String what,
  required String done,
  required String check,
  required SmartschoolMyGroupSaveUnconfirmedError error,
  String checkWith = 'list your own groups with list_my_groups',
}) {
  final why = switch (error) {
    SmartschoolMyGroupSaveUnconfirmedError(:final int statusCode) =>
      'HTTP $statusCode',
    SmartschoolMyGroupSaveUnconfirmedError(:final Object cause) =>
      'no answer: ${cause.runtimeType}',
    _ => 'an answer that does not confirm it',
  };
  log('$tool: Smartschool did not confirm the write, not retrying ($why)');
  return '$what may or may not have been $done: it was sent, but Smartschool '
      'did not confirm it. Do not call $tool again for it. First $checkWith '
      '$check. Then tell the user what you found.';
}

// ---------------------------------------------------------------------------
// The members of a group (#233)
// ---------------------------------------------------------------------------

/// What `add_my_group_members` and `remove_my_group_members` read to check
/// a change of the members of own group [id] that Smartschool did not
/// confirm: `checkWith` of [myGroupWriteNotConfirmed].
String readMyGroupToCheck(int id) =>
    'read the members of the group with read_my_group (group_id $id)';

/// [count] members, like `no members`, `1 member` or `3 members`.
String myGroupMemberCount(int count) => switch (count) {
  0 => 'no members',
  1 => '1 member',
  _ => '$count members',
};

/// The [ToolError] for own group [group], which has a member that is not a
/// person (a class or a Smartschool group, added in Smartschool with the
/// picker's tabs; not seen live): the library does not change the members
/// of such a group (a [SmartschoolMyGroupsError] before sending), as what
/// it holds was not tried. Said in plain words, before anything is sent;
/// [nothingDone] says what did not happen.
ToolError myGroupNotOnlyPeople(MyGroup group, {required String nothingDone}) =>
    ToolError(
      'Your own group ${myGroupReference(group)} has a member that is not a '
      'person (a class or a group): the server does not change the members '
      'of such a group, as that was not tried in Smartschool. The user '
      'changes its members $myGroupsInProfile. $nothingDone',
    );

/// At most this many people per call of `add_my_group_members` and of
/// `remove_my_group_members`, as many as `send_message` takes in one field.
const maxMyGroupMemberChanges = 50;

/// The input schema of the people argument of `add_my_group_members`
/// (`people`) and `remove_my_group_members` (`members`): 1 to
/// [maxMyGroupMemberChanges] texts.
Schema myGroupPeopleSchema(String description) => Schema.list(
  description: description,
  items: Schema.string(minLength: 1),
  minItems: 1,
  maxItems: maxMyGroupMemberChanges,
);

/// The argument [name] of [arguments] ([myGroupPeopleSchema]), each text
/// trimmed and once (ignoring case and extra spaces), in the order given.
///
/// Throws a [ToolError], before anything is sent, for an empty list and for
/// an entry that is not text, or empty.
List<String> myGroupPeopleArgument(
  Map<String, Object?> arguments,
  String name,
) {
  final values = switch (arguments[name]) {
    final List<Object?> values when values.isNotEmpty => values,
    _ => throw ToolError(
      '$name must list at least one person. $myGroupNothingSent',
    ),
  };
  final seen = <String>{};
  return [
    for (final value in values)
      if (value is! String || value.trim().isEmpty)
        throw ToolError(
          'Each entry of $name must be a person, like "Sven Lamber (user '
          '146)"; ${value is String ? 'an empty one' : '$value'} is not. '
          '$myGroupNothingSent',
        )
      else if (seen.add(normalName(value)))
        value.trim(),
  ];
}

/// [count] people, like `1 person` or `3 people`.
String myGroupPeopleCount(int count) =>
    count == 1 ? '1 person' : '$count people';
