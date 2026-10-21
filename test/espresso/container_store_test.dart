import 'package:dotscale/espresso/container_store.dart';
import 'package:dotscale/espresso/scale_container.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load sem nada salvo devolve vazio', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PrefsContainerStore().load(), isEmpty);
  });

  test('save e load devolvem a mesma lista', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsContainerStore();
    await store.save(const [
      ScaleContainer(id: 'd', name: 'Dosímetro', kind: ContainerKind.doser, grams: 80.0),
      ScaleContainer(id: 'g', name: 'Copinho', kind: ContainerKind.grinderCup, grams: 40.2),
    ]);
    final loaded = await PrefsContainerStore().load();
    expect(loaded.map((c) => c.id), ['d', 'g']);
    expect(loaded[1].kind, ContainerKind.grinderCup);
    expect(loaded[1].grams, 40.2);
  });

  test('JSON corrompido devolve vazio', () async {
    SharedPreferences.setMockInitialValues({'containers': 'xx'});
    expect(await PrefsContainerStore().load(), isEmpty);
  });
}
