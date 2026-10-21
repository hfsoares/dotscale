import 'package:flutter/material.dart';

import '../ble/scale_connection.dart';

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';

/// Frames crus (RX/TX) para validar o protocolo na balança real.
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key, required this.log});

  final List<FrameLogEntry> log;

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return ExpansionTile(
      title: const Text('Debug'),
      subtitle: Text('${log.length} frames'),
      children: [
        SizedBox(
          height: 240,
          child: ListView.builder(
            itemCount: log.length,
            itemBuilder: (context, i) {
              final e = log[i];
              final crc = e.crcOk ? '' : '  CRC ≠';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: SelectableText('${_time(e.at)} ${e.outgoing ? 'TX' : 'RX'}  ${_hex(e.bytes)}$crc', style: mono),
              );
            },
          ),
        ),
      ],
    );
  }
}
