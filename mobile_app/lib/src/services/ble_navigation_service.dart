import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../config/app_constants.dart';

class BleNavigationService {
  Guid get _serviceUuid => Guid(AppConstants.bleServiceUuid);
  Guid get _characteristicUuid => Guid(AppConstants.bleCharacteristicUuid);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  bool _isConnecting = false;

  bool get isConnected =>
      _characteristic != null && _device != null && !_isConnecting;

  Future<void> start() async {
    if (await FlutterBluePlus.isSupported == false) {
      return;
    }

    _scanSubscription ??= FlutterBluePlus.onScanResults.listen(
      _handleScanResults,
      onError: (_) {},
    );

    await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first;

    if (await FlutterBluePlus.isScanning.first) {
      return;
    }

    await FlutterBluePlus.startScan(
      withNames: const [AppConstants.bleDeviceName],
      timeout: const Duration(seconds: 5),
    );
  }

  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _scanSubscription = null;
    _connectionSubscription = null;
  }

  Future<void> writePayload(Uint8List payload) async {
    if (_characteristic == null) {
      await start();
      return;
    }

    await _characteristic!.write(payload, withoutResponse: false);
  }

  Future<void> _handleScanResults(List<ScanResult> results) async {
    if (_isConnecting || _characteristic != null) {
      return;
    }

    for (final result in results) {
      final advertisedName = result.advertisementData.advName;
      final localName = result.advertisementData.localName;
      final platformName = result.device.platformName;
      final isTarget = advertisedName == AppConstants.bleDeviceName ||
          localName == AppConstants.bleDeviceName ||
          platformName == AppConstants.bleDeviceName;

      if (isTarget) {
        await FlutterBluePlus.stopScan();
        await _connect(result.device);
        break;
      }
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (_isConnecting) {
      return;
    }

    _isConnecting = true;
    try {
      _device = device;
      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _characteristic = null;
          Timer(const Duration(seconds: 2), () {
            start();
          });
        }
      });
      device.cancelWhenDisconnected(
        _connectionSubscription!,
        delayed: true,
        next: true,
      );

      await device.connect();
      await device.connectionState
          .where((state) => state == BluetoothConnectionState.connected)
          .first;

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid != _serviceUuid) {
          continue;
        }
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _characteristicUuid) {
            _characteristic = characteristic;
            return;
          }
        }
      }
    } finally {
      _isConnecting = false;
    }
  }
}
