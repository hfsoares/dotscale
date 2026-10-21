import 'package:dotscale/protocol/commands.dart';
import 'package:dotscale/protocol/crc16.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crc16Modbus do vetor padrão "123456789"', () {
    expect(crc16Modbus('123456789'.codeUnits), 0x4B37);
  });

  test('tare bate com o frame conhecido', () {
    expect(DotCommands.tare(), [0xA5, 0x5A, 0x03, 0x0D, 0x00, 0x00, 0x64, 0xD1]);
  });

  test('unitGrams bate com o frame conhecido', () {
    expect(DotCommands.unitGrams(), [0xA5, 0x5A, 0x03, 0x06, 0x00, 0x01, 0x00, 0xE8, 0xA7]);
  });

  test('standardMode tem payload 01 00 e CRC válido', () {
    final f = DotCommands.standardMode();
    expect(f.sublist(0, 8), [0xA5, 0x5A, 0x03, 0x08, 0x00, 0x02, 0x01, 0x00]);
    final crc = crc16Modbus(f.sublist(0, 8));
    expect(f.sublist(8), [crc >> 8, crc & 0xFF]);
  });
}
