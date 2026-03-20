import 'package:flutter_test/flutter_test.dart';
import 'package:redpill/utils/token_amount.dart';

void main() {
  group('normalizeHumanAmountInput', () {
    test('trims and strips inner spaces', () {
      expect(normalizeHumanAmountInput('  0.05  '), '0.05');
      expect(normalizeHumanAmountInput('1 234,56'), '1234.56');
    });
    test('comma as decimal separator', () {
      expect(normalizeHumanAmountInput('0,05'), '0.05');
    });
    test('US thousands', () {
      expect(normalizeHumanAmountInput('1,234.56'), '1234.56');
    });
    test('EU thousands', () {
      expect(normalizeHumanAmountInput('1.234,56'), '1234.56');
    });
  });

  group('parseTokenAmountToWei', () {
    test('0.05 MOR-style', () {
      final w = parseTokenAmountToWei('0.05');
      expect(w, BigInt.parse('50000000000000000'));
    });
    test('0,05', () {
      final w = parseTokenAmountToWei('0,05');
      expect(w, BigInt.parse('50000000000000000'));
    });
    test('1 ETH whole', () {
      final w = parseTokenAmountToWei('1');
      expect(w, BigInt.parse('1000000000000000000'));
    });
    test('reject zero / empty', () {
      expect(parseTokenAmountToWei(''), isNull);
      expect(parseTokenAmountToWei('0'), isNull);
      expect(parseTokenAmountToWei('0.0'), isNull);
    });
    test('truncates beyond 18 fractional digits', () {
      final w20 = parseTokenAmountToWei('0.${'1' * 20}');
      final w18 = parseTokenAmountToWei('0.${'1' * 18}');
      expect(w20, w18);
    });
  });

  group('round-trip preview', () {
    test('0.05 displays as MOR 2dp', () {
      final w = parseTokenAmountToWei('0.05')!;
      expect(formatWeiForSendPreview(w, isMor: true), '0.05');
    });
  });
}
