import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import 'fake_messages.dart';

/// Where "Mijn groepen", the user's own mail groups, are in the profile: the
/// list (`function` `main`, or none), a group's members page (`users`), and
/// for the writes the form of a group (`addedit`) and its delete (`delete`),
/// each with the group's `mID`.
const fakeMyGroupsPath = '/?module=Profile&file=mygroups';

/// The dispatcher of Smartschool's member picker, whose selection of a
/// group (`usc` `mygroups_{id}`) gives each member's platform and school.
const fakeUserSelectPath = '/?module=Userselect&file=dispatcher';

/// The removal of one member of an own group, the cross on its row (#233).
const fakeDeleteUserPath = '/Profile/Mygroups/deleteUser';

/// A person in an own mail group, as the member picker lists one: user id,
/// name (last name first, as Smartschool shows members), platform (`ssId`)
/// and school. The own school ([FakeMailbox.platformId],
/// [FakeMailbox.ownSchool]) unless given.
class FakeMyGroupMember {
  const FakeMyGroupMember(
    this.userId,
    this.name, {
    this.platform = FakeMailbox.platformId,
    this.school = FakeMailbox.ownSchool,
  });

  final int userId;
  final String name;
  final int platform;

  /// The school's name, `''` for none (the picker then gives an empty
  /// `<schoolname>`).
  final String school;
}

/// An own mail group of the fake's account, with its name and description
/// as Smartschool saved them, and its members.
class FakeMyGroup {
  FakeMyGroup(
    this.id,
    this.name, {
    this.description = '',
    List<FakeMyGroupMember>? members,
  }) : members = members ?? [];

  final int id;
  String name;
  String description;
  final List<FakeMyGroupMember> members;

  /// The group as the search of a compose form finds it: a group with its
  /// id and name, and its description (seen live, 2026-11-16, #231).
  FakeRecipient get recipient => FakeRecipient.group(
    name,
    id: id,
    description: description.isEmpty ? null : description,
  );
}

/// "Mijn groepen" of the fake's account (`MyGroupsService` of
/// flutter_smartschool 0.4.6, yvanvds/dartschool#251), served to logged-in
/// requests in the shapes of the library's hand-written fixtures
/// (`test/fixtures/smartschool/requests/get/profile/mygroups/` and
/// `post/userselect/` in dartschool) and its documented answers
/// (`doc/my-groups.md`): the list of [groups], a group's members page, and
/// the member picker's selection. Made-up groups and people only: the
/// members of a real group are mostly pupils.
///
/// As Smartschool does, loading a group's members page sets the picker's
/// selection of that group in the session it is loaded in to the current
/// members ([_selections]), and hands out a new token for the page's
/// members form; the picker answers `get Items Selected` from that
/// selection, and redirects a request without `X-Requested-With` to the
/// start page. The list does not escape names and descriptions.
///
/// The writes of a group itself (#232, dartschool#252) are served as the
/// library documents them (seen live, 2026-11-16): the form of a group
/// (`GET addedit`, with `mID` for an existing one) with a new token for
/// every load, kept per session; its save (`POST addedit`, to the URL the
/// form was loaded from), which strips tags from the name and the
/// description, as Smartschool does, and is answered `302` to the list
/// (`function=main`), keeping the feedback "not done" (type `2`) in the
/// session ([_feedback]) for a save it refuses (a wrong token, an empty
/// name, a group it does not have); and the delete (`GET delete`), answered
/// with the list itself, without the group, and the feedback "done" (type
/// `1`), or "not done" for a group it does not have. A new group gets the
/// id [nextId].
///
/// The writes of the members (#233, dartschool#253) are served as the
/// library documents them (seen live, 2026-11-16): the picker's `confirm
/// Selection` replaces the session's selection of the group with the people
/// it is sent (named by [person]) and answers `closeUsc` on the form `form`,
/// saving nothing; the post of the members form (`POST users`), with the
/// token of the members page loaded last in the session, saves that
/// selection as the group's members, and is answered with the members page
/// (a new token, and the selection set to the new members); and `POST
/// /Profile/Mygroups/deleteUser` removes one member, answered `true` also
/// for someone who is not a member. [writes] lists them.
class FakeMyGroups {
  /// The own groups, in any order: the list sorts them by name.
  final List<FakeMyGroup> groups = [];

