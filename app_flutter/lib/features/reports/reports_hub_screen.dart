// lib/features/reports/reports_hub_screen.dart
// Trung tâm Báo cáo Tài chính & Vận hành Chuẩn mực POS Trạm
// Tuân thủ 100% đặc tả REPORT_SPEC.md (12 Báo cáo, lọc đa chiều, biểu đồ fl_chart, xuất Excel/PDF)

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/reports/report_calculator.dart';
import '../../core/reports/report_date_utils.dart';
import '../../core/reports/report_export_service.dart';
import '../../core/reports/report_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

enum ReportKind {
  overview('BC_TONGHOP', 'Tổng quan Quản trị', Icons.dashboard_outlined),
  periodRevenue('BC_DOANHTHU_KY', 'Doanh thu theo kỳ', Icons.timeline_outlined),
  category('BC_NHOMHANG', 'Nhóm hàng / Danh mục', Icons.category_outlined),
  product('BC_HANGHOA', 'Hiệu suất Món ăn', Icons.restaurant_menu_outlined),
  staff('BC_NHANVIEN', 'Năng suất Nhân viên', Icons.people_alt_outlined),
  hourly('BC_KHUNGGIO', 'Khung giờ bán hàng', Icons.access_time_outlined),
  paymentMethods('BC_PTTT', 'Hình thức thanh toán', Icons.payment_outlined),
  promotions('BC_KHUYENMAI', 'Khuyến mãi & Voucher', Icons.discount_outlined),
  cancellations('BC_HUYMON', 'Hủy món & Hủy đơn', Icons.cancel_presentation_outlined),
  cashShifts('BC_CAKET', 'Ca két & Chênh lệch', Icons.account_balance_wallet_outlined),
  grossProfit('BC_LOINHUAN', 'Lợi nhuận gộp & COGS', Icons.trending_up_outlined),
  endOfDay('BC_CUOINGAY_Z', 'Cuối ngày (Z-Report)', Icons.summarize_outlined);

  final String code;
  final String title;
  final IconData icon;
  const ReportKind(this.code, this.title, this.icon);
}

enum DateRangeFilter {
  today('Hôm nay'),
  yesterday('Hôm qua'),
  last7Days('7 ngày qua'),
  thisMonth('Tháng này'),
  lastMonth('Tháng trước'),
  custom('Tùy chọn');

  final String label;
  const DateRangeFilter(this.label);
}

class ReportsHubScreen extends StatefulWidget {
  final ReportKind initialReport;

  const ReportsHubScreen({
    super.key,
    this.initialReport = ReportKind.overview,
  });

  @override
  State<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends State<ReportsHubScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  late ReportKind _selectedKind;
  DateRangeFilter _dateFilter = DateRangeFilter.today;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  String _selectedStoreCode = '';
  String _selectedShiftId = 'ALL';
  String _selectedStaff = 'ALL';
  bool _comparePreviousPeriod = false;

  bool _loading = true;
  bool _exporting = false;
  String? _errorMessage;

  List<BillModel> _allBills = [];
  List<CashShiftModel> _allShifts = [];
  List<TableModel> _tables = [];
  Map<int, ProductModel> _productsMap = {};
  List<StoreInfoModel> _stores = [];

  // Sort & search for product report
  String _productSearchQuery = '';
  String _productSort = 'REV_DESC'; // REV_DESC, QTY_DESC, NAME_ASC

  @override
  void initState() {
    super.initState();
    _selectedKind = widget.initialReport;
    _selectedStoreCode = _auth.currentStoreCode;
    _applyDateRange(DateRangeFilter.today);
    _loadInitialData();
  }

