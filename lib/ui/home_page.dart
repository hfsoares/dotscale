import 'package:flutter/material.dart';

import '../ble/scale_connection.dart';
import 'debug_panel.dart';
import 'format.dart';
import 'scale_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final ScaleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = controller.status;
        return Scaffold(
          appBar: AppBar(title: Text(status.deviceName?.isNotEmpty == true ? status.deviceName! : 'DotScale')),
          body: SafeArea(
            child: Column(
              children: [
                _StatusBar(status: status),
                Expanded(child: _body(context, status)),
                DebugPanel(log: controller.log),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, ConnectionStatus status) {
    switch (status.phase) {
      case ConnectionPhase.connected:
      case ConnectionPhase.reconnecting:
        return _LiveView(controller: controller);
      case ConnectionPhase.bluetoothOff:
      case ConnectionPhase.permissionDenied:
      case ConnectionPhase.error:
        return _Problem(
          message: status.message ?? _phaseText(status.phase),
          onRetry: controller.connection.reconnectLast,
          onScan: () async {
            await controller.connection.disconnect();
            await controller.connection.startScan();
          },
        );
      case ConnectionPhase.connecting:
      case ConnectionPhase.pairing:
        return const Center(child: CircularProgressIndicator());
      case ConnectionPhase.idle:
      case ConnectionPhase.scanning:
        return _ScanView(controller: controller, scanning: status.phase == ConnectionPhase.scanning);
    }
  }
}

String _phaseText(ConnectionPhase phase) => switch (phase) {
  ConnectionPhase.idle => 'Desconectado',
  ConnectionPhase.bluetoothOff => 'Bluetooth desligado',
  ConnectionPhase.permissionDenied => 'Permissão de Bluetooth negada',
  ConnectionPhase.scanning => 'Procurando…',
  ConnectionPhase.connecting => 'Conectando…',
  ConnectionPhase.pairing => 'Pareando… confirme no aviso do sistema, se aparecer',
  ConnectionPhase.connected => 'Conectado',
  ConnectionPhase.reconnecting => 'Reconectando…',
  ConnectionPhase.error => 'Erro',
};

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = status.phase == ConnectionPhase.connected;
    return Container(
      width: double.infinity,
      color: ok ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // Nos estados de problema o detalhe aparece no corpo da tela.
      child: Text(switch (status.phase) {
        ConnectionPhase.bluetoothOff || ConnectionPhase.permissionDenied || ConnectionPhase.error => 'Desconectado',
        final phase => _phaseText(phase),
      }),
    );
  }
}

class _LiveView extends StatelessWidget {
  const _LiveView({required this.controller});

  final ScaleController controller;

  @override
  Widget build(BuildContext context) {
    final weight = controller.lastWeight;
    final battery = controller.batteryPercent;
    const tabular = [FontFeature.tabularFigures()];
    final secondary = Theme.of(context).textTheme.titleLarge?.copyWith(fontFeatures: tabular);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Opacity(
          opacity: controller.isLive ? 1 : 0.35,
          child: Column(
            children: [
              FittedBox(
                child: Text(
                  weight == null ? '--' : formatGrams(weight.grams),
                  style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w600, fontFeatures: tabular),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(weight == null ? '-- g/s' : formatFlow(weight.flowGramsPerSecond), style: secondary),
                  const SizedBox(width: 32),
                  Text(battery == null ? '--%' : '$battery%', style: secondary),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: controller.isLive ? controller.tare : null,
          icon: const Icon(Icons.exposure_zero),
          label: const Text('Tarar'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(220, 72),
            textStyle: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        if (controller.tareError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(controller.tareError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 24),
        TextButton(onPressed: controller.connection.disconnect, child: const Text('Desconectar')),
      ],
    );
  }
}

class _ScanView extends StatelessWidget {
  const _ScanView({required this.controller, required this.scanning});

  final ScaleController controller;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: scanning ? null : controller.connection.startScan,
          icon: scanning
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bluetooth_searching),
          label: const Text('Procurar balança'),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final scale in controller.found)
                ListTile(
                  leading: const Icon(Icons.scale),
                  title: Text(scale.name),
                  subtitle: Text('${scale.rssi} dBm'),
                  onTap: () => controller.connection.connect(scale.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry, required this.onScan});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Tentar de novo')),
            const SizedBox(height: 8),
            TextButton(onPressed: onScan, child: const Text('Procurar balança')),
          ],
        ),
      ),
    );
  }
}
