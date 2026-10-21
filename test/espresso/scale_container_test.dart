import 'package:dotscale/espresso/scale_container.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const doser = ScaleContainer(id: 'd', name: 'Dosímetro', kind: ContainerKind.doser, grams: 80.0);
  const cup = ScaleContainer(id: 'x', name: 'Azul', kind: ContainerKind.cup, grams: 82.5);
  const grinderCup = ScaleContainer(id: 'g', name: 'Copinho', kind: ContainerKind.grinderCup, grams: 40.0);

  test('toJson/fromJson ida e volta', () {
    for (final c in [doser, cup, grinderCup]) {
      final back = ScaleContainer.fromJson(c.toJson());
      expect(back.id, c.id);
      expect(back.name, c.name);
      expect(back.kind, c.kind);
      expect(back.grams, c.grams);
    }
  });

  test('containersNear acha só os que estão a menos de 3 g', () {
    expect(containersNear([doser, cup, grinderCup], 81.0), [doser, cup]);
  });

  test('label em português', () {
    expect(ContainerKind.doser.label, 'Dosímetro');
    expect(ContainerKind.grinderCup.label, 'Copinho do moedor');
    expect(ContainerKind.cup.label, 'Xícara');
  });

  test('copyWith troca o nome', () {
    expect(doser.copyWith(name: 'Branco').name, 'Branco');
    expect(doser.copyWith(name: 'Branco').grams, 80.0);
  });
}
