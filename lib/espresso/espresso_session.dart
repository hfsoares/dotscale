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

  /// A conexão caiu durante a extração: os números podem estar errados.
  final bool interrupted;

  const EspressoResult({
    required this.dose,
    required this.beans,
    required this.beverage,
    required this.extraction,
    required this.preInfusion,
    required this.cupName,
    required this.samples,
    this.interrupted = false,
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
  // Candidato a gotas: começou quando o líquido passou de dripMinNet.
  ({DateTime at, double net})? _dripCandidate;
  double _dripRunningMax = 0;
  // Referência do fim: última subida de pelo menos endMinRise.
  ({DateTime at, double net})? _lastRise;
  double? _prevNet;
  bool _hadGap = false;

  EspressoStep get step => _step;
  double? get rawGrams => _raw;
  double? get netGrams => _raw == null ? null : _raw! - _offset;
  double? get stableGrams => _stability.stableGrams;

  /// O número grande: no passo do pó, o peso sem o copinho (a dose); nos outros, o líquido.
  double? get displayGrams {
    final net = netGrams;
    final beans = _beans;
    final fromGrinderCup =
        _step == EspressoStep.awaitingGrounds || (_step == EspressoStep.awaitingCup && _retention != null);
    if (net == null || beans == null || !fromGrinderCup) return net;
    for (final cup in containers.where((c) => c.kind == ContainerKind.grinderCup)) {
      final dose = _raw! - cup.grams;
      if (dose >= -tuning.matchTolerance && dose <= beans + tuning.groundsAbove + tuning.minObject) return dose;
    }
    return net;
  }

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
    _extractionStart = _riseStart(candidate.at);
    _lastRise = (at: at, net: net);
    _prevNet = net;
    _step = EspressoStep.extracting;
  }

  /// Onde a subida começou: a primeira leitura, até 2 janelas antes do candidato, que se
  /// descola da linha de base (mediana do segundo anterior). Gotas soltas da pré-infusão
  /// mudam a linha de base em vez de puxar o início para trás.
  DateTime _riseStart(DateTime candidateAt) {
    final from = candidateAt.subtract(tuning.dripWindow * 2);
    final baseFrom = from.subtract(const Duration(seconds: 1));
    final base = _median([
      for (final x in _samples)
        if (!_at(x).isBefore(baseFrom) && _at(x).isBefore(from)) x.grams,
    ]);
    for (final x in _samples) {
      if (!_at(x).isBefore(from) && x.grams > (base ?? 0) + tuning.dripMaxDip) return _at(x);
    }
    return candidateAt;
  }

  DateTime _at(WeightSample x) => _cupTaredAt!.add(x.t);

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  void _detectEnd(DateTime at, double net, {required bool gap}) {
    final jump = (net - _prevNet!).abs() > tuning.handlingJump;
    _prevNet = net;
    if (gap) _hadGap = true;
    if (jump) return _finish(before: at);
    if (gap) {
      // A conexão caiu: o tempo sem leituras não conta como "parou de subir".
      _lastRise = (at: at, net: net);
      return;
    }
    if (net > _lastRise!.net + tuning.endMinRise) {
      _lastRise = (at: at, net: net);
      return;
    }
    if (at.difference(_lastRise!.at) >= tuning.endWindow) _finish(before: at.add(const Duration(microseconds: 1)));
  }

  /// Fecha a extração na última subida. A bebida é a mediana do patamar entre essa subida e
  /// [before] (exclusive, para deixar de fora o tranco de levantar a balança); sem patamar,
  /// a mediana das leituras logo antes da subida.
  void _finish({required DateTime before}) {
    final end = _lastRise!.at;
    final kept = [
      for (final x in _samples)
        if (!_at(x).isAfter(end)) x,
    ];
    final plateau = [
      for (final x in _samples)
        if (!_at(x).isBefore(end) && _at(x).isBefore(before)) x.grams,
    ];
    final tail = [
      for (final x in kept)
        if (end.difference(_at(x)) < const Duration(milliseconds: 300)) x.grams,
    ];
    final beverage = _median(plateau.length >= 3 ? plateau : tail) ?? _lastRise!.net;
    _result = EspressoResult(
      dose: _dose!,
      beans: _beans,
      beverage: (beverage * 10).round() / 10,
      extraction: end.difference(_extractionStart!),
      preInfusion: _timerStart == null ? null : _extractionStart!.difference(_timerStart!),
      cupName: _cupName,
      samples: List.unmodifiable(kept),
      interrupted: _hadGap,
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
    _prevNet = null;
    _hadGap = false;
  }
}
