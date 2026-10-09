// lib/features/reports/end_of_day_report_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/reports/report_calculator.dart';
import '../../core/reports/report_export_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import 'reports_hub_screen.dart';

class EndOfDayReportScreen extends StatefulWidget {
  const EndOfDayReportScreen({super.key});

  @override
  State<EndOfDayReportScreen> createState() => _EndOfDayReportScreenState();
}

class _EndOfDayReportScreenState extends State<EndOfDayReportScreen>
    with SingleTickerProviderStateMixin {
  final _fb = FirebaseService();
  final _auth = AuthService();

  late TabController _tabController;

  List<BillModel> _bills = [];
  List<TableModel> _tables = [];
  List<CashShiftModel> _shifts = [];
  List<StoreInfoModel> _stores = [];
  bool _loading = true;

  // Filter state
  String _selectedDateRange = 'TODAY'; // TODAY, YESTERDAY, 7DAYS, THIS_MONTH, CUSTOM
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _selectedStoreCode = ''; // '' = current or ALL
  String _selectedStaff = 'ALL'; // 'ALL' or staff full name / username

  // Tab 3 (Hàng hoá) search and sort
  String _productSearch = '';
  String _sortBy = 'REV_DESC'; // REV_DESC, QTY_DESC, NAME_ASC
  String _productViewMode = 'AMOUNT'; // 'AMOUNT' (Số tiền bán) or 'QUANTITY' (Số lượng bán)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _selectedStoreCode = _auth.currentStoreCode;
    _loadStores();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    try {
      final list = await _fb.getAllStores();
      if (mounted && list.isNotEmpty) {
        setState(() => _stores = list);
      }
    } catch (_) {}
  }

  void _loadData() {
    _fb.billsStream().listen((b) {
      if (mounted) setState(() { _bills = b; _loading = false; });
    });
    _fb.tablesStream().listen((t) {
      if (mounted) setState(() => _tables = t);
    }, onError: (Object e) => debugPrint('Lỗi tải danh sách bàn: $e'));
    _fb.cashShiftsStream().listen((s) {
      if (mounted) setState(() => _shifts = s);
    });
  }

  // Date range filter helper
  bool _isWithinRange(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_selectedDateRange) {
      case 'TODAY':
        return dt.year == now.year && dt.month == now.month && dt.day == now.day;
      case 'YESTERDAY':
        final yesterday = today.subtract(const Duration(days: 1));
        return dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
      case '7DAYS':
        final sevenDaysAgo = today.subtract(const Duration(days: 7));
        return dt.isAfter(sevenDaysAgo) && dt.isBefore(now.add(const Duration(days: 1)));
      case 'THIS_MONTH':
        return dt.year == now.year && dt.month == now.month;
      case 'LAST_MONTH':
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        return dt.year == lastMonth.year && dt.month == lastMonth.month;
      case 'CUSTOM':
        if (_customStartDate == null) return true;
        final start = DateTime(_customStartDate!.year, _customStartDate!.month, _customStartDate!.day);
        final end = _customEndDate != null
            ? DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day, 23, 59, 59)
            : DateTime(start.year, start.month, start.day, 23, 59, 59);
        return dt.isAfter(start.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(end.add(const Duration(seconds: 1)));
      default:
        return true;
    }
  }

  String get _dateRangeLabel {
    switch (_selectedDateRange) {
      case 'TODAY':
        return 'Hôm nay';
      case 'YESTERDAY':
        return 'Hôm qua';
      case '7DAYS':
        return '7 ngày qua';
      case 'THIS_MONTH':
        return 'Tháng này';
      case 'LAST_MONTH':
        return 'Tháng trước';
      case 'CUSTOM':
        if (_customStartDate != null) {
          final s = DateFormat('dd/MM').format(_customStartDate!);
          final e = _customEndDate != null ? DateFormat('dd/MM').format(_customEndDate!) : s;
          return '$s - $e';
        }
        return 'Tùy chọn';
      default:
        return 'Hôm nay';
    }
  }

  // Filtered bills
  List<BillModel> get _rangeBills {
    return _bills.where((b) {
      final ts = b.closedAt ?? b.createdAt;
      return _isWithinRange(ts);
    }).toList();
  }

  List<BillModel> get _paidBills => _rangeBills.where((b) => b.status == 'PAID').toList();
  List<BillModel> get _cancelledBills => _rangeBills.where((b) => b.status == 'CANCELLED').toList();

  // Serving tables (current active state)
  List<TableModel> get _servingTables => _tables.where((t) => t.inUse).toList();

  int get _servingItemsCount {
    int count = 0;
    for (final t in _servingTables) {
      if (t.currentOrderJson.isNotEmpty) {
        try {
          final list = jsonDecode(t.currentOrderJson);
          if (list is List) {
            for (final it in list) {
              count += (it['quantity'] as num?)?.toInt() ?? 1;
            }
          }
        } catch (_) {}
      }
    }
    return count;
  }

  int get _servingGuestsCount {
    return _servingTables.fold(0, (s, t) => s + (t.guestCount ?? 1));
  }

  int get _servingEstimatedRevenue {
    int total = 0;
    for (final t in _servingTables) {
      if (t.currentOrderJson.isNotEmpty) {
        try {
          final list = jsonDecode(t.currentOrderJson);
          if (list is List) {
            for (final it in list) {
              final price = (it['price'] as num?)?.toInt() ?? 0;
              final qty = (it['quantity'] as num?)?.toInt() ?? 1;
              int toppingSum = 0;
              if (it['selectedToppings'] is List) {
                for (final tp in it['selectedToppings']) {
                  if (tp is Map && tp['price'] != null) {
                    toppingSum += (tp['price'] as num).toInt();
                  }
                }
              }
              total += (price + toppingSum) * qty;
            }
          }
        } catch (_) {}
      }
    }
    return total;
  }

  // ==================== TAB 1: TỔNG HỢP CALCULATIONS ====================
  int get _grossRevenue => _paidBills.fold(0, (s, b) => s + b.subTotal);

  int get _itemDiscounts {
    int sum = 0;
    for (final b in _paidBills) {
      for (final it in b.items) {
        // Giảm giá dòng là tổng CẢ DÒNG đã lưu (không nhân số lượng)
        sum += it.lineDiscountTotal;
      }
    }
    return sum;
  }

  int get _billDiscounts {
    int sum = 0;
    for (final b in _paidBills) {
      final billDisc = b.discounts.fold(0, (ds, d) => ds + d.amount);
      sum += billDisc + b.pointsDiscount;
      if (sum == 0 && b.totalDiscount > 0) {
        sum += (b.totalDiscount - _itemDiscounts).clamp(0, b.totalDiscount);
      }
    }
    return sum;
  }

  int get _netRevenue => _paidBills.fold(0, (s, b) => s + b.finalAmount);
  int get _vatTotal => _paidBills.fold(0, (s, b) => s + b.vatAmount);
  int get _otherIncome => 0; // Thu khác
  int get _refundAmount => 0; // Trả hàng

  int get _netRevenueWithOther => _netRevenue + _otherIncome - _refundAmount;
  int get _netRevenueWithoutOther => _netRevenue - _refundAmount;

  int get _totalPaidGuests {
    return _paidBills.length; // 1 guest per bill as baseline, plus table guest counts if tracked
  }

  int get _avgRevenuePerBill {
    if (_paidBills.isEmpty) return 0;
    return (_netRevenue / _paidBills.length).round();
  }

  // ==================== TAB 2: THU CHI CALCULATIONS ====================
  int get _cashSales => _paidBills
      .where((b) => b.paymentMethod == 'CASH')
      .fold(0, (s, b) => s + b.finalAmount);

  int get _qrSales => _paidBills
      .where((b) => b.paymentMethod.contains('QR') || b.paymentMethod.contains('TRANSFER'))
      .fold(0, (s, b) => s + b.finalAmount);

  int get _cardSales => _paidBills
      .where((b) => b.paymentMethod == 'CARD')
      .fold(0, (s, b) => s + b.finalAmount);

  // Cash shift adjustments within range
  int get _totalCashIn {
    return _shifts
        .where((s) => _isWithinRange(s.openedAt))
        .fold(0, (sum, s) => sum + s.cashIn);
  }

  int get _totalCashOut {
    return _shifts
        .where((s) => _isWithinRange(s.openedAt))
        .fold(0, (sum, s) => sum + s.cashOut);
  }

  // Available staff list
  List<String> get _staffList {
    final Set<String> staffSet = {};
    for (final b in _bills) {
      final billStaff = b.staffFullName.isNotEmpty
          ? b.staffFullName
          : (b.orderStaffSummary.isNotEmpty ? b.orderStaffSummary : b.staffUsername);
      if (billStaff.isNotEmpty) staffSet.add(billStaff);
      for (final it in b.items) {
        if (it.orderedByName.isNotEmpty) staffSet.add(it.orderedByName);
      }
    }
    final list = staffSet.toList();
    list.sort();
    return list;
  }

  // ==================== TAB 3: HÀNG HÓA CALCULATIONS ====================
  List<Map<String, dynamic>> get _productSalesList {
    final Map<String, Map<String, dynamic>> productMap = {};

    for (final bill in _paidBills) {
      final billStaff = bill.staffFullName.isNotEmpty
          ? bill.staffFullName
          : (bill.orderStaffSummary.isNotEmpty
              ? bill.orderStaffSummary
              : (bill.staffUsername.isNotEmpty ? bill.staffUsername : 'Nhân viên chung'));

      for (final item in bill.items) {
        final itemStaff = item.orderedByName.isNotEmpty ? item.orderedByName : billStaff;
        if (_selectedStaff != 'ALL' && itemStaff != _selectedStaff) {
          continue;
        }

        final key = item.name.trim();
        if (!productMap.containsKey(key)) {
          productMap[key] = {
            'name': key,
            'productId': item.productId,
            'quantity': 0,
            'revenue': 0,
            'unitPrice': item.unitPrice,
            'category': 'Đồ uống & Món ăn',
            'staffSales': <String, int>{},
          };
        }
        productMap[key]!['quantity'] = (productMap[key]!['quantity'] as int) + item.quantity;
        productMap[key]!['revenue'] = (productMap[key]!['revenue'] as int) + item.itemTotal;

        final staffMap = productMap[key]!['staffSales'] as Map<String, int>;
        staffMap[itemStaff] = (staffMap[itemStaff] ?? 0) + item.quantity;
      }
    }

    var list = productMap.values.toList();

    // Filter by search query
    if (_productSearch.isNotEmpty) {
      final q = _productSearch.toLowerCase();
      list = list.where((p) => (p['name'] as String).toLowerCase().contains(q)).toList();
    }

    // Sort
    if (_sortBy == 'QTY_DESC') {
      list.sort((a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int));
    } else if (_sortBy == 'REV_DESC') {
      list.sort((a, b) => (b['revenue'] as int).compareTo(a['revenue'] as int));
    } else if (_sortBy == 'NAME_ASC') {
      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    } else {
      if (_productViewMode == 'AMOUNT') {
        list.sort((a, b) => (b['revenue'] as int).compareTo(a['revenue'] as int));
      } else {
        list.sort((a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int));
      }
    }

    return list;
  }

  // ==================== TAB 4: PHÒNG BÀN CALCULATIONS ====================
  List<Map<String, dynamic>> get _tableSalesList {
    final Map<String, Map<String, dynamic>> tableMap = {};

    for (final bill in _paidBills) {
      final key = '${bill.zone}_${bill.tableName}';
      if (!tableMap.containsKey(key)) {
        tableMap[key] = {
          'zone': bill.zone,
          'tableName': bill.tableName,
          'orderCount': 0,
          'revenue': 0,
        };
      }
      tableMap[key]!['orderCount'] = (tableMap[key]!['orderCount'] as int) + 1;
      tableMap[key]!['revenue'] = (tableMap[key]!['revenue'] as int) + bill.finalAmount;
    }

    final list = tableMap.values.toList();
    list.sort((a, b) => (b['revenue'] as int).compareTo(a['revenue'] as int));
    return list;
  }

  // Dialog to select Date Range
  void _showDateRangePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Chọn thời gian báo cáo', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildDateOption('Hôm nay', 'TODAY', ctx),
              _buildDateOption('Hôm qua', 'YESTERDAY', ctx),
              _buildDateOption('7 ngày qua', '7DAYS', ctx),
              _buildDateOption('Tháng này', 'THIS_MONTH', ctx),
              _buildDateOption('Tháng trước', 'LAST_MONTH', ctx),
              ListTile(
                leading: const Icon(Icons.date_range, color: TramColors.brandPrimary),
                title: const Text('Tùy chọn ngày...'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                    initialDateRange: _customStartDate != null && _customEndDate != null
                        ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
                        : DateTimeRange(start: DateTime.now().subtract(const Duration(days: 1)), end: DateTime.now()),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDateRange = 'CUSTOM';
                      _customStartDate = picked.start;
                      _customEndDate = picked.end;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateOption(String title, String val, BuildContext ctx) {
    final isSelected = _selectedDateRange == val;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.circle_outlined,
        color: isSelected ? TramColors.brandPrimary : Colors.grey,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? TramColors.brandPrimary : Colors.black87,
        ),
      ),
      onTap: () {
        setState(() => _selectedDateRange = val);
        Navigator.pop(ctx);
      },
    );
  }

  // Dialog to select Store
  void _showStorePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Chọn chi nhánh xem báo cáo', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  _selectedStoreCode.isEmpty ? Icons.check_circle : Icons.store,
                  color: _selectedStoreCode.isEmpty ? TramColors.brandPrimary : Colors.grey,
                ),
                title: Text('${_auth.currentStoreInfo?.storeName ?? _auth.currentStoreCode} (Hiện tại)'),
                onTap: () {
                  setState(() => _selectedStoreCode = _auth.currentStoreCode);
                  Navigator.pop(ctx);
                },
              ),
              ..._stores.map((s) {
                final isSelected = _selectedStoreCode == s.storeCode;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.store,
                    color: isSelected ? TramColors.brandPrimary : Colors.grey,
                  ),
                  title: Text(s.storeName),
                  subtitle: Text('Mã: ${s.storeCode}'),
                  onTap: () {
                    setState(() => _selectedStoreCode = s.storeCode);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // Dialog to select Staff
  void _showStaffPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Lọc hàng hóa theo nhân viên', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  _selectedStaff == 'ALL' ? Icons.check_circle : Icons.circle_outlined,
                  color: _selectedStaff == 'ALL' ? TramColors.brandPrimary : Colors.grey,
                ),
                title: Text(
                  'Tất cả nhân viên (${_staffList.length})',
                  style: TextStyle(
                    fontWeight: _selectedStaff == 'ALL' ? FontWeight.bold : FontWeight.normal,
                    color: _selectedStaff == 'ALL' ? TramColors.brandPrimary : Colors.black87,
                  ),
                ),
                onTap: () {
                  setState(() => _selectedStaff = 'ALL');
                  Navigator.pop(ctx);
                },
              ),
              ..._staffList.map((staff) {
                final isSelected = _selectedStaff == staff;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.person_outline,
                    color: isSelected ? TramColors.brandPrimary : Colors.grey,
                  ),
                  title: Text(
                    staff,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? TramColors.brandPrimary : Colors.black87,
                    ),
                  ),
                  onTap: () {
                    setState(() => _selectedStaff = staff);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // Export Product Sales Report to Excel
  Future<void> _exportHangHoaExcel() async {
    try {
      final excel = Excel.createExcel();
      const sheetName = 'HangHoaBanRa';
      final sheet = excel[sheetName];
      excel.setDefaultSheet(sheetName);

      final currentStoreName = _stores.firstWhere(
        (s) => s.storeCode == _selectedStoreCode,
        orElse: () => _auth.currentStoreInfo ?? StoreInfoModel(storeCode: _auth.currentStoreCode, storeName: 'POS Trạm - ${_auth.currentStoreCode}'),
      ).storeName;

      // Header Info
      sheet.appendRow([TextCellValue('BÁO CÁO HÀNG HÓA BÁN RA THEO NHÂN VIÊN')]);
      sheet.appendRow([TextCellValue('Chi nhánh: $currentStoreName')]);
      sheet.appendRow([TextCellValue('Thời gian: $_dateRangeLabel')]);
      sheet.appendRow([TextCellValue('Nhân viên: ${_selectedStaff == 'ALL' ? 'Tất cả nhân viên' : _selectedStaff}')]);
      final nowStr = DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now());
      sheet.appendRow([TextCellValue('Thời điểm xuất file: $nowStr')]);
      sheet.appendRow([]);

      // Table Headers
      final isAmt = _productViewMode == 'AMOUNT';
      sheet.appendRow([
        TextCellValue('Xếp hạng'),
        TextCellValue('Tên món ăn / Đồ uống'),
        TextCellValue('Nhân viên bán'),
        TextCellValue('Đơn giá (VNĐ)'),
        TextCellValue('Số lượng bán'),
        TextCellValue('Doanh thu món (VNĐ)'),
        TextCellValue('Tỷ trọng ${isAmt ? "doanh thu" : "số lượng"} (%)'),
      ]);

      final list = _productSalesList;
      final totalQty = list.fold<int>(0, (s, it) => s + (it['quantity'] as int));
      final totalRev = list.fold<int>(0, (s, it) => s + (it['revenue'] as int));

      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        final qty = item['quantity'] as int;
        final rev = item['revenue'] as int;
        final double pctNum = isAmt
            ? (totalRev > 0 ? (rev / totalRev * 100) : 0.0)
            : (totalQty > 0 ? (qty / totalQty * 100) : 0.0);
        final pct = pctNum.toStringAsFixed(1);

        String staffStr = '';
        if (_selectedStaff != 'ALL') {
          staffStr = _selectedStaff;
        } else {
          final staffSales = item['staffSales'] as Map<String, int>? ?? {};
          staffStr = staffSales.entries.map((e) => '${e.key} (${e.value})').join('; ');
          if (staffStr.isEmpty) staffStr = 'Nhân viên chung';
        }

        sheet.appendRow([
          DoubleCellValue((i + 1).toDouble()),
          TextCellValue(item['name'] as String),
          TextCellValue(staffStr),
          DoubleCellValue((item['unitPrice'] as int).toDouble()),
          DoubleCellValue(qty.toDouble()),
          DoubleCellValue(rev.toDouble()),
          TextCellValue('$pct%'),
        ]);
      }

      // Sheet 2: Chi tiết theo từng nhân viên nếu chọn Tất cả nhân viên
      if (_selectedStaff == 'ALL') {
        final staffSheet = excel['ChiTietTheoNhanVien'];
        staffSheet.appendRow([TextCellValue('CHI TIẾT MÓN BÁN CỦA TỪNG NHÂN VIÊN')]);
        staffSheet.appendRow([TextCellValue('Thời gian: $_dateRangeLabel')]);
        staffSheet.appendRow([]);
        staffSheet.appendRow([
          TextCellValue('Nhân viên'),
          TextCellValue('Tên món'),
          TextCellValue('Đơn giá (VNĐ)'),
          TextCellValue('Số lượng bán'),
          TextCellValue('Doanh thu (VNĐ)'),
        ]);

        final Map<String, Map<String, Map<String, dynamic>>> staffMap = {};
        for (final bill in _paidBills) {
          final billStaff = bill.staffFullName.isNotEmpty
              ? bill.staffFullName
              : (bill.orderStaffSummary.isNotEmpty
                  ? bill.orderStaffSummary
                  : (bill.staffUsername.isNotEmpty ? bill.staffUsername : 'Nhân viên chung'));
          for (final item in bill.items) {
            final itemStaff = item.orderedByName.isNotEmpty ? item.orderedByName : billStaff;
            if (!staffMap.containsKey(itemStaff)) {
              staffMap[itemStaff] = {};
            }
            final pMap = staffMap[itemStaff]!;
            final key = item.name.trim();
            if (!pMap.containsKey(key)) {
              pMap[key] = {
                'name': key,
                'unitPrice': item.unitPrice,
                'quantity': 0,
                'revenue': 0,
              };
            }
            pMap[key]!['quantity'] = (pMap[key]!['quantity'] as int) + item.quantity;
            pMap[key]!['revenue'] = (pMap[key]!['revenue'] as int) + item.itemTotal;
          }
        }

        for (final entry in staffMap.entries) {
          final sName = entry.key;
          for (final p in entry.value.values) {
            staffSheet.appendRow([
              TextCellValue(sName),
              TextCellValue(p['name'] as String),
              DoubleCellValue((p['unitPrice'] as int).toDouble()),
              DoubleCellValue((p['quantity'] as int).toDouble()),
              DoubleCellValue((p['revenue'] as int).toDouble()),
            ]);
          }
        }
      }

      final safeStaff = _selectedStaff == 'ALL' ? 'Tat_Ca_NV' : FirebaseService.sanitizeFileName(_selectedStaff);
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final fileName = 'BaoCao_HangHoa_${safeStaff}_${_selectedDateRange}_$dateStr.xlsx';

      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$fileName';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Báo cáo hàng hóa bán ra - $currentStoreName (${_selectedStaff == 'ALL' ? 'Tất cả NV' : _selectedStaff})',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất file Excel: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Active serving tables modal sheet
  void _showServingTablesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Chi Tiết Bàn Đang Phục Vụ',
                  style: GoogleFonts.beVietnamPro(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: TramColors.warningSurface, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    '${_servingTables.length} BÀN',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: TramColors.warningInk),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (_servingTables.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('Hiện tại không có bàn nào đang phục vụ',
                      style: GoogleFonts.beVietnamPro(color: TramColors.textSecondary)),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _servingTables.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final t = _servingTables[i];
                    int itemsCount = 0;
                    int estTotal = 0;
                    if (t.currentOrderJson.isNotEmpty) {
                      try {
                        final list = jsonDecode(t.currentOrderJson);
                        if (list is List) {
                          for (final it in list) {
                            final q = (it['quantity'] as num?)?.toInt() ?? 1;
                            final p = (it['price'] as num?)?.toInt() ?? 0;
                            itemsCount += q;
                            estTotal += p * q;
                          }
                        }
                      } catch (_) {}
                    }
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: TramColors.warningSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.table_restaurant, color: TramColors.warningInk),
                      ),
                      title: Text('${t.name} • ${t.zone}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${t.guestCount ?? 1} khách • $itemsCount món đang phục vụ',
                          style: const TextStyle(fontSize: 12, color: TramColors.textSecondary)),
                      trailing: Text(
                        FormatUtils.vnd(estTotal),
                        style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStoreName = _stores.firstWhere(
      (s) => s.storeCode == _selectedStoreCode,
      orElse: () => _auth.currentStoreInfo ?? StoreInfoModel(storeCode: _auth.currentStoreCode, storeName: 'POS Trạm - ${_auth.currentStoreCode}'),
    ).storeName;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: TramColors.textPrimary, // nền sáng => icon/chữ tối (tránh trắng trên nền kem)
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Báo cáo cuối ngày',
          style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment_outlined, color: TramColors.brandPrimary),
            tooltip: 'Trung tâm Báo cáo Quản trị',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportsHubScreen(initialReport: ReportKind.endOfDay)),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download_outlined, color: Colors.black87),
            tooltip: 'Xuất báo cáo',
            onSelected: (val) {
              if (val == 'EXCEL_Z') _exportZReportExcel();
              if (val == 'PDF_Z') _exportZReportPdf();
              if (val == 'EXCEL_PROD') _exportHangHoaExcel();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'EXCEL_Z',
                child: Row(
                  children: [
                    Icon(Icons.table_view_outlined, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Text('Xuất Excel (Z-Report)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'PDF_Z',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('Xuất PDF (Z-Report)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'EXCEL_PROD',
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Colors.blue, size: 18),
                    SizedBox(width: 8),
                    Text('Xuất Excel (Hàng hóa)'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.black87),
            tooltip: 'Giải thích chỉ số',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Quy ước tính toán Báo Cáo Cuối Ngày'),
                  content: const SingleChildScrollView(
                    child: Text(
                      '• Doanh thu tổng: Tổng tiền hàng trước khi áp dụng chiết khấu/khuyến mãi.\n'
                      '• Giảm giá món: Chiết khấu trực tiếp trên từng dòng sản phẩm.\n'
                      '• Giảm giá hóa đơn: Voucher khuyến mãi, thẻ thành viên, trừ điểm.\n'
                      '• Doanh thu: Số tiền thực tế sau giảm giá (đã bao gồm thuế GTGT).\n'
                      '• Đang phục vụ: Thống kê tức thời các bàn đang có khách ngồi tại quán.\n'
                      '• Doanh thu thuần: Doanh thu bán hàng trừ chi phí hoàn trả hàng.',
                    ),
                  ),
                  actions: [
                    ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu')),
                  ],
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Column(
            children: [
              // Filter chips bar matching screenshot exactly
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: [
                    InkWell(
                      onTap: _showDateRangePicker,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF0F2F5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.tune, size: 18, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Date chip dropdown
                    InkWell(
                      onTap: _showDateRangePicker,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _dateRangeLabel,
                              style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Branch chip dropdown
                    Expanded(
                      child: InkWell(
                        onTap: _showStorePicker,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F2F5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  currentStoreName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Colors.black54),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4 Tabs matching exact screenshot: Tổng hợp, Thu chi, Hàng hóa, Phòng bàn
              TabBar(
                controller: _tabController,
                indicatorColor: TramColors.brandPrimary,
                indicatorWeight: 3,
                labelColor: TramColors.brandPrimary,
                unselectedLabelColor: TramColors.textSecondary,
                labelStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold),
                unselectedLabelStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.normal),
                tabs: const [
                  Tab(text: 'Tổng hợp'),
                  Tab(text: 'Thu chi'),
                  Tab(text: 'Hàng hóa'),
                  Tab(text: 'Phòng bàn'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTongHopTab(),
                _buildThuChiTab(),
                _buildHangHoaTab(),
                _buildPhongBanTab(),
              ],
            ),
    );
  }

  Future<void> _exportZReportExcel() async {
    try {
      final store = _stores.firstWhere(
        (s) => s.storeCode == _selectedStoreCode,
        orElse: () => _auth.currentStoreInfo ?? StoreInfoModel(storeCode: _auth.currentStoreCode, storeName: 'POS Trạm - ${_auth.currentStoreCode}'),
      );
      final z = ReportCalculator.generateEndOfDayZReport(
        bills: _rangeBills,
        shifts: _shifts,
        tables: _tables,
        storeCode: store.storeCode,
        storeName: store.storeName,
      );
      final t1 = z.tab1TongHop;
      final t2 = z.tab2ThuChi;
      final rows = [
        ['Doanh thu gộp (Gross Revenue)', ReportExportService.formatCurrency(t1.grossRevenue), 'VND'],
        ['Tổng giảm giá món', ReportExportService.formatCurrency(t1.itemDiscounts), 'VND'],
        ['Tổng giảm giá hóa đơn', ReportExportService.formatCurrency(t1.billDiscounts), 'VND'],
        ['Tổng chiết khấu / Giảm giá', ReportExportService.formatCurrency(t1.totalDiscount), 'VND'],
        ['Doanh thu sau chiết khấu', ReportExportService.formatCurrency(t1.afterDiscount), 'VND'],
        ['Tiền thuế GTGT (VAT)', ReportExportService.formatCurrency(t1.vatTotal), 'VND'],
        ['Doanh thu thuần (Net Revenue)', ReportExportService.formatCurrency(t1.netRevenue), 'VND'],
        ['Tiền hoàn trả hàng', ReportExportService.formatCurrency(t1.refundAmount), 'VND'],
        ['Doanh thu thực thu cuối ngày', ReportExportService.formatCurrency(t1.netRevenueWithoutRefund), 'VND'],
        ['Số hóa đơn đã thanh toán', t1.paidBillsCount, 'Đơn'],
        ['Doanh thu trung bình / đơn', ReportExportService.formatCurrency(t1.avgRevenuePerBill), 'VND/đơn'],
        ['Tổng số lượng khách', t1.totalGuests, 'Khách'],
        ['Bán hàng thu tiền mặt', ReportExportService.formatCurrency(t2.cashSales), 'VND'],
        ['Bán hàng chuyển khoản QR', ReportExportService.formatCurrency(t2.transferSales), 'VND'],
        ['Bán hàng qua thẻ / POS', ReportExportService.formatCurrency(t2.cardSales), 'VND'],
        ['Tổng tiền thu bán hàng', ReportExportService.formatCurrency(t2.totalRevenue), 'VND'],
        ['Tổng thu nộp tiền vào quỹ', ReportExportService.formatCurrency(t2.cashInTotal), 'VND'],
        ['Tổng chi rút tiền quỹ', ReportExportService.formatCurrency(t2.cashOutTotal), 'VND'],
        ['Tổng tiền hoàn trả khách', ReportExportService.formatCurrency(t2.refundTotal), 'VND'],
      ];
      final now = DateTime.now();
      final start = _customStartDate ?? DateTime(now.year, now.month, now.day);
      final end = _customEndDate ?? start;
      final path = await ReportExportService.exportToExcel(
        reportCode: 'BC_CUOINGAY_Z',
        reportTitle: 'BÁO CÁO CUỐI NGÀY (Z-REPORT)',
        storeCode: store.storeCode,
        storeName: store.storeName,
        storeAddress: store.address,
        storePhone: store.phone,
        startDate: start,
        endDate: end,
        headers: ['Chỉ tiêu đối soát cuối ngày', 'Giá trị', 'Đơn vị tính'],
        rows: rows,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xuất Excel: ${path.split("/").last}'), backgroundColor: TramColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất Excel: $e'), backgroundColor: TramColors.danger),
        );
      }
    }
  }

  Future<void> _exportZReportPdf() async {
    try {
      final store = _stores.firstWhere(
        (s) => s.storeCode == _selectedStoreCode,
        orElse: () => _auth.currentStoreInfo ?? StoreInfoModel(storeCode: _auth.currentStoreCode, storeName: 'POS Trạm - ${_auth.currentStoreCode}'),
      );
      final z = ReportCalculator.generateEndOfDayZReport(
        bills: _rangeBills,
        shifts: _shifts,
        tables: _tables,
        storeCode: store.storeCode,
        storeName: store.storeName,
      );
      final t1 = z.tab1TongHop;
      final t2 = z.tab2ThuChi;
      final rows = [
        ['Doanh thu gộp (Gross Revenue)', ReportExportService.formatCurrency(t1.grossRevenue), 'VND'],
        ['Tổng giảm giá món', ReportExportService.formatCurrency(t1.itemDiscounts), 'VND'],
        ['Tổng giảm giá hóa đơn', ReportExportService.formatCurrency(t1.billDiscounts), 'VND'],
        ['Tổng chiết khấu / Giảm giá', ReportExportService.formatCurrency(t1.totalDiscount), 'VND'],
        ['Doanh thu sau chiết khấu', ReportExportService.formatCurrency(t1.afterDiscount), 'VND'],
        ['Tiền thuế GTGT (VAT)', ReportExportService.formatCurrency(t1.vatTotal), 'VND'],
        ['Doanh thu thuần (Net Revenue)', ReportExportService.formatCurrency(t1.netRevenue), 'VND'],
        ['Tiền hoàn trả hàng', ReportExportService.formatCurrency(t1.refundAmount), 'VND'],
        ['Doanh thu thực thu cuối ngày', ReportExportService.formatCurrency(t1.netRevenueWithoutRefund), 'VND'],
        ['Số hóa đơn đã thanh toán', t1.paidBillsCount, 'Đơn'],
        ['Doanh thu trung bình / đơn', ReportExportService.formatCurrency(t1.avgRevenuePerBill), 'VND/đơn'],
        ['Tổng số lượng khách', t1.totalGuests, 'Khách'],
        ['Bán hàng thu tiền mặt', ReportExportService.formatCurrency(t2.cashSales), 'VND'],
        ['Bán hàng chuyển khoản QR', ReportExportService.formatCurrency(t2.transferSales), 'VND'],
        ['Bán hàng qua thẻ / POS', ReportExportService.formatCurrency(t2.cardSales), 'VND'],
        ['Tổng tiền thu bán hàng', ReportExportService.formatCurrency(t2.totalRevenue), 'VND'],
        ['Tổng thu nộp tiền vào quỹ', ReportExportService.formatCurrency(t2.cashInTotal), 'VND'],
        ['Tổng chi rút tiền quỹ', ReportExportService.formatCurrency(t2.cashOutTotal), 'VND'],
        ['Tổng tiền hoàn trả khách', ReportExportService.formatCurrency(t2.refundTotal), 'VND'],
      ];
      final now = DateTime.now();
      final start = _customStartDate ?? DateTime(now.year, now.month, now.day);
      final end = _customEndDate ?? start;
      final path = await ReportExportService.exportToPdf(
        reportCode: 'BC_CUOINGAY_Z',
        reportTitle: 'BÁO CÁO CUỐI NGÀY (Z-REPORT)',
        storeCode: store.storeCode,
        storeName: store.storeName,
        storeAddress: store.address,
        storePhone: store.phone,
        startDate: start,
        endDate: end,
        headers: ['Chỉ tiêu đối soát cuối ngày', 'Giá trị', 'Đơn vị tính'],
        rows: rows,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xuất PDF: ${path.split("/").last}'), backgroundColor: TramColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất PDF: $e'), backgroundColor: TramColors.danger),
        );
      }
    }
  }

  // ==================== TAB 1: TỔNG HỢP ====================
  Widget _buildTongHopTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // Ô DOANH THU ƯỚC TÍNH NGÀY = TỔNG DOANH THU + ĐƠN ĐANG PHỤC VỤ
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TramColors.brandPrimary, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: TramColors.brandPrimary.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: TramColors.brandPrimary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'KPI TRỌNG TÂM',
                          style: GoogleFonts.beVietnamPro(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Doanh thu ước tính ngày',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: TramColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.calculate_outlined, color: TramColors.brandPrimary, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                FormatUtils.vnd(_netRevenue + _servingEstimatedRevenue),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: TramColors.brandPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Công thức: Tổng doanh thu (${FormatUtils.vnd(_netRevenue)}) + Đang phục vụ (${FormatUtils.vnd(_servingEstimatedRevenue)} từ ${_servingTables.length} bàn)',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // 1. TỔNG KẾT BÁN HÀNG
        _buildSectionCard(
          title: 'TỔNG KẾT BÁN HÀNG',
          rows: [
            _buildReportRow('Doanh thu tổng', FormatUtils.vnd(_grossRevenue)),
            _buildReportRow('Tổng giảm giá món', FormatUtils.vnd(_itemDiscounts)),
            _buildReportRow('Tổng giảm giá hóa đơn', FormatUtils.vnd(_billDiscounts)),
            _buildReportRow(
              'Doanh thu (Đã thu)',
              FormatUtils.vnd(_netRevenue),
              subtitle: 'Bao gồm ${FormatUtils.vnd(_vatTotal)} tiền thuế',
            ),
            _buildReportRow(
              'Doanh thu ước tính cả ngày',
              FormatUtils.vnd(_netRevenue + _servingEstimatedRevenue),
              subtitle: 'Tổng doanh thu + Đơn đang phục vụ',
              isBold: true,
            ),
            _buildReportRow('Thu khác', FormatUtils.vnd(_otherIncome)),
            _buildReportRow('Trả hàng', FormatUtils.vnd(_refundAmount)),
            _buildReportRow(
              'Doanh thu thuần',
              FormatUtils.vnd(_netRevenueWithOther),
              subtitle: 'Bao gồm thu khác',
              isBold: true,
            ),
            _buildReportRow(
              'Doanh thu thuần',
              FormatUtils.vnd(_netRevenueWithoutOther),
              subtitle: 'Không bao gồm thu khác',
              isBold: true,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 2. ĐANG PHỤC VỤ >
        _buildSectionCard(
          title: 'ĐANG PHỤC VỤ',
          trailingIcon: Icons.arrow_forward_ios,
          onTitleTap: _showServingTablesSheet,
          rows: [
            _buildReportRow('Đơn đang phục vụ', _servingTables.length.toString()),
            _buildReportRow('Số lượng sản phẩm', _servingItemsCount.toString()),
            _buildReportRow('Số khách', _servingGuestsCount.toString()),
            _buildReportRow('Doanh thu ước tính', FormatUtils.vnd(_servingEstimatedRevenue)),
            _buildReportRow('Thu khác', '0'),
          ],
        ),

        const SizedBox(height: 12),

        // 3. HÓA ĐƠN
        _buildSectionCard(
          title: 'HÓA ĐƠN',
          rows: [
            _buildReportRow('Số hóa đơn', _paidBills.length.toString()),
            _buildReportRow('Số khách', _totalPaidGuests.toString()),
            _buildReportRow('Doanh thu TB/Đơn', FormatUtils.vnd(_avgRevenuePerBill)),
          ],
        ),

        const SizedBox(height: 12),

        // 4. HÓA ĐƠN ĐÃ HỦY
        _buildSectionCard(
          title: 'HÓA ĐƠN ĐÃ HỦY',
          rows: [
            _buildReportRow('Số lượng đơn hủy', _cancelledBills.length.toString()),
            _buildReportRow(
              'Giá trị hủy',
              FormatUtils.vnd(_cancelledBills.fold(0, (s, b) => s + b.finalAmount)),
            ),
          ],
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ==================== TAB 2: THU CHI ====================
  Widget _buildThuChiTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _buildSectionCard(
          title: 'PHƯƠNG THỨC THANH TOÁN BÁN HÀNG',
          rows: [
            _buildReportRow('Tiền mặt (Cash)', FormatUtils.vnd(_cashSales), isBold: true),
            _buildReportRow('Chuyển khoản VietQR', FormatUtils.vnd(_qrSales), isBold: true, color: TramColors.info),
            if (_cardSales > 0)
              _buildReportRow('Thẻ ngân hàng POS', FormatUtils.vnd(_cardSales)),
            const Divider(height: 16),
            _buildReportRow(
              'TỔNG THỰC THU BÁN HÀNG',
              FormatUtils.vnd(_netRevenue),
              isBold: true,
              color: TramColors.brandPrimary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'GIAO DỊCH KÉT TIỀN & THU CHI KHÁC',
          rows: [
            _buildReportRow('Tiền nộp thêm vào két (Cash In)', FormatUtils.vnd(_totalCashIn), color: TramColors.success),
            _buildReportRow('Tiền rút / chi vặt két (Cash Out)', FormatUtils.vnd(_totalCashOut), color: TramColors.danger),
            const Divider(height: 16),
            _buildReportRow(
              'DÒNG TIỀN KÉT PHÁT SINH',
              '${_totalCashIn - _totalCashOut >= 0 ? "+" : ""}${FormatUtils.vnd(_totalCashIn - _totalCashOut)}',
              isBold: true,
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==================== TAB 3: HÀNG HÓA (BÁO CÁO HÀNG HÓA BÁN RA) ====================
  Widget _buildHangHoaTab() {
    final list = _productSalesList;
    final totalQty = list.fold<int>(0, (s, it) => s + (it['quantity'] as int));
    final totalRev = list.fold<int>(0, (s, it) => s + (it['revenue'] as int));

    return Column(
      children: [
        // Search & Filter header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm tên món...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFFF5F6F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setState(() => _productSearch = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    initialValue: _sortBy,
                    tooltip: 'Sắp xếp',
                    icon: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6F8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.sort, color: TramColors.brandPrimary),
                    ),
                    onSelected: (val) => setState(() => _sortBy = val),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: _productViewMode == 'AMOUNT' ? 'REV_DESC' : 'QTY_DESC',
                        child: Text(_productViewMode == 'AMOUNT' ? 'Doanh thu cao nhất' : 'Số lượng bán nhiều nhất'),
                      ),
                      PopupMenuItem(
                        value: _productViewMode == 'AMOUNT' ? 'QTY_DESC' : 'REV_DESC',
                        child: Text(_productViewMode == 'AMOUNT' ? 'Số lượng bán nhiều nhất' : 'Doanh thu cao nhất'),
                      ),
                      const PopupMenuItem(value: 'NAME_ASC', child: Text('Tên món A-Z')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Staff filter chip & Export Excel row
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _showStaffPicker,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedStaff != 'ALL' ? const Color(0xFFFBECEE) : const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedStaff != 'ALL' ? TramColors.brandPrimary : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 16,
                              color: _selectedStaff != 'ALL' ? TramColors.brandPrimary : Colors.black87,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _selectedStaff == 'ALL' ? 'Tất cả nhân viên (${_staffList.length})' : _selectedStaff,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  fontWeight: _selectedStaff != 'ALL' ? FontWeight.bold : FontWeight.w500,
                                  color: _selectedStaff != 'ALL' ? TramColors.brandPrimary : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _exportHangHoaExcel,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.file_download_outlined, size: 16, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Xuất Excel',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Segmented Toggle: [Số tiền bán] vs [Số lượng bán]
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (_productViewMode != 'AMOUNT') {
                            setState(() {
                              _productViewMode = 'AMOUNT';
                              _sortBy = 'REV_DESC';
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _productViewMode == 'AMOUNT' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _productViewMode == 'AMOUNT'
                                ? const [BoxShadow(color: Color(0x12000000), blurRadius: 4, offset: Offset(0, 1))]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.monetization_on_outlined,
                                size: 16,
                                color: _productViewMode == 'AMOUNT' ? TramColors.brandPrimary : Colors.black87,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Số tiền bán',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: _productViewMode == 'AMOUNT' ? FontWeight.bold : FontWeight.w500,
                                  color: _productViewMode == 'AMOUNT' ? TramColors.brandPrimary : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (_productViewMode != 'QUANTITY') {
                            setState(() {
                              _productViewMode = 'QUANTITY';
                              _sortBy = 'QTY_DESC';
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _productViewMode == 'QUANTITY' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _productViewMode == 'QUANTITY'
                                ? const [BoxShadow(color: Color(0x12000000), blurRadius: 4, offset: Offset(0, 1))]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 16,
                                color: _productViewMode == 'QUANTITY' ? TramColors.brandPrimary : Colors.black87,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Số lượng bán',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: _productViewMode == 'QUANTITY' ? FontWeight.bold : FontWeight.w500,
                                  color: _productViewMode == 'QUANTITY' ? TramColors.brandPrimary : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              // Summary stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _productViewMode == 'AMOUNT'
                        ? '${list.length} món • Tổng: $totalQty phần'
                        : '${list.length} món • Doanh số: ${FormatUtils.vnd(totalRev)}',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _productViewMode == 'AMOUNT'
                        ? 'Doanh số: ${FormatUtils.vnd(totalRev)}'
                        : 'Tổng bán: $totalQty phần',
                    style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Product list
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 50, color: Colors.grey.shade400),
                      const SizedBox(height: 10),
                      Text(
                        'Không có dữ liệu hàng hóa bán ra trong kỳ',
                        style: GoogleFonts.beVietnamPro(color: TramColors.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final item = list[i];
                    final qty = item['quantity'] as int;
                    final rev = item['revenue'] as int;

                    // Calculate percentage based on active view mode
                    final double pctNum = _productViewMode == 'AMOUNT'
                        ? (totalRev > 0 ? (rev / totalRev * 100) : 0.0)
                        : (totalQty > 0 ? (qty / totalQty * 100) : 0.0);
                    final pct = pctNum.toStringAsFixed(1);

                    final staffSales = item['staffSales'] as Map<String, int>? ?? {};
                    String staffLabel = '';
                    if (_selectedStaff != 'ALL') {
                      staffLabel = 'NV bán: $_selectedStaff';
                    } else if (staffSales.isNotEmpty) {
                      staffLabel = 'NV: ${staffSales.entries.map((e) => "${e.key} (${e.value})").join(", ")}';
                    }

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: const [
                          BoxShadow(color: Color(0x04000000), blurRadius: 4, offset: Offset(0, 1)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: i < 3 ? TramColors.brandPrimary : Colors.grey.shade200,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: i < 3 ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'],
                                  style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _productViewMode == 'AMOUNT'
                                      ? 'Đơn giá: ${FormatUtils.vnd(item['unitPrice'])} • $qty phần bán ra'
                                      : 'Đơn giá: ${FormatUtils.vnd(item['unitPrice'])} • Doanh thu: ${FormatUtils.vnd(rev)}',
                                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
                                ),
                                if (staffLabel.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      staffLabel,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: TramColors.brandPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _productViewMode == 'AMOUNT' ? FormatUtils.vnd(rev) : '$qty phần',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: TramColors.brandPrimary,
                                ),
                              ),
                              Text(
                                'Tỷ trọng: $pct%',
                                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                              ),
                            ],
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

  // ==================== TAB 4: PHÒNG BÀN ====================
  Widget _buildPhongBanTab() {
    final list = _tableSalesList;
    final totalRev = list.fold<int>(0, (s, it) => s + (it['revenue'] as int));

    return list.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_bar_outlined, size: 50, color: Colors.grey.shade400),
                const SizedBox(height: 10),
                Text('Chưa có dữ liệu bàn nào trong kỳ', style: GoogleFonts.beVietnamPro(color: TramColors.textSecondary)),
              ],
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final t = list[i];
              final orders = t['orderCount'] as int;
              final rev = t['revenue'] as int;
              final pct = totalRev > 0 ? (rev / totalRev * 100).toStringAsFixed(1) : '0.0';

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: TramColors.brandPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.table_restaurant, color: TramColors.brandPrimary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${t['tableName']} (${t['zone']})',
                              style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('$orders lượt khách hoàn tất',
                              style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(FormatUtils.vnd(rev),
                            style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: TramColors.brandPrimary)),
                        Text('Tỷ trọng: $pct%', style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
  }

  // ==================== REUSABLE CARD & ROW BUILDERS ====================
  Widget _buildSectionCard({
    required String title,
    IconData? trailingIcon,
    VoidCallback? onTitleTap,
    required List<Widget> rows,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTitleTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B7280),
                    letterSpacing: 0.3,
                  ),
                ),
                if (trailingIcon != null)
                  Icon(trailingIcon, size: 14, color: const Color(0xFF6B7280)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildReportRow(
    String label,
    String value, {
    String? subtitle,
    bool isBold = false,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
          Text(
            value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
