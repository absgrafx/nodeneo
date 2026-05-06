import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/app_lock_service.dart';
import '../../services/biometric_labels.dart';
import '../../services/default_tuning_store.dart';
import '../../services/form_factor.dart';
import '../../services/keychain_sync_store.dart';
import '../../services/platform_caps.dart';
import '../../services/session_duration_store.dart';
import '../../services/wallet_vault.dart';
import '../../theme.dart';
import '../../widgets/section_card.dart';
import '../security/app_lock_autofill.dart';
import '../security/app_lock_setup_choice_screen.dart';
import '../security/app_lock_setup_screen.dart';

/// Preferences screen: system prompt, default tuning, session duration, security.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  // --- Duration state ---
  bool _durationLoading = true;
  int _sessionDurationSeconds = SessionDurationStore.defaultSeconds;

  // --- Defaults state (system prompt + tuning) ---
  bool _defaultsLoading = true;
  final _promptController = TextEditingController();
  String _savedPrompt = '';
  double _temperature = DefaultTuningStore.defaultTemperature;
  double _topP = DefaultTuningStore.defaultTopP;
  int _maxTokens = DefaultTuningStore.defaultMaxTokens;
  double _frequencyPenalty = DefaultTuningStore.defaultFrequencyPenalty;
  double _presencePenalty = DefaultTuningStore.defaultPresencePenalty;

  // --- Security state ---
  bool _securityLoading = true;
  bool _lockOn = false;
  bool _bioOn = false;
  bool _bioAvailable = false;
  LockMode _lockMode = LockMode.off;
  // Platform-aware label for the biometric modality on this device — refined
  // by `_loadSecurity` (Face ID vs Touch ID vs Fingerprint vs Face Unlock vs
  // Windows Hello). Defaults to the platform best-guess so the section renders
  // sensibly during the async probe.
  BiometricLabels _bio = BiometricLabels.platformGuess;
  bool _icloudSync = false;
  bool _icloudSyncChanging = false;

  @override
  void initState() {
    super.initState();
    _loadDuration();
    _loadDefaults();
    _loadSecurity();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  // ── Duration ──────────────────────────────────────────────────

  Future<void> _loadDuration() async {
    final sec = await SessionDurationStore.instance.readSeconds();
    if (!mounted) return;
    setState(() {
      _sessionDurationSeconds = sec;
      _durationLoading = false;
    });
  }

  Future<void> _saveDuration(int seconds) async {
    await SessionDurationStore.instance.writeSeconds(seconds);
    if (!mounted) return;
    setState(() => _sessionDurationSeconds = seconds);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Default session: ${SessionDurationStore.formatDurationLabel(seconds)}',
        ),
      ),
    );
  }

  // ── Defaults (system prompt + tuning) ───────────────────────────

  Future<void> _loadDefaults() async {
    final d = await DefaultTuningStore.instance.read();
    if (!mounted) return;
    final prompt = d['system_prompt'] as String? ?? '';
    setState(() {
      _promptController.text = prompt;
      _savedPrompt = prompt;
      _temperature =
          (d['temperature'] as num?)?.toDouble() ??
          DefaultTuningStore.defaultTemperature;
      _topP =
          (d['top_p'] as num?)?.toDouble() ?? DefaultTuningStore.defaultTopP;
      _maxTokens =
          (d['max_tokens'] as num?)?.toInt() ??
          DefaultTuningStore.defaultMaxTokens;
      _frequencyPenalty =
          (d['frequency_penalty'] as num?)?.toDouble() ??
          DefaultTuningStore.defaultFrequencyPenalty;
      _presencePenalty =
          (d['presence_penalty'] as num?)?.toDouble() ??
          DefaultTuningStore.defaultPresencePenalty;
      _defaultsLoading = false;
    });
  }

  Future<void> _saveDefaults({String? snackMessage}) async {
    final prompt = _promptController.text.trim();
    await DefaultTuningStore.instance.write(
      temperature: _temperature,
      topP: _topP,
      maxTokens: _maxTokens,
      frequencyPenalty: _frequencyPenalty,
      presencePenalty: _presencePenalty,
      systemPrompt: prompt,
    );
    if (!mounted) return;
    setState(() => _savedPrompt = prompt);
    if (snackMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackMessage),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool get _hasTuningOverrides =>
      _temperature != DefaultTuningStore.defaultTemperature ||
      _topP != DefaultTuningStore.defaultTopP ||
      _maxTokens != DefaultTuningStore.defaultMaxTokens ||
      _frequencyPenalty != DefaultTuningStore.defaultFrequencyPenalty ||
      _presencePenalty != DefaultTuningStore.defaultPresencePenalty;

  // ── Security ─────────────────────────────────────────────────

  Future<void> _loadSecurity() async {
    final auth = LocalAuthentication();
    final labels = await BiometricLabels.probe(auth);
    final lock = await AppLockService.instance.isLockEnabled;
    final bio = await AppLockService.instance.biometricEnabled;
    final mode = await AppLockService.instance.mode;
    final sync = await KeychainSyncStore.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _lockOn = lock;
      _bioOn = bio;
      _bioAvailable = labels.available;
      _bio = labels;
      _lockMode = mode;
      _icloudSync = sync;
      _securityLoading = false;
    });
  }

  Future<void> _openEnableLock() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AppLockSetupChoiceScreen(),
      ),
    );
    if (ok == true && mounted) await _loadSecurity();
  }

  Future<void> _openChangePassword() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AppLockSetupScreen(changingPassword: true),
      ),
    );
    if (ok == true && mounted) await _loadSecurity();
  }

  Future<void> _confirmDisableLock() async {
    // Biometric-only mode: confirm the user is physically present with a
    // Face ID prompt instead of asking for a password we never stored.
    if (_lockMode == LockMode.biometricOnly) {
      final auth = LocalAuthentication();
      try {
        final ok = await auth.authenticate(
          localizedReason: 'Confirm ${_bio.name} to turn off app lock',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
        if (!mounted || !ok) return;
        await AppLockService.instance.disableLock();
        if (mounted) await _loadSecurity();
      } on PlatformException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Biometric check failed.')),
        );
      }
      return;
    }

    final ctrl = TextEditingController();
    final userCtrl = TextEditingController(text: kAppLockAutofillUsername);
    final pwFocus = FocusNode();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off app lock?'),
        content: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Enter your app password to confirm.'),
              const SizedBox(height: 12),
              AppLockHiddenUsernameForAutofill(controller: userCtrl),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                focusNode: pwFocus,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(
                  labelText: 'App password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final v = await AppLockService.instance.verifyPassword(ctrl.text);
              if (!ctx.mounted) return;
              if (v) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Incorrect password.')),
                );
              }
            },
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    userCtrl.dispose();
    pwFocus.dispose();
    if (ok == true) {
      await AppLockService.instance.disableLock();
      if (mounted) await _loadSecurity();
    }
  }

  Future<void> _setBiometric(bool v) async {
    if (v && !_bioAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometrics are not available on this device.'),
        ),
      );
      return;
    }
    // Refuse to turn biometrics off in biometric-only mode — that would
    // effectively disable the lock through a side door without the user
    // ever confirming. Send them through "Turn off app lock" instead.
    if (!v && _lockMode == LockMode.biometricOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a backup password first, or turn off app lock to remove biometrics.',
          ),
        ),
      );
      return;
    }
    await AppLockService.instance.setBiometricEnabled(v);
    if (mounted) await _loadSecurity();
  }

  Future<void> _addBackupPassword() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AppLockSetupScreen(changingPassword: false),
      ),
    );
    if (ok == true && mounted) await _loadSecurity();
  }

  Future<void> _removeBackupPassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove backup password?'),
        content: Text(
          'You\'ll only be able to unlock with ${_bio.name}. Your wallet '
          'private key still works as a fallback if biometrics fail.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await AppLockService.instance.removePasswordKeepBiometric();
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable biometrics first before removing the password.'),
        ),
      );
      return;
    }
    await _loadSecurity();
  }

  Future<void> _setICloudSync(bool v) async {
    setState(() => _icloudSyncChanging = true);
    await KeychainSyncStore.instance.setEnabled(v);
    try {
      await WalletVault.instance.resyncKeychainItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Keychain update error: $e')));
      }
    }
    if (mounted) {
      setState(() {
        _icloudSync = v;
        _icloudSyncChanging = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  String _shortDuration(int sec) {
    if (sec < 3600) return '${sec ~/ 60} min';
    if (sec == 3600) return '1 hr';
    if (sec < 86400) return '${sec ~/ 3600} hrs';
    return '24 hrs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
      body: MaxContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Mobile builds don't ship the AI Gateway, so this whole notice
            // would be confusing — there's no Cursor/Zed/curl path to talk
            // about. Desktop users still need it (the most common mistake is
            // assuming preferences saved here follow them into Cursor) but in
            // a more subtle, expandable form.
            if (PlatformCaps.supportsGateway) ...[
              const _GatewayScopeNotice(),
              const SizedBox(height: 12),
            ],
            SectionCard(
              icon: Icons.psychology_outlined,
              title: 'System Prompt',
              status: StatusPill(
                active: _savedPrompt.isNotEmpty,
                label: _savedPrompt.isNotEmpty ? 'Custom' : 'None',
              ),
              child: _buildSystemPromptBody(theme),
            ),
            const SizedBox(height: 12),
            SectionCard(
              icon: Icons.tune_rounded,
              title: 'Default Tuning',
              status: StatusPill(
                active: _hasTuningOverrides,
                label: _hasTuningOverrides ? 'Custom' : 'Default',
              ),
              child: _buildTuningBody(theme),
            ),
            const SizedBox(height: 12),
            SectionCard(
              icon: Icons.timer_outlined,
              title: 'Session Duration',
              status: StatusPill(
                active: true,
                label: _shortDuration(_sessionDurationSeconds),
              ),
              child: _buildDurationBody(theme),
            ),
            const SizedBox(height: 12),
            SectionCard(
              icon: Icons.lock_outline,
              title: 'Security',
              status: StatusPill(
                active: _lockOn,
                label: _lockStatusPillLabel(),
              ),
              child: _buildSecurityBody(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemPromptBody(ThemeData theme) {
    if (_defaultsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: NeoTheme.green),
        ),
      );
    }
    final hasUnsaved = _promptController.text.trim() != _savedPrompt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sets the persona and behavior for all new chats. '
          'You can also override this per-conversation from the chat tuning panel.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _promptController,
          maxLines: 5,
          minLines: 3,
          style: const TextStyle(fontSize: 13, height: 1.4),
          decoration: InputDecoration(
            hintText:
                'e.g. "You are a concise technical assistant. '
                'Respond in short paragraphs with no filler."',
            hintStyle: TextStyle(
              fontSize: 12,
              color: theme.hintColor.withValues(alpha: 0.5),
              height: 1.4,
            ),
            hintMaxLines: 3,
            filled: true,
            fillColor: NeoTheme.mainPanelFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: NeoTheme.mainPanelOutline()),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: NeoTheme.mainPanelOutline()),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: NeoTheme.green.withValues(alpha: 0.6),
              ),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Tooltip(
              message:
                  'Tip: Start with "You are..." to define the assistant\'s role,\n'
                  'then add style rules like "Be concise" or "Use bullet points".',
              preferBelow: false,
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 14,
                    color: NeoTheme.green.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Prompt tips',
                    style: TextStyle(
                      fontSize: 11,
                      color: NeoTheme.green.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_savedPrompt.isNotEmpty)
              TextButton(
                onPressed: () {
                  _promptController.clear();
                  _saveDefaults(snackMessage: 'System prompt cleared');
                },
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: hasUnsaved
                  ? () => _saveDefaults(
                      snackMessage: _promptController.text.trim().isEmpty
                          ? 'System prompt cleared'
                          : 'Default system prompt saved',
                    )
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: NeoTheme.green,
                disabledBackgroundColor: NeoTheme.green.withValues(alpha: 0.2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: Text(
                'Save',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasUnsaved ? Colors.black : const Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTuningBody(ThemeData theme) {
    if (_defaultsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: NeoTheme.green),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Default generation parameters for new conversations. '
          'Override per-conversation from the chat tuning panel.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        _buildSlider(
          label: 'Temperature',
          tooltip:
              'Controls randomness. Lower = more focused; higher = more creative.',
          value: _temperature,
          min: 0.0,
          max: 2.0,
          divisions: 20,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) {
            setState(() => _temperature = v);
            _saveDefaults();
          },
        ),
        const SizedBox(height: 8),
        _buildSlider(
          label: 'Top P',
          tooltip:
              'Nucleus sampling. Limits token choices to the top P probability mass.',
          value: _topP,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) {
            setState(() => _topP = v);
            _saveDefaults();
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Max Tokens', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Tooltip(
                    message:
                        'Maximum tokens in the response. Higher = longer replies.',
                    preferBelow: false,
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 4),
                    child: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: _maxTokens > 64
                  ? () {
                      setState(
                        () => _maxTokens = (_maxTokens - 256).clamp(64, 16384),
                      );
                      _saveDefaults();
                    }
                  : null,
            ),
            Text(
              '$_maxTokens',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: _maxTokens < 16384
                  ? () {
                      setState(
                        () => _maxTokens = (_maxTokens + 256).clamp(64, 16384),
                      );
                      _saveDefaults();
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSlider(
          label: 'Frequency Penalty',
          tooltip:
              'Penalises tokens based on how often they appeared. Reduces repetition.',
          value: _frequencyPenalty,
          min: 0.0,
          max: 2.0,
          divisions: 20,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) {
            setState(() => _frequencyPenalty = v);
            _saveDefaults();
          },
        ),
        const SizedBox(height: 8),
        _buildSlider(
          label: 'Presence Penalty',
          tooltip:
              'Penalises tokens that appeared at all. Encourages new topics.',
          value: _presencePenalty,
          min: 0.0,
          max: 2.0,
          divisions: 20,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) {
            setState(() => _presencePenalty = v);
            _saveDefaults();
          },
        ),
        if (_hasTuningOverrides) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _temperature = DefaultTuningStore.defaultTemperature;
                  _topP = DefaultTuningStore.defaultTopP;
                  _maxTokens = DefaultTuningStore.defaultMaxTokens;
                  _frequencyPenalty =
                      DefaultTuningStore.defaultFrequencyPenalty;
                  _presencePenalty = DefaultTuningStore.defaultPresencePenalty;
                });
                _saveDefaults(snackMessage: 'Tuning reset to defaults');
              },
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text(
                'Reset to defaults',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required String tooltip,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Tooltip(
              message: tooltip,
              preferBelow: false,
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 4),
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: const Color(0xFF6B7280),
              ),
            ),
            const Spacer(),
            Text(
              format(value),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: NeoTheme.green,
            inactiveTrackColor: const Color(0xFF374151),
            thumbColor: NeoTheme.green,
            overlayColor: NeoTheme.green.withValues(alpha: 0.12),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildDurationBody(ThemeData theme) {
    if (_durationLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: NeoTheme.green),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, sec) in SessionDurationStore.presets)
              ChoiceChip(
                label: Text(label),
                selected: _sessionDurationSeconds == sec,
                onSelected: (_) => _saveDuration(sec),
                selectedColor: NeoTheme.green.withValues(alpha: 0.18),
                side: BorderSide(
                  color: _sessionDurationSeconds == sec
                      ? NeoTheme.green.withValues(alpha: 0.5)
                      : const Color(0xFF374151),
                ),
                labelStyle: TextStyle(
                  color: _sessionDurationSeconds == sec
                      ? NeoTheme.green
                      : const Color(0xFF9CA3AF),
                  fontWeight: _sessionDurationSeconds == sec
                      ? FontWeight.w600
                      : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'How long each on-chain chat session lasts. Affects estimated MOR stake.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  String _lockStatusPillLabel() {
    switch (_lockMode) {
      case LockMode.off:
        return 'Off';
      case LockMode.biometricOnly:
        return _bio.name;
      case LockMode.passwordOnly:
        return 'Password';
      case LockMode.passwordWithBiometric:
        return '${_bio.name} + password';
    }
  }

  String _lockBodyDescription() {
    switch (_lockMode) {
      case LockMode.off:
        return 'Require ${_bio.name} or a password before using the app. '
            'Separate from your wallet private key.';
      case LockMode.biometricOnly:
        return 'Unlocking with ${_bio.name}. Add a backup password to '
            'unlock when biometrics fail (e.g. mask, sunglasses).';
      case LockMode.passwordOnly:
        return _bioAvailable
            ? 'Unlocking with a password. Turn on ${_bio.name} below for '
                  'a faster unlock.'
            : 'Unlocking with a password. Biometrics are not available on '
                  'this device.';
      case LockMode.passwordWithBiometric:
        return 'Unlocking with ${_bio.name}, password as fallback.';
    }
  }

  Widget _buildSecurityBody(ThemeData theme) {
    if (_securityLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: NeoTheme.green),
        ),
      );
    }
    final hasPw = _lockMode == LockMode.passwordOnly ||
        _lockMode == LockMode.passwordWithBiometric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _lockBodyDescription(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        if (!_lockOn)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openEnableLock,
              style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Turn on app lock'),
            ),
          )
        else ...[
          if (hasPw)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _openChangePassword,
                child: const Text('Change app password'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addBackupPassword,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add backup password'),
              ),
            ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Unlock with ${_bio.name}',
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              _bioAvailable
                  ? (_lockMode == LockMode.biometricOnly
                        ? 'Add a backup password before turning this off.'
                        : '${_bio.name} unlocks instantly on this device.')
                  : 'Not available on this device.',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
            value: _bioOn,
            onChanged: (!_bioAvailable && !_bioOn)
                ? null
                : (v) => _setBiometric(v),
            activeThumbColor: NeoTheme.green,
          ),
          if (_lockMode == LockMode.passwordWithBiometric) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _removeBackupPassword,
                child: Text(
                  'Remove backup password',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _confirmDisableLock,
              child: const Text(
                'Turn off app lock',
                style: TextStyle(fontSize: 12, color: Color(0xFFF87171)),
              ),
            ),
          ),
        ],

        if (PlatformCaps.supportsIcloudKeychainSync) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF374151)),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'iCloud Keychain sync',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              _icloudSync
                  ? 'Wallet secret syncs across your Apple devices.'
                  : 'Wallet secret stays on this device only.',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
            value: _icloudSync,
            onChanged: _icloudSyncChanging ? null : (v) => _setICloudSync(v),
            activeThumbColor: NeoTheme.green,
          ),
          if (_icloudSync)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NeoTheme.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: NeoTheme.amber.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: NeoTheme.amber.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Anyone with access to your Apple ID can read the synced wallet secret.',
                        style: TextStyle(
                          fontSize: 10,
                          color: NeoTheme.amber.withValues(alpha: 0.85),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Inline notice that explains the scope of these preferences vs requests
/// that flow through the local AI Gateway. Desktop-only — mobile builds
/// don't ship the gateway and the [SessionsScreen] gates this widget out
/// before it ever renders.
///
/// Collapsed by default to keep the Preferences screen visually quiet — the
/// information is important the first time you read it, but tedious every
/// other visit. Tapping the row expands the full passthrough explanation.
/// This was the on-device feedback from validation 2026-05-01: the original
/// always-on green-bordered card dominated the screen on every return visit.
class _GatewayScopeNotice extends StatefulWidget {
  const _GatewayScopeNotice();

  @override
  State<_GatewayScopeNotice> createState() => _GatewayScopeNoticeState();
}

class _GatewayScopeNoticeState extends State<_GatewayScopeNotice> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = NeoTheme.green.withValues(alpha: 0.85);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: _expanded
                ? NeoTheme.green.withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _expanded
                  ? NeoTheme.green.withValues(alpha: 0.18)
                  : NeoTheme.mainPanelOutline(0.25),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: accentColor),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'These preferences apply to Node Neo chats only',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 4, 2),
                        child: Text(
                          'Requests that flow through the AI Gateway '
                          '(Cursor, Zed, curl, or any OpenAI-compatible '
                          'client) are passed through verbatim — the calling '
                          'application controls its own system prompt, tools, '
                          'temperature, and max_tokens. Override them on the '
                          'caller side, not here.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: const Color(0xFFD1D5DB),
                            height: 1.45,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
