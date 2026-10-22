import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'ble/fbp_dot_connection.dart';
import 'ble/scale_connection.dart';
import 'espresso/container_store.dart';
import 'ui/espresso_controller.dart';
import 'ui/home_page.dart';
import 'ui/scale_controller.dart';
import 'sim/espresso_demo.dart';
import 'sim/simulated_dot_connection.dart';

// flutter run --dart-define=SIMULATE=true: espresso de demonstração sem a Dot.
const _simulate = bool.fromEnvironment('SIMULATE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late final EspressoController espresso;
  final ScaleConnection connection = _simulate
      ? SimulatedDotConnection(
          espressoDemo(pressStart: () => espresso.startTimer(), pressFinish: () => espresso.dismissResult()),
        )
      : FbpDotConnection();
  // O celular fica ao lado da máquina: tela acesa só enquanto a balança transmite.
  final controller = ScaleController(connection, onLiveChanged: (live) => WakelockPlus.toggle(enable: live));
  espresso = EspressoController(connection, _simulate ? MemoryContainerStore(demoContainers) : PrefsContainerStore());
  await espresso.load();
  runApp(DotScaleApp(controller: controller, espresso: espresso));
  connection.reconnectLast();
}

class DotScaleApp extends StatelessWidget {
  const DotScaleApp({super.key, required this.controller, required this.espresso});

  final ScaleController controller;
  final EspressoController espresso;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DotScale',
      theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.brown, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(controller: controller, espresso: espresso),
    );
  }
}
