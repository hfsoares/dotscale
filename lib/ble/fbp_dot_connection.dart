import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/commands.dart';
import '../protocol/dot_event.dart';
import '../protocol/frame_decoder.dart';
import 'connection_messages.dart';
import 'dot_name.dart';
import 'last_scale_store.dart';
import 'scale_connection.dart';

final _serviceUuid = Guid('fff0');
final _notifyUuid = Guid('fff1');
final _commandUuid = Guid('fff2');

const _scanTimeout = Duration(seconds: 15);
const _connectAttempts = 3;
const _connectRetryDelay = Duration(milliseconds: 500);
const _settleAfterSubscribe = Duration(milliseconds: 500);
const _settleBetweenCommands = Duration(milliseconds: 200);
const _maxReconnectDelay = Duration(seconds: 10);
const _batteryPollInterval = Duration(seconds: 60);

/// Conexão com a Timemore Dot via flutter_blue_plus.
///
/// Sequência: conectar → bond (Android) → descobrir FFF0 → assinar FFF1
/// → unidade em gramas → modo padrão. Sem tara e sem keep-alive.
class FbpDotConnection implements ScaleConnection {
  FbpDotConnection({LastScaleStore? store}) : _store = store ?? LastScaleStore();

  final LastScaleStore _store;
  final _decoder = FrameDecoder();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _scanController = StreamController<List<FoundScale>>.broadcast();
  final _eventController = StreamController<DotEvent>.broadcast();
  final _frameController = StreamController<FrameLogEntry>.broadcast();

  ConnectionStatus _status = const ConnectionStatus(ConnectionPhase.idle);
  BluetoothDevice? _device;
  BluetoothCharacteristic? _command;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  Timer? _batteryTimer;
  bool _userDisconnected = true;
  bool _reconnecting = false;

  @override
  ConnectionStatus get currentStatus => _status;
  @override
  Stream<ConnectionStatus> get status => _statusController.stream;
  @override
  Stream<List<FoundScale>> get scanResults => _scanController.stream;
  @override
  Stream<DotEvent> get events => _eventController.stream;
  @override
  Stream<FrameLogEntry> get frames => _frameController.stream;

  void _setStatus(ConnectionPhase phase, {String? message}) {
    _status = ConnectionStatus(phase, deviceName: _device?.platformName, message: message);
    _statusController.add(_status);
  }

