import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/logic/ai.dart';
import 'package:spicci/logic/analysis.dart';

void main() {
  final categories = {1: const Category(id: 1, name: 'Food', type: 'OUT')};
  final txns = [
    Txn(
      date: DateTime(2026, 11, 3),
      amountCents: 4250,
      type: TxType.expense,
      accountId: 1,
      categoryId: 1,
      note: 'Dinner with Marco at secret place',
    ),
    Txn(date: DateTime(2026, 11, 1), amountCents: 200000, type: TxType.income, accountId: 1, note: 'ACME salary'),
  ];

  test('payload holds only aggregates, never notes', () {
    final payload = aiPayload(txns, Period.month(DateTime(2026, 11)), categories);
    final json = jsonEncode(payload);
    expect(json, isNot(contains('Marco')));
    expect(json, isNot(contains('ACME')));
    expect(payload['expenses'], 42.5);
    expect((payload['expensesByCategory'] as List).single, {'category': 'Food', 'amount': 42.5, 'previousPeriod': 0.0});
  });

  test('chat sends the key and model and returns the reply', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': ' - Spese in calo '},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final ai = AiClient(baseUrl: 'https://api.example.com/v1/', apiKey: 'k', model: 'm', client: client);
    expect(await ai.chat('sys', 'user'), '- Spese in calo');
    expect(sent.url.toString(), 'https://api.example.com/v1/chat/completions');
    expect(sent.headers['Authorization'], 'Bearer k');
    expect((jsonDecode(sent.body) as Map)['model'], 'm');
  });

  test('errors carry the provider message; models are listed', () async {
    final client = MockClient(
      (req) async => req.url.path.endsWith('models')
          ? http.Response(
              jsonEncode({
                'data': [
                  {'id': 'b'},
                  {'id': 'a'},
                ],
              }),
              200,
            )
          : http.Response(
              jsonEncode({
                'error': {'message': 'Invalid API key'},
              }),
              401,
            ),
    );
    final ai = AiClient(baseUrl: 'https://x/v1', apiKey: 'k', model: 'm', client: client);
    expect(await ai.models(), ['a', 'b']);
    expect(() => ai.chat('s', 'u'), throwsA(predicate((e) => '$e'.contains('Invalid API key'))));
  });
}
