// Dytech: sign-in + station list for the Console (outgoing-only) app.
// The Console cannot be used without signing in with a Remote Center account
// (username + password + authenticator code). Stations come from the panel and
// only the ones this account may access are shown. All messages are plain language.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

const String _kPanel = 'https://cp-remote.huslex.com';
const String _kOptToken = 'dytech-console-token';
const String _kOptUser = 'dytech-console-user';
const String _kOptExp = 'dytech-console-exp';

class _Res {
  final int status;
  final Map<String, dynamic> json;
  _Res(this.status, this.json);
  bool get ok => status >= 200 && status < 300;
  String get error => (json['error'] ?? '').toString();
}

Future<_Res> _call(String method, String path,
    {Map<String, dynamic>? body, String? token}) async {
  try {
    final uri = Uri.parse('$_kPanel$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final http.Response r = method == 'GET'
        ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 15))
        : await http
            .post(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{}))
            .timeout(const Duration(seconds: 15));
    Map<String, dynamic> j = <String, dynamic>{};
    try {
      final d = jsonDecode(r.body);
      if (d is Map<String, dynamic>) j = d;
    } catch (_) {}
    return _Res(r.statusCode, j);
  } catch (_) {
    return _Res(0, <String, dynamic>{'error': 'network'});
  }
}

/// Plain-language text for every failure the user can meet.
/// Each message ends with a short code (Exx) so we can tell exactly what happened
/// when someone reports it. Codes: E01 no connection, E02 wrong data, E03 locked,
/// E04 password must be chosen first, E05 session ended, E06 subscription paused,
/// E07 station gone, E08 missing fields, E09 other (with the server status number).
// Friendly text on screen; the technical code goes only to the application log.
String _friendly(_Res r, {bool login = false}) {
  String m(String text, String code) {
    try {
      bind.mainGetCommon(key: 'dytech-log:console $code status=${r.status} err=${r.error}');
    } catch (_) {}
    return translate(text);
  }

  if (r.status == 0 || r.error == 'network') {
    return m('Cannot reach the server. Check your internet connection and try again.', 'E01');
  }
  switch (r.error) {
    case 'bad':
      return m('Wrong username, password or code. Please check them and try again.', 'E02');
    case 'locked':
      return m('Too many attempts. Please wait 15 minutes and try again.', 'E03');
    case 'must_change':
      return m(
          'Sign in once at Remote Center in your browser and choose your own password, then come back here.',
          'E04');
    case 'expired':
      return m('Your session has ended. Please sign in again.', 'E05');
    case 'paused':
      return m("This customer's subscription is paused.", 'E06');
    case 'notfound':
      return m('This station is no longer available to you.', 'E07');
  }
  if (r.status == 401) {
    return m('Your session has ended. Please sign in again.', 'E05');
  }
  if (r.status == 404 && login) {
    return m('The service is not available right now. Please contact your administrator.', 'E10');
  }
  if (r.status == 404) {
    return m('This station is no longer available to you.', 'E07');
  }
  return m('Something went wrong. Please try again in a moment.', 'E09-${r.status}');
}

class DytechConsoleHome extends StatefulWidget {
  const DytechConsoleHome({Key? key}) : super(key: key);

  @override
  State<DytechConsoleHome> createState() => _DytechConsoleHomeState();
}

class _DytechConsoleHomeState extends State<DytechConsoleHome> {
  String _token = '';
  String _user = '';
  String _notice = '';

  @override
  void initState() {
    super.initState();
    final t = bind.mainGetLocalOption(key: _kOptToken);
    final exp = int.tryParse(bind.mainGetLocalOption(key: _kOptExp)) ?? 0;
    if (t.isNotEmpty && exp > DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      _token = t;
      _user = bind.mainGetLocalOption(key: _kOptUser);
    }
  }

  Future<void> _clear() async {
    await bind.mainSetLocalOption(key: _kOptToken, value: '');
    await bind.mainSetLocalOption(key: _kOptUser, value: '');
    await bind.mainSetLocalOption(key: _kOptExp, value: '');
  }

  @override
  Widget build(BuildContext context) {
    if (_token.isEmpty) {
      return _LoginView(
        notice: _notice,
        onSignedIn: (token, user) {
          setState(() {
            _token = token;
            _user = user;
            _notice = '';
          });
        },
      );
    }
    return _StationsView(
      token: _token,
      user: _user,
      onSignedOut: (String message) async {
        await _clear();
        if (!mounted) return;
        setState(() {
          _token = '';
          _user = '';
          _notice = message;
        });
      },
    );
  }
}

