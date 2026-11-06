// lib/features/history/history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../manager/widgets/bill_detail_sheet.dart';
import '../../core/domain/business_day.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  String _search = '';
  Set<String>? _activeUsernames; // null = chưa tải được → không lọc tài khoản đã xóa
  String? _staffFilter; // chủ/quản lý: lọc theo tài khoản thu tiền
  DateTime _selectedDate = BusinessDay.now();
  final String _selectedPaymentMethod = 'ALL';
  String _selectedStatus = 'ALL'; // 'ALL', 'PAID', 'CANCELLED'

  List<BillModel> _currentFiltered = [];

  @override
  void initState() {
    super.initState();
    if (_auth.canViewAllBillsHistory) _loadActiveUsernames();
  }

  Future<void> _loadActiveUsernames() async {
    try {
      final users = await _fb.getUsers();
      if (!mounted || users.isEmpty) return;
      setState(() => _activeUsernames = {for (final u in users) u.username.trim().toLowerCase()});
    } catch (_) {}
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(
        '$label ($count)',
        style: GoogleFonts.beVietnamPro(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : context.tc.textPrimary,
        ),
      ),
      selected: isSelected,
      selectedColor: context.tc.primary,
      backgroundColor: context.tc.cardElevated,
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
            icon: const Icon(LucideIcons.download),
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
              if (context.mounted) {
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
        stream: _fb.myBillsStream(),
        initialData: const [],
        builder: (context, snapshot) {
          final streamBills = snapshot.data ?? [];
          // Nhân viên chỉ thấy HĐ của mình; chủ/quản lý (VIEW_ALL_BILLS_HISTORY) thấy hết + lọc theo tài khoản
          final allBills = _fb.scopeVisibleBills(streamBills, filterUsername: _staffFilter);
          final activeUsers = _activeUsernames;
          final staffOptions = <String, String>{
            for (final b in streamBills)
              if (b.staffUsername.isNotEmpty && (activeUsers == null || activeUsers.contains(b.staffUsername.trim().toLowerCase())))
                b.staffUsername: b.staffFullName.isNotEmpty ? '${b.staffFullName} (${b.staffUsername})' : b.staffUsername,
          };
          final filtered = allBills.where((b) {
            // Status match
            if (_selectedStatus != 'ALL' && b.status != _selectedStatus) {
              return false;
            }

            // Date match
            final dt = DateTime.fromMillisecondsSinceEpoch(b.businessTimeMs); // ngày kinh doanh
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
                color: context.tc.card,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Tìm mã HD, mã đơn, bàn, thu ngân...',
                              prefixIcon: const Icon(LucideIcons.search, size: 20),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, AppSpacing.minTapTarget)),
                          icon: const Icon(LucideIcons.calendar, size: 16),
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
                          _buildFilterChip('Hoàn thành', 'PAID', paidBills.length),
                          const SizedBox(width: 6),
                          _buildFilterChip('Đã hủy', 'CANCELLED', cancelledBills.length),
                        ],
                      ),
                    ),
                    if (_auth.canViewAllBillsHistory && staffOptions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButton<String?>(
                        isExpanded: true,
                        isDense: true,
                        value: staffOptions.containsKey(_staffFilter) ? _staffFilter : null,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Tất cả tài khoản')),
                          for (final e in staffOptions.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => _staffFilter = v),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Revenue summary bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: context.tc.primaryLight, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: Text('Bán: ${paidBills.length}${cancelledBills.isNotEmpty ? " • Hủy: ${cancelledBills.length}" : ""}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 12, color: context.tc.primaryDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (totalDiscounts > 0)
                            Text('KM: -${FormatUtils.vnd(totalDiscounts)}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.danger)),
                          Flexible(child: Text('Doanh thu: ${FormatUtils.vnd(totalRevenue)}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13, color: context.tc.primaryDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
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
                        child: Text('Không có hóa đơn nào', style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary)),
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

    // Bấm vào mở bảng chi tiết hóa đơn đầy đủ (giống tài khoản Quản lý / Chủ quán)
    return Card(
      child: ListTile(
        onTap: () => BillDetailSheet.show(context, bill),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isCancelled ? context.bg(Colors.red.shade50) : context.tc.successLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCancelled ? LucideIcons.circleX : LucideIcons.receiptText,
            color: isCancelled ? context.tc.danger : context.tc.success,
            size: 20,
          ),
        ),
        // Mã hóa đơn hiển thị đầy đủ (không cắt bớt)
        title: Text(
          bill.billCode,
          style: GoogleFonts.beVietnamPro(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isCancelled ? context.tc.textHint : context.tc.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCancelled ? context.bg(Colors.red.shade50) : context.tc.cardElevated,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tableText,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: isCancelled ? context.tc.danger : context.tc.textPrimary,
                      ),
                    ),
                  ),
                  if (isCancelled)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: context.tc.danger, borderRadius: BorderRadius.circular(4)),
                      child: const Text('HỦY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${showOrderCode ? "Đơn: ${bill.orderCode} • " : ""}Thu ngân: ${bill.staffFullName} • ${FormatUtils.timeOnly(bill.reportTimeMs)} • $methodStr',
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
              ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              FormatUtils.vnd(bill.finalAmount),
              style: GoogleFonts.beVietnamPro(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isCancelled ? context.tc.textHint : context.tc.primary,
                decoration: isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            Text(
              isCancelled ? 'Đã hủy' : (bill.status == 'PAID' ? 'Hoàn thành' : bill.status),
              style: GoogleFonts.beVietnamPro(fontSize: 10, color: isCancelled ? context.tc.danger : context.tc.success, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
