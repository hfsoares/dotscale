import 'package:dotscale/ble/scale_connection.dart';
import 'package:dotscale/espresso/scale_container.dart';
import 'package:dotscale/protocol/dot_event.dart';
import 'package:dotscale/ui/containers_page.dart';
import 'package:dotscale/ui/espresso_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scale_connection.dart';
import '../fakes/in_memory_container_store.dart';

const doser = ScaleContainer(id: 'd', name: 'Dosímetro', kind: ContainerKind.doser, grams: 80.0);

void main() {
  late FakeScaleConnection fake;
  late InMemoryContainerStore store;
  late EspressoController controller;
  late DateTime t;

  Future<void> pump(WidgetTester tester, [List<ScaleContainer> initial = const []]) async {
    t = DateTime(2026, 10, 21, 13);
    fake = FakeScaleConnection();
    store = InMemoryContainerStore(initial);
    controller = EspressoController(fake, store, now: () => t);
    addTearDown(controller.dispose);
    await controller.load();
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    await tester.pumpWidget(MaterialApp(home: ContainersPage(controller: controller)));
  }

  Future<void> hold(WidgetTester tester, double grams) async {
    for (var i = 0; i < 15; i++) {
      fake.emitEvent(WeightReading(grams: grams, flowGramsPerSecond: 0, timerSeconds: 0, overload: false));
      t = t.add(const Duration(milliseconds: 100));
    }
    await tester.pump();
  }

  FilledButton registerButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Cadastrar recipiente'));

  testWidgets('cadastrar desabilitado sem peso estável', (tester) async {
    await pump(tester);
    expect(registerButton(tester).onPressed, isNull);
    await hold(tester, 150);
    expect(registerButton(tester).onPressed, isNotNull);
  });

  testWidgets('cadastrar grava nome e tipo', (tester) async {
    await pump(tester);
    await hold(tester, 152.3);
    await tester.tap(find.text('Cadastrar recipiente'));
    await tester.pumpAndSettle();
    expect(find.text('152.3 g'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Azul');
    await tester.tap(find.text('Xícara'));
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(store.containers.single.name, 'Azul');
    expect(store.containers.single.kind, ContainerKind.cup);
    expect(store.containers.single.grams, 152.3);
    expect(find.text('Azul'), findsOneWidget);
  });

  testWidgets('diálogo avisa de recipiente parecido', (tester) async {
    await pump(tester, [doser]);
    await hold(tester, 81.5);
    await tester.tap(find.text('Cadastrar recipiente'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Atenção: parecido com Dosímetro'), findsOneWidget);
  });

  testWidgets('apagar remove da lista', (tester) async {
    await pump(tester, [doser]);
    expect(find.text('Dosímetro'), findsOneWidget);
    await tester.tap(find.byTooltip('Apagar'));
    await tester.pumpAndSettle();
    expect(store.containers, isEmpty);
    expect(find.text('Dosímetro'), findsNothing);
  });

  testWidgets('renomear troca o nome', (tester) async {
    await pump(tester, [doser]);
    await tester.tap(find.byTooltip('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Porcelana');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(store.containers.single.name, 'Porcelana');
  });
}
