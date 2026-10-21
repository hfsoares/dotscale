import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/scale_connection.dart';
import '../protocol/dot_event.dart';

/// Junta os streams da conexão num estado único para a tela.
class ScaleController extends ChangeNotifier {
  ScaleController(this.connection, {this.logCapacity = 200, this.onLiveChanged}) : _status = connection.currentStatus {
    _subs = [
      connection.status.listen(_onStatus),
      connection.events.listen(_onEvent),
      connection.scanResults.listen((found) {
        _found = found;
        notifyListeners();
      }),
      connection.frames.listen((entry) {
        _log.insert(0, entry);
        if (_log.length > logCapacity) _log.removeLast();
        notifyListeners();
      }),
    ];
  }

  final ScaleConnection connection;
  final int logCapacity;

  /// Chamado quando a balança passa a transmitir ao vivo ou deixa de transmitir (ex.: para a tela ficar acesa).
  final void Function(bool live)? onLiveChanged;

  late final List<StreamSubscription<Object?>> _subs;
  ConnectionStatus _status;
  WeightReading? _lastWeight;
  int? _batteryPercent;
  List<FoundScale> _found = const [];
  final List<FrameLogEntry> _log = [];

  ConnectionStatus get status => _status;
  WeightReading? get lastWeight => _lastWeight;
  int? get batteryPercent => _batteryPercent;
  List<FoundScale> get found => _found;
  List<FrameLogEntry> get log => List.unmodifiable(_log);
  bool get isLive => _status.phase == ConnectionPhase.connected;

  void _onStatus(ConnectionStatus status) {
    final wasLive = isLive;
    _status = status;
    if (status.phase == ConnectionPhase.scanning) _found = const [];
    if (wasLive != isLive) onLiveChanged?.call(isLive);
    notifyListeners();
  }

  void _onEvent(DotEvent event) {
    switch (event) {
      case WeightReading():
        _lastWeight = event;
      case BatteryReading(:final percent):
        _batteryPercent = percent;
      case UnknownReport():
        return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
