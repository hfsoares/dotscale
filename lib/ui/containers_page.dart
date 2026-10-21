import 'package:flutter/material.dart';

import '../espresso/scale_container.dart';
import 'espresso_controller.dart';
import 'format.dart';

class ContainersPage extends StatelessWidget {
  const ContainersPage({super.key, required this.controller});

  final EspressoController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recipientes')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final grams = controller.registrableGrams;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Os recipientes são reconhecidos pelo peso. Ligue a balança vazia; '
                'se o zero estiver errado, use Tarar com ela vazia.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: grams == null ? null : () => _register(context, grams),
                icon: const Icon(Icons.add),
                label: const Text('Cadastrar recipiente'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  grams == null
                      ? 'Coloque o recipiente vazio na balança e espere o peso parar.'
                      : 'Na balança: ${formatGrams(grams)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              for (final c in controller.containers)
                ListTile(
                  title: Text(c.name),
                  subtitle: Text('${c.kind.label} · ${formatGrams(c.grams)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Renomear',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _rename(context, c),
                      ),
                      IconButton(
                        tooltip: 'Apagar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => controller.remove(c.id),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _register(BuildContext context, double grams) async {
    final near = controller.nearRegistrable();
    final result = await showDialog<(String, ContainerKind)>(
      context: context,
      builder: (context) => _RegisterDialog(grams: grams, near: near),
    );
    if (result == null) return;
    await controller.addContainer(result.$1, result.$2, grams: grams);
  }

  Future<void> _rename(BuildContext context, ScaleContainer container) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title: 'Renomear', initial: container.name),
    );
    if (name != null) await controller.rename(container.id, name);
  }
}

class _RegisterDialog extends StatefulWidget {
  const _RegisterDialog({required this.grams, required this.near});

  final double grams;
  final List<ScaleContainer> near;

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final _name = TextEditingController();
  ContainerKind _kind = ContainerKind.doser;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Cadastrar recipiente'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatGrams(widget.grams), style: Theme.of(context).textTheme.headlineSmall),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nome'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final kind in ContainerKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          if (widget.near.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Atenção: parecido com ${widget.near.map((c) => c.name).join(', ')}; podem ser confundidos.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, (_name.text.trim(), _kind)),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Nome'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isNotEmpty) Navigator.pop(context, name);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
