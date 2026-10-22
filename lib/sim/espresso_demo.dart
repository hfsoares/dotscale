import '../espresso/container_store.dart';
import '../espresso/scale_container.dart';
import 'simulated_dot_connection.dart';

const demoContainers = [
  ScaleContainer(id: 'd', name: 'Dosímetro de porcelana', kind: ContainerKind.doser, grams: 80.0),
  ScaleContainer(id: 'g', name: 'Copinho da Starseeker', kind: ContainerKind.grinderCup, grams: 40.0),
  ScaleContainer(id: 'x', name: 'Xícara favorita', kind: ContainerKind.cup, grams: 120.0),
];

/// Recipientes só em memória: a simulação não mexe nos cadastrados de verdade.
class MemoryContainerStore implements ContainerStore {
  MemoryContainerStore(this._containers);

  List<ScaleContainer> _containers;

  @override
  Future<List<ScaleContainer>> load() async => _containers;
  @override
  Future<void> save(List<ScaleContainer> containers) async => _containers = containers;
}

Duration _s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

/// Espresso completo: 18,2 g de grãos, 17,9 g de pó no copinho, pré-infusão de 8 s e 36,1 g de bebida
/// em 27 s; no fim a balança e a xícara saem da Gaggia juntas e o resumo é fechado.
List<SimSegment> espressoDemo({required void Function() pressStart, required void Function() pressFinish}) => [
  SimSegment.hold(0, _s(3), mark: '01-ocioso'),
  SimSegment(0, 80, _s(0.4)),
  SimSegment.hold(80, _s(3), mark: '02-dosimetro'),
  SimSegment(80, 89, _s(3), mark: '03-pesando-graos'),
  SimSegment(89, 98.2, _s(3)),
  SimSegment.hold(98.2, _s(3), mark: '04-graos-pesados'),
  SimSegment(98.2, 0, _s(0.4)),
  SimSegment.hold(0, _s(3), mark: '05-aguardando-po'),
  SimSegment(0, 57.9, _s(0.5)),
  SimSegment.hold(57.9, _s(3), mark: '06-dose-no-copinho'),
  SimSegment(57.9, 0, _s(0.4)),
  SimSegment.hold(0, _s(3), mark: '07-aguardando-xicara'),
  SimSegment(0, 120, _s(0.5)),
  SimSegment.hold(120, _s(3), mark: '08-xicara-pronta'),
  SimSegment.hold(120, _s(8), mark: '09-pre-infusao', action: pressStart),
  SimSegment(120, 138, _s(13), mark: '10-extraindo'),
  SimSegment(138, 156.1, _s(14)),
  SimSegment.hold(156.1, _s(2.5), mark: '11-fluxo-parou'),
  SimSegment.hold(156.1, _s(5), mark: '12-resultado'),
  SimSegment(156.1, 30, _s(0.3)),
  SimSegment(30, 190, _s(0.3)),
  SimSegment(190, 156.1, _s(0.4)),
  SimSegment.hold(156.1, _s(4), mark: '13-resultado-fora-da-gaggia'),
  SimSegment.hold(156.1, _s(3), mark: '14-finalizado', action: pressFinish),
];
