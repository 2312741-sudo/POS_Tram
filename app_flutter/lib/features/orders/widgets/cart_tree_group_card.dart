// lib/features/orders/widgets/cart_tree_group_card.dart
//
// Hiển thị món trong giỏ hàng theo cấu trúc Cây / Nhánh (Tree Grouped View):
// - GỐC (Root Header): Tên món chung, tổng số phần, tổng tiền sau giảm giá của cả nhóm.
// - NHÁNH (Branches): Các phân nhánh biến thể (Size, Đường, Đá, Topping, Ghi chú, Giảm giá món, Ưu đãi khuyến mãi).
// - Các nhánh được kết nối trực quan bằng đường kẻ cây (Tree Line Painter: ├── và └──).
// - Nếu sản phẩm chỉ có 1 nhánh duy nhất: hiển thị gọn gàng như thẻ đơn thông thường.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/order_item_model.dart';
import '../../../widgets/common_widgets.dart';
import 'cart_item_card.dart';

/// Dữ liệu một nhánh trong nhóm sản phẩm
class CartBranchItem {
  final int cartIndex;
  final OrderItemModel item;
  final List<({String campaignName, int discountAmount, int quantity, bool isGift})> promoDiscounts;
  final bool soldOut;

  const CartBranchItem({
    required this.cartIndex,
    required this.item,
    this.promoDiscounts = const [],
    this.soldOut = false,
  });

  int get totalPromoDiscount => promoDiscounts.fold<int>(0, (s, p) => s + p.discountAmount);
  int get effectiveTotal => (item.itemTotal - totalPromoDiscount).clamp(0, item.lineGross);
  bool get hasAnyDiscount => item.hasDiscount || totalPromoDiscount > 0;
}

/// Nhóm các dòng trong giỏ hàng thuộc cùng một loại sản phẩm (Gốc)
class CartProductGroup {
  final String groupKey;
  final int productId;
  final String productName;
  final List<CartBranchItem> branches;

  const CartProductGroup({
    required this.groupKey,
    required this.productId,
    required this.productName,
    required this.branches,
  });

  int get totalQuantity => branches.fold<int>(0, (s, b) => s + b.item.quantity);
  int get totalGross => branches.fold<int>(0, (s, b) => s + b.item.lineGross);
  int get totalDiscount => branches.fold<int>(0, (s, b) => s + b.item.lineDiscountTotal + b.totalPromoDiscount);
  int get effectiveTotal => branches.fold<int>(0, (s, b) => s + b.effectiveTotal);
  bool get hasAnyDiscount => totalDiscount > 0;
}

/// Gom các món trong giỏ hàng thành danh sách các nhóm sản phẩm gốc kèm các nhánh
List<CartProductGroup> buildCartProductGroups({
  required List<OrderItemModel> cart,
  required Map<int, List<({String campaignName, int discountAmount, int quantity, bool isGift})>> linePromoDiscounts,
  required bool Function(OrderItemModel) isSoldOutFn,
}) {
  final groups = <String, CartProductGroup>{};
  final groupOrder = <String>[];

  for (int i = 0; i < cart.length; i++) {
    final item = cart[i];
    final key = item.productId > 0 ? 'id_${item.productId}' : 'name_${item.name.trim().toLowerCase()}';
    final branch = CartBranchItem(
      cartIndex: i,
      item: item,
      promoDiscounts: linePromoDiscounts[i] ?? const [],
      soldOut: isSoldOutFn(item),
    );

    if (!groups.containsKey(key)) {
      groupOrder.add(key);
      groups[key] = CartProductGroup(
        groupKey: key,
        productId: item.productId,
        productName: item.name,
        branches: [branch],
      );
    } else {
      groups[key]!.branches.add(branch);
    }
  }

  return groupOrder.map((k) => groups[k]!).toList();
}

/// CustomPainter vẽ đường nối nhánh cây phân cấp (Tree branch connector)
class TreeBranchPainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  final Color lineColor;
  final Color nodeColor;

  TreeBranchPainter({
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
    required this.nodeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;

    final x = size.width / 2;
    const branchY = 18.0;

    if (isLast) {
      // Đường dọc từ đỉnh xuống gần branchY rồi uốn cong 90 độ rẽ sang phải
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x, (branchY - 8).clamp(0, size.height))
        ..quadraticBezierTo(x, branchY, x + 8, branchY)
        ..lineTo(size.width, branchY);
      canvas.drawPath(path, linePaint);
    } else {
      // Đường dọc xuyên suốt nhánh từ đầu đến cuối
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      // Đường ngang rẽ nhánh
      canvas.drawLine(Offset(x, branchY), Offset(size.width, branchY), linePaint);
    }

    // Nút tròn phân nhánh (node dot)
    canvas.drawCircle(Offset(x, branchY), 4.5, dotPaint);
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, branchY), 2.0, innerPaint);
  }

  @override
  bool shouldRepaint(covariant TreeBranchPainter oldDelegate) =>
      oldDelegate.isFirst != isFirst ||
      oldDelegate.isLast != isLast ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.nodeColor != nodeColor;
}