class _LoginView extends StatefulWidget {
  final String notice;
  final void Function(String token, String user) onSignedIn;
  const _LoginView({Key? key, required this.notice, required this.onSignedIn})
      : super(key: key);

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String _error = '';

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final u = _user.text.trim();
    final p = _pass.text;
    final c = _code.text.trim();
    if (u.isEmpty || p.isEmpty || c.length != 6) {
      setState(() => _error = translate('Please enter your username, your password and the 6-digit code from your authenticator app.'));
      bind.mainGetCommon(key: 'dytech-log:console E08 missing fields');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final r = await _call('POST', '/api/console/login',
        body: {'username': u, 'password': p, 'code': c});
    if (!mounted) return;
    if (r.ok && (r.json['token'] ?? '').toString().isNotEmpty) {
      final token = r.json['token'].toString();
      final user = (r.json['user'] ?? u).toString();
      final secs = int.tryParse((r.json['expires_in'] ?? '').toString()) ?? 3600;
      final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + secs - 60;
      await bind.mainSetLocalOption(key: _kOptToken, value: token);
      await bind.mainSetLocalOption(key: _kOptUser, value: user);
      await bind.mainSetLocalOption(key: _kOptExp, value: exp.toString());
      _pass.clear();
      _code.clear();
      widget.onSignedIn(token, user);
      return;
    }
    setState(() {
      _busy = false;
      _error = _friendly(r, login: true);
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final msg = _error.isNotEmpty ? _error : widget.notice;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(translate('Sign in'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(translate('Use your Remote Center account to see your stations.'),
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 18),
              TextField(
                controller: _user,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    labelText: translate('Username')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                enabled: !_busy,
                obscureText: _hide,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  labelText: translate('Password'),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility_off : Icons.visibility, size: 18),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    counterText: '',
                    labelText: translate('Authenticator code'),
                    helperText: translate('6 digits from your authenticator app')),
                onSubmitted: (_) => _submit(),
              ),
              if (msg.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(msg,
                      style: TextStyle(
                          fontSize: 13,
                          color: _error.isNotEmpty ? scheme.error : null)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(translate(_busy ? 'Signing in…' : 'Sign in')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Station {
  final int id;
  final String name;
  final String code;
  final String group;
  final bool online;
  final bool paused;
  _Station(this.id, this.name, this.code, this.group, this.online, this.paused);
}

class _StationsView extends StatefulWidget {
  final String token;
  final String user;
  final Future<void> Function(String message) onSignedOut;
  const _StationsView(
      {Key? key, required this.token, required this.user, required this.onSignedOut})
      : super(key: key);

  @override
  State<_StationsView> createState() => _StationsViewState();
}

class _StationsViewState extends State<_StationsView> {
  final _search = TextEditingController();
  Timer? _timer;
  List<_Station> _all = <_Station>[];
  bool _loading = true;
  bool _connecting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _call('GET', '/api/console/stations', token: widget.token);
    if (!mounted) return;
    if (r.status == 401) {
      await widget.onSignedOut(_friendly(r));
      return;
    }
    if (!r.ok) {
      setState(() {
        _loading = false;
        _error = _friendly(r);
      });
      return;
    }
    final list = <_Station>[];
    final raw = r.json['stations'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(_Station(
              int.tryParse('${e['id']}') ?? 0,
              '${e['name'] ?? ''}',
              '${e['code'] ?? ''}',
              '${e['group'] ?? ''}',
              e['online'] == true,
              e['paused'] == true));
        }
      }
    }
    setState(() {
      _all = list;
      _loading = false;
      _error = '';
    });
  }

  Future<void> _signOut() async {
    await _call('POST', '/api/console/logout', token: widget.token);
    await widget.onSignedOut('');
  }

  Future<void> _connect(_Station s) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = '';
    });
    final r = await _call('POST', '/api/console/connect/${s.id}', token: widget.token);
    if (!mounted) return;
    if (r.status == 401) {
      await widget.onSignedOut(_friendly(r));
      return;
    }
    if (!r.ok) {
      setState(() {
        _connecting = false;
        _error = _friendly(r);
      });
      return;
    }
    final rdId = '${r.json['rd_id'] ?? ''}';
    final pw = '${r.json['password'] ?? ''}';
    setState(() => _connecting = false);
    if (rdId.isNotEmpty) {
      await connect(context, rdId, password: pw);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _search.text.trim().toLowerCase();
    final shown = _all
        .where((s) =>
            q.isEmpty ||
            s.name.toLowerCase().contains(q) ||
            s.group.toLowerCase().contains(q) ||
            s.code.toLowerCase().contains(q))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(translate('Stations'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(widget.user, style: const TextStyle(fontSize: 13)),
              IconButton(
                tooltip: translate('Refresh'),
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _load,
              ),
              TextButton(onPressed: _signOut, child: Text(translate('Sign out'))),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: translate('Search stations'),
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error, style: TextStyle(fontSize: 13, color: scheme.error)),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? Center(
                        child: Text(translate(_all.isEmpty
                            ? 'No stations are available for your account yet.'
                            : 'No stations match your search.')))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) => _row(shown[i], scheme),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(_Station s, ColorScheme scheme) {
    final canConnect = s.online && !s.paused && !_connecting;
    final label = s.paused ? 'Paused' : (s.online ? 'Connect' : 'Offline');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outline.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.paused
                  ? Colors.orange
                  : (s.online ? Colors.green : Colors.grey),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(s.group.isEmpty ? s.code : '${s.group} · ${s.code}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: canConnect ? () => _connect(s) : null,
            child: Text(translate(label)),
          ),
        ],
      ),
    );
  }
}