  void _applyDateRange(DateRangeFilter filter) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _dateFilter = filter;
      switch (filter) {
        case DateRangeFilter.today:
          _startDate = today;
          _endDate = today;
          break;
        case DateRangeFilter.yesterday:
          final y = today.subtract(const Duration(days: 1));
          _startDate = y;
          _endDate = y;
          break;
        case DateRangeFilter.last7Days:
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = today;
          break;
        case DateRangeFilter.thisMonth:
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = today;
          break;
        case DateRangeFilter.lastMonth:
          final lastMonthEnd = DateTime(today.year, today.month, 0);
          _startDate = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
          _endDate = lastMonthEnd;
          break;
        case DateRangeFilter.custom:
          break;
      }
    });
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final stores = await _fb.getAllStores();
      if (mounted) setState(() => _stores = stores);

      // Listen streams
      _fb.billsStream().listen((bills) {
        if (mounted) {
          setState(() {
            _allBills = bills;
            _loading = false;
          });
        }
      }, onError: (e) {
        if (mounted) setState(() => _errorMessage = 'Lỗi tải hóa đơn: $e');
      });

      _fb.cashShiftsStream().listen((shifts) {
        if (mounted) setState(() => _allShifts = shifts);
      });

      _fb.tablesStream().listen((t) {
        if (mounted) setState(() => _tables = t);
      }, onError: (Object e) => debugPrint('Lỗi tải danh sách bàn: $e'));

      _fb.productsStream(storeCode: _selectedStoreCode).listen((prods) {
        if (mounted) {
          final map = <int, ProductModel>{};
          for (final p in prods) {
            if (p.id > 0) map[p.id] = p;
          }
          setState(() => _productsMap = map);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Không thể tải dữ liệu: $e';
        });
      }
    }
  }

  // ==================== FILTERING LOGIC ====================

  /// Lọc danh sách hóa đơn theo Store, Ngày, Ca và Nhân viên
  List<BillModel> _filterBills(List<BillModel> bills, {DateTime? customStart, DateTime? customEnd}) {
    final start = customStart ?? _startDate;
    final end = customEnd ?? _endDate;

    return bills.where((b) {
      // 1. Lọc ngày
      final dt = ReportDateUtils.getBillDateTime(b.closedAt, b.createdAt, b.status);
      if (!ReportDateUtils.isInRange(dt, start, end)) return false;

      // 2. Lọc ca
      if (_selectedShiftId != 'ALL') {
        if (b.shiftId != _selectedShiftId) return false;
      }

      // 3. Lọc nhân viên
      if (_selectedStaff != 'ALL') {
        final matchesCashier = b.staffUsername == _selectedStaff || b.staffFullName == _selectedStaff;
        final matchesOrder = b.items.any((it) => it.orderedBy == _selectedStaff || it.orderedByName == _selectedStaff);
        if (!matchesCashier && !matchesOrder) return false;
      }

      return true;
    }).toList();
  }

  /// Danh sách hóa đơn của kỳ hiện tại
  List<BillModel> get _currentBills => _filterBills(_allBills);

  /// Danh sách hóa đơn của kỳ trước (để so sánh tăng trưởng)
  List<BillModel> get _previousBills {
    final days = _endDate.difference(_startDate).inDays + 1;
    final prevEnd = _startDate.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: days - 1));
    return _filterBills(_allBills, customStart: prevStart, customEnd: prevEnd);
  }

  /// Ca làm việc trong kỳ
  List<CashShiftModel> get _currentShifts {
    return _allShifts.where((s) {
      final dt = ReportDateUtils.toUtc7(s.openedAt);
      return ReportDateUtils.isInRange(dt, _startDate, _endDate);
    }).toList();
  }

  StoreInfoModel get _currentStoreInfo {
    return _stores.firstWhere(
      (s) => s.storeCode == _selectedStoreCode,
      orElse: () => _auth.currentStoreInfo ?? StoreInfoModel(
        storeCode: _selectedStoreCode,
        storeName: 'POS Trạm',
      ),
    );
  }

  // ==================== EXPORT HANDLERS ====================

  Future<void> _handleExportExcel() async {
    setState(() => _exporting = true);
    final sm = ScaffoldMessenger.of(context);
    try {
      final store = _currentStoreInfo;
      final headers = _getReportHeaders(_selectedKind);
      final rows = _getReportRows(_selectedKind, _currentBills);
      final totalRow = _getReportTotalRow(_selectedKind, _currentBills);

      final path = await ReportExportService.exportToExcel(
        reportCode: _selectedKind.code,
        reportTitle: _selectedKind.title,
        storeCode: store.storeCode,
        storeName: store.storeName,
        storeAddress: store.address,
        storePhone: store.phone,
        startDate: _startDate,
        endDate: _endDate,
        headers: headers,
        rows: rows,
        totalRow: totalRow,
      );

      sm.showSnackBar(
        SnackBar(
          content: Text('Đã xuất Excel thành công: ${path.split("/").last}'),
          backgroundColor: TramColors.success,
        ),
      );
    } catch (e) {
      sm.showSnackBar(
        SnackBar(content: Text('Lỗi xuất Excel: $e'), backgroundColor: TramColors.danger),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _handleExportPdf() async {
    setState(() => _exporting = true);
    final sm = ScaffoldMessenger.of(context);
    try {
      final store = _currentStoreInfo;
      final headers = _getReportHeaders(_selectedKind);
      final rows = _getReportRows(_selectedKind, _currentBills);
      final totalRow = _getReportTotalRow(_selectedKind, _currentBills);

      final path = await ReportExportService.exportToPdf(
        reportCode: _selectedKind.code,
        reportTitle: _selectedKind.title,
        storeCode: store.storeCode,
        storeName: store.storeName,
        storeAddress: store.address,
        storePhone: store.phone,
        startDate: _startDate,
        endDate: _endDate,
        headers: headers,
        rows: rows,
        totalRow: totalRow,
      );

      sm.showSnackBar(
        SnackBar(
          content: Text('Đã xuất PDF thành công: ${path.split("/").last}'),
          backgroundColor: TramColors.success,
        ),
      );
    } catch (e) {
      sm.showSnackBar(
        SnackBar(content: Text('Lỗi xuất PDF: $e'), backgroundColor: TramColors.danger),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<String> _getReportHeaders(ReportKind kind) {
    switch (kind) {
      case ReportKind.overview:
        return ['Chỉ số tài chính', 'Giá trị', 'Đơn vị tính'];
      case ReportKind.periodRevenue:
        return ['Thời gian', 'Số hóa đơn', 'Doanh thu gộp', 'Giảm giá', 'Doanh thu thuần', 'Tiền mặt', 'Chuyển khoản', 'Thẻ / Ví', 'Tỷ trọng'];
      case ReportKind.category:
        return ['Nhóm hàng', 'Số lượng bán', 'Doanh thu gộp', 'Giảm giá', 'Doanh thu thuần', 'Giá vốn (COGS)', 'Lợi nhuận gộp', 'Tỷ suất LN'];
      case ReportKind.product:
        return ['Mã món', 'Tên món', 'Nhóm', 'ĐVT', 'Đơn giá', 'Số lượng', 'Doanh thu gộp', 'Giảm giá', 'Doanh thu thuần', 'Giá vốn', 'Lợi nhuận gộp', 'Tỷ suất LN'];
      case ReportKind.staff:
        return ['Nhân viên', 'Tài khoản', 'Số món / Đơn', 'Doanh thu nhận order', 'Doanh thu chốt thu ngân'];
      case ReportKind.hourly:
        return ['Khung giờ', 'Số đơn', 'Doanh thu gộp', 'Tổng giảm giá', 'Tiền thuế VAT', 'Doanh thu thuần'];
      case ReportKind.paymentMethods:
        return ['Hình thức thanh toán', 'Số giao dịch', 'Doanh thu gộp', 'Giảm giá', 'Tiền VAT', 'Thực thu'];
      case ReportKind.promotions:
        return ['Mã CT / Voucher', 'Tên chương trình', 'Loại hình', 'Lượt áp dụng', 'Chi phí giảm giá'];
      case ReportKind.cancellations:
        return ['Thời điểm hủy', 'Mã hóa đơn', 'Bàn / Khu vực', 'Nhân viên', 'Lý do hủy', 'Chi tiết món', 'Giá trị thất thoát'];
      case ReportKind.cashShifts:
        return ['Mã ca', 'Tên ca', 'Thu ngân', 'Đầu ca', 'Bán tiền mặt', 'Nộp thêm', 'Chi vặt', 'Két kỳ vọng', 'Thực kiểm', 'Chênh lệch'];
      case ReportKind.grossProfit:
        return ['Tên món', 'Số lượng', 'Đơn giá bán', 'Đơn giá vốn', 'Doanh thu thuần', 'Tổng giá vốn', 'Lợi nhuận gộp', 'Tỷ suất LN'];
      case ReportKind.endOfDay:
        return ['Chỉ tiêu cuối ngày', 'Giá trị', 'Ghi chú đối soát'];
    }
  }

  List<List<dynamic>> _getReportRows(ReportKind kind, List<BillModel> bills) {
    switch (kind) {
      case ReportKind.overview:
        final o = ReportCalculator.calculateOverviewReport(bills, productsMap: _productsMap);
        return [
          ['Doanh thu thuần (Net Revenue)', ReportExportService.formatCurrency(o.netRevenue), 'VND'],
          ['Doanh thu gộp (Gross Revenue)', ReportExportService.formatCurrency(o.grossRevenue), 'VND'],
          ['Tổng chiết khấu & Giảm giá', ReportExportService.formatCurrency(o.totalDiscount), 'VND'],
          ['Tiền thuế GTGT (VAT)', ReportExportService.formatCurrency(o.vatTotal), 'VND'],
          ['Tổng giá vốn hàng bán (COGS)', ReportExportService.formatCurrency(o.totalCostPrice), 'VND'],
          ['Lợi nhuận gộp (Gross Profit)', ReportExportService.formatCurrency(o.grossProfit), 'VND'],
          ['Tỷ suất lợi nhuận gộp', '${o.grossProfitMarginPercent}%', '%'],
          ['Tổng số hóa đơn hoàn tất', o.paidBillsCount, 'Đơn'],
          ['Giá trị trung bình / đơn', ReportExportService.formatCurrency(o.avgRevenuePerPaidBill), 'VND/đơn'],
          ['Tổng số lượt khách phục vụ', o.totalGuests, 'Khách'],
          ['Hóa đơn hủy & Thất thoát', '${o.cancelledBillsCount} đơn (${ReportExportService.formatCurrency(o.cancelledTotalValue)})', 'VND'],
        ];

      case ReportKind.periodRevenue:
        final list = ReportCalculator.calculateRevenueByPeriod(bills, PeriodType.day);
        return list.map((item) => [
          item.periodKey,
          item.billCount,
          ReportExportService.formatCurrency(item.grossRevenue),
          ReportExportService.formatCurrency(item.totalDiscount),
          ReportExportService.formatCurrency(item.netRevenue),
          ReportExportService.formatCurrency(item.cashRevenue),
          ReportExportService.formatCurrency(item.transferRevenue),
          ReportExportService.formatCurrency(item.cardRevenue),
          '${item.percentage}%',
        ]).toList();

      case ReportKind.category:
        final list = ReportCalculator.calculateCategoryReport(bills, productsMap: _productsMap);
        return list.map((item) => [
          item.category,
          item.quantity,
          ReportExportService.formatCurrency(item.grossRevenue),
          ReportExportService.formatCurrency(item.itemDiscount),
          ReportExportService.formatCurrency(item.netRevenue),
          ReportExportService.formatCurrency(item.costPrice),
          ReportExportService.formatCurrency(item.grossProfit),
          '${item.grossProfitMarginPercent}%',
        ]).toList();

      case ReportKind.product:
        var list = ReportCalculator.calculateProductReport(bills, productsMap: _productsMap);
        if (_productSearchQuery.trim().isNotEmpty) {
          final q = _productSearchQuery.trim().toLowerCase();
          list = list.where((item) =>
            item.productName.toLowerCase().contains(q) ||
            item.productCode.toLowerCase().contains(q) ||
            item.category.toLowerCase().contains(q),
          ).toList();
        }
        if (_productSort == 'QTY_DESC') {
          list.sort((a, b) => b.quantity.compareTo(a.quantity));
        } else if (_productSort == 'NAME_ASC') {
          list.sort((a, b) => a.productName.compareTo(b.productName));
        } else {
          list.sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
        }
        return list.map((item) => [
          item.productCode,
          item.productName,
          item.category,
          item.unit,
          ReportExportService.formatCurrency(item.basePrice),
          item.quantity,
          ReportExportService.formatCurrency(item.grossRevenue),
          ReportExportService.formatCurrency(item.itemDiscount),
          ReportExportService.formatCurrency(item.netRevenue),
          ReportExportService.formatCurrency(item.costPrice),
          ReportExportService.formatCurrency(item.grossProfit),
          '${item.grossProfitMarginPercent}%',
        ]).toList();

      case ReportKind.staff:
        final res = ReportCalculator.calculateStaffPerformance(bills);
        final rows = <List<dynamic>>[];
        for (final o in res.orderStaff) {
          rows.add([o.staffFullName, o.staffUsername, '${o.itemsCount} món', ReportExportService.formatCurrency(o.netRevenue), '-']);
        }
        for (final c in res.cashierStaff) {
          rows.add([c.staffFullName, c.staffUsername, '${c.billCount} đơn', '-', ReportExportService.formatCurrency(c.netRevenue)]);
        }
        return rows;

      case ReportKind.hourly:
        final list = ReportCalculator.calculateHourlyReport(bills);
        return list.map((item) => [
          item.hourLabel,
          item.billCount,
          ReportExportService.formatCurrency(item.grossRevenue),
          ReportExportService.formatCurrency(item.totalDiscount),
          ReportExportService.formatCurrency(item.vatAmount),
          ReportExportService.formatCurrency(item.netRevenue),
        ]).toList();

      case ReportKind.paymentMethods:
        final map = ReportCalculator.calculatePaymentMethodsReport(bills);
        return map.entries.map((e) => [
          e.key == 'CASH' ? 'Tiền mặt' : (e.key == 'TRANSFER_QR' ? 'Chuyển khoản QR' : 'Thẻ / Khác'),
          e.value.billCount,
          ReportExportService.formatCurrency(e.value.grossRevenue),
          ReportExportService.formatCurrency(e.value.totalDiscount),
          ReportExportService.formatCurrency(e.value.vatAmount),
          ReportExportService.formatCurrency(e.value.finalAmount),
        ]).toList();

      case ReportKind.promotions:
        final p = ReportCalculator.calculatePromotionsReport(bills);
        final rows = <List<dynamic>>[];
        for (final c in p.campaigns) {
          rows.add([c.promoCode, c.name, 'Voucher Bill', c.usedCount, ReportExportService.formatCurrency(c.discountAmount)]);
        }
        if (p.pointsRedemption.usedCount > 0) {
          rows.add(['KMT_POINTS', 'Đổi điểm thưởng', 'Tích điểm', p.pointsRedemption.usedCount, ReportExportService.formatCurrency(p.pointsRedemption.discountAmount)]);
        }
        for (final it in p.itemDiscounts.details) {
          rows.add(['ITEM_PROMO', it.productName, 'Giảm theo món', it.quantity, ReportExportService.formatCurrency(it.discountAmount)]);
        }
        return rows;

      case ReportKind.cancellations:
        final c = ReportCalculator.calculateCancellationReport(bills);
        return c.bills.map((b) => [
          ReportDateUtils.formatDisplayDateTime(ReportDateUtils.toUtc7(b.cancelledAt)),
          b.billCode,
          b.tableName,
          b.staffFullName,
          b.reason,
          b.items.join(', '),
          ReportExportService.formatCurrency(b.subTotal),
        ]).toList();

      case ReportKind.cashShifts:
        final sList = ReportCalculator.calculateCashShiftReport(_currentShifts, bills);
        return sList.map((s) => [
          s.shiftCode,
          s.shiftName,
          s.staffFullName,
          ReportExportService.formatCurrency(s.initialCash),
          ReportExportService.formatCurrency(s.cashSales),
          ReportExportService.formatCurrency(s.cashIn),
          ReportExportService.formatCurrency(s.cashOut),
          ReportExportService.formatCurrency(s.expectedCash),
          ReportExportService.formatCurrency(s.actualCash),
          ReportExportService.formatCurrency(s.difference),
        ]).toList();

      case ReportKind.grossProfit:
        final gp = ReportCalculator.calculateGrossProfitReport(bills, productsMap: _productsMap);
        return gp.items.map((it) => [
          it.productName,
          it.quantity,
          ReportExportService.formatCurrency(it.basePrice),
          ReportExportService.formatCurrency(it.costPrice ~/ (it.quantity > 0 ? it.quantity : 1)),
          ReportExportService.formatCurrency(it.netRevenue),
          ReportExportService.formatCurrency(it.costPrice),
          ReportExportService.formatCurrency(it.grossProfit),
          '${it.grossProfitMarginPercent}%',
        ]).toList();

      case ReportKind.endOfDay:
        final z = ReportCalculator.generateEndOfDayZReport(
          bills: bills,
          shifts: _currentShifts,
          tables: _tables,
          productsMap: _productsMap,
          storeCode: _selectedStoreCode,
          storeName: _currentStoreInfo.storeName,
        );
        return [
          ['Doanh thu gộp (Subtotal)', ReportExportService.formatCurrency(z.tab1TongHop.grossRevenue), 'Tổng tiền trước giảm giá'],
          ['Tổng chiết khấu / Giảm giá', ReportExportService.formatCurrency(z.tab1TongHop.totalDiscount), 'Giảm bill + Món + Điểm'],
          ['Doanh thu sau giảm giá', ReportExportService.formatCurrency(z.tab1TongHop.afterDiscount), 'Trước thuế VAT'],
          ['Thuế GTGT (VAT)', ReportExportService.formatCurrency(z.tab1TongHop.vatTotal), 'Đã chốt trên hóa đơn'],
          ['Doanh thu thuần (Net)', ReportExportService.formatCurrency(z.tab1TongHop.netRevenue), 'Thực tế khách trả'],
          ['Hoàn trả (Refund)', ReportExportService.formatCurrency(z.tab1TongHop.refundAmount), 'Đơn trả lại tiền'],
          ['Doanh thu thực thu cuối ngày', ReportExportService.formatCurrency(z.tab1TongHop.netRevenueWithoutRefund), 'NetRevenue - Refund'],
          ['Tiền mặt thu được', ReportExportService.formatCurrency(z.tab2ThuChi.cashSales), 'Thu ngân chốt'],
          ['Chuyển khoản QR thu được', ReportExportService.formatCurrency(z.tab2ThuChi.transferSales), 'VietQR ngân hàng'],
          ['Tổng sản phẩm bán ra', z.tab3HangHoa.totalItemsSold, 'Ly / Đĩa'],
        ];
    }
  }

  List<dynamic>? _getReportTotalRow(ReportKind kind, List<BillModel> bills) {
    if (bills.isEmpty) return null;
    final o = ReportCalculator.calculateOverviewReport(bills, productsMap: _productsMap);

    switch (kind) {
      case ReportKind.overview:
        return ['TỔNG CỘNG', ReportExportService.formatCurrency(o.netRevenue), '100% Khớp'];
      case ReportKind.periodRevenue:
        return ['TỔNG CỘNG', o.paidBillsCount, ReportExportService.formatCurrency(o.grossRevenue), ReportExportService.formatCurrency(o.totalDiscount), ReportExportService.formatCurrency(o.netRevenue), '-', '-', '-', '100%'];
      case ReportKind.category:
        return ['TỔNG CỘNG', '-', ReportExportService.formatCurrency(o.grossRevenue), ReportExportService.formatCurrency(o.itemDiscounts), ReportExportService.formatCurrency(o.afterDiscount), ReportExportService.formatCurrency(o.totalCostPrice), ReportExportService.formatCurrency(o.grossProfit), '${o.grossProfitMarginPercent}%'];
      case ReportKind.product:
        return ['TỔNG CỘNG', '', '', '', '', '-', ReportExportService.formatCurrency(o.grossRevenue), ReportExportService.formatCurrency(o.itemDiscounts), ReportExportService.formatCurrency(o.afterDiscount), ReportExportService.formatCurrency(o.totalCostPrice), ReportExportService.formatCurrency(o.grossProfit), '${o.grossProfitMarginPercent}%'];
      case ReportKind.hourly:
        return ['TỔNG CỘNG', o.paidBillsCount, ReportExportService.formatCurrency(o.grossRevenue), ReportExportService.formatCurrency(o.totalDiscount), ReportExportService.formatCurrency(o.vatTotal), ReportExportService.formatCurrency(o.netRevenue)];
      case ReportKind.paymentMethods:
        return ['TỔNG CỘNG', o.paidBillsCount, ReportExportService.formatCurrency(o.grossRevenue), ReportExportService.formatCurrency(o.totalDiscount), ReportExportService.formatCurrency(o.vatTotal), ReportExportService.formatCurrency(o.netRevenue)];
      default:
        return null;
    }
  }

  // ==================== UI BUILDERS ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TramColors.background,
      appBar: AppBar(
        title: Text(
          'Báo Cáo & Phân Tích Tài Chính',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: TramColors.textPrimary,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_outlined, color: Colors.green),
            tooltip: 'Xuất file Excel (.xlsx)',
            onPressed: _exporting ? null : _handleExportExcel,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: TramColors.brandPrimary),
            tooltip: 'Xuất file PDF (.pdf)',
            onPressed: _exporting ? null : _handleExportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Tải lại',
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: TramColors.brandPrimary))
          : _errorMessage != null
              ? _buildErrorView()
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFiltersBar(),
                      _buildReportSelectorTabs(),
                      _buildOverviewKpiCards(),
                      if (_selectedKind == ReportKind.periodRevenue ||
                          _selectedKind == ReportKind.hourly ||
                          _selectedKind == ReportKind.category ||
                          _selectedKind == ReportKind.paymentMethods)
                        _buildChartSection(),
                      _buildReportTableSection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: TramColors.danger),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Đã xảy ra lỗi',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(fontSize: 14, color: TramColors.textPrimary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
              style: ElevatedButton.styleFrom(backgroundColor: TramColors.brandPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Cửa hàng & Ngày
          Row(
            children: [
              // Store Dropdown
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _selectedStoreCode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Cửa hàng',
                    labelStyle: GoogleFonts.beVietnamPro(fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: _stores.map((s) => DropdownMenuItem(
                    value: s.storeCode,
                    child: Text(s.storeName, style: GoogleFonts.beVietnamPro(fontSize: 12), overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedStoreCode = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Date Range Preset
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<DateRangeFilter>(
                  value: _dateFilter,
                  decoration: InputDecoration(
                    labelText: 'Khoảng ngày',
                    labelStyle: GoogleFonts.beVietnamPro(fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: DateRangeFilter.values.map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(f.label, style: GoogleFonts.beVietnamPro(fontSize: 12)),
                  )).toList(),
                  onChanged: (f) {
                    if (f != null) {
                      if (f == DateRangeFilter.custom) {
                        _showCustomDateRangePicker();
                      } else {
                        _applyDateRange(f);
                      }
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Ca & Nhân viên
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedShiftId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Ca làm việc',
                    labelStyle: GoogleFonts.beVietnamPro(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('Tất cả ca', style: TextStyle(fontSize: 11))),
                    ..._allShifts.map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.shiftName.isNotEmpty ? s.shiftName : s.id, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedShiftId = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedStaff,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Nhân viên',
                    labelStyle: GoogleFonts.beVietnamPro(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('Tất cả nhân viên', style: TextStyle(fontSize: 11))),
                    ..._allBills
                        .map((b) => b.staffUsername.isNotEmpty ? b.staffUsername : b.staffFullName)
                        .where((u) => u.isNotEmpty)
                        .toSet()
                        .map((u) => DropdownMenuItem(
                      value: u,
                      child: Text(u, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedStaff = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3: Kỳ hiển thị & So sánh kỳ trước
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kỳ: ${ReportDateUtils.formatDisplayDate(_startDate)} - ${ReportDateUtils.formatDisplayDate(_endDate)}',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: TramColors.brandPrimary),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _comparePreviousPeriod,
                    activeColor: TramColors.brandPrimary,
                    onChanged: (v) => setState(() => _comparePreviousPeriod = v ?? false),
                  ),
                  Text('So sánh kỳ trước', style: GoogleFonts.beVietnamPro(fontSize: 11)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCustomDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _dateFilter = DateRangeFilter.custom;
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Widget _buildReportSelectorTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: ReportKind.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final kind = ReportKind.values[i];
            final isSelected = kind == _selectedKind;
            return ChoiceChip(
              avatar: Icon(kind.icon, size: 14, color: isSelected ? Colors.white : TramColors.brandPrimary),
              label: Text(kind.title),
              selected: isSelected,
              selectedColor: TramColors.brandPrimary,
              backgroundColor: const Color(0xFFF7F4F2),
              labelStyle: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : TramColors.textPrimary,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (_) => setState(() => _selectedKind = kind),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOverviewKpiCards() {
    final o = ReportCalculator.calculateOverviewReport(_currentBills, productsMap: _productsMap);
    final prevO = _comparePreviousPeriod
        ? ReportCalculator.calculateOverviewReport(_previousBills, productsMap: _productsMap)
        : null;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CHỈ SỐ TÀI CHÍNH CỐT LÕI',
                style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: TramColors.textSecondary),
              ),
              if (_comparePreviousPeriod)
                Text(
                  'Đang so sánh kỳ trước',
                  style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.success, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildKpiCard(
                'Doanh thu thuần',
                ReportExportService.formatCurrency(o.netRevenue),
                icon: Icons.account_balance_wallet,
                color: TramColors.brandPrimary,
                prevValue: prevO?.netRevenue,
                currentValue: o.netRevenue,
              ),
              const SizedBox(width: 8),
              _buildKpiCard(
                'Lợi nhuận gộp',
                ReportExportService.formatCurrency(o.grossProfit),
                icon: Icons.trending_up,
                color: Colors.green.shade800,
                subText: 'Biên LN: ${o.grossProfitMarginPercent}%',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildKpiCard(
                'Số hóa đơn',
                '${o.paidBillsCount} đơn',
                icon: Icons.receipt_long,
                color: Colors.blue.shade800,
                subText: 'TB: ${ReportExportService.formatCurrency(o.avgRevenuePerPaidBill)}',
              ),
              const SizedBox(width: 8),
              _buildKpiCard(
                'Tổng giảm giá',
                ReportExportService.formatCurrency(o.totalDiscount),
                icon: Icons.discount,
                color: Colors.orange.shade800,
                subText: 'VAT: ${ReportExportService.formatCurrency(o.vatTotal)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    String title,
    String value, {
    required IconData icon,
    required Color color,
    String? subText,
    int? prevValue,
    int? currentValue,
  }) {
    String? diffText;
    Color diffColor = Colors.grey;
    if (prevValue != null && currentValue != null && prevValue > 0) {
      final diff = ((currentValue - prevValue) / prevValue * 100);
      final isUp = diff >= 0;
      diffText = '${isUp ? "+" : ""}${diff.toStringAsFixed(1)}%';
      diffColor = isUp ? Colors.green : Colors.red;
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.15)),
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
                    style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (diffText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: diffColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                    child: Text(diffText, style: GoogleFonts.beVietnamPro(fontSize: 9, fontWeight: FontWeight.bold, color: diffColor)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
            if (subText != null) ...[
              const SizedBox(height: 2),
              Text(
                subText,
                style: GoogleFonts.beVietnamPro(fontSize: 9, color: TramColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== BIỂU ĐỒ FL_CHART ====================

  Widget _buildChartSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BIỂU ĐỒ TRỰC QUAN',
            style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: TramColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: _buildChartForSelectedKind(),
          ),
        ],
      ),
    );
  }

  Widget _buildChartForSelectedKind() {
    if (_selectedKind == ReportKind.hourly) {
      final hourly = ReportCalculator.calculateHourlyReport(_currentBills);
      final maxRev = hourly.fold<int>(1, (max, h) => h.netRevenue > max ? h.netRevenue : max);

      return BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxRev * 1.15,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final h = hourly[group.x.toInt()];
                return BarTooltipItem(
                  '${h.hourLabel}\n${ReportExportService.formatCurrency(h.netRevenue)} (${h.billCount} đơn)',
                  GoogleFonts.beVietnamPro(color: Colors.white, fontSize: 10),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final h = val.toInt();
                  if (h % 3 == 0) {
                    return Text('$h h', style: GoogleFonts.beVietnamPro(fontSize: 9, color: Colors.grey));
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: hourly.map((h) => BarChartGroupData(
            x: h.hour,
            barRods: [
              BarChartRodData(
                toY: h.netRevenue.toDouble(),
                color: TramColors.brandPrimary,
                width: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          )).toList(),
        ),
      );
    } else if (_selectedKind == ReportKind.paymentMethods) {
      final payments = ReportCalculator.calculatePaymentMethodsReport(_currentBills);
      final total = payments.values.fold<int>(0, (s, p) => s + p.finalAmount);
      if (total == 0) return const Center(child: Text('Chưa có giao dịch'));

      return Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 36,
                sections: [
                  if ((payments['CASH']?.finalAmount ?? 0) > 0)
                    PieChartSectionData(
                      value: payments['CASH']!.finalAmount.toDouble(),
                      title: '${(payments['CASH']!.finalAmount / total * 100).toStringAsFixed(0)}%',
                      color: Colors.green.shade700,
                      radius: 40,
                      titleStyle: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  if ((payments['TRANSFER_QR']?.finalAmount ?? 0) > 0)
                    PieChartSectionData(
                      value: payments['TRANSFER_QR']!.finalAmount.toDouble(),
                      title: '${(payments['TRANSFER_QR']!.finalAmount / total * 100).toStringAsFixed(0)}%',
                      color: Colors.blue.shade700,
                      radius: 40,
                      titleStyle: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  if ((payments['CARD']?.finalAmount ?? 0) > 0)
                    PieChartSectionData(
                      value: payments['CARD']!.finalAmount.toDouble(),
                      title: '${(payments['CARD']!.finalAmount / total * 100).toStringAsFixed(0)}%',
                      color: Colors.purple.shade700,
                      radius: 40,
                      titleStyle: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendRow('Tiền mặt', Colors.green.shade700, payments['CASH']?.finalAmount ?? 0),
              const SizedBox(height: 6),
              _buildLegendRow('Chuyển khoản QR', Colors.blue.shade700, payments['TRANSFER_QR']?.finalAmount ?? 0),
              const SizedBox(height: 6),
              _buildLegendRow('Thẻ / Khác', Colors.purple.shade700, payments['CARD']?.finalAmount ?? 0),
            ],
          ),
        ],
      );
    } else {
      // Default: Period trend line
      final periodList = ReportCalculator.calculateRevenueByPeriod(_currentBills, PeriodType.day);
      if (periodList.isEmpty) return const Center(child: Text('Chưa có dữ liệu'));

      return BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx >= 0 && idx < periodList.length) {
                    final k = periodList[idx].periodKey;
                    return Text(k.length > 5 ? k.substring(0, 5) : k, style: GoogleFonts.beVietnamPro(fontSize: 9));
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: periodList.asMap().entries.map((e) => BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.netRevenue.toDouble(),
                color: TramColors.brandPrimary,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          )).toList(),
        ),
      );
    }
  }

  Widget _buildLegendRow(String label, Color color, int amount) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label: ', style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary)),
        Text(ReportExportService.formatCurrency(amount), style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ==================== BẢNG BÁO CÁO CHI TIẾT ====================

  Widget _buildReportTableSection() {
    final headers = _getReportHeaders(_selectedKind);
    final rows = _getReportRows(_selectedKind, _currentBills);
    final totalRow = _getReportTotalRow(_selectedKind, _currentBills);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CHI TIẾT: ${_selectedKind.title.toUpperCase()}',
                style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: TramColors.textSecondary),
              ),
              Text(
                '${rows.length} dòng',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
              ),
            ],
          ),
          if (_selectedKind == ReportKind.product) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm món ăn hoặc mã món...',
                      hintStyle: GoogleFonts.beVietnamPro(fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 16),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) => setState(() => _productSearchQuery = v),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _productSort,
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(value: 'REV_DESC', child: Text('Doanh thu cao nhất', style: GoogleFonts.beVietnamPro(fontSize: 11))),
                    DropdownMenuItem(value: 'QTY_DESC', child: Text('Bán chạy nhất', style: GoogleFonts.beVietnamPro(fontSize: 11))),
                    DropdownMenuItem(value: 'NAME_ASC', child: Text('Tên món A-Z', style: GoogleFonts.beVietnamPro(fontSize: 11))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _productSort = val);
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (rows.isEmpty)
            _buildEmptyState()
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8F4EE)),
                headingTextStyle: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
                dataTextStyle: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textPrimary),
                columnSpacing: 16,
                columns: headers.map((h) => DataColumn(
                  label: Text(h),
                  numeric: h.contains('VND') || h.contains('Giá') || h.contains('Doanh thu') || h.contains('Tiền') || h.contains('Lợi nhuận') || h.contains('%') || h.contains('Số lượng'),
                )).toList(),
                rows: [
                  ...rows.map((r) => DataRow(
                    cells: r.map((c) => DataCell(Text(c?.toString() ?? ''))).toList(),
                  )),
                  if (totalRow != null)
                    DataRow(
                      color: WidgetStateProperty.all(const Color(0xFFFDF8F5)),
                      cells: totalRow.map((c) => DataCell(
                        Text(c?.toString() ?? '', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, color: TramColors.brandPrimary)),
                      )).toList(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'Không có dữ liệu trong khoảng thời gian này',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
