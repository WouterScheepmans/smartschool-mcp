import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/my_groups.dart';
import '../session.dart';
import 'server_tool.dart';

/// `create_my_group`: makes an own mail group of the user ("Mijn groepen"
/// in the Smartschool profile, `MyGroupsService.create`, dartschool#252),
/// with a name and a description, and gives it as `send_message` takes it
/// (#232).
///
/// Marked destructive, as the other writes of the server are, for Claude
/// Desktop and Codex to ask approval; not idempotent: it makes a group. The
/// name is checked before anything is sent: not empty
/// ([myGroupNameArgument]), and not the name of another own group, which is
/// named ([checkMyGroupNameFree]). The library sends the save once, never
/// again after logging in again, and confirms it in the list after it; a
/// save it cannot confirm is reported as maybe made
/// ([myGroupWriteNotConfirmed]).
ServerTool createMyGroupTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'create_my_group',
    title: 'Make an own Smartschool mail group',
    description:
        'Makes a new own group of the user in Smartschool ("Mijn groepen"): '
        'a group of people the user keeps $myGroupsInProfile, to send '
        'messages to. It gets a name and optionally a description, both '
        'plain text (Smartschool removes tags), and has no members yet. '
        'Before calling this tool, show the user the name and the '
        'description, and only call this tool after the user has explicitly '
        'confirmed it. An empty name, or one that another own group has '
        'already, is refused, and nothing is made. The result gives the '
        'group as send_message takes it, like "Projectwerk (group 298)". If '
        'the result says it may or may not have been made, do not call this '
        'tool again: check with list_my_groups, and tell the user. For '
        'requests like "maak een groep Reis Parijs".',
    inputSchema: Schema.object(
      properties: {
        'name': Schema.string(
          description:
              'The name of the group, as the user confirmed it: plain text, '
              'not the name of another own group.',
          minLength: 1,
        ),
        'description': Schema.string(
          description:
              'The description of the group, as the user confirmed it: '
              'plain text. Default: none.',
        ),
      },
      required: ['name'],
    ),
    annotations: ToolAnnotations(
      title: 'Make an own Smartschool mail group',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _create(session, request.arguments ?? const {}),
);

Future<CallToolResult> _create(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final name = myGroupNameArgument(arguments['name']);
  final description = myGroupDescriptionArgument(arguments['description']);
  final MyGroup group;
  try {
    group = await withMyGroupWrite(
      session,
      (groups) async {
        checkMyGroupNameFree(await groups.list(), name);
        return groups.create(name: name, description: description ?? '');
      },
      what: 'the new own group "$name"',
      nothingDone: 'No group was made.',
    );
  } on SmartschoolMyGroupSaveUnconfirmedError catch (error) {
    return myGroupWriteNotConfirmed(
      tool: 'create_my_group',
      what: 'Your own group "$name"',
      done: 'made',
      check: 'to see whether it is there',
      error: error,
    );
  }
  log('create_my_group: made own group ${group.id}');
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Made your own group ${myGroupListing(group)}.',
          'Send a message to it with send_message, as '
              '"${myGroupReference(group)}". It has no members yet: the user '
              'adds people $myGroupsInProfile.',
        ].join('\n'),
      ),
    ],
  );
}
