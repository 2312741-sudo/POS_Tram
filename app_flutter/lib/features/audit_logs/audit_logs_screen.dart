// lib/features/audit_logs/audit_logs_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  String _searchStaff = '';
  String _selectedAction = 'ALL';
  bool _onlySuspicious = false;
  DateTimeRange? _selectedDateRange;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch Sử Thao Tác & Chống Gian Lận'),
      ),
      body: StreamBuilder<List<AuditLogModel>>(
        stream: _fb.auditLogsStream(),
        initialData: const [],
        builder: (context, snapshot) {
          final allLogs = snapshot.data ?? [];

          // Filter logs
          final filteredLogs = allLogs.where((log) {
            // 1. Staff search
            if (_searchStaff.isNotEmpty) {
              final q = _searchStaff.toLowerCase();
              final match = log.username.toLowerCase().contains(q) || log.userFullName.toLowerCase().contains(q);
              if (!match) return false;
            }

            // 2. Action filter
            if (_selectedAction != 'ALL' && log.action != _selectedAction) {
              return false;
            }

            // 3. Suspicious filter
            if (_onlySuspicious && !log.isSuspicious) {
              return false;
            }

            // 4. Date range filter
            if (_selectedDateRange != null) {
              final logDate = DateTime.fromMillisecondsSinceEpoch(log.timestamp);
              final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
              final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);
              if (logDate.isBefore(start) || logDate.isAfter(end)) {
                return false;
              }
            }

            return true;
          }).toList();

          return Column(
            children: [
              // Filter Card
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Tìm nhân viên...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onChanged: (v) => setState(() => _searchStaff = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _selectedAction,
                            isDense: true,
                            decoration: InputDecoration(
                              labelText: 'Loại thao tác',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'ALL', child: Text('Tất cả thao tác')),
                              DropdownMenuItem(value: 'LOGIN', child: Text('Đăng nhập')),
                              DropdownMenuItem(value: 'LOGOUT', child: Text('Đăng xuất')),
                              DropdownMenuItem(value: 'CREATE_BILL', child: Text('Tạo hóa đơn')),
                              DropdownMenuItem(value: 'CANCEL_BILL', child: Text('Hủy hóa đơn')),
                              DropdownMenuItem(value: 'APPLY_DISCOUNT', child: Text('Áp dụng khuyến mãi')),
                              DropdownMenuItem(value: 'MANUAL_DISCOUNT', child: Text('Bớt tiền thủ công')),
                              DropdownMenuItem(value: 'SEND_KITCHEN', child: Text('Gửi bếp')),
                              DropdownMenuItem(value: 'CANCEL_KITCHEN_ITEM', child: Text('Hủy món đã gửi bếp')),
                              DropdownMenuItem(value: 'MERGE_TABLE', child: Text('Ghép bàn')),
                              DropdownMenuItem(value: 'SPLIT_BILL', child: Text('Tách bill')),
                              DropdownMenuItem(value: 'CHANGE_PERMISSION', child: Text('Phân quyền')),
                              DropdownMenuItem(value: 'PRINT_BILL', child: Text('In hóa đơn')),
                              DropdownMenuItem(value: 'REPRINT_BILL', child: Text('In lại hóa đơn')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedAction = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilterChip(
                          selected: _onlySuspicious,
                          avatar: Icon(Icons.security, size: 16, color: _onlySuspicious ? Colors.white : AppColors.danger),
                          label: Text(
                            'Chỉ xem thao tác nhạy cảm / cảnh báo',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: _onlySuspicious ? Colors.white : AppColors.danger,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          selectedColor: AppColors.danger,
                          backgroundColor: AppColors.dangerLight,
                          onSelected: (val) => setState(() => _onlySuspicious = val),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.date_range, size: 16),
                          label: Text(
                            _selectedDateRange == null
                                ? 'Chọn ngày'
                                : '${DateFormat("dd/MM").format(_selectedDateRange!.start)} - ${DateFormat("dd/MM").format(_selectedDateRange!.end)}',
                            style: GoogleFonts.beVietnamPro(fontSize: 12),
                          ),
                          onPressed: () async {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                              initialDateRange: _selectedDateRange,
                            );
                            if (picked != null) {
                              setState(() => _selectedDateRange = picked);
                            }
                          },
                        ),
                        if (_selectedDateRange != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _selectedDateRange = null),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Log list
              Expanded(
                child: filteredLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text('Không tìm thấy nhật ký thao tác phù hợp', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredLogs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final log = filteredLogs[index];
                          return _buildLogCard(log);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogCard(AuditLogModel log) {
    Color badgeColor = AppColors.info;
    Color badgeBg = AppColors.infoLight;

    if (log.isSuspicious || log.action == 'CANCEL_BILL' || log.action == 'CANCEL_KITCHEN_ITEM' || log.action == 'MANUAL_DISCOUNT') {
      badgeColor = AppColors.danger;
      badgeBg = AppColors.dangerLight;
    } else if (log.action == 'APPLY_DISCOUNT' || log.action == 'CHANGE_PERMISSION' || log.action == 'MERGE_TABLE') {
      badgeColor = AppColors.warning;
      badgeBg = AppColors.warningLight;
    } else if (log.action == 'CREATE_BILL' || log.action == 'LOGIN') {
      badgeColor = AppColors.success;
      badgeBg = AppColors.successLight;
    }

    final hasSnapshot = log.beforeState != null || log.afterState != null;

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
          child: Icon(
            log.isSuspicious ? Icons.warning_amber_rounded : Icons.history,
            color: badgeColor,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6)),
              child: Text(
                log.action,
                style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                log.details,
                style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                '${log.userFullName} (@${log.username})',
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              Text(
                '• ${FormatUtils.dateTime(log.timestamp)}',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
        ),
        children: [
          const Divider(),
          Row(
            children: [
              Text('Mục tiêu: ${log.targetType} [${log.targetId}]', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (log.isSuspicious)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.dangerLight, borderRadius: BorderRadius.circular(4)),
                  child: Text('CẢNH BÁO RỦI RO', style: GoogleFonts.beVietnamPro(fontSize: 10, color: AppColors.danger, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(log.details, style: GoogleFonts.beVietnamPro(fontSize: 13)),

          // Before and After Snapshot diff
          if (hasSnapshot) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DỮ LIỆU THAY ĐỔI (SNAPSHOT DIFF):', style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  if (log.beforeState != null) ...[
                    Text('🔴 Trước khi đổi:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.danger)),
                    Text(const JsonEncoder.withIndent('  ').convert(log.beforeState), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    const SizedBox(height: 6),
                  ],
                  if (log.afterState != null) ...[
                    Text('🟢 Sau khi đổi:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success)),
                    Text(const JsonEncoder.withIndent('  ').convert(log.afterState), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
