import 'scale_container.dart';
import 'stability.dart';
import 'tuning.dart';

enum EspressoStep { idle, weighingBeans, awaitingGrounds, awaitingCup, cupReady, preInfusion, extracting }

class WeightSample {
  /// Tempo desde a tara da xícara.
  final Duration t;
  final double grams;

  const WeightSample(this.t, this.grams);
}

class EspressoResult {
  final double dose;
  final double? beans;
  final double beverage;
  final Duration extraction;
  final Duration? preInfusion;
  final String? cupName;
  final List<WeightSample> samples;

  const EspressoResult({
    required this.dose,
    required this.beans,
    required this.beverage,
    required this.extraction,
    required this.preInfusion,
    required this.cupName,
    required this.samples,
  });

  double get ratio => beverage / dose;
}

/// Máquina de estados do espresso, alimentada pelo peso bruto da Dot.
///
/// Reconhecimento: só o primeiro peso estável depois de a balança ficar vazia
/// identifica um objeto ("rearme"); encher um recipiente não o re-reconhece.
class EspressoSession {
  EspressoSession({List<ScaleContainer> containers = const [], this.tuning = const EspressoTuning()})
    : containers = List.unmodifiable(containers),
      _stability = StabilityTracker(tuning);

  final EspressoTuning tuning;
  List<ScaleContainer> containers;
  final StabilityTracker _stability;

  EspressoStep _step = EspressoStep.idle;
  bool _armed = true;
  bool _grinderCupOnScale = false;
  double _offset = 0;
  double? _raw;
  double? _lastStableNet;
  double? _beans;
  double? _dose;
  double? _retention;
  String? _cupName;
  EspressoResult? _result;
  bool _reconnectWarning = false;

  EspressoStep get step => _step;
  double? get rawGrams => _raw;
  double? get netGrams => _raw == null ? null : _raw! - _offset;
  double? get stableGrams => _stability.stableGrams;
  double? get beans => _beans;
  double? get dose => _dose;

  /// Grãos − pó; só quando a dose veio do copinho.
  double? get retention => _retention;
  String? get cupName => _cupName;
  EspressoResult? get result => _result;
  bool get reconnectWarning => _reconnectWarning;
  DateTime? get timerStartedAt => null;
  DateTime? get extractionStartedAt => null;

  void addReading(DateTime at, double grams) {
    _raw = grams;
    _stability.add(at, grams);
    final stable = _stability.stableGrams;
    if (stable == null) return;
    if (stable.abs() < tuning.emptyBelow) {
      _onEmpty();
    } else if (stable >= tuning.minObject) {
      if (_step == EspressoStep.weighingBeans) _lastStableNet = stable - _offset;
      if (_armed) _onObject(stable);
    }
  }

  void startTimer(DateTime at) {}

  void useBeansAsDose() {
    if (_step != EspressoStep.awaitingGrounds) return;
    _dose = _beans;
    _step = EspressoStep.awaitingCup;
  }

  void cancel() {
    _clearSession();
    _result = null;
  }

  void connectionLost() {}

  void _onEmpty() {
    _armed = true;
    _grinderCupOnScale = false;
    switch (_step) {
      case EspressoStep.weighingBeans:
        final beans = _lastStableNet ?? 0;
        if (beans < tuning.minBeans) {
          _clearSession();
        } else {
          _beans = (beans * 10).round() / 10;
          _offset = 0;
          _step = EspressoStep.awaitingGrounds;
        }
      case EspressoStep.cupReady:
        _offset = 0;
        _cupName = null;
        _step = EspressoStep.awaitingCup;
      default:
        break;
    }
  }

  void _onObject(double grams) {
    if (_step != EspressoStep.extracting && _matching(ContainerKind.doser, grams) != null) {
      _clearSession();
      _result = null;
      _offset = grams;
      _lastStableNet = 0;
      _step = EspressoStep.weighingBeans;
      _armed = false;
      return;
    }
    switch (_step) {
      case EspressoStep.awaitingGrounds:
        final beans = _beans!;
        for (final cup in containers.where((c) => c.kind == ContainerKind.grinderCup)) {
          final dose = grams - cup.grams;
          if (dose >= beans - tuning.groundsBelow && dose <= beans + tuning.groundsAbove) {
            _dose = (dose * 10).round() / 10;
            _retention = beans - _dose!;
            _step = EspressoStep.awaitingCup;
            _armed = false;
            return;
          }
        }
        if (_matching(ContainerKind.grinderCup, grams) != null) {
          _grinderCupOnScale = true;
          return;
        }
        if (_grinderCupOnScale) return;
        _dose = beans;
        _tareCup(grams);
      case EspressoStep.awaitingCup:
        if (_matching(ContainerKind.grinderCup, grams) != null) {
          _armed = false;
          return;
        }
        _tareCup(grams);
      default:
        _armed = false;
    }
  }

  void _tareCup(double grams) {
    _offset = grams;
    _cupName = _matching(ContainerKind.cup, grams)?.name;
    _step = EspressoStep.cupReady;
    _armed = false;
  }

  ScaleContainer? _matching(ContainerKind kind, double grams) {
    for (final c in containers) {
      if (c.kind == kind && (c.grams - grams).abs() <= tuning.matchTolerance) return c;
    }
    return null;
  }

  void _clearSession() {
    _step = EspressoStep.idle;
    _offset = 0;
    _lastStableNet = null;
    _beans = null;
    _dose = null;
    _retention = null;
    _cupName = null;
    _grinderCupOnScale = false;
    _reconnectWarning = false;
  }
}