  /// The id the next group made gets.
  int nextId = 900601;

  /// The person the member picker knows by user id and platform, for a
  /// `confirm Selection` that names someone who is not a member yet: as
  /// `FakeSmartschool` wires it, the people of its mailbox's directory.
  FakeMyGroupMember? Function(int userId, int platform) person = (_, _) => null;

  /// The requests, in order: `GET main`, `GET users <id>`,
  /// `POST userSelect/get Items Selected <usc>`, `GET addedit` and
  /// `POST addedit` (the form for a new group and its save),
  /// `GET addedit <id>` and `POST addedit <id>` (the edit form of a group
  /// and its save), `GET delete <id>`,
  /// `POST userSelect/confirm Selection <usc>` and `POST users <id>` (a new
  /// selection and the members form that saves it),
  /// `POST deleteUser <group id> <user id>`, and for the routes that are
  /// not served `GET <function> <id>` or `POST <path>`.
  final List<String> requests = [];

  /// The saves of the form of a group, as they went out: their form fields.
  final List<Map<String, String>> saves = [];

  /// Routes of a write (`save`, `delete`, `members`, `deleteUser`) whose
  /// write is handled, after which the connection drops before the answer
  /// comes in: the write was made, but the library cannot confirm it.
  final Set<String> dropping = {};

  /// Called with each request, as [requests] records it, before it is
  /// answered, so that a test can change the groups in between: for
  /// example delete a group between the list and its members page.
  void Function(String request)? beforeAnswer;

  void _record(String request) {
    requests.add(request);
    beforeAnswer?.call(request);
  }

  /// The requests that are not reads ([requests] but the list, the members
  /// page, the form of a group and the picker's selection).
  List<String> get writes => [
    for (final request in requests)
      if (!_reads.any(request.startsWith)) request,
  ];

  static const _reads = [
    'GET main',
    'GET users ',
    'GET addedit',
    'POST userSelect/get Items Selected ',
  ];

  /// Routes (`main`, `users`, `picker`, `form`, `save`, `delete`, and of
  /// #233 `confirm`, the picker's `confirm Selection`, `members`, the post
  /// of the members form, and `deleteUser`) answered with an error page and
  /// this HTTP status instead, without handling a write; with `200`, an
  /// HTML page where another page or XML was expected. `main` is the list
  /// itself, also after a save; `picker` is every request of the picker.
  final Map<String, int> failing = {};

  /// The token of the form of a group loaded last in each session.
  final Map<String?, String> _formTokens = {};

  /// The feedback type (`1` done, `2` not done) the next list in a session
  /// shows, by session: Smartschool keeps it until a page shows it.
  final Map<String?, int> _feedback = {};

  /// The picker's selection of each group (`usc` `mygroups_{id}`) by
  /// session, as the last load of its members page in that session set it.
  final Map<String?, Map<String, List<FakeMyGroupMember>>> _selections = {};

  /// The token of the members form of the last members page loaded in each
  /// session.
  final Map<String?, String> _tokens = {};
  int _tokensGiven = 0;

  /// The own groups as the search of a compose form finds them.
  Iterable<FakeRecipient> get recipients => [
    for (final group in groups) group.recipient,
  ];

  FakeMyGroup? _group(int? id) =>
      groups.where((group) => group.id == id).firstOrNull;

  ResponseBody? respond(RequestOptions options) {
    final uri = options.uri;
    final query = uri.queryParameters;
    if (uri.path == fakeDeleteUserPath) return _removeUser(options);
    if (uri.path != '/') return null;
    if (query['module'] == 'Profile' && query['file'] == 'mygroups') {
      return _profile(options, query);
    }
    if (query['module'] == 'Userselect' && query['file'] == 'dispatcher') {
      return _picker(options);
    }
    return null;
  }

