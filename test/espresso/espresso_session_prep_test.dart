import 'package:dotscale/espresso/espresso_session.dart';
import 'package:dotscale/espresso/scale_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_driver.dart';

const containers = [
  ScaleContainer(id: 'd', name: 'Dosímetro', kind: ContainerKind.doser, grams: 80.0),
  ScaleContainer(id: 'g', name: 'Copinho', kind: ContainerKind.grinderCup, grams: 40.0),
  ScaleContainer(id: 'x', name: 'Azul', kind: ContainerKind.cup, grams: 150.0),
];
const s = Duration(milliseconds: 1500);

void main() {
  late EspressoSession session;
  late SessionDriver d;

  setUp(() {
    session = EspressoSession(containers: containers);
    d = SessionDriver(session);
    d.hold(0, s);
  });

  void weighBeans([double beans = 18.0]) {
    d.hold(80, s);
    d.ramp(80, 80 + beans, const Duration(seconds: 3));
    d.hold(80 + beans, s);
    d.hold(0, s);
  }

  void grounds([double dose = 17.8]) {
    d.hold(40 + dose, s);
    d.hold(0, s);
  }

  test('dosímetro vazio inicia o espresso com líquido 0', () {
    d.hold(80, s);
    expect(session.step, EspressoStep.weighingBeans);
    expect(session.netGrams, 0.0);
  });

  test('grãos são registrados ao tirar o dosímetro', () {
    weighBeans();
    expect(session.beans, 18.0);
    expect(session.step, EspressoStep.awaitingGrounds);
  });

  test('menos de 3 g de grãos volta para ocioso', () {
    weighBeans(2.0);
    expect(session.step, EspressoStep.idle);
    expect(session.beans, isNull);
  });

  test('copinho com pó registra dose e retenção', () {
    weighBeans();
    d.hold(57.8, s);
    expect(session.dose, 17.8);
    expect(session.retention, closeTo(0.2, 1e-9));
    expect(session.step, EspressoStep.awaitingCup);
  });

  test('copinho vazio é ignorado e depois o pó é reconhecido', () {
    weighBeans();
    d.hold(40, s);
    expect(session.step, EspressoStep.awaitingGrounds);
    d.ramp(40, 57.8, const Duration(seconds: 2));
    d.hold(57.8, s);
    expect(session.step, EspressoStep.awaitingCup);
    expect(session.dose, 17.8);
  });

  test('outro objeto pula o copinho: dose = grãos e objeto vira xícara', () {
    weighBeans();
    d.hold(120, s);
    expect(session.dose, 18.0);
    expect(session.retention, isNull);
    expect(session.step, EspressoStep.cupReady);
    expect(session.netGrams, 0.0);
  });

  test('número grande mostra a dose sem o copinho', () {
    weighBeans();
    expect(session.displayGrams, 0.0);
    d.hold(40, s);
    expect(session.displayGrams, closeTo(0.0, 1e-9));
    d.ramp(40, 57.8, const Duration(seconds: 2));
    d.hold(57.8, s);
    expect(session.step, EspressoStep.awaitingCup);
    expect(session.displayGrams, closeTo(17.8, 1e-9));
    d.hold(0, s);
    expect(session.displayGrams, 0.0);
  });

  test('com a dose reconhecida, o número grande não oscila com o ruído', () {
    weighBeans();
    d.hold(57.8, s);
    d.readings([57.7, 57.9, 57.7]);
    expect(session.displayGrams, 17.8);
  });

  test('sem copinho, o número grande é o líquido', () {
    weighBeans();
    session.useBeansAsDose();
    d.hold(120, s);
    expect(session.step, EspressoStep.cupReady);
    expect(session.displayGrams, 0.0);
  });

  test('usar peso dos grãos', () {
    weighBeans();
    session.useBeansAsDose();
    expect(session.dose, 18.0);
    expect(session.step, EspressoStep.awaitingCup);
  });

  test('xícara cadastrada é tarada e nomeada', () {
    weighBeans();
    grounds();
    d.hold(150, s);
    expect(session.step, EspressoStep.cupReady);
    expect(session.cupName, 'Azul');
    expect(session.netGrams, 0.0);
  });

  test('xícara não cadastrada também é tarada', () {
    weighBeans();
    grounds();
    d.hold(133, s);
    expect(session.step, EspressoStep.cupReady);
    expect(session.cupName, isNull);
    expect(session.netGrams, 0.0);
  });

  test('tirar a xícara antes das gotas tara de novo o próximo objeto', () {
    weighBeans();
    grounds();
    d.hold(133, s);
    d.hold(0, s);
    expect(session.step, EspressoStep.awaitingCup);
    d.hold(150, s);
    expect(session.step, EspressoStep.cupReady);
    expect(session.cupName, 'Azul');
    expect(session.netGrams, 0.0);
  });

  test('dosímetro no meio do preparo reinicia', () {
    weighBeans();
    grounds();
    d.hold(80, s);
    expect(session.step, EspressoStep.weighingBeans);
    expect(session.beans, isNull);
    expect(session.dose, isNull);
  });

  test('peso oscilando perto de 1 g não rearma nem vira objeto', () {
    weighBeans();
    grounds();
    for (var i = 0; i < 20; i++) {
      d.hold(i.isEven ? 0.9 : 1.1, const Duration(milliseconds: 100));
    }
    expect(session.step, EspressoStep.awaitingCup);
  });

  test('leituras negativas não casam com nada', () {
    d.hold(-80, s);
    expect(session.step, EspressoStep.idle);
    d.hold(0, s);
    d.hold(80, s);
    expect(session.step, EspressoStep.weighingBeans);
  });

  test('cancelar volta para ocioso sem resultado', () {
    weighBeans();
    session.cancel();
    expect(session.step, EspressoStep.idle);
    expect(session.beans, isNull);
    expect(session.result, isNull);
  });
}
