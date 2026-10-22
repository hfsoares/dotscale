import 'package:dotscale/ble/scale_connection.dart';
import 'package:dotscale/espresso/scale_container.dart';
import 'package:dotscale/protocol/dot_event.dart';
import 'package:dotscale/ui/espresso_controller.dart';
import 'package:dotscale/ui/home_page.dart';
import 'package:dotscale/ui/scale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scale_connection.dart';
import '../fakes/in_memory_container_store.dart';

const doser = ScaleContainer(id: 'd', name: 'Dosímetro', kind: ContainerKind.doser, grams: 80.0);
const grinderCup = ScaleContainer(id: 'g', name: 'Copinho', kind: ContainerKind.grinderCup, grams: 40.0);

void main() {
  late FakeScaleConnection fake;
  late EspressoController espresso;
  late DateTime t;

  Future<void> pump(WidgetTester tester, [List<ScaleContainer> initial = const [doser, grinderCup]]) async {
    t = DateTime(2026, 10, 21, 13);
    fake = FakeScaleConnection();
    final scale = ScaleController(fake);
    addTearDown(scale.dispose);
    espresso = EspressoController(fake, InMemoryContainerStore(initial), now: () => t);
    addTearDown(espresso.dispose);
    await espresso.load();
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(controller: scale, espresso: espresso),
      ),
    );
  }

  Future<void> hold(WidgetTester tester, double grams, {int readings = 15}) async {
    for (var i = 0; i < readings; i++) {
      fake.emitEvent(WeightReading(grams: grams, flowGramsPerSecond: 0, timerSeconds: 0, overload: false));
      t = t.add(const Duration(milliseconds: 100));
    }
    await tester.pump();
  }

  Future<void> ramp(WidgetTester tester, double from, double to, int readings) async {
    for (var i = 1; i <= readings; i++) {
      fake.emitEvent(
        WeightReading(
          grams: from + (to - from) * i / readings,
          flowGramsPerSecond: 1.3,
          timerSeconds: 0,
          overload: false,
        ),
      );
      t = t.add(const Duration(milliseconds: 100));
    }
    await tester.pump();
  }

  Future<void> toCup(WidgetTester tester) async {
    await hold(tester, 0);
    await hold(tester, 80);
    await hold(tester, 98);
    await hold(tester, 0);
    await hold(tester, 57.8);
    await hold(tester, 0);
    await hold(tester, 120);
  }

  FilledButton button(WidgetTester tester, String text) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, text));

  Future<void> finish(WidgetTester tester) => tester.pump(const Duration(seconds: 3));

  testWidgets('sem recipientes mostra o aviso de cadastro', (tester) async {
    await pump(tester, const []);
    expect(find.text('Cadastre o dosímetro e o copinho do moedor para o espresso automático.'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Recipientes'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastrar recipiente'), findsOneWidget);
  });

  testWidgets('idle não tem instrução e mostra Tarar habilitado, sem ícone', (tester) async {
    await pump(tester);
    await hold(tester, 0);
    expect(find.text('Coloque o dosímetro'), findsNothing);
    expect(button(tester, 'Tarar').onPressed, isNotNull);
    expect(find.byIcon(Icons.exposure_zero), findsNothing);
    await finish(tester);
  });

  testWidgets('fluxo até a xícara mostra Pré-infusão grande e esconde Tarar', (tester) async {
    await pump(tester);
    await hold(tester, 0);
    await hold(tester, 80);
    expect(find.text('Grãos'), findsOneWidget);
    expect(find.text('Tarar'), findsNothing);
    await hold(tester, 98);
    await hold(tester, 0);
    expect(find.text('Coloque o copinho com o pó'), findsOneWidget);
    await hold(tester, 57.8);
    expect(find.text('Coloque a xícara na Gaggia'), findsOneWidget);
    expect(find.text('Dose 17.8 g · retenção 0.2 g'), findsOneWidget);
    expect(find.text('17.8 g'), findsOneWidget); // número grande: a dose, não 57.8 g
    expect(find.textContaining('Balança'), findsNothing);
    await hold(tester, 0);
    await hold(tester, 120);
    expect(find.text('Pronto — inicie a pré-infusão'), findsOneWidget);
    expect(button(tester, 'Pré-infusão').onPressed, isNotNull);
    expect(find.text('Iniciar'), findsNothing);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Pré-infusão')).height, greaterThanOrEqualTo(88));
    expect(find.text('Tarar'), findsNothing);
    await finish(tester);
  });

  testWidgets('durante a extração bebida, ratio e tempo têm o mesmo destaque', (tester) async {
    await pump(tester);
    await toCup(tester);
    await hold(tester, 120, readings: 10);
    await ramp(tester, 120, 138, 100);
    expect(find.text('Extraindo'), findsOneWidget);
    expect(find.text('Bebida'), findsOneWidget);
    expect(find.text('Ratio'), findsOneWidget);
    expect(find.text('Tempo'), findsOneWidget);
    final values = [find.text('18.0 g'), find.text('1:1.0'), find.textContaining(RegExp(r'^\d+\.\d s$'))];
    final heights = [for (final v in values) tester.getSize(v).height];
    expect(heights.every((h) => (h - heights.first).abs() < 1), isTrue, reason: '$heights');
    expect(find.text('138.0 g'), findsNothing);
    await finish(tester);
  });

  testWidgets('pré-infusão conta o próprio tempo e Infusão inicia a extração', (tester) async {
    await pump(tester);
    await toCup(tester);
    await tester.tap(find.text('Pré-infusão'));
    await tester.pump();
    t = t.add(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Tempo'), findsOneWidget);
    expect(find.text('4.0 s'), findsOneWidget);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Infusão')).height, greaterThanOrEqualTo(88));
    await tester.tap(find.text('Infusão'));
    await tester.pump();
    expect(find.text('Extraindo'), findsOneWidget);
    expect(find.text('Infusão'), findsNothing);
    expect(find.text('0.0 s'), findsOneWidget); // o tempo agora é o da extração
    await finish(tester);
  });

  testWidgets('resultado final mostra tempo, dose, bebida e ratio', (tester) async {
    await pump(tester);
    await toCup(tester);
    await hold(tester, 120, readings: 10);
    await ramp(tester, 120, 155.6, 270);
    await hold(tester, 155.6, readings: 50);
    expect(find.text('1:2.0'), findsOneWidget);
    expect(find.text('17.8 g'), findsOneWidget);
    expect(find.text('35.6 g'), findsOneWidget);
    expect(find.textContaining('Extração'), findsOneWidget);
    expect(find.text('Tarar'), findsNothing);
    expect(find.text('155.6 g'), findsNothing); // sem o peso grande
    expect(find.textContaining('g/s'), findsNothing);
    await tester.tap(find.text('Finalizar'));
    await tester.pump();
    expect(find.text('Último espresso'), findsNothing);
    expect(find.text('Tarar'), findsOneWidget);
    expect(find.text('155.6 g'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('aviso de desconexão aparece', (tester) async {
    await pump(tester);
    await toCup(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.reconnecting));
    await tester.pump();
    expect(
      find.text('A balança desconectou. Se ela reiniciou, os pesos podem estar errados — cancele e recomece.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('Cancelar volta para o início, com Tarar', (tester) async {
    await pump(tester);
    await toCup(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    expect(find.text('Tarar'), findsOneWidget);
    expect(find.text('Pronto — inicie a pré-infusão'), findsNothing);
    final screen = tester.getSize(find.byType(Scaffold)).width;
    expect(tester.getCenter(find.text('Tarar')).dx, closeTo(screen / 2, 30));
    await finish(tester);
  });

  testWidgets('resultado interrompido mostra aviso', (tester) async {
    await pump(tester);
    await toCup(tester);
    await hold(tester, 120, readings: 10);
    await ramp(tester, 120, 135, 110);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.reconnecting));
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    t = t.add(const Duration(seconds: 20));
    await hold(tester, 0);
    expect(find.text('A conexão caiu durante a extração; confira os números.'), findsOneWidget);
    await finish(tester);
  });
}
