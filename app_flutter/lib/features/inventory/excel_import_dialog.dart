import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/inventory_models.dart';
import '../../data/services/inventory_service.dart';
import '../../data/services/firebase_service.dart';
import 'inventory_excel_service.dart';

class ExcelImportDialog extends StatefulWidget {
  final List<CatalogItemModel> existingItems;
  final VoidCallback? onImportCompleted;

  const ExcelImportDialog({
    super.key,
    required this.existingItems,
    this.onImportCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required List<CatalogItemModel> existingItems,
    VoidCallback? onImportCompleted,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExcelImportDialog(
        existingItems: existingItems,
        onImportCompleted: onImportCompleted,
      ),
    );
  }

  @override
  State<ExcelImportDialog> createState() => _ExcelImportDialogState();
}

class _ExcelImportDialogState extends State<ExcelImportDialog> {
  final _inventoryService = InventoryService();
  final _firebaseService = FirebaseService();

  int _currentStep = 1; // 1: Cấu hình, 2: Chọn file & xem trước

  // Cấu hình import (Khớp 100% với modal hình ảnh)
  bool _updateStockBalance = false; // Cập nhật giá trị tồn kho? (Mặc định: Không)
  String _duplicateSkuOption = 'error'; // 'error': Báo lỗi và dừng, 'replace': Thay thế tên hàng cũ
  String _scopeOption = 'all'; // 'all': Toàn hệ thống, 'branch': Theo chi nhánh