  ResponseBody _profile(RequestOptions options, Map<String, String> query) {
    final function = query['function'] ?? 'main';
    final id = int.tryParse(query['mID'] ?? '');
    final session = sessionOf(options);
    if (options.method == 'POST' && function == 'addedit') {
      return _save(options, id, session);
    }
    if (options.method == 'POST' && function == 'users') {
      return _saveMembers(options, id, session);
    }
    if (options.method != 'GET') {
      _record('${options.method} $function ${id ?? ''}'.trim());
      return _html('<html><body>Not in the fake</body></html>', status: 404);
    }
    switch (function) {
      case 'addedit':
        _record('GET addedit ${id ?? ''}'.trim());
        if (failing['form'] case final status?) return _errorPage(status);
        final group = _group(id);
        if (id != null && group == null) {
          // Seen live for an id the user has no group of: the list, with
          // "De actie werd niet correct uitgevoerd!".
          return _html(_listPage(feedback: 2));
        }
        final token = _formTokens[session] = 'fake-token-${++_tokensGiven}';
        return _html(_formPage(token, group));
      case 'delete':
        _record('GET delete $id');
        if (failing['delete'] case final status?) return _errorPage(status);
        final group = _group(id);
        if (group != null) groups.remove(group);
        if (dropping.contains('delete')) throw _dropped(options);
        // Answered with the list itself, not a redirect (seen live).
        return _html(_listPage(feedback: group == null ? 2 : 1));
      case 'main':
        _record('GET main');
        if (failing['main'] case final status?) return _errorPage(status);
        return _html(_listPage(feedback: _feedback.remove(session)));
      case 'users':
        _record('GET users $id');
        if (failing['users'] case final status?) return _errorPage(status);
        final group = _group(id);
        if (group == null) {
          // Seen live for an id the user has no group of: the list, with
          // "De actie werd niet correct uitgevoerd!".
          return _html(_listPage(feedback: 2));
        }
        return _membersAnswer(group, session);
    }
    _record('GET $function ${id ?? ''}'.trim());
    return _html('<html><body>Not in the fake</body></html>', status: 404);
  }

