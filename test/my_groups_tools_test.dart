/// The user's own mail groups, "Mijn groepen" (#231): `list_my_groups` and
/// `read_my_group`, called over MCP on the real server, session and
/// library, against a fake Smartschool whose "Mijn groepen" keeps own groups
/// and their members in the shapes of `MyGroupsService` (dartschool#251,
/// `test/support/fake_my_groups.dart`), and whose compose search finds them
/// as groups, so that a line of `list_my_groups` goes into `send_message`.
/// Made-up groups and people only (the fakes of `test/fixtures/lvs/FAKES.md`):
/// the members of a real group are mostly pupils.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:smartschool_mcp/src/tools/list_my_groups_tool.dart';
import 'package:smartschool_mcp/src/tools/read_my_group_tool.dart';
import 'package:smartschool_mcp/src/tools/send_message_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/log_capture.dart';
import 'support/mcp.dart';

const _otherSchool = 'Sint-Lodewijkscollege';

/// A group with three people of the own school, one of them without a
/// school name, and one of another school of the school group.
FakeMyGroup _projectwerk() => FakeMyGroup(
  900501,
  'Projectwerk 5A',
  description: 'Testvak informatica',
  members: [
    const FakeMyGroupMember(900002, 'Peeters Marie'),
    const FakeMyGroupMember(900001, 'Janssens Jan'),
    const FakeMyGroupMember(900003, 'Dupont Chloé', school: ''),
    const FakeMyGroupMember(
      900004,
      'Aerts An',
      platform: 5810,
      school: _otherSchool,
    ),
  ],
);

/// A group without members or description, whose name Smartschool's list
/// does not escape.
FakeMyGroup _empty() => FakeMyGroup(900502, 'Testgroep & "co"');

FakeMyGroup _zorg() => FakeMyGroup(
  900503,
  'zorgteam test',
  description: 'Testvak 2B',
  members: [const FakeMyGroupMember(900005, 'Dupré Céline')],
);

/// Every name of the fakes above, which the log must never hold.
const _names = [
  'Projectwerk',
  'Testgroep',
  'zorgteam',
  'Testvak',
  'Peeters',
  'Janssens',
  'Dupont',
  'Aerts',
  'Dupré',
  _otherSchool,
];

