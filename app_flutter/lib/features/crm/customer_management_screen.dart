// lib/features/crm/customer_management_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/reports/report_export_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

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

  bool get _isManagerOrOwner {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.isOwner ||
        user.isManager ||
        user.can(AppPermissions.viewReports) ||
        user.can(AppPermissions.manageStoreSettings) ||
        _auth.canAccessManagerHub;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final info = await _fb.getStoreInfo();
      _storeInfo = info;
      _pointRedeemRate = info.pointRedeemRate;
      _pointEarnRate = info.pointEarnRate;

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
        if (_selectedTier == 'VIP' && c.groupName != 'VIP') return false;
        if (_selectedTier == 'THAN_THIET' && c.groupName != 'Thân thiết') return false;
        if (_selectedTier == 'THANH_VIEN' && c.groupName != 'Thành viên') return false;
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
        pts,
        val,
        c.groupName,
        dateStr,
      ]);
    }

    final totalRow = [
      'TỔNG CỘNG',
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
            const Icon(Icons.settings, color: TramColors.brandPrimary),
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
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
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
              style: GoogleFonts.beVietnamPro(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: TramColors.brandPrimary),
            onPressed: () async {
              final newRedeem = int.tryParse(redeemCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1000;
              final newEarn = double.tryParse(earnCtrl.text.trim()) ?? 1.0;

              final updatedInfo = (_storeInfo ?? StoreInfoModel(storeCode: _auth.currentStoreCode, storeName: 'POS Trạm')).copyWith(
                pointRedeemRate: newRedeem,
                pointEarnRate: newEarn,
              );

              await _fb.saveStoreInfo(updatedInfo);
              if (mounted) {
                setState(() {
                  _storeInfo = updatedInfo;
                  _pointRedeemRate = newRedeem;
                  _pointEarnRate = newEarn;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã cập nhật cấu hình tỷ lệ đổi điểm thành công!'),
                    backgroundColor: TramColors.success,
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
      backgroundColor: TramColors.background,
      appBar: AppBar(
        title: Text(
          'Khách Hàng & CRM Tích Điểm',
          style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isManagerOrOwner)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Cấu hình tỷ lệ đổi điểm',
              onPressed: _showConfigPointRateDialog,
            ),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top KPI Summary
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildKpiBox(
                          title: 'Tổng khách hàng',
                          value: '$totalCustomers',
                          icon: Icons.people_outline,
                          color: TramColors.brandPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildKpiBox(
                          title: 'Tổng điểm KMT',
                          value: '${FormatUtils.number(totalPoints)} pt',
                          icon: Icons.monetization_on_outlined,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildKpiBox(
                          title: 'Giá trị quy đổi',
                          value: FormatUtils.vnd(totalValue),
                          icon: Icons.redeem_outlined,
                          color: TramColors.success,
                        ),
                      ),
                    ],
                  ),
                ),

                // Search & Filter
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Tìm theo Tên, SĐT hoặc Mã khách hàng...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          filled: true,
                          fillColor: Colors.grey.shade100,
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
                            const SizedBox(width: 6),
                            _buildFilterChip('VIP', 'VIP ≥500pt'),
                            const SizedBox(width: 6),
                            _buildFilterChip('THAN_THIET', 'Thân thiết 100-499pt'),
                            const SizedBox(width: 6),
                            _buildFilterChip('THANH_VIEN', 'Thành viên <100pt'),
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
                              Icon(Icons.person_search_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                'Không tìm thấy khách hàng nào',
                                style: GoogleFonts.beVietnamPro(color: Colors.grey.shade600),
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
                            final isVip = c.groupName == 'VIP';

                            return Card(
                              elevation: 0.5,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: isVip ? Colors.amber.shade300 : Colors.grey.shade200),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: isVip ? Colors.amber.shade100 : TramColors.primaryLight.withOpacity(0.4),
                                      child: Text(
                                        c.fullName.isNotEmpty ? c.fullName.substring(0, 1).toUpperCase() : 'K',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isVip ? Colors.amber.shade900 : TramColors.primaryDark,
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
                                                  color: isVip ? Colors.amber.shade50 : Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: isVip ? Colors.amber.shade400 : Colors.grey.shade300),
                                                ),
                                                child: Text(
                                                  c.groupName,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isVip ? Colors.amber.shade900 : Colors.grey.shade700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.phone, size: 12, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Text(c.phone, style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey.shade700)),
                                              const SizedBox(width: 10),
                                              Text('• Mã: ${c.code}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.grey.shade600)),
                                            ],
                                          ),
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
                                            color: Colors.blue.shade800,
                                          ),
                                        ),
                                        Text(
                                          '= ${FormatUtils.vnd(val)}',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: TramColors.success,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
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
                  style: GoogleFonts.beVietnamPro(fontSize: 10, color: Colors.grey.shade700),
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
      selectedColor: TramColors.brandPrimary.withOpacity(0.15),
      labelStyle: TextStyle(color: isSelected ? TramColors.brandPrimary : Colors.black87),
      onSelected: (val) {
        if (val) setState(() => _selectedTier = key);
      },
    );
  }
}
