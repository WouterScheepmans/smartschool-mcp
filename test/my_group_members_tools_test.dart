/// The writes of the members of the user's own mail groups, "Mijn groepen"
/// (#233): `add_my_group_members` and `remove_my_group_members`, called over
/// MCP on the real server, session and library, against the fake "Mijn
/// groepen" of #231 (`test/support/fake_my_groups.dart`), which serves the
/// member picker's new selection, the members form that saves it and the
/// removal of one member as `MyGroupsService` documents them
/// (dartschool#253). The people to add are found with the fake compose
/// search, as `send_message` finds its recipients. Made-up groups and people
/// only (the fakes of `test/fixtures/lvs/FAKES.md`): the members of a real
/// group are mostly pupils.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/add_my_group_members_tool.dart';
import 'package:smartschool_mcp/src/tools/create_my_group_tool.dart';
import 'package:smartschool_mcp/src/tools/delete_my_group_tool.dart';
import 'package:smartschool_mcp/src/tools/list_my_groups_tool.dart';
import 'package:smartschool_mcp/src/tools/read_my_group_tool.dart';
import 'package:smartschool_mcp/src/tools/remove_my_group_members_tool.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/log_capture.dart';
import 'support/mcp.dart';

FakeMyGroup _projectwerk() => FakeMyGroup(
  900501,
  'Projectwerk 5A',
  description: 'Testvak informatica',
  members: [
    const FakeMyGroupMember(900002, 'Peeters Marie'),
    const FakeMyGroupMember(900001, 'Janssens Jan'),
    const FakeMyGroupMember(900005, 'Dupré Céline'),
  ],
);

FakeMyGroup _zorg() =>
    FakeMyGroup(900503, 'zorgteam test', description: 'Testvak 2B');

/// The people the compose search finds: two of the same name, a member of
/// [_projectwerk] (first name first, as the search names people), and a
/// person of another school, whom it finds with "Toon personen van andere
/// scholen" on only.
const _directory = [
  FakeRecipient.user('Sven Lamber', id: 900011, className: '5GZ'),
  FakeRecipient.user('Lien Dewit', id: 900012, className: '6A'),
  FakeRecipient.user('Lien Dewit', id: 900013, className: '6B'),
  FakeRecipient.user('Marie Peeters', id: 900002, className: '5A'),
  FakeRecipient.user(
    'Ned Flanders',
    id: 2231,
    school: 'Sint-Andreas',
    platform: 5810,
  ),
];

/// Every name of the fakes and the tests, which the log must never hold.
const _names = [
  'Projectwerk',
  'zorgteam',
  'Testvak',
  'Peeters',
  'Janssens',
  'Dupré',
  'Lamber',
  'Dewit',
  'Flanders',
  'dartschool test',
];

