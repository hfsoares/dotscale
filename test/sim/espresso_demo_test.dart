import 'package:flutter/foundation.dart';
import 'package:dotscale/espresso/espresso_session.dart';
import 'package:dotscale/sim/espresso_demo.dart';
import 'package:dotscale/sim/simulated_dot_connection.dart';
import 'package:dotscale/ui/espresso_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('o espresso de demonstração passa por todas as fases', (tester) async {
    late EspressoController espresso;
    final connection = SimulatedDotConnection(
      espressoDemo(pressStart: () => espresso.startTimer(), pressFinish: () => espresso.dismissResult()),
    );
    espresso = EspressoController(
      connection,
      MemoryContainerStore(demoContainers),
      now: () => tester.binding.clock.now(),
    );
    addTearDown(espresso.dispose);
    await espresso.load();

    final steps = <String, EspressoStep>{};
    EspressoResult? result;
    final printer = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message == null || !message.startsWith('SIMSHOT ')) return;
      steps[message.substring(8)] = espresso.session.step;
      if (message == 'SIMSHOT 13-resultado-fora-da-gaggia') result = espresso.session.result;
    };

    await connection.reconnectLast();
    for (var i = 0; i < 1000 && !steps.containsKey('end'); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await connection.disconnect();
    await tester.pump(const Duration(seconds: 2));
    debugPrint = printer;

    expect(steps, {
      'start': EspressoStep.idle,
      '01-ocioso': EspressoStep.idle,
      '02-dosimetro': EspressoStep.weighingBeans,
      '03-pesando-graos': EspressoStep.weighingBeans,
      '04-graos-pesados': EspressoStep.weighingBeans,
      '05-aguardando-po': EspressoStep.awaitingGrounds,
      '06-dose-no-copinho': EspressoStep.awaitingCup,
      '07-aguardando-xicara': EspressoStep.awaitingCup,
      '08-xicara-pronta': EspressoStep.cupReady,
      '09-pre-infusao': EspressoStep.preInfusion,
      '10-extraindo': EspressoStep.extracting,
      '11-fluxo-parou': EspressoStep.extracting,
      '12-resultado': EspressoStep.idle,
      '13-resultado-fora-da-gaggia': EspressoStep.idle,
      '14-finalizado': EspressoStep.idle,
      'end': EspressoStep.idle,
    });
    expect(espresso.session.result, isNull);
    final r = result!;
    expect(r.beans, closeTo(18.2, 0.15));
    expect(r.dose, closeTo(17.9, 0.15));
    expect(r.beverage, closeTo(36.1, 0.15));
    expect(r.extraction.inMilliseconds / 1000, closeTo(27, 0.7));
    expect(r.preInfusion!.inMilliseconds / 1000, closeTo(8, 0.7));
    expect(r.cupName, 'Xícara favorita');
  });
}
