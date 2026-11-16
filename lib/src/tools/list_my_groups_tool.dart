import 'package:dart_mcp/server.dart';

import '../messages/my_groups.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_my_groups`: the user's own mail groups ("Mijn groepen" in the
/// Smartschool profile, `MyGroupsService.list`, dartschool#251), one line
/// each as `send_message` takes a group, with its description
/// ([formatMyGroups], #231). Only reads.
ServerTool listMyGroupsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_my_groups',
    title: 'List the own Smartschool mail groups',
    description:
        'Lists the user\'s own groups in Smartschool ("Mijn groepen"): '
        'groups of people the user keeps and manages $myGroupsInProfile. A '
        'message to one goes to all its members. Lists each group as '
        'send_message takes it, like "Projectwerk (group 298)", then after a '
        '"|" its '
        'description; pass what comes before the "|" to send_message. Read '
        'who is in a group with read_my_group. Listing changes nothing in '
        'Smartschool. For requests like "welke eigen groepen heb ik?" or '
        '"stuur dit naar mijn groep Projectwerk".',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(
      title: 'List the own Smartschool mail groups',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final groups = await withMyGroups(
      session,
      (groups, client) => groups.list(),
    );
    return CallToolResult(content: [TextContent(text: formatMyGroups(groups))]);
  },
);
