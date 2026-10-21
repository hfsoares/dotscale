import 'dart:typed_data';

import '../protocol/dot_event.dart';

enum ConnectionPhase {
  idle,
  bluetoothOff,
  permissionDenied,
  scanning,
  connecting,
  pairing,
  connected,
  reconnecting,
  error,
}

class ConnectionStatus {
  final ConnectionPhase phase;
  final String? deviceName;
  final String? message;

  const ConnectionStatus(this.phase, {this.deviceName, this.message});
}

class FoundScale {
  final String id;
  final String name;
  final int rssi;

  const FoundScale(this.id, this.name, this.rssi);
}

class FrameLogEntry {
  final DateTime at;
  final bool outgoing;
  final Uint8List bytes;
  final bool crcOk;

  const FrameLogEntry({required this.at, required this.outgoing, required this.bytes, this.crcOk = true});
}

abstract class ScaleConnection {
  ConnectionStatus get currentStatus;
  Stream<ConnectionStatus> get status;
  Stream<List<FoundScale>> get scanResults;
  Stream<DotEvent> get events;

  /// RX (frames decodificados) e TX (comandos enviados).
  Stream<FrameLogEntry> get frames;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);

  /// Desconexão pedida pelo usuário: sem reconexão automática.
  Future<void> disconnect();

  /// Reconecta à última balança conhecida; sem nenhuma, procura balanças.
  Future<void> reconnectLast();

  void dispose();
}
