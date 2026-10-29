// lib/features/reports/kitchen_sla_screen.dart
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/domain/kitchen_sla.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/share_utils.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum SlaDateFilter {
  today('Hôm nay'),
  yesterday('Hôm qua'),
  last7Days('7 ngày qua'),
  thisMonth('Tháng này'),
  custom('Tùy chọn');

  final String label;
  const SlaDateFilter(this.label);
}

class KitchenSlaScreen extends StatefulWidget {
  const KitchenSlaScreen({super.key});

  @override
  State<KitchenSlaScreen> createState() => _KitchenSlaScreenState();
}

class _KitchenSlaScreenState extends State<KitchenSlaScreen> with SingleTickerProviderStateMixin {
  final _fb = FirebaseService();
  final _auth = AuthService();

  late TabController _tabController;
  SlaDateFilter _dateFilter = SlaDateFilter.today;
  DateTimeRange? _customRange;
  int _thresholdMinutes = 15;
  String _selectedGroup = 'ALL'; // 'ALL', 'drink', 'food'

  bool _loading = true;
  String? _error;
  KitchenSlaSummary? _summary;
  bool _exporting = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTimeRange _resolveRange() {
    final now = DateTime.now();
    switch (_dateFilter) {
      case SlaDateFilter.today:
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case SlaDateFilter.yesterday:
        final y = now.subtract(const Duration(days: 1));
        final start = DateTime(y.year, y.month, y.day);
        final end = DateTime(y.year, y.month, y.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case SlaDateFilter.last7Days:
        final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case SlaDateFilter.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case SlaDateFilter.custom:
        return _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, now.day),
              end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
            );
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final range = _resolveRange();
      final fromMs = range.start.millisecondsSinceEpoch;
      final toMs = range.end.millisecondsSinceEpoch;

      final data = await _fb.kitchenOrdersInRange(
        storeCode: _auth.currentStoreCode,
        fromMs: fromMs,
        toMs: toMs,
      );

      final summary = KitchenSla.compute(
        data,
        threshold: Duration(minutes: _thresholdMinutes),
        fromMs: fromMs,
        toMs: toMs,
      );

      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Lỗi nạp dữ liệu SLA: $e';
          _loading = false;
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '0 phút';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '$s giây';
    return s > 0 ? '$m p $s gi' : '$m phút';
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 3)), end: now),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _dateFilter = SlaDateFilter.custom;
      });
      _loadData();
    }
  }

  Future<void> _exportExcel() async {
    final summary = _summary;
    if (summary == null || summary.orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu đơn bếp để xuất file.')),
      );
      return;
    }

    setState(() => _exporting = true);
    final sm = ScaffoldMessenger.of(context);

    try {
      final excel = Excel.createExcel();
      final sheetOrders = excel['Báo Cáo Đơn Bếp'];
      final sheetItems = excel['Chi Tiết Món'];

      // Header sheet đơn
      sheetOrders.appendRow([
        TextCellValue('Mã đơn'),
        TextCellValue('Tên bàn'),
        TextCellValue('Số món'),
        TextCellValue('Gửi bếp lúc'),
        TextCellValue('Hoàn thành lúc'),
        TextCellValue('Thời gian làm (phút)'),
        TextCellValue('Trạng thái SLA'),
        TextCellValue('Ghi chú tách món'),
      ]);

      final timeFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
      for (final o in summary.orders) {
        final durationMin = (o.duration.inSeconds / 60.0).toStringAsFixed(1);
        final isLate = o.isLate(summary.threshold);
        sheetOrders.appendRow([
          TextCellValue(o.orderCode ?? o.orderKey),
          TextCellValue(o.tableName),
          IntCellValue(o.itemCount),
          TextCellValue(timeFmt.format(DateTime.fromMillisecondsSinceEpoch(o.sentAt))),
          TextCellValue(timeFmt.format(DateTime.fromMillisecondsSinceEpoch(o.doneAt))),
          TextCellValue(durationMin),
          TextCellValue(isLate ? 'TRỄ (${summary.threshold.inMinutes}p)' : 'ĐẠT'),
          TextCellValue(o.isPartialSplit ? 'Tách xong nước/bánh trước' : ''),
        ]);
      }

      // Header sheet món
      sheetItems.appendRow([
        TextCellValue('Mã đơn'),
        TextCellValue('Tên bàn'),
        TextCellValue('Tên món'),
        TextCellValue('Phân loại'),
        TextCellValue('Số lượng'),
        TextCellValue('Gửi bếp lúc'),
        TextCellValue('Xong lúc'),
        TextCellValue('Thời gian làm (phút)'),
      ]);

      for (final it in summary.items) {
        final durationMin = (it.duration.inSeconds / 60.0).toStringAsFixed(1);
        sheetItems.appendRow([
          TextCellValue(it.orderKey),
          TextCellValue(it.tableName),
          TextCellValue(it.itemName),
          TextCellValue(kitchenGroupLabel(it.group)),
          IntCellValue(it.quantity),
          TextCellValue(timeFmt.format(DateTime.fromMillisecondsSinceEpoch(it.sentAt))),
          TextCellValue(timeFmt.format(DateTime.fromMillisecondsSinceEpoch(it.doneAt))),
          TextCellValue(durationMin),
        ]);
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) throw Exception('Không thể tạo file Excel');

      final tempDir = await getTemporaryDirectory();
      final dateTag = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${tempDir.path}/BaoCao_SOS_Bep_${_auth.currentStoreCode}_$dateTag.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      if (!mounted) return;
      await shareFilesSafe(
        [XFile(filePath)],
        subject: 'Báo cáo thời gian phục vụ bếp (SOS / SLA) - Chi nhánh ${_auth.currentStoreCode}',
        context: context,
      );

      sm.showSnackBar(
        const SnackBar(content: Text('Xuất file báo cáo Excel thành công!'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      sm.showSnackBar(
        SnackBar(content: Text('Lỗi xuất Excel: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _confirmClearSlaData() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(LucideIcons.trash2, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Xoá dữ liệu báo cáo SOS',
                style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Bạn muốn xoá lịch sử thời gian phục vụ bếp (SOS) theo khoảng đang lọc (${_dateFilter.label}) hay xoá toàn bộ dữ liệu SOS của chi nhánh ${_auth.currentStoreCode}?\n\nLưu ý: Các đơn đang chờ chế biến trong bếp sẽ được giữ nguyên.',
          style: GoogleFonts.beVietnamPro(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'range'),
            child: Text('Xoá (${_dateFilter.label})'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('Xoá tất cả SOS'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    setState(() => _clearing = true);
    final sm = ScaffoldMessenger.of(context);
    try {
      int deleted = 0;
      if (choice == 'range') {
        final range = _resolveRange();
        deleted = await _fb.clearKitchenSlaData(
          storeCode: _auth.currentStoreCode,
          fromMs: range.start.millisecondsSinceEpoch,
          toMs: range.end.millisecondsSinceEpoch,
        );
      } else {
        deleted = await _fb.clearKitchenSlaData(
          storeCode: _auth.currentStoreCode,
        );
      }
      if (!mounted) return;
      sm.showSnackBar(
        SnackBar(
          content: Text('Đã xoá $deleted bản ghi dữ liệu SOS thành công!'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadData();
    } catch (e) {
      sm.showSnackBar(
        SnackBar(content: Text('Lỗi xoá dữ liệu SOS: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final filteredItems = (summary?.items ?? []).where((it) {
      if (_selectedGroup == 'ALL') return true;
      return it.group == _selectedGroup;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Đo Tốc Độ Phục Vụ (SOS / Bếp)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(fontSize: 15.5, fontWeight: FontWeight.bold),
            ),
            Text(
              'Từ lúc gửi bếp đến khi hoàn tất • ${_auth.currentStoreCode}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(LucideIcons.table, color: Colors.greenAccent),
            tooltip: 'Xuất file Excel báo cáo SOS',
            onPressed: (_exporting || _loading || _clearing) ? null : _exportExcel,
          ),
          IconButton(
            icon: _clearing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(LucideIcons.trash, color: Colors.amberAccent),
            tooltip: 'Xoá dữ liệu SOS',
            onPressed: (_clearing || _loading || _exporting) ? null : _confirmClearSlaData,
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Tải lại',
            onPressed: (_loading || _clearing) ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amberAccent,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.receiptText, size: 17),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Theo Đơn Hàng',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.utensils, size: 17),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Chi Tiết Từng Món',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.tc.card,
              border: Border(bottom: BorderSide(color: context.tc.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in SlaDateFilter.values) ...[
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _dateFilter == f,
                      onSelected: (val) {
                        if (!val) return;
                        if (f == SlaDateFilter.custom) {
                          _pickCustomRange();
                        } else {
                          setState(() => _dateFilter = f);
                          _loadData();
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                  const SizedBox(width: 8),
                  Container(height: 24, width: 1, color: context.tc.border),
                  const SizedBox(width: 8),
                  Text('Ngưỡng trễ:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  DropdownButton<int>(
                    value: _thresholdMinutes,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 phút')),
                      DropdownMenuItem(value: 10, child: Text('10 phút')),
                      DropdownMenuItem(value: 15, child: Text('15 phút')),
                      DropdownMenuItem(value: 20, child: Text('20 phút')),
                      DropdownMenuItem(value: 30, child: Text('30 phút')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _thresholdMinutes = val);
                        _loadData();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: _loading
                ? const LoadingState(message: 'Đang tải dữ liệu thời gian bếp...')
                : _error != null
                    ? ErrorState(title: 'Lỗi tải dữ liệu', message: _error!, onRetry: _loadData)
                    : (summary == null || summary.orders.isEmpty)
                        ? const EmptyState(
                            icon: LucideIcons.timer,
                            title: 'Chưa có dữ liệu đơn bếp hoàn tất',
                            subtitle: 'Hệ thống sẽ đo thời gian ngay khi bếp bấm hoàn thành các đơn gọi món.',
                          )
                        : Column(
                            children: [
                              // KPI Cards
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                                child: Row(
                                  children: [
                                    _buildKpiCard(
                                      title: 'TB / Đơn',
                                      value: _formatDuration(summary.averageOrder),
                                      icon: LucideIcons.timer,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 6),
                                    _buildKpiCard(
                                      title: 'Chậm nhất',
                                      value: _formatDuration(summary.maxOrder),
                                      icon: LucideIcons.triangleAlert,
                                      color: Colors.deepOrange,
                                    ),
                                    const SizedBox(width: 6),
                                    _buildKpiCard(
                                      title: 'TB / Món',
                                      value: _formatDuration(summary.averageItem),
                                      icon: LucideIcons.coffee,
                                      color: Colors.teal,
                                    ),
                                    const SizedBox(width: 6),
                                    _buildKpiCard(
                                      title: 'Tỉ lệ trễ',
                                      value:
                                          '${summary.lateOrderCount}/${summary.orders.length} (${(summary.lateOrderCount * 100 / summary.orders.length).toStringAsFixed(0)}%)',
                                      icon: LucideIcons.triangleAlert,
                                      color: summary.lateOrderCount > 0 ? AppColors.danger : AppColors.success,
                                    ),
                                  ],
                                ),
                              ),

                              // Tab Content
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    // Tab 1: Orders
                                    ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                                      itemCount: summary.orders.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (context, i) {
                                        final o = summary.orders[i];
                                        final isLate = o.isLate(summary.threshold);
                                        final timeFmt = DateFormat('HH:mm:ss');
                                        final hasOrderCode = o.orderCode != null && o.orderCode!.isNotEmpty;
                                        return Card(
                                          elevation: 1,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            side: BorderSide(
                                              color: isLate ? Colors.red.shade300 : context.tc.border,
                                            ),
                                          ),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            leading: CircleAvatar(
                                              radius: 18,
                                              backgroundColor: isLate ? Colors.red.shade100 : Colors.green.shade100,
                                              child: Icon(
                                                isLate ? LucideIcons.timerOff : LucideIcons.check,
                                                color: isLate ? AppColors.danger : AppColors.success,
                                                size: 18,
                                              ),
                                            ),
                                            title: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    o.tableName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.beVietnamPro(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isLate ? Colors.red.shade50 : Colors.green.shade50,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: isLate ? Colors.red.shade200 : Colors.green.shade200,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    _formatDuration(o.duration),
                                                    style: GoogleFonts.beVietnamPro(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                      color: isLate ? AppColors.danger : AppColors.success,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (hasOrderCode) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    'Mã đơn: ${o.orderCode} • ${o.itemCount} món',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.beVietnamPro(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w500,
                                                      color: context.tc.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Gửi: ${timeFmt.format(DateTime.fromMillisecondsSinceEpoch(o.sentAt))} ➔ Xong: ${timeFmt.format(DateTime.fromMillisecondsSinceEpoch(o.doneAt))}${hasOrderCode ? "" : " (${o.itemCount} món)"}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.beVietnamPro(fontSize: 12),
                                                ),
                                                if (o.isPartialSplit)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Text(
                                                      'Có tách xong phần nước/bánh trước',
                                                      style: GoogleFonts.beVietnamPro(
                                                        fontSize: 11,
                                                        color: Colors.blue.shade700,
                                                        fontStyle: FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),

                                    // Tab 2: Items
                                    Column(
                                      children: [
                                        // Group selector
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                ChoiceChip(
                                                  label: const Text('Tất cả món'),
                                                  selected: _selectedGroup == 'ALL',
                                                  onSelected: (_) => setState(() => _selectedGroup = 'ALL'),
                                                ),
                                                const SizedBox(width: 8),
                                                ChoiceChip(
                                                  label: const Text('Nước uống'),
                                                  selected: _selectedGroup == kKitchenGroupDrink,
                                                  onSelected: (_) => setState(() => _selectedGroup = kKitchenGroupDrink),
                                                ),
                                                const SizedBox(width: 8),
                                                ChoiceChip(
                                                  label: const Text('Bánh / Món ăn'),
                                                  selected: _selectedGroup == kKitchenGroupFood,
                                                  onSelected: (_) => setState(() => _selectedGroup = kKitchenGroupFood),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: ListView.separated(
                                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                                            itemCount: filteredItems.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                                            itemBuilder: (context, i) {
                                              final it = filteredItems[i];
                                              final timeFmt = DateFormat('HH:mm:ss');
                                              return ListTile(
                                                tileColor: context.tc.card,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  side: BorderSide(color: context.tc.border),
                                                ),
                                                leading: Icon(
                                                  it.group == kKitchenGroupFood ? LucideIcons.cake : LucideIcons.coffee,
                                                  color: context.tc.primary,
                                                ),
                                                title: Text(
                                                  '${it.quantity}x ${it.itemName}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, fontSize: 14),
                                                ),
                                                subtitle: Text(
                                                  'Bàn: ${it.tableName} • Gửi: ${timeFmt.format(DateTime.fromMillisecondsSinceEpoch(it.sentAt))} ➔ Xong: ${timeFmt.format(DateTime.fromMillisecondsSinceEpoch(it.doneAt))}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.beVietnamPro(fontSize: 11.5),
                                                ),
                                                trailing: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: context.tc.primary.withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    _formatDuration(it.duration),
                                                    style: GoogleFonts.beVietnamPro(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                      color: context.tc.primary,
                                                    ),
                                                  ),
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
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
