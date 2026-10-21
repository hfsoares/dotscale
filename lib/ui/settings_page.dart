import 'package:flutter/material.dart';

import 'debug_panel.dart';
import 'scale_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final ScaleController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(children: [DebugPanel(log: controller.log)]),
      ),
    );
  }
}