  /// Confere adaptador ligado; emite o estado adequado e devolve false se não der.
  Future<bool> _ensureAdapterOn() async {
    if (!await FlutterBluePlus.isSupported) {
      _setStatus(ConnectionPhase.error, message: 'Este aparelho não tem Bluetooth LE');
      return false;
    }
    final state = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown)
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
    final problem = adapterProblem(state);
    if (problem != null) {
      _setStatus(problem.phase, message: problem.message);
      return false;
    }
    return true;
  }

  bool _isPermissionError(Object e) => e.toString().toLowerCase().contains('permission');

  @override
  Future<void> startScan() async {
    if (!await _ensureAdapterOn()) return;
    await _scanSub?.cancel();
    await _isScanningSub?.cancel();

    final found = <String, FoundScale>{};
    _scanController.add(const []);
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        final advertisesService = r.advertisementData.serviceUuids.contains(_serviceUuid);
        if (!isDotName(name) && !advertisesService) continue;
        final id = r.device.remoteId.str;
        found[id] = FoundScale(id, name.isEmpty ? id : name, r.rssi);
      }
      _scanController.add(found.values.toList());
    });
    _isScanningSub = FlutterBluePlus.isScanning.skip(1).listen((scanning) {
      if (!scanning && _status.phase == ConnectionPhase.scanning) _setStatus(ConnectionPhase.idle);
    });

    _setStatus(ConnectionPhase.scanning);
    try {
      await FlutterBluePlus.startScan(timeout: _scanTimeout);
    } catch (e) {
      if (_isPermissionError(e)) {
        _setStatus(ConnectionPhase.permissionDenied, message: 'Permissão de Bluetooth negada');
      } else {
        _setStatus(ConnectionPhase.error, message: 'Falha ao procurar: $e');
      }
    }
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  @override
  Future<void> connect(String deviceId) async {
    await stopScan();
    await _teardown();
    _userDisconnected = false;
    _device = BluetoothDevice.fromId(deviceId);
    if (!await _ensureAdapterOn()) return;
    try {
      await _connectOnce(ConnectionPhase.connecting);
    } catch (e) {
      if (_userDisconnected) return;
      await _teardown(disconnectDevice: true);
      _setStatus(
        _isPermissionError(e) ? ConnectionPhase.permissionDenied : ConnectionPhase.error,
        message: _isPermissionError(e) ? 'Permissão de Bluetooth negada' : describeConnectError(e),
      );
    }
  }

  Future<void> _connectOnce(ConnectionPhase phase) async {
    final device = _device!;
    _setStatus(phase);

    // Logo após uma sessão anterior, a Dot pode segurar o link antigo por um instante.
    for (var attempt = 1;; attempt++) {
      try {
        await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 10));
        break;
      } catch (_) {
        if (attempt >= _connectAttempts || _userDisconnected) rethrow;
        await Future<void>.delayed(_connectRetryDelay);
      }
    }

    // A Dot só transmite com o link criptografado. No iOS o sistema pareia sozinho.
    if (Platform.isAndroid && await device.bondState.first != BluetoothBondState.bonded) {
      _setStatus(ConnectionPhase.pairing);
      try {
        await device.createBond();
      } catch (e) {
        throw PairingFailed(e);
      }
    }

    final services = await device.discoverServices();
    final service = services.where((s) => s.uuid == _serviceUuid).firstOrNull;
    final notify = service?.characteristics.where((c) => c.uuid == _notifyUuid).firstOrNull;
    final command = service?.characteristics.where((c) => c.uuid == _commandUuid).firstOrNull;
    if (notify == null || command == null) {
      throw StateError('Serviço FFF0/FFF1/FFF2 não encontrado. É mesmo uma Timemore Dot?');
    }
    _command = command;

    _decoder.reset();
    await _notifySub?.cancel();
    _notifySub = notify.onValueReceived.listen(_onNotify);
    device.cancelWhenDisconnected(_notifySub!);
    try {
      await notify.setNotifyValue(true);
    } catch (_) {
      await notify.setNotifyValue(true, forceIndications: true);
    }

    await _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) _onLinkLost();
    });

    await Future<void>.delayed(_settleAfterSubscribe);
    await _send(DotCommands.unitGrams());
    await Future<void>.delayed(_settleBetweenCommands);
    await _send(DotCommands.standardMode());
    await Future<void>.delayed(_settleBetweenCommands);
    await _send(DotCommands.queryBattery());
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(_batteryPollInterval, (_) {
      if (_command != null) unawaited(_send(DotCommands.queryBattery()).catchError((_) {}));
    });

    await _store.save(device.remoteId.str);
    _setStatus(ConnectionPhase.connected);
  }

  void _onNotify(List<int> value) {
    for (final frame in _decoder.add(value)) {
      _frameController.add(FrameLogEntry(at: DateTime.now(), outgoing: false, bytes: frame.bytes, crcOk: frame.crcOk));
      final event = frame.event;
      if (event != null) _eventController.add(event);
    }
  }

  Future<void> _send(Uint8List frame) async {
    _frameController.add(FrameLogEntry(at: DateTime.now(), outgoing: true, bytes: frame));
    await _command!.write(frame, withoutResponse: true);
  }

  void _onLinkLost() {
    _batteryTimer?.cancel();
    if (_userDisconnected || _reconnecting) return;
    if (_status.phase != ConnectionPhase.connected) return; // falha durante a conexão: tratada em connect()
    unawaited(_reconnectLoop());
  }

  Future<void> _reconnectLoop() async {
    _reconnecting = true;
    var delay = const Duration(seconds: 1);
    try {
      while (!_userDisconnected) {
        // Com o Bluetooth desligado, dizer isso e esperar ele voltar em vez de tentar à toa.
        if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
          _setStatus(ConnectionPhase.bluetoothOff, message: 'Bluetooth desligado. Reconecto quando ele voltar.');
          await FlutterBluePlus.adapterState.firstWhere((s) => s == BluetoothAdapterState.on);
          delay = const Duration(seconds: 1);
          if (_userDisconnected) return;
        }
        _setStatus(ConnectionPhase.reconnecting);
        await Future<void>.delayed(delay);
        if (_userDisconnected) return;
        try {
          await _connectOnce(ConnectionPhase.reconnecting);
          return;
        } catch (_) {
          delay = Duration(milliseconds: math.min(delay.inMilliseconds * 2, _maxReconnectDelay.inMilliseconds));
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  @override
  Future<void> tare() async {
    if (_command == null || _status.phase != ConnectionPhase.connected) {
      throw StateError('Balança não conectada');
    }
    await _send(DotCommands.tare());
  }

  @override
  Future<void> disconnect() async {
    _userDisconnected = true;
    await _teardown(disconnectDevice: true);
    _setStatus(ConnectionPhase.idle);
  }

  @override
  Future<void> reconnectLast() async {
    final id = _device?.remoteId.str ?? await _store.load();
    if (id == null) return startScan();
    return connect(id);
  }

  Future<void> _teardown({bool disconnectDevice = false}) async {
    _batteryTimer?.cancel();
    _batteryTimer = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _notifySub?.cancel();
    _notifySub = null;
    _command = null;
    if (disconnectDevice) {
      try {
        await _device?.disconnect();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _userDisconnected = true;
    unawaited(_teardown(disconnectDevice: true));
    unawaited(_scanSub?.cancel());
    unawaited(_isScanningSub?.cancel());
    _statusController.close();
    _scanController.close();
    _eventController.close();
    _frameController.close();
  }
}
