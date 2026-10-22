import 'dart:collection';

import 'tuning.dart';

/// Diz se o peso está parado, olhando as leituras da última janela.
class StabilityTracker {
  StabilityTracker(this.tuning);

  final EspressoTuning tuning;
  final _window = Queue<({DateTime at, double grams})>();

  void add(DateTime at, double grams) {
    _window.add((at: at, grams: grams));
    // Guarda uma leitura na borda (≥ janela atrás): os intervalos da Dot oscilam entre ~90 e
    // ~115 ms, e sem ela a janela às vezes cobriria menos que o mínimo e o peso "piscaria".
    while (_window.length >= 2 && at.difference(_window.elementAt(1).at) >= tuning.stableWindow) {
      _window.removeFirst();
    }
  }

  void reset() => _window.clear();

  /// Média da janela (arredondada a 0,1 g) quando o peso está estável; senão null.
  double? get stableGrams {
    if (_window.length < tuning.stableMinSamples) return null;
    final span = _window.last.at.difference(_window.first.at);
    if (span * 10 < tuning.stableWindow * 9) return null;
    var min = double.infinity, max = double.negativeInfinity, sum = 0.0;
    for (final r in _window) {
      if (r.grams < min) min = r.grams;
      if (r.grams > max) max = r.grams;
      sum += r.grams;
    }
    if (max - min > tuning.stableRange + 1e-9) return null;
    return (sum / _window.length * 10).round() / 10;
  }
}
