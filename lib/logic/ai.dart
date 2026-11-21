import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import 'analysis.dart';

/// An OpenAI-compatible provider. [trains] marks free tiers that may use data for training.
class AiPreset {
  const AiPreset(this.id, this.name, this.baseUrl, {this.trains = false});
  final String id;
  final String name;
  final String baseUrl;
  final bool trains;
}

const aiPresets = [
  AiPreset('groq', 'Groq', 'https://api.groq.com/openai/v1'),
  AiPreset('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1'),
  AiPreset('gemini', 'Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai', trains: true),
  AiPreset('mistral', 'Mistral', 'https://api.mistral.ai/v1', trains: true),
  AiPreset('cerebras', 'Cerebras', 'https://api.cerebras.ai/v1'),
  AiPreset('custom', 'Custom', ''),
];

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiClient {
  AiClient({required this.baseUrl, required this.apiKey, required this.model, http.Client? client})
    : _http = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/$path');
  Map<String, String> get _headers => {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'};

  /// Model ids the provider offers, so the user picks a real one instead of typing it.
  Future<List<String>> models() async {
    final r = await _http.get(_uri('models'), headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw AiException('HTTP ${r.statusCode}: ${_error(r.body)}');
    final data = (jsonDecode(r.body) as Map)['data'] as List;
    return [for (final m in data) (m as Map)['id'] as String]..sort();
  }

  Future<String> chat(String system, String user) async {
    final r = await _http
        .post(
          _uri('chat/completions'),
          headers: _headers,
          body: jsonEncode({
            'model': model,
            'temperature': 0.4,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw AiException('HTTP ${r.statusCode}: ${_error(r.body)}');
    final content =
        (((jsonDecode(utf8.decode(r.bodyBytes)) as Map)['choices'] as List).first as Map)['message']['content'];
    return (content as String).trim();
  }

  static String _error(String body) {
    try {
      final e = (jsonDecode(body) as Map)['error'];
      return e is Map ? '${e['message']}' : '$e';
    } on Object {
      return body.length > 200 ? body.substring(0, 200) : body;
    }
  }
}

/// The only data sent to the provider: totals per category and per month.
/// Notes, tags, account names and single transactions never leave the phone.
Map<String, Object?> aiPayload(Iterable<Txn> txns, Period p, Map<int, Category> categories) {
  double eur(int cents) => cents / 100;
  final t = totals(txns, p);
  final prev = totals(txns, p.previous);
  return {
    'period': p.isYear ? '${p.start.year}' : '${p.start.year}-${p.start.month.toString().padLeft(2, '0')}',
    'currency': 'EUR',
    'income': eur(t.incomeCents),
    'expenses': eur(t.expenseCents),
    'previousPeriod': {'income': eur(prev.incomeCents), 'expenses': eur(prev.expenseCents)},
    'expensesByCategory': [
      for (final s in categoryBreakdown(txns, p, categories))
        {
          'category': categories[s.categoryId]?.name ?? 'Uncategorised',
          'amount': eur(s.cents),
          'previousPeriod': eur(s.previousCents),
        },
    ],
    'last6Months': [
      for (final (m, mt) in monthlySeries(txns, p.isYear ? DateTime(p.start.year, 12) : p.start, count: 6))
        {
          'month': '${m.year}-${m.month.toString().padLeft(2, '0')}',
          'income': eur(mt.incomeCents),
          'expenses': eur(mt.expenseCents),
        },
    ],
  };
}

String aiSystemPrompt(String language) =>
    'You are a calm personal-finance assistant. You receive aggregated spending data as JSON. '
    'All numbers are already correct: never recompute or invent figures, only quote them. '
    'Write 3 to 5 short bullet points in $language: what changed versus the previous period, '
    'the categories that matter most, and one practical suggestion. No greetings, no disclaimers.';
