import 'package:dotscale/ble/dot_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconhece nomes da Dot', () {
    expect(isDotName('TIMEMORE_Dot_A1B2'), isTrue);
    expect(isDotName('xx-TES017-yy'), isTrue);
    expect(isDotName('timemore_dot'), isTrue);
  });

  test('rejeita outros nomes', () {
    expect(isDotName('Timemore Scale'), isFalse);
    expect(isDotName(''), isFalse);
  });
}
