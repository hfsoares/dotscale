import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/scale_connection.dart';
import '../espresso/container_store.dart';
import '../espresso/espresso_session.dart';
import '../espresso/scale_container.dart';
import '../espresso/tuning.dart';
import '../protocol/dot_event.dart';

/// Liga o peso da balança à máquina do espresso e cuida dos recipientes cadastrados.
class EspressoController extends ChangeNotifier {
  EspressoController(
    this.connection,
    this.store, {
    this.now = DateTime.now,
    EspressoTuning tuning = const EspressoTuning(),
  }) : session = EspressoSession(tuning: tuning) {
    _subs = [
      connection.events.listen((event) {
        if (event is! WeightReading) return;
        session.addReading(now(), event.grams);
        notifyListeners();
      }),
      connection.status.listen((status) {
        final connected = status.phase == ConnectionPhase.connected;
        if (_wasConnected && !connected) {
          session.connectionLost();
          notifyListeners();
        }
        _wasConnected = connected;
      }),
    ];
  }

  final ScaleConnection connection;
  final ContainerStore store;
  final EspressoSession session;
  final DateTime Function() now;
  late final List<StreamSubscription<Object?>> _subs;
  bool _wasConnected = false;
  List<ScaleContainer> _containers = const [];

  List<ScaleContainer> get containers => _containers;

  bool get hasRequiredContainers =>
      _containers.any((c) => c.kind == ContainerKind.doser) &&
      _containers.any((c) => c.kind == ContainerKind.grinderCup);

  /// Peso estável que pode virar um recipiente; null se a balança não estiver conectada e parada.
  double? get registrableGrams {
    if (connection.currentStatus.phase != ConnectionPhase.connected) return null;
    final grams = session.stableGrams;
    return grams != null && grams >= 1.0 ? grams : null;
  }

  List<ScaleContainer> nearRegistrable() {
    final grams = registrableGrams;
    return grams == null ? const [] : containersNear(_containers, grams, within: session.tuning.conflictWithin);
  }

  Future<void> load() async => _set(await store.load());

  Future<void> addContainer(String name, ContainerKind kind, {required double grams}) => _save([
    ..._containers,
    ScaleContainer(id: now().microsecondsSinceEpoch.toString(), name: name, kind: kind, grams: grams),
  ]);

  Future<void> rename(String id, String name) =>
      _save([for (final c in _containers) c.id == id ? c.copyWith(name: name) : c]);

  Future<void> remove(String id) => _save([
    for (final c in _containers)
      if (c.id != id) c,
  ]);

  void startTimer() => _act(() => session.startTimer(now()));
  void startExtraction() => _act(() => session.startExtraction(now()));
  void useBeansAsDose() => _act(session.useBeansAsDose);
  void dismissResult() => _act(session.dismissResult);
  void cancel() => _act(session.cancel);

  /// Tempo da fase em curso: a pré-infusão desde o "Pré-infusão", a extração desde o seu início.
  Duration? elapsed() {
    final started = switch (session.step) {
      EspressoStep.preInfusion => session.timerStartedAt,
      EspressoStep.extracting => session.extractionStartedAt,
      _ => null,
    };
    return started == null ? null : now().difference(started);
  }

  void _act(void Function() action) {
    action();
    notifyListeners();
  }

  Future<void> _save(List<ScaleContainer> containers) async {
    await store.save(containers);
    _set(containers);
  }

  void _set(List<ScaleContainer> containers) {
    _containers = List.unmodifiable(containers);
    session.containers = _containers;
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
