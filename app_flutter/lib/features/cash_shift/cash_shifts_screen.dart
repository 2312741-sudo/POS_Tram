import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/domain/shift_scope.dart';
import '../../core/reports/report_export_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/text_formatters.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../core/utils/share_utils.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CashShiftsScreen extends StatefulWidget {
  const CashShiftsScreen({super.key});

  @override
  State<CashShiftsScreen> createState() => _CashShiftsScreenState();
}

class _CashShiftsScreenState extends State<CashShiftsScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  List<CashShiftModel> _shifts = [];
  StreamSubscription<List<CashShiftModel>>? _shiftsSub;
  Timer? _safetyTimeoutTimer;
  final Map<String, List<BillModel>> _shiftBillsCache = {};
  bool _loading = true;
  String _searchQuery = '';
  String _statusFilter = 'ALL'; // ALL, OPEN, CLOSED
  DateTime? _selectedDate;
  String? _ownerFilter; // lọc theo tài khoản (chỉ chủ/quản lý có VIEW_ALL_SHIFTS)

  bool get _canViewAllShifts => _auth.canViewAllShifts;

  /// Phiếu bàn giao (số kỳ vọng, chênh lệch, in/chia sẻ) chỉ dành cho người có VIEW_SHIFT_HANDOVER.
  bool get _canViewDifference => _auth.canViewShiftHandover;

  @override
  void initState() {
    super.initState();
    _initShiftsData();
  }

  @override
  void dispose() {
    _safetyTimeoutTimer?.cancel();
    _shiftsSub?.cancel();
    super.dispose();
  }

  void _initShiftsData() {
    // 1. Lấy dữ liệu ngay từ cache trong Repository nếu có sẵn
    final cached = _fb.cachedCashShiftsList;
    if (cached != null && cached.isNotEmpty) {
      _shifts = cached;
      _loading = false;
    } else if (_fb.activeShiftCache != null) {
      _shifts = [_fb.activeShiftCache!];
      _loading = false;
    }

    // 2. Cơ chế timeout an toàn 3s: Tự động tắt loading tránh spinner xoay vô tận
    _safetyTimeoutTimer?.cancel();
    _safetyTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
        });
      }
    });

    // 3. Chủ động lấy danh sách ca gần nhất qua Future (bổ sung cho stream)
    _fb.getRecentCashShifts().then((recent) {
      if (mounted && recent.isNotEmpty) {
        setState(() {
          _shifts = recent;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    });

    // 4. Lắng nghe Stream realtime (đã hỗ trợ replay cache ngay lập tức khi đăng ký)
    _shiftsSub = _fb.cashShiftsStream().listen((list) {
      _safetyTimeoutTimer?.cancel();
      if (mounted) {
        setState(() {
          _shifts = list;
          _loading = false;
        });
      }
    }, onError: (_) {
      _safetyTimeoutTimer?.cancel();
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    });
  }

  Future<List<BillModel>> _getOrFetchShiftBills(CashShiftModel shift) async {
    if (_shiftBillsCache.containsKey(shift.id)) {
      return _shiftBillsCache[shift.id]!;
    }
    try {
      final bills = await _fb.getBillsForShift(shift);
      _shiftBillsCache[shift.id] = bills;
      return bills;
    } catch (_) {
      return <BillModel>[];
    }
  }

  List<BillModel> _getShiftBills(CashShiftModel shift, {List<BillModel>? bills}) {
    final list = bills ?? _shiftBillsCache[shift.id] ?? <BillModel>[];
    return list.where((b) => billBelongsToShift(b, shift)).toList();
  }

  Map<String, dynamic> _computeShiftPromoStats(CashShiftModel shift, {List<BillModel>? bills}) {
    final shiftBills = _getShiftBills(shift, bills: bills).where((b) => b.status == 'PAID').toList();
    int discountedItemsCount = 0;
    int discountedItemsTotal = 0;
    int voucherCount = 0;
    int voucherTotal = 0;
    int pointsUsedTotal = 0;
    int pointsDiscountTotal = 0;

    for (final b in shiftBills) {
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
      'paidBills': shiftBills,
    };
  }

  Future<void> _exportShiftPromotionsExcel(CashShiftModel shift) async {
    final bills = await _getOrFetchShiftBills(shift);
    final promo = _computeShiftPromoStats(shift, bills: bills);
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

  List<CashShiftModel> get _filteredShifts {
    return _fb.scopeVisibleShifts(_shifts, filterOwner: _ownerFilter).where((s) {
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
      builder: (ctx) => _canViewDifference ? _buildSlipSheet(shift) : _buildMyShiftSummary(shift),
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
      decoration: BoxDecoration(
        color: context.tc.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.tc.border,
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
                        color: context.tc.primary,
                      ),
                    ),
                    Text(
                      'Mã ca: ${shift.shiftCode}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.tc.textSecondary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: shift.isOpen
                        ? context.tc.successLight
                        : context.tc.cardElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: shift.isOpen
                          ? context.tc.success
                          : context.tc.textHint,
                    ),
                  ),
                  child: Text(
                    shift.isOpen ? 'ĐANG MỞ' : 'ĐÃ KẾT CA',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: shift.isOpen ? context.tc.success : context.tc.textSecondary,
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
                color: context.tc.cardElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.tc.borderLight),
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
                color: context.tc.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.tc.borderLight),
              ),
              child: Column(
                children: [
                  _buildNumberRow('1. Tiền mặt đầu ca:', FormatUtils.vndComma(shift.initialCash)),
                  _buildNumberRow('2. Doanh số tiền mặt (+):', FormatUtils.vndComma(shift.totalCashSales),
                      color: context.tc.success),
                  _buildNumberRow('3. Doanh thu Chuyển khoản (VietQR):', FormatUtils.vndComma(shift.totalQrSales),
                      color: context.tc.info),
                  if (shift.totalCardSales > 0)
                    _buildNumberRow('4. Doanh thu Thẻ POS:', FormatUtils.vndComma(shift.totalCardSales)),
                  _buildNumberRow('5. Nộp thêm vào két (Cash In):', FormatUtils.vndComma(shift.cashIn)),
                  _buildNumberRow('6. Chi vặt từ két (Cash Out):', FormatUtils.vndComma(shift.cashOut),
                      color: context.tc.danger),
                  const Divider(height: 16),
                  _buildNumberRow('TỔNG DOANH THU BÁN TRONG CA:', FormatUtils.vndComma(shift.totalRevenue),
                      isBold: true),
                  const Divider(height: 16),
                  if (_canViewDifference) ...[
                    _buildNumberRow('TIỀN MẶT KỲ VỌNG TRONG KÉT:', FormatUtils.vndComma(shift.expectedCash),
                        isBold: true, color: context.tc.primary),
                    if (!shift.isOpen) ...[
                      _buildNumberRow(
                          'TIỀN MẶT THỰC KIỂM ĐẾM:', FormatUtils.vndComma(shift.actualCash ?? 0),
                          isBold: true),
                      _buildNumberRow(
                        'CHÊNH LỆCH KÉT:',
                        '${(shift.difference ?? 0) >= 0 ? "+" : ""}${FormatUtils.vndComma(shift.difference ?? 0)}',
                        isBold: true,
                        color: (shift.difference ?? 0) == 0
                            ? context.tc.success
                            : ((shift.difference ?? 0) > 0 ? context.tc.info : context.tc.danger),
                      ),
                    ],
                  ] else ...[
                    _buildNumberRow('TIỀN MẶT THỰC KIỂM ĐẾM:',
                        FormatUtils.vndComma(shift.actualCash ?? 0),
                        isBold: true),
                    _buildNumberRow('CHÊNH LỆCH KÉT:', '•••••• (Chỉ Quản lý được xem)',
                        isBold: true, color: context.tc.textHint),
                  ],
                ],
              ),
            ),
            // Promotional Breakdown for Shift (Module 4) - tải bills theo ca khi mở sheet
            FutureBuilder<List<BillModel>>(
              future: _getOrFetchShiftBills(shift),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !_shiftBillsCache.containsKey(shift.id)) {
                  return Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.tc.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.line(const Color(0xFFF5D5D8))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: context.tc.primary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Đang tính toán khuyến mãi ca...',
                          style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.primary),
                        ),
                      ],
                    ),
                  );
                }
                final bills = snapshot.data ?? _shiftBillsCache[shift.id] ?? <BillModel>[];
                final promo = _computeShiftPromoStats(shift, bills: bills);
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
                    color: context.tc.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.line(const Color(0xFFF5D5D8))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(LucideIcons.badgePercent, size: 16, color: context.tc.primary),
                          const SizedBox(width: 6),
                          Text(
                            'KHUYẾN MÃI & GIẢM GIÁ TRONG CA',
                            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: context.tc.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildNumberRow('• Món giảm giá ($discItemsCount món):', '-${FormatUtils.vndComma(discItemsTotal)}', color: context.tc.danger),
                      _buildNumberRow('• Voucher / KM ($vCount lượt):', '-${FormatUtils.vndComma(vTotal)}', color: context.tc.danger),
                      _buildNumberRow('• Điểm KMT đổi ($pUsed điểm):', '-${FormatUtils.vndComma(pDisc)}', color: context.tc.danger),
                      const Divider(height: 12),
                      _buildNumberRow('TỔNG GIẢM GIÁ TRONG CA:', '-${FormatUtils.vndComma(totDisc)}', isBold: true, color: context.tc.primary),
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
                  color: context.tc.warningLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ghi chú ca: ${shift.notes}',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.warningInk),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(LucideIcons.table, size: 18, color: context.ink(const Color(0xFF137333))),
                label: Text('Xuất Excel Khuyến Mãi Ca', style: TextStyle(color: context.ink(const Color(0xFF137333)), fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF137333)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () async {
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đang chuẩn bị dữ liệu và xuất Excel...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    await _exportShiftPromotionsExcel(shift);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Lỗi xuất Excel: $e'), backgroundColor: AppColors.danger),
                      );
                    }
                  }
                },
              ),
            ),
            if (shift.isOpen && !_isOwnShift(shift) && _canViewAllShifts) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(LucideIcons.lock, size: 18, color: context.tc.danger),
                  label: Text('Đóng ca bắt buộc', style: TextStyle(color: context.tc.danger, fontWeight: FontWeight.bold)),
                  onPressed: () => _forceCloseShift(shift),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(LucideIcons.share2, size: 18),
                    label: const Text('Chia Sẻ Phiếu'),
                    onPressed: () async {
                      final text = '''
================================
${storeName.toUpperCase()}
PHIẾU BÀN GIAO CA BÁN HÀNG
Mã ca: ${shift.shiftCode}
Thu ngân: ${shift.staffFullName} (${shift.staffUsername})
Mở ca: $openedStr
Kết ca: $closedStr
--------------------------------
1. Tiền mặt đầu ca: ${FormatUtils.vndComma(shift.initialCash)}
2. Bán hàng tiền mặt: ${FormatUtils.vndComma(shift.totalCashSales)}
3. Doanh thu VietQR: ${FormatUtils.vndComma(shift.totalQrSales)}
4. Nộp thêm két: ${FormatUtils.vndComma(shift.cashIn)}
5. Chi vặt két: ${FormatUtils.vndComma(shift.cashOut)}
--------------------------------
TỔNG DOANH THU: ${FormatUtils.vndComma(shift.totalRevenue)}
TIỀN KIỂM ĐẾM THỰC TẾ: ${FormatUtils.vndComma(shift.actualCash ?? 0)}
${_canViewDifference ? "CHÊNH LỆCH: ${FormatUtils.vndComma(shift.difference ?? 0)}" : ""}
Ghi chú: ${shift.notes}
================================
''';
                      try {
                        await shareTextSafe(text, subject: 'Phiếu bàn giao ca ${shift.shiftCode}', context: context);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Không mở được hộp chia sẻ: $e'), backgroundColor: AppColors.danger),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(LucideIcons.printer, size: 18),
                    label: const Text('In Phiếu Bàn Giao'),
                    style: ElevatedButton.styleFrom(backgroundColor: context.tc.primary),
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Đã gửi lệnh in phiếu bàn giao ca ${shift.shiftCode} tới máy in nhiệt.'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
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
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
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
              color: color ?? context.tc.textPrimary,
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
      backgroundColor: context.tc.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _canViewDifference ? 'Phiếu Bàn Giao Ca' : 'Ca Của Tôi',
              style: GoogleFonts.beVietnamPro(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              _canViewDifference ? 'Xem phiên giao két & chênh lệch của nhân viên' : 'Lịch sử ca làm việc của riêng bạn',
              style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.calendarDays),
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
              icon: const Icon(LucideIcons.x, size: 20),
              tooltip: 'Xóa lọc ngày',
              onPressed: () => setState(() => _selectedDate = null),
            ),
        ],
      ),
      body: Column(
        children: [
          // Chủ/quản lý: lọc ca theo tài khoản
          if (_canViewAllShifts) _buildOwnerFilter(),

          // Search & Filter Row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm theo mã ca, tên nhân viên...',
                      prefixIcon: const Icon(LucideIcons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: context.tc.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: context.tc.borderLight),
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: context.tc.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.tc.borderLight),
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
                  Icon(LucideIcons.funnel, size: 14, color: context.tc.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Đang lọc ngày: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.tc.primary,
                    ),
                  ),
                ],
              ),
            ),

          // List of shifts
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      final list = await _fb.getRecentCashShifts(forceRefresh: true);
                      if (mounted) {
                        setState(() {
                          _shifts = list;
                          _loading = false;
                        });
                      }
                    },
                    child: filtered.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(LucideIcons.receiptText, size: 56, color: context.tc.textHint),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Không tìm thấy phiên giao két nào',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 14,
                                        color: context.tc.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final shift = filtered[i];
                              return _buildShiftCard(shift);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerFilter() {
    final owners = <String, String>{}; // username -> tên hiển thị
    for (final s in _shifts) {
      if (s.staffUsername.isEmpty) continue;
      owners[s.staffUsername] = s.staffFullName.isNotEmpty ? '${s.staffFullName} (${s.staffUsername})' : s.staffUsername;
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.tc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.tc.borderLight),
      ),
      child: DropdownButton<String?>(
        isExpanded: true,
        value: owners.containsKey(_ownerFilter) ? _ownerFilter : null,
        underline: const SizedBox(),
        hint: const Text('Tất cả tài khoản'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Tất cả tài khoản')),
          for (final e in owners.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() => _ownerFilter = v),
      ),
    );
  }

  bool _isOwnShift(CashShiftModel s) {
    final id = _fb.shiftIdentity;
    return shiftOwnedBy(s, uid: id.uid, username: id.username);
  }

  /// Đóng bắt buộc ca của tài khoản khác (chủ/quản lý): nhập tiền kiểm đếm + ghi chú, có nhật ký kiểm toán.
  Future<void> _forceCloseShift(CashShiftModel shift) async {
    final cashCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đóng ca bắt buộc'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ca ${shift.shiftCode} của ${shift.staffFullName} (${shift.staffUsername}) sẽ bị đóng. Thao tác được ghi vào nhật ký.'),
            const SizedBox(height: 12),
            TextField(
              controller: cashCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                ThousandsSeparatorInputFormatter(),
              ],
              decoration: const InputDecoration(labelText: 'Tiền mặt kiểm đếm thực tế', suffixText: 'đ'),
            ),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Lý do đóng ca')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đóng ca')),
        ],
      ),
    );
    final actual = resolveActualCash(input: cashCtrl.text, expectedCash: shift.expectedCash, canViewHandover: true);
    final note = 'Đóng bắt buộc: ${noteCtrl.text.trim()}';
    cashCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true || actual == null) return;
    try {
      await _fb.closeCashShift(shift, actual, note);
      if (!mounted) return;
      Navigator.of(context).maybePop(); // đóng bảng chi tiết
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã đóng ca ${shift.shiftCode}'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không đóng được ca: $e'), backgroundColor: AppColors.danger));
    }
  }

  /// Chi tiết ca cho tài khoản KHÔNG có quyền xem phiếu bàn giao: chỉ doanh số + số tiền mình đã kiểm đếm.
  Widget _buildMyShiftSummary(CashShiftModel shift) {
    final openedStr = DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(shift.openedAt));
    final closedStr = shift.closedAt != null
        ? DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(shift.closedAt!))
        : 'Đang mở';
    return Container(
      decoration: BoxDecoration(
        color: context.tc.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('CA CỦA TÔI', style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold, color: context.tc.primary)),
          const SizedBox(height: 12),
          _buildSlipMetaRow('Mã ca:', shift.shiftCode),
          _buildSlipMetaRow('Giờ mở ca:', openedStr),
          _buildSlipMetaRow('Giờ kết ca:', closedStr),
          const Divider(height: 20),
          _buildNumberRow('Tổng doanh số ca:', FormatUtils.vndComma(shift.totalRevenue), isBold: true),
          if (!shift.isOpen) _buildNumberRow('Tiền mặt tôi đã kiểm đếm:', FormatUtils.vndComma(shift.actualCash ?? 0)),
          const SizedBox(height: 8),
          Text(
            'Phiếu bàn giao và số đối soát két chỉ dành cho Quản lý.',
            style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
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
        color: context.tc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.tc.borderLight),
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
                                ? context.tc.successLight
                                : context.tc.cardElevated,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            LucideIcons.calculator,
                            size: 18,
                            color: shift.isOpen ? context.tc.success : context.tc.textSecondary,
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
                                color: context.tc.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: shift.isOpen ? context.tc.success : context.tc.borderLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        shift.isOpen ? 'ĐANG MỞ' : 'ĐÃ KẾT CA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: shift.isOpen ? Colors.white : context.tc.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Thời gian: $openedStr ➔ $closedStr',
                  style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
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
                                fontSize: 11, color: context.tc.textSecondary)),
                        Text(
                          FormatUtils.vndComma(shift.totalRevenue),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: context.tc.primary,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tiền đếm thực tế',
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 11, color: context.tc.textSecondary)),
                        Text(
                          shift.isOpen
                              ? 'Đang bán...'
                              : FormatUtils.vndComma(shift.actualCash ?? 0),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (_canViewDifference)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Chênh lệch',
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 11, color: context.tc.textSecondary)),
                        if (!_canViewDifference && !shift.isOpen)
                          Text('••••••',
                              style: GoogleFonts.beVietnamPro(
                                  fontSize: 13, fontWeight: FontWeight.bold, color: context.tc.textHint))
                        else if (shift.isOpen)
                          Text('Chưa chốt',
                              style: GoogleFonts.beVietnamPro(
                                  fontSize: 12, color: context.tc.textSecondary))
                        else
                          Text(
                            '${diff >= 0 ? "+" : ""}${FormatUtils.vndComma(diff)}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: diff == 0
                                  ? context.tc.success
                                  : (diff > 0 ? context.tc.info : context.tc.danger),
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
                        color: context.tc.primary,
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
