import 'package:dotscale/ble/scale_connection.dart';
import 'package:dotscale/espresso/espresso_session.dart';
import 'package:dotscale/espresso/scale_container.dart';
import 'package:dotscale/protocol/dot_event.dart';
import 'package:dotscale/ui/espresso_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scale_connection.dart';
import '../fakes/in_memory_container_store.dart';

const doser = ScaleContainer(id: 'd', name: 'Dosímetro', kind: ContainerKind.doser, grams: 80.0);
const grinderCup = ScaleContainer(id: 'g', name: 'Copinho', kind: ContainerKind.grinderCup, grams: 40.0);

void main() {
  late FakeScaleConnection fake;
  late InMemoryContainerStore store;
  late EspressoController controller;
  late DateTime t;

  void hold(double grams, {int readings = 15}) {
    for (var i = 0; i < readings; i++) {
      fake.emitEvent(WeightReading(grams: grams, flowGramsPerSecond: 0, timerSeconds: 0, overload: false));
      t = t.add(const Duration(milliseconds: 100));
    }
  }

  Future<void> setUpWith(List<ScaleContainer> initial) async {
    t = DateTime(2026, 10, 21, 13);
    fake = FakeScaleConnection();
    store = InMemoryContainerStore(initial);
    controller = EspressoController(fake, store, now: () => t);
    await controller.load();
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
  }

  tearDown(() => controller.dispose());

  test('load traz recipientes do store', () async {
    await setUpWith([doser, grinderCup]);
    expect(controller.containers, [doser, grinderCup]);
    expect(controller.session.containers, [doser, grinderCup]);
  });

  test('leituras chegam à sessão', () async {
    await setUpWith([doser]);
    var notified = 0;
    controller.addListener(() => notified++);
    hold(0);
    hold(80);
    expect(controller.session.step, EspressoStep.weighingBeans);
    expect(notified, greaterThan(0));
  });

  test('addContainer usa o peso estável e salva', () async {
    await setUpWith([]);
    hold(152.3);
    expect(controller.registrableGrams, 152.3);
    await controller.addContainer('Azul', ContainerKind.cup, grams: controller.registrableGrams!);
    expect(store.containers.single.name, 'Azul');
    expect(store.containers.single.grams, 152.3);
    expect(controller.session.containers.single.kind, ContainerKind.cup);
  });

  test('sem peso estável não há o que cadastrar', () async {
    await setUpWith([]);
    expect(controller.registrableGrams, isNull);
    hold(0.5);
    expect(controller.registrableGrams, isNull);
  });

  test('sem conexão não há o que cadastrar', () async {
    await setUpWith([]);
    hold(150);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.reconnecting));
    expect(controller.registrableGrams, isNull);
  });

  test('rename e remove salvam', () async {
    await setUpWith([doser, grinderCup]);
    await controller.rename('d', 'Porcelana');
    expect(store.containers.first.name, 'Porcelana');
    await controller.remove('g');
    expect(store.containers.map((c) => c.id), ['d']);
    expect(controller.session.containers.map((c) => c.id), ['d']);
  });

  test('nearRegistrable acha recipientes parecidos', () async {
    await setUpWith([doser, grinderCup]);
    hold(81.5);
    expect(controller.nearRegistrable(), [doser]);
  });

  test('queda da conexão com xícara tarada liga o aviso', () async {
    await setUpWith([doser, grinderCup]);
    hold(0);
    hold(80);
    hold(98);
    hold(0);
    hold(120);
    expect(controller.session.step, EspressoStep.cupReady);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.reconnecting));
    expect(controller.session.reconnectWarning, isTrue);
  });

  test('hasRequiredContainers', () async {
    await setUpWith([doser]);
    expect(controller.hasRequiredContainers, isFalse);
    await setUpWith([doser, grinderCup]);
    expect(controller.hasRequiredContainers, isTrue);
  });

  test('elapsed corre na pré-infusão', () async {
    await setUpWith([doser, grinderCup]);
    hold(0);
    hold(80);
    hold(98);
    hold(0);
    hold(120);
    expect(controller.elapsed(), isNull);
    controller.startTimer();
    t = t.add(const Duration(seconds: 5));
    expect(controller.elapsed(), const Duration(seconds: 5));
  });
}
