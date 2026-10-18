// Dytech: one-time "Activate" card for the incoming client. The license is handed to the Rust side
// through the local option `dytech-activate`; progress comes back through `dytech-activate-status`
// and the synced service option `dytech-token` (set once the station is linked to the panel).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class DytechActivateCard extends StatefulWidget {
  final VoidCallback? onChanged;
  const DytechActivateCard({Key? key, this.onChanged}) : super(key: key);

  @override
  State<DytechActivateCard> createState() => _DytechActivateCardState();
}

class _DytechActivateCardState extends State<DytechActivateCard> {
  final _ctrl = TextEditingController();
  Timer? _timer;
  bool _activated = true; // hidden until we know otherwise (avoids a flash)
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    final token = await bind.mainGetOption(key: 'dytech-token');
    final status = bind.mainGetLocalOption(key: 'dytech-activate-status');
    if (!mounted) return;
    final activated = token.isNotEmpty;
    var busy = _busy;
    var error = _error;
    if (status == 'busy') {
      busy = true;
    } else if (status.startsWith('err:')) {
      busy = false;
      error = status.substring(4);
    } else if (status == 'ok') {
      busy = false;
      error = '';
    }
    if (activated != _activated || busy != _busy || error != _error) {
      setState(() {
        _activated = activated;
        _busy = busy;
        _error = error;
      });
      widget.onChanged?.call();
    }
  }

  Future<void> _submit() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    await bind.mainSetLocalOption(key: 'dytech-activate', value: key);
  }

  @override
  Widget build(BuildContext context) {
    if (_activated) return const Offstage();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 16, top: 8, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Activate this station',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Enter the license key from Dytech Remote Center.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'License key'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error,
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Activating…' : 'Activate'),
            ),
          ),
        ],
      ),
    );
  }
}
