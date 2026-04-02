import 'package:flutter/material.dart';

import '../../services/session_duration_store.dart';
import '../../theme.dart';

/// Default on-chain chat session duration (stake window) for new sessions.
class SessionLengthSettingsScreen extends StatefulWidget {
  const SessionLengthSettingsScreen({super.key});

  @override
  State<SessionLengthSettingsScreen> createState() => _SessionLengthSettingsScreenState();
}

class _SessionLengthSettingsScreenState extends State<SessionLengthSettingsScreen> {
  bool _loading = true;
  int _sessionDurationSeconds = SessionDurationStore.defaultSeconds;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sec = await SessionDurationStore.instance.readSeconds();
    if (!mounted) return;
    setState(() {
      _sessionDurationSeconds = sec;
      _loading = false;
    });
  }

  Future<void> _saveSessionDuration(int seconds) async {
    await SessionDurationStore.instance.writeSeconds(seconds);
    if (!mounted) return;
    setState(() => _sessionDurationSeconds = seconds);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Default chat session: ${SessionDurationStore.formatDurationLabel(seconds)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Session length')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: NeoTheme.green))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Chat session length',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'Default time window for new on-chain inference sessions (affects estimated MOR stake). '
                  'You can override this on the error screen when opening a chat fails, or change it here anytime.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
                ),
                const SizedBox(height: 20),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Default duration',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _sessionDurationSeconds,
                      items: [
                        for (final (label, sec) in SessionDurationStore.presets)
                          DropdownMenuItem<int>(value: sec, child: Text(label)),
                      ],
                      onChanged: (v) {
                        if (v != null) _saveSessionDuration(v);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
