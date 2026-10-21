import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'scale_connection.dart';

class PairingFailed implements Exception {
  final Object cause;
  PairingFailed(this.cause);
}

/// Estado a mostrar quando o adaptador não está pronto; null quando está ligado.
ConnectionStatus? adapterProblem(BluetoothAdapterState state) => switch (state) {
  BluetoothAdapterState.on => null,
  BluetoothAdapterState.unauthorized =>
    const ConnectionStatus(ConnectionPhase.permissionDenied, message: 'Permissão de Bluetooth negada'),
  // No iOS o estado fica "unknown" até o usuário responder ao pedido de permissão.
  BluetoothAdapterState.unknown => const ConnectionStatus(
    ConnectionPhase.bluetoothOff,
    message: 'Aguardando o Bluetooth. Se apareceu um pedido de permissão, aceite e tente de novo.',
  ),
  _ => const ConnectionStatus(ConnectionPhase.bluetoothOff, message: 'Bluetooth desligado'),
};

String describeConnectError(Object e) {
  if (e is PairingFailed) return 'Pareamento recusado ou falhou';
  if (e is StateError) return e.message;
  final timedOut =
      e is TimeoutException || (e is FlutterBluePlusException && e.code == FbpErrorCode.timeout.index);
  if (timedOut) return 'A balança não respondeu. Ela está ligada e perto?';
  return 'Falha ao conectar: $e';
}
