import 'dart:async';

import 'package:flutter/material.dart';

import '../espresso/espresso_session.dart';
import 'espresso_controller.dart';
import 'format.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Instrução do passo, peso líquido grande e os números do espresso.
class EspressoPanel extends StatefulWidget {
  const EspressoPanel({super.key, required this.espresso, required this.live});

  final EspressoController espresso;

  /// A balança está transmitindo; senão o número aparece esmaecido.
  final bool live;

  @override
  State<EspressoPanel> createState() => _EspressoPanelState();
}

class _EspressoPanelState extends State<EspressoPanel> {
  Timer? _ticker;

  // O cronômetro precisa andar mesmo se o peso parar de chegar.
  void _syncTicker(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final espresso = widget.espresso;
    final session = espresso.session;
    final step = session.step;
    final elapsed = espresso.elapsed();
    _syncTicker(elapsed != null);

    final theme = Theme.of(context);
    final secondary = theme.textTheme.titleLarge?.copyWith(fontFeatures: _tabular);
    final net = session.netGrams;
    final dose = session.dose;
    final withCup = {EspressoStep.cupReady, EspressoStep.preInfusion, EspressoStep.extracting}.contains(step);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_instruction(step), style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        if (session.reconnectWarning)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'A balança desconectou. Se ela reiniciou, os pesos podem estar errados — cancele e recomece.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        Opacity(
          opacity: widget.live ? 1 : 0.35,
          child: FittedBox(
            child: Text(
              net == null ? '--' : formatGrams(net),
              style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w600, fontFeatures: _tabular),
            ),
          ),
        ),
        if (step != EspressoStep.idle && session.rawGrams != null)
          Text('Balança ${formatGrams(session.rawGrams!)}', style: theme.textTheme.bodySmall),
        ..._details(session, step),
        if (withCup && dose != null && net != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(formatRatio(net < 0 ? 0 : net, dose), style: secondary),
                if (elapsed != null) ...[const SizedBox(width: 32), Text(formatSeconds(elapsed), style: secondary)],
              ],
            ),
          ),
        if (step == EspressoStep.idle && session.result != null) _ResultCard(result: session.result!),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          alignment: WrapAlignment.center,
          children: [
            if (step == EspressoStep.awaitingGrounds)
              FilledButton(onPressed: espresso.useBeansAsDose, child: const Text('Usar peso dos grãos')),
            if (step == EspressoStep.cupReady)
              FilledButton(onPressed: espresso.startTimer, child: const Text('Iniciar')),
            if (step != EspressoStep.idle) OutlinedButton(onPressed: espresso.cancel, child: const Text('Cancelar')),
          ],
        ),
      ],
    );
  }

  List<Widget> _details(EspressoSession session, EspressoStep step) {
    final beans = session.beans;
    final dose = session.dose;
    final retention = session.retention;
    final line = switch (step) {
      EspressoStep.awaitingGrounds when beans != null => 'Grãos ${formatGrams(beans)}',
      EspressoStep.awaitingCup when dose != null =>
        retention == null
            ? 'Dose ${formatGrams(dose)}'
            : 'Dose ${formatGrams(dose)} · retenção ${formatGrams(retention)}',
      EspressoStep.cupReady || EspressoStep.preInfusion || EspressoStep.extracting when dose != null => [
        if (session.cupName != null) session.cupName!,
        'Dose ${formatGrams(dose)}',
      ].join(' · '),
      _ => null,
    };
    return [if (line != null) Text(line, style: Theme.of(context).textTheme.titleMedium)];
  }
}

String _instruction(EspressoStep step) => switch (step) {
  EspressoStep.idle => 'Coloque o dosímetro',
  EspressoStep.weighingBeans => 'Grãos',
  EspressoStep.awaitingGrounds => 'Coloque o copinho com o pó',
  EspressoStep.awaitingCup => 'Coloque a xícara na Gaggia',
  EspressoStep.cupReady => 'Pronto — inicie a extração',
  EspressoStep.preInfusion => 'Pré-infusão',
  EspressoStep.extracting => 'Extraindo',
};

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final EspressoResult result;

  @override
  Widget build(BuildContext context) {
    final pre = result.preInfusion;
    final rows = [
      ('Extração', formatSeconds(result.extraction)),
      if (pre != null) ('Pré-infusão', formatSeconds(pre)),
      if (pre != null) ('Total', formatSeconds(pre + result.extraction)),
      ('Dose', formatGrams(result.dose)),
      ('Bebida', formatGrams(result.beverage)),
      ('Ratio', formatRatio(result.beverage, result.dose)),
      if (result.cupName != null) ('Xícara', result.cupName!),
    ];
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(fontFeatures: _tabular);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Último espresso', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                for (final (label, value) in rows)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Text(label, style: style),
                      ),
                      Text(value, style: style),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
