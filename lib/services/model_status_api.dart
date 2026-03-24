import 'dart:convert';

import 'package:http/http.dart' as http;

const _statusApiUrl = 'https://active.mor.org/status/api.json';

/// Parsed response from the Morpheus network status API.
class ModelStatusResponse {
  final String overallStatus;
  final int updatedAt;
  final String summary;
  final int totalModels;
  final int operationalModels;
  final int degradedModels;
  final int totalProviders;
  final int activeProviders;
  final List<ModelStatusEntry> models;

  const ModelStatusResponse({
    required this.overallStatus,
    required this.updatedAt,
    required this.summary,
    required this.totalModels,
    required this.operationalModels,
    required this.degradedModels,
    required this.totalProviders,
    required this.activeProviders,
    required this.models,
  });

  factory ModelStatusResponse.fromJson(Map<String, dynamic> j) {
    final mods = j['models'] as Map<String, dynamic>? ?? {};
    final provs = j['providers'] as Map<String, dynamic>? ?? {};
    final detail = (j['models_detail'] as List<dynamic>?) ?? [];
    return ModelStatusResponse(
      overallStatus: j['status'] as String? ?? 'unknown',
      updatedAt: j['updated_at'] as int? ?? 0,
      summary: j['summary'] as String? ?? '',
      totalModels: mods['total'] as int? ?? 0,
      operationalModels: mods['operational'] as int? ?? 0,
      degradedModels: mods['degraded'] as int? ?? 0,
      totalProviders: provs['total'] as int? ?? 0,
      activeProviders: provs['active'] as int? ?? 0,
      models: detail.map((e) => ModelStatusEntry.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class ModelStatusEntry {
  final String id;
  final String name;
  final String status;
  final String type;
  final List<String> tags;
  final int providers;
  final double minPriceMorHr;
  /// Rolling uptime percentages keyed by window: "6h", "24h", "7d", "14d".
  final Map<String, double> uptime;

  const ModelStatusEntry({
    required this.id,
    required this.name,
    required this.status,
    required this.type,
    required this.tags,
    required this.providers,
    required this.minPriceMorHr,
    this.uptime = const {},
  });

  bool get isTEE => tags.any((t) => t.toLowerCase() == 'tee');

  /// 6-hour availability; null when the API didn't supply uptime data.
  double? get uptime6h => uptime['6h'];

  factory ModelStatusEntry.fromJson(Map<String, dynamic> j) {
    final rawUptime = j['uptime'] as Map<String, dynamic>? ?? {};
    return ModelStatusEntry(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? 'Unknown',
      status: j['status'] as String? ?? 'unknown',
      type: j['type'] as String? ?? 'LLM',
      tags: (j['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      providers: j['providers'] as int? ?? 0,
      minPriceMorHr: (j['min_price_mor_hr'] as num?)?.toDouble() ?? 0,
      uptime: rawUptime.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }

  /// Format price for display; omit if zero or negligible.
  String? get formattedPrice {
    if (minPriceMorHr <= 0) return null;
    if (minPriceMorHr < 0.001) return '<0.001 MOR/hr';
    if (minPriceMorHr < 0.01) return '${minPriceMorHr.toStringAsFixed(4)} MOR/hr';
    return '${minPriceMorHr.toStringAsFixed(2)} MOR/hr';
  }
}

/// Fetches the Morpheus network status API. Timeout after 10 s.
Future<ModelStatusResponse> fetchModelStatus() async {
  final resp = await http.get(Uri.parse(_statusApiUrl)).timeout(const Duration(seconds: 10));
  if (resp.statusCode != 200) {
    throw Exception('Status API returned ${resp.statusCode}');
  }
  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  return ModelStatusResponse.fromJson(body);
}
