import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/my_groups.dart';
import '../messages/recipient_search.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `add_my_group_members`: adds people to one of the user's own mail groups
/// ("Mijn groepen", `MyGroupsService.addMembers`, dartschool#253), by its id
/// from `list_my_groups` (#233).
///
/// The people are named as `search_recipients` lists them, and looked up
/// again as `send_message` looks up its recipients ([searchRecipientsAll],
/// [RecipientRequest]): nothing is changed when one does not name exactly
/// one person, and the result then lists who Smartschool finds. Only people
/// of the own school, by their own account: the library refuses a person of
/// another school of the school group (not tried), and adds a co-account
/// as the pupil's own account (yvanvds/dartschool#256), so the tool refuses
/// both itself, in plain words. Someone who is a member already is
/// reported, not sent.
///
/// Marked destructive, as the other writes of the server are, for Claude
/// Desktop and Codex to ask approval; not idempotent, as #233 marks both
/// writes of the members. The library sends the whole new member list once
/// (Smartschool's member picker replaces the members) and confirms it in
/// the members page Smartschool answers with; a change it cannot confirm is
/// reported as maybe saved ([myGroupWriteNotConfirmed]), with `read_my_group`
/// to check.
ServerTool addMyGroupMembersTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'add_my_group_members',
    title: 'Add people to an own Smartschool mail group',
    description:
        'Adds people to one of the user\'s own groups in Smartschool ("Mijn '
        'groepen"), by its id from list_my_groups: people of the user\'s own '
        'school, by their own account (not a co-account, not a group or a '
        'class). Before calling this tool, look up every person with '
        'search_recipients, show the user the group and every person to add '
        '(the names as search_recipients lists them, with their class), and '
        'only call this tool after the user has explicitly confirmed it. '
        'When search_recipients finds several people for a name, or none, '
        'ask the user who they mean: never choose for them. Pass each person '
        'as search_recipients lists it before the "|", like "Sven Lamber '
        '(user 146)"; a name alone is enough when exactly one person has '
        'that name. The tool looks every person up again, and changes '
        'nothing when one does not name exactly one person of the own '
        'school: it then lists who Smartschool finds. Someone who is in the '
        'group already is reported, not added again. The result gives the '
        'number of members after the change. If the result says the change '
        'may or may not have been saved, do not call this tool again: check '
        'with read_my_group, and tell the user. For requests like "zet Jan '
        'en An in mijn groep Projectwerk".',
    inputSchema: Schema.object(
      properties: {
        'group_id': myGroupIdSchema(),
        'people': myGroupPeopleSchema(
          'The people to add, as the user confirmed them: each as '
          'search_recipients lists it before the "|", like "Sven Lamber '
          '(user 146)", or a name that exactly one person has.',
        ),
      },
      required: ['group_id', 'people'],
    ),
    annotations: ToolAnnotations(
      title: 'Add people to an own Smartschool mail group',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _add(session, request.arguments ?? const {}),
);

const _nothingChanged = 'Nothing was changed.';

/// What [_add] found before the change: the people to add, those in the
/// group already, the number of members before, and whether the library
/// saved the change (`false`: nothing to change by then).
typedef _Addition = ({
  List<UserRecipient> adding,
  List<UserRecipient> already,
  int before,
  bool added,
});

Future<CallToolResult> _add(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = requiredIntArgument(arguments, 'group_id');
  final requests = [
    for (final text in myGroupPeopleArgument(arguments, 'people'))
      _addable(RecipientRequest.parse(text)),
  ];
  late MyGroup group;
  // The people the change went out for, for a change not confirmed.
  var sent = const <UserRecipient>[];
  final _Addition addition;
  try {
    addition = await withMyGroupWrite(
      session,
      (groups, client) async {
        group = findMyGroup(await groups.list(), id);
        final people = await _lookUp(client, requests);
        final List<MyGroupMember> members;
        try {
          members = await groups.members(group);
        } on SmartschoolMyGroupNotFoundError {
          // Deleted since the list was read.
          throw unknownMyGroup(
            await groups.list(),
            id,
            nothingDone: _nothingChanged,
          );
        }
        if (members.any((member) => !member.isUser)) {
          throw myGroupNotOnlyPeople(group, nothingDone: _nothingChanged);
        }
        final already = <UserRecipient>[];
        final adding = <UserRecipient>[];
        for (final person in people) {
          final user = person.user;
          final member = members
              .where((member) => member.userId == user.userId)
              .firstOrNull;
          if (member == null) {
            adding.add(person);
          } else if (member.ssId == user.ssId) {
            already.add(person);
          } else {
            // The members page names members by user id only: the library
            // refuses this as an answer it cannot use.
            throw ToolError(
              '${person.reference} has the user id of a member of your own '
              'group of another school, '
              '${myGroupMemberLine(member, ownPlatform: user.ssId)}: '
              'Smartschool\'s members page cannot tell the two apart, so the '
              'server does not add them. $_nothingChanged',
            );
          }
        }
        sent = adding;
        final added =
            adding.isNotEmpty &&
            await groups.addMembers(group, [
              for (final person in adding) person.user,
            ]);
        return (
          adding: adding,
          already: already,
          before: members.length,
          added: added,
        );
      },
      what: 'the addition of people to own group $id',
      nothingDone: _nothingChanged,
    );
  } on SmartschoolMyGroupSaveUnconfirmedError catch (error) {
    return myGroupWriteNotConfirmed(
      tool: 'add_my_group_members',
      what:
          'The addition of ${myGroupPeopleCount(sent.length)} to your own '
          'group "${group.name}" (group $id)',
      done: 'saved',
      check: 'to see who is in it now',
      checkWith: readMyGroupToCheck(id),
      error: error,
    );
  }
  final (:adding, :already, :before, :added) = addition;
  final heading = 'your own group "${group.name}" (group $id)';
  if (!added) {
    log('add_my_group_members: nothing to add to own group $id');
    // People to add who were members by the time of the change.
    final members = before + adding.length;
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Nothing was changed: '
                '${already.length + adding.length == 1 ? 'that person is' : 'they are all'} '
                'in $heading already. It has ${myGroupMemberCount(members)}.',
            for (final person in [...already, ...adding]) '- ${person.listing}',
          ].join('\n'),
        ),
      ],
    );
  }
  log('add_my_group_members: added ${adding.length} to own group $id');
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Added ${myGroupPeopleCount(adding.length)} to $heading; it now has '
              '${myGroupMemberCount(before + adding.length)}:',
          for (final person in adding) '- ${person.listing}',
          if (already.isNotEmpty) ...[
            'In it already, so not added again:',
            for (final person in already) '- ${person.listing}',
          ],
        ].join('\n'),
      ),
    ],
  );
}

