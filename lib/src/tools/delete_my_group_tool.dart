import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/my_groups.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `delete_my_group`: deletes one of the user's own mail groups ("Mijn
/// groepen", `MyGroupsService.delete`, dartschool#252), by its id from
/// `list_my_groups`, with its member list (#232). An own group does not go
/// to a trash: it is gone.
///
/// Marked destructive for approval; not idempotent, as #232 marks all three
/// writes of an own group. Before anything is sent, the id is checked
/// against the list of own groups ([findMyGroup], which lists the groups
/// there are). The library sends the delete once and confirms it by
/// Smartschool's answer, the list without the group; a delete it cannot
/// confirm is reported as maybe deleted ([myGroupWriteNotConfirmed]).
ServerTool deleteMyGroupTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'delete_my_group',
    title: 'Delete an own Smartschool mail group',
    description:
        'Deletes one of the user\'s own groups in Smartschool ("Mijn '
        'groepen"), by its id from list_my_groups, with its member list. '
        'This cannot be undone: an own group does not go to a trash. Before '
        'calling this tool, show the user the group by name with its number '
        'of members (read_my_group gives them), say that it cannot be '
        'undone, and only call this tool after the user has explicitly '
        'confirmed it. An id that is not one of the user\'s groups is '
        'refused, and nothing is deleted. If the result says it may or may '
        'not have been deleted, do not call this tool again: check with '
        'list_my_groups, and tell the user. For requests like "verwijder '
        'mijn groep Reis Parijs".',
    inputSchema: Schema.object(
      properties: {'group_id': myGroupIdSchema()},
      required: ['group_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Delete an own Smartschool mail group',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _delete(session, request.arguments ?? const {}),
);

Future<CallToolResult> _delete(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  const nothingDeleted = 'Nothing was deleted.';
  final id = requiredIntArgument(arguments, 'group_id');
  late MyGroup group;
  try {
    await withMyGroupWrite(
      session,
      (groups) async {
        group = findMyGroup(await groups.list(), id);
        try {
          await groups.delete(group);
        } on SmartschoolMyGroupNotFoundError {
          // Gone before the delete: deleted meanwhile, elsewhere.
          throw unknownMyGroup(
            await groups.list(),
            id,
            nothingDone: nothingDeleted,
          );
        }
      },
      what: 'the delete of own group $id',
      nothingDone: nothingDeleted,
    );
  } on SmartschoolMyGroupSaveUnconfirmedError catch (error) {
    return myGroupWriteNotConfirmed(
      tool: 'delete_my_group',
      what: 'Your own group "${group.name}" (group $id)',
      done: 'deleted',
      check: 'to see whether it is still there',
      error: error,
    );
  }
  log('delete_my_group: deleted own group $id');
  return CallToolResult(
    content: [
      TextContent(
        text:
            'Deleted your own group "${group.name}" (group $id), with its '
            'member list. It is gone: an own group has no trash, and '
            'send_message no longer finds it.',
      ),
    ],
  );
}
