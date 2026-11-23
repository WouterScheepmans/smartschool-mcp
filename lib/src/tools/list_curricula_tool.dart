import 'package:dart_mcp/server.dart';

import '../goals/goals.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_curricula`: the curricula of Smartschool's goal selector
/// (`GoalService.getCurricula`, dartschool#222), in its groups, as
/// [formatCurricula] lists them (#186); with `source` `go_navigator`, those
/// of the GO! Navigator ([goalSource]), each with its grade.
ServerTool listCurriculaTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_curricula',
    title: 'List the Smartschool curricula of learning goals',
    description:
        'Lists the curricula of learning goals that Smartschool\'s goal '
        'selector offers for lesfiches and lessons, in its groups and order: '
        'such as Overheid SO (the eindtermen per grade and finality), '
        'Levensbeschouwing SO (the curricula of the philosophies of life), '
        'Andere SO and Minidatabanken (the school\'s own mini-databases). '
        'With source go_navigator, the curricula of the GO! instead (the '
        '"GO! Navigator" tab of a lesfiche\'s goals, for GO! schools: the '
        'leerplannen per grade and study option). '
        'One line per curriculum: its title, its grade (GO! Navigator), '
        'whether it is hidden in the selector or a favourite, and its id. '
        'Filter with query (words in the title or the grade, like "wiskunde '
        'derde graad"). read_curriculum reads the goals of one, by that id '
        'and the same source; '
        'read_lesfiche and read_planned_element show the goals a lesfiche '
        'or a lesson has. Listing changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Words that must all occur in the title of the curriculum, '
              'case-insensitive, in any order, like "eindtermen derde '
              'graad". Default: every curriculum.',
        ),
        'source': goalSourceSchema(),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List the Smartschool curricula of learning goals',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final query = (request.arguments?['query'] as String? ?? '').trim();
    final location = goalSource(request.arguments?['source']);
    final groups = await withGoals(
      session,
      (goals) => goals.getCurricula(location: location),
    );
    return CallToolResult(
      content: [
        TextContent(text: formatCurricula(groups, query, location: location)),
      ],
    );
  },
);
