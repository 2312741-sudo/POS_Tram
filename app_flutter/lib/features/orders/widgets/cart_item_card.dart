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

class CartItemCard extends StatelessWidget {
  final OrderItemModel item;
  final VoidCallback onRemove;
  final VoidCallback onEditNote;
  final VoidCallback onDiscount;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const CartItemCard({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onEditNote,
    required this.onDiscount,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final hasSize = item.selectedSize.trim().isNotEmpty;
    final hasSugar = item.selectedSugar.trim().isNotEmpty;
    final hasIce = item.selectedIce.trim().isNotEmpty;
    final hasToppings = item.selectedToppings.isNotEmpty;
    final hasDiscount = item.discountAmount > 0;

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
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (item.isSentKitchen)
                          const StatusBadge(
                            label: 'Đã gửi bếp',
                            color: AppColors.success,
                            icon: Icons.check,
                            fontSize: 10,
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Xóa món',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline,
                      size: 22, color: AppColors.textSecondary),
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
                            AppColors.info, AppColors.infoLight),
                      if (hasSugar)
                        _AttrChip(item.selectedSugar.trim(), AppColors.success,
                            AppColors.successLight),
                      if (hasIce)
                        _AttrChip(item.selectedIce.trim(),
                            const Color(0xFF0F5E66), const Color(0xFFE0F2F1)),
                      if (hasToppings)
                        _AttrChip('+${item.selectedToppings.join(', ')}',
                            AppColors.warningInk, AppColors.warningLight),
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
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_note,
                            size: 16, color: AppColors.warningInk),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Ghi chú: ${item.note}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: AppColors.warningInk,
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

            // 4. Giảm giá món
            if (hasDiscount) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    item.discountPercent > 0
                        ? '🏷️ Giảm ${item.discountPercent}% (-${FormatUtils.vnd(item.discountAmount)})${item.discountReason.isNotEmpty ? ": ${item.discountReason}" : ""}'
                        : '🏷️ Giảm -${FormatUtils.vnd(item.discountAmount)}${item.discountReason.isNotEmpty ? ": ${item.discountReason}" : ""}',
                    style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600),
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
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${FormatUtils.vnd(item.unitPrice)} × ${item.quantity}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                FormatUtils.vnd(item.itemTotal),
                                style: GoogleFonts.beVietnamPro(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _ActionPill(
                        icon: Icons.edit_note,
                        label: item.note.isEmpty ? '+ Ghi chú' : 'Ghi chú',
                        compact: compact,
                        onTap: onEditNote,
                      ),
                      const SizedBox(width: 6),
                      _ActionPill(
                        icon: hasDiscount
                            ? Icons.discount
                            : Icons.discount_outlined,
                        label: hasDiscount ? 'Đã giảm' : 'Giảm món',
                        compact: compact,
                        onTap: onDiscount,
                        color: hasDiscount ? AppColors.danger : null,
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
    final fg = color ?? AppColors.textPrimary;
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
                color != null ? AppColors.dangerLight : AppColors.cardElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: color != null
                    ? color!.withValues(alpha: 0.4)
                    : AppColors.border),
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
