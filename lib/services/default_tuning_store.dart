import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists user-chosen default tuning parameters so new conversations
/// start with these values instead of the hard-coded defaults.
class DefaultTuningStore {
  DefaultTuningStore._();
  static final DefaultTuningStore instance = DefaultTuningStore._();

  static const _fileName = 'default_tuning.json';

  static const double defaultTemperature = 1.0;
  static const double defaultTopP = 1.0;
  static const int defaultMaxTokens = 2048;
  static const double defaultFrequencyPenalty = 0.0;
  static const double defaultPresencePenalty = 0.0;

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}nodeneo');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<Map<String, dynamic>> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return _hardDefaults;
      final raw = await f.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'temperature': (json['temperature'] as num?)?.toDouble() ?? defaultTemperature,
        'top_p': (json['top_p'] as num?)?.toDouble() ?? defaultTopP,
        'max_tokens': (json['max_tokens'] as num?)?.toInt() ?? defaultMaxTokens,
        'frequency_penalty': (json['frequency_penalty'] as num?)?.toDouble() ?? defaultFrequencyPenalty,
        'presence_penalty': (json['presence_penalty'] as num?)?.toDouble() ?? defaultPresencePenalty,
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
  }) async {
    final f = await _file();
    await f.writeAsString(
      jsonEncode({
        'temperature': temperature,
        'top_p': topP,
        'max_tokens': maxTokens,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
      }),
      flush: true,
    );
  }

  static Map<String, dynamic> get _hardDefaults => {
        'temperature': defaultTemperature,
        'top_p': defaultTopP,
        'max_tokens': defaultMaxTokens,
        'frequency_penalty': defaultFrequencyPenalty,
        'presence_penalty': defaultPresencePenalty,
      };
}
