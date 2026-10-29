// lib/features/crm/customer_management_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/reports/report_export_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/text_formatters.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import 'customer_delete_service.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  List<KmtCustomerModel> _customers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedTier = 'ALL';

  StoreInfoModel? _storeInfo;
  int _pointRedeemRate = 1000;
  double _pointEarnRate = 1.0;
  List<LoyaltyTier> _tiers = LoyaltyTier.defaults;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Quyền quản lý khách hàng (Thêm / Sửa thông tin)
  bool get _canManageCustomer => _auth.isOwner || _auth.isManager || _auth.can(AppPermissions.manageCustomers);

  /// Chỉ Chủ quán / Quản lý có quyền quản lý khách hàng mới được xóa khách
  bool get _canDeleteCustomer => (_auth.isOwner || _auth.isManager) && _auth.can(AppPermissions.manageCustomers);

  DateTime? _parseBirthday(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) {
      return DateTime.tryParse(t);
    }
    if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(t)) {
      final parts = t.split('/');
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return DateTime.tryParse(t);
  }

  String _formatBirthday(String raw) {
    final d = _parseBirthday(raw);
    if (d != null) {
      return DateFormat('dd/MM/yyyy').format(d);
    }
    return raw.trim();
  }

  Future<void> _showAddOrEditCustomerDialog({KmtCustomerModel? customer}) async {
    final isEditing = customer != null;
    final nameCtrl = TextEditingController(text: customer?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    String gender = (customer?.gender.isNotEmpty ?? false) ? customer!.gender : 'Khác';
    if (!['Nam', 'Nữ', 'Khác'].contains(gender)) {
      gender = 'Khác';
    }

    DateTime? birthday = customer != null ? _parseBirthday(customer.birthday) : null;
    final bdayCtrl = TextEditingController(
      text: birthday != null ? DateFormat('dd/MM/yyyy').format(birthday) : '',
    );
    String? formError;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isEditing ? Icons.edit_outlined : Icons.person_add_outlined,
                color: context.tc.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEditing ? 'Chỉnh Sửa Khách Hàng' : 'Thêm Khách Hàng Mới',
                  style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (formError != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formError!,
                              style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isEditing) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: context.tc.cardElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.tc.borderLight),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Mã: ${customer.code}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.tc.textSecondary)),
                          Text('${customer.currentPoints} pt (${customer.tierName(_tiers)})', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: context.ink(Colors.blue.shade800))),
                        ],
                      ),
                    ),
                  ],
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (formError != null) setDialogState(() => formError = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại *',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (formError != null) setDialogState(() => formError = null);
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Giới tính',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.tc.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Nam', label: Text('Nam'), icon: Icon(Icons.male, size: 16)),
                        ButtonSegment(value: 'Nữ', label: Text('Nữ'), icon: Icon(Icons.female, size: 16)),
                        ButtonSegment(value: 'Khác', label: Text('Khác'), icon: Icon(Icons.person_outline, size: 16)),
                      ],
                      selected: {gender},
                      onSelectionChanged: (set) => setDialogState(() => gender = set.first),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: bdayCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Ngày sinh',
                      hintText: 'Chọn ngày sinh (dd/MM/yyyy)',
                      prefixIcon: const Icon(Icons.cake_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: birthday != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setDialogState(() {
                                  birthday = null;
                                  bdayCtrl.clear();
                                });
                              },
                            )
                          : const Icon(Icons.calendar_today, size: 18),
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final initial = birthday ?? DateTime(2000, 1, 1);
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: initial.isAfter(now) ? now : initial,
                        firstDate: DateTime(1920),
                        lastDate: now,
                        helpText: 'CHỌN NGÀY SINH KHÁCH HÀNG',
                      );
                      if (picked != null) {
                        setDialogState(() {
                          birthday = picked;
                          bdayCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: context.tc.primary),
              onPressed: isSaving ? null : () async {
                final name = nameCtrl.text.trim().toUpperCase();
                final phone = phoneCtrl.text.trim();
                final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

                if (name.isEmpty) {
                  setDialogState(() => formError = 'Vui lòng nhập họ và tên khách hàng');
                  return;
                }
                if (digits.length < 9) {
                  setDialogState(() => formError = 'Số điện thoại phải có ít nhất 9 chữ số');
                  return;
                }

                // Check duplicate phone
                final duplicate = _customers.where((c) {
                  if (isEditing && c.id == customer.id) return false;
                  return c.phone.replaceAll(RegExp(r'[^0-9]'), '') == digits;
                }).firstOrNull;

                if (duplicate != null) {
                  setDialogState(() => formError = 'Số điện thoại này đã thuộc về khách "${duplicate.fullName}"');
                  return;
                }

                setDialogState(() => isSaving = true);
                final bdayStr = birthday != null ? DateFormat('yyyy-MM-dd').format(birthday!) : '';

                try {
                  if (isEditing) {
                    final updated = customer.copyWith(
                      name: name,
                      phone: phone,
                      gender: gender,
                      birthday: bdayStr,
                    );
                    await _fb.saveCustomer(updated);
                  } else {
                    final id = 'CUST_${DateTime.now().millisecondsSinceEpoch}';
                    final newCustomer = KmtCustomerModel(
                      id: id,
                      code: id,
                      fullName: name,
                      phone: phone,
                      gender: gender,
                      birthday: bdayStr,
                      currentPoints: 0,
                      totalPoints: 0,
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                    );
                    await _fb.saveCustomer(newCustomer);
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEditing ? 'Đã cập nhật thông tin khách hàng!' : 'Đã thêm khách hàng mới thành công!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    await _loadData();
                  }
                } catch (e) {
                  setDialogState(() {
                    isSaving = false;
                    formError = 'Lỗi lưu thông tin: $e';
                  });
                }
              },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isEditing ? 'Lưu thay đổi' : 'Thêm khách hàng'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCustomer(KmtCustomerModel c) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Xóa khách hàng "${c.fullName}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Khách hàng sẽ bị xóa khỏi chi nhánh này. Nếu khách không còn ở chi nhánh nào khác, '
                'toàn bộ điểm tích lũy và lịch sử điểm cũng bị xóa. Hóa đơn cũ được giữ nguyên. '
                'Không thể hoàn tác.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Gõ XOA để xác nhận', border: OutlineInputBorder()),
                onChanged: (_) => setLocal(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.tc.danger),
              onPressed: isDeleteCustomerConfirmed(ctrl.text) ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Xóa khách hàng'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final dangerColor = context.tc.danger;
    try {
      final removedMember = await CustomerDeleteService().deleteCustomer(
        storeCode: _auth.currentStoreCode,
        customerId: c.id,
      );
      messenger.showSnackBar(SnackBar(content: Text(deleteCustomerSuccessMessage(removedMember: removedMember))));
      if (mounted) await _loadData();
    } on CustomerDeleteException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: dangerColor));
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final info = await _fb.getStoreInfo();
      _storeInfo = info;
      _pointRedeemRate = info.pointRedeemRate;
      _pointEarnRate = info.pointEarnRate;
      _tiers = info.loyaltyTiers;

      final list = await _fb.getAllCustomers();
      if (mounted) {
        setState(() {
          _customers = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<KmtCustomerModel> get _filteredCustomers {
    return _customers.where((c) {
      if (_selectedTier != 'ALL') {
        if (c.tierName(_tiers) != _selectedTier) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = c.fullName.toLowerCase().contains(q);
        final matchPhone = c.phone.toLowerCase().contains(q);
        final matchCode = c.code.toLowerCase().contains(q);
        if (!matchName && !matchPhone && !matchCode) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportExcel() async {
    final customersToExport = _filteredCustomers;
    if (customersToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có khách hàng nào để xuất Excel')),
      );
      return;
    }

    final headers = [
      'STT',
      'Mã Khách Hàng',
      'Họ Và Tên',
      'Số Điện Thoại',
      'Giới Tính',
      'Ngày Sinh',
      'Điểm Tích Lũy (KMT)',
      'Giá Trị Quy Đổi (VNĐ)',
      'Hạng Thành Viên',
      'Ngày Tham Gia',
    ];

    int sumPoints = 0;
    int sumVal = 0;

    final rows = <List<dynamic>>[];
    for (int i = 0; i < customersToExport.length; i++) {
      final c = customersToExport[i];
      final pts = c.currentPoints;
      final val = pts * _pointRedeemRate;
      sumPoints += pts;
      sumVal += val;

      final dateStr = c.createdAt != null
          ? DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(c.createdAt!))
          : '—';

      rows.add([
        i + 1,
        c.code,
        c.fullName,
        c.phone,
        c.gender,
        _formatBirthday(c.birthday),
        pts,
        val,
        c.tierName(_tiers),
        dateStr,
      ]);
    }

    final totalRow = [
      'TỔNG CỘNG',
      '—',
      '—',
      '—',
      '—',
      '—',
      sumPoints,
      sumVal,
      '—',
      '—',
    ];

    final storeCode = _auth.currentStoreCode;
    final storeName = _storeInfo?.storeName ?? 'POS Trạm F&B';
    final storeAddress = _storeInfo?.address ?? 'Đà Lạt, Lâm Đồng';
    final storePhone = _storeInfo?.phone ?? '0987654321';
    final now = DateTime.now();

    final sm = ScaffoldMessenger.of(context);
    try {
    await ReportExportService.exportToExcel(
      reportCode: 'CRM_KHACHHANG',
      reportTitle: 'DANH SÁCH KHÁCH HÀNG CRM & TÍCH ĐIỂM KMT',
      storeCode: storeCode,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      startDate: now,
      endDate: now,
      headers: headers,
      rows: rows,
      totalRow: totalRow,
    );
    } catch (e) {
      sm.showSnackBar(SnackBar(content: Text('Lỗi xuất Excel: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _showConfigPointRateDialog() async {
    final redeemCtrl = TextEditingController(text: _pointRedeemRate.toString());
    final earnCtrl = TextEditingController(text: _pointEarnRate.toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.settings, color: context.tc.primary),
            const SizedBox(width: 8),
            Text(
              'Cấu Hình Tỷ Lệ Điểm KMT',
              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thiết lập giá trị quy đổi điểm tích luỹ và tỷ lệ thưởng điểm cho khách hàng CRM Khuyến Mãi Trạm:',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: redeemCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Giá trị 1 điểm đổi thưởng (VNĐ)',
                suffixText: 'đ / pt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: earnCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tỷ lệ tích điểm (% trên doanh số bill)',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ví dụ: 1 pt = 1.000đ, khi khách dùng 20 điểm sẽ giảm 20.000đ (được tính là khuyến mãi, không tính vào doanh thu thuần).',
              style: GoogleFonts.beVietnamPro(fontSize: 11, fontStyle: FontStyle.italic, color: context.tc.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.tc.primary),
            onPressed: () async {
              final newRedeem = int.tryParse(redeemCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1000;
              final newEarn = double.tryParse(earnCtrl.text.trim()) ?? 1.0;

              final updatedInfo = (_storeInfo ?? StoreInfoModel(storeCode: _auth.currentStoreCode, storeName: 'POS Trạm')).copyWith(
                pointRedeemRate: newRedeem,
                pointEarnRate: newEarn,
              );

              await _fb.saveStoreInfo(updatedInfo);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                setState(() {
                  _storeInfo = updatedInfo;
                  _pointRedeemRate = newRedeem;
                  _pointEarnRate = newEarn;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã cập nhật cấu hình tỷ lệ đổi điểm thành công!'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text('Lưu cấu hình'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCustomers = _customers.length;
    final totalPoints = _customers.fold(0, (sum, c) => sum + c.currentPoints);
    final totalValue = totalPoints * _pointRedeemRate;

    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        title: Text(
          'Khách Hàng & CRM Tích Điểm',
          style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_canManageCustomer)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Thêm khách hàng mới',
              onPressed: () => _showAddOrEditCustomerDialog(),
            ),
          if (_auth.isOwner || _auth.can(AppPermissions.manageLoyalty))
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Cấu hình tỷ lệ đổi điểm',
              onPressed: _showConfigPointRateDialog,
            ),
          if (_auth.can(AppPermissions.exportData))
            IconButton(
              icon: const Icon(Icons.table_view_outlined),
              tooltip: 'Xuất Excel danh sách',
              onPressed: _exportExcel,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: _canManageCustomer
          ? FloatingActionButton.extended(
              backgroundColor: context.tc.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add),
              label: Text('Thêm khách hàng', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
              onPressed: () => _showAddOrEditCustomerDialog(),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top KPI Summary
                Container(
                  color: context.tc.card,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildKpiBox(
                          title: 'Tổng khách hàng',
                          value: '$totalCustomers',
                          icon: Icons.people_outline,
                          color: context.tc.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildKpiBox(
                          title: 'Tổng điểm KMT',
                          value: '${FormatUtils.number(totalPoints)} pt',
                          icon: Icons.monetization_on_outlined,
                          color: context.ink(Colors.blue.shade700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildKpiBox(
                          title: 'Giá trị quy đổi',
                          value: FormatUtils.vnd(totalValue),
                          icon: Icons.redeem_outlined,
                          color: context.tc.success,
                        ),
                      ),
                    ],
                  ),
                ),

                // Search & Filter
                Container(
                  color: context.tc.card,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Tìm theo Tên, SĐT hoặc Mã khách hàng...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          filled: true,
                          fillColor: context.tc.cardElevated,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('ALL', 'Tất cả (${_customers.length})'),
                            // Hạng do Chủ quán đặt trên Web Admin (storeInfo.loyaltyTiers)
                            for (final t in _tiers) ...[
                              const SizedBox(width: 6),
                              _buildFilterChip(t.name, '${t.name} ≥${t.minPoints}pt'),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Customer List
                Expanded(
                  child: _filteredCustomers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_search_outlined, size: 64, color: context.tc.textHint),
                              const SizedBox(height: 8),
                              Text(
                                'Không tìm thấy khách hàng nào',
                                style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredCustomers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final c = _filteredCustomers[index];
                            final pts = c.currentPoints;
                            final val = pts * _pointRedeemRate;
                            final tierLabel = c.tierName(_tiers);
                            final isVip = _tiers.length > 1 && tierLabel == _tiers.last.name;

                            return Card(
                              elevation: 0.5,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: isVip ? Colors.amber.shade300 : context.tc.borderLight),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _canManageCustomer ? () => _showAddOrEditCustomerDialog(customer: c) : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: isVip ? context.bg(Colors.amber.shade100) : context.tc.primaryLight.withValues(alpha: 0.4),
                                        child: Text(
                                          c.fullName.isNotEmpty ? c.fullName.substring(0, 1).toUpperCase() : 'K',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isVip ? context.ink(Colors.amber.shade900) : context.tc.primaryDark,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    c.fullName,
                                                    style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isVip ? context.bg(Colors.amber.shade50) : context.tc.cardElevated,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: isVip ? Colors.amber.shade400 : context.tc.border),
                                                  ),
                                                  child: Text(
                                                    tierLabel,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: isVip ? context.ink(Colors.amber.shade900) : context.tc.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.phone, size: 12, color: context.tc.textHint),
                                                const SizedBox(width: 4),
                                                Text(c.phone, style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary)),
                                                const SizedBox(width: 10),
                                                Text('• Mã: ${c.code}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary)),
                                              ],
                                            ),
                                            if (c.gender.isNotEmpty || c.birthday.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  if (c.gender.isNotEmpty) ...[
                                                    Icon(
                                                      c.gender == 'Nam'
                                                          ? Icons.male
                                                          : (c.gender == 'Nữ' ? Icons.female : Icons.person_outline),
                                                      size: 13,
                                                      color: c.gender == 'Nam'
                                                          ? Colors.blue.shade700
                                                          : (c.gender == 'Nữ' ? Colors.pink.shade700 : context.tc.textHint),
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      c.gender,
                                                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                                                    ),
                                                  ],
                                                  if (c.gender.isNotEmpty && c.birthday.isNotEmpty)
                                                    Text(' • ', style: TextStyle(color: context.tc.textHint, fontSize: 11)),
                                                  if (c.birthday.isNotEmpty) ...[
                                                    Icon(Icons.cake_outlined, size: 12, color: context.ink(Colors.orange.shade700)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      _formatBirthday(c.birthday),
                                                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${FormatUtils.number(pts)} pt',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: context.ink(Colors.blue.shade800),
                                            ),
                                          ),
                                          Text(
                                            '= ${FormatUtils.vnd(val)}',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: context.tc.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_canManageCustomer)
                                        IconButton(
                                          tooltip: 'Chỉnh sửa thông tin',
                                          icon: Icon(Icons.edit_outlined, size: 20, color: context.tc.primary),
                                          onPressed: () => _showAddOrEditCustomerDialog(customer: c),
                                        ),
                                      if (_canDeleteCustomer)
                                        IconButton(
                                          tooltip: 'Xóa khách hàng',
                                          icon: Icon(Icons.delete_outline, size: 20, color: context.tc.danger),
                                          onPressed: () => _confirmDeleteCustomer(c),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildKpiBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.beVietnamPro(fontSize: 10, color: context.tc.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedTier == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: context.tc.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: isSelected ? context.tc.primary : context.tc.textPrimary),
      onSelected: (val) {
        if (val) setState(() => _selectedTier = key);
      },
    );
  }
}
