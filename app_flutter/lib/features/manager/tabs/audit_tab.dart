// lib/features/manager/tabs/audit_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/permissions/app_permissions.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/firebase_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AuditTab extends StatefulWidget {
  const AuditTab({super.key});

  @override
  State<AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<AuditTab> {
  final _fb = FirebaseService();
  List<AuditLogModel> _logs = [];
  bool _loading = true;
  bool _denied = false;
  Timer? _safetyTimer;

  String _search = '';
  String _categoryFilter = 'ALL'; // 'ALL', 'SUSPICIOUS', 'CANCEL', 'PAYMENT', 'TABLE', 'SHIFT'

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    super.dispose();
  }

  void _loadLogs() {
    final auth = AuthService();
    if (!(auth.isRootOwner || auth.can(AppPermissions.viewAuditLogs))) {
      // Không có quyền xem nhật ký thao tác: không đăng ký luồng dữ liệu (rules cũng chặn đọc).
      _loading = false;
      _denied = true;
      return;
    }
    _safetyTimer?.cancel();
    _safetyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _loading) setState(() => _loading = false);
    });

    _fb.auditLogsStream().listen((list) {
      _safetyTimer?.cancel();
      if (mounted) {
        setState(() {
          _logs = list;
          _loading = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  int get _suspiciousCount => _logs.where((l) => l.isSuspicious).length;
  static bool _isCancelLike(String action) => action.contains('CANCEL') || action.contains('HỦY') || action == 'DELETE_ITEM';
  int get _cancelItemCount => _logs.where((l) => _isCancelLike(l.action)).length;
  int get _discountCount => _logs.where((l) => l.action.contains('DISCOUNT') || l.action.contains('GIẢM')).length;

  List<AuditLogModel> get _filteredLogs {
    return _logs.where((l) {
      // Category filter
      if (_categoryFilter == 'SUSPICIOUS' && !l.isSuspicious) return false;
      if (_categoryFilter == 'CANCEL' && !_isCancelLike(l.action)) return false;
      if (_categoryFilter == 'PAYMENT' && !l.action.contains('PAY') && !l.action.contains('BILL') && !l.action.contains('DISCOUNT')) return false;
      if (_categoryFilter == 'TABLE' && !l.action.contains('TABLE') && !l.action.contains('BÀN')) return false;
      if (_categoryFilter == 'SHIFT' && !l.action.contains('SHIFT') && !l.action.contains('CA')) return false;

      // Search filter
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final matchUser = l.userFullName.toLowerCase().contains(q) || l.username.toLowerCase().contains(q);
        final matchAction = l.action.toLowerCase().contains(q);
        final matchDetails = l.details.toLowerCase().contains(q);
        final matchTarget = l.targetId.toLowerCase().contains(q);

        if (!matchUser && !matchAction && !matchDetails && !matchTarget) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Bạn không có quyền xem lịch sử thao tác. Liên hệ Chủ quán để được cấp quyền.',
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(fontSize: 14, color: context.tc.textSecondary),
          ),
        ),
      );
    }
    if (_loading && _logs.isEmpty) {
      return Center(child: CircularProgressIndicator(color: context.tc.primary));
    }

    final filtered = _filteredLogs;

    return RefreshIndicator(
      color: context.tc.primary,
      onRefresh: () async {
        setState(() {});
      },
      child: Column(
        children: [
          // Anti-Fraud Summary Banner
          Container(
            padding: const EdgeInsets.all(14),
            color: context.tc.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Row(
                      children: [
                        Icon(LucideIcons.shieldCheck, size: 22, color: context.tc.danger),
                        const SizedBox(width: 8),
                        Flexible(child: Text(
                          'Giám Sát & Chống Gian Lận',
                          style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold, color: context.tc.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    )),
                    if (_suspiciousCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: context.tc.dangerLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: context.tc.danger.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '$_suspiciousCount cảnh báo',
                          style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: context.tc.danger),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3 Mini stat chips
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStatChip(
                        title: 'Nghi vấn',
                        count: '$_suspiciousCount ca',
                        icon: LucideIcons.triangleAlert,
                        color: context.tc.danger,
                        active: _categoryFilter == 'SUSPICIOUS',
                        onTap: () => setState(() => _categoryFilter = _categoryFilter == 'SUSPICIOUS' ? 'ALL' : 'SUSPICIOUS'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMiniStatChip(
                        title: 'Hủy món bếp',
                        count: '$_cancelItemCount lần',
                        icon: LucideIcons.chefHat,
                        color: context.tc.warning,
                        active: _categoryFilter == 'CANCEL',
                        onTap: () => setState(() => _categoryFilter = _categoryFilter == 'CANCEL' ? 'ALL' : 'CANCEL'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMiniStatChip(
                        title: 'Giảm giá tay',
                        count: '$_discountCount lần',
                        icon: LucideIcons.badgePercent,
                        color: context.tc.info,
                        active: _categoryFilter == 'PAYMENT',
                        onTap: () => setState(() => _categoryFilter = _categoryFilter == 'PAYMENT' ? 'ALL' : 'PAYMENT'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm theo nhân viên, bàn, món, thao tác...',
                    hintStyle: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textHint),
                    prefixIcon: Icon(LucideIcons.search, size: 20, color: context.tc.primary),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: () => setState(() => _search = ''),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: context.tc.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.tc.borderLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.tc.borderLight),
                    ),
                  ),
                  onChanged: (val) => setState(() => _search = val.trim()),
                ),
                const SizedBox(height: 8),

                // Category Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Tất cả', 'ALL'),
                      const SizedBox(width: 6),
                      _buildFilterChip('Nghi vấn', 'SUSPICIOUS', isWarning: true),
                      const SizedBox(width: 6),
                      _buildFilterChip('Hủy món bếp', 'CANCEL'),
                      const SizedBox(width: 6),
                      _buildFilterChip('Thanh toán & Giảm giá', 'PAYMENT'),
                      const SizedBox(width: 6),
                      _buildFilterChip('Đổi/Gộp bàn', 'TABLE'),
                      const SizedBox(width: 6),
                      _buildFilterChip('Ca & Két tiền', 'SHIFT'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Total Count Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: context.tc.cardElevated,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(
                  'Nhật ký thao tác (${filtered.length} sự kiện)',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: context.tc.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(
                  'Cập nhật thời gian thực',
                  style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.success),
                ),
              ],
            ),
          ),

          // Logs List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.shield, size: 56, color: context.tc.textHint),
                        const SizedBox(height: 10),
                        Text(
                          'Không có nhật ký nào phù hợp bộ lọc',
                          style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final log = filtered[index];
                      return _buildAuditLogCard(log);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatChip({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : context.tc.cardElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? color : context.tc.border, width: active ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 2),
            Text(
              count,
              style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
            Text(
              title,
              style: GoogleFonts.beVietnamPro(fontSize: 10, color: context.tc.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, {bool isWarning = false}) {
    final isSelected = _categoryFilter == key;
    Color chipColor = isWarning ? context.tc.danger : context.tc.primary;

    return InkWell(
      onTap: () => setState(() => _categoryFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? chipColor : context.tc.cardElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? chipColor : context.tc.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : context.tc.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildAuditLogCard(AuditLogModel log) {
    final timeStr = DateFormat('HH:mm - dd/MM/yyyy').format(log.dateTime);
    final isSuspicious = log.isSuspicious;

    Color iconColor;
    IconData iconData;

    if (_isCancelLike(log.action)) {
      iconColor = context.tc.danger;
      iconData = LucideIcons.circleX;
    } else if (log.action.contains('DISCOUNT') || log.action.contains('GIẢM')) {
      iconColor = context.tc.warning;
      iconData = LucideIcons.badgePercent;
    } else if (log.action.contains('TABLE') || log.action.contains('BÀN')) {
      iconColor = const Color(0xFF0284C7);
      iconData = LucideIcons.arrowLeftRight;
    } else if (log.action.contains('PAY') || log.action.contains('THANH')) {
      iconColor = context.tc.success;
      iconData = LucideIcons.circleCheck;
    } else {
      iconColor = context.tc.info;
      iconData = LucideIcons.history;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSuspicious ? context.tc.card : context.tc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSuspicious ? context.tc.danger.withValues(alpha: 0.6) : context.tc.borderLight,
          width: isSuspicious ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Suspicious Alert Banner
          if (isSuspicious) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.tc.dangerLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.tc.danger.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.triangleAlert, size: 14, color: context.tc.danger),
                  const SizedBox(width: 6),
                  Flexible(child: Text(
                    'CẢNH BÁO THAO TÁC NGHI VẤN GIAN LẬN',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: context.tc.danger,
                    ),
                  )),
                ],
              ),
            ),
          ],

          // Row 1: Action + User + Time
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(iconData, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: Text(
                          log.action,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSuspicious ? context.tc.danger : context.tc.textPrimary,
                          ), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(
                          timeStr,
                          style: GoogleFonts.beVietnamPro(fontSize: 10, color: context.tc.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nhân viên: ${log.userFullName.isNotEmpty ? log.userFullName : log.username} (${log.userRole})',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.tc.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Details text
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSuspicious ? context.tc.card : context.tc.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSuspicious ? context.tc.danger.withValues(alpha: 0.2) : context.tc.borderLight),
            ),
            child: Text(
              log.details,
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textPrimary),
            ),
          ),

          // State Comparison (Before vs After)
          if (log.beforeState != null && log.afterState != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.tc.cardElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.tc.borderLight),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trước khi đổi:',
                          style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.bold, color: context.tc.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          log.beforeState.toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(LucideIcons.arrowRight, size: 14, color: context.tc.textHint),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sau khi đổi:',
                          style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.bold, color: context.tc.primary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          log.afterState.toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: context.tc.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
