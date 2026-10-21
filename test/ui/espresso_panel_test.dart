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

  testWidgets('idle mostra Coloque o dosímetro e Tarar habilitado', (tester) async {
    await pump(tester);
    await hold(tester, 0);
    expect(find.text('Coloque o dosímetro'), findsOneWidget);
    expect(button(tester, 'Tarar').onPressed, isNotNull);
    await finish(tester);
  });

  testWidgets('fluxo até a xícara mostra Iniciar e Tarar desabilitado', (tester) async {
    await pump(tester);
    await hold(tester, 0);
    await hold(tester, 80);
    expect(find.text('Grãos'), findsOneWidget);
    await hold(tester, 98);
    await hold(tester, 0);
    expect(find.text('Coloque o copinho com o pó'), findsOneWidget);
    await hold(tester, 57.8);
    expect(find.text('Coloque a xícara na Gaggia'), findsOneWidget);
    expect(find.text('Dose 17.8 g · retenção 0.2 g'), findsOneWidget);
    await hold(tester, 0);
    await hold(tester, 120);
    expect(find.text('Pronto — inicie a extração'), findsOneWidget);
    expect(button(tester, 'Iniciar').onPressed, isNotNull);
    expect(button(tester, 'Tarar').onPressed, isNull);
    await finish(tester);
  });

  testWidgets('durante a extração mostra ratio e cronômetro', (tester) async {
    await pump(tester);
    await toCup(tester);
    await hold(tester, 120, readings: 10);
    await ramp(tester, 120, 138, 100);
    expect(find.text('Extraindo'), findsOneWidget);
    expect(find.text('1:1.0'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+\.\d s$')), findsOneWidget);
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
    expect(find.text('Coloque o dosímetro'), findsOneWidget);
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

  testWidgets('Cancelar volta para Coloque o dosímetro', (tester) async {
    await pump(tester);
    await toCup(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    expect(find.text('Coloque o dosímetro'), findsOneWidget);
    await finish(tester);
  });
}
