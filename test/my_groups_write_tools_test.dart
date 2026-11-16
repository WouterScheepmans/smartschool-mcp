/// The writes of the user's own mail groups, "Mijn groepen" (#232):
/// `create_my_group`, `edit_my_group` and `delete_my_group`, called over MCP
/// on the real server, session and library, against the fake "Mijn groepen"
/// of #231 (`test/support/fake_my_groups.dart`), which serves the form of a
/// group, its save and its delete as `MyGroupsService` documents them
/// (dartschool#252). A made group goes into `send_message` as the result
/// gives it. Made-up groups and people only (the fakes of
/// `test/fixtures/lvs/FAKES.md`): the members of a real group are mostly
/// pupils.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/create_my_group_tool.dart';
import 'package:smartschool_mcp/src/tools/delete_my_group_tool.dart';
import 'package:smartschool_mcp/src/tools/edit_my_group_tool.dart';
import 'package:smartschool_mcp/src/tools/list_my_groups_tool.dart';
import 'package:smartschool_mcp/src/tools/read_my_group_tool.dart';
import 'package:smartschool_mcp/src/tools/send_message_tool.dart';
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
  ],
);

FakeMyGroup _zorg() =>
    FakeMyGroup(900503, 'zorgteam test', description: 'Testvak 2B');

/// Every name of the fakes and the tests, which the log must never hold.
const _names = [
  'Projectwerk',
  'zorgteam',
  'Testvak',
  'Peeters',
  'Janssens',
  'Reis',
  'Parijs',
  'dartschool test',
];

/// What every write says when it went out without Smartschool confirming
/// it, after "may or may not have been ...".
String _notConfirmed(String tool, String check) =>
    ': it was sent, but Smartschool did not confirm it. Do not call $tool '
    'again for it. First list your own groups with list_my_groups $check. '
    'Then tell the user what you found.';

