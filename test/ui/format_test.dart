import 'package:dotscale/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatGrams', () {
    expect(formatGrams(18.44), '18.4 g');
    expect(formatGrams(-2.5), '-2.5 g');
    expect(formatGrams(-0.04), '0.0 g');
  });

  test('formatFlow nunca mostra -0.0', () {
    expect(formatFlow(1.2), '1.2 g/s');
    expect(formatFlow(-0.01), '0.0 g/s');
  });
}
