// lib/features/printer/printer_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/theme_mode_selector.dart';
import '../../core/printer/bluetooth_printer_service.dart';
import '../../core/printer/print_queue_service.dart';
import '../../core/printer/printer_types.dart';
import '../../core/printer/receipt_printer.dart';
import '../../core/services/auth_service.dart';
import '../../data/services/firebase_service.dart';
import '../../data/models/store_info_model.dart';

/// Màn hình Cài Đặt Máy In Mạng LAN & Bluetooth (POS Trạm)
class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  /// Tiện ích mở màn hình từ bất kỳ vị trí nào
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
    );
  }

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final BluetoothPrinterService _btService = BluetoothPrinterService.instance;
  final PrintQueueService _queueService = PrintQueueService.instance;
  final AuthService _auth = AuthService();
  final FirebaseService _fb = FirebaseService();

  // Trạng thái cấu hình máy in
  String _printerType = 'LAN'; // 'LAN' hoặc 'BLUETOOTH'
  bool get _isLanMode => _printerType == 'LAN';

  // Cấu hình máy in LAN
  late final TextEditingController _billIpController;
  late final TextEditingController _kitchenIpController;
  bool _autoPrintBill = true;
  bool _isLoadingStore = false;
  bool _isSavingLan = false;
  StoreInfoModel? _storeInfo;

  // Kiểm tra kết nối IP
  bool _isTestingBillIp = false;
  bool? _billIpTestSuccess;
  bool _isTestingKitchenIp = false;
  bool? _kitchenIpTestSuccess;

  // Cấu hình Bluetooth
  List<PrinterDevice> _devices = [];
  bool _isScanning = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _billIpController = TextEditingController(text: '192.168.1.201');
    _kitchenIpController = TextEditingController(text: '192.168.1.200');

    _btService.addListener(_onServiceChanged);
    _queueService.addListener(_onServiceChanged);
    _initData();
  }

  @override
  void dispose() {
    _billIpController.dispose();
    _kitchenIpController.dispose();
    _btService.removeListener(_onServiceChanged);
    _queueService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initData() async {
    await _btService.init();
    await _queueService.init();
    await _loadStoreConfig();

    if (!_isLanMode) {
      await _checkStatusAndScan();
    }
  }

  Future<void> _loadStoreConfig() async {
    setState(() => _isLoadingStore = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final localType = prefs.getString('tram_pos_printer_type');
      final localBillIp = prefs.getString('tram_pos_lan_bill_printer_ip');
      final localKitchenIp = prefs.getString('tram_pos_lan_kitchen_printer_ip');
      final localAutoPrint = prefs.getBool('tram_pos_auto_print_bill');

      final store = _auth.currentStoreInfo ?? await _fb.getStoreInfo();
      _storeInfo = store;

      _printerType = localType ?? store.printerType;
      if (localBillIp != null && localBillIp.trim().isNotEmpty) {
        _billIpController.text = localBillIp.trim();
      } else if (store.billPrinterIp.isNotEmpty) {
        _billIpController.text = store.billPrinterIp.trim();
      }

      if (localKitchenIp != null && localKitchenIp.trim().isNotEmpty) {
        _kitchenIpController.text = localKitchenIp.trim();
      } else if (store.kitchenPrinterIp.isNotEmpty) {
        _kitchenIpController.text = store.kitchenPrinterIp.trim();
      }

      _autoPrintBill = localAutoPrint ?? store.autoPrintBill;
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingStore = false);
    }
  }

  Future<void> _setPrinterType(String type) async {
    if (_printerType == type) return;
    setState(() => _printerType = type);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tram_pos_printer_type', type);

    if (type == 'BLUETOOTH') {
      _checkStatusAndScan();
    }
  }

  Future<void> _testLanIp(String ip, {required bool isKitchen}) async {
    final cleanIp = ip.trim();
    if (cleanIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isKitchen ? 'Vui lòng nhập IP máy in bếp' : 'Vui lòng nhập IP máy in hóa đơn'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      if (isKitchen) {
        _isTestingKitchenIp = true;
        _kitchenIpTestSuccess = null;
      } else {
        _isTestingBillIp = true;
        _billIpTestSuccess = null;
      }
    });

    final ok = await ReceiptPrinter.testLanConnection(printerIp: cleanIp);

    if (!mounted) return;
    setState(() {
      if (isKitchen) {
        _isTestingKitchenIp = false;
        _kitchenIpTestSuccess = ok;
      } else {
        _isTestingBillIp = false;
        _billIpTestSuccess = ok;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Kết nối thành công tới $cleanIp:9100! Máy in đang online.'
            : 'Không thể kết nối tới $cleanIp:9100. Hãy kiểm tra máy in và mạng Wi-Fi.'),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _saveLanConfig() async {
    if (_isSavingLan) return;
    setState(() => _isSavingLan = true);

    try {
      final billIp = _billIpController.text.trim();
      final kitchenIp = _kitchenIpController.text.trim();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tram_pos_printer_type', 'LAN');
      await prefs.setString('tram_pos_lan_bill_printer_ip', billIp);
      await prefs.setString('tram_pos_lan_kitchen_printer_ip', kitchenIp);
      await prefs.setBool('tram_pos_auto_print_bill', _autoPrintBill);

      // Cập nhật cấu hình lên Firebase cho chi nhánh nếu có quyền
      if (_storeInfo != null) {
        final updated = _storeInfo!.copyWith(
          printerType: 'LAN',
          billPrinterIp: billIp.isNotEmpty ? billIp : _storeInfo!.billPrinterIp,
          kitchenPrinterIp: kitchenIp.isNotEmpty ? kitchenIp : _storeInfo!.kitchenPrinterIp,
          autoPrintBill: _autoPrintBill,
        );
        try {
          await _fb.saveStoreInfo(updated);
          await _auth.refreshRolesAndStoreInfo();
          _storeInfo = updated;
        } catch (_) {
          // Bỏ qua nếu là tài khoản nhân viên không có quyền ghi storeInfo
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu cấu hình máy in LAN thành công!'),
          backgroundColor: AppColors.success,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingLan = false);
    }
  }

  Future<void> _checkStatusAndScan() async {
    await _btService.checkConnectionStatus();
    _startScan();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    final results = await _btService.scanPrinters();
    if (mounted) {
      setState(() {
        _devices = results;
        _isScanning = false;
      });
      if (_btService.lastErrorMessage.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_btService.lastErrorMessage),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _connectDevice(PrinterDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đang kết nối tới ${device.name}...'),
        duration: const Duration(seconds: 2),
      ),
    );
    final ok = await _btService.connect(device.macAddress, deviceName: device.name);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kết nối thành công với ${device.name}!'),
          backgroundColor: AppColors.success,
        ),
      );
      _startScan();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_btService.lastErrorMessage.isNotEmpty
              ? _btService.lastErrorMessage
              : 'Không thể kết nối với máy in.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _disconnectDevice() async {
    await _btService.disconnect();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã ngắt kết nối máy in.')),
      );
      _startScan();
    }
  }

  Future<void> _testPrint({required bool isKitchen}) async {
    if (_isTesting) return;
    setState(() => _isTesting = true);

    try {
      final bytes = ReceiptPrinter.buildTestReceiptBytes(
        storeName: _storeInfo?.storeName ?? 'POS Trạm - Coffee & Tea',
        paperSize: _btService.paperSize,
        isKitchen: isKitchen,
      );

      if (_isLanMode) {
        final ip = isKitchen ? _kitchenIpController.text.trim() : _billIpController.text.trim();
        if (ip.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isKitchen ? 'Vui lòng nhập IP máy in bếp để in thử.' : 'Vui lòng nhập IP máy in hóa đơn để in thử.'),
              backgroundColor: AppColors.warning,
            ),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đang gửi lệnh in thử tới $ip:9100...'),
            duration: const Duration(seconds: 1),
          ),
        );

        final ok = await ReceiptPrinter.printViaLan(printerIp: ip, data: bytes);
        if (!mounted) return;

        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('In thử thành công tới máy in LAN ($ip)!'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          await _queueService.enqueueAndPrint(
            title: isKitchen ? 'In thử Bếp (LAN)' : 'In thử Bill (LAN)',
            type: 'TEST',
            bytes: bytes,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không thể in tới máy in tại $ip:9100. Đã lưu vào Hàng đợi in lại.'),
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        // Bluetooth
        final isConnected = _btService.isConnectedState;
        if (!isConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Chưa kết nối máy in Bluetooth. Vui lòng kết nối thiết bị bên dưới.'),
              backgroundColor: AppColors.warning,
            ),
          );
          return;
        }

        final success = await _queueService.enqueueAndPrint(
          title: isKitchen ? 'In thử: Phiếu Bếp' : 'In thử: Hóa Đơn',
          type: 'TEST',
          bytes: bytes,
        );

        if (!mounted) return;
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isKitchen ? 'In thử phiếu bếp thành công!' : 'In thử hóa đơn thành công!'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_btService.lastErrorMessage.isNotEmpty
                  ? _btService.lastErrorMessage
                  : 'Máy in mất kết nối hoặc hết giấy. Phiếu đã lưu vào Hàng đợi.'),
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _retryJob(PrintJob job) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đang thử in lại: ${job.title}...'),
        duration: const Duration(seconds: 1),
      ),
    );
    final ok = await _queueService.retryJob(job.id);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('In lại ${job.title} thành công!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(job.errorMessage ?? 'Không thể in lại. Vui lòng kiểm tra nguồn và kết nối máy in.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _retryAllFailed() async {
    final count = await _queueService.retryAllFailed();
    if (!mounted) return;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã in lại thành công $count phiếu!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể in lại. Vui lòng kiểm tra nguồn và giấy máy in.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _btService.isConnectedState;
    final failedCount = _queueService.failedCount;

    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        title: Text(
          'Cài Đặt Máy In',
          style: GoogleFonts.beVietnamPro(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        backgroundColor: context.tc.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        elevation: 0.5,
        actions: [
          if (failedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Badge(
                  label: Text('$failedCount'),
                  backgroundColor: context.tc.danger,
                  child: IconButton(
                    tooltip: 'Phiếu in lỗi chờ in lại',
                    icon: const Icon(Icons.print_disabled, color: Colors.white),
                    onPressed: _showQueueBottomSheet,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: _isLanMode ? 'Tải lại cấu hình' : 'Quét lại thiết bị',
            icon: (_isScanning || _isLoadingStore)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: (_isScanning || _isLoadingStore)
                ? null
                : () => _isLanMode ? _loadStoreConfig() : _startScan(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _isLanMode ? _loadStoreConfig : _startScan,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Bộ chuyển đổi phương thức kết nối (Mạng LAN vs Bluetooth)
            _buildModeSelector(),
            const SizedBox(height: 16),

            // 2. Nội dung cấu hình theo chế độ
            if (_isLanMode) ...[
              _buildLanConfigCard(),
              const SizedBox(height: 16),
            ] else ...[
              _buildStatusCard(isConnected),
              const SizedBox(height: 16),
              _buildDeviceListCard(isConnected),
              const SizedBox(height: 16),
            ],

            // 3. Khổ giấy in nhiệt (Chung cho cả LAN và Bluetooth)
            _buildPaperSizeCard(),
            const SizedBox(height: 16),

            // 4. Cấu hình chế độ chữ tiếng Việt
            _buildEncodingCard(),
            const SizedBox(height: 16),

            // 5. Thử nghiệm in
            _buildTestPrintCard(isConnected),
            const SizedBox(height: 16),

            // 6. Hàng đợi in lại (Print Queue)
            _buildQueueOverviewCard(),
            const SizedBox(height: 16),

            // 7. Giao diện thiết bị (Sáng / Tối / Theo hệ thống)
            const ThemeModeCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 1. Bộ chọn chế độ kết nối (Segmented Control)
  Widget _buildModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: context.tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.tc.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _setPrinterType('LAN'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: _isLanMode ? context.tc.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lan_outlined,
                      size: 18,
                      color: _isLanMode ? Colors.white : context.tc.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Mạng LAN / Wi-Fi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _isLanMode ? Colors.white : context.tc.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: () => _setPrinterType('BLUETOOTH'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: !_isLanMode ? context.tc.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bluetooth,
                      size: 18,
                      color: !_isLanMode ? Colors.white : context.tc.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Bluetooth',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: !_isLanMode ? Colors.white : context.tc.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2A. Card Cấu hình Máy In Mạng LAN / Wi-Fi
  Widget _buildLanConfigCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.tc.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.router_outlined, color: context.tc.primary, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Máy In Mạng LAN (Ethernet / Wi-Fi)',
                        style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Kết nối trực tiếp qua địa chỉ IP nội bộ (Port 9100 standard)',
                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Mục 1: IP Máy in Hóa Đơn (Thu Ngân)
            Text(
              'IP Máy In Hóa Đơn (Thu Ngân)',
              style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _billIpController,
              keyboardType: TextInputType.text,
              style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.receipt_long, color: context.tc.primary, size: 20),
                hintText: 'VD: 192.168.1.201',
                hintStyle: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textHint),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(6),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 36),
                      side: BorderSide(color: context.tc.primary),
                      foregroundColor: context.tc.primary,
                    ),
                    onPressed: _isTestingBillIp ? null : () => _testLanIp(_billIpController.text, isKitchen: false),
                    child: _isTestingBillIp
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Kiểm tra', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
            if (_billIpTestSuccess != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    _billIpTestSuccess! ? Icons.check_circle : Icons.error,
                    size: 14,
                    color: _billIpTestSuccess! ? context.tc.success : context.tc.danger,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _billIpTestSuccess!
                          ? 'Máy in Hóa đơn đang phản hồi tốt (Port 9100 Online)'
                          : 'Không kết nối được tới IP máy in Hóa đơn.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: _billIpTestSuccess! ? context.tc.success : context.tc.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Mục 2: IP Máy in Bếp (Tùy chọn)
            Text(
              'IP Máy In Bếp / Pha Chế (Tùy chọn)',
              style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _kitchenIpController,
              keyboardType: TextInputType.text,
              style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.soup_kitchen, color: context.tc.primary, size: 20),
                hintText: 'VD: 192.168.1.200 (để trống nếu không dùng)',
                hintStyle: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textHint),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(6),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 36),
                      side: BorderSide(color: context.tc.primary),
                      foregroundColor: context.tc.primary,
                    ),
                    onPressed: _isTestingKitchenIp ? null : () => _testLanIp(_kitchenIpController.text, isKitchen: true),
                    child: _isTestingKitchenIp
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Kiểm tra', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
            if (_kitchenIpTestSuccess != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    _kitchenIpTestSuccess! ? Icons.check_circle : Icons.error,
                    size: 14,
                    color: _kitchenIpTestSuccess! ? context.tc.success : context.tc.danger,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _kitchenIpTestSuccess!
                          ? 'Máy in Bếp đang phản hồi tốt (Port 9100 Online)'
                          : 'Không kết nối được tới IP máy in Bếp.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: _kitchenIpTestSuccess! ? context.tc.success : context.tc.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Tự động in hóa đơn khi thanh toán
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Tự động in hóa đơn khi thanh toán',
                style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Tự gửi lệnh in tới máy in hóa đơn ngay sau khi hoàn tất thu tiền',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
              ),
              value: _autoPrintBill,
              onChanged: (val) => setState(() => _autoPrintBill = val),
            ),
            const SizedBox(height: 12),

            // Nút Lưu Cài Đặt LAN
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.tc.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isSavingLan
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 18),
                label: Text(
                  'Lưu Cài Đặt Máy In LAN',
                  style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSavingLan ? null : _saveLanConfig,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2B. Thẻ Trạng thái Bluetooth
  Widget _buildStatusCard(bool isConnected) {
    final savedName = _btService.savedName.isNotEmpty ? _btService.savedName : 'Chưa thiết lập';
    final savedMac = _btService.savedMac;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isConnected ? context.tc.success : context.tc.warning).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isConnected ? Icons.print : Icons.print_disabled,
                    color: isConnected ? context.tc.success : context.tc.warning,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected ? 'Đã Kết Nối Máy In' : 'Chưa Kết Nối Máy In',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isConnected ? context.tc.success : context.tc.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        savedName,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.tc.textPrimary,
                        ),
                      ),
                      if (savedMac.isNotEmpty)
                        Text(
                          'MAC: $savedMac',
                          style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (isConnected)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, AppSpacing.minTapTarget),
                      foregroundColor: context.tc.danger,
                      side: BorderSide(color: context.tc.danger),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: _disconnectDevice,
                    child: const Text('Ngắt kết nối'),
                  )
                else if (savedMac.isNotEmpty)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, AppSpacing.minTapTarget),
                      backgroundColor: context.tc.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () => _connectDevice(PrinterDevice(name: savedName, macAddress: savedMac)),
                    child: const Text('Kết nối lại'),
                  ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Tự động kết nối lại khi mở ứng dụng',
                style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'Tự phát hiện và kết nối lại máy in đã lưu mà không cần quét lại',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
              ),
              value: _btService.autoReconnectEnabled,
              onChanged: (val) => _btService.setAutoReconnect(val),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Cấu hình khổ giấy
  Widget _buildPaperSizeCard() {
    final currentSize = _btService.paperSize;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt, color: context.tc.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Khổ Giấy In Nhiệt',
                    style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Chọn đúng khổ giấy để hóa đơn được căn lề chuẩn và không bị tràn ký tự',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _btService.setPaperSize(PrinterPaperSize.mm58),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: currentSize == PrinterPaperSize.mm58
                            ? context.tc.primary.withValues(alpha: 0.1)
                            : context.tc.surface,
                        border: Border.all(
                          color: currentSize == PrinterPaperSize.mm58
                              ? context.tc.primary
                              : context.tc.border,
                          width: currentSize == PrinterPaperSize.mm58 ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_outlined,
                            color: currentSize == PrinterPaperSize.mm58
                                ? context.tc.primary
                                : context.tc.textSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Khổ 58mm',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: currentSize == PrinterPaperSize.mm58
                                  ? context.tc.primary
                                  : context.tc.textPrimary,
                            ),
                          ),
                          Text(
                            '32 ký tự / dòng (Mini/Cầm tay)',
                            style: GoogleFonts.beVietnamPro(fontSize: 10, color: context.tc.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _btService.setPaperSize(PrinterPaperSize.mm80),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: currentSize == PrinterPaperSize.mm80
                            ? context.tc.primary.withValues(alpha: 0.1)
                            : context.tc.surface,
                        border: Border.all(
                          color: currentSize == PrinterPaperSize.mm80
                              ? context.tc.primary
                              : context.tc.border,
                          width: currentSize == PrinterPaperSize.mm80 ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            color: currentSize == PrinterPaperSize.mm80
                                ? context.tc.primary
                                : context.tc.textSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Khổ 80mm',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: currentSize == PrinterPaperSize.mm80
                                  ? context.tc.primary
                                  : context.tc.textPrimary,
                            ),
                          ),
                          Text(
                            '48 ký tự / dòng (Máy thu ngân)',
                            style: GoogleFonts.beVietnamPro(fontSize: 10, color: context.tc.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 4. Cấu hình chữ tiếng Việt
  Widget _buildEncodingCard() {
    final currentEnc = _btService.encoding;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.text_fields, color: context.tc.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hỗ Trợ Tiếng Việt Có Dấu',
                    style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Máy in không hỗ trợ bảng mã tiếng Việt có thể chọn chế độ Đồ Họa Raster để in chữ có dấu sắc nét',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
            ),
            const SizedBox(height: 10),
            RadioGroup<PrinterTextEncoding>(
              groupValue: currentEnc,
              onChanged: (val) => val != null ? _btService.setEncoding(val) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<PrinterTextEncoding>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Không dấu (ESC/POS chuẩn)', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Tốc độ in nhanh nhất, loại bỏ dấu tiếng Việt, tương thích mọi máy in nhiệt', style: GoogleFonts.beVietnamPro(fontSize: 11)),
                    value: PrinterTextEncoding.vietnameseAscii,
                    activeColor: context.tc.primary,
                  ),
                  RadioListTile<PrinterTextEncoding>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('UTF-8 Trực tiếp', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Gửi mã UTF-8 có dấu (chỉ dành cho máy in hỗ trợ nạp font tiếng Việt)', style: GoogleFonts.beVietnamPro(fontSize: 11)),
                    value: PrinterTextEncoding.utf8Direct,
                    activeColor: context.tc.primary,
                  ),
                  RadioListTile<PrinterTextEncoding>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Đồ họa Raster Bitmap (Có dấu 100%)', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Chuyển toàn bộ phiếu sang hình ảnh đơn sắc, in rõ ràng mọi dấu tiếng Việt', style: GoogleFonts.beVietnamPro(fontSize: 11)),
                    value: PrinterTextEncoding.rasterImage,
                    activeColor: context.tc.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 5. Thử nghiệm in
  Widget _buildTestPrintCard(bool isConnected) {
    final activeTargetDesc = _isLanMode
        ? 'Mạng LAN (IP Bill: ${_billIpController.text.trim().isNotEmpty ? _billIpController.text.trim() : "Chưa đặt"})'
        : 'Bluetooth (${_btService.savedName.isNotEmpty ? _btService.savedName : "Chưa kết nối"})';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.print_outlined, color: context.tc.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'In Thử Nghiệm (Test Print)',
                    style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Đang gửi lệnh tới: $activeTargetDesc',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: context.tc.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.tc.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.receipt, size: 18),
                    label: Text(
                      'In Thử Hóa Đơn',
                      style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _isTesting ? null : () => _testPrint(isKitchen: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.tc.primary,
                      side: BorderSide(color: context.tc.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isTesting
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.tc.primary))
                        : const Icon(Icons.soup_kitchen, size: 18),
                    label: Text(
                      'In Thử Phiếu Bếp',
                      style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _isTesting ? null : () => _testPrint(isKitchen: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 2C. Danh sách máy in Bluetooth quét được
  Widget _buildDeviceListCard(bool isConnected) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth_searching, color: context.tc.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Máy In Bluetooth Gần Đây',
                    style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: _isScanning
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 16),
                  label: const Text('Quét lại'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isScanning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: context.tc.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Đang tìm kiếm máy in nhiệt Bluetooth...',
                        style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else if (_devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.bluetooth_disabled, color: context.tc.textHint, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        'Chưa tìm thấy máy in Bluetooth nào.',
                        style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hãy bật Bluetooth của thiết bị và bật nguồn máy in nhiệt.',
                        style: GoogleFonts.beVietnamPro(color: context.tc.textHint, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final dev = _devices[i];
                  final isCurrent = dev.isConnected || (dev.macAddress.toUpperCase() == _btService.savedMac.toUpperCase());

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.print,
                      color: isCurrent && isConnected ? context.tc.success : context.tc.textSecondary,
                    ),
                    title: Text(
                      dev.name,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        color: isCurrent && isConnected ? context.tc.success : context.tc.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      dev.macAddress,
                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                    ),
                    trailing: isCurrent && isConnected
                        ? Chip(
                            label: const Text('Đang dùng', style: TextStyle(color: Colors.white, fontSize: 11)),
                            backgroundColor: context.tc.success,
                            visualDensity: VisualDensity.compact,
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.tc.primary,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(64, 40),
                            ),
                            onPressed: () => _connectDevice(dev),
                            child: const Text('Kết nối'),
                          ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 6. Hàng đợi in lại (Print Queue Overview)
  Widget _buildQueueOverviewCard() {
    final jobs = _queueService.jobs;
    final failedCount = _queueService.failedCount;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.queue, color: context.tc.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hàng Đợi In Lại',
                    style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                if (failedCount > 0) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 34),
                      backgroundColor: context.tc.danger,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.replay, size: 14),
                    label: Text('In lại ($failedCount)'),
                    onPressed: _retryAllFailed,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_sweep, color: context.tc.danger, size: 20),
                    tooltip: 'Xóa phiếu lỗi',
                    onPressed: () async {
                      await _queueService.clearFailedJobs();
                      if (mounted) setState(() {});
                    },
                  ),
                ] else
                  TextButton(
                    onPressed: _showQueueBottomSheet,
                    child: const Text('Xem tất cả'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Nếu máy in mất kết nối hoặc hết giấy, các phiếu sẽ được bảo lưu tại đây và không bị mất dữ liệu.',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
            ),
            const SizedBox(height: 12),
            if (jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    'Hàng đợi đang trống. Các lệnh in hoàn tất sẽ tự xóa.',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textHint),
                  ),
                ),
              )
            else
              Column(
                children: jobs.take(3).map((job) => _buildJobItem(job)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobItem(PrintJob job) {
    Color statusColor;
    switch (job.status) {
      case PrintJobStatus.success:
        statusColor = context.tc.success;
        break;
      case PrintJobStatus.failed:
        statusColor = context.tc.danger;
        break;
      case PrintJobStatus.printing:
        statusColor = context.tc.primary;
        break;
      case PrintJobStatus.pending:
        statusColor = context.tc.warning;
        break;
    }

    final timeStr = DateFormat('HH:mm:ss dd/MM').format(DateTime.fromMillisecondsSinceEpoch(job.createdAt));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.tc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            job.type == 'KITCHEN' ? Icons.soup_kitchen : Icons.receipt_long,
            color: statusColor,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.title,
                  style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Thời gian: $timeStr • Thử lại: ${job.retryCount}',
                  style: GoogleFonts.beVietnamPro(fontSize: 10, color: context.tc.textSecondary),
                ),
                if (job.errorMessage != null && job.status == PrintJobStatus.failed)
                  Text(
                    job.errorMessage!,
                    style: GoogleFonts.beVietnamPro(fontSize: 10, color: context.tc.danger),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              job.status.label,
              style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
            ),
          ),
          if (job.status == PrintJobStatus.failed) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.refresh, size: 18, color: context.tc.primary),
              tooltip: 'In lại phiếu này',
              onPressed: () => _retryJob(job),
            ),
          ],
          IconButton(
            icon: Icon(Icons.close, size: 16, color: context.tc.textHint),
            tooltip: 'Xóa phiếu',
            onPressed: () => _queueService.removeJob(job.id),
          ),
        ],
      ),
    );
  }

  void _showQueueBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final allJobs = _queueService.jobs;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Danh Sách Hàng Đợi In (${allJobs.length})',
                        style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          if (_queueService.failedCount > 0)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(64, AppSpacing.minTapTarget),
                                backgroundColor: context.tc.danger,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                await _retryAllFailed();
                                setModalState(() {});
                              },
                              child: Text('In lại (${_queueService.failedCount})'),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.delete_sweep, color: context.tc.textHint),
                            tooltip: 'Dọn dẹp phiếu xong',
                            onPressed: () async {
                              await _queueService.clearCompletedJobs();
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(),
                  if (allJobs.isEmpty)
                    const Expanded(
                      child: Center(child: Text('Hàng đợi trống.')),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: allJobs.length,
                        itemBuilder: (_, i) {
                          final j = allJobs[i];
                          return Dismissible(
                            key: Key(j.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              color: context.tc.danger,
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) {
                              _queueService.removeJob(j.id);
                              setModalState(() {});
                            },
                            child: _buildJobItem(j),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
