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
/// [awaitingPayment] = có khách và đã in phiếu tạm tính (TableModel.prePrintedAt).
enum TableVisualStatus { empty, inUse, awaitingPayment, reserved }

class TableStatusStyle {
  final String label;

  /// Màu nhận diện: dải màu, viền thẻ, nền nhãn trạng thái (chữ trắng đặt lên trên).
  final Color color;

  /// Nền thẻ bàn / ô màu mẫu trong chú thích.
  final Color background;

  /// Chữ/icon màu trạng thái đặt trên [background] (hoặc nền thẻ) – đủ tương phản.
  final Color ink;
  final IconData icon;
  const TableStatusStyle(this.label, this.color, this.background, this.icon, {Color? ink}) : ink = ink ?? color;

  /// Kiểu hiển thị theo theme hiện tại (sáng/tối).
  static TableStatusStyle resolve(BuildContext context, TableVisualStatus s) =>
      of(s, dark: context.isDarkMode);

  static TableStatusStyle of(TableVisualStatus s, {bool dark = false}) {
    switch (s) {
      case TableVisualStatus.inUse:
        return dark
            ? const TableStatusStyle('Có khách', TramColors.tableInUseDark, TramColors.tableInUseBgDark, Icons.people_alt,
                ink: TramColors.tableInUseInkDark)
            : const TableStatusStyle('Có khách', TramColors.tableInUse, TramColors.tableInUseBg, Icons.people_alt,
                ink: TramColors.brandDark);
      case TableVisualStatus.awaitingPayment:
        return dark
            ? const TableStatusStyle('Chờ thanh toán', TramColors.tableAwaitingPaymentDark, TramColors.tableAwaitingPaymentBgDark,
                Icons.receipt_long, ink: TramColors.tableAwaitingPaymentInkDark)
            : const TableStatusStyle('Chờ thanh toán', TramColors.tableAwaitingPayment, TramColors.tableAwaitingPaymentBg, Icons.receipt_long);
      case TableVisualStatus.reserved:
        return dark
            ? const TableStatusStyle('Đặt trước', TramColors.tableReservedDark, TramColors.tableReservedBgDark, Icons.event_seat,
                ink: TramColors.tableReservedInkDark)
            : const TableStatusStyle('Đặt trước', TramColors.warningInk, TramColors.tableReservedBg, Icons.event_seat);
      case TableVisualStatus.empty:
        return dark
            ? TableStatusStyle('Trống', TramColors.tableEmptyDark, TramTokens.dark.card, Icons.check_circle_outline,
                ink: TramColors.tableEmptyInkDark)
            : const TableStatusStyle('Trống', TramColors.tableEmpty, Colors.white, Icons.check_circle_outline);
    }
  }

