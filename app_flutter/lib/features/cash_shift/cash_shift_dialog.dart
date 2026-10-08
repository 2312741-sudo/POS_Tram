// lib/features/cash_shift/cash_shift_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import 'cash_shifts_screen.dart';

class CashShiftDialog extends StatefulWidget {
  const CashShiftDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const CashShiftDialog(),
    );
  }

  @override
  State<CashShiftDialog> createState() => _CashShiftDialogState();
}

class _CashShiftDialogState extends State<CashShiftDialog> with SingleTickerProviderStateMixin {
  final _fb = FirebaseService();
  final _auth = AuthService();

  CashShiftModel? _currentShift;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _allowStaffViewDifference = true;
  late TabController _tabController;
  StreamSubscription<List<CashShiftModel>>? _shiftSub;
  StreamSubscription<List<BillModel>>? _billsSub;
  List<BillModel> _shiftBills = [];

  final _initialCashCtrl = TextEditingController(text: '1000000');
  final _adjustAmountCtrl = TextEditingController();
  final _adjustReasonCtrl = TextEditingController();
  final _actualCashCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

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

  Map<String, dynamic> _computeShiftPromoStats() {
    if (_currentShift == null) return {};
    final shift = _currentShift!;
    final bills = _shiftBills.where((b) {
      if (b.status != 'PAID') return false;
      if (b.shiftId != null && b.shiftId!.isNotEmpty) {
        return b.shiftId == shift.id || b.shiftId == shift.shiftCode;
      }
      final closeT = shift.closedAt ?? 9999999999999;
      return b.createdAt >= shift.openedAt && b.createdAt <= closeT;
    }).toList();

    int discountedItemsCount = 0;
    int discountedItemsTotal = 0;
    int voucherCount = 0;
    int voucherTotal = 0;
    int pointsUsedTotal = 0;
    int pointsDiscountTotal = 0;

    for (final b in bills) {
      for (final it in b.items) {
        if (it.discountAmount > 0) {
          discountedItemsCount += it.quantity;
          discountedItemsTotal += it.discountAmount;
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
    };
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Instant cache-first initialization to prevent UI lag
    final cached = _fb.activeShiftCache;
    if (cached != null && cached.isOpen) {
      _currentShift = cached;
      _isLoading = false;
      if (_canViewDifference) {
        _actualCashCtrl.text = cached.expectedCash.toString();
      }
    } else {
      _currentShift = null;
      _isLoading = true;
    }

    // Real-time synchronization with Firebase Realtime Database
    _shiftSub = _fb.cashShiftsStream().listen((shifts) {
      if (!mounted) return;
      final openShift = shifts.where((s) => s.isOpen).firstOrNull ?? _fb.activeShiftCache;
      setState(() {
        if (openShift != null && openShift.isOpen) {
          _currentShift = openShift;
          if (_actualCashCtrl.text.isEmpty && _canViewDifference) {
            _actualCashCtrl.text = openShift.expectedCash.toString();
          }
        } else {
          _currentShift = null;
        }
        _isLoading = false;
      });
    });

    _billsSub = _fb.billsStream().listen((bills) {
      if (!mounted) return;
      setState(() {
        _shiftBills = bills;
      });
    });

    _loadShift();
  }

  @override
  void dispose() {
    _shiftSub?.cancel();
    _billsSub?.cancel();
    _tabController.dispose();
    _initialCashCtrl.dispose();
    _adjustAmountCtrl.dispose();
    _adjustReasonCtrl.dispose();
    _actualCashCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShift() async {
    try {
      final storeInfo = await _fb.getStoreInfo();
      _allowStaffViewDifference = storeInfo.allowStaffViewShiftDifference;
    } catch (_) {}

    final shift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
    if (mounted) {
      setState(() {
        if (shift != null && shift.isOpen) {
          _currentShift = shift;
          if (_canViewDifference) {
            _actualCashCtrl.text = shift.expectedCash.toString();
          } else {
            _actualCashCtrl.text = '';
          }
        } else if (_currentShift == null) {
          _currentShift = null;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _openShift() async {
    if (_isSubmitting) return;
    final initial = int.tryParse(_initialCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final now = DateTime.now();
    final shiftCode = 'CA-${DateFormat('yyMMdd-HHmm').format(now)}';

    setState(() => _isSubmitting = true);

    final newShift = CashShiftModel(
      id: 'SHIFT_${now.millisecondsSinceEpoch}',
      shiftCode: shiftCode,
      storeCode: _auth.currentStoreCode,
      staffUsername: _auth.currentUser?.username ?? 'staff',
      staffFullName: _auth.currentUser?.fullName ?? 'Thu Ngân',
      openedAt: now.millisecondsSinceEpoch,
      initialCash: initial,
    );

    try {
      await _fb.openCashShift(newShift);
    } catch (e) {
      _showShiftError(e);
      return;
    }
    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _currentShift = newShift;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã mở ca $shiftCode thành công! Tiền két đầu ca: ${FormatUtils.vnd(initial)}'),
          backgroundColor: TramColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  void _showShiftError(Object e) {
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lỗi lưu ca: $e'), backgroundColor: AppColors.danger),
    );
  }

  Future<void> _addAdjustment(bool isCashIn) async {
    if (_currentShift == null || _isSubmitting) return;
    final amount = int.tryParse(_adjustAmountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final reason = _adjustReasonCtrl.text.trim();
    if (amount <= 0 || reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập số tiền và lý do rõ ràng')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _fb.addCashShiftAdjustment(
        shiftId: _currentShift!.id,
        amount: amount,
        isCashIn: isCashIn,
        reason: reason,
      );
    } catch (e) {
      _showShiftError(e);
      return;
    }

    _adjustAmountCtrl.clear();
    _adjustReasonCtrl.clear();
    await _loadShift();
    if (mounted) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isCashIn ? "Đã nộp thêm" : "Đã chi vặt"} ${FormatUtils.vnd(amount)}'),
          backgroundColor: isCashIn ? TramColors.success : TramColors.warningInk,
        ),
      );
    }
  }

  Future<void> _closeShift() async {
    if (_currentShift == null || _isSubmitting) return;
    final shiftToClose = _currentShift!;
    final actual = int.tryParse(_actualCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? shiftToClose.expectedCash;
    final notes = _notesCtrl.text.trim();

    setState(() => _isSubmitting = true);

    try {
      await _fb.closeCashShift(shiftToClose, actual, notes);
    } catch (e) {
      _showShiftError(e);
      return;
    }
    final diff = actual - shiftToClose.expectedCash;

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _currentShift = null;
      });
      Navigator.pop(context, false);
      if (_canViewDifference) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Đã Chốt Ca Thành Công', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mã ca: ${shiftToClose.shiftCode}'),
                const SizedBox(height: 6),
                Text('Doanh thu ca: ${FormatUtils.vnd(shiftToClose.totalRevenue)}'),
                const SizedBox(height: 6),
                Text('Tiền két kỳ vọng: ${FormatUtils.vnd(shiftToClose.expectedCash)}'),
                const SizedBox(height: 6),
                Text('Tiền kiểm đếm thực tế: ${FormatUtils.vnd(actual)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Chênh lệch: ${diff >= 0 ? "+" : ""}${FormatUtils.vnd(diff)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: diff == 0 ? TramColors.success : (diff > 0 ? TramColors.info : TramColors.danger),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(ctx, MaterialPageRoute(builder: (_) => const CashShiftsScreen()));
                },
                child: const Text('Xem phiếu bàn giao'),
              ),
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Bàn Giao Ca Thành Công', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mã ca: ${shiftToClose.shiftCode}'),
                const SizedBox(height: 6),
                Text('Thu ngân: ${shiftToClose.staffFullName}'),
                const SizedBox(height: 6),
                Text('Tiền thực tế bàn giao: ${FormatUtils.vnd(actual)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: TramColors.infoSurface, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    'Đã lưu thông tin bàn giao ca. Quản lý sẽ kiểm đếm đối soát số dư két.',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.info),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hoàn tất')),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasOpenShift = _currentShift != null && _currentShift!.isOpen;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: _isLoading
          ? const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()))
          : !hasOpenShift
              ? _buildOpenShiftView()
              : _buildShiftManagerView(),
    );
  }

  Widget _buildOpenShiftView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: TramColors.warningSurface, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.lock_open_rounded, color: TramColors.warningInk, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mở Ca Bán Hàng & Két Tiền', style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    'Khai báo tiền mặt đầu ca để bắt đầu nhận đơn',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _initialCashCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Tiền mặt đầu ca trong két (VND)',
            prefixIcon: const Icon(Icons.attach_money),
            suffixText: 'đ',
            suffixIcon: _initialCashCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      setState(() {
                        _initialCashCtrl.clear();
                      });
                    },
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [0, 500000, 1000000, 2000000, 3000000, 5000000].map((amt) {
            return ActionChip(
              backgroundColor: TramColors.primaryLight.withValues(alpha: 0.4),
              label: Text(
                FormatUtils.vnd(amt),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: TramColors.primaryDark),
              ),
              onPressed: () {
                setState(() {
                  _initialCashCtrl.text = amt.toString();
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            icon: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline),
            label: Text(_isSubmitting ? 'Đang kích hoạt ca...' : 'Bắt Đầu Ca Làm Việc'),
            style: ElevatedButton.styleFrom(backgroundColor: TramColors.brandPrimary),
            onPressed: _isSubmitting ? null : _openShift,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CashShiftsScreen()));
            },
            icon: const Icon(Icons.history, size: 16, color: TramColors.brandPrimary),
            label: Text(
              'Xem lịch sử các ca trước đó ›',
              style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShiftManagerView() {
    final shift = _currentShift!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: shift.isOpen ? TramColors.successSurface : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.point_of_sale,
                      color: shift.isOpen ? TramColors.success : TramColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shift.shiftCode,
                          style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'NV: ${shift.staffFullName} • Mở lúc ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(shift.openedAt))}',
                          style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: shift.isOpen ? TramColors.success : TramColors.textSecondary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                shift.isOpen ? 'ĐANG MỞ' : 'ĐÃ ĐÓNG',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CashShiftsScreen()));
              },
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, size: 16, color: TramColors.brandPrimary),
                  const SizedBox(width: 4),
                  Text(
                    'Xem tất cả phiếu giao ca ›',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: TramColors.brandPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (_isManagerOrOwner)
              InkWell(
                onTap: () async {
                  final nextVal = !_allowStaffViewDifference;
                  await _fb.updateStoreShiftDifferenceSetting(nextVal);
                  setState(() => _allowStaffViewDifference = nextVal);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(nextVal
                            ? 'Đã BẬT cho phép nhân viên xem chênh lệch khi kết ca'
                            : 'Đã TẮT (Ẩn chênh lệch két đối với nhân viên)'),
                        backgroundColor: nextVal ? TramColors.success : TramColors.warningInk,
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    Icon(
                      _allowStaffViewDifference ? Icons.visibility : Icons.visibility_off,
                      size: 14,
                      color: _allowStaffViewDifference ? TramColors.success : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _allowStaffViewDifference ? 'NV xem lệch: BẬT' : 'NV xem lệch: TẮT',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _allowStaffViewDifference ? TramColors.success : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TabBar(
          controller: _tabController,
          labelColor: TramColors.brandPrimary,
          unselectedLabelColor: TramColors.textSecondary,
          indicatorColor: TramColors.brandPrimary,
          labelStyle: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Tổng Quan'),
            Tab(text: 'Thu / Chi Két'),
            Tab(text: 'Chốt Ca'),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 290,
          child: TabBarView(
            controller: _tabController,
            children: [
              // TAB 1: Tổng quan số dư két
              SingleChildScrollView(
                child: Column(
                  children: [
                    _buildStatRow('Tiền mặt đầu ca:', FormatUtils.vnd(shift.initialCash)),
                    _buildStatRow('+ Bán hàng tiền mặt:', FormatUtils.vnd(shift.totalCashSales), color: TramColors.success),
                    _buildStatRow('+ Doanh thu VietQR:', FormatUtils.vnd(shift.totalQrSales), color: TramColors.info),
                    _buildStatRow('+ Tiền nộp thêm (Cash In):', FormatUtils.vnd(shift.cashIn)),
                    _buildStatRow('- Tiền chi vặt (Cash Out):', FormatUtils.vnd(shift.cashOut), color: TramColors.danger),
                    const Divider(height: 20),
                    if (_canViewDifference)
                      _buildStatRow('TIỀN MẶT TRONG KÉT HIỆN TẠI:', FormatUtils.vnd(shift.expectedCash), isBold: true, color: TramColors.brandPrimary)
                    else
                      _buildStatRow('TIỀN MẶT TRONG KÉT HIỆN TẠI:', '•••••• (Chỉ Quản lý)', isBold: true, color: Colors.grey),
                    _buildStatRow('TỔNG DOANH SỐ CA:', FormatUtils.vnd(shift.totalRevenue), isBold: true),
                    Builder(
                      builder: (ctx) {
                        final promo = _computeShiftPromoStats();
                        final totalPromo = (promo['totalPromoDiscount'] as int?) ?? 0;
                        if (totalPromo <= 0) return const SizedBox.shrink();
                        final dItems = promo['discountedItemsCount'] ?? 0;
                        final dItemsTotal = promo['discountedItemsTotal'] ?? 0;
                        final vCount = promo['voucherCount'] ?? 0;
                        final pUsed = promo['pointsUsedTotal'] ?? 0;

                        return Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDF5F6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFF5D5D8)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.discount_outlined, size: 14, color: Color(0xFF7E2930)),
                                  const SizedBox(width: 4),
                                  Text('Khuyến mãi ca:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF7E2930))),
                                  const Spacer(),
                                  Text('-${FormatUtils.vnd(totalPromo)}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: TramColors.danger)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$dItems món giảm (-${FormatUtils.vnd(dItemsTotal)}) • $vCount voucher • $pUsed điểm KMT',
                                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // TAB 2: Thu / Chi két tiền
              SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: _adjustAmountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Số tiền (VND)', suffixText: 'đ'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _adjustReasonCtrl,
                      decoration: const InputDecoration(labelText: 'Lý do (VD: Mua đá, Trả tiền ship, Nộp thêm tiền lẻ)'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Nộp Thêm Tiền'),
                            style: ElevatedButton.styleFrom(backgroundColor: TramColors.success),
                            onPressed: _isSubmitting ? null : () => _addAdjustment(true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('Rút / Chi Vặt'),
                            style: ElevatedButton.styleFrom(backgroundColor: TramColors.warningInk),
                            onPressed: _isSubmitting ? null : () => _addAdjustment(false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // TAB 3: Chốt két & Kết ca
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_canViewDifference)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: TramColors.warningSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: TramColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_clock, size: 16, color: TramColors.warningInk),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Kiểm đếm mù đang bật: Nhân viên tự đếm và khai báo toàn bộ tiền mặt trong két để quản lý đối soát.',
                                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.warningInk),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text('Kiểm đếm toàn bộ tiền mặt trong két và nhập số thực tế vào bên dưới:',
                          style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _actualCashCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Tiền mặt thực tế kiểm đếm (VND)', suffixText: 'đ'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(labelText: 'Ghi chú bàn giao ca'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: _isSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline),
                        label: Text(_isSubmitting ? 'Đang chốt ca...' : 'Xác Nhận Chốt Két & Kết Ca'),
                        style: ElevatedButton.styleFrom(backgroundColor: TramColors.brandPrimary),
                        onPressed: _isSubmitting ? null : _closeShift,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color ?? TramColors.textPrimary)),
        ],
      ),
    );
  }
}
