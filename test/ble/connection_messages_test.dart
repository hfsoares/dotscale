import 'package:dotscale/ble/connection_messages.dart';
import 'package:dotscale/ble/scale_connection.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timeout do flutter_blue_plus vira mensagem amigável', () {
    final e = FlutterBluePlusException(ErrorPlatform.fbp, 'connect', FbpErrorCode.timeout.index, 'Timed out after 10s');
    expect(describeConnectError(e), 'A balança não respondeu. Ela está ligada e perto?');
  });

  test('falha de pareamento', () {
    expect(describeConnectError(PairingFailed('x')), 'Pareamento recusado ou falhou');
  });

  test('adaptador ligado não é problema', () {
    expect(adapterProblem(BluetoothAdapterState.on), isNull);
  });

  test('adaptador desligado', () {
    final s = adapterProblem(BluetoothAdapterState.off)!;
    expect(s.phase, ConnectionPhase.bluetoothOff);
    expect(s.message, 'Bluetooth desligado');
  });

  test('sem autorização é permissão negada', () {
    expect(adapterProblem(BluetoothAdapterState.unauthorized)!.phase, ConnectionPhase.permissionDenied);
  });

  test('estado desconhecido não diz que o Bluetooth está desligado', () {
    final s = adapterProblem(BluetoothAdapterState.unknown)!;
    expect(s.message, isNot('Bluetooth desligado'));
    expect(s.message, contains('permissão'));
  });
}
