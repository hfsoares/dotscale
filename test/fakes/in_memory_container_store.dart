import 'package:dotscale/espresso/container_store.dart';
import 'package:dotscale/espresso/scale_container.dart';

class InMemoryContainerStore implements ContainerStore {
  InMemoryContainerStore([List<ScaleContainer> initial = const []]) : containers = List.of(initial);

  List<ScaleContainer> containers;
  int saves = 0;

  @override
  Future<List<ScaleContainer>> load() async => List.of(containers);

  @override
  Future<void> save(List<ScaleContainer> list) async {
    saves++;
    containers = List.of(list);
  }
}
