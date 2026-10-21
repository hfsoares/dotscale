import 'package:dotscale/espresso/espresso_session.dart';
import 'package:dotscale/espresso/scale_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_driver.dart';

const containers = [
  ScaleContainer(id: 'd', name: 'Dosímetro', kind: ContainerKind.doser, grams: 80.0),
  ScaleContainer(id: 'g', name: 'Copinho', kind: ContainerKind.grinderCup, grams: 40.0),
];
const s = Duration(milliseconds: 1500);
const cup = 120.0;

Duration secs(num v) => Duration(milliseconds: (v * 1000).round());

void main() {
  late EspressoSession session;
  late SessionDriver d;

  setUp(() {
    session = EspressoSession(containers: containers);
    d = SessionDriver(session);
    d.hold(0, s);
    d.hold(80, s);
    d.ramp(80, 98, secs(3));
    d.hold(98, s);
    d.hold(0, s);
    d.hold(cup, s); // pula o copinho: dose = grãos (18 g), xícara tarada
    expect(session.step, EspressoStep.cupReady);
  });

  void shot({double to = 36, num seconds = 27}) {
    d.hold(cup, secs(3));
    d.ramp(cup, cup + to, secs(seconds));
    d.hold(cup + to, secs(5));
  }

  void expectDuration(Duration? actual, num seconds) =>
      expect(actual!.inMilliseconds / 1000, closeTo(seconds, 0.3));

  test('extração completa: tempo, bebida e ratio', () {
    shot();
    final r = session.result!;
    expect(session.step, EspressoStep.idle);
    expect(r.beverage, 36.0);
    expect(r.dose, 18.0);
    expect(r.beans, 18.0);
    expect(r.ratio, closeTo(2.0, 1e-9));
    expectDuration(r.extraction, 27);
    expect(r.preInfusion, isNull);
  });

  test('extraindo expõe o início e o step', () {
    d.hold(cup, secs(3));
    d.ramp(cup, cup + 10, secs(7));
    expect(session.step, EspressoStep.extracting);
    expect(session.extractionStartedAt, isNotNull);
    expect(session.timerStartedAt, session.extractionStartedAt);
  });

  test('Iniciar marca a pré-infusão', () {
    d.hold(cup, secs(1));
    session.startTimer(d.now);
    final started = d.now;
    expect(session.step, EspressoStep.preInfusion);
    expect(session.timerStartedAt, started);
    d.hold(cup, secs(8));
    d.ramp(cup, cup + 36, secs(27));
    d.hold(cup + 36, secs(5));
    final r = session.result!;
    expectDuration(r.preInfusion, 8);
    expectDuration(r.extraction, 27);
  });

  test('Iniciar fora de cupReady não faz nada', () {
    session.cancel();
    session.startTimer(d.now);
    expect(session.step, EspressoStep.idle);
  });

  test('vibração não inicia o cronômetro', () {
    for (var i = 0; i < 5; i++) {
      d.hold(cup, secs(1));
      d.hold(cup + 2, secs(0.3));
    }
    d.hold(cup, secs(2));
    expect(session.step, EspressoStep.cupReady);
    expect(session.extractionStartedAt, isNull);
  });

  test('objeto deixado na xícara (degrau sem subida) não inicia', () {
    d.hold(cup, secs(1));
    d.hold(cup + 5, secs(3));
    expect(session.step, EspressoStep.cupReady);
  });

  test('tirar a balança depois do fim não muda o resultado', () {
    shot();
    final r = session.result!;
    d.ramp(cup + 36, -150, secs(1));
    for (var i = 0; i < 10; i++) {
      d.hold(i.isEven ? 10 : 200, secs(0.3));
    }
    d.hold(0, s);
    expect(session.result, same(r));
    expect(session.step, EspressoStep.idle);
  });

  test('dosímetro durante a extração é ignorado', () {
    d.hold(cup, secs(3));
    d.ramp(cup, cup + 10, secs(7));
    d.hold(80, s);
    expect(session.step, EspressoStep.extracting);
  });

  test('dosímetro com resultado na tela começa outro espresso', () {
    shot();
    d.hold(0, s);
    d.hold(80, s);
    expect(session.result, isNull);
    expect(session.step, EspressoStep.weighingBeans);
  });

  test('lacuna de leituras na extração', () {
    d.hold(cup, secs(3));
    d.ramp(cup, cup + 20, secs(15));
    session.connectionLost();
    expect(session.reconnectWarning, isTrue);
    d.wait(secs(6));
    d.ramp(cup + 20, cup + 36, secs(12));
    expect(session.step, EspressoStep.extracting);
    d.hold(cup + 36, secs(5));
    expect(session.result!.beverage, 36.0);
    expect(session.reconnectWarning, isFalse);
  });

  test('queda de conexão sem nada na balança não avisa', () {
    session.cancel();
    session.connectionLost();
    expect(session.reconnectWarning, isFalse);
  });

  test('samples cobrem da tara ao fim', () {
    shot();
    final samples = session.result!.samples;
    expect(samples.first.t, Duration.zero);
    expect(samples.last.grams, closeTo(36.0, 0.05));
    expect(samples.length, greaterThan(300));
  });
}
