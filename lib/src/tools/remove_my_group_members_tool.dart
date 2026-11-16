import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/my_groups.dart';
import '../messages/recipient_search.dart';
import '../problems.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `remove_my_group_members`: removes members from one of the user's own
/// mail groups ("Mijn groepen", `MyGroupsService.removeMember`,
/// dartschool#253), by its id from `list_my_groups` (#233).
///
/// The members are named as `read_my_group` lists them, and found among the
/// group's members, which are read first: nothing is removed when one does
/// not name exactly one member (the result then lists the members).
/// Someone who is not in the group is reported, not sent.
///
/// Smartschool removes one member per request, and answers `true` whether
/// or not anyone was removed: the library confirms each removal in the
/// members page after it. So the members are removed one by one, each in a
/// session call of its own, and the result says who was removed; where a
/// removal fails, the rest is not tried, and a removal Smartschool did not
/// confirm is reported as maybe made, with `read_my_group` to check
/// ([myGroupNotConfirmedText]).
///
/// Marked destructive for approval; not idempotent, as #233 marks both
/// writes of the members.
ServerTool removeMyGroupMembersTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'remove_my_group_members',
    title: 'Remove people from an own Smartschool mail group',
    description:
        'Removes members from one of the user\'s own groups in Smartschool '
        '("Mijn groepen"), by its id from list_my_groups. Read the group with '
        'read_my_group first. Before calling this tool, show the user the '
        'group and every member to remove, and only call this tool after the '
        'user has explicitly confirmed it. Pass each member as read_my_group '
        'lists it before the "|", like "Lamber Sven (user 146)"; a name alone '
        'is enough when exactly one member has that name. Nothing is removed '
        'when one does not name exactly one member: the result then lists '
        'the members. Someone who is not in the group is reported, not sent. '
        'The members are removed one by one; the result says who was removed '
        'and how many members the group has after. If the result says a '
        'removal may or may not have been made, do not call this tool again '
        'for it: check with read_my_group, and tell the user. For requests '
        'like "haal Jan uit mijn groep Projectwerk".',
    inputSchema: Schema.object(
      properties: {
        'group_id': myGroupIdSchema(),
        'members': myGroupPeopleSchema(
          'The members to remove, as the user confirmed them: each as '
          'read_my_group lists it before the "|", like "Lamber Sven (user '
          '146)", or a name that exactly one member has.',
        ),
      },
      required: ['group_id', 'members'],
    ),
    annotations: ToolAnnotations(
      title: 'Remove people from an own Smartschool mail group',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _remove(session, request.arguments ?? const {}),
);

const _nothingRemoved = 'Nothing was removed.';

/// Where the removals stopped: at [member], which was not removed
/// ([maybeRemoved] false) or may or may not have been, for [reason].
typedef _Stop = ({MyGroupMember member, bool maybeRemoved, String reason});

