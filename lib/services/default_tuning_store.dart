import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bridge.dart';

/// Persists user-chosen default tuning parameters and system prompt.
/// Stored in SQLite preferences (backed up with conversations).
class DefaultTuningStore {
  DefaultTuningStore._();
  static final DefaultTuningStore instance = DefaultTuningStore._();

  static const _prefKey = 'default_tuning_json';
  static const _legacyFileName = 'default_tuning.json';

  static const double defaultTemperature = 1.0;
  static const double defaultTopP = 1.0;
  static const int defaultMaxTokens = 2048;
  static const double defaultFrequencyPenalty = 0.0;
  static const double defaultPresencePenalty = 0.0;
  static const String defaultSystemPrompt = '';

  bool _migrated = false;

  Future<Map<String, dynamic>> read() async {
    try {
      await _migrateFromFileIfNeeded();
      final raw = GoBridge().getPreference(_prefKey);
      if (raw.isEmpty) return _hardDefaults;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'temperature': (json['temperature'] as num?)?.toDouble() ?? defaultTemperature,
        'top_p': (json['top_p'] as num?)?.toDouble() ?? defaultTopP,
        'max_tokens': (json['max_tokens'] as num?)?.toInt() ?? defaultMaxTokens,
        'frequency_penalty': (json['frequency_penalty'] as num?)?.toDouble() ?? defaultFrequencyPenalty,
        'presence_penalty': (json['presence_penalty'] as num?)?.toDouble() ?? defaultPresencePenalty,
        'system_prompt': json['system_prompt'] as String? ?? defaultSystemPrompt,
      };
    } catch (_) {
      return _hardDefaults;
    }
  }

  Future<void> write({
    required double temperature,
    required double topP,
    required int maxTokens,
    required double frequencyPenalty,
    required double presencePenalty,
    String systemPrompt = '',
  }) async {
    final json = jsonEncode({
      'temperature': temperature,
      'top_p': topP,
      'max_tokens': maxTokens,
      'frequency_penalty': frequencyPenalty,
      'presence_penalty': presencePenalty,
      'system_prompt': systemPrompt,
    });
    try {
      GoBridge().setPreference(_prefKey, json);
    } catch (_) {}
  }

  /// One-time migration: if the old file exists, read it, write to DB, delete file.
  Future<void> _migrateFromFileIfNeeded() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final d = await getApplicationSupportDirectory();
      final f = File('${d.path}${Platform.pathSeparator}nodeneo${Platform.pathSeparator}$_legacyFileName');
      if (!await f.exists()) return;
      final raw = await f.readAsString();
      final existing = GoBridge().getPreference(_prefKey);
      if (existing.isEmpty) {
        GoBridge().setPreference(_prefKey, raw.trim());
      }
      await f.delete();
    } catch (_) {}
  }

  static Map<String, dynamic> get _hardDefaults => {
        'temperature': defaultTemperature,
        'top_p': defaultTopP,
        'max_tokens': defaultMaxTokens,
        'frequency_penalty': defaultFrequencyPenalty,
        'presence_penalty': defaultPresencePenalty,
        'system_prompt': defaultSystemPrompt,
      };
}
