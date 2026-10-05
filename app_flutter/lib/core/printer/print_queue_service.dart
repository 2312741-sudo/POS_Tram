// lib/core/printer/print_queue_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'printer_types.dart';
import 'bluetooth_printer_service.dart';

/// Dịch vụ Hàng đợi in lại (Print Queue Service)
/// Đảm bảo khi in gặp sự cố (mất kết nối, hết giấy, kẹt lệnh), phiếu không bao giờ bị mất,
/// người dùng theo dõi rõ trạng thái và có thể nhấn in lại bất cứ lúc nào.
class PrintQueueService extends ChangeNotifier {
  static final PrintQueueService _instance = PrintQueueService._internal();
  static PrintQueueService get instance => _instance;
  PrintQueueService._internal();

  static const String _storageKey = 'tram_pos_print_queue_v1';
  final List<PrintJob> _jobs = [];
  bool _isProcessing = false;

  List<PrintJob> get jobs => List.unmodifiable(_jobs);
  List<PrintJob> get failedJobs => _jobs.where((j) => j.status == PrintJobStatus.failed).toList();
  List<PrintJob> get pendingJobs => _jobs.where((j) => j.status == PrintJobStatus.pending).toList();
  int get failedCount => failedJobs.length;
  bool get isProcessing => _isProcessing;

  /// Khởi tạo và khôi phục hàng đợi từ bộ nhớ máy
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List list = jsonDecode(jsonStr);
        _jobs.clear();
        for (final item in list) {
          try {
            _jobs.add(PrintJob.fromMap(Map<String, dynamic>.from(item as Map)));
          } catch (_) {}
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Lưu hàng đợi vào bộ nhớ bền vững (SharedPreferences)
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _jobs.map((j) => j.toMap()).toList();
      await prefs.setString(_storageKey, jsonEncode(list));
    } catch (_) {}
  }

  /// Thêm một lệnh in vào hàng đợi và thực thi gửi lệnh ngay lập tức
  Future<bool> enqueueAndPrint({
    required String title,
    required String type, // 'BILL', 'KITCHEN', 'TEST'
    required Uint8List bytes,
    String? tableName,
    String? orderCode,
    String? billCode,
  }) async {
    final job = PrintJob(
      id: const Uuid().v4(),
      title: title,
      type: type,
      bytes: bytes,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      status: PrintJobStatus.pending,
      tableName: tableName,
      orderCode: orderCode,
      billCode: billCode,
    );

    _jobs.insert(0, job);
    await _saveToStorage();
    notifyListeners();

    return await _executeJob(job);
  }

  /// Thực thi gửi lệnh in ra máy in Bluetooth
  Future<bool> _executeJob(PrintJob job) async {
    job.status = PrintJobStatus.printing;
    notifyListeners();

    try {
      final bt = BluetoothPrinterService.instance;
      final success = await bt.printBytes(job.bytes);

      if (success) {
        job.status = PrintJobStatus.success;
        job.errorMessage = null;
        await _saveToStorage();
        notifyListeners();
        return true;
      } else {
        job.status = PrintJobStatus.failed;
        job.retryCount++;
        job.errorMessage = bt.lastErrorMessage.isNotEmpty
            ? bt.lastErrorMessage
            : 'Máy in mất kết nối hoặc hết giấy. Vui lòng kiểm tra giấy in và kết nối thiết bị.';
        await _saveToStorage();
        notifyListeners();
        return false;
      }
    } catch (e) {
      job.status = PrintJobStatus.failed;
      job.retryCount++;
      job.errorMessage = 'Lỗi gửi dữ liệu in: $e';
      await _saveToStorage();
      notifyListeners();
      return false;
    }
  }

  /// In lại một phiếu cụ thể trong hàng đợi
  Future<bool> retryJob(String jobId) async {
    final index = _jobs.indexWhere((j) => j.id == jobId);
    if (index == -1) return false;
    final job = _jobs[index];
    return await _executeJob(job);
  }

  /// In lại tất cả các phiếu đang bị lỗi trong hàng đợi
  Future<int> retryAllFailed() async {
    if (_isProcessing) return 0;
    _isProcessing = true;
    notifyListeners();

    int successCount = 0;
    final failedList = List<PrintJob>.from(failedJobs);

    for (final job in failedList) {
      final ok = await _executeJob(job);
      if (ok) {
        successCount++;
      } else {
        // Nếu in tiếp tục lỗi do mất kết nối, dừng lại tránh spam
        final isConnected = await BluetoothPrinterService.instance.isConnected();
        if (!isConnected) break;
      }
    }

    _isProcessing = false;
    notifyListeners();
    return successCount;
  }

  /// Xóa một phiếu khỏi hàng đợi (thu ngân chủ động hủy bỏ)
  Future<void> removeJob(String jobId) async {
    _jobs.removeWhere((j) => j.id == jobId);
    await _saveToStorage();
    notifyListeners();
  }

  /// Dọn dẹp các phiếu đã in thành công
  Future<void> clearCompletedJobs() async {
    _jobs.removeWhere((j) => j.status == PrintJobStatus.success);
    await _saveToStorage();
    notifyListeners();
  }

  /// Xóa toàn bộ hàng đợi
  Future<void> clearAll() async {
    _jobs.clear();
    await _saveToStorage();
    notifyListeners();
  }
}
