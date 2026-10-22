import 'package:flutter/material.dart';

import '../ble/scale_connection.dart';
import '../espresso/espresso_session.dart';
import 'containers_page.dart';
import 'espresso_controller.dart';
import 'espresso_panel.dart';
import 'format.dart';
import 'scale_controller.dart';
import 'settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller, required this.espresso});

  final ScaleController controller;
  final EspressoController espresso;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, espresso]),
      builder: (context, _) {
        final status = controller.status;
        return Scaffold(
          appBar: AppBar(
            title: Text(status.deviceName?.isNotEmpty == true ? status.deviceName! : 'DotScale'),
            actions: [
              _ConnectionIcon(phase: status.phase, onDisconnect: controller.connection.disconnect),
              if (status.phase == ConnectionPhase.connected && controller.batteryPercent != null)
                _Battery(percent: controller.batteryPercent!),
              IconButton(
                tooltip: 'Recipientes',
                icon: const Icon(Icons.coffee),
                onPressed: () => _openContainers(context, espresso),
              ),
              IconButton(
                tooltip: 'Configurações',
                icon: const Icon(Icons.settings),
                onPressed: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => SettingsPage(controller: controller))),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(children: [Expanded(child: _body(context, status))]),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, ConnectionStatus status) {
    switch (status.phase) {
      case ConnectionPhase.connected:
      case ConnectionPhase.reconnecting:
        return _LiveView(controller: controller, espresso: espresso);
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
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_phaseText(status.phase), textAlign: TextAlign.center),
            ],
          ),
        );
      case ConnectionPhase.idle:
      case ConnectionPhase.scanning:
        return _ScanView(controller: controller, scanning: status.phase == ConnectionPhase.scanning);
    }
  }
}

void _openContainers(BuildContext context, EspressoController espresso) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ContainersPage(controller: espresso)));

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

/// Estado da conexão só como ícone; o texto fica no tooltip. Conectado, o toque abre o Desconectar.
class _ConnectionIcon extends StatelessWidget {
  const _ConnectionIcon({required this.phase, required this.onDisconnect});

  final ConnectionPhase phase;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (phase) {
      ConnectionPhase.connected => (Icons.bluetooth_connected, 'Conectado', scheme.onSurfaceVariant),
      ConnectionPhase.reconnecting => (Icons.bluetooth_searching, 'Reconectando…', scheme.error),
      ConnectionPhase.scanning => (Icons.bluetooth_searching, 'Procurando…', scheme.onSurfaceVariant),
      ConnectionPhase.connecting => (Icons.bluetooth_searching, 'Conectando…', scheme.onSurfaceVariant),
      ConnectionPhase.pairing => (Icons.bluetooth_searching, 'Pareando…', scheme.onSurfaceVariant),
      _ => (Icons.bluetooth_disabled, 'Desconectado', scheme.onSurfaceVariant),
    };
    if (phase == ConnectionPhase.connected || phase == ConnectionPhase.reconnecting) {
      return PopupMenuButton<void>(
        tooltip: label,
        icon: Icon(icon, size: 20, color: color),
        itemBuilder: (_) => [PopupMenuItem(onTap: onDisconnect, child: const Text('Desconectar'))],
      );
    }
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(icon, size: 20, color: color, semanticLabel: label),
      ),
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.percent});

  final int percent;

  static const _bars = [
    Icons.battery_0_bar,
    Icons.battery_1_bar,
    Icons.battery_2_bar,
    Icons.battery_3_bar,
    Icons.battery_4_bar,
    Icons.battery_5_bar,
    Icons.battery_6_bar,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final low = percent <= 15;
    final color = low ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
    final icon = low ? Icons.battery_alert : (percent >= 95 ? Icons.battery_full : _bars[(percent * 7 / 100).floor()]);
    return Tooltip(
      message: 'Bateria da balança',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            Text('$percent%', style: theme.textTheme.bodySmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _LiveView extends StatelessWidget {
  const _LiveView({required this.controller, required this.espresso});

  final ScaleController controller;
  final EspressoController espresso;

  @override
  Widget build(BuildContext context) {
    final weight = controller.lastWeight;
    final secondary = Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final session = espresso.session;
    // O resumo do último espresso ocupa a tela até o Finalizar.
    final showResult = session.step == EspressoStep.idle && session.result != null;
    // A tara manual mexe no zero de que o reconhecimento depende: só antes do dosímetro.
    final showTare = session.step == EspressoStep.idle && !showResult;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            if (!espresso.hasRequiredContainers) ...[
              const Text(
                'Cadastre o dosímetro e o copinho do moedor para o espresso automático.',
                textAlign: TextAlign.center,
              ),
              OutlinedButton(onPressed: () => _openContainers(context, espresso), child: const Text('Recipientes')),
              const SizedBox(height: 16),
            ],
            EspressoPanel(espresso: espresso, live: controller.isLive),
            if (!showResult) ...[
              const SizedBox(height: 8),
              Text(weight == null ? '-- g/s' : formatFlow(weight.flowGramsPerSecond), style: secondary),
            ],
            if (showTare) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: controller.isLive ? controller.tare : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(220, 72),
                  textStyle: Theme.of(context).textTheme.headlineSmall,
                ),
                child: const Text('Tarar'),
              ),
              if (controller.tareError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(controller.tareError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ],
        ),
      ),
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
