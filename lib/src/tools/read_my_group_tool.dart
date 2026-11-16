import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/my_groups.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `read_my_group`: the members of one of the user's own mail groups
/// ("Mijn groepen", `MyGroupsService.members`, dartschool#251), by its id
/// from `list_my_groups`, one line each with the user id, and the school of
/// a person of another school ([formatMyGroupMembers], #231). Only reads:
/// the list of own groups (to check the id), the group's members page and
/// the member picker's selection, and a compose form for the own school's
/// platform ([ownPlatform]).
ServerTool readMyGroupTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_my_group',
    title: 'Read an own Smartschool mail group',
    description:
        'Reads who is in one of the user\'s own groups in Smartschool ("Mijn '
        'groepen"), by its id from list_my_groups: each member by name (last '
        'name first, as Smartschool shows them) with "(user <id>)", and for '
        'a person of another school of the school group also the platform '
        'and their school. A message to the group goes to all of them. '
        'Reading changes nothing in Smartschool. For requests like "wie zit '
        'er in mijn groep Projectwerk?".',
    inputSchema: Schema.object(
      properties: {'group_id': myGroupIdSchema()},
      required: ['group_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Read an own Smartschool mail group',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final id = requiredIntArgument(request.arguments ?? const {}, 'group_id');
    final text = await withMyGroups(session, (groups, client) async {
      final all = await groups.list();
      final group = findMyGroup(all, id);
      final List<MyGroupMember> members;
      try {
        members = await groups.members(group);
      } on SmartschoolMyGroupNotFoundError {
        // Deleted since the list was read.
        throw unknownMyGroup(await groups.list(), id);
      }
      return formatMyGroupMembers(
        group,
        members,
        ownPlatform: members.isEmpty ? null : await ownPlatform(client),
      );
    });
    return CallToolResult(content: [TextContent(text: text)]);
  },
);