  // Trạng thái file & dữ liệu parse
  PlatformFile? _pickedFile;
  bool _isParsing = false;
  String? _parseError;
  List<ParsedInventoryItem> _parsedRows = [];
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: AppColors.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _currentStep == 1 ? _buildStep1Config() : _buildStep2UploadAndPreview(),
            ),
            const Divider(height: 1, color: AppColors.border),
            _buildFooterActions(),
          ],
        ),
      ),
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.table_view_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thêm hàng hóa từ file Excel',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentStep == 1
                      ? 'Bước 1/2: Thiết lập cấu hình nhập dữ liệu'
                      : 'Bước 2/2: Chọn file Excel & kiểm tra dữ liệu',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
            tooltip: 'Đóng',
          ),
        ],
      ),
    );
  }

  // ==================== BƯỚC 1: CẤU HÌNH (GIAO DIỆN THEO HÌNH ẢNH) ====================
  Widget _buildStep1Config() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Cập nhật giá trị tồn kho?
          _buildSectionTitle('1. Cập nhật giá trị tồn kho?'),
          Row(
            children: [
              Expanded(
                child: RadioListTile<bool>(
                  title: const Text('Không'),
                  value: false,
                  groupValue: _updateStockBalance,
                  activeColor: AppColors.primary,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _updateStockBalance = val ?? false),
                ),
              ),
              Expanded(
                child: RadioListTile<bool>(
                  title: const Text('Có'),
                  value: true,
                  groupValue: _updateStockBalance,
                  activeColor: AppColors.primary,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _updateStockBalance = val ?? true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Xử lý trùng mã hàng, khác tên hàng?
          _buildSectionTitle('2. Xử lý trùng mã hàng, khác tên hàng?'),
          RadioListTile<String>(
            title: const Text('Báo lỗi và dừng import'),
            value: 'error',
            groupValue: _duplicateSkuOption,
            activeColor: AppColors.primary,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _duplicateSkuOption = val ?? 'error'),
          ),
          RadioListTile<String>(
            title: const Text('Thay thế tên hàng cũ bằng tên hàng mới'),
            value: 'replace',
            groupValue: _duplicateSkuOption,
            activeColor: AppColors.primary,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _duplicateSkuOption = val ?? 'replace'),
          ),
          const SizedBox(height: 16),

          // 3. Phạm vi áp dụng trạng thái kinh doanh:
          _buildSectionTitle('3. Phạm vi áp dụng trạng thái kinh doanh:'),
          RadioListTile<String>(
            title: const Text('Toàn hệ thống'),
            value: 'all',
            groupValue: _scopeOption,
            activeColor: AppColors.primary,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _scopeOption = val ?? 'all'),
          ),
          RadioListTile<String>(
            title: const Text('Theo chi nhánh'),
            value: 'branch',
            groupValue: _scopeOption,
            activeColor: AppColors.primary,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _scopeOption = val ?? 'branch'),
          ),
          const SizedBox(height: 20),

          // Khung Lưu ý chuẩn
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Lưu ý',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildBulletPoint('Hệ thống cho phép nhập tối đa 500 mặt hàng mỗi lần.'),
                _buildBulletPoint('Các trường: Nhóm quản lý, Tên hàng, ĐVT là bắt buộc.'),
                _buildBulletPoint('Nếu không nhập mã hàng, hệ thống sẽ tự động sinh mã theo quy tắc SP00000x.'),
                _buildBulletPoint('Định dạng file tải lên phải là .xlsx hoặc .xls.'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Link tải file mẫu
          InkWell(
            onTap: _downloadTemplate,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.download_for_offline_outlined, color: AppColors.managerAccent, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'Chưa có file mẫu? Tải ngay file mẫu Excel',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.managerAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.beVietnamPro(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                color: const Color(0xFF78350F),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BƯỚC 2: CHỌN FILE & XEM TRƯỚC ====================
  Widget _buildStep2UploadAndPreview() {
    return Column(
      children: [
        // File selection banner
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface.withAlpha(120),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pickedFile != null ? 'Tệp đã chọn: ${_pickedFile!.name}' : 'Chưa chọn tệp dữ liệu',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_pickedFile != null)
                      Text(
                        'Kích thước: ${(_pickedFile!.size / 1024).toStringAsFixed(1)} KB',
                        style: GoogleFonts.beVietnamPro(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _pickAndParseFile,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: Text(_pickedFile == null ? 'Chọn file Excel' : 'Đổi file khác'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  textStyle: GoogleFonts.beVietnamPro(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // Main preview body
        Expanded(
          child: _isParsing
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Đang phân tích cấu trúc file Excel...'),
                    ],
                  ),
                )
              : _parseError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'Lỗi khi đọc file',
                              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _parseError!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _pickAndParseFile,
                              child: const Text('Chọn file khác'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _parsedRows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.cloud_upload_outlined, size: 64, color: AppColors.border),
                                const SizedBox(height: 16),
                                Text(
                                  'Chưa có dữ liệu để xem trước',
                                  style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Vui lòng bấm nút "Chọn file Excel" để tải lên file .xlsx chứa 21 cột tiêu chuẩn',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.beVietnamPro(fontSize: 12.5, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildParsedTable(),
        ),
      ],
    );
  }

  Widget _buildParsedTable() {
    final validCount = _parsedRows.where((r) => r.isValid).length;
    final invalidCount = _parsedRows.where((r) => !r.isValid).length;

    return Column(
      children: [
        // Summary Chips Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.card,
          child: Row(
            children: [
              _buildCountBadge('Tổng số', _parsedRows.length, Colors.blueGrey),
              const SizedBox(width: 8),
              _buildCountBadge('Hợp lệ', validCount, const Color(0xFF146A65)),
              const SizedBox(width: 8),
              if (invalidCount > 0)
                _buildCountBadge('Lỗi / Trùng', invalidCount, AppColors.danger),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        // List of items
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _parsedRows.length,
            itemBuilder: (context, index) {
              final row = _parsedRows[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: row.isValid ? AppColors.surface.withAlpha(60) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: row.isValid ? AppColors.border : const Color(0xFFFCA5A5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Số thứ tự
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: row.isValid ? AppColors.primary.withAlpha(20) : AppColors.danger.withAlpha(20),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${row.index}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: row.isValid ? AppColors.primary : AppColors.danger,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Thông tin chính
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.name,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: row.isValid ? const Color(0xFFE6F4F2) : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  row.statusMessage,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: row.isValid ? const Color(0xFF146A65) : AppColors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Mã: ${row.sku}',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              Text(
                                'ĐVT: ${row.baseUnitId}',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              Text(
                                'Giá vốn: ${FormatUtils.currency(row.costPrice)}',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              if (_updateStockBalance)
                                Text(
                                  'Tồn: ${row.onHandQty}',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              Text(
                                'Nhóm: ${row.managementGroup}',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
          ),
          Text(
            '$count',
            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  // ==================== FOOTER ACTIONS ====================
  Widget _buildFooterActions() {
    final validCount = _parsedRows.where((r) => r.isValid).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: AppColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep == 1) ...[
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text('Bỏ qua', style: GoogleFonts.beVietnamPro(color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => setState(() => _currentStep = 2),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(
                'Tiếp tục',
                style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
              ),
            ),
          ] else ...[
            OutlinedButton(
              onPressed: _isImporting ? null : () => setState(() => _currentStep = 1),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: Text('Quay lại', style: GoogleFonts.beVietnamPro(color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: (_isImporting || validCount == 0) ? null : _executeImport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Nhập vào kho ($validCount)',
                      style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== HÀM XỬ LÝ NGHIỆP VỤ ====================

  /// Tải file mẫu
  Future<void> _downloadTemplate() async {
    try {
      final path = await InventoryExcelService.downloadSampleTemplate();
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tạo và mở file mẫu Excel thành công!'),
            backgroundColor: Color(0xFF146A65),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải file mẫu: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// Chọn file Excel từ thiết bị và phân tích
  Future<void> _pickAndParseFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() {
        _pickedFile = file;
        _isParsing = true;
        _parseError = null;
        _parsedRows = [];
      });

      var bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null) {
        throw Exception('Không đọc được dữ liệu nhị phân từ file đã chọn');
      }

      final parsed = InventoryExcelService.parseExcelBytes(
        bytes: bytes,
        existingItems: widget.existingItems,
        duplicateSkuOption: _duplicateSkuOption,
      );

      setState(() {
        _parsedRows = parsed;
        _isParsing = false;
      });
    } catch (e) {
      setState(() {
        _parseError = e.toString();
        _isParsing = false;
      });
    }
  }

  /// Thực hiện lưu dữ liệu vào Firebase Realtime Database
  Future<void> _executeImport() async {
    final validRows = _parsedRows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Xác định danh sách chi nhánh cần áp dụng
      List<String> targetBranches = [];
      if (_scopeOption == 'all') {
        final allStores = await _firebaseService.getAllStores();
        targetBranches = allStores.map((s) => s.storeCode).toList();
      } else {
        targetBranches = [_inventoryService.currentStoreCode];
      }

      // Không có chi nhánh hợp lệ -> dừng lại, không ghi mặc định vào chi nhánh khác
      targetBranches = targetBranches.where((c) => c.trim().isNotEmpty).toList();
      if (targetBranches.isEmpty) {
        throw Exception('Không xác định được chi nhánh hiện tại để nhập kho');
      }

      for (final branch in targetBranches) {
        for (final r in validRows) {
          final existingItem = widget.existingItems.cast<CatalogItemModel?>().firstWhere(
            (ci) => ci?.sku?.toLowerCase() == r.sku.toLowerCase(),
            orElse: () => null,
          );

          final itemId = existingItem?.itemId ?? _inventoryService.generateItemId();

          final item = CatalogItemModel(
            itemId: itemId,
            sku: r.sku,
            name: r.name,
            kind: r.kind,
            managementGroup: r.category.isNotEmpty ? r.category : r.managementGroup,
            groupIds: r.category.isNotEmpty ? [r.category] : [],
            baseUnitId: r.baseUnitId,
            conversionRate: r.conversionRate,
            trackStock: r.trackStock,
            costPrice: r.costPrice,
            minStock: r.minStock,
            maxStock: r.maxStock,
            status: r.status,
            description: r.description,
            imageUrl: r.imageUrl.isNotEmpty ? r.imageUrl : null,
            weight: r.weight,
            weightUnit: r.weightUnit.isNotEmpty ? r.weightUnit : null,
            location: r.location.isNotEmpty ? r.location : null,
            brand: r.brand.isNotEmpty ? r.brand : null,
            createdAt: existingItem?.createdAt ?? now,
            updatedAt: now,
          );

          await _inventoryService.saveCatalogItemToBranch(branch, item);

          // Cập nhật tồn kho nếu người dùng chọn "Có"
          if (_updateStockBalance && r.trackStock) {
            final balanceId = '${branch}_$itemId';
            final balance = StockBalanceModel(
              balanceId: balanceId,
              branchId: branch,
              itemId: itemId,
              onHandQty: r.onHandQty,
              reservedQty: 0,
              inventoryValue: r.onHandQty * r.costPrice,
              averageCostScaled: r.costPrice * 100,
              lastEventSeq: 0,
              updatedAt: now,
            );
            await _inventoryService.saveStockBalanceToBranch(branch, balance);
          }
        }
      }

      if (mounted) {
        widget.onImportCompleted?.call();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã nhập thành công ${validRows.length} mặt hàng vào kho!'),
            backgroundColor: const Color(0xFF146A65),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi lưu dữ liệu vào kho: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }
}
