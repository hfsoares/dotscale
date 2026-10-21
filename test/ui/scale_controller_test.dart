import 'dart:typed_data';

import 'package:dotscale/ble/scale_connection.dart';
import 'package:dotscale/protocol/dot_event.dart';
import 'package:dotscale/ui/scale_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scale_connection.dart';

const _w = WeightReading(grams: 18.4, flowGramsPerSecond: 1.2, timerSeconds: 0, overload: false);

void main() {
  late FakeScaleConnection fake;
  late ScaleController controller;
  setUp(() {
    fake = FakeScaleConnection();
    controller = ScaleController(fake, logCapacity: 3);
  });

  test('peso emitido atualiza lastWeight', () {
    fake.emitEvent(_w);
    expect(controller.lastWeight?.grams, 18.4);
  });

  test('bateria emitida atualiza batteryPercent', () {
    fake.emitEvent(const BatteryReading(87));
    expect(controller.batteryPercent, 87);
  });

  test('log limitado à capacidade, mais recente primeiro', () {
    for (var i = 0; i < 5; i++) {
      fake.emitFrame(FrameLogEntry(at: DateTime(2026), outgoing: false, bytes: Uint8List.fromList([i])));
    }
    expect(controller.log.map((e) => e.bytes.single), [4, 3, 2]);
  });

  test('reconnecting deixa de ser ao vivo mas preserva o peso', () {
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    fake.emitEvent(_w);
    expect(controller.isLive, isTrue);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.reconnecting));
    expect(controller.isLive, isFalse);
    expect(controller.lastWeight?.grams, 18.4);
  });

  test('onLiveChanged avisa entrada e saída de connected', () {
    final changes = <bool>[];
    final c = ScaleController(fake, onLiveChanged: changes.add);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.connected));
    fake.emitEvent(_w);
    fake.emitStatus(const ConnectionStatus(ConnectionPhase.reconnecting));
    expect(changes, [true, false]);
    c.dispose();
  });
}
