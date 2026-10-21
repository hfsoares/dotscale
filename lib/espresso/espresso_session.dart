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

  DateTime? _lastReadingAt;
  DateTime? _cupTaredAt;
  final List<WeightSample> _samples = [];
  DateTime? _timerStart;
  DateTime? _extractionStart;
  // Primeira leitura depois da última com líquido ≤ dripMaxDip: onde as gotas começaram.
  DateTime? _firstAfterFlatAt;
  // Candidato a gotas: começou quando o líquido passou de dripMinNet.
  ({DateTime at, double net})? _dripCandidate;
  double _dripRunningMax = 0;
  // Referência do fim: última subida de pelo menos endMinRise.
  ({DateTime at, double net})? _lastRise;
  double _maxNet = 0;

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

  /// Início do cronômetro: o toque em "Iniciar", senão as primeiras gotas.
  DateTime? get timerStartedAt => _timerStart ?? _extractionStart;
  DateTime? get extractionStartedAt => _extractionStart;

  void addReading(DateTime at, double grams) {
    final gap = _lastReadingAt != null && at.difference(_lastReadingAt!) > tuning.endWindow ~/ 2;
    _lastReadingAt = at;
    _raw = grams;
    _stability.add(at, grams);
    switch (_step) {
      case EspressoStep.cupReady || EspressoStep.preInfusion:
        _record(at, grams);
        _detectDrips(at, grams - _offset);
      case EspressoStep.extracting:
        _record(at, grams);
        _detectEnd(at, grams - _offset, gap: gap);
        return;
      default:
        break;
    }
    final stable = _stability.stableGrams;
    if (stable == null) return;
    if (stable.abs() < tuning.emptyBelow) {
      _onEmpty();
    } else if (stable >= tuning.minObject) {
      if (_step == EspressoStep.weighingBeans) _lastStableNet = stable - _offset;
      if (_armed) _onObject(stable);
    }
  }

  void startTimer(DateTime at) {
    if (_step != EspressoStep.cupReady) return;
    _timerStart = at;
    _step = EspressoStep.preInfusion;
  }

  void useBeansAsDose() {
    if (_step != EspressoStep.awaitingGrounds) return;
    _dose = _beans;
    _step = EspressoStep.awaitingCup;
  }

  void cancel() {
    _clearSession();
    _result = null;
  }

  void connectionLost() {
    _stability.reset();
    const withLoad = {
      EspressoStep.weighingBeans,
      EspressoStep.cupReady,
      EspressoStep.preInfusion,
      EspressoStep.extracting,
    };
    if (withLoad.contains(_step)) _reconnectWarning = true;
  }

  void _record(DateTime at, double grams) => _samples.add(WeightSample(at.difference(_cupTaredAt!), grams - _offset));

  void _detectDrips(DateTime at, double net) {
    if (net <= tuning.dripMaxDip) {
      _firstAfterFlatAt = null;
    } else {
      _firstAfterFlatAt ??= at;
    }
    final candidate = _dripCandidate;
    if (candidate == null) {
      if (net > tuning.dripMinNet) {
        _dripCandidate = (at: at, net: net);
        _dripRunningMax = net;
      }
      return;
    }
    if (net > _dripRunningMax) _dripRunningMax = net;
    if (net < _dripRunningMax - tuning.dripMaxDip) {
      // Recuou: foi toque ou vibração, não gotas.
      _dripCandidate = null;
      return;
    }
    if (at.difference(candidate.at) < tuning.dripWindow) return;
    if (net - candidate.net < tuning.dripMinRise) {
      // Degrau parado (algo apoiado na xícara): recomeça a janela a partir daqui.
      _dripCandidate = (at: at, net: net);
      _dripRunningMax = net;
      return;
    }
    _dripCandidate = null;
    _extractionStart = _firstAfterFlatAt ?? candidate.at;
    _lastRise = (at: at, net: net);
    _maxNet = net;
    _step = EspressoStep.extracting;
  }

  void _detectEnd(DateTime at, double net, {required bool gap}) {
    if (net > _maxNet) _maxNet = net;
    if (gap) {
      // A conexão caiu: o tempo sem leituras não conta como "parou de subir".
      _lastRise = (at: at, net: net);
      return;
    }
    if (net > _lastRise!.net + tuning.endMinRise) {
      _lastRise = (at: at, net: net);
      return;
    }
    if (at.difference(_lastRise!.at) < tuning.endWindow) return;
    final end = _lastRise!.at;
    _result = EspressoResult(
      dose: _dose!,
      beans: _beans,
      beverage: (_maxNet * 10).round() / 10,
      extraction: end.difference(_extractionStart!),
      preInfusion: _timerStart == null ? null : _extractionStart!.difference(_timerStart!),
      cupName: _cupName,
      samples: List.unmodifiable(_samples.where((x) => x.t <= end.difference(_cupTaredAt!))),
    );
    _clearSession();
  }

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
      case EspressoStep.cupReady || EspressoStep.preInfusion:
        _offset = 0;
        _cupName = null;
        _resetCupTracking();
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
    _resetCupTracking();
    _cupTaredAt = _lastReadingAt;
    _samples.add(const WeightSample(Duration.zero, 0));
    _step = _timerStart == null ? EspressoStep.cupReady : EspressoStep.preInfusion;
    _armed = false;
  }

  void _resetCupTracking() {
    _cupTaredAt = null;
    _samples.clear();
    _firstAfterFlatAt = null;
    _dripCandidate = null;
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
    _resetCupTracking();
    _timerStart = null;
    _extractionStart = null;
    _lastRise = null;
    _maxNet = 0;
  }
}