void main() {
  late FakeSmartschool server;
  late FakeMyGroups myGroups;
  late SmartschoolSession session;
  late ServerConnection connection;

  List<ServerTool> tools() => [
    listMyGroupsTool(session),
    readMyGroupTool(session),
    createMyGroupTool(session),
    editMyGroupTool(session),
    deleteMyGroupTool(session),
    sendMessageTool(session),
  ];

  setUp(() async {
    server = FakeSmartschool();
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

  /// The own groups of the fake, as `name | description` by id.
  Map<int, String> stored() => {
    for (final group in myGroups.groups)
      group.id: '${group.name} | ${group.description}',
  };

  test('all three are writes the client asks approval for, after Claude '
      'showed what changes', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    for (final name in [
      'create_my_group',
      'edit_my_group',
      'delete_my_group',
    ]) {
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
          contains('do not call this tool again: check with list_my_groups'),
        ),
        reason: name,
      );
    }
    expect(
      tools['create_my_group']!.description,
      contains('show the user the name and the description'),
    );
    expect(
      tools['edit_my_group']!.description,
      contains('show the user the group by its current name and what changes'),
    );
    expect(
      tools['delete_my_group']!.description,
      allOf(
        contains('This cannot be undone: an own group does not go to a trash'),
        contains('show the user the group by name with its number of members'),
        contains('say that it cannot be undone'),
      ),
    );
    final create = tools['create_my_group']!.inputSchema;
    expect(create.properties!.keys, ['name', 'description']);
    expect(create.required, ['name']);
    final edit = tools['edit_my_group']!.inputSchema;
    expect(edit.properties!.keys, ['group_id', 'name', 'description']);
    expect(edit.required, ['group_id']);
    final delete = tools['delete_my_group']!.inputSchema;
    expect(delete.properties!.keys, ['group_id']);
    expect(delete.required, ['group_id']);
  });

  test('a throwaway group is made, sent to, renamed, given a description and '
      'deleted again, and each step is in the list', () async {
    expect(
      await ok('create_my_group', {'name': 'dartschool test'}),
      'Made your own group dartschool test (group 900601).\n'
      'Send a message to it with send_message, as "dartschool test (group '
      '900601)". It has no members yet: the user adds people in their '
      'Smartschool profile, under "Mijn groepen".',
    );
    expect(
      await ok('list_my_groups'),
      contains('\n- dartschool test (group 900601)\n'),
    );
    expect(
      await ok('send_message', {
        'to': ['dartschool test (group 900601)'],
        'subject': 'Test',
        'body': 'Een test.',
      }),
      startsWith('Sent the message.\n'),
    );

    expect(
      await ok('edit_my_group', {
        'group_id': 900601,
        'name': 'dartschool test 2',
        'description': 'Reis Parijs',
      }),
      'Changed your own group "dartschool test" (group 900601).\n'
      'Name: dartschool test 2\n'
      'Description: Reis Parijs\n'
      'send_message takes it as "dartschool test 2 (group 900601)".',
    );
    expect(
      await ok('list_my_groups'),
      contains('\n- dartschool test 2 (group 900601) | Reis Parijs\n'),
    );

    expect(
      await ok('delete_my_group', {'group_id': 900601}),
      'Deleted your own group "dartschool test 2" (group 900601), with its '
      'member list. It is gone: an own group has no trash, and send_message '
      'no longer finds it.',
    );
    expect(await ok('list_my_groups'), isNot(contains('dartschool test')));
    expect(stored().keys, [900501, 900503]);

    expect(myGroups.writes, [
      'POST addedit',
      'POST addedit 900601',
      'GET delete 900601',
    ]);
    expect(
      [
        for (final action in server.mailbox.actions)
          if (action.startsWith('send ')) action,
      ],
      ['send to=dartschool test (group) cc= bcc= subject=Test'],
    );
  });

  group('create_my_group', () {
    test('makes a group with a description, reading the list and the form '
        'first, and saves it once', () async {
      expect(
        await ok('create_my_group', {
          'name': '  Reis Parijs ',
          'description': ' Testvak informatica 6 ',
        }),
        startsWith(
          'Made your own group Reis Parijs (group 900601) | Testvak '
          'informatica 6.\n',
        ),
      );
      expect(myGroups.requests, [
        'GET main',
        'GET main',
        'GET addedit',
        'POST addedit',
        'GET main',
      ]);
      expect(myGroups.saves.single, {
        '_csrf_token': isNotEmpty,
        'store': '1',
        'name': 'Reis Parijs',
        'desc': 'Testvak informatica 6',
      });
      expect(stored()[900601], 'Reis Parijs | Testvak informatica 6');
    });

    test('a name and a description are plain text: the result gives the '
        'group as Smartschool saved it, without tags', () async {
      expect(
        await ok('create_my_group', {
          'name': 'Reis <b>Parijs</b>',
          'description': '<i>Testvak</i> & meer',
        }),
        startsWith(
          'Made your own group Reis Parijs (group 900601) | Testvak & meer.\n',
        ),
      );
    });

    for (final (name, refusal) in [
      ('   ', 'name is empty: an own group needs a name'),
      ('<b> </b>', 'name "<b> </b>" has no text outside its tags'),
    ]) {
      test('refuses the name "$name" before anything is sent', () async {
        expect(
          await error('create_my_group', {'name': name}),
          allOf(startsWith(refusal), endsWith(' Nothing was sent.')),
        );
        expect(server.requests, isEmpty);
      });
    }

    test('refuses a name another own group has already, naming that group, '
        'after reading the list only', () async {
      for (final name in ['Projectwerk 5A', ' Projectwerk <i>5A</i>']) {
        expect(
          await error('create_my_group', {'name': name}),
          'Your own group Projectwerk 5A (group 900501) has that name '
          'already: two own groups with one name cannot be told apart in '
          'search_recipients and send_message. Ask the user for another '
          'name. Nothing was sent.',
          reason: name,
        );
      }
      expect(myGroups.requests, ['GET main', 'GET main']);
      expect(myGroups.writes, isEmpty);
    });

    test('a save whose answer does not come in may or may not have made the '
        'group: not sent again, and the log names no group', () async {
      myGroups.dropping.add('save');

      final (result, text, log) = await logged('create_my_group', {
        'name': 'Reis Parijs',
      });

      expect(result.isError, isTrue);
      expect(
        text,
        'Your own group "Reis Parijs" may or may not have been made'
        '${_notConfirmed('create_my_group', 'to see whether it is there')}',
      );
      expect(myGroups.writes, ['POST addedit']);
      // It was made: list_my_groups shows it.
      expect(
        await ok('list_my_groups'),
        contains('Reis Parijs (group 900601)'),
      );
      expect(
        log,
        contains(
          'create_my_group: Smartschool did not confirm the write, not '
          'retrying (no answer: ',
        ),
      );
      for (final name in _names) {
        expect(log, isNot(contains(name)), reason: name);
      }
    });

    test('a save answered with an error is not confirmed either', () async {
      myGroups.failing['save'] = 500;

      final (result, text, log) = await logged('create_my_group', {
        'name': 'Reis Parijs',
      });

      expect(result.isError, isTrue);
      expect(text, startsWith('Your own group "Reis Parijs" may or may not'));
      expect(log, contains('not retrying (HTTP 500)'));
      expect(myGroups.writes, ['POST addedit']);
    });

    test('logs in again when Smartschool refuses the session for the save, '
        'and makes the group once', () async {
      server.expireSessionBefore(
        (request) =>
            request.method == 'POST' &&
            request.uri.queryParameters['function'] == 'addedit',
      );

      expect(
        await ok('create_my_group', {'name': 'Reis Parijs'}),
        startsWith('Made your own group Reis Parijs (group 900601).\n'),
      );
      expect(server.logins, 2);
      expect(server.refusedPosts, ['401 /']);
      // The refused save never reached "Mijn groepen"; the second did.
      expect(myGroups.writes, ['POST addedit']);
      expect(stored().keys, [900501, 900503, 900601]);
    });

    test('a form Smartschool answers with an error is an error in plain '
        'words: nothing was made', () async {
      myGroups.failing['form'] = 500;

      expect(
        await error('create_my_group', {'name': 'Reis Parijs'}),
        allOf(
          startsWith(
            'Smartschool gave an answer about your own groups ("Mijn '
            'groepen") that the server could not use (HTTP 500).',
          ),
          endsWith(' No group was made.'),
        ),
      );
      expect(myGroups.writes, isEmpty);
    });
  });

  group('edit_my_group', () {
    test('renames a group and changes its description, keeping its '
        'members', () async {
      expect(
        await ok('edit_my_group', {
          'group_id': 900501,
          'name': 'Projectwerk 6',
          'description': 'Reis Parijs',
        }),
        'Changed your own group "Projectwerk 5A" (group 900501).\n'
        'Name: Projectwerk 6\n'
        'Description: Reis Parijs\n'
        'send_message takes it as "Projectwerk 6 (group 900501)".',
      );
      expect(myGroups.requests, [
        'GET main',
        'GET main',
        'GET addedit 900501',
        'POST addedit 900501',
        'GET main',
      ]);
      expect(stored()[900501], 'Projectwerk 6 | Reis Parijs');
      expect(myGroups.groups.first.members, hasLength(2));
    });

    test('keeps what is left out, and an empty description removes '
        'it', () async {
      expect(
        await ok('edit_my_group', {'group_id': 900501, 'description': 'Reis'}),
        contains('Name: Projectwerk 5A\nDescription: Reis\n'),
      );
      expect(myGroups.saves.last['name'], 'Projectwerk 5A');

      expect(
        await ok('edit_my_group', {'group_id': 900501, 'name': 'Projectwerk'}),
        contains('Name: Projectwerk\nDescription: Reis\n'),
      );
      expect(myGroups.saves.last['desc'], 'Reis');

      expect(
        await ok('edit_my_group', {'group_id': 900501, 'description': ''}),
        contains('Name: Projectwerk\nDescription: none\n'),
      );
      expect(stored()[900501], 'Projectwerk | ');
    });

    test('takes the group\'s own name, but refuses the name of another own '
        'group, naming it', () async {
      expect(
        await ok('edit_my_group', {
          'group_id': 900501,
          'name': 'Projectwerk 5A',
          'description': 'Reis',
        }),
        contains('Name: Projectwerk 5A\nDescription: Reis\n'),
      );
      myGroups.requests.clear();

      expect(
        await error('edit_my_group', {
          'group_id': 900503,
          'name': 'Projectwerk 5A',
        }),
        startsWith(
          'Your own group Projectwerk 5A (group 900501) has that name '
          'already',
        ),
      );
      expect(myGroups.requests, ['GET main']);
    });

    test('refuses a call that changes nothing, and an empty name, before '
        'anything is sent', () async {
      expect(
        await error('edit_my_group', {'group_id': 900501}),
        'Give a new name, a new description or both: there is nothing to '
        'change. Nothing was sent.',
      );
      expect(
        await error('edit_my_group', {'group_id': 900501, 'name': ' '}),
        startsWith('name is empty'),
      );
      expect(server.requests, isEmpty);
    });

    test('refuses an id that is not one of the user\'s groups, with the '
        'groups there are, before anything is sent', () async {
      expect(
        await error('edit_my_group', {'group_id': 298, 'name': 'Reis'}),
        'You have no own group with id 298 (any more). Nothing was sent. '
        'Your own groups:\n'
        '- Projectwerk 5A (group 900501) | Testvak informatica\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.requests, ['GET main']);
    });

    test('a group deleted before its edit form is refused with the groups '
        'there are then', () async {
      myGroups.beforeAnswer = (request) {
        if (request == 'GET addedit 900501') {
          myGroups.groups.removeWhere((group) => group.id == 900501);
        }
      };

      expect(
        await error('edit_my_group', {'group_id': 900501, 'name': 'Reis'}),
        'You have no own group with id 900501 (any more). Nothing was '
        'changed. Your own groups:\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.writes, isEmpty);
    });

    test('a save whose answer does not come in may or may not have been '
        'saved: not sent again', () async {
      myGroups.dropping.add('save');

      expect(
        await error('edit_my_group', {'group_id': 900501, 'name': 'Reis'}),
        'The change of your own group "Projectwerk 5A" (group 900501) may or '
        'may not have been saved'
        '${_notConfirmed('edit_my_group', 'to see its name and description now')}',
      );
      expect(myGroups.writes, ['POST addedit 900501']);
    });
  });

  group('delete_my_group', () {
    test('deletes a group with its member list, after reading the list '
        'only', () async {
      expect(
        await ok('delete_my_group', {'group_id': 900501}),
        'Deleted your own group "Projectwerk 5A" (group 900501), with its '
        'member list. It is gone: an own group has no trash, and send_message '
        'no longer finds it.',
      );
      expect(myGroups.requests, ['GET main', 'GET main', 'GET delete 900501']);
      expect(stored().keys, [900503]);
    });

    test('refuses an id that is not one of the user\'s groups, with the '
        'groups there are, before anything is sent', () async {
      expect(
        await error('delete_my_group', {'group_id': 298}),
        'You have no own group with id 298 (any more). Nothing was sent. '
        'Your own groups:\n'
        '- Projectwerk 5A (group 900501) | Testvak informatica\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.writes, isEmpty);
    });

    test('a group deleted elsewhere just before the delete: nothing was '
        'deleted, with the groups there are', () async {
      myGroups.beforeAnswer = (request) {
        if (request == 'GET delete 900501') {
          myGroups.groups.removeWhere((group) => group.id == 900501);
        }
      };

      expect(
        await error('delete_my_group', {'group_id': 900501}),
        'You have no own group with id 900501 (any more). Nothing was '
        'deleted. Your own groups:\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.writes, ['GET delete 900501']);
    });

    for (final (what, setUpFailure, log) in [
      (
        'whose answer does not come in',
        (FakeMyGroups groups) => groups.dropping.add('delete'),
        'not retrying (no answer: ',
      ),
      (
        'answered with an error',
        (FakeMyGroups groups) => groups.failing['delete'] = 500,
        'not retrying (HTTP 500)',
      ),
    ]) {
      test('a delete $what may or may not have been made: not sent again, '
          'and the log names no group', () async {
        setUpFailure(myGroups);

        final (result, text, logText) = await logged('delete_my_group', {
          'group_id': 900501,
        });

        expect(result.isError, isTrue);
        expect(
          text,
          'Your own group "Projectwerk 5A" (group 900501) may or may not have '
          'been deleted'
          '${_notConfirmed('delete_my_group', 'to see whether it is still there')}',
        );
        expect(myGroups.writes, ['GET delete 900501']);
        expect(logText, contains('delete_my_group: Smartschool did not '));
        expect(logText, contains(log));
        for (final name in _names) {
          expect(logText, isNot(contains(name)), reason: name);
        }
      });
    }
  });

  test('the log of the writes names no group, only ids', () async {
    for (final (tool, arguments, line) in [
      (
        'create_my_group',
        <String, Object?>{'name': 'Reis Parijs', 'description': 'Testvak'},
        'create_my_group: made own group 900601',
      ),
      (
        'edit_my_group',
        <String, Object?>{'group_id': 900601, 'name': 'dartschool test'},
        'edit_my_group: changed own group 900601',
      ),
      (
        'delete_my_group',
        <String, Object?>{'group_id': 900601},
        'delete_my_group: deleted own group 900601',
      ),
      (
        'create_my_group',
        <String, Object?>{'name': 'Projectwerk 5A'},
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
