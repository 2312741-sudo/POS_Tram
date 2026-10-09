// lib/features/history/history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/printer/receipt_printer.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  String _search = '';
  DateTime _selectedDate = DateTime.now();
  String _selectedPaymentMethod = 'ALL';
  String _selectedStatus = 'ALL'; // 'ALL', 'PAID', 'CANCELLED'

  List<BillModel> _currentFiltered = [];

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(
        '$label ($count)',
        style: GoogleFonts.beVietnamPro(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: Colors.grey.shade100,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (val) {
        if (val) setState(() => _selectedStatus = value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch Sử Hóa Đơn'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Xuất Báo Cáo Excel (Trạm)',
            onPressed: () async {
              if (_currentFiltered.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Không có hóa đơn nào để xuất!')),
                );
                return;
              }
              final storeName = _auth.currentStoreInfo?.storeName ?? 'TramFnB';
              final path = await _fb.exportReportExcel(
                storeName: storeName,
                reportType: 'HoaDon',
                bills: _currentFiltered,
              );
              if (mounted) {
                if (path != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã xuất file Excel: $path'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Xuất báo cáo thất bại!')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<BillModel>>(
        stream: _fb.billsStream(),
        initialData: const [],
        builder: (context, snapshot) {
          final allBills = snapshot.data ?? [];
          final filtered = allBills.where((b) {
            // Status match
            if (_selectedStatus != 'ALL' && b.status != _selectedStatus) {
              return false;
            }

            // Date match
            final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
            if (dt.year != _selectedDate.year || dt.month != _selectedDate.month || dt.day != _selectedDate.day) {
              return false;
            }

            // Payment method match
            if (_selectedPaymentMethod != 'ALL' && b.paymentMethod != _selectedPaymentMethod) {
              return false;
            }

            // Search by code, orderCode, table, or staff
            if (_search.isNotEmpty) {
              final q = _search.toLowerCase();
              final match = b.billCode.toLowerCase().contains(q) ||
                  (b.orderCode != null && b.orderCode!.toLowerCase().contains(q)) ||
                  b.tableName.toLowerCase().contains(q) ||
                  b.staffFullName.toLowerCase().contains(q) ||
                  b.staffUsername.toLowerCase().contains(q);
              if (!match) return false;
            }

            return true;
          }).toList();
          _currentFiltered = filtered;

          final paidBills = filtered.where((b) => b.status == 'PAID').toList();
          final cancelledBills = filtered.where((b) => b.status == 'CANCELLED').toList();
          final totalRevenue = paidBills.fold<int>(0, (s, b) => s + b.finalAmount);
          final totalDiscounts = paidBills.fold<int>(0, (s, b) => s + b.totalDiscount);

          return Column(
            children: [
              // Filter Toolbar
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Tìm mã HD, mã đơn, bàn, thu ngân...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setState(() => _selectedDate = picked);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Status filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('Tất cả', 'ALL', filtered.length),
                          const SizedBox(width: 6),
                          _buildFilterChip('Đã thanh toán', 'PAID', paidBills.length),
                          const SizedBox(width: 6),
                          _buildFilterChip('Đã hủy', 'CANCELLED', cancelledBills.length),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Revenue summary bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Bán: ${paidBills.length}${cancelledBills.isNotEmpty ? " • Hủy: ${cancelledBills.length}" : ""}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryDark)),
                          if (totalDiscounts > 0)
                            Text('KM: -${FormatUtils.vnd(totalDiscounts)}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.danger)),
                          Text('Doanh thu: ${FormatUtils.vnd(totalRevenue)}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryDark)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Bills List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('Không có hóa đơn nào', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final bill = filtered[index];
                          return _buildBillCard(bill);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBillCard(BillModel bill) {
    final isCancelled = bill.status == 'CANCELLED';
    final methodStr = bill.paymentMethod == 'TRANSFER_QR'
        ? 'VietQR'
        : bill.paymentMethod == 'CARD'
            ? 'Thẻ'
            : 'Tiền mặt';
    final hasTable = bill.tableName.trim().isNotEmpty;
    final tableText = hasTable
        ? '${bill.tableName}${bill.zone.trim().isNotEmpty ? " (${bill.zone})" : ""}'
        : 'Mang về';
    final showOrderCode = bill.orderCode != null &&
        bill.orderCode!.trim().isNotEmpty &&
        bill.orderCode != bill.billCode;

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isCancelled ? Colors.red.shade50 : AppColors.successLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCancelled ? Icons.cancel_outlined : Icons.receipt_long,
            color: isCancelled ? AppColors.danger : AppColors.success,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              bill.billCode,
              style: GoogleFonts.beVietnamPro(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isCancelled ? Colors.grey : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isCancelled ? Colors.red.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tableText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: isCancelled ? AppColors.danger : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            if (isCancelled) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'HỦY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${showOrderCode ? "Đơn: ${bill.orderCode} • " : ""}Thu ngân: ${bill.staffFullName} • ${FormatUtils.timeOnly(bill.closedAt ?? bill.createdAt)} • $methodStr',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              FormatUtils.vnd(bill.finalAmount),
              style: GoogleFonts.beVietnamPro(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isCancelled ? Colors.grey : AppColors.primary,
                decoration: isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            if (isCancelled)
              Text('Đã hủy', style: GoogleFonts.beVietnamPro(fontSize: 10, color: AppColors.danger, fontWeight: FontWeight.bold)),
          ],
        ),
        children: [
          const Divider(),
          // Items breakdown
          ...bill.items.map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        '${i.name} x${i.quantity}${i.hasDiscount ? ' • ${i.discountDescription(FormatUtils.vnd)}' : ''}',
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                      ),
                    ),
                    Text(FormatUtils.vnd(i.itemTotal), style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tiền hàng:', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
              Text(FormatUtils.vnd(bill.subTotal), style: GoogleFonts.beVietnamPro(fontSize: 12)),
            ],
          ),
          if (bill.discounts.isNotEmpty) ...[
            ...bill.discounts.map((d) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(' - ${d.promoCode ?? d.description}:', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.success)),
                    Text('-${FormatUtils.vnd(d.amount)}', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.bold)),
                  ],
                )),
          ],
          if (bill.vatRate > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('VAT (${bill.vatRate.toStringAsFixed(0)}%):', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
                Text('+${FormatUtils.vnd(bill.vatAmount)}', style: GoogleFonts.beVietnamPro(fontSize: 12)),
              ],
            ),
          const SizedBox(height: 12),

          // Action buttons: Cancel / Delete and Reprint
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Hủy / Xóa hóa đơn button
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                icon: Icon(
                  isCancelled ? Icons.delete_forever : Icons.cancel_outlined,
                  size: 16,
                ),
                label: Text(
                  isCancelled ? 'Xóa hóa đơn' : 'Hủy hóa đơn',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _showCancelOrDeleteBillDialog(context, bill),
              ),

              // Reprint button
              OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('In lại hóa đơn'),
                onPressed: () async {
                  if (!_auth.can(AppPermissions.reprintBill)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bạn không có quyền in lại hóa đơn!'), backgroundColor: AppColors.danger),
                    );
                    return;
                  }

                  final store = await _fb.getStoreInfo();
                  final bytes = ReceiptPrinter.buildBillReceiptBytes(store: store, bill: bill, isPrePrint: false);
                  await ReceiptPrinter.printViaLan(printerIp: store.billPrinterIp, data: bytes);

                  // Audit log for reprint
                  await _fb.logAction(AuditLogModel(
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                    username: _auth.currentUser?.username ?? 'staff',
                    userFullName: _auth.currentUser?.fullName ?? 'Thu Ngân',
                    userRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
                    action: 'REPRINT_BILL',
                    targetType: 'BILL',
                    targetId: bill.billCode,
                    details: 'In lại hóa đơn ${bill.billCode} bàn ${bill.tableName}',
                    isSuspicious: true,
                  ));

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi lệnh in lại bill!')));
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCancelOrDeleteBillDialog(BuildContext context, BillModel bill) async {
    if (!_auth.can(AppPermissions.cancelBill)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn không có quyền hủy hoặc xóa hóa đơn!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final reasonCtrl = TextEditingController();
    final quickReasons = [
      'Khách đổi ý hủy món',
      'Nhập nhầm bàn / nhầm món',
      'Thu ngân tính nhầm tiền',
      'Hóa đơn thử nghiệm / test',
      'Khách không đủ tiền thanh toán',
    ];
    String selectedReason = quickReasons.first;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bill.status == 'CANCELLED' ? 'Xóa Hóa Đơn Khỏi Hệ Thống' : 'Hủy / Xóa Hóa Đơn',
                  style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Mã HĐ: ${bill.billCode}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryDark)),
                          Text(bill.status == 'CANCELLED' ? 'ĐÃ HỦY' : 'ĐÃ THANH TOÁN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: bill.status == 'CANCELLED' ? AppColors.danger : AppColors.success)),
                        ],
                      ),
                      if (bill.orderCode != null && bill.orderCode!.isNotEmpty)
                        Text('Mã đặt món: ${bill.orderCode}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.blueGrey)),
                      const SizedBox(height: 4),
                      Text('Bàn: ${bill.tableName} (${bill.zone}) • Tổng tiền: ${FormatUtils.vnd(bill.finalAmount)}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('Thu ngân: ${bill.staffFullName} • ${FormatUtils.timeOnly(bill.closedAt ?? bill.createdAt)}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Lý do hủy / xóa *:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: quickReasons.map((r) {
                    final isSel = selectedReason == r;
                    return ChoiceChip(
                      label: Text(r, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : AppColors.textPrimary)),
                      selected: isSel,
                      selectedColor: AppColors.danger,
                      backgroundColor: Colors.grey.shade100,
                      onSelected: (val) {
                        if (val) {
                          setDlgState(() {
                            selectedReason = r;
                            reasonCtrl.text = r;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    hintText: 'Nhập chi tiết lý do...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
            if (bill.status != 'CANCELLED')
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Hủy hóa đơn'),
                onPressed: () async {
                  final reason = reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : selectedReason;
                  Navigator.pop(ctx);
                  await _fb.cancelPaidBill(
                    bill: bill,
                    reason: reason,
                    staffUsername: _auth.currentUser?.username ?? 'staff',
                    staffFullName: _auth.currentUser?.fullName ?? 'Thu Ngân',
                    staffRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã hủy hóa đơn ${bill.billCode}!'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                },
              ),
            // Tùy chọn Xóa vĩnh viễn (Chủ quán hoặc quản lý cấp cao)
            if (_auth.isRootOwner || _auth.isOwner || _auth.can(AppPermissions.cancelBill))
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade800,
                  side: BorderSide(color: Colors.red.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text('Xóa hẳn khỏi máy'),
                onPressed: () async {
                  final reason = reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : selectedReason;
                  Navigator.pop(ctx);
                  await _fb.deleteBill(
                    bill: bill,
                    reason: reason,
                    staffUsername: _auth.currentUser?.username ?? 'staff',
                    staffFullName: _auth.currentUser?.fullName ?? 'Thu Ngân',
                    staffRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã xóa vĩnh viễn hóa đơn ${bill.billCode}!'),
                        backgroundColor: Colors.black87,
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
