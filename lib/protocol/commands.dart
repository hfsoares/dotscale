import 'dart:typed_data';

import 'crc16.dart';

// Frame da Dot, nos dois sentidos (big-endian):
//   A5 5A | classe | tipo | tamanho do payload (2) | payload | CRC-16/MODBUS (2)

const kMagic0 = 0xA5;
const kMagic1 = 0x5A;

const kClassNotify = 0x01;
const kClassQuery = 0x02;
const kClassCommand = 0x03;

const kTypeWeight = 0x01;
const kTypeBattery = 0x05;
const kTypeUnit = 0x06;
const kTypeMode = 0x08;
const kTypeTare = 0x0D;

Uint8List buildFrame(int frameClass, int type, [List<int> payload = const []]) {
  final frame = Uint8List(6 + payload.length + 2);
  frame[0] = kMagic0;
  frame[1] = kMagic1;
  frame[2] = frameClass;
  frame[3] = type;
  frame[4] = payload.length >> 8;
  frame[5] = payload.length & 0xFF;
  frame.setRange(6, 6 + payload.length, payload);
  final crc = crc16Modbus(frame.sublist(0, 6 + payload.length));
  frame[frame.length - 2] = crc >> 8;
  frame[frame.length - 1] = crc & 0xFF;
  return frame;
}

/// Comandos enviados para FFF2. `02 04` é uma consulta, não a tara.
abstract final class DotCommands {
  static Uint8List tare() => buildFrame(kClassCommand, kTypeTare);
  static Uint8List unitGrams() => buildFrame(kClassCommand, kTypeUnit, const [0x00]);
  static Uint8List standardMode() => buildFrame(kClassCommand, kTypeMode, const [0x01, 0x00]);
}
