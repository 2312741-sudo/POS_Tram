// lib/features/manager/tabs/bills_tab.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/firebase_service.dart';
import '../widgets/bill_detail_sheet.dart';

class BillsTab extends StatefulWidget {
  const BillsTab({super.key});

  @override
  State<BillsTab> createState() => _BillsTabState();
}

class _BillsTabState extends State<BillsTab> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  List<BillModel> _allBills = [];
  List<TableModel> _tables = [];
  bool _loading = true;

  String _search = '';
  String _dateFilter = 'TODAY'; // 'TODAY', 'YESTERDAY', 'WEEK', 'ALL', 'CUSTOM'
  DateTime? _customDate;
  String _statusFilter = 'ALL'; // 'ALL', 'PAID', 'CANCELLED'
  String _paymentFilter = 'ALL'; // 'ALL', 'CASH', 'TRANSFER'
  String _zoneFilter = 'ALL'; // 'ALL', 'MANG_VE', or specific zone name
  String _tableFilter = 'ALL'; // 'ALL' or specific table name

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _fb.billsStream().listen((b) {
      if (mounted) {
        setState(() {
          _allBills = b;
          _loading = false;
        });
      }
    });

    _fb.tablesStream().listen((t) {
      if (mounted) {
        setState(() {
          _tables = t;
        });
      }
    }, onError: (Object e) => debugPrint('Lỗi tải danh sách bàn: $e'));
  }

  bool _isTakeaway(BillModel b) {
    final t = b.tableName.toLowerCase();
    final z = b.zone.toLowerCase();
    return t.contains('mang về') || t.contains('mang ve') || z.contains('mang về') || z.contains('mang ve');
  }

  List<String> get _availableZones {
    final set = <String>{};
    for (final t in _tables) {
      if (t.zone.isNotEmpty && !t.zone.toLowerCase().contains('mang về') && !t.zone.toLowerCase().contains('mang ve')) {
        set.add(t.zone);
      }
    }
    for (final b in _allBills) {
      if (b.zone.isNotEmpty && !b.zone.toLowerCase().contains('mang về') && !b.zone.toLowerCase().contains('mang ve')) {
        set.add(b.zone);
      }
    }
    return set.toList()..sort();
  }

  List<String> get _availableTables {
    final set = <String>{};
    for (final t in _tables) {
      if (_zoneFilter == 'ALL' || t.zone.toLowerCase() == _zoneFilter.toLowerCase()) {
        if (t.name.isNotEmpty && !t.name.toLowerCase().contains('mang về') && !t.name.toLowerCase().contains('mang ve')) {
          set.add(t.name);
        }
      }
    }
    for (final b in _allBills) {
      if (_zoneFilter == 'ALL' || b.zone.toLowerCase() == _zoneFilter.toLowerCase()) {
        if (b.tableName.isNotEmpty && !b.tableName.toLowerCase().contains('mang về') && !b.tableName.toLowerCase().contains('mang ve')) {
          set.add(b.tableName);
        }
      }
    }
    return set.toList()..sort();
  }

  List<BillModel> get _filteredBills {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    return _allBills.where((b) {
      // 1. Status Filter
      if (_statusFilter == 'PAID' && b.status != 'PAID') return false;
      if (_statusFilter == 'CANCELLED' && b.status != 'CANCELLED') return false;
      if (_statusFilter == 'ALL' && b.status != 'PAID' && b.status != 'CANCELLED') return false;

      // 2. Date Filter
      final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
      final billDay = DateTime(dt.year, dt.month, dt.day);

      if (_dateFilter == 'TODAY') {
        if (billDay != today) return false;
      } else if (_dateFilter == 'YESTERDAY') {
        if (billDay != yesterday) return false;
      } else if (_dateFilter == 'WEEK') {
        if (billDay.isBefore(weekStart)) return false;
      } else if (_dateFilter == 'THIS_MONTH') {
        if (dt.year != now.year || dt.month != now.month) return false;
      } else if (_dateFilter == 'LAST_MONTH') {
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        if (dt.year != lastMonth.year || dt.month != lastMonth.month) return false;
      } else if (_dateFilter == 'CUSTOM' && _customDate != null) {
        final cDay = DateTime(_customDate!.year, _customDate!.month, _customDate!.day);
        if (billDay != cDay) return false;
      }

      // 3. Zone and Table Filter
      if (_zoneFilter != 'ALL') {
        if (_zoneFilter == 'MANG_VE') {
          if (!_isTakeaway(b)) return false;
        } else {
          if (b.zone.toLowerCase() != _zoneFilter.toLowerCase()) return false;
        }
      }
      if (_tableFilter != 'ALL') {
        if (b.tableName.toLowerCase() != _tableFilter.toLowerCase()) return false;
      }

      // 4. Payment Filter
      if (_paymentFilter == 'CASH') {
        final m = b.paymentMethod.toLowerCase();
        if (!m.contains('cash') && !m.contains('tiền mặt')) return false;
      } else if (_paymentFilter == 'TRANSFER') {
        final m = b.paymentMethod.toLowerCase();
        if (!m.contains('transfer') && !m.contains('chuyển') && !m.contains('qr')) return false;
      }

      // 5. Search Filter
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final matchCode = b.billCode.toLowerCase().contains(q) || (b.orderCode != null && b.orderCode!.toLowerCase().contains(q));
        final matchTable = b.tableName.toLowerCase().contains(q);
        final matchZone = b.zone.toLowerCase().contains(q);
        final matchStaff = b.staffFullName.toLowerCase().contains(q) || b.staffUsername.toLowerCase().contains(q);
        final matchOrderStaff = b.orderStaffSummary.toLowerCase().contains(q);
        final matchCustomer = (b.customerName ?? '').toLowerCase().contains(q) || (b.customerPhone ?? '').contains(q);

        if (!matchCode && !matchTable && !matchZone && !matchStaff && !matchOrderStaff && !matchCustomer) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? DateTime.now(),
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dateFilter = 'CUSTOM';
        _customDate = picked;
      });
    }
  }

  Future<void> _exportFilteredExcel() async {
    final bills = _filteredBills;
    if (bills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có hóa đơn nào để xuất!')),
      );
      return;
    }
    final storeName = _auth.currentStoreInfo?.storeName ?? 'TramFnB';
    final path = await _fb.exportReportExcel(
      storeName: storeName,
      reportType: 'HoaDon_$_dateFilter',
      bills: bills,
    );
    if (path != null) {
      await Share.shareXFiles([XFile(path)], text: 'Báo cáo danh sách hóa đơn - $storeName');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xuất báo cáo thất bại!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _allBills.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: TramColors.brandPrimary));
    }

    final filtered = _filteredBills;
    final paidBills = filtered.where((b) => b.status != 'CANCELLED').toList();
    final cancelledBills = filtered.where((b) => b.status == 'CANCELLED').toList();
    final totalAmount = paidBills.fold(0, (s, b) => s + b.finalAmount);
    final takeawayBills = paidBills.where(_isTakeaway).toList();
    final takeawayCount = takeawayBills.length;
    final takeawayRevenue = takeawayBills.fold(0, (s, b) => s + b.finalAmount);

    return RefreshIndicator(
      color: TramColors.brandPrimary,
      onRefresh: () async {
        setState(() {});
      },
      child: Column(
        children: [
          // Filter & Search Header Box
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: Colors.white,
            child: Column(
              children: [
                // Search Input
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm theo mã bill, bàn, thu ngân, người order...',
                    hintStyle: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search, size: 20, color: TramColors.brandPrimary),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _search = ''),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: TramColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: TramColors.borderLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: TramColors.borderLight),
                    ),
                  ),
                  onChanged: (val) => setState(() => _search = val.trim()),
                ),
                const SizedBox(height: 10),

                // Date Filters Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDateChip('Hôm nay', 'TODAY'),
                      const SizedBox(width: 8),
                      _buildDateChip('Hôm qua', 'YESTERDAY'),
                      const SizedBox(width: 8),
                      _buildDateChip('Tuần này', 'WEEK'),
                      const SizedBox(width: 8),
                      _buildDateChip('Tháng này', 'THIS_MONTH'),
                      const SizedBox(width: 8),
                      _buildDateChip('Tháng trước', 'LAST_MONTH'),
                      const SizedBox(width: 8),
                      _buildDateChip('Tất cả', 'ALL'),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _pickCustomDate,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _dateFilter == 'CUSTOM' ? TramColors.brandPrimary : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _dateFilter == 'CUSTOM' ? TramColors.brandPrimary : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_month,
                                size: 14,
                                color: _dateFilter == 'CUSTOM' ? Colors.white : TramColors.textPrimary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _dateFilter == 'CUSTOM' && _customDate != null
                                    ? DateFormat('dd/MM').format(_customDate!)
                                    : 'Chọn ngày',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  fontWeight: _dateFilter == 'CUSTOM' ? FontWeight.bold : FontWeight.normal,
                                  color: _dateFilter == 'CUSTOM' ? Colors.white : TramColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Room / Table Filters Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildZoneChip('Tất cả phòng/bàn', 'ALL'),
                      const SizedBox(width: 8),
                      _buildZoneChip('🥡 Mang về', 'MANG_VE'),
                      ..._availableZones.map((z) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _buildZoneChip(z, z),
                      )),
                      if (_availableTables.isNotEmpty && _zoneFilter != 'MANG_VE') ...[
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          tooltip: 'Lọc theo bàn',
                          initialValue: _tableFilter,
                          onSelected: (val) => setState(() => _tableFilter = val),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'ALL',
                              child: Text('Tất cả bàn'),
                            ),
                            ..._availableTables.map((t) => PopupMenuItem(
                              value: t,
                              child: Text(t),
                            )),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _tableFilter != 'ALL' ? TramColors.brandPrimary : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _tableFilter != 'ALL' ? TramColors.brandPrimary : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.table_restaurant,
                                  size: 14,
                                  color: _tableFilter != 'ALL' ? Colors.white : TramColors.textPrimary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _tableFilter != 'ALL' ? 'Bàn: $_tableFilter' : 'Chọn bàn',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    fontWeight: _tableFilter != 'ALL' ? FontWeight.bold : FontWeight.normal,
                                    color: _tableFilter != 'ALL' ? Colors.white : TramColors.textPrimary,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 16,
                                  color: _tableFilter != 'ALL' ? Colors.white : TramColors.textPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Status & Payment Filters & Export Bar in a single neat row
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildStatusChip('Tất cả', 'ALL'),
                            const SizedBox(width: 6),
                            _buildStatusChip('Đã thanh toán', 'PAID'),
                            const SizedBox(width: 6),
                            _buildStatusChip('Đã hủy', 'CANCELLED'),
                            const SizedBox(width: 8),
                            Container(width: 1, height: 16, color: Colors.grey.shade300),
                            const SizedBox(width: 8),
                            _buildPaymentChip('Tất cả HTTT', 'ALL'),
                            const SizedBox(width: 6),
                            _buildPaymentChip('💵 Tiền mặt', 'CASH'),
                            const SizedBox(width: 6),
                            _buildPaymentChip('🏦 VietQR', 'TRANSFER'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.file_download_outlined, color: TramColors.brandPrimary),
                      tooltip: 'Xuất file Excel',
                      visualDensity: VisualDensity.compact,
                      onPressed: _exportFilteredExcel,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Total Bar with Takeaway Metrics
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFFBF8F2),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long, size: 16, color: TramColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          cancelledBills.isEmpty
                              ? 'Tổng: ${paidBills.length} hóa đơn'
                              : 'Tổng: ${paidBills.length} h/đơn (${cancelledBills.length} đã hủy)',
                          style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: TramColors.textSecondary),
                        ),
                      ],
                    ),
                    Text(
                      FormatUtils.vnd(totalAmount),
                      style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w800, color: TramColors.brandPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shopping_bag_outlined, size: 15, color: Color(0xFF8B5CF6)),
                        const SizedBox(width: 4),
                        Text(
                          'Mang về: $takeawayCount đơn',
                          style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF8B5CF6)),
                        ),
                      ],
                    ),
                    Text(
                      FormatUtils.vnd(takeawayRevenue),
                      style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF8B5CF6)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // List of bills
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey),
                        const SizedBox(height: 10),
                        Text(
                          'Không tìm thấy hóa đơn nào phù hợp bộ lọc',
                          style: GoogleFonts.beVietnamPro(fontSize: 13, color: TramColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final bill = filtered[index];
                      return _buildBillCard(bill);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneChip(String label, String key) {
    final isSelected = _zoneFilter == key;
    return InkWell(
      onTap: () => setState(() {
        _zoneFilter = key;
        _tableFilter = 'ALL';
      }),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? TramColors.brandPrimary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? TramColors.brandPrimary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : TramColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildDateChip(String label, String key) {
    final isSelected = _dateFilter == key;
    return InkWell(
      onTap: () => setState(() => _dateFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? TramColors.brandPrimary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? TramColors.brandPrimary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : TramColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentChip(String label, String key) {
    final isSelected = _paymentFilter == key;
    return InkWell(
      onTap: () => setState(() => _paymentFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? TramColors.brandPrimary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? TramColors.brandPrimary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? TramColors.brandPrimary : TramColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String key) {
    final isSelected = _statusFilter == key;
    final isDanger = key == 'CANCELLED';
    return InkWell(
      onTap: () => setState(() => _statusFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDanger ? TramColors.danger : TramColors.brandPrimary)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (isDanger ? TramColors.danger : TramColors.brandPrimary)
                : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : TramColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildBillCard(BillModel bill) {
    final isCash = bill.paymentMethod.toLowerCase().contains('cash') || bill.paymentMethod.toLowerCase().contains('tiền mặt');
    final isCancelled = bill.status == 'CANCELLED';
    final timeStr = FormatUtils.dateTime(bill.closedAt ?? bill.createdAt);

    final tableName = bill.tableName.trim();
    final zone = bill.zone.trim();
    final hasTable = tableName.isNotEmpty || zone.isNotEmpty;
    final tableDisplay = tableName.isNotEmpty
        ? (zone.isNotEmpty ? '$tableName ($zone)' : tableName)
        : zone;

    // Only show orderCode chip if distinct from billCode
    final showOrderCode = bill.orderCode != null &&
        bill.orderCode!.trim().isNotEmpty &&
        bill.orderCode!.trim() != bill.billCode.trim();

    return InkWell(
      onTap: () => BillDetailSheet.show(context, bill),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCancelled ? Colors.red.shade50.withValues(alpha: 0.3) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCancelled ? TramColors.danger.withValues(alpha: 0.3) : TramColors.borderLight,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Bill code + Order code on Left, Final Amount on Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        bill.billCode,
                        style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 14, color: TramColors.textPrimary),
                      ),
                      if (showOrderCode) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#${bill.orderCode}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  FormatUtils.vnd(bill.finalAmount),
                  style: GoogleFonts.beVietnamPro(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isCancelled ? TramColors.danger : TramColors.brandPrimary,
                    decoration: isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Row 2: Table / Room Badge + Cancelled status badge (if any)
            if (hasTable || isCancelled) ...[
              Row(
                children: [
                  if (hasTable)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: TramColors.brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isTakeaway(bill) ? Icons.shopping_bag_outlined : Icons.table_restaurant_outlined,
                            size: 13,
                            color: TramColors.brandPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tableDisplay,
                            style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
                          ),
                        ],
                      ),
                    ),
                  if (isCancelled) ...[
                    if (hasTable) const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: TramColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: TramColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'ĐÃ HỦY',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: TramColors.danger,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
            ],

            // Row 3: Items preview
            Text(
              bill.items.map((i) => '${i.quantity}x ${i.name}').join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
            ),
            if (isCancelled && bill.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Lý do hủy: ${bill.note}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.beVietnamPro(fontSize: 11, fontStyle: FontStyle.italic, color: TramColors.danger),
              ),
            ],
            const SizedBox(height: 8),

            // Row 4: Meta & Staff & Payment Method Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isCancelled
                            ? TramColors.danger
                            : (isCash ? TramColors.success : TramColors.info)).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isCancelled
                            ? '🚫 Đã hủy'
                            : (isCash ? '💵 Tiền mặt' : '🏦 VietQR'),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isCancelled
                              ? TramColors.danger
                              : (isCash ? TramColors.success : TramColors.info),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