  static TableVisualStatus statusOf(TableModel t) {
    if (t.inUse) return t.isAwaitingPayment ? TableVisualStatus.awaitingPayment : TableVisualStatus.inUse;
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
    final style = TableStatusStyle.resolve(context, status);
    final tc = context.tc;
    final awaiting = status == TableVisualStatus.awaitingPayment;
    // Bàn chờ thanh toán vẫn là bàn có khách (chi tiết, tổng tiền, menu thao tác giống nhau).
    final inUse = status == TableVisualStatus.inUse || awaiting;
    final isReserved = status == TableVisualStatus.reserved;
    final items = table.currentItems;
    final int itemsCount = items.fold(0, (sum, i) => sum + i.quantity);
    final int totalAmount = items.fold(0, (sum, i) => sum + i.itemTotal);

    final accent = status == TableVisualStatus.empty ? tc.border : style.color;

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
                                color: inUse ? style.ink : tc.textPrimary,
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
                      Expanded(child: _buildDetails(context, style, inUse, isReserved)),
                      // Chân thẻ: tổng tiền / gợi ý + menu thao tác nhanh
                      Row(
                        children: [
                          Expanded(child: _buildFooter(context, style, inUse, isReserved, itemsCount, totalAmount)),
                          _buildMenu(context, inUse, isReserved),
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

  Widget _buildDetails(BuildContext context, TableStatusStyle style, bool inUse, bool isReserved) {
    final small = GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary);
    final List<Widget> lines = [];

    if (isReserved) {
      lines.add(Text(
        table.reservationCustomer ?? 'Khách hẹn',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: style.ink),
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
          style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.ink(TramColors.success)),
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
        style: GoogleFonts.beVietnamPro(fontSize: 12, color: style.ink, fontWeight: FontWeight.w600),
      ));
      if (code != null) {
        lines.add(Text(code, maxLines: 1, overflow: TextOverflow.ellipsis, style: small.copyWith(fontSize: 11)));
      }
      if (table.isAwaitingPayment) {
        final at = DateTime.fromMillisecondsSinceEpoch(table.prePrintedAt!);
        final hhmm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
        lines.add(Text(
          '🧾 Đã in tạm tính $hhmm',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: small.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: style.ink),
        ));
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

  Widget _buildFooter(BuildContext context, TableStatusStyle style, bool inUse, bool isReserved, int itemsCount, int totalAmount) {
    if (inUse) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$itemsCount món',
            style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary, fontWeight: FontWeight.w600),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              FormatUtils.vnd(totalAmount),
              maxLines: 1,
              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.w800, color: context.isDarkMode ? style.ink : TramColors.primary),
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
        color: isReserved ? style.ink : context.tc.textSecondary,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildMenu(BuildContext context, bool inUse, bool isReserved) {
    final tc = context.tc;
    return PopupMenuButton<String>(
      tooltip: 'Thao tác nhanh',
      icon: Icon(Icons.more_vert, size: 20, color: tc.textSecondary),
      padding: EdgeInsets.zero,
      onSelected: onMenuSelected,
      itemBuilder: (ctx) => [
        if (!inUse && !isReserved)
          _menuItem('RESERVE', Icons.bookmark_add_outlined, 'Đặt trước bàn này', tc.warningInk),
        if (inUse) ...[
          _menuItem('TRANSFER', Icons.swap_horiz, 'Chuyển sang bàn khác', context.ink(TramColors.managerAccent)),
          _menuItem('MERGE', Icons.call_merge, 'Ghép vào bàn khác', tc.warning),
          _menuItem('CANCEL_BILL', Icons.cancel_outlined, 'Hủy hóa đơn', tc.danger, danger: true),
        ],
        _menuItem('QR', Icons.qr_code, 'Xem mã QR', tc.textPrimary),
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
          Flexible(child: Text(label, style: danger ? TextStyle(color: color) : null)),
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
  final String selected; // 'ALL' | 'EMPTY' | 'IN_USE' | 'AWAITING' | 'RESERVED'
  final int total;
  final int emptyCount;
  final int inUseCount; // Có khách, CHƯA in tạm tính
  final int awaitingCount; // Chờ thanh toán (đã in tạm tính)
  final int reservedCount;
  final ValueChanged<String> onSelected;

  const TableStatusFilterBar({
    super.key,
    required this.selected,
    required this.total,
    required this.emptyCount,
    required this.inUseCount,
    this.awaitingCount = 0,
    required this.reservedCount,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final empty = TableStatusStyle.resolve(context, TableVisualStatus.empty);
    final inUse = TableStatusStyle.resolve(context, TableVisualStatus.inUse);
    final awaiting = TableStatusStyle.resolve(context, TableVisualStatus.awaitingPayment);
    final reserved = TableStatusStyle.resolve(context, TableVisualStatus.reserved);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _chip(context, 'ALL', 'Tất cả', total, tc.textPrimary, tc.textPrimary, tc.card, onFill: tc.card),
          const SizedBox(width: 8),
          _chip(context, 'EMPTY', empty.label, emptyCount, empty.color, empty.ink, empty.background),
          const SizedBox(width: 8),
          _chip(context, 'IN_USE', inUse.label, inUseCount, inUse.color, inUse.ink, inUse.background),
          const SizedBox(width: 8),
          _chip(context, 'AWAITING', awaiting.label, awaitingCount, awaiting.color, awaiting.ink, awaiting.background),
          const SizedBox(width: 8),
          _chip(context, 'RESERVED', reserved.label, reservedCount, reserved.color, reserved.ink, reserved.background),
        ],
      ),
    );
  }

  /// [color] = nền khi chọn / viền ô mẫu, [ink] = chữ khi chưa chọn,
  /// [onFill] = chữ trên nền [color] khi đã chọn.
  Widget _chip(BuildContext context, String key, String label, int count, Color color, Color ink, Color swatchBg,
      {Color onFill = Colors.white}) {
    final tc = context.tc;
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
            color: isSelected ? color : tc.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: isSelected ? color : tc.border, width: 1.2),
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
                  border: Border.all(color: isSelected ? onFill : color, width: 2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$label ($count)',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? onFill : ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
