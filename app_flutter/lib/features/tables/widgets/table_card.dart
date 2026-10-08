// lib/features/tables/widgets/table_card.dart
//
// Thẻ bàn trên sơ đồ bàn. Chỉ hiển thị – mọi thao tác (mở bàn, đặt trước,
// chuyển/ghép, hủy) được truyền vào qua callback từ TableListScreen.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';

/// Trạng thái hiển thị của bàn (dùng chung cho thẻ bàn và chú thích).
enum TableVisualStatus { empty, inUse, reserved }

class TableStatusStyle {
  final String label;
  final Color color;
  final Color background;
  final IconData icon;
  const TableStatusStyle(this.label, this.color, this.background, this.icon);

  static TableStatusStyle of(TableVisualStatus s) {
    switch (s) {
      case TableVisualStatus.inUse:
        return const TableStatusStyle('Có khách', TramColors.tableInUse, TramColors.tableInUseBg, Icons.people_alt);
      case TableVisualStatus.reserved:
        return const TableStatusStyle('Đặt trước', TramColors.warningInk, TramColors.tableReservedBg, Icons.event_seat);
      case TableVisualStatus.empty:
        return const TableStatusStyle('Trống', TramColors.tableEmpty, Colors.white, Icons.check_circle_outline);
    }
  }

  static TableVisualStatus statusOf(TableModel t) {
    if (t.inUse) return TableVisualStatus.inUse;
    if (t.isReserved) return TableVisualStatus.reserved;
    return TableVisualStatus.empty;
  }
}

class TableCard extends StatelessWidget {
  final TableModel table;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String> onMenuSelected;

