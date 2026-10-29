// lib/features/orders/widgets/cart_item_card.dart
//
// Thẻ một món trong giỏ hàng (OrderCartScreen). Chỉ hiển thị; mọi thao tác
// được truyền vào qua callback nên hành vi nghiệp vụ giữ nguyên ở màn hình.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';
import '../../../widgets/common_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CartItemCard extends StatelessWidget {
  final OrderItemModel item;
  final VoidCallback onRemove;
  final VoidCallback onEditNote;
  final VoidCallback onDiscount;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Món đã báo hết hàng sau khi được thêm vào giỏ (chỉ cảnh báo, không xóa món).
  final bool soldOut;

  /// Chi tiết giảm giá khuyến mãi (Combo, Mua X tặng Y, theo hóa đơn...) áp dụng trên dòng này
  final List<({String campaignName, int discountAmount, int quantity, bool isGift})> promoDiscounts;

  /// Nhãn tùy biến cho trạng thái bếp (ví dụ: "Đã gửi bếp (1/8)" khi đơn gồm nhiều đợt gửi)
  final String? kitchenBadgeLabel;

  /// Nội dung nhãn giảm giá của dòng món, gồm số phần được giảm
  /// (VD: "Giảm 10% × 2/5 món (-8.000 đ): Khách quen").
  static String discountLabel(OrderItemModel item) {
    final reason = item.discountReason.isNotEmpty ? ': ${item.discountReason}' : '';
    final desc = item.discountDescription(FormatUtils.vnd);
    if (item.discountMode == 'FIXED') {
      return 'Giảm -${FormatUtils.vnd(item.lineDiscountTotal)}$reason';
    }
    return '$desc (-${FormatUtils.vnd(item.lineDiscountTotal)})$reason';
  }

  const CartItemCard({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onEditNote,
    required this.onDiscount,
    required this.onIncrement,
    required this.onDecrement,
    this.soldOut = false,
    this.promoDiscounts = const [],
    this.kitchenBadgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasSize = item.selectedSize.trim().isNotEmpty;
    final hasSugar = item.selectedSugar.trim().isNotEmpty;
    final hasIce = item.selectedIce.trim().isNotEmpty;
    final hasToppings = item.selectedToppings.isNotEmpty;
    final hasDiscount = item.hasDiscount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Tên món + Badge gửi bếp + Nút xóa món
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          item.name,
                          style: GoogleFonts.beVietnamPro(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: context.tc.textPrimary,
                          ),
                        ),
                        if (soldOut && !item.isSentKitchen)
                          StatusBadge(
                            label: 'Món đã hết hàng',
                            color: context.tc.danger,
                            icon: LucideIcons.triangleAlert,
                            fontSize: 10,
                          ),
                        if (kitchenBadgeLabel != null || item.isSentKitchen)
                          StatusBadge(
                            label: kitchenBadgeLabel ?? 'Đã gửi bếp',
                            color: context.tc.success,
                            icon: LucideIcons.check,
                            fontSize: 10,
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Xóa món',
                  onPressed: onRemove,
                  icon: Icon(LucideIcons.trash2,
                      size: 22, color: context.tc.textSecondary),
                ),
              ],
            ),

            // 2. Size, Đường, Đá, Topping
            if (hasSize || hasSugar || hasIce || hasToppings) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: onEditNote,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (hasSize)
                        _AttrChip('Size ${item.selectedSize.trim()}',
                            context.tc.info, context.tc.infoLight),
                      if (hasSugar)
                        _AttrChip(item.selectedSugar.trim(), context.tc.success,
                            context.tc.successLight),
                      if (hasIce)
                        _AttrChip(item.selectedIce.trim(),
                            context.ink(const Color(0xFF0F5E66)), context.bg(const Color(0xFFE0F2F1))),
                      if (hasToppings)
                        _AttrChip('+${item.selectedToppings.join(', ')}',
                            context.tc.warningInk, context.tc.warningLight),
                    ],
                  ),
                ),
              ),
            ],

            // 3. Ghi chú món
            if (item.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: onEditNote,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.tc.warningLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: context.tc.warning.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.notebookPen,
                            size: 16, color: context.tc.warningInk),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Ghi chú: ${item.note}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: context.tc.warningInk,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // 4. Giảm giá món thủ công
            if (hasDiscount) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.tc.dangerLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: context.tc.danger.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    discountLabel(item),
                    style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: context.tc.danger,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],

            // 4b. Giảm giá do chương trình khuyến mãi (Combo, Mua X tặng Y, ...)
            if (promoDiscounts.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final promo in promoDiscounts)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFFDBA74)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.gift, size: 14, color: Color(0xFFC2410C)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            promo.isGift
                                ? 'Món tặng (100%): ${promo.campaignName}'
                                : 'Giảm KM: -${FormatUtils.vnd(promo.discountAmount)} (${promo.campaignName})',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11,
                              color: const Color(0xFFC2410C),
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 8),

            // 5. Giá tiền + thao tác (Ghi chú, Giảm giá) + Stepper
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Màn hình hẹp (≤ 360dp): nút thao tác chỉ hiện icon để không đè giá tiền
                  final compact = constraints.maxWidth < 380;
                  final totalPromoDiscount = promoDiscounts.fold<int>(0, (s, p) => s + p.discountAmount);
                  final hasAnyDiscount = hasDiscount || totalPromoDiscount > 0;
                  final effectiveTotal = (item.itemTotal - totalPromoDiscount).clamp(0, item.lineGross);

                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(child: Text(
                                  '${FormatUtils.vnd(item.unitPrice)} × ${item.quantity}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.beVietnamPro(
                                      fontSize: 12, color: context.tc.textSecondary),
                                )),
                                if (hasAnyDiscount) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    FormatUtils.vnd(item.lineGross),
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: context.tc.textSecondary,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                FormatUtils.vnd(effectiveTotal),
                                style: GoogleFonts.beVietnamPro(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: hasAnyDiscount ? AppColors.success : context.tc.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _ActionPill(
                        icon: LucideIcons.notebookPen,
                        label: item.note.isEmpty ? '+ Ghi chú' : 'Ghi chú',
                        compact: compact,
                        onTap: onEditNote,
                      ),
                      const SizedBox(width: 6),
                      _ActionPill(
                        icon: hasDiscount
                            ? LucideIcons.badgePercent
                            : LucideIcons.badgePercent,
                        label: hasDiscount ? 'Đã giảm' : 'Giảm món',
                        compact: compact,
                        onTap: onDiscount,
                        color: hasDiscount ? context.tc.danger : null,
                      ),
                      const SizedBox(width: 6),
                      QuantityStepper(
                        value: item.quantity,
                        onDecrement: onDecrement,
                        onIncrement: onIncrement,
                        buttonSize: compact ? 36 : 40,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttrChip extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color bgColor;
  const _AttrChip(this.label, this.textColor, this.bgColor);

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
      child: Text(label.trim(),
          style: TextStyle(
              fontSize: 11, color: textColor, fontWeight: FontWeight.w700)),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool compact;
  const _ActionPill(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.tc.textPrimary;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38, minWidth: 38),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
          decoration: BoxDecoration(
            color:
                color != null ? context.tc.dangerLight : context.tc.cardElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: color != null
                    ? color!.withValues(alpha: 0.4)
                    : context.tc.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 20 : 16, color: fg),
              if (!compact) ...[
                const SizedBox(width: 3),
                Text(label,
                    style: GoogleFonts.beVietnamPro(
                        fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
