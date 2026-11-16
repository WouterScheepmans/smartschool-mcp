import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/my_groups.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `edit_my_group`: changes the name, the description or both of one of
/// the user's own mail groups ("Mijn groepen", `MyGroupsService.update`,
/// dartschool#252), by its id from `list_my_groups` (#232). What is left
/// out stays; an empty description empties it.
///
/// Marked destructive, as the other writes of the server are, for Claude
/// Desktop and Codex to ask approval; not idempotent, as #232 marks all
/// three writes of an own group. Before anything is sent, the id is
/// checked against the list of own groups ([findMyGroup], which lists the
/// groups there are) and a new name as `create_my_group` checks one. The
/// library sends the save once and confirms it in the list after it; a
/// save it cannot confirm is reported as maybe saved
/// ([myGroupWriteNotConfirmed]).
ServerTool editMyGroupTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'edit_my_group',
    title: 'Change an own Smartschool mail group',
    description:
        'Changes the name, the description or both of one of the user\'s '
        'own groups in Smartschool ("Mijn groepen"), by its id from '
        'list_my_groups. What is left out stays as it is; an empty '
        'description removes the description. Both are plain text '
        '(Smartschool removes tags). The members stay. Before calling this '
        'tool, show the user the group by its current name and what '
        'changes, and only call this tool after the user has explicitly '
        'confirmed it. An empty name, a name that another own group has '
        'already, and an id that is not one of the user\'s groups are '
        'refused, and nothing is changed. After a new name, send_message '
        'takes the group by that name. If the result says the change may or '
        'may not have been saved, do not call this tool again: check with '
        'list_my_groups, and tell the user. For requests like "hernoem mijn '
        'groep Projectwerk naar Projectwerk 6".',
    inputSchema: Schema.object(
      properties: {
        'group_id': myGroupIdSchema(),
        'name': Schema.string(
          description:
              'The new name, as the user confirmed it: plain text, not the '
              'name of another own group. Leave it out to keep the name.',
          minLength: 1,
        ),
        'description': Schema.string(
          description:
              'The new description, as the user confirmed it: plain text; '
              'empty to remove the description. Leave it out to keep it.',
        ),
      },
      required: ['group_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Change an own Smartschool mail group',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _edit(session, request.arguments ?? const {}),
);

Future<CallToolResult> _edit(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  const nothingChanged = 'Nothing was changed.';
  final id = requiredIntArgument(arguments, 'group_id');
  final name = arguments['name'] == null
      ? null
      : myGroupNameArgument(arguments['name']);
  final description = myGroupDescriptionArgument(arguments['description']);
  if (name == null && description == null) {
    throw const ToolError(
      'Give a new name, a new description or both: there is nothing to '
      'change. $myGroupNothingSent',
    );
  }
  late MyGroup before;
  final MyGroup saved;
  try {
    saved = await withMyGroupWrite(
      session,
      (groups) async {
        final all = await groups.list();
        before = findMyGroup(all, id);
        if (name != null) checkMyGroupNameFree(all, name, except: id);
        try {
          return await groups.update(
            before,
            name: name,
            description: description,
          );
        } on SmartschoolMyGroupNotFoundError {
          // Deleted since the list was read: its edit form was the list.
          throw unknownMyGroup(
            await groups.list(),
            id,
            nothingDone: nothingChanged,
          );
        }
      },
      what: 'the change of own group $id',
      nothingDone: nothingChanged,
    );
  } on SmartschoolMyGroupSaveUnconfirmedError catch (error) {
    return myGroupWriteNotConfirmed(
      tool: 'edit_my_group',
      what: 'The change of your own group "${before.name}" (group $id)',
      done: 'saved',
      check: 'to see its name and description now',
      error: error,
    );
  }
  log('edit_my_group: changed own group $id');
  final savedDescription = saved.description.trim();
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Changed your own group "${before.name}" (group $id).',
          'Name: ${saved.name}',
          'Description: ${savedDescription.isEmpty ? 'none' : savedDescription}',
          'send_message takes it as "${myGroupReference(saved)}".',
        ].join('\n'),
      ),
    ],
  );
}