  const TableCard({
    super.key,
    required this.table,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final status = TableStatusStyle.statusOf(table);
    final style = TableStatusStyle.of(status);
    final inUse = status == TableVisualStatus.inUse;
    final isReserved = status == TableVisualStatus.reserved;
    final items = table.currentItems;
    final int itemsCount = items.fold(0, (sum, i) => sum + i.quantity);
    final int totalAmount = items.fold(0, (sum, i) => sum + i.itemTotal);

    final accent = status == TableVisualStatus.empty ? AppColors.border : style.color;

    return Semantics(
      button: true,
      label: '${table.name}, ${style.label}',
      child: Material(
        color: style.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(color: accent, width: status == TableVisualStatus.empty ? 1 : 2),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: inUse ? 1.5 : 0,
        shadowColor: style.color.withValues(alpha: 0.3),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dải màu trạng thái – nhận biết ngay từ xa
              Container(height: 5, color: style.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tên bàn + nhãn trạng thái
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              table.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: inUse ? AppColors.primaryDark : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _StatusPill(style: style),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Expanded(child: _buildDetails(style, inUse, isReserved)),
                      // Chân thẻ: tổng tiền / gợi ý + menu thao tác nhanh
                      Row(
                        children: [
                          Expanded(child: _buildFooter(style, inUse, isReserved, itemsCount, totalAmount)),
                          _buildMenu(inUse, isReserved),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(TableStatusStyle style, bool inUse, bool isReserved) {
    final small = GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary);
    final List<Widget> lines = [];

    if (isReserved) {
      lines.add(Text(
        table.reservationCustomer ?? 'Khách hẹn',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: style.color),
      ));
      final sub = [
        if ((table.reservationTime ?? '').isNotEmpty) '🕒 ${table.reservationTime}',
        if ((table.reservationPhone ?? '').isNotEmpty) table.reservationPhone!,
      ].join(' • ');
      if (sub.isNotEmpty) {
        lines.add(Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: small));
      }
      if (table.reservationDeposit > 0) {
        lines.add(Text(
          'Cọc: ${FormatUtils.vnd(table.reservationDeposit)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
        ));
      }
    } else if (inUse) {
      final code = (table.currentBillId != null && table.currentBillId!.isNotEmpty)
          ? 'HĐ: ${table.currentBillId}'
          : ((table.currentOrderCode != null && table.currentOrderCode!.isNotEmpty) ? 'Đơn: ${table.currentOrderCode}' : null);
      final meta = [
        table.zone,
        if (table.guestCount != null && table.guestCount! > 0) '👥 ${table.guestCount}',
        if (table.durationInUse != null) '⏱ ${table.durationInUse!.inMinutes}p',
      ].join(' • ');
      lines.add(Text(
        meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
      ));
      if (code != null) {
        lines.add(Text(code, maxLines: 1, overflow: TextOverflow.ellipsis, style: small.copyWith(fontSize: 11)));
      }
    } else {
      lines.add(Text(table.zone, maxLines: 1, overflow: TextOverflow.ellipsis, style: small));
      if (table.capacity > 0) {
        lines.add(Text('${table.capacity} chỗ', maxLines: 1, overflow: TextOverflow.ellipsis, style: small));
      }
    }

    // Cuộn ẩn (không cho kéo) thay vì tràn khi cỡ chữ hệ thống lớn
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  Widget _buildFooter(TableStatusStyle style, bool inUse, bool isReserved, int itemsCount, int totalAmount) {
    if (inUse) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$itemsCount món',
            style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              FormatUtils.vnd(totalAmount),
              maxLines: 1,
              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
          ),
        ],
      );
    }
    return Text(
      isReserved ? 'Chạm để nhận bàn' : 'Giữ để đặt trước',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.beVietnamPro(
        fontSize: 11,
        color: isReserved ? style.color : AppColors.textSecondary,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildMenu(bool inUse, bool isReserved) {
    return PopupMenuButton<String>(
      tooltip: 'Thao tác nhanh',
      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
      padding: EdgeInsets.zero,
      onSelected: onMenuSelected,
      itemBuilder: (ctx) => [
        if (!inUse && !isReserved)
          _menuItem('RESERVE', Icons.bookmark_add_outlined, 'Đặt trước bàn này', TramColors.warningInk),
        if (inUse) ...[
          _menuItem('TRANSFER', Icons.swap_horiz, 'Chuyển sang bàn khác', TramColors.managerAccent),
          _menuItem('MERGE', Icons.call_merge, 'Ghép vào bàn khác', TramColors.warning),
          _menuItem('CANCEL_BILL', Icons.cancel_outlined, 'Hủy hóa đơn', AppColors.danger, danger: true),
        ],
        _menuItem('QR', Icons.qr_code, 'Xem mã QR', AppColors.textPrimary),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, Color color, {bool danger = false}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Flexible(child: Text(label, style: danger ? const TextStyle(color: AppColors.danger) : null)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final TableStatusStyle style;
  const _StatusPill({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        style.label,
        style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

/// Thanh lọc trạng thái kiêm chú thích màu (legend) của sơ đồ bàn.
class TableStatusFilterBar extends StatelessWidget {
  final String selected; // 'ALL' | 'EMPTY' | 'IN_USE' | 'RESERVED'
  final int total;
  final int emptyCount;
  final int inUseCount;
  final int reservedCount;
  final ValueChanged<String> onSelected;

  const TableStatusFilterBar({
    super.key,
    required this.selected,
    required this.total,
    required this.emptyCount,
    required this.inUseCount,
    required this.reservedCount,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final empty = TableStatusStyle.of(TableVisualStatus.empty);
    final inUse = TableStatusStyle.of(TableVisualStatus.inUse);
    final reserved = TableStatusStyle.of(TableVisualStatus.reserved);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _chip('ALL', 'Tất cả', total, AppColors.textPrimary, Colors.white),
          const SizedBox(width: 8),
          _chip('EMPTY', empty.label, emptyCount, empty.color, empty.background),
          const SizedBox(width: 8),
          _chip('IN_USE', inUse.label, inUseCount, inUse.color, inUse.background),
          const SizedBox(width: 8),
          _chip('RESERVED', reserved.label, reservedCount, reserved.color, reserved.background),
        ],
      ),
    );
  }

  Widget _chip(String key, String label, int count, Color color, Color swatchBg) {
    final isSelected = selected == key;
    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: () => onSelected(key),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: isSelected ? color : AppColors.border, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ô màu mẫu – khớp màu viền/nền của thẻ bàn
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: key == 'ALL' ? Colors.transparent : swatchBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isSelected ? Colors.white : color, width: 2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$label ($count)',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