void main() {
  late FakeSmartschool server;
  late FakeMyGroups myGroups;
  late SmartschoolSession session;
  late ServerConnection connection;

  List<ServerTool> tools() => [
    listMyGroupsTool(session),
    readMyGroupTool(session),
    sendMessageTool(session),
  ];

  setUp(() async {
    server = FakeSmartschool();
    myGroups = server.myGroups;
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

  /// Calls [tool] as [logged] does, and expects an error result.
  Future<(String, String)> errorWithLog(
    String tool, [
    Map<String, Object?>? arguments,
  ]) async {
    final (result, text, log) = await logged(tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return (text, log);
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

  test('both only read, and read_my_group takes a group id', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    for (final name in ['list_my_groups', 'read_my_group']) {
      final annotations = tools[name]!.toolAnnotations!;
      expect(annotations.readOnlyHint, isTrue, reason: name);
      expect(annotations.idempotentHint, isTrue, reason: name);
      expect(annotations.destructiveHint, isNot(true), reason: name);
      expect(tools[name]!.description, contains('"Mijn groepen"'));
    }
    expect(
      tools['list_my_groups']!.description,
      allOf(
        contains('A message to one goes to all its members.'),
        contains('in their Smartschool profile, under "Mijn groepen"'),
        contains('pass what comes before the "|" to send_message'),
      ),
    );
    final schema = tools['read_my_group']!.inputSchema;
    expect(schema.properties!.keys, ['group_id']);
    expect(schema.required, ['group_id']);
  });

  group('list_my_groups', () {
    test('says when there are none', () async {
      expect(
        await ok('list_my_groups'),
        'You have no own groups ("Mijn groepen"). The user makes them in '
        'their Smartschool profile, under "Mijn groepen".',
      );
      expect(myGroups.requests, ['GET main']);
    });

    test('lists each group by name, as send_message takes it, with its '
        'description after a "|", and reads nothing else', () async {
      myGroups.groups.addAll([_zorg(), _projectwerk(), _empty()]);

      expect(
        await ok('list_my_groups'),
        'You have 3 own groups ("Mijn groepen"); a message to one goes to '
        'all its members:\n'
        '- Projectwerk 5A (group 900501) | Testvak informatica\n'
        '- Testgroep & "co" (group 900502)\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      myGroups.groups.removeRange(1, 3);
      expect(
        await ok('list_my_groups'),
        'You have 1 own group ("Mijn groepen"); a message to one goes to all '
        'its members:\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.requests, ['GET main', 'GET main']);
      expect(myGroups.writes, isEmpty);
      expect(server.mailbox.composeForms, 0);
    });

    test('a group as it lists it goes into send_message as it is, and the '
        'message goes to the group', () async {
      myGroups.groups.addAll([_projectwerk(), _empty()]);
      final lines = (await ok('list_my_groups')).split('\n').skip(1);

      for (final line in lines) {
        final reference = line.substring(2).split(' | ').first;
        final text = await ok('send_message', {
          'to': [reference],
          'subject': 'Test',
          'body': 'Een test.',
        });
        expect(text, startsWith('Sent the message.\n'), reason: reference);
      }

      expect(
        [
          for (final action in server.mailbox.actions)
            if (action.startsWith('send ')) action,
        ],
        [
          'send to=Projectwerk 5A (group) cc= bcc= subject=Test',
          'send to=Testgroep & "co" (group) cc= bcc= subject=Test',
        ],
      );
      expect(myGroups.writes, isEmpty);
    });

    test('an answer Smartschool gives that the library cannot use is an '
        'error in plain words, with the details in the log only', () async {
      myGroups.failing['main'] = 500;

      final (text, log) = await errorWithLog('list_my_groups');

      expect(
        text,
        'Smartschool gave an answer about your own groups ("Mijn groepen") '
        'that the server could not use (HTTP 500). Try again in a moment. If '
        'it keeps happening, look at the groups in Smartschool itself, under '
        '"Mijn groepen" in your profile; the details are in the server log.',
      );
      expect(log, contains('my groups: SmartschoolMyGroupsError(500)'));
    });

    test('logs in again when the session expired, and lists', () async {
      myGroups.groups.add(_projectwerk());
      await ok('list_my_groups');
      server.expireSession();

      expect(
        await ok('list_my_groups'),
        contains('- Projectwerk 5A (group 900501) | Testvak informatica'),
      );
      expect(server.logins, 2);
    });
  });

  group('read_my_group', () {
    setUp(() => myGroups.groups.addAll([_projectwerk(), _empty(), _zorg()]));

    test('lists the members by name with their user id, and the platform and '
        'school of a person of another school', () async {
      expect(
        await ok('read_my_group', {'group_id': 900501}),
        'Own group Projectwerk 5A (group 900501) | Testvak informatica\n'
        '4 members:\n'
        '- Aerts An (user 900004, platform 5810) | school: $_otherSchool\n'
        '- Dupont Chloé (user 900003)\n'
        '- Janssens Jan (user 900001)\n'
        '- Peeters Marie (user 900002)',
      );
      expect(myGroups.requests, [
        'GET main',
        'GET users 900501',
        'POST userSelect/get Items Selected mygroups_900501',
      ]);
      // The own school's platform, from a compose form left unused.
      expect(server.mailbox.composeForms, 1);
      expect(server.mailbox.submits, 0);
      expect(myGroups.writes, isEmpty);
    });

    test('takes the id as a whole number written with a decimal part, and '
        'says when a group has one member', () async {
      expect(
        await ok('read_my_group', {'group_id': 900503.0}),
        'Own group zorgteam test (group 900503) | Testvak 2B\n'
        '1 member:\n'
        '- Dupré Céline (user 900005)',
      );
    });

    test('says when a group has no members, without loading a compose '
        'form', () async {
      expect(
        await ok('read_my_group', {'group_id': 900502}),
        'Own group Testgroep & "co" (group 900502)\n'
        'It has no members: the user adds people in their Smartschool '
        'profile, under "Mijn groepen".',
      );
      expect(server.mailbox.composeForms, 0);
    });

    test('refuses an id that is not one of the user\'s groups, with the '
        'groups there are, before reading any members', () async {
      expect(
        await error('read_my_group', {'group_id': 298}),
        'You have no own group with id 298 (any more). Nothing was sent. '
        'Your own groups:\n'
        '- Projectwerk 5A (group 900501) | Testvak informatica\n'
        '- Testgroep & "co" (group 900502)\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.requests, ['GET main']);

      myGroups.groups.clear();
      expect(
        await error('read_my_group', {'group_id': 900501}),
        'You have no own group with id 900501 (any more). Nothing was sent. '
        'You have no own groups: the user makes them in their Smartschool '
        'profile, under "Mijn groepen".',
      );
    });

    test('a group deleted after the list was read is refused with the '
        'groups there are then', () async {
      myGroups.beforeAnswer = (request) {
        if (request == 'GET users 900501') {
          myGroups.groups.removeWhere((group) => group.id == 900501);
        }
      };

      expect(
        await error('read_my_group', {'group_id': 900501}),
        'You have no own group with id 900501 (any more). Nothing was sent. '
        'Your own groups:\n'
        '- Testgroep & "co" (group 900502)\n'
        '- zorgteam test (group 900503) | Testvak 2B',
      );
      expect(myGroups.requests, ['GET main', 'GET users 900501', 'GET main']);
    });

    test('an id that is not a whole number is refused before anything is '
        'sent', () async {
      expect(
        await error('read_my_group', {'group_id': 900501.5}),
        contains('is not an integer'),
      );
      expect(myGroups.requests, isEmpty);
    });

    for (final (route, status) in [('users', 500), ('picker', 503)]) {
      test('an answer of the $route the library cannot use is an error in '
          'plain words; the log names no group or member', () async {
        myGroups.failing[route] = status;

        final (text, log) = await errorWithLog('read_my_group', {
          'group_id': 900501,
        });

        expect(
          text,
          startsWith(
            'Smartschool gave an answer about your own groups ("Mijn '
            'groepen") that the server could not use (HTTP $status). Try '
            'again in a moment.',
          ),
        );
        expect(log, contains('my groups: SmartschoolMyGroupsError($status)'));
        for (final name in _names) {
          expect(log, isNot(contains(name)), reason: name);
        }
      });
    }

    test('a picker answer that is an HTML page is an unexpected problem, as '
        'for every tool, and only its type is logged', () async {
      myGroups.failing['picker'] = 200;

      final (text, log) = await errorWithLog('read_my_group', {
        'group_id': 900501,
      });

      expect(
        text,
        startsWith(
          'Talking to Smartschool failed with an unexpected error. Try again '
          'in a moment.',
        ),
      );
      expect(
        log,
        contains(
          'Smartschool problem (unexpected): SmartschoolUnexpectedPageError\n',
        ),
      );
      for (final name in _names) {
        expect(log, isNot(contains(name)), reason: name);
      }
    });

    test(
      'a members page answered with another page is the same error',
      () async {
        myGroups.failing['users'] = 200;

        final (text, log) = await errorWithLog('read_my_group', {
          'group_id': 900501,
        });

        expect(text, contains('that the server could not use. Try again'));
        expect(log, contains('my groups: SmartschoolMyGroupsError: '));
      },
    );

    test('logs in again when the session expired before the picker\'s '
        'request, loads the members page again and reads the members once '
        'more', () async {
      server.expireSessionBefore(
        (request) =>
            request.uri.queryParameters['module'] == 'Userselect' &&
            request.method == 'POST',
      );

      final text = await ok('read_my_group', {'group_id': 900501});

      expect(text, contains('4 members:'));
      expect(server.logins, 2);
      expect(myGroups.requests, [
        'GET main',
        'GET users 900501',
        'GET users 900501',
        'POST userSelect/get Items Selected mygroups_900501',
      ]);
    });

    test('the log of a list and a read names no group or member', () async {
      for (final (tool, arguments) in [
        ('list_my_groups', <String, Object?>{}),
        ('read_my_group', <String, Object?>{'group_id': 900501}),
      ]) {
        final (result, text, log) = await logged(tool, arguments);
        expect(result.isError, isNot(true), reason: text);
        expect(text, contains('Projectwerk 5A'), reason: tool);
        // The log of the server that handled the call was captured.
        expect(log, contains('client: test'), reason: tool);
        for (final name in _names) {
          expect(log, isNot(contains(name)), reason: '$tool: $name');
        }
      }
    });
  });
}