  /// A save of the form of a group: a new one without [id], the group with
  /// that id otherwise. Answered `302` to the list (seen live), with the
  /// feedback "not done" kept in [session] for a save Smartschool refuses.
  ResponseBody _save(RequestOptions options, int? id, String? session) {
    _record('POST addedit ${id ?? ''}'.trim());
    if (failing['save'] case final status?) return _errorPage(status);
    final data = options.data;
    final fields = data is Map
        ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
        : const <String, String>{};
    saves.add(fields);
    // Smartschool strips the tags of a saved name and description.
    final name = (fields['name'] ?? '').replaceAll(_tags, '');
    final description = (fields['desc'] ?? '').replaceAll(_tags, '');
    final group = _group(id);
    if (fields['_csrf_token'] == null ||
        fields['_csrf_token'] != _formTokens[session] ||
        fields['store'] != '1' ||
        name.trim().isEmpty ||
        (id != null && group == null)) {
      _feedback[session] = 2;
    } else if (group == null) {
      groups.add(FakeMyGroup(nextId++, name, description: description));
    } else {
      group
        ..name = name
        ..description = description;
    }
    if (dropping.contains('save')) throw _dropped(options);
    return ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['$fakeMyGroupsPath&function=main'],
      },
    );
  }

  static final _tags = RegExp(r'<[^>]*>');

  /// The members page of [group], loaded in [session]: it sets the picker's
  /// selection of the group in that session to the current members, and
  /// hands out a new token for its members form.
  ResponseBody _membersAnswer(FakeMyGroup group, String? session) {
    (_selections[session] ??= {})['mygroups_${group.id}'] = [...group.members];
    final token = _tokens[session] = 'fake-token-${++_tokensGiven}';
    return _html(_membersPage(group, token));
  }

  /// A post of the members form of the group with [id] (#233): with the
  /// token of the members page loaded last in [session], it saves the
  /// picker's selection of the group in that session as its members
  /// (replacing them, as Smartschool does), and is answered with the members
  /// page (seen live). A form with another token saves nothing; what
  /// Smartschool answers to it has not been seen.
  ResponseBody _saveMembers(RequestOptions options, int? id, String? session) {
    _record('POST users $id');
    if (failing['members'] case final status?) return _errorPage(status);
    final group = _group(id);
    // Not seen live: answered as the members page of such an id.
    if (group == null) return _html(_listPage(feedback: 2));
    final fields = _fields(options.data);
    final selection = _selections[session]?['mygroups_${group.id}'];
    if (fields['_csrf_token'] != null &&
        fields['_csrf_token'] == _tokens[session] &&
        fields['store'] == '1' &&
        selection != null) {
      group.members
        ..clear()
        ..addAll(selection);
    }
    if (dropping.contains('members')) throw _dropped(options);
    return _membersAnswer(group, session);
  }

  /// The removal of one member (#233): `POST /Profile/Mygroups/deleteUser`
  /// with `userID` and `groupID`, answered `200`, `application/json`,
  /// `true`, also for someone who is not a member (seen live).
  ResponseBody _removeUser(RequestOptions options) {
    final fields = _fields(options.data);
    _record(
      '${options.method} deleteUser ${fields['groupID']} ${fields['userID']}',
    );
    if (options.method != 'POST') {
      return _html('<html><body>Not in the fake</body></html>', status: 404);
    }
    if (failing['deleteUser'] case final status?) return _errorPage(status);
    final user = int.tryParse(fields['userID'] ?? '');
    _group(
      int.tryParse(fields['groupID'] ?? ''),
    )?.members.removeWhere((member) => member.userId == user);
    if (dropping.contains('deleteUser')) throw _dropped(options);
    return ResponseBody.fromString(
      'true',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  /// The fields of a form-encoded request's [data], as text.
  static Map<String, String> _fields(Object? data) => data is Map
      ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
      : const {};

  /// The connection dropping after a request went out and was handled.
  static Object _dropped(RequestOptions options) =>
      DioException.connectionError(
        requestOptions: options,
        reason: 'Connection closed before full header was received',
        error: const SocketException('Connection reset by peer'),
      );

  ResponseBody _picker(RequestOptions options) {
    final data = options.data;
    final form = data is Map
        ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
        : const <String, String>{};
    final command = _commandOf(form['command']);
    if (options.method != 'POST' || command == null) {
      _record('${options.method} userSelect');
      return _html('<html><body>Not in the fake</body></html>', status: 404);
    }
    final usc = command.params['usc'] ?? '';
    _record('POST ${command.subsystem}/${command.action} $usc');
    if (failing['picker'] case final status?) return _errorPage(status);
    // Without X-Requested-With, Smartschool sends the picker's requests to
    // the start page (seen live, dartschool#251).
    if (!_isXhr(options.headers)) {
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['/?module=Homepage'],
        },
      );
    }
    if (command.subsystem == 'userSelect' &&
        command.action == 'confirm Selection') {
      return _confirmSelection(sessionOf(options), usc, command.params);
    }
    if (command.subsystem != 'userSelect' ||
        command.action != 'get Items Selected') {
      return _xml(_pickerStatus('error'));
    }
    final selection = _selections[sessionOf(options)]?[usc];
    // What Smartschool answers for a group whose members page was not
    // loaded in the session has not been seen: an answer without a
    // selection, which the library refuses.
    if (selection == null) return _xml(_pickerStatus('ok'));
    return _xml(_selectionAnswer(selection));
  }

  /// The picker's `confirm Selection` of [usc] in [session] (#233): the
  /// selection it is sent (`xml`, an `<item>` with its `type`, `ssId` and
  /// `id` per person) becomes the session's selection of the group, each
  /// person named as the current selection names them,
  /// or by [person]; someone the picker does not know is left out (what
  /// Smartschool does then has not been seen). Answered `closeUsc` on the
  /// form `form` (the dartschool fixture `confirm-selection.xml`), saving
  /// nothing.
  ResponseBody _confirmSelection(
    String? session,
    String usc,
    Map<String, String> params,
  ) {
    if (failing['confirm'] case final status?) return _errorPage(status);
    final current = _selections[session]?[usc] ?? const [];
    final selection = <FakeMyGroupMember>[];
    for (final item in XmlDocument.parse(
      params['xml'] ?? '<items/>',
    ).findAllElements('item')) {
      int? number(String tag) =>
          int.tryParse(item.getElement(tag)?.innerText.trim() ?? '');
      final (id, platform) = (number('id'), number('ssId'));
      if (item.getElement('type')?.innerText.trim() != 'U' ||
          id == null ||
          platform == null) {
        continue;
      }
      final member =
          current
              .where((m) => m.userId == id && m.platform == platform)
              .firstOrNull ??
          person(id, platform);
      if (member != null) selection.add(member);
    }
    (_selections[session] ??= {})[usc] = selection;
    return _xml(
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<server><response><status>ok</status><actions><action>\n'
      '<subsystem>userselect</subsystem><command>closeUsc</command>\n'
      '<data><close><type>1</type><formname>form</formname></close></data>\n'
      '</action></actions></response></server>\n',
    );
  }

  /// The list of own groups, sorted by name, unescaped as Smartschool sends
  /// it, with the feedback of type [feedback] in a script when given.
  String _listPage({int? feedback}) {
    final sorted = [...groups]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final rows = [
      for (final group in sorted)
        '<div class="smsc-table__row">\n'
            '\t<div class="smsc-table__cell mygroup-icon star-icon"></div>\n'
            '\t<div class="smsc-table__cell mygroup-name">${group.name}</div>\n'
            '\t<div class="smsc-table__cell">${group.description}</div>\n'
            '\t<div class="smsc-table__cell smsc-table__cell--text-right mygroup-actions">\n'
            '\t\t<a href="$fakeMyGroupsPath&function=addedit&mID=${group.id}" class="edit" title=\'Wijzigen\'></a>\n'
            '\t\t<a href="$fakeMyGroupsPath&function=users&mID=${group.id}" class="add" title=\'Personen toevoegen\'></a>\n'
            '\t\t<a onClick="confirmDelete(\'$fakeMyGroupsPath&function=delete&mID=${group.id}\');" class="delete" title=\'Verwijderen\'></a>\n'
            '\t</div>\n'
            '</div>\n',
    ].join();
    final message = switch (feedback) {
      null => null,
      1 => 'De actie werd correct uitgevoerd.',
      _ => 'De actie werd niet correct uitgevoerd!',
    };
    final script = message == null
        ? ''
        : '<script type="text/javascript">\$(document).ready(function() '
              '{var msg = "$message", type = $feedback;var show = function() '
              '{if (window.notificationShowFeedback) { '
              'window.notificationShowFeedback(msg, type); return true; }'
              'return false;};if (show()) { return; }});</script>\n';
    return '''
<!DOCTYPE html>
<html lang="nl">
<head><meta charset="utf-8"><title>Profiel - Smartschool</title></head>
<body>
<div id="smscMainBlockContainer">
	<div id="smscMainBlockContainerContent">
		<div class="smscSettings">
			<a class="smscSettings_backbutton" href="/?module=Profile"></a>
			<div class="smscSettings_mainTitle">Mijn groepen</div>
			<div>Stel uw eigen favoriete groepen samen</div>
		</div>
		<div>
			<div class="smsc-table mygroup-table">
<a href="$fakeMyGroupsPath&function=addedit" class="smsc-linkbutton smsc-linkbutton--icon smsc-linkbutton--add add-groups">Nieuwe groep</a>
	<div class="smsc-table__header">
		<div class="smsc-table__cell mygroup-icon"></div>
		<div class="smsc-table__cell mygroup-name">Naam</div>
		<div class="smsc-table__cell">Omschrijving</div>
		<div class="smsc-table__cell smsc-table__cell--text-right mygroup-actions"></div>
	</div>
$rows</div>
		</div>
	</div>
</div>
$script</body>
</html>
''';
  }

  /// The form for a new own group with the token [token]; with [group], the
  /// edit form of that group, its name and description escaped in their
  /// `value` (in the shape of the library's `addedit.html`).
  String _formPage(String token, FakeMyGroup? group) {
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    final name = escape.convert(group?.name ?? '');
    final description = escape.convert(group?.description ?? '');
    return '''
<!DOCTYPE html>
<html lang="nl">
<head><meta charset="utf-8"><title>Profiel - Smartschool</title></head>
<body>
<div id="smscMainBlockContainer">
	<div id="smscMainBlockContainerContent">
		<div class="smscSettings">
			<a class="smscSettings_backbutton" href="$fakeMyGroupsPath"></a>
			<div class="smscSettings_mainTitle">${group == null ? 'Nieuwe groep' : 'Groep wijzigen'}</div>
		</div>
		<form name="form" action="" method="post">
<input type="hidden" name="_csrf_token" value="$token" />
<input type="hidden" name="store" value="1" />
			<div class="smsc-form__row">
				<label for="name">Naam</label>
				<input type="text" name="name" id="name" value="$name" />
			</div>
			<div class="smsc-form__row">
				<label for="desc">Omschrijving</label>
				<input type="text" name="desc" id="desc" value="$description" />
			</div>
			<input type="submit" value="Opslaan" />
		</form>
	</div>
</div>
</body>
</html>
''';
  }

  /// The members page of [group], its members sorted by name, with the
  /// token [token] in its members form.
  String _membersPage(FakeMyGroup group, String token) {
    const escape = HtmlEscape();
    final sorted = [...group.members]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final rows = [
      for (final member in sorted)
        '<div class="smsc-table__row">\n'
            '\t<div class="smsc-table__cell profile-users-table-icon"></div>\n'
            '\t<div class="smsc-table__cell" id="${member.userId}">'
            '${escape.convert(member.name)}</div>\n'
            '\t<div class="smsc-table__cell smsc-table__cell--text-right '
            'profile-users-table-action">\n'
            '\t\t<div class="delete2-icon deleteUserRow" '
            'data-userid="${member.userId}" data-groupid="${group.id}" '
            'title="Verwijderen"></div>\n'
            '\t</div>\n'
            '</div>\n',
    ].join();
    return '''
<!DOCTYPE html>
<html lang="nl">
<head><meta charset="utf-8"><title>Profiel - Smartschool</title></head>
<body>
<div id="smscMainBlockContainer">
	<div id="smscMainBlockContainerContent">
		<div class="smscSettings">
			<a class="smscSettings_backbutton" href="$fakeMyGroupsPath"></a>
			<div class="smscSettings_mainTitle">${escape.convert(group.name)}</div>
		</div>
		<form name="form" action="" method="post">
<input type="hidden" name="_csrf_token" value="$token" />
<input type="hidden" name="store" value="1" />
<input type="hidden" name="mID" value="" />
		</form>
		<div class="smsc-table profile-users-table">
$rows		</div>
	</div>
</div>
</body>
</html>
''';
  }

  /// The picker's answer to `get Items Selected` with [members] as its
  /// selection, `<items />` for none.
  static String _selectionAnswer(List<FakeMyGroupMember> members) {
    const escape = HtmlEscape(HtmlEscapeMode.element);
    final items = [
      for (final member in members)
        '<item><type>U</type><id>${member.userId}</id>'
            '<ssId>${member.platform}</ssId><parentId>0</parentId>'
            '<name>${escape.convert(member.name)}</name><icon>user</icon>'
            '<sortField>${escape.convert(member.name.toLowerCase())}</sortField>'
            '<selectable>1</selectable><forbidden>0</forbidden>'
            '<tooltip>Niet geselecteerd</tooltip>'
            '<schoolname>${escape.convert(member.school)}</schoolname>'
            '</item>\n',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<server><response><status>ok</status><actions><action>\n'
        '<subsystem>userselect</subsystem>'
        '<command>handle selected items</command>\n'
        '<data>${items.isEmpty ? '<items />' : '<items>\n$items</items>'}'
        '</data>\n'
        '</action></actions></response></server>\n';
  }

  /// A picker answer with [status] and no actions.
  static String _pickerStatus(String status) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<server><response><status>$status</status><actions></actions>'
      '</response></server>\n';

  /// The subsystem, action and params of the XML command [xml] of the
  /// picker's dispatcher, or null when it is not one.
  static ({String subsystem, String action, Map<String, String> params})?
  _commandOf(String? xml) {
    if (xml == null) return null;
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException {
      return null;
    }
    final command = document.rootElement.getElement('command');
    final subsystem = command?.getElement('subsystem')?.innerText.trim();
    final action = command?.getElement('action')?.innerText.trim();
    if (subsystem == null || action == null) return null;
    return (
      subsystem: subsystem,
      action: action,
      params: {
        for (final param
            in command!.getElement('params')?.childElements ??
                const <XmlElement>[])
          ?param.getAttribute('name'): param.innerText,
      },
    );
  }

  static bool _isXhr(Map<String, Object?> headers) => headers.entries.any(
    (header) =>
        header.key.toLowerCase() == 'x-requested-with' &&
        header.value == 'XMLHttpRequest',
  );

  static ResponseBody _errorPage(int status) =>
      _html('<html><body>Fout</body></html>', status: status);

  static ResponseBody _html(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      );

  static ResponseBody _xml(String body) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: ['text/xml; charset=utf-8'],
    },
  );
}
