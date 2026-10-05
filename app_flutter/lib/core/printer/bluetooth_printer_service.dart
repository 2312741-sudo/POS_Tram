// lib/core/printer/bluetooth_printer_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'printer_types.dart';

/// Dịch vụ kết nối và quản lý máy in nhiệt Bluetooth
class BluetoothPrinterService extends ChangeNotifier {
  static final BluetoothPrinterService _instance = BluetoothPrinterService._internal();
  static BluetoothPrinterService get instance => _instance;
  BluetoothPrinterService._internal();

  static const String _keyMac = 'tram_pos_bt_printer_mac';
  static const String _keyName = 'tram_pos_bt_printer_name';
  static const String _keyPaperSize = 'tram_pos_paper_size';
  static const String _keyEncoding = 'tram_pos_text_encoding';
  static const String _keyAutoReconnect = 'tram_pos_auto_reconnect';

  String _savedMac = '';
  String _savedName = '';
  PrinterPaperSize _paperSize = PrinterPaperSize.mm58;
  PrinterTextEncoding _encoding = PrinterTextEncoding.vietnameseAscii;
  bool _autoReconnect = true;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isScanning = false;
  String _lastErrorMessage = '';

  String get savedMac => _savedMac;
  String get savedName => _savedName;
  PrinterPaperSize get paperSize => _paperSize;
  PrinterTextEncoding get encoding => _encoding;
  bool get autoReconnectEnabled => _autoReconnect;

  bool get isConnectedState => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isScanning => _isScanning;
  String get lastErrorMessage => _lastErrorMessage;

  /// Khởi tạo và đọc cấu hình đã lưu
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedMac = prefs.getString(_keyMac) ?? '';
      _savedName = prefs.getString(_keyName) ?? '';
      _paperSize = PrinterPaperSize.fromString(prefs.getString(_keyPaperSize));
      _encoding = PrinterTextEncoding.fromString(prefs.getString(_keyEncoding));
      _autoReconnect = prefs.getBool(_keyAutoReconnect) ?? true;

      // Kiểm tra trạng thái kết nối ban đầu
      await checkConnectionStatus();

      // Nếu có máy in đã lưu và bật auto-reconnect mà chưa kết nối, thử kết nối
      if (_savedMac.isNotEmpty && _autoReconnect && !_isConnected) {
        autoReconnect();
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Cập nhật khổ giấy (58mm hoặc 80mm)
  Future<void> setPaperSize(PrinterPaperSize size) async {
    _paperSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPaperSize, size.name);
    notifyListeners();
  }

