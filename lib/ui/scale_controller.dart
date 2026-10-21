import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/scale_connection.dart';
import '../protocol/dot_event.dart';

/// Junta os streams da conexão num estado único para a tela.
class ScaleController extends ChangeNotifier {
  ScaleController(
    this.connection, {
    this.logCapacity = 200,
    this.onLiveChanged,
    this.staleAfter = const Duration(seconds: 2),
  }) : _status = connection.currentStatus {
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
  final Duration staleAfter;

  /// Chamado quando a balança passa a transmitir ao vivo ou deixa de transmitir (ex.: para a tela ficar acesa).
  final void Function(bool live)? onLiveChanged;

  late final List<StreamSubscription<Object?>> _subs;
  ConnectionStatus _status;
  WeightReading? _lastWeight;
  int? _batteryPercent;
  List<FoundScale> _found = const [];
  final List<FrameLogEntry> _log = [];
  bool _stale = false;
  Timer? _staleTimer;

  ConnectionStatus get status => _status;
  WeightReading? get lastWeight => _lastWeight;
  int? get batteryPercent => _batteryPercent;
  List<FoundScale> get found => _found;
  List<FrameLogEntry> get log => List.unmodifiable(_log);
  /// Conectado e recebendo peso: o link BLE pode levar vários segundos para
  /// acusar a queda, então um peso parado também deixa de contar como ao vivo.
  bool get isLive => _status.phase == ConnectionPhase.connected && !_stale;

  void _updateLive(void Function() change) {
    final wasLive = isLive;
    change();
    if (wasLive != isLive) onLiveChanged?.call(isLive);
    notifyListeners();
  }

  void _onStatus(ConnectionStatus status) {
    _updateLive(() {
      _status = status;
      if (status.phase == ConnectionPhase.scanning) _found = const [];
      if (status.phase != ConnectionPhase.connected) _staleTimer?.cancel();
    });
  }

  void _onEvent(DotEvent event) {
    switch (event) {
      case WeightReading():
        _staleTimer?.cancel();
        _staleTimer = Timer(staleAfter, () => _updateLive(() => _stale = true));
        _updateLive(() {
          _lastWeight = event;
          _stale = false;
        });
        return;
      case BatteryReading(:final percent):
        _batteryPercent = percent;
      case UnknownReport():
        return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