/// Card hiển thị một nhóm sản phẩm dạng cây (Gốc + các Nhánh)
class CartTreeGroupCard extends StatelessWidget {
  final CartProductGroup group;
  final void Function(int cartIndex) onRemove;
  final void Function(int cartIndex) onEditNote;
  final void Function(int cartIndex) onDiscount;
  final void Function(int cartIndex) onIncrement;
  final void Function(int cartIndex) onDecrement;
  final void Function(CartProductGroup group)? onRemoveGroup;

  const CartTreeGroupCard({
    super.key,
    required this.group,
    required this.onRemove,
    required this.onEditNote,
    required this.onDiscount,
    required this.onIncrement,
    required this.onDecrement,
    this.onRemoveGroup,
  });

  @override
  Widget build(BuildContext context) {
    // Nếu sản phẩm chỉ có 1 nhánh duy nhất: hiển thị thẻ đơn gọn gàng
    if (group.branches.length == 1) {
      final b = group.branches.first;
      return CartItemCard(
        item: b.item,
        onRemove: () => onRemove(b.cartIndex),
        onEditNote: () => onEditNote(b.cartIndex),
        onDiscount: () => onDiscount(b.cartIndex),
        onIncrement: () => onIncrement(b.cartIndex),
        onDecrement: () => onDecrement(b.cartIndex),
        soldOut: b.soldOut,
        promoDiscounts: b.promoDiscounts,
      );
    }

    // Sản phẩm có ≥ 2 nhánh: hiển thị cấu trúc Cây (Gốc + các Nhánh con)
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.tc.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. GỐC SẢN PHẨM (ROOT HEADER)
          _buildRootHeader(context),

          const Divider(height: 1, thickness: 1),

          // 2. DANH SÁCH CÁC NHÁNH (BRANCHES)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6, left: 6, right: 8),
            child: Column(
              children: [
                for (int i = 0; i < group.branches.length; i++)
                  _buildBranchRow(
                    context,
                    branchIndex: i,
                    branch: group.branches[i],
                    isFirst: i == 0,
                    isLast: i == group.branches.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Gốc sản phẩm: Tên món, số lượng nhánh, tổng số phần, tổng tiền gốc và tổng tiền thực trả
  Widget _buildRootHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: context.tc.primaryLight.withValues(alpha: 0.28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Biểu tượng gốc sản phẩm
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.tc.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.tc.borderLight),
            ),
            child: Icon(
              Icons.account_tree_rounded,
              size: 20,
              color: context.tc.primary,
            ),
          ),
          const SizedBox(width: 10),

          // Tên sản phẩm + Nhãn số nhánh & số phần
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.productName,
                  style: GoogleFonts.beVietnamPro(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: context.tc.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.tc.primaryLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${group.branches.length} nhánh biến thể • ${group.totalQuantity} phần',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.tc.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tổng tiền gốc + tổng tiền sau giảm của cả nhóm
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (group.hasAnyDiscount)
                Text(
                  FormatUtils.vnd(group.totalGross),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    color: context.tc.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                FormatUtils.vnd(group.effectiveTotal),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: group.hasAnyDiscount ? AppColors.success : context.tc.primary,
                ),
              ),
            ],
          ),

