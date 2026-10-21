import 'dart:typed_data';

import 'commands.dart';
import 'crc16.dart';
import 'dot_event.dart';

const _headerLength = 6;
const _trailerLength = 2;
// Frames reais têm no máximo 9 bytes de payload; mais que isso é dessincronização.
const _maxPayloadLength = 64;

class DecodedFrame {
  final Uint8List bytes;
  final int frameClass;
  final int type;
  final Uint8List payload;
  final bool crcOk;
  final DotEvent? event;

  const DecodedFrame({
    required this.bytes,
    required this.frameClass,
    required this.type,
    required this.payload,
    required this.crcOk,
    required this.event,
  });
}

/// Remonta o stream de notificações: um frame pode vir em pedaços,
/// ou vários frames na mesma notificação.
class FrameDecoder {
  final List<int> _buffer = [];

  List<DecodedFrame> add(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = <DecodedFrame>[];
    while (true) {
      final start = _buffer.indexOf(kMagic0);
      if (start < 0) {
        _buffer.clear();
        break;
      }
      _buffer.removeRange(0, start);
      if (_buffer.length < _headerLength + _trailerLength) break;

      final payloadLength = (_buffer[4] << 8) | _buffer[5];
      if (_buffer[1] != kMagic1 || payloadLength > _maxPayloadLength) {
        _buffer.removeAt(0);
        continue;
      }
      final frameLength = _headerLength + payloadLength + _trailerLength;
      if (_buffer.length < frameLength) break;

      frames.add(_decode(Uint8List.fromList(_buffer.sublist(0, frameLength))));
      _buffer.removeRange(0, frameLength);
    }
    return frames;
  }

  void reset() => _buffer.clear();

  DecodedFrame _decode(Uint8List bytes) {
    final bodyLength = bytes.length - _trailerLength;
    final received = (bytes[bodyLength] << 8) | bytes[bodyLength + 1];
    final frameClass = bytes[2];
    final type = bytes[3];
    final payload = Uint8List.sublistView(bytes, _headerLength, bodyLength);
    return DecodedFrame(
      bytes: bytes,
      frameClass: frameClass,
      type: type,
      payload: payload,
      // O CRC de entrada ainda não foi confirmado em hardware: só marca, não descarta.
      crcOk: crc16Modbus(bytes.sublist(0, bodyLength)) == received,
      event: _event(frameClass, type, payload),
    );
  }

  DotEvent? _event(int frameClass, int type, Uint8List payload) {
    if (frameClass != kClassNotify && frameClass != kClassQuery) return null;
    final data = ByteData.sublistView(payload);
    if (type == kTypeWeight && payload.length >= 8) {
      return WeightReading(
        grams: data.getInt32(0) / 10,
        flowGramsPerSecond: data.getInt16(4) / 10,
        timerSeconds: data.getUint16(6),
        overload: payload.length > 8 && payload[8] != 0,
      );
    }
    if (type == kTypeBattery && payload.length >= 2) return BatteryReading(payload[1]);
    return UnknownReport(frameClass, type, List.unmodifiable(payload));
  }
}