void main() {
  late FakeSmartschool server;
  late FakeMyGroups myGroups;
  late SmartschoolSession session;
  late ServerConnection connection;

  List<ServerTool> tools() => [
    listMyGroupsTool(session),
    readMyGroupTool(session),
    createMyGroupTool(session),
    deleteMyGroupTool(session),
    addMyGroupMembersTool(session),
    removeMyGroupMembersTool(session),
  ];

  setUp(() async {
    server = FakeSmartschool();
    server.mailbox.directory.addAll(_directory);
    myGroups = server.myGroups..groups.addAll([_projectwerk(), _zorg()]);
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(tools: tools());
  });

  /// Calls [tool] on a server connected in a zone that captures the log,
  /// and returns its result, its text and the log.
  Future<(CallToolResult, String, String)> logged(
    String tool, [
    Map<String, Object?>? arguments,
  ]) async {
    final ((result, text), log) = await captureLog(() async {
      final (connection, _) = await connect(tools: tools());
      return callTool(connection, tool, arguments);
    });
    return (result, text, log);
  }

  Future<String> ok(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// The members of own group [id] in the fake, as `name user`.
  List<String> membersOf(int id) => [
    for (final member
        in myGroups.groups.firstWhere((group) => group.id == id).members)
      '${member.name} ${member.userId}',
  ];

  /// The recipient searches of the fake compose forms.
  List<String> searches() => [
    for (final action in server.mailbox.actions)
      if (action.startsWith('search ')) action,
  ];

  test('both are writes the client asks approval for, after Claude showed '
      'the group and the people', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    for (final name in ['add_my_group_members', 'remove_my_group_members']) {
      final annotations = tools[name]!.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse, reason: name);
      expect(annotations.destructiveHint, isTrue, reason: name);
      expect(annotations.idempotentHint, isFalse, reason: name);
      expect(annotations.openWorldHint, isTrue, reason: name);
      expect(
        tools[name]!.description,
        allOf(
          contains('"Mijn groepen"'),
          // The words of every confirmed write of the server.
          contains(
            'only call this tool after the user has explicitly confirmed it',
          ),
          contains('check with read_my_group, and tell the user'),
        ),
        reason: name,
      );
    }
    expect(
      tools['add_my_group_members']!.description,
      allOf(
        contains(
          'show the user the group and every person to add (the names as '
          'search_recipients lists them, with their class)',
        ),
        contains('never choose for them'),
        contains('not a co-account, not a group or a class'),
      ),
    );
    expect(
      tools['remove_my_group_members']!.description,
      contains('show the user the group and every member to remove'),
    );
    final add = tools['add_my_group_members']!.inputSchema;
    expect(add.properties!.keys, ['group_id', 'people']);
    expect(add.required, ['group_id', 'people']);
    final remove = tools['remove_my_group_members']!.inputSchema;
    expect(remove.properties!.keys, ['group_id', 'members']);
    expect(remove.required, ['group_id', 'members']);
  });

  test('a throwaway group gets a person, who is in it and is taken out '
      'again, and the group is deleted', () async {
    expect(
      await ok('create_my_group', {'name': 'dartschool test'}),
      contains('It has no members yet: add people with add_my_group_members.'),
    );
    expect(
      await ok('add_my_group_members', {
        'group_id': 900601,
        'people': ['Sven Lamber (user 900011)'],
      }),
      'Added 1 person to your own group "dartschool test" (group 900601); it '
      'now has 1 member:\n'
      '- Sven Lamber (user 900011) | 5GZ',
    );
    expect(
      await ok('read_my_group', {'group_id': 900601}),
      'Own group dartschool test (group 900601)\n'
      '1 member:\n'
      '- Sven Lamber (user 900011)',
    );
    expect(
      await ok('remove_my_group_members', {
        'group_id': 900601,
        'members': ['Sven Lamber (user 900011)'],
      }),
      'Removed 1 member from your own group "dartschool test" (group '
      '900601); it now has no members:\n'
      '- Sven Lamber (user 900011)',
    );
    expect(
      await ok('read_my_group', {'group_id': 900601}),
      'Own group dartschool test (group 900601)\n'
      'It has no members: add people with add_my_group_members.',
    );
    expect(
      await ok('delete_my_group', {'group_id': 900601}),
      startsWith('Deleted your own group "dartschool test" (group 900601)'),
    );
    expect(myGroups.writes, [
      'POST addedit',
      'POST userSelect/confirm Selection mygroups_900601',
      'POST users 900601',
      'POST deleteUser 900601 900011',
      'GET delete 900601',
    ]);
  });

  group('add_my_group_members', () {
    test('adds people named by reference and by a name alone, and reports '
        'who is in it already, saving the members once', () async {
      expect(
        await ok('add_my_group_members', {
          'group_id': 900501,
          'people': [
            'Sven Lamber (user 900011)',
            'Lien Dewit (user 900013)',
            ' marie  PEETERS ',
            'Sven Lamber',
          ],
        }),
        'Added 2 people to your own group "Projectwerk 5A" (group 900501); '
        'it now has 5 members:\n'
        '- Sven Lamber (user 900011) | 5GZ\n'
        '- Lien Dewit (user 900013) | 6B\n'
        'In it already, so not added again:\n'
        '- Marie Peeters (user 900002) | 5A',
      );
      expect(
        membersOf(900501),
        unorderedEquals([
          'Peeters Marie 900002',
          'Janssens Jan 900001',
          'Dupré Céline 900005',
          'Sven Lamber 900011',
          'Lien Dewit 900013',
        ]),
      );
      expect(myGroups.writes, [
        'POST userSelect/confirm Selection mygroups_900501',
        'POST users 900501',
      ]);
      // Each name searched once, on one compose form.
      expect(searches(), [
        'search val=Sven Lamber',
        'search val=Lien Dewit',
        'search val=marie  PEETERS',
      ]);
      expect(
        await ok('read_my_group', {'group_id': 900501}),
        contains(
          '5 members:\n'
          '- Dupré Céline (user 900005)\n'
          '- Janssens Jan (user 900001)\n'
          '- Lien Dewit (user 900013)\n'
          '- Peeters Marie (user 900002)\n'
          '- Sven Lamber (user 900011)',
        ),
      );
    });

    test('someone who is in the group already is reported, and nothing is '
        'sent', () async {
      final (result, text) = await callTool(
        connection,
        'add_my_group_members',
        {
          'group_id': 900501,
          'people': ['Marie Peeters (user 900002)'],
        },
      );
      expect(result.isError, isNot(true));
      expect(
        text,
        'Nothing was changed: that person is in your own group "Projectwerk '
        '5A" (group 900501) already. It has 3 members.\n'
        '- Marie Peeters (user 900002) | 5A',
      );
      expect(myGroups.writes, isEmpty);
    });

    test('a name that names several people, or none, changes nothing, with '
        'who Smartschool finds', () async {
      expect(
        await error('add_my_group_members', {
          'group_id': 900501,
          'people': ['Lien Dewit', 'Kim Nobody', 'Sven Lamber (user 900012)'],
        }),
        'Nothing was changed: not every entry names exactly one person of the '
        'user\'s own school.\n'
        '- "Lien Dewit": Smartschool finds 2 people with that name. They '
        'are:\n'
        '  - Lien Dewit (user 900012) | 6A\n'
        '  - Lien Dewit (user 900013) | 6B\n'
        '- "Kim Nobody": Smartschool finds no person with exactly that name.\n'
        '- "Sven Lamber (user 900012)": Smartschool finds no person with that '
        'name and id. It finds:\n'
        '  - Sven Lamber (user 900011) | 5GZ\n'
        'Show the user who Smartschool finds and let them choose: never '
        'choose for them. Then call add_my_group_members again with each '
        'person as search_recipients lists it before the "|", like "Sven '
        'Lamber (user 146)".',
      );
      expect(myGroups.writes, isEmpty);
      expect(membersOf(900501), hasLength(3));
    });

    test('a person of another school of the school group is refused in plain '
        'words, and nothing is changed', () async {
      server.mailbox.otherSchools = true;

      expect(
        await error('add_my_group_members', {
          'group_id': 900501,
          'people': ['Sven Lamber', 'Ned Flanders'],
        }),
        'Nothing was changed: not every entry names exactly one person of the '
        'user\'s own school.\n'
        '- "Ned Flanders": Ned Flanders (user 2231, platform 5810) | school: '
        'Sint-Andreas, a person of another school of the school group, whom '
        'the server does not add.\n'
        'The server adds people of the user\'s own school only, as adding '
        'others was not tried in Smartschool: tell the user, and leave them '
        'out.',
      );
      expect(myGroups.writes, isEmpty);
    });

    for (final (entry, refusal) in [
      ('5GZ (group 298)', '"5GZ (group 298)" names a group, not a person'),
      (
        'Sven Lamber (user 900011, co-account 1)',
        '"Sven Lamber (user 900011, co-account 1)" names a co-account (the '
            'account of a parent)',
      ),
      (
        'Ned Flanders (user 2231, platform 5810)',
        '"Ned Flanders (user 2231, platform 5810)" names a person of another '
            'school of the school group',
      ),
    ]) {
      test('refuses "$entry" before anything is sent', () async {
        expect(
          await error('add_my_group_members', {
            'group_id': 900501,
            'people': ['Sven Lamber', entry],
          }),
          allOf(startsWith(refusal), endsWith(' Nothing was sent.')),
        );
        expect(server.requests, isEmpty);
      });
    }

    test('refuses an id that is not one of the user\'s groups, with the '
        'groups there are, before looking anyone up', () async {
      expect(
        await error('add_my_group_members', {
          'group_id': 298,
          'people': ['Sven Lamber'],
        }),
        'You have no own group with id 298 (any more). Nothing was sent. '
        'Your own groups:\n'
        '- Projectwerk 5A (group 900501) | Testvak informatica\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.requests, ['GET main']);
      expect(searches(), isEmpty);
    });

    test('a change whose answer does not come in may or may not have been '
        'saved: not sent again, read_my_group to check, and the log names '
        'no one', () async {
      myGroups.dropping.add('members');

      final (result, text, log) = await logged('add_my_group_members', {
        'group_id': 900501,
        'people': ['Sven Lamber'],
      });

      expect(result.isError, isTrue);
      expect(
        text,
        'The addition of 1 person to your own group "Projectwerk 5A" (group '
        '900501) may or may not have been saved: it was sent, but Smartschool '
        'did not confirm it. Do not call add_my_group_members again for it. '
        'First read the members of the group with read_my_group (group_id '
        '900501) to see who is in it now. Then tell the user what you found.',
      );
      expect(myGroups.writes, [
        'POST userSelect/confirm Selection mygroups_900501',
        'POST users 900501',
      ]);
      // It was saved: read_my_group shows him.
      expect(
        await ok('read_my_group', {'group_id': 900501}),
        contains('- Sven Lamber (user 900011)'),
      );
      expect(
        log,
        contains(
          'add_my_group_members: Smartschool did not confirm the write, not '
          'retrying (no answer: ',
        ),
      );
      for (final name in _names) {
        expect(log, isNot(contains(name)), reason: name);
      }
    });

    test('a picker that does not take the new selection is an error in '
        'plain words: the members form is not sent', () async {
      myGroups.failing['confirm'] = 500;

      expect(
        await error('add_my_group_members', {
          'group_id': 900501,
          'people': ['Sven Lamber'],
        }),
        allOf(
          startsWith(
            'Smartschool gave an answer about your own groups ("Mijn '
            'groepen") that the server could not use (HTTP 500).',
          ),
          endsWith(' Nothing was changed.'),
        ),
      );
      expect(myGroups.writes, [
        'POST userSelect/confirm Selection mygroups_900501',
      ]);
      expect(membersOf(900501), hasLength(3));
    });

    test('logs in again when Smartschool refuses the session for the '
        'members form, and saves the members once', () async {
      server.expireSessionBefore(
        (request) =>
            request.method == 'POST' &&
            request.uri.queryParameters['function'] == 'users',
      );

      expect(
        await ok('add_my_group_members', {
          'group_id': 900501,
          'people': ['Sven Lamber'],
        }),
        startsWith(
          'Added 1 person to your own group "Projectwerk 5A" (group 900501); '
          'it now has 4 members:\n',
        ),
      );
      expect(server.logins, 2);
      expect(server.refusedPosts, ['401 /']);
      // The refused form never reached "Mijn groepen"; the second did.
      expect(myGroups.writes, [
        'POST userSelect/confirm Selection mygroups_900501',
        'POST userSelect/confirm Selection mygroups_900501',
        'POST users 900501',
      ]);
      expect(membersOf(900501), hasLength(4));
    });
  });

  group('remove_my_group_members', () {
    test('removes members named as read_my_group lists them, or by a name in '
        'another order, one by one', () async {
      expect(
        await ok('remove_my_group_members', {
          'group_id': 900501,
          'members': [
            'Peeters Marie (user 900002) | ignored',
            'jan  janssens',
            'Peeters Marie (user 900002)',
          ],
        }),
        'Removed 2 members from your own group "Projectwerk 5A" (group '
        '900501); it now has 1 member:\n'
        '- Peeters Marie (user 900002)\n'
        '- Janssens Jan (user 900001)',
      );
      expect(membersOf(900501), ['Dupré Céline 900005']);
      expect(myGroups.writes, [
        'POST deleteUser 900501 900002',
        'POST deleteUser 900501 900001',
      ]);
    });

    test('someone who is not in the group is reported, not sent', () async {
      expect(
        await ok('remove_my_group_members', {
          'group_id': 900501,
          'members': [
            'Peeters Marie (user 900002)',
            'Lamber Sven (user 900011)',
          ],
        }),
        'Removed 1 member from your own group "Projectwerk 5A" (group '
        '900501); it now has 2 members:\n'
        '- Peeters Marie (user 900002)\n'
        'Not in the group, so not removed:\n'
        '- "Lamber Sven (user 900011)"',
      );
      expect(myGroups.writes, ['POST deleteUser 900501 900002']);

      final (result, text) = await callTool(
        connection,
        'remove_my_group_members',
        {
          'group_id': 900501,
          'members': ['Lamber Sven (user 900011)'],
        },
      );
      expect(result.isError, isNot(true));
      expect(
        text,
        'Nothing was removed: that person is not in your own group '
        '"Projectwerk 5A" (group 900501). It has 2 members.\n'
        'Not in the group, so not removed:\n'
        '- "Lamber Sven (user 900011)"',
      );
      expect(myGroups.writes, ['POST deleteUser 900501 900002']);
    });

    test('an entry that does not name exactly one member removes nothing, '
        'with the members', () async {
      expect(
        await error('remove_my_group_members', {
          'group_id': 900501,
          'members': [
            'Peeters Marie (user 900002)',
            'Peeters',
            'Dewit Lien (user 900002)',
            '5A (group 298)',
          ],
        }),
        'Nothing was removed: not every entry names exactly one member of '
        'your own group "Projectwerk 5A" (group 900501).\n'
        '- "Peeters": no member has that name.\n'
        '- "Dewit Lien (user 900002)": no member has that name and id.\n'
        '- "5A (group 298)" names a group, not a member.\n'
        'Its members:\n'
        '- Dupré Céline (user 900005)\n'
        '- Janssens Jan (user 900001)\n'
        '- Peeters Marie (user 900002)\n'
        'Show the user the members and let them choose: never choose for '
        'them. Then call remove_my_group_members again with each member as '
        'read_my_group lists it, like "Lamber Sven (user 146)".',
      );
      expect(myGroups.writes, isEmpty);
    });

    test('refuses an id that is not one of the user\'s groups, with the '
        'groups there are', () async {
      expect(
        await error('remove_my_group_members', {
          'group_id': 298,
          'members': ['Peeters Marie (user 900002)'],
        }),
        'You have no own group with id 298 (any more). Nothing was sent. '
        'Your own groups:\n'
        '- Projectwerk 5A (group 900501) | Testvak informatica\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.writes, isEmpty);
    });

    test('a removal whose answer does not come in stops the removals: who '
        'was removed, who may have been, and who was not tried', () async {
      myGroups.beforeAnswer = (request) {
        if (request == 'POST deleteUser 900501 900001') {
          myGroups.dropping.add('deleteUser');
        }
      };

      final (result, text, log) = await logged('remove_my_group_members', {
        'group_id': 900501,
        'members': [
          'Peeters Marie (user 900002)',
          'Janssens Jan (user 900001)',
          'Dupré Céline (user 900005)',
        ],
      });

      expect(result.isError, isTrue);
      expect(
        text,
        'Removing members from your own group "Projectwerk 5A" (group '
        '900501) stopped at Janssens Jan (user 900001): 1 member was '
        'removed.\n'
        'Removed:\n'
        '- Peeters Marie (user 900002)\n'
        'Maybe removed:\n'
        '- Janssens Jan (user 900001)\n'
        'Not tried:\n'
        '- Dupré Céline (user 900005)\n'
        'Janssens Jan (user 900001) may or may not have been removed: it was '
        'sent, but Smartschool did not confirm it. Do not call '
        'remove_my_group_members again for it. First read the members of '
        'the group with read_my_group (group_id 900501) to see who is in it '
        'now. Then tell the user what you found.',
      );
      expect(myGroups.writes, [
        'POST deleteUser 900501 900002',
        'POST deleteUser 900501 900001',
      ]);
      expect(log, contains('not retrying (no answer: '));
      expect(log, contains('removed 1 of 3 from own group 900501 (stopped)'));
      for (final name in _names) {
        expect(log, isNot(contains(name)), reason: name);
      }
    });

    test('a removal answered with an error may or may not have been '
        'made', () async {
      myGroups.failing['deleteUser'] = 500;

      final (result, text, log) = await logged('remove_my_group_members', {
        'group_id': 900501,
        'members': ['Peeters Marie (user 900002)'],
      });

      expect(result.isError, isTrue);
      expect(
        text,
        allOf(
          startsWith(
            'Removing members from your own group "Projectwerk 5A" (group '
            '900501) stopped at Peeters Marie (user 900002): nothing was '
            'removed.\n'
            'Maybe removed:\n'
            '- Peeters Marie (user 900002)\n',
          ),
          contains('may or may not have been removed'),
        ),
      );
      expect(log, contains('not retrying (HTTP 500)'));
    });

    test('a members page that cannot be read before a removal stops there: '
        'that member was not removed', () async {
      var loads = 0;
      myGroups.beforeAnswer = (request) {
        // The read of the members, then each removal's page before and
        // after it: the fourth is before the second removal.
        if (request == 'GET users 900501' && ++loads == 4) {
          myGroups.failing['users'] = 500;
        }
      };

      expect(
        await error('remove_my_group_members', {
          'group_id': 900501,
          'members': [
            'Peeters Marie (user 900002)',
            'Janssens Jan (user 900001)',
          ],
        }),
        'Removing members from your own group "Projectwerk 5A" (group '
        '900501) stopped at Janssens Jan (user 900001): 1 member was '
        'removed.\n'
        'Removed:\n'
        '- Peeters Marie (user 900002)\n'
        'Not removed:\n'
        '- Janssens Jan (user 900001)\n'
        'Smartschool gave an answer about your own groups ("Mijn groepen") '
        'that the server could not use (HTTP 500). Try again in a moment. If '
        'it keeps happening, look at the groups in Smartschool itself, under '
        '"Mijn groepen" in your profile; the details are in the server log. '
        'Janssens Jan (user 900001) was not removed.',
      );
      expect(myGroups.writes, ['POST deleteUser 900501 900002']);
    });

    test('logs in again when Smartschool refuses the session for a removal, '
        'and removes the member once', () async {
      server.expireSessionBefore(
        (request) =>
            request.method == 'POST' && request.uri.path == fakeDeleteUserPath,
      );

      expect(
        await ok('remove_my_group_members', {
          'group_id': 900501,
          'members': ['Peeters Marie (user 900002)'],
        }),
        startsWith('Removed 1 member from your own group "Projectwerk 5A"'),
      );
      expect(server.logins, 2);
      expect(myGroups.writes, ['POST deleteUser 900501 900002']);
      expect(membersOf(900501), hasLength(2));
    });
  });

  test('the log of the member writes names no group and no one, only '
      'ids', () async {
    for (final (tool, arguments, line) in [
      (
        'add_my_group_members',
        <String, Object?>{
          'group_id': 900501,
          'people': ['Sven Lamber', 'Lien Dewit (user 900012)'],
        },
        'add_my_group_members: added 2 to own group 900501',
      ),
      (
        'add_my_group_members',
        <String, Object?>{
          'group_id': 900501,
          'people': ['Sven Lamber'],
        },
        'add_my_group_members: nothing to add to own group 900501',
      ),
      (
        'remove_my_group_members',
        <String, Object?>{
          'group_id': 900501,
          'members': ['Lamber Sven (user 900011)', 'Peeters Marie'],
        },
        'remove_my_group_members: removed 2 of 2 from own group 900501',
      ),
      (
        'add_my_group_members',
        <String, Object?>{
          'group_id': 900501,
          'people': ['Lien Dewit'],
        },
        'client: test',
      ),
    ]) {
      final (result, text, log) = await logged(tool, arguments);
      expect(log, contains(line), reason: tool);
      expect(text, isNotEmpty, reason: '$tool: ${result.isError}');
      for (final name in _names) {
        expect(log, isNot(contains(name)), reason: '$tool: $name');
      }
    }
  });
}
