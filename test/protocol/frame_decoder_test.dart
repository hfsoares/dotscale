import 'package:dotscale/protocol/commands.dart';
import 'package:dotscale/protocol/dot_event.dart';
import 'package:dotscale/protocol/frame_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _be16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

List<int> weightFrame(int raw, {int flow = 0, int timer = 0, int overload = 0, int frameClass = kClassNotify}) =>
    buildFrame(frameClass, kTypeWeight, [..._be32(raw), ..._be16(flow), ..._be16(timer), overload]);

WeightReading weightOf(DecodedFrame f) => f.event as WeightReading;

void main() {
  late FrameDecoder decoder;
  setUp(() => decoder = FrameDecoder());

  test('frame inteiro de peso', () {
    final frames = decoder.add(weightFrame(184));
    expect(frames, hasLength(1));
    expect(weightOf(frames.single).grams, 18.4);
    expect(frames.single.crcOk, isTrue);
  });

  test('peso negativo', () {
    expect(weightOf(decoder.add(weightFrame(-25)).single).grams, -2.5);
  });

  test('peso acima de 3276.7 g', () {
    expect(weightOf(decoder.add(weightFrame(45000)).single).grams, 4500.0);
  });

  test('fluxo negativo e timer', () {
    final w = weightOf(decoder.add(weightFrame(100, flow: -12, timer: 65)).single);
    expect(w.flowGramsPerSecond, -1.2);
    expect(w.timerSeconds, 65);
    expect(w.overload, isFalse);
  });

  test('flag de sobrecarga', () {
    expect(weightOf(decoder.add(weightFrame(100, overload: 1)).single).overload, isTrue);
  });

  test('frame dividido em 3 pedaços', () {
    final f = weightFrame(184);
    expect(decoder.add(f.sublist(0, 3)), isEmpty);
    expect(decoder.add(f.sublist(3, 10)), isEmpty);
    expect(decoder.add(f.sublist(10)), hasLength(1));
  });

  test('dois frames na mesma notificação', () {
    final frames = decoder.add([...weightFrame(10), ...weightFrame(20)]);
    expect(frames.map((f) => weightOf(f).grams), [1.0, 2.0]);
  });

  test('lixo antes do magic', () {
    final frames = decoder.add([0x00, 0x13, 0xA5, ...weightFrame(184)]);
    expect(frames, hasLength(1));
    expect(weightOf(frames.single).grams, 18.4);
  });

  test('A5 sem 5A é descartado', () {
    expect(decoder.add([0xA5, 0x00, ...weightFrame(184)]), hasLength(1));
  });

  test('tamanho absurdo ressincroniza', () {
    final frames = decoder.add([0xA5, 0x5A, 0x01, 0x01, 0x01, 0x00, ...weightFrame(184)]);
    expect(frames, hasLength(1));
    expect(weightOf(frames.single).grams, 18.4);
  });

  test('CRC divergente não derruba', () {
    final f = weightFrame(184);
    f[f.length - 1] ^= 0xFF;
    final frames = decoder.add(f);
    expect(frames, hasLength(1));
    expect(frames.single.crcOk, isFalse);
    expect(frames.single.event, isA<WeightReading>());
  });

  test('bateria', () {
    final e = decoder.add(buildFrame(kClassNotify, kTypeBattery, [0x02, 87])).single.event;
    expect((e as BatteryReading).percent, 87);
  });

  test('classe 0x02 também é relatório', () {
    expect(decoder.add(weightFrame(184, frameClass: kClassQuery)).single.event, isA<WeightReading>());
  });

  test('ACK de comando sem evento', () {
    expect(decoder.add(buildFrame(kClassCommand, kTypeTare, [1])).single.event, isNull);
  });

  test('tipo desconhecido', () {
    final e = decoder.add(buildFrame(kClassNotify, 0x10, [1, 2])).single.event;
    expect(e, isA<UnknownReport>());
    expect((e as UnknownReport).type, 0x10);
  });

  test('reset descarta bytes pendentes', () {
    final f = weightFrame(184);
    decoder.add(f.sublist(0, 5));
    decoder.reset();
    expect(decoder.add(f.sublist(5)), isEmpty);
  });
}