  /// Cập nhật chế độ mã hóa tiếng Việt
  Future<void> setEncoding(PrinterTextEncoding enc) async {
    _encoding = enc;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEncoding, enc.name);
    notifyListeners();
  }

  /// Cập nhật tự động kết nối lại
  Future<void> setAutoReconnect(bool val) async {
    _autoReconnect = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoReconnect, val);
    notifyListeners();
  }

  /// Kiểm tra Bluetooth trên thiết bị đã bật hay chưa
  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra và xin quyền Bluetooth trên Android 12+
  Future<bool> checkPermission() async {
    try {
      return await PrintBluetoothThermal.isPermissionBluetoothGranted;
    } catch (_) {
      return false;
    }
  }

  /// Quét danh sách máy in Bluetooth đã ghép đôi hoặc ở gần
  Future<List<PrinterDevice>> scanPrinters() async {
    _isScanning = true;
    _lastErrorMessage = '';
    notifyListeners();

    try {
      final isBtOn = await isBluetoothEnabled();
      if (!isBtOn) {
        _lastErrorMessage = 'Bluetooth chưa được bật. Vui lòng bật Bluetooth để quét máy in.';
        _isScanning = false;
        notifyListeners();
        return [];
      }

      final perm = await checkPermission();
      if (!perm) {
        _lastErrorMessage = 'Chưa cấp quyền Bluetooth (Nearby Devices). Vui lòng cấp quyền trong Cài Đặt ứng dụng.';
        _isScanning = false;
        notifyListeners();
        return [];
      }

      final List<BluetoothInfo> rawList = await PrintBluetoothThermal.pairedBluetooths;
      final connected = await isConnected();

      final list = rawList.map((dev) {
        final isCur = connected && dev.macAdress.toUpperCase() == _savedMac.toUpperCase();
        return PrinterDevice(
          name: dev.name.isNotEmpty ? dev.name : 'Máy in (${dev.macAdress})',
          macAddress: dev.macAdress,
          isConnected: isCur,
        );
      }).toList();

      _isScanning = false;
      notifyListeners();
      return list;
    } catch (e) {
      _lastErrorMessage = 'Lỗi khi quét thiết bị Bluetooth: $e';
      _isScanning = false;
      notifyListeners();
      return [];
    }
  }

  /// Kết nối tới máy in theo địa chỉ MAC
  Future<bool> connect(String macAddress, {String? deviceName}) async {
    final mac = macAddress.trim();
    if (mac.isEmpty) {
      _lastErrorMessage = 'Địa chỉ MAC của máy in không hợp lệ.';
      return false;
    }

    _isConnecting = true;
    _lastErrorMessage = '';
    notifyListeners();

    try {
      final isBtOn = await isBluetoothEnabled();
      if (!isBtOn) {
        _lastErrorMessage = 'Bluetooth chưa được bật. Vui lòng bật Bluetooth để kết nối máy in.';
        _isConnecting = false;
        notifyListeners();
        return false;
      }

      final success = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      _isConnected = success;
      _isConnecting = false;

      if (success) {
        _savedMac = mac;
        if (deviceName != null && deviceName.isNotEmpty) {
          _savedName = deviceName;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyMac, _savedMac);
        await prefs.setString(_keyName, _savedName);
        _lastErrorMessage = '';
      } else {
        _lastErrorMessage = 'Không thể kết nối với máy in $mac. Vui lòng kiểm tra nguồn và ghép đôi máy in.';
      }

      notifyListeners();
      return success;
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _lastErrorMessage = 'Lỗi kết nối máy in: $e';
      notifyListeners();
      return false;
    }
  }

  /// Ngắt kết nối máy in
  Future<bool> disconnect() async {
    try {
      final res = await PrintBluetoothThermal.disconnect;
      _isConnected = false;
      notifyListeners();
      return res;
    } catch (_) {
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  /// Kiểm tra trạng thái kết nối hiện tại
  Future<bool> checkConnectionStatus() async {
    try {
      final status = await PrintBluetoothThermal.connectionStatus;
      _isConnected = status;
      notifyListeners();
      return status;
    } catch (_) {
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  /// Kiểm tra kết nối nhanh
  Future<bool> isConnected() async {
    return await checkConnectionStatus();
  }

  /// Tự động kết nối lại máy in đã lưu trong bộ nhớ
  Future<bool> autoReconnect() async {
    if (_savedMac.isEmpty) return false;
    if (_isConnected) return true;

    // Thử kết nối tối đa 2 lần
    for (int attempt = 1; attempt <= 2; attempt++) {
      final ok = await connect(_savedMac, deviceName: _savedName);
      if (ok) return true;
      if (attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return false;
  }

  /// Gửi chuỗi byte ESC/POS ra máy in qua kết nối Bluetooth
  Future<bool> printBytes(Uint8List data) async {
    if (data.isEmpty) return true;

    // 1. Kiểm tra Bluetooth
    final isBtOn = await isBluetoothEnabled();
    if (!isBtOn) {
      _lastErrorMessage = 'Bluetooth chưa được bật. Vui lòng bật Bluetooth để kết nối máy in.';
      return false;
    }

    // 2. Kiểm tra nếu chưa chọn máy in
    if (_savedMac.isEmpty) {
      _lastErrorMessage = 'Chưa chọn máy in Bluetooth. Vui lòng vào Cài Đặt Máy In để chọn thiết bị.';
      return false;
    }

    // 3. Nếu chưa kết nối, thử tự động kết nối lại
    bool connected = await isConnected();
    if (!connected) {
      connected = await autoReconnect();
      if (!connected) {
        _lastErrorMessage = 'Mất kết nối với máy in Bluetooth. Đang thử kết nối lại...';
        return false;
      }
    }

    // 4. Gửi dữ liệu ra máy in
    try {
      final success = await PrintBluetoothThermal.writeBytes(data);
      if (success) {
        _lastErrorMessage = '';
        return true;
      } else {
        _lastErrorMessage = 'Máy in mất kết nối hoặc hết giấy. Vui lòng kiểm tra giấy in và kết nối thiết bị.';
        _isConnected = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastErrorMessage = 'Máy in mất kết nối hoặc hết giấy. Chi tiết lỗi: $e';
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }
}
