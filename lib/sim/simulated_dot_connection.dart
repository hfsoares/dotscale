import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ble/scale_connection.dart';
import '../protocol/dot_event.dart';

/// Um trecho do roteiro: o peso vai de [from] até [to] em [duration] (com [from] == [to], parado).
/// [mark] aparece no log como `SIMSHOT <mark>` 1,5 s antes de o trecho terminar (hora de tirar o
/// screenshot com a tela já assentada); [action] roda no início.
class SimSegment {
  const SimSegment(this.from, this.to, this.duration, {this.mark, this.action});

  const SimSegment.hold(double grams, Duration duration, {String? mark, void Function()? action})
    : this(grams, grams, duration, mark: mark, action: action);

  final double from;
  final double to;
  final Duration duration;
  final String? mark;
  final void Function()? action;
}

/// Balança de mentira para demonstrar o app sem a Dot: conecta sozinha e toca um roteiro de pesos
/// com o ritmo e o ruído da Dot real.
class SimulatedDotConnection implements ScaleConnection {
  SimulatedDotConnection(this.script, {this.startDelay = const Duration(seconds: 3)});

  final List<SimSegment> script;
  final Duration startDelay;

  final _status = StreamController<ConnectionStatus>.broadcast();
  final _scan = StreamController<List<FoundScale>>.broadcast();
  final _events = StreamController<DotEvent>.broadcast();
  final _frames = StreamController<FrameLogEntry>.broadcast();
  final _random = Random(7);
  ConnectionStatus _current = const ConnectionStatus(ConnectionPhase.idle);
  double _zero = 0;
  double _last = 0;
  bool _running = false;

  static const _markLead = Duration(milliseconds: 1500);

  // Intervalos medidos na Dot.
  static const _intervals = [93, 94, 112];

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
  Future<void> reconnectLast() async {
    if (_running) return;
    _running = true;
    _emitStatus(const ConnectionStatus(ConnectionPhase.connected, deviceName: 'Dot simulada'));
    _events.add(const BatteryReading(87));
    unawaited(_play());
  }

  Future<void> _play() async {
    await _hold(0, startDelay);
    debugPrint('SIMSHOT start');
    for (final segment in script) {
      segment.action?.call();
      final before = segment.mark == null ? segment.duration : segment.duration - _markLead;
      final split =
          segment.from + (segment.to - segment.from) * before.inMilliseconds / segment.duration.inMilliseconds;
      await _ramp(segment.from, split, before);
      if (segment.mark != null) {
        debugPrint('SIMSHOT ${segment.mark}');
        await _ramp(split, segment.to, _markLead);
      }
    }
    debugPrint('SIMSHOT end');
    while (_running) {
      await _hold(_last, const Duration(seconds: 1));
    }
  }

  Future<void> _hold(double grams, Duration duration) => _ramp(grams, grams, duration);

  Future<void> _ramp(double from, double to, Duration duration) async {
    var elapsed = 0;
    var i = 0;
    final total = duration.inMilliseconds;
    while (elapsed < total) {
      final step = _intervals[i++ % _intervals.length];
      await Future<void>.delayed(Duration(milliseconds: step));
      elapsed += step;
      final target = from + (to - from) * min(1, elapsed / total);
      _emit(target, step);
    }
  }

  void _emit(double grams, int ms) {
    // Ruído de ±0,1 g de vez em quando, como a Dot.
    final noise = _random.nextDouble() < 0.15 ? (_random.nextBool() ? 0.1 : -0.1) : 0.0;
    final shown = ((grams - _zero + noise) * 10).round() / 10;
    final flow = (shown - _last) * 1000 / ms;
    _last = shown;
    _events.add(WeightReading(grams: shown, flowGramsPerSecond: flow, timerSeconds: 0, overload: false));
  }

  void _emitStatus(ConnectionStatus status) {
    _current = status;
    _status.add(status);
  }

  @override
  Future<void> tare() async => _zero += _last;
  @override
  Future<void> startScan() async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<void> disconnect() async {
    _running = false;
    _emitStatus(const ConnectionStatus(ConnectionPhase.idle));
  }

  @override
  void dispose() => _running = false;
}
