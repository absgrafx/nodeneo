import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../services/bridge.dart';
import '../theme.dart';

/// Re-auth with recovery phrase or private key to clear app lock only (wallet + SQLite + RPC stay).
Future<void> showAppLockRecoverySheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _AppLockRecoveryBody(),
  );
}

class _AppLockRecoveryBody extends StatefulWidget {
  const _AppLockRecoveryBody();

  @override
  State<_AppLockRecoveryBody> createState() => _AppLockRecoveryBodyState();
}

class _AppLockRecoveryBodyState extends State<_AppLockRecoveryBody> {
  final _phrase = TextEditingController();
  final _key = TextEditingController();
  bool _phraseMode = true;
  bool _busy = false;
  bool _obscureKey = true;
  String? _error;

  @override
  void dispose() {
    _phrase.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bridge = GoBridge();
      final ok = _phraseMode
          ? bridge.verifyRecoveryMnemonic(_phrase.text)
          : bridge.verifyRecoveryPrivateKey(_key.text.trim());
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'That does not match this wallet. Check spelling and spaces.';
        });
        return;
      }
      await AppLockService.instance.disableLock();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on GoBridgeException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unlock with backup',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the same recovery phrase or private key as this wallet. '
              'Your chats and settings stay on this device.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: true, label: Text('Phrase'), icon: Icon(Icons.notes_outlined, size: 18)),
                ButtonSegment<bool>(value: false, label: Text('Private key'), icon: Icon(Icons.key_outlined, size: 18)),
              ],
              selected: {_phraseMode},
              onSelectionChanged: (s) {
                setState(() {
                  _phraseMode = s.first;
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 16),
            if (_phraseMode)
              TextField(
                controller: _phrase,
                maxLines: 4,
                minLines: 3,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  hintText: 'Recovery phrase (12 or 24 words)',
                  border: OutlineInputBorder(),
                ),
              )
            else
              TextField(
                controller: _key,
                obscureText: _obscureKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: '0x… private key',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 13)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      final empty = _phraseMode ? _phrase.text.trim().isEmpty : _key.text.trim().isEmpty;
                      if (empty) {
                        setState(() => _error = 'Enter your ${_phraseMode ? "phrase" : "private key"}.');
                        return;
                      }
                      _verify();
                    },
              style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Verify and turn off app lock'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
