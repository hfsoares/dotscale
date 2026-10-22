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
    final net = session.netGrams;
    final shown = session.displayGrams;
    final instruction = _instruction(step);
    final dose = session.dose;
    final timed = step == EspressoStep.preInfusion || step == EspressoStep.extracting;
    final showResult = step == EspressoStep.idle && session.result != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (instruction != null) Text(instruction, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        if (session.reconnectWarning)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'A balança desconectou. Se ela reiniciou, os pesos podem estar errados — cancele e recomece.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (timed)
          // Bebida, ratio e tempo pesam igual enquanto o café sai.
          Opacity(
            opacity: widget.live ? 1 : 0.35,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  _Metric('Bebida', net == null ? '--' : formatGrams(net < 0 ? 0 : net)),
                  _Metric('Ratio', net == null || dose == null ? '--' : formatRatio(net < 0 ? 0 : net, dose)),
                  _Metric('Tempo', elapsed == null ? '--' : formatSeconds(elapsed)),
                ],
              ),
            ),
          )
        else if (!showResult)
          Opacity(
            opacity: widget.live ? 1 : 0.35,
            child: FittedBox(
              child: Text(
                shown == null ? '--' : formatGrams(shown),
                style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w600, fontFeatures: _tabular),
              ),
            ),
          ),
        ..._details(session, step),
        if (showResult) _ResultCard(result: session.result!),
        const SizedBox(height: 16),
        if (step == EspressoStep.awaitingGrounds)
          FilledButton(onPressed: espresso.useBeansAsDose, child: const Text('Usar peso dos grãos')),
        if (step == EspressoStep.cupReady) _BigButton('Pré-infusão', onPressed: espresso.startTimer),
        if (step == EspressoStep.preInfusion) _BigButton('Infusão', onPressed: espresso.startExtraction),
        if (showResult) _BigButton('Finalizar', onPressed: espresso.dismissResult),
        if (step != EspressoStep.idle)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(onPressed: espresso.cancel, child: const Text('Cancelar')),
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

String? _instruction(EspressoStep step) => switch (step) {
  EspressoStep.idle => null,
  EspressoStep.weighingBeans => 'Grãos',
  EspressoStep.awaitingGrounds => 'Coloque o copinho com o pó',
  EspressoStep.awaitingCup => 'Coloque a xícara na Gaggia',
  EspressoStep.cupReady => 'Xícara pronta',
  EspressoStep.preInfusion => 'Pré-infusão',
  EspressoStep.extracting => 'Extraindo',
};

/// Um dos três números da extração: rótulo pequeno em cima, valor grande com a unidade menor.
class _Metric extends StatelessWidget {
  const _Metric(this.label, this.text);

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = text.lastIndexOf(' ');
    final value = split < 0 ? text : text.substring(0, split);
    final unit = split < 0 ? '' : text.substring(split);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Text(label, style: theme.textTheme.titleMedium),
            FittedBox(
              child: Text.rich(
                TextSpan(
                  text: value,
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, fontFeatures: _tabular),
                  children: [TextSpan(text: unit, style: const TextStyle(fontSize: 17))],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão do próximo passo: grande, para acertar com a mão ocupada.
class _BigButton extends StatelessWidget {
  const _BigButton(this.label, {required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(96),
      textStyle: Theme.of(context).textTheme.headlineMedium,
    ),
    child: Text(label),
  );
}

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
            if (result.interrupted)
              Text(
                'A conexão caiu durante a extração; confira os números.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
