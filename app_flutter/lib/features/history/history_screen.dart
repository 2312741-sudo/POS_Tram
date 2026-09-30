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

  List<BillModel> _currentFiltered = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch Sử Hóa Đơn Đã Thanh Toán'),
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
            // Only paid bills
            if (b.status != 'PAID') return false;

            // Date match
            final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
            if (dt.year != _selectedDate.year || dt.month != _selectedDate.month || dt.day != _selectedDate.day) {
              return false;
            }

            // Payment method match
            if (_selectedPaymentMethod != 'ALL' && b.paymentMethod != _selectedPaymentMethod) {
              return false;
            }

            // Search by code, table, or staff
            if (_search.isNotEmpty) {
              final q = _search.toLowerCase();
              final match = b.billCode.toLowerCase().contains(q) ||
                  b.tableName.toLowerCase().contains(q) ||
                  b.staffFullName.toLowerCase().contains(q) ||
                  b.staffUsername.toLowerCase().contains(q);
              if (!match) return false;
            }

            return true;
          }).toList();
          _currentFiltered = filtered;

          final totalRevenue = filtered.fold<int>(0, (s, b) => s + b.finalAmount);
          final totalDiscounts = filtered.fold<int>(0, (s, b) => s + b.totalDiscount);

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
                              hintText: 'Tìm mã HD, bàn, thu ngân...',
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
                    const SizedBox(height: 10),
                    // Revenue summary bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Đã bán: ${filtered.length} hóa đơn', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryDark)),
                          if (totalDiscounts > 0)
                            Text('Khuyến mãi: -${FormatUtils.vnd(totalDiscounts)}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.danger)),
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
                        child: Text('Không có hóa đơn nào trong ngày này', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
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
    final methodStr = bill.paymentMethod == 'TRANSFER_QR'
        ? 'VietQR'
        : bill.paymentMethod == 'CARD'
            ? 'Thẻ'
            : 'Tiền mặt';

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.successLight, shape: BoxShape.circle),
          child: const Icon(Icons.receipt_long, color: AppColors.success, size: 20),
        ),
        title: Row(
          children: [
            Text(bill.billCode, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
              child: Text('${bill.tableName} (${bill.zone})', style: GoogleFonts.beVietnamPro(fontSize: 11)),
            ),
          ],
        ),
        subtitle: Text(
          'Thu ngân: ${bill.staffFullName} • ${FormatUtils.timeOnly(bill.closedAt ?? bill.createdAt)} • $methodStr',
          style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Text(
          FormatUtils.vnd(bill.finalAmount),
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
        ),
        children: [
          const Divider(),
          // Items breakdown
          ...bill.items.map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${i.name} x${i.quantity}', style: GoogleFonts.beVietnamPro(fontSize: 13)),
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

          // Reprint button
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
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
          ),
        ],
      ),
    );
  }
}
