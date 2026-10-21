import 'dart:async';

import 'package:dotscale/ble/scale_connection.dart';
import 'package:dotscale/protocol/dot_event.dart';

class FakeScaleConnection implements ScaleConnection {
  final _status = StreamController<ConnectionStatus>.broadcast(sync: true);
  final _scan = StreamController<List<FoundScale>>.broadcast(sync: true);
  final _events = StreamController<DotEvent>.broadcast(sync: true);
  final _frames = StreamController<FrameLogEntry>.broadcast(sync: true);
  ConnectionStatus _current = const ConnectionStatus(ConnectionPhase.idle);
  final calls = <String>[];

  void emitStatus(ConnectionStatus s) {
    _current = s;
    _status.add(s);
  }

  void emitEvent(DotEvent e) => _events.add(e);
  void emitFound(List<FoundScale> f) => _scan.add(f);
  void emitFrame(FrameLogEntry f) => _frames.add(f);

  @override
  ConnectionStatus get currentStatus => _current;
  @override
  Stream<ConnectionStatus> get status => _status.stream;
  @override
  Stream<List<FoundScale>> get scanResults => _scan.stream;
  @override
  Stream<DotEvent> get events => _events.stream;
  @override
  Stream<FrameLogEntry> get frames => _frames.stream;

  @override
  Future<void> startScan() async => calls.add('startScan');
  @override
  Future<void> stopScan() async => calls.add('stopScan');
  @override
  Future<void> connect(String deviceId) async => calls.add('connect:$deviceId');
  @override
  Future<void> disconnect() async => calls.add('disconnect');
  @override
  Future<void> reconnectLast() async => calls.add('reconnectLast');
  @override
  void dispose() {}
}