Future<CallToolResult> _remove(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = requiredIntArgument(arguments, 'group_id');
  final entries = myGroupPeopleArgument(arguments, 'members');
  final (group, members) = await withMyGroupWrite(
    session,
    (groups, _) async {
      final group = findMyGroup(await groups.list(), id);
      try {
        return (group, await groups.members(group));
      } on SmartschoolMyGroupNotFoundError {
        // Deleted since the list was read.
        throw unknownMyGroup(
          await groups.list(),
          id,
          nothingDone: _nothingRemoved,
        );
      }
    },
    what: 'the removal of members from own group $id',
    nothingDone: _nothingRemoved,
  );
  final heading = 'your own group "${group.name}" (group $id)';

  final targets = <MyGroupMember>[];
  final notIn = <String>[];
  final unclear = <String>[];
  final people = [
    for (final member in members)
      if (member.isUser) member,
  ];
  for (final entry in entries) {
    // A line of read_my_group, without what follows its "|".
    final request = RecipientRequest.parse(entry.split('|').first);
    final text = '"${request.text}"';
    if (request.group || request.coaccount != 0) {
      unclear.add(
        '- $text names ${request.group ? 'a group' : 'a co-account'}, not a '
        'member.',
      );
      continue;
    }
    final named = [
      for (final member in people)
        if ((request.id == null || member.userId == request.id) &&
            _sameName(member.name, request.name))
          member,
    ];
    if (named case [final member]) {
      if (!targets.any((target) => target.userId == member.userId)) {
        targets.add(member);
      }
    } else if (request.id case final userId?
        when !people.any((member) => member.userId == userId)) {
      notIn.add('- $text');
    } else {
      unclear.add(
        named.isEmpty
            ? '- $text: no member has '
                  '${request.id == null ? 'that name' : 'that name and id'}.'
            : '- $text: ${named.length} members have that name.',
      );
    }
  }
  if (unclear.isNotEmpty) {
    throw ToolError(
      [
        'Nothing was removed: not every entry names exactly one member of '
            '$heading.',
        ...unclear,
        if (members.isEmpty)
          'It has no members.'
        else ...[
          'Its members:',
          for (final member in members) '- ${_line(member)}',
        ],
        'Show the user the members and let them choose: never choose for '
            'them. Then call remove_my_group_members again with each member '
            'as read_my_group lists it, like "Lamber Sven (user 146)".',
      ].join('\n'),
    );
  }

  final removed = <MyGroupMember>[];
  final gone = <MyGroupMember>[];
  _Stop? stop;
  for (final member in targets) {
    stop = await _removeOne(
      session,
      group,
      member,
      removed: removed,
      gone: gone,
    );
    if (stop != null) break;
  }
  log(
    'remove_my_group_members: removed ${removed.length} of '
    '${targets.length} from own group $id'
    '${stop == null ? '' : ' (stopped)'}',
  );

  final untried = stop == null
      ? const <MyGroupMember>[]
      : targets.skip(targets.indexOf(stop.member) + 1);
  final after = members.length - removed.length - gone.length;
  final lines = [
    if (stop != null) ...[
      'Removing members from $heading stopped at ${_line(stop.member)}: '
          '${switch (removed.length) {
            0 => 'nothing was removed',
            1 => '1 member was removed',
            final n => '$n members were removed',
          }}.',
      if (removed.isNotEmpty) ...[
        'Removed:',
        for (final member in removed) '- ${_line(member)}',
      ],
      stop.maybeRemoved ? 'Maybe removed:' : 'Not removed:',
      '- ${_line(stop.member)}',
      if (untried.isNotEmpty) ...[
        'Not tried:',
        for (final member in untried) '- ${_line(member)}',
      ],
    ] else if (removed.isEmpty)
      'Nothing was removed: '
          '${gone.length + notIn.length == 1 ? 'that person is not' : 'none of them is'} '
          'in $heading. It has ${myGroupMemberCount(after)}.'
    else ...[
      'Removed ${myGroupMemberCount(removed.length)} from $heading; it now '
          'has ${myGroupMemberCount(after)}:',
      for (final member in removed) '- ${_line(member)}',
    ],
    if (gone.isNotEmpty || notIn.isNotEmpty) ...[
      'Not in the group, so not removed:',
      for (final member in gone) '- ${_line(member)}',
      ...notIn,
    ],
    ?stop?.reason,
  ];
  return CallToolResult(
    isError: stop != null,
    content: [TextContent(text: lines.join('\n'))],
  );
}

/// Removes [member] from [group], in a session call of its own, and adds it
/// to [removed] once Smartschool confirmed it, or to [gone] when the group's
/// members page no longer lists it (removed meanwhile): the library then
/// sends nothing. Returns null then; else where and why it stopped.
Future<_Stop?> _removeOne(
  SmartschoolSession session,
  MyGroup group,
  MyGroupMember member, {
  required List<MyGroupMember> removed,
  required List<MyGroupMember> gone,
}) async {
  final named = _line(member);
  try {
    final done = await withMyGroupWrite(
      session,
      (groups, _) => groups.removeMember(group, member),
      what: 'the removal of $named',
      nothingDone: '$named was not removed.',
    );
    (done ? removed : gone).add(member);
    return null;
  } on SmartschoolMyGroupSaveUnconfirmedError catch (error) {
    return (
      member: member,
      maybeRemoved: true,
      reason: myGroupNotConfirmedText(
        tool: 'remove_my_group_members',
        what: named,
        done: 'removed',
        check: 'to see who is in it now',
        checkWith: readMyGroupToCheck(group.id),
        error: error,
      ),
    );
  } on ToolError catch (error) {
    return (member: member, maybeRemoved: false, reason: error.message);
  } on SmartschoolProblem catch (problem) {
    // Smartschool refused the session, also after logging in again, or
    // could not be reached before the removal was sent.
    return (
      member: member,
      maybeRemoved: false,
      reason: '${problem.message} $named was not removed.',
    );
  }
}

/// [member] as `read_my_group` lists it, but every member as one of the own
/// school: the user id names a member on the members page.
String _line(MyGroupMember member) =>
    myGroupMemberLine(member, ownPlatform: null);

/// Whether [a] and [b] are the same name, ignoring case and extra spaces,
/// also in another order of their words: `read_my_group` lists a member
/// last name first, the compose search mostly first name first.
bool _sameName(String a, String b) {
  String words(String name) => (normalName(name).split(' ')..sort()).join(' ');
  return words(a) == words(b);
}
