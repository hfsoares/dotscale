import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'ble/fbp_dot_connection.dart';
import 'ui/home_page.dart';
import 'ui/scale_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final connection = FbpDotConnection();
  // O celular fica ao lado da máquina: tela acesa só enquanto a balança transmite.
  final controller = ScaleController(connection, onLiveChanged: (live) => WakelockPlus.toggle(enable: live));
  runApp(DotScaleApp(controller: controller));
  connection.reconnectLast();
}

class DotScaleApp extends StatelessWidget {
  const DotScaleApp({super.key, required this.controller});

  final ScaleController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DotScale',
      theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.brown, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(controller: controller),
    );
  }
}
