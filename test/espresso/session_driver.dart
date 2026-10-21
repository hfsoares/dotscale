import 'package:dotscale/espresso/espresso_session.dart';

const tick = Duration(milliseconds: 100);

/// Alimenta a sessão com leituras a cada 100 ms, como a Dot.
class SessionDriver {
  SessionDriver(this.session, {DateTime? start}) : now = start ?? DateTime(2026, 10, 21, 13);

  final EspressoSession session;
  DateTime now;

  void hold(double grams, Duration d) {
    for (var i = 0; i < d.inMilliseconds ~/ tick.inMilliseconds; i++) {
      session.addReading(now, grams);
      now = now.add(tick);
    }
  }

  void ramp(double from, double to, Duration d) {
    final n = d.inMilliseconds ~/ tick.inMilliseconds;
    for (var i = 1; i <= n; i++) {
      session.addReading(now, from + (to - from) * i / n);
      now = now.add(tick);
    }
  }

  void wait(Duration d) => now = now.add(d);
}
