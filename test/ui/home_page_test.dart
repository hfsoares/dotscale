import 'dart:typed_data';

import 'package:dotscale/ble/scale_connection.dart';
import 'package:dotscale/protocol/commands.dart';
import 'package:dotscale/protocol/dot_event.dart';
import 'package:dotscale/ui/espresso_controller.dart';
import 'package:dotscale/ui/home_page.dart';
import 'package:dotscale/ui/scale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scale_connection.dart';
import '../fakes/in_memory_container_store.dart';

const _w = WeightReading(grams: 18.4, flowGramsPerSecond: 1.2, timerSeconds: 0, overload: false);

void main() {
  late FakeScaleConnection fake;
  late ScaleController controller;

  Future<void> pump(WidgetTester tester) async {
    fake = FakeScaleConnection();
    controller = ScaleController(fake);
    addTearDown(controller.dispose);
    final espresso = EspressoController(fake, InMemoryContainerStore());
    addTearDown(espresso.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(controller: controller, espresso: espresso),
      ),
    );
  }

  testWidgets('idle mostra Procurar balança e inicia o scan', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Procurar balança'));
    expect(fake.calls, contains('startScan'));
  });

  testWidgets('lista balanças encontradas e conecta ao tocar', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.scanning));
    fake.emitFound([const FoundScale('id1', 'TIMEMORE_Dot_01', -60)]);
    await tester.pump();
    await tester.tap(find.text('TIMEMORE_Dot_01'));
    expect(fake.calls, contains('connect:id1'));
  });

  testWidgets('conectado mostra peso, fluxo e bateria', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected, deviceName: 'TIMEMORE_Dot_01'));
    fake.emitEvent(_w);
    fake.emitEvent(const BatteryReading(87));
    await tester.pump();
    expect(find.text('18.4 g'), findsOneWidget);
    expect(find.text('1.2 g/s'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // deixa o timer de peso parado expirar
  });

  testWidgets('conectado mostra Desconectar', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    await tester.pump();
    await tester.ensureVisible(find.text('Desconectar'));
    await tester.tap(find.text('Desconectar'));
    expect(fake.calls, contains('disconnect'));
  });

  testWidgets('Bluetooth desligado oferece Tentar de novo', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.bluetoothOff));
    await tester.pump();
    expect(find.text('Bluetooth desligado'), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    expect(fake.calls, contains('reconnectLast'));
  });

  testWidgets('permissão negada oferece Tentar de novo', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.permissionDenied));
    await tester.pump();
    expect(find.text('Permissão de Bluetooth negada'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('reconectando esmaece o último peso', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    fake.emitEvent(_w);
    await tester.pump();
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.reconnecting));
    await tester.pump();
    expect(find.text('Reconectando…'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('18.4 g'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('erro mostra mensagem e Tentar de novo reconecta', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.error, message: 'Pareamento recusado'));
    await tester.pump();
    expect(find.text('Pareamento recusado'), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    expect(fake.calls, contains('reconnectLast'));
  });

  testWidgets('painel de debug mostra frames em hex e CRC divergente', (tester) async {
    await pump(tester);
    final frame = buildFrame(kClassNotify, kTypeWeight, [0, 0, 0, 184, 0, 0, 0, 0, 0]);
    fake.emitFrame(FrameLogEntry(at: DateTime(2026), outgoing: false, bytes: frame, crcOk: false));
    fake.emitFrame(FrameLogEntry(at: DateTime(2026), outgoing: true, bytes: Uint8List.fromList([0xA5, 0x5A, 0x03])));
    await tester.pump();
    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A5 5A 01 01'), findsOneWidget);
    expect(find.textContaining('CRC ≠'), findsOneWidget);
  });

  testWidgets('erro oferece voltar a procurar balanças', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.error, message: 'A balança não respondeu'));
    await tester.pump();
    await tester.tap(find.text('Procurar balança'));
    await tester.pump();
    expect(fake.calls, containsAllInOrder(['disconnect', 'startScan']));
  });

  testWidgets('Tarar envia a tara quando ao vivo', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    fake.emitEvent(_w);
    await tester.pump();
    await tester.tap(find.text('Tarar'));
    expect(fake.calls, contains('tare'));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Tarar fica desativado ao reconectar', (tester) async {
    await pump(tester);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    fake.emitEvent(_w);
    await tester.pump();
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.reconnecting));
    await tester.pump();
    await tester.tap(find.text('Tarar'));
    expect(fake.calls, isNot(contains('tare')));
  });

  testWidgets('falha da tara aparece na tela', (tester) async {
    await pump(tester);
    fake.tareFailure = StateError('link caiu');
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    fake.emitEvent(_w);
    await tester.pump();
    await tester.tap(find.text('Tarar'));
    await tester.pump();
    expect(find.text('Não foi possível tarar. Tente de novo.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
