import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/reports/report_export_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class CashShiftsScreen extends StatefulWidget {
  const CashShiftsScreen({super.key});

  @override
  State<CashShiftsScreen> createState() => _CashShiftsScreenState();
}

class _CashShiftsScreenState extends State<CashShiftsScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  List<CashShiftModel> _shifts = [];
  List<BillModel> _allBills = [];
  StreamSubscription<List<CashShiftModel>>? _shiftsSub;
  StreamSubscription<List<BillModel>>? _billsSub;
  bool _loading = true;
  String _searchQuery = '';
  String _statusFilter = 'ALL'; // ALL, OPEN, CLOSED
  DateTime? _selectedDate;
  bool _allowStaffViewDifference = true;
  bool _updatingSetting = false;

  bool get _isManagerOrOwner {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.isOwner ||
        user.isManager ||
        user.can(AppPermissions.viewReports) ||
        user.can(AppPermissions.manageStoreSettings) ||
        _auth.canAccessManagerHub;
  }

  bool get _canViewDifference => _isManagerOrOwner || _allowStaffViewDifference;

  @override
  void initState() {
    super.initState();
    _loadStoreSetting();
    _loadShifts();
  }

  @override
  void dispose() {
    _shiftsSub?.cancel();
    _billsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStoreSetting() async {
    try {
      final store = await _fb.getStoreInfo();
      if (mounted) {
        setState(() {
          _allowStaffViewDifference = store.allowStaffViewShiftDifference;
        });
      }
    } catch (_) {}
  }

  void _loadShifts() {
    _shiftsSub = _fb.cashShiftsStream().listen((list) {
      if (mounted) {
        setState(() {
          _shifts = list;
          _loading = false;
        });
      }
    });

    _billsSub = _fb.billsStream().listen((bills) {
      if (mounted) {
        setState(() {
          _allBills = bills;
        });
      }
    });
  }

  List<BillModel> _getShiftBills(CashShiftModel shift) {
    return _allBills.where((b) {
      if (b.shiftId != null && b.shiftId!.isNotEmpty) {
        return b.shiftId == shift.id || b.shiftId == shift.shiftCode;
      }
      final closeT = shift.closedAt ?? 9999999999999;
      return b.createdAt >= shift.openedAt && b.createdAt <= closeT;
    }).toList();
  }

  Map<String, dynamic> _computeShiftPromoStats(CashShiftModel shift) {
    final bills = _getShiftBills(shift).where((b) => b.status == 'PAID').toList();
    int discountedItemsCount = 0;
    int discountedItemsTotal = 0;
    int voucherCount = 0;
    int voucherTotal = 0;
    int pointsUsedTotal = 0;
    int pointsDiscountTotal = 0;

    for (final b in bills) {
      for (final it in b.items) {
        if (it.lineDiscountTotal > 0) {
          // Chỉ đếm số phần được giảm; tổng giảm là tổng CẢ DÒNG đã lưu
          discountedItemsCount += it.discountedQuantity;
          discountedItemsTotal += it.lineDiscountTotal;
        }
      }
      for (final d in b.discounts) {
        voucherCount += 1;
        voucherTotal += d.amount;
      }
      if (b.pointsDiscount > 0 || b.pointsUsed > 0) {
        pointsUsedTotal += b.pointsUsed;
        pointsDiscountTotal += b.pointsDiscount;
      }
    }

    final totalPromoDiscount = discountedItemsTotal + voucherTotal + pointsDiscountTotal;

    return {
      'discountedItemsCount': discountedItemsCount,
      'discountedItemsTotal': discountedItemsTotal,
      'voucherCount': voucherCount,
      'voucherTotal': voucherTotal,
      'pointsUsedTotal': pointsUsedTotal,
      'pointsDiscountTotal': pointsDiscountTotal,
      'totalPromoDiscount': totalPromoDiscount,
      'paidBills': bills,
    };
  }

  Future<void> _exportShiftPromotionsExcel(CashShiftModel shift) async {
    final promo = _computeShiftPromoStats(shift);
    final List<BillModel> paidBills = List<BillModel>.from(promo['paidBills']);
    final storeInfo = _auth.currentStoreInfo;
    final storeName = storeInfo?.storeName ?? 'POS Trạm F&B';
    final storeCode = storeInfo?.storeCode ?? _auth.currentStoreCode;
    final storeAddress = storeInfo?.address ?? 'Đà Lạt, Lâm Đồng';
    final storePhone = storeInfo?.phone ?? '0987654321';

    final headers = [
      'STT',
      'Mã Hóa Đơn',
      'Bàn / Khu Vực',
      'Thời Gian',
      'Thu Ngân',
      'Tổng Tiền Hàng',
      'Giảm Giá Món',
      'Voucher / KM',
      'Điểm Dùng',
      'Giảm Giá Điểm',
      'Tổng Giảm Giá',
      'Thanh Toán',
      'Phương Thức',
    ];

    int sumGross = 0;
    int sumItemDisc = 0;
    int sumVoucher = 0;
    int sumPoints = 0;
    int sumPointsDisc = 0;
    int sumTotalDisc = 0;
    int sumFinal = 0;

    final rows = <List<dynamic>>[];
    for (int i = 0; i < paidBills.length; i++) {
      final b = paidBills[i];
      final itemD = b.items.fold(0, (s, it) => s + it.lineDiscountTotal);
      final voucherD = b.discounts.fold(0, (s, d) => s + d.amount);
      final pUsed = b.pointsUsed;
      final pDisc = b.pointsDiscount;
      final totD = b.totalDiscount;
      final finalAmt = b.finalAmount;

      sumGross += b.subTotal;
      sumItemDisc += itemD;
      sumVoucher += voucherD;
      sumPoints += pUsed;
      sumPointsDisc += pDisc;
      sumTotalDisc += totD;
      sumFinal += finalAmt;

      final dtStr = DateFormat('dd/MM/yyyy HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt),
      );

      rows.add([
        i + 1,
        b.billCode,
        b.tableName,
        dtStr,
        b.staffFullName.isNotEmpty ? b.staffFullName : shift.staffFullName,
        b.subTotal,
        itemD,
        voucherD,
        pUsed,
        pDisc,
        totD,
        finalAmt,
        b.paymentMethod,
      ]);
    }

    final totalRow = [
      'TỔNG CỘNG',
      '—',
      '—',
      '—',
      '—',
      sumGross,
      sumItemDisc,
      sumVoucher,
      sumPoints,
      sumPointsDisc,
      sumTotalDisc,
      sumFinal,
      '—',
    ];

    final openedDt = DateTime.fromMillisecondsSinceEpoch(shift.openedAt);
    final closedDt = shift.closedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(shift.closedAt!)
        : DateTime.now();

    await ReportExportService.exportToExcel(
      reportCode: 'KM_CA_${shift.shiftCode}',
      reportTitle: 'KHUYẾN MÃI & GIẢM GIÁ CA ${shift.shiftCode}',
      storeCode: storeCode,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      startDate: openedDt,
      endDate: closedDt,
      headers: headers,
      rows: rows,
      totalRow: totalRow,
    );
  }

  Future<void> _toggleAllowDifference(bool val) async {
    setState(() => _updatingSetting = true);
    await _fb.updateStoreShiftDifferenceSetting(val);
    setState(() {
      _allowStaffViewDifference = val;
      _updatingSetting = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(val
              ? 'Đã BẬT cho phép nhân viên xem chênh lệch khi kết ca'
              : 'Đã TẮT (Ẩn chênh lệch két đối với nhân viên khi kết ca)'),
          backgroundColor: val ? TramColors.success : TramColors.warningInk,
        ),
      );
    }
  }

  List<CashShiftModel> get _filteredShifts {
    return _shifts.where((s) {
      if (_statusFilter == 'OPEN' && !s.isOpen) return false;
      if (_statusFilter == 'CLOSED' && s.isOpen) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchCode = s.shiftCode.toLowerCase().contains(q);
        final matchStaff = s.staffFullName.toLowerCase().contains(q) ||
            s.staffUsername.toLowerCase().contains(q);
        if (!matchCode && !matchStaff) return false;
      }

      if (_selectedDate != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(s.openedAt);
        if (dt.year != _selectedDate!.year ||
            dt.month != _selectedDate!.month ||
            dt.day != _selectedDate!.day) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _showSlipDetailModal(CashShiftModel shift) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSlipSheet(shift),
    );
  }

  Widget _buildSlipSheet(CashShiftModel shift) {
    final openedStr = DateFormat('HH:mm:ss - dd/MM/yyyy')
        .format(DateTime.fromMillisecondsSinceEpoch(shift.openedAt));
    final closedStr = shift.closedAt != null
        ? DateFormat('HH:mm:ss - dd/MM/yyyy')
            .format(DateTime.fromMillisecondsSinceEpoch(shift.closedAt!))
        : 'Đang mở (Chưa kết ca)';

    final storeInfo = _auth.currentStoreInfo;
    final storeName = storeInfo?.storeName ?? 'POS Trạm F&B';
    final storeAddress = storeInfo?.address ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Slip Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PHIẾU BÀN GIAO CA',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: TramColors.brandPrimary,
                    ),
                  ),
                  Text(
                    'Mã ca: ${shift.shiftCode}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TramColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: shift.isOpen
                      ? TramColors.successSurface
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: shift.isOpen
                        ? TramColors.success
                        : Colors.grey.shade400,
                  ),
                ),
                child: Text(
                  shift.isOpen ? 'ĐANG MỞ' : 'ĐÃ KẾT CA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: shift.isOpen ? TramColors.success : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          // Store & Staff Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSlipMetaRow('Cửa hàng / Chi nhánh:', storeName),
                if (storeAddress.isNotEmpty)
                  _buildSlipMetaRow('Địa chỉ:', storeAddress),
                _buildSlipMetaRow(
                    'Thu ngân bàn giao:', '${shift.staffFullName} (${shift.staffUsername})'),
                _buildSlipMetaRow('Giờ mở ca:', openedStr),
                _buildSlipMetaRow('Giờ kết ca:', closedStr),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Numbers Breakdown
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TramColors.borderLight),
            ),
            child: Column(
              children: [
                _buildNumberRow('1. Tiền mặt đầu ca:', FormatUtils.vnd(shift.initialCash)),
                _buildNumberRow('2. Doanh số tiền mặt (+):', FormatUtils.vnd(shift.totalCashSales),
                    color: TramColors.success),
                _buildNumberRow('3. Doanh thu Chuyển khoản (VietQR):', FormatUtils.vnd(shift.totalQrSales),
                    color: TramColors.info),
                if (shift.totalCardSales > 0)
                  _buildNumberRow('4. Doanh thu Thẻ POS:', FormatUtils.vnd(shift.totalCardSales)),
                _buildNumberRow('5. Nộp thêm vào két (Cash In):', FormatUtils.vnd(shift.cashIn)),
                _buildNumberRow('6. Chi vặt từ két (Cash Out):', FormatUtils.vnd(shift.cashOut),
                    color: TramColors.danger),
                const Divider(height: 16),
                _buildNumberRow('TỔNG DOANH THU BÁN TRONG CA:', FormatUtils.vnd(shift.totalRevenue),
                    isBold: true),
                const Divider(height: 16),
                if (_canViewDifference) ...[
                  _buildNumberRow('TIỀN MẶT KỲ VỌNG TRONG KÉT:', FormatUtils.vnd(shift.expectedCash),
                      isBold: true, color: TramColors.brandPrimary),
                  if (!shift.isOpen) ...[
                    _buildNumberRow(
                        'TIỀN MẶT THỰC KIỂM ĐẾM:', FormatUtils.vnd(shift.actualCash ?? 0),
                        isBold: true),
                    _buildNumberRow(
                      'CHÊNH LỆCH KÉT:',
                      '${(shift.difference ?? 0) >= 0 ? "+" : ""}${FormatUtils.vnd(shift.difference ?? 0)}',
                      isBold: true,
                      color: (shift.difference ?? 0) == 0
                          ? TramColors.success
                          : ((shift.difference ?? 0) > 0 ? TramColors.info : TramColors.danger),
                    ),
                  ],
                ] else ...[
                  _buildNumberRow('TIỀN MẶT THỰC KIỂM ĐẾM:',
                      FormatUtils.vnd(shift.actualCash ?? 0),
                      isBold: true),
                  _buildNumberRow('CHÊNH LỆCH KÉT:', '•••••• (Chỉ Quản lý được xem)',
                      isBold: true, color: Colors.grey),
                ],
              ],
            ),
          ),
          // Promotional Breakdown for Shift (Module 4)
          Builder(
            builder: (ctx) {
              final promo = _computeShiftPromoStats(shift);
              final discItemsCount = promo['discountedItemsCount'] as int;
              final discItemsTotal = promo['discountedItemsTotal'] as int;
              final vCount = promo['voucherCount'] as int;
              final vTotal = promo['voucherTotal'] as int;
              final pUsed = promo['pointsUsedTotal'] as int;
              final pDisc = promo['pointsDiscountTotal'] as int;
              final totDisc = promo['totalPromoDiscount'] as int;

              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF5F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF5D5D8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.discount_outlined, size: 16, color: Color(0xFF7E2930)),
                        const SizedBox(width: 6),
                        Text(
                          'KHUYẾN MÃI & GIẢM GIÁ TRONG CA',
                          style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF7E2930)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildNumberRow('• Món giảm giá ($discItemsCount món):', '-${FormatUtils.vnd(discItemsTotal)}', color: TramColors.danger),
                    _buildNumberRow('• Voucher / KM ($vCount lượt):', '-${FormatUtils.vnd(vTotal)}', color: TramColors.danger),
                    _buildNumberRow('• Điểm KMT đổi ($pUsed điểm):', '-${FormatUtils.vnd(pDisc)}', color: TramColors.danger),
                    const Divider(height: 12),
                    _buildNumberRow('TỔNG GIẢM GIÁ TRONG CA:', '-${FormatUtils.vnd(totDisc)}', isBold: true, color: const Color(0xFF7E2930)),
                  ],
                ),
              );
            },
          ),
          if (shift.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TramColors.warningSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Ghi chú ca: ${shift.notes}',
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.warningInk),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.table_view_outlined, size: 18, color: Color(0xFF137333)),
              label: const Text('Xuất Excel Khuyến Mãi Ca', style: TextStyle(color: Color(0xFF137333), fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF137333)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () async {
                try {
                  await _exportShiftPromotionsExcel(shift);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi xuất Excel: $e'), backgroundColor: TramColors.danger),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Chia Sẻ Phiếu'),
                  onPressed: () {
                    final text = '''
================================
${storeName.toUpperCase()}
PHIẾU BÀN GIAO CA BÁN HÀNG
Mã ca: ${shift.shiftCode}
Thu ngân: ${shift.staffFullName} (${shift.staffUsername})
Mở ca: $openedStr
Kết ca: $closedStr
--------------------------------
1. Tiền mặt đầu ca: ${FormatUtils.vnd(shift.initialCash)}
2. Bán hàng tiền mặt: ${FormatUtils.vnd(shift.totalCashSales)}
3. Doanh thu VietQR: ${FormatUtils.vnd(shift.totalQrSales)}
4. Nộp thêm két: ${FormatUtils.vnd(shift.cashIn)}
5. Chi vặt két: ${FormatUtils.vnd(shift.cashOut)}
--------------------------------
TỔNG DOANH THU: ${FormatUtils.vnd(shift.totalRevenue)}
TIỀN KIỂM ĐẾM THỰC TẾ: ${FormatUtils.vnd(shift.actualCash ?? 0)}
${_canViewDifference ? "CHÊNH LỆCH: " + FormatUtils.vnd(shift.difference ?? 0) : ""}
Ghi chú: ${shift.notes}
================================
''';
                    Share.share(text, subject: 'Phiếu bàn giao ca ${shift.shiftCode}');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('In Phiếu Bàn Giao'),
                  style: ElevatedButton.styleFrom(backgroundColor: TramColors.brandPrimary),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã gửi lệnh in phiếu bàn giao ca ${shift.shiftCode} tới máy in nhiệt.'),
                        backgroundColor: TramColors.success,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlipMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? TramColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredShifts;

    return Scaffold(
      backgroundColor: TramColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phiếu Bàn Giao Ca',
              style: GoogleFonts.beVietnamPro(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              'Xem phiên giao két & chênh lệch của nhân viên',
              style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Chọn ngày',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
          ),
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              tooltip: 'Xóa lọc ngày',
              onPressed: () => setState(() => _selectedDate = null),
            ),
        ],
      ),
      body: Column(
        children: [
          // Manager Control Banner for Difference Toggle
          if (_isManagerOrOwner)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TramColors.borderLight),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _allowStaffViewDifference
                          ? TramColors.successSurface
                          : TramColors.warningSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _allowStaffViewDifference ? Icons.visibility : Icons.visibility_off,
                      color: _allowStaffViewDifference
                          ? TramColors.success
                          : TramColors.warningInk,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Xem chênh lệch tiền két khi kết ca',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _allowStaffViewDifference
                              ? 'Nhân viên nhìn thấy số dư lý thuyết và chênh lệch'
                              : 'Ẩn chênh lệch: Nhân viên kiểm đếm mù, chỉ Quản lý xem đối soát',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: TramColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _allowStaffViewDifference,
                    activeColor: TramColors.brandPrimary,
                    onChanged: _updatingSetting ? null : _toggleAllowDifference,
                  ),
                ],
              ),
            ),

          // Search & Filter Row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm theo mã ca, tên nhân viên...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: TramColors.borderLight),
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: TramColors.borderLight),
                  ),
                  child: DropdownButton<String>(
                    value: _statusFilter,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('Tất cả ca')),
                      DropdownMenuItem(value: 'OPEN', child: Text('Đang mở')),
                      DropdownMenuItem(value: 'CLOSED', child: Text('Đã chốt')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _statusFilter = v);
                    },
                  ),
                ),
              ],
            ),
          ),

          if (_selectedDate != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, size: 14, color: TramColors.brandPrimary),
                  const SizedBox(width: 4),
                  Text(
                    'Đang lọc ngày: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TramColors.brandPrimary,
                    ),
                  ),
                ],
              ),
            ),

          // List of shifts
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'Không tìm thấy phiên giao két nào',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 14,
                                color: TramColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final shift = filtered[i];
                          return _buildShiftCard(shift);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftCard(CashShiftModel shift) {
    final openedStr = DateFormat('HH:mm dd/MM')
        .format(DateTime.fromMillisecondsSinceEpoch(shift.openedAt));
    final closedStr = shift.closedAt != null
        ? DateFormat('HH:mm dd/MM')
            .format(DateTime.fromMillisecondsSinceEpoch(shift.closedAt!))
        : 'Chưa đóng';

    final diff = shift.difference ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TramColors.borderLight),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showSlipDetailModal(shift),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: shift.isOpen
                                ? TramColors.successSurface
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.point_of_sale,
                            size: 18,
                            color: shift.isOpen ? TramColors.success : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shift.shiftCode,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'NV: ${shift.staffFullName} (${shift.staffUsername})',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: TramColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: shift.isOpen ? TramColors.success : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        shift.isOpen ? 'ĐANG MỞ' : 'ĐÃ KẾT CA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: shift.isOpen ? Colors.white : Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Thời gian: $openedStr ➔ $closedStr',
                  style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tổng doanh thu ca',
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 11, color: TramColors.textSecondary)),
                        Text(
                          FormatUtils.vnd(shift.totalRevenue),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: TramColors.brandPrimary,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tiền đếm thực tế',
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 11, color: TramColors.textSecondary)),
                        Text(
                          shift.isOpen
                              ? 'Đang bán...'
                              : FormatUtils.vnd(shift.actualCash ?? 0),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Chênh lệch',
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 11, color: TramColors.textSecondary)),
                        if (!_canViewDifference && !shift.isOpen)
                          Text('••••••',
                              style: GoogleFonts.beVietnamPro(
                                  fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey))
                        else if (shift.isOpen)
                          Text('Chưa chốt',
                              style: GoogleFonts.beVietnamPro(
                                  fontSize: 12, color: TramColors.textSecondary))
                        else
                          Text(
                            '${diff >= 0 ? "+" : ""}${FormatUtils.vnd(diff)}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: diff == 0
                                  ? TramColors.success
                                  : (diff > 0 ? TramColors.info : TramColors.danger),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Xem chi tiết phiếu ›',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: TramColors.brandPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
