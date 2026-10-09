// lib/features/printer/printer_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/printer/bluetooth_printer_service.dart';
import '../../core/printer/print_queue_service.dart';
import '../../core/printer/printer_types.dart';
import '../../core/printer/receipt_printer.dart';

/// Màn hình Cài Đặt Máy In Bluetooth & LAN (POS Trạm)
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

  List<PrinterDevice> _devices = [];
  bool _isScanning = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _btService.addListener(_onServiceChanged);
    _queueService.addListener(_onServiceChanged);
    _initData();
  }

  @override
  void dispose() {
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
    await _checkStatusAndScan();
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
            backgroundColor: TramColors.warning,
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
          backgroundColor: TramColors.success,
        ),
      );
      _startScan();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_btService.lastErrorMessage.isNotEmpty
              ? _btService.lastErrorMessage
              : 'Không thể kết nối với máy in.'),
          backgroundColor: TramColors.danger,
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isKitchen ? 'Đang gửi lệnh in thử phiếu bếp...' : 'Đang gửi lệnh in thử hóa đơn...'),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final bytes = ReceiptPrinter.buildTestReceiptBytes(
        storeName: 'POS Trạm - Coffee & Tea',
        paperSize: _btService.paperSize,
        isKitchen: isKitchen,
      );

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
            backgroundColor: TramColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_btService.lastErrorMessage.isNotEmpty
                ? _btService.lastErrorMessage
                : 'Máy in mất kết nối hoặc hết giấy. Vui lòng kiểm tra giấy in và kết nối thiết bị.'),
            backgroundColor: TramColors.danger,
            duration: const Duration(seconds: 4),
          ),
        );
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
          backgroundColor: TramColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_btService.lastErrorMessage.isNotEmpty
              ? _btService.lastErrorMessage
              : 'Máy in mất kết nối hoặc hết giấy.'),
          backgroundColor: TramColors.danger,
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
          backgroundColor: TramColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể in lại. Vui lòng kiểm tra nguồn và giấy máy in.'),
          backgroundColor: TramColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _btService.isConnectedState;
    final failedCount = _queueService.failedCount;

    return Scaffold(
      backgroundColor: TramColors.background,
      appBar: AppBar(
        title: Text(
          'Cài Đặt Máy In',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: TramColors.surface,
        foregroundColor: TramColors.textPrimary, // nền sáng => icon/chữ tối (tránh trắng trên nền kem)
        elevation: 0.5,
        actions: [
          if (failedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Badge(
                  label: Text('$failedCount'),
                  backgroundColor: TramColors.danger,
                  child: IconButton(
                    tooltip: 'Phiếu in lỗi chờ in lại',
                    icon: const Icon(Icons.print_disabled, color: TramColors.danger),
                    onPressed: () {
                      _showQueueBottomSheet();
                    },
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Quét lại thiết bị',
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: TramColors.brandPrimary),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _startScan,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Thẻ trạng thái kết nối
            _buildStatusCard(isConnected),
            const SizedBox(height: 16),

            // 2. Cấu hình khổ giấy
            _buildPaperSizeCard(),
            const SizedBox(height: 16),

            // 3. Cấu hình chế độ chữ tiếng Việt
            _buildEncodingCard(),
            const SizedBox(height: 16),

            // 4. Thử nghiệm in
            _buildTestPrintCard(isConnected),
            const SizedBox(height: 16),

            // 5. Danh sách máy in quét được
            _buildDeviceListCard(isConnected),
            const SizedBox(height: 16),

            // 6. Hàng đợi in lại (Print Queue)
            _buildQueueOverviewCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

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
                    color: (isConnected ? TramColors.success : TramColors.warning).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isConnected ? Icons.print : Icons.print_disabled,
                    color: isConnected ? TramColors.success : TramColors.warning,
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
                          color: isConnected ? TramColors.success : TramColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        savedName,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: TramColors.textPrimary,
                        ),
                      ),
                      if (savedMac.isNotEmpty)
                        Text(
                          'MAC: $savedMac',
                          style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (isConnected)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TramColors.danger,
                      side: const BorderSide(color: TramColors.danger),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: _disconnectDevice,
                    child: const Text('Ngắt kết nối'),
                  )
                else if (savedMac.isNotEmpty)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TramColors.brandPrimary,
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
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
              ),
              value: _btService.autoReconnectEnabled,
              activeThumbColor: TramColors.brandPrimary,
              onChanged: (val) => _btService.setAutoReconnect(val),
            ),
          ],
        ),
      ),
    );
  }

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
                const Icon(Icons.receipt, color: TramColors.brandPrimary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Khổ Giấy In Nhiệt',
                  style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Chọn đúng khổ giấy để hóa đơn được căn lề chuẩn và không bị tràn ký tự',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
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
                            ? TramColors.brandPrimary.withValues(alpha: 0.1)
                            : TramColors.surface,
                        border: Border.all(
                          color: currentSize == PrinterPaperSize.mm58
                              ? TramColors.brandPrimary
                              : Colors.grey.shade300,
                          width: currentSize == PrinterPaperSize.mm58 ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_outlined,
                            color: currentSize == PrinterPaperSize.mm58
                                ? TramColors.brandPrimary
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Khổ 58mm',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: currentSize == PrinterPaperSize.mm58
                                  ? TramColors.brandPrimary
                                  : TramColors.textPrimary,
                            ),
                          ),
                          Text(
                            '32 ký tự / dòng (Mini/Cầm tay)',
                            style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary),
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
                            ? TramColors.brandPrimary.withValues(alpha: 0.1)
                            : TramColors.surface,
                        border: Border.all(
                          color: currentSize == PrinterPaperSize.mm80
                              ? TramColors.brandPrimary
                              : Colors.grey.shade300,
                          width: currentSize == PrinterPaperSize.mm80 ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            color: currentSize == PrinterPaperSize.mm80
                                ? TramColors.brandPrimary
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Khổ 80mm',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: currentSize == PrinterPaperSize.mm80
                                  ? TramColors.brandPrimary
                                  : TramColors.textPrimary,
                            ),
                          ),
                          Text(
                            '48 ký tự / dòng (Máy thu ngân)',
                            style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary),
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
                const Icon(Icons.text_fields, color: TramColors.brandPrimary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Hỗ Trợ Tiếng Việt Có Dấu',
                  style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Máy in không hỗ trợ bảng mã tiếng Việt có thể chọn chế độ Đồ Họa Raster để in chữ có dấu sắc nét',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
            ),
            const SizedBox(height: 10),
            RadioListTile<PrinterTextEncoding>(
              contentPadding: EdgeInsets.zero,
              title: Text('Không dấu (ESC/POS chuẩn)', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Tốc độ in nhanh nhất, loại bỏ dấu tiếng Việt, tương thích mọi máy in nhiệt', style: GoogleFonts.beVietnamPro(fontSize: 11)),
              value: PrinterTextEncoding.vietnameseAscii,
              groupValue: currentEnc,
              activeColor: TramColors.brandPrimary,
              onChanged: (val) => val != null ? _btService.setEncoding(val) : null,
            ),
            RadioListTile<PrinterTextEncoding>(
              contentPadding: EdgeInsets.zero,
              title: Text('UTF-8 Trực tiếp', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Gửi mã UTF-8 có dấu (chỉ dành cho máy in hỗ trợ nạp font tiếng Việt)', style: GoogleFonts.beVietnamPro(fontSize: 11)),
              value: PrinterTextEncoding.utf8Direct,
              groupValue: currentEnc,
              activeColor: TramColors.brandPrimary,
              onChanged: (val) => val != null ? _btService.setEncoding(val) : null,
            ),
            RadioListTile<PrinterTextEncoding>(
              contentPadding: EdgeInsets.zero,
              title: Text('Đồ họa Raster Bitmap (Có dấu 100%)', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Chuyển toàn bộ phiếu sang hình ảnh đơn sắc, in rõ ràng mọi dấu tiếng Việt', style: GoogleFonts.beVietnamPro(fontSize: 11)),
              value: PrinterTextEncoding.rasterImage,
              groupValue: currentEnc,
              activeColor: TramColors.brandPrimary,
              onChanged: (val) => val != null ? _btService.setEncoding(val) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestPrintCard(bool isConnected) {
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
                const Icon(Icons.print_outlined, color: TramColors.brandPrimary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'In Thử Nghiệm (Test Print)',
                  style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Kiểm tra kết nối và thẩm mỹ của bản in trước khi phục vụ khách',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TramColors.brandPrimary,
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
                      foregroundColor: TramColors.brandPrimary,
                      side: const BorderSide(color: TramColors.brandPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: TramColors.brandPrimary))
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bluetooth_searching, color: TramColors.brandPrimary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Máy In Bluetooth Gần Đây',
                      style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('Quét lại'),
                ),
              ],
            ),
            if (_isScanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2, color: TramColors.brandPrimary),
                      SizedBox(height: 10),
                      Text('Đang quét các thiết bị Bluetooth ở gần...'),
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
                      Icon(Icons.bluetooth_disabled, color: Colors.grey.shade400, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        'Chưa tìm thấy máy in Bluetooth nào.',
                        style: GoogleFonts.beVietnamPro(color: TramColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hãy bật Bluetooth của thiết bị và bật nguồn máy in nhiệt.',
                        style: GoogleFonts.beVietnamPro(color: Colors.grey.shade500, fontSize: 11),
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
                      color: isCurrent && isConnected ? TramColors.success : Colors.grey.shade600,
                    ),
                    title: Text(
                      dev.name,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        color: isCurrent && isConnected ? TramColors.success : TramColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      dev.macAddress,
                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                    ),
                    trailing: isCurrent && isConnected
                        ? const Chip(
                            label: Text('Đang dùng', style: TextStyle(color: Colors.white, fontSize: 11)),
                            backgroundColor: TramColors.success,
                            visualDensity: VisualDensity.compact,
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TramColors.brandPrimary,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.queue, color: TramColors.brandPrimary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Hàng Đợi In Lại (Print Queue)',
                      style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (failedCount > 0)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TramColors.danger,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.replay, size: 14),
                    label: Text('In lại tất cả ($failedCount)'),
                    onPressed: _retryAllFailed,
                  )
                else
                  TextButton(
                    onPressed: _showQueueBottomSheet,
                    child: const Text('Xem tất cả'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Nếu máy in mất kết nối hoặc hết giấy, các phiếu sẽ được bảo lưu tại đây và không bị mất dữ liệu.',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    'Hàng đợi đang trống. Các lệnh in hoàn tất sẽ tự xóa.',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey.shade500),
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
        statusColor = TramColors.success;
        break;
      case PrintJobStatus.failed:
        statusColor = TramColors.danger;
        break;
      case PrintJobStatus.printing:
        statusColor = TramColors.brandPrimary;
        break;
      case PrintJobStatus.pending:
        statusColor = TramColors.warning;
        break;
    }

    final timeStr = DateFormat('HH:mm:ss dd/MM').format(DateTime.fromMillisecondsSinceEpoch(job.createdAt));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: TramColors.surface,
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
                  style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary),
                ),
                if (job.errorMessage != null && job.status == PrintJobStatus.failed)
                  Text(
                    job.errorMessage!,
                    style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.danger),
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
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: TramColors.brandPrimary),
              tooltip: 'In lại phiếu này',
              onPressed: () => _retryJob(job),
            ),
          ],
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
                                backgroundColor: TramColors.danger,
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
                            icon: const Icon(Icons.delete_sweep, color: Colors.grey),
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
                              color: TramColors.danger,
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
