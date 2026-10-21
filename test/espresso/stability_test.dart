import 'package:dotscale/espresso/stability.dart';
import 'package:dotscale/espresso/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 21, 13);

/// Envia [values] a cada 100 ms a partir de [start]; devolve o instante seguinte.
DateTime feed(StabilityTracker tracker, DateTime start, List<double> values) {
  var at = start;
  for (final v in values) {
    tracker.add(at, v);
    at = at.add(const Duration(milliseconds: 100));
  }
  return at;
}

void main() {
  late StabilityTracker tracker;
  setUp(() => tracker = StabilityTracker(const EspressoTuning()));

  test('10 leituras iguais em 1 s são estáveis', () {
    feed(tracker, _t0, List.filled(11, 50.0));
    expect(tracker.stableGrams, 50.0);
  });

  test('menos de 5 leituras não é estável', () {
    var at = _t0;
    for (var i = 0; i < 4; i++) {
      tracker.add(at, 50.0);
      at = at.add(const Duration(milliseconds: 300));
    }
    expect(tracker.stableGrams, isNull);
  });

  test('janela curta demais não é estável', () {
    feed(tracker, _t0, List.filled(5, 50.0));
    expect(tracker.stableGrams, isNull);
  });

  test('variação de 0,4 g não é estável', () {
    feed(tracker, _t0, [for (var i = 0; i < 11; i++) i.isEven ? 50.0 : 50.4]);
    expect(tracker.stableGrams, isNull);
  });

  test('pico sai da janela depois de 1 s e volta a ser estável', () {
    var at = feed(tracker, _t0, [...List.filled(10, 50.0), 52.0]);
    expect(tracker.stableGrams, isNull);
    feed(tracker, at, List.filled(11, 50.0));
    expect(tracker.stableGrams, 50.0);
  });

  test('reset esquece tudo', () {
    feed(tracker, _t0, List.filled(11, 50.0));
    tracker.reset();
    expect(tracker.stableGrams, isNull);
  });
}
