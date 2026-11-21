import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/format.dart';

void main() {
  test('amounts parse with either decimal separator, whatever the locale', () {
    expect(parseAmount('12,50'), 12.5);
    expect(parseAmount('12.50'), 12.5);
    expect(parseAmount('1.234,5'), 1234.5);
    expect(parseAmount('1,234.56'), 1234.56);
    expect(parseAmount(' 8 '), 8);
    expect(parseAmount('−20,5'), -20.5);
    expect(parseAmount(''), isNull);
    expect(parseAmount('abc'), isNull);
  });
}