/// [request] when it can name a person to add; throws a [ToolError], before
/// anything is sent, when it names a group, a co-account or a person of
/// another school of the school group.
RecipientRequest _addable(RecipientRequest request) {
  final text = '"${request.text}"';
  if (request.group) {
    throw ToolError(
      '$text names a group, not a person: an own group takes people, not '
      'groups or classes. Pass each person as search_recipients lists them, '
      'like "Sven Lamber (user 146)". $myGroupNothingSent',
    );
  }
  if (request.coaccount != 0) {
    throw ToolError(
      '$text names a co-account (the account of a parent): the server adds '
      'people to an own group by their own account only, as adding a '
      'co-account was not tried in Smartschool. Pass the person\'s own '
      'account, like "Sven Lamber (user 146)", or leave them out. '
      '$myGroupNothingSent',
    );
  }
  if (request.otherSchool) {
    throw ToolError(
      '$text names a person of another school of the school group: the '
      'server adds people of the user\'s own school only, as adding a person '
      'of another school was not tried in Smartschool. Leave them out, and '
      'tell the user. $myGroupNothingSent',
    );
  }
  return request;
}

/// The person each of [requests] names, each once, looked up with the
/// search of a compose form on [client] as `send_message` looks up its
/// recipients: every name searched once, all on one form, with the
/// account's setting "Toon personen van andere scholen".
///
/// A request matches the people the search finds by their own account only
/// (a co-account has the pupil's user id, and the library would add the
/// pupil, yvanvds/dartschool#256); a group never. Throws a [ToolError] that
/// lists every request that names no such person, or several, with who the
/// search does find, and every person it names of another school of the
/// school group, or of a school Smartschool does not say.
Future<List<UserRecipient>> _lookUp(
  SmartschoolClient client,
  List<RecipientRequest> requests,
) async {
  final messages = MessagesService(client);
  try {
    // The spelling searched for each name, by its normalName: the first.
    final names = <String, String>{};
    for (final request in requests) {
      names.putIfAbsent(normalName(request.name), () => request.name);
    }
    final searches = await searchRecipientsAll(messages, names.values);
    final unclear = <String>[];
    final refused = <String>[];
    final found = <UserRecipient>[];
    for (final request in requests) {
      final people = [
        for (final recipient in searches[names[normalName(request.name)]]!)
          if (recipient case UserRecipient(:final user) when user.userLt == 0)
            recipient,
      ];
      final text = '"${request.text}"';
      switch (request.matches(people)) {
        case [final UserRecipient person]:
          switch (person.user.otherSchool) {
            case false:
              found.add(person);
            case true:
              refused.add(
                '- $text: ${person.listing}, a person of another school of '
                'the school group, whom the server does not add.',
              );
            case null:
              refused.add(
                '- $text: Smartschool does not say whether '
                '${person.reference} is of the user\'s own school, so the '
                'server does not add them.',
              );
          }
        case []:
          unclear.add(
            '- $text: Smartschool finds no person with '
            '${request.id == null ? 'exactly that name' : 'that name and id'}'
            '${listCandidates(people, 'It finds')}',
          );
        case final matches:
          unclear.add(
            '- $text: Smartschool finds ${myGroupPeopleCount(matches.length)} '
            'with that name${listCandidates(matches, 'They are')}',
          );
      }
    }
    if (unclear.isNotEmpty || refused.isNotEmpty) {
      throw ToolError(
        [
          'Nothing was changed: not every entry names exactly one person of '
              'the user\'s own school.',
          ...unclear,
          ...refused,
          if (unclear.isNotEmpty)
            'Show the user who Smartschool finds and let them choose: never '
                'choose for them. Then call add_my_group_members again with '
                'each person as search_recipients lists it before the "|", '
                'like "Sven Lamber (user 146)".',
          if (refused.isNotEmpty)
            'The server adds people of the user\'s own school only, as adding '
                'others was not tried in Smartschool: tell the user, and leave '
                'them out.',
        ].join('\n'),
      );
    }
    return [...withoutRepeats(found).whereType<UserRecipient>()];
  } finally {
    await messages.dispose();
  }
}
