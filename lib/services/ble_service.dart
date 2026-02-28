import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class Bt04aBleService {
  Bt04aBleService({
    FlutterReactiveBle? ble,
    Uuid? serviceId,
    Uuid? notifyCharId,
  })  : _ble = ble ?? FlutterReactiveBle(),
        svcFfe0 = serviceId ??
            Uuid.parse("0000ffe0-0000-1000-8000-00805f9b34fb"),
        chrFfe1 = notifyCharId ??
            Uuid.parse("0000ffe1-0000-1000-8000-00805f9b34fb");

  final FlutterReactiveBle _ble;

  // BT04-A: service FFE0 / notify characteristic commonly FFE1
  final Uuid svcFfe0;
  final Uuid chrFfe1;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  String? _deviceId;
  String _rxBuf = "";

  final _luxCtrl = StreamController<double>.broadcast();
  Stream<double> get luxStream => _luxCtrl.stream;

  final _connCtrl = StreamController<bool>.broadcast();
  Stream<bool> get connectedStream => _connCtrl.stream;

  final _statusCtrl = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusCtrl.stream;

  bool _isDisposed = false;

  Future<void> _ensureBlePerms() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> startAutoConnect() async {
    if (_isDisposed) return;

    await _ensureBlePerms();
    stop();

    _connCtrl.add(false);
    _statusCtrl.add("BLE: scanning");

    _scanSub = _ble
        .scanForDevices(
      withServices: const [],
      scanMode: ScanMode.lowLatency,
    )
        .listen((d) {
      final name = d.name.trim();
      if (name.isEmpty) return;

      if (name.toUpperCase().contains("BT04")) {
        _scanSub?.cancel();
        _scanSub = null;

        _deviceId = d.id;
        _statusCtrl.add("BLE: connecting ($name)");
        _connect(d.id);
      }
    }, onError: (_) {
      _statusCtrl.add("BLE scan error");
      _retryLater();
    });
  }

  void _connect(String deviceId) {
    _connSub?.cancel();
    _connSub = _ble
        .connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    )
        .listen((u) {
      if (u.connectionState == DeviceConnectionState.connected) {
        _connCtrl.add(true);
        _statusCtrl.add("BLE: connected");
        _subscribeNotify(deviceId);
      } else if (u.connectionState == DeviceConnectionState.disconnected) {
        _connCtrl.add(false);
        _statusCtrl.add("BLE: disconnected (retry)");
        _notifySub?.cancel();
        _notifySub = null;
        _retryLater();
      }
    }, onError: (_) {
      _connCtrl.add(false);
      _statusCtrl.add("BLE connect error (retry)");
      _retryLater();
    });
  }

  void _subscribeNotify(String deviceId) {
    _notifySub?.cancel();
    _rxBuf = "";

    final q = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: svcFfe0,
      characteristicId: chrFfe1,
    );

    _statusCtrl.add("BLE: subscribing notify...");

    _notifySub = _ble.subscribeToCharacteristic(q).listen((bytes) {
      _onBleBytes(bytes);
    }, onError: (_) {
      // 常见原因：notify characteristic UUID 不是 FFE1
      _statusCtrl.add("Notify error (check UUID)");
    });
  }

  void _onBleBytes(List<int> bytes) {
    final chunk = utf8.decode(bytes, allowMalformed: true);
    _rxBuf += chunk;

    while (true) {
      final idx = _rxBuf.indexOf('\n');
      if (idx < 0) break;

      final line = _rxBuf.substring(0, idx).trim();
      _rxBuf = _rxBuf.substring(idx + 1);

      if (line.isEmpty) continue;
      if (line.toUpperCase() == "ERR") continue;

      final lux = double.tryParse(line);
      if (lux == null) continue;

      _luxCtrl.add(lux.clamp(0, 50000));
      _statusCtrl.add("BLE: streaming");
    }
  }

  void _retryLater() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_isDisposed) return;
      startAutoConnect();
    });
  }

  void stop() {
    _scanSub?.cancel();
    _scanSub = null;
    _notifySub?.cancel();
    _notifySub = null;
    _connSub?.cancel();
    _connSub = null;
  }

  void dispose() {
    _isDisposed = true;
    stop();
    _luxCtrl.close();
    _connCtrl.close();
    _statusCtrl.close();
  }
}