import 'package:dotscale/espresso/espresso_session.dart';

const tick = Duration(milliseconds: 100);

/// Alimenta a sessão com leituras a cada 100 ms, como a Dot.
class SessionDriver {
  SessionDriver(this.session, {DateTime? start, this.noisy = false}) : now = start ?? DateTime(2026, 10, 21, 13);

  final EspressoSession session;
  DateTime now;

  /// Soma um ruído determinístico de ±0,1 g, como a Dot parada.
  bool noisy;
  static const _noise = [0.0, 0.1, -0.1, 0.05, -0.05, 0.1, 0.0, -0.1];
  int _i = 0;

  void _add(double grams) {
    session.addReading(now, noisy ? grams + _noise[_i++ % _noise.length] : grams);
    now = now.add(tick);
  }

  void hold(double grams, Duration d) {
    for (var i = 0; i < d.inMilliseconds ~/ tick.inMilliseconds; i++) {
      _add(grams);
    }
  }

  void ramp(double from, double to, Duration d) {
    final n = d.inMilliseconds ~/ tick.inMilliseconds;
    for (var i = 1; i <= n; i++) {
      _add(from + (to - from) * i / n);
    }
  }

  void wait(Duration d) => now = now.add(d);

  /// Leituras avulsas, uma por tick (ex.: o tranco de levantar a balança).
  void readings(List<double> values) => values.forEach(_add);
}