          // Nút xóa toàn bộ nhóm nếu có
          if (onRemoveGroup != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Xóa toàn bộ ${group.productName}',
              icon: Icon(Icons.delete_sweep_outlined, size: 20, color: context.tc.textSecondary),
              onPressed: () => onRemoveGroup!(group),
            ),
          ],
        ],
      ),
    );
  }

  /// Từng nhánh phân cấp của sản phẩm
  Widget _buildBranchRow(
    BuildContext context, {
    required int branchIndex,
    required CartBranchItem branch,
    required bool isFirst,
    required bool isLast,
  }) {
    final item = branch.item;
    final hasSize = item.selectedSize.trim().isNotEmpty;
    final hasSugar = item.selectedSugar.trim().isNotEmpty;
    final hasIce = item.selectedIce.trim().isNotEmpty;
    final hasToppings = item.selectedToppings.isNotEmpty;
    final hasAttrs = hasSize || hasSugar || hasIce || hasToppings;
    final compact = MediaQuery.of(context).size.width < 380;

    return Stack(
      children: [
        // Cột vẽ đường kẻ cây phân cấp (Tree line)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 26,
          child: CustomPaint(
            painter: TreeBranchPainter(
              isFirst: isFirst,
              isLast: isLast,
              lineColor: context.tc.primary.withValues(alpha: 0.35),
              nodeColor: context.tc.primary,
            ),
          ),
        ),

        // Thân nội dung của nhánh
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(
              color: context.tc.cardElevated.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.tc.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A. Tiêu đề nhánh + Trạng thái + Nút xóa nhánh
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.tc.primaryLight.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.tc.primary.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        'Nhánh #${branchIndex + 1}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.tc.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (branch.soldOut && !item.isSentKitchen)
                      StatusBadge(
                        label: 'Hết hàng',
                        color: context.tc.danger,
                        icon: Icons.warning_amber_rounded,
                        fontSize: 10,
                      ),
                    if (item.isSentKitchen)
                      StatusBadge(
                        label: 'Đã gửi bếp',
                        color: context.tc.success,
                        icon: Icons.check,
                        fontSize: 10,
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Xóa nhánh #${branchIndex + 1}',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: Icon(Icons.close_rounded, size: 18, color: context.tc.textSecondary),
                      onPressed: () => onRemove(branch.cartIndex),
                    ),
                  ],
                ),

                // B. Thuộc tính biến thể (Size, Đường, Đá, Topping)
                if (hasAttrs) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => onEditNote(branch.cartIndex),
                    borderRadius: BorderRadius.circular(6),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (hasSize)
                          _BranchAttrChip('Size ${item.selectedSize.trim()}', context.tc.info, context.tc.infoLight),
                        if (hasSugar)
                          _BranchAttrChip(item.selectedSugar.trim(), context.tc.success, context.tc.successLight),
                        if (hasIce)
                          _BranchAttrChip(
                            item.selectedIce.trim(),
                            context.ink(const Color(0xFF0F5E66)),
                            context.bg(const Color(0xFFE0F2F1)),
                          ),
                        if (hasToppings)
                          _BranchAttrChip(
                            '+${item.selectedToppings.join(', ')}',
                            context.tc.warningInk,
                            context.tc.warningLight,
                          ),
                      ],
                    ),
                  ),
                ],

                // C. Ghi chú của nhánh
                if (item.note.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  InkWell(
                    onTap: () => onEditNote(branch.cartIndex),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.tc.warningLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.tc.warning.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note, size: 15, color: context.tc.warningInk),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Ghi chú: ${item.note}',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
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
                ],

                // D. Giảm giá món thủ công
                if (item.hasDiscount) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.tc.dangerLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: context.tc.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      CartItemCard.discountLabel(item),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: context.tc.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                // E. Giảm giá do chương trình khuyến mãi (Combo, Mua X tặng Y, ...)
                if (branch.promoDiscounts.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  for (final promo in branch.promoDiscounts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
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
                            const Icon(Icons.card_giftcard_rounded, size: 14, color: Color(0xFFC2410C)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                promo.isGift
                                    ? '🎁 Món tặng (100%): ${promo.campaignName}'
                                    : '🎁 Giảm KM: -${FormatUtils.vnd(promo.discountAmount)} (${promo.campaignName})',
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

                const SizedBox(height: 6),

                // F. Giá tiền + Thao tác (Ghi chú, Giảm giá) + Stepper
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${FormatUtils.vnd(item.unitPrice)} × ${item.quantity}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: context.tc.textSecondary,
                                ),
                              ),
                              if (branch.hasAnyDiscount) ...[
                                const SizedBox(width: 4),
                                Text(
                                  FormatUtils.vnd(item.lineGross),
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 10,
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
                              FormatUtils.vnd(branch.effectiveTotal),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: branch.hasAnyDiscount ? AppColors.success : context.tc.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _BranchActionPill(
                      icon: Icons.edit_note,
                      label: item.note.isEmpty ? '+ Ghi chú' : 'Ghi chú',
                      compact: compact,
                      onTap: () => onEditNote(branch.cartIndex),
                    ),
                    const SizedBox(width: 4),
                    _BranchActionPill(
                      icon: item.hasDiscount ? Icons.discount : Icons.discount_outlined,
                      label: item.hasDiscount ? 'Đã giảm' : 'Giảm món',
                      compact: compact,
                      onTap: () => onDiscount(branch.cartIndex),
                      color: item.hasDiscount ? context.tc.danger : null,
                    ),
                    const SizedBox(width: 4),
                    QuantityStepper(
                      value: item.quantity,
                      onDecrement: () => onDecrement(branch.cartIndex),
                      onIncrement: () => onIncrement(branch.cartIndex),
                      buttonSize: compact ? 32 : 36,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BranchAttrChip extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color bgColor;
  const _BranchAttrChip(this.label, this.textColor, this.bgColor);

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label.trim(),
        style: TextStyle(fontSize: 10, color: textColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BranchActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool compact;

  const _BranchActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.tc.textPrimary;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 32 : 36, minWidth: compact ? 32 : 36),
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: color != null ? color!.withValues(alpha: 0.1) : context.tc.cardElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: color != null ? color!.withValues(alpha: 0.4) : context.tc.borderLight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: compact ? 15 : 17, color: fg),
              if (!compact) ...[
                const SizedBox(width: 3),
                Text(
                  label,
                  style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
