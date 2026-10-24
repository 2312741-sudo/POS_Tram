// lib/features/orders/widgets/cart_tree_group_card.dart
//
// Hiển thị món trong giỏ hàng theo cấu trúc Cây / Nhánh (Tree Grouped View):
// - GỐC (Root Header): Tên món chung, tổng số phần, tổng tiền sau giảm giá của cả nhóm.
// - NHÁNH (Branches): Các phân nhánh biến thể (Size, Đường, Đá, Topping, Ghi chú, Giảm giá món, Ưu đãi khuyến mãi).
// - Các nhánh được kết nối trực quan bằng đường kẻ cây thanh thoát, không đóng hộp rườm rà.
// - Nút thao tác (Ghi chú, Giảm giá) dạng icon compact để không bao giờ bị đè/chồng chéo giá tiền.
// - Nếu sản phẩm chỉ có 1 nhánh duy nhất: hiển thị gọn gàng như thẻ đơn thông thường.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/order_item_model.dart';
import '../../../widgets/common_widgets.dart';
import 'cart_item_card.dart';

/// Dữ liệu một nhánh trong nhóm sản phẩm (tập hợp các dòng giỏ hàng có cùng tính chất/tùy chọn)
class CartBranchItem {
  final int cartIndex;
  final List<int> cartIndices;
  final OrderItemModel item;
  final List<OrderItemModel> rawItems;
  final List<({String campaignName, int discountAmount, int quantity, bool isGift})> promoDiscounts;
  final bool soldOut;
  final int sentCount;
  final int unsentCount;

  const CartBranchItem({
    required this.cartIndex,
    this.cartIndices = const [],
    required this.item,
    this.rawItems = const [],
    this.promoDiscounts = const [],
    this.soldOut = false,
    this.sentCount = 0,
    this.unsentCount = 0,
  });

  int get totalQuantity => item.quantity;
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

/// Tạo khóa nhận diện tính chất/tùy chọn của món.
/// KHÔNG tính trạng thái gửi bếp (isSentKitchen) để các món giống hệt tính chất
/// (dù gửi trước hay gửi sau) luôn được gom chung một nhánh trực quan, gọn gàng.
String getCartItemNatureKey(
  OrderItemModel item,
  List<({String campaignName, int discountAmount, int quantity, bool isGift})> promos,
) {
  final sortedToppings = List<String>.from(item.selectedToppings)..sort();
  final promoKey = promos.map((p) => '${p.campaignName}:${p.isGift ? "GIFT" : p.discountAmount}').join('|');

  final manualDiscountKey = item.hasDiscount
      ? '${item.discountPercent}_${item.discountUnitAmount}_${item.discountAmount}_${item.discountReason.trim().toLowerCase()}'
      : 'none';

  return [
    item.price,
    item.selectedSize.trim().toLowerCase(),
    item.sizeExtraPrice,
    item.selectedSugar.trim().toLowerCase(),
    item.selectedIce.trim().toLowerCase(),
    sortedToppings.join(',').toLowerCase(),
    item.toppingPrice,
    item.note.trim().toLowerCase(),
    manualDiscountKey,
    promoKey,
  ].join(':::');
}

/// Gom các món trong giỏ hàng thành danh sách các nhóm sản phẩm gốc kèm các nhánh.
/// Chỉ phân nhánh khi món KHÁC TÍNH CHẤT (size, đường, đá, topping, ghi chú, chiết khấu).
/// Không phân nhánh theo trạng thái gửi bếp (món đã gửi bếp và chưa gửi bếp có cùng tính chất sẽ gộp chung).
List<CartProductGroup> buildCartProductGroups({
  required List<OrderItemModel> cart,
  required Map<int, List<({String campaignName, int discountAmount, int quantity, bool isGift})>> linePromoDiscounts,
  required bool Function(OrderItemModel) isSoldOutFn,
}) {
  final groups = <String, CartProductGroup>{};
  final groupOrder = <String>[];
  final branchBuckets = <String, Map<String, List<({int index, OrderItemModel item, List<({String campaignName, int discountAmount, int quantity, bool isGift})> promos, bool soldOut})>>>{};
  final branchOrder = <String, List<String>>{};

  for (int i = 0; i < cart.length; i++) {
    final item = cart[i];
    final groupKey = item.productId > 0 ? 'id_${item.productId}' : 'name_${item.name.trim().toLowerCase()}';
    final promos = linePromoDiscounts[i] ?? const [];
    final soldOut = isSoldOutFn(item);
    final natureKey = getCartItemNatureKey(item, promos);

    if (!branchBuckets.containsKey(groupKey)) {
      groupOrder.add(groupKey);
      branchBuckets[groupKey] = {};
      branchOrder[groupKey] = [];
    }

    if (!branchBuckets[groupKey]!.containsKey(natureKey)) {
      branchOrder[groupKey]!.add(natureKey);
      branchBuckets[groupKey]![natureKey] = [];
    }

    branchBuckets[groupKey]![natureKey]!.add((
      index: i,
      item: item,
      promos: promos,
      soldOut: soldOut,
    ));
  }

  for (final groupKey in groupOrder) {
    final natureKeys = branchOrder[groupKey]!;
    final branches = <CartBranchItem>[];

    for (final nk in natureKeys) {
      final entries = branchBuckets[groupKey]![nk]!;
      final cartIndices = entries.map((e) => e.index).toList();
      final rawItems = entries.map((e) => e.item).toList();

      final totalQty = rawItems.fold<int>(0, (s, it) => s + it.quantity);
      final sentCount = rawItems.where((it) => it.isSentKitchen).fold<int>(0, (s, it) => s + it.quantity);
      final unsentCount = rawItems.where((it) => !it.isSentKitchen).fold<int>(0, (s, it) => s + it.quantity);
      final totalDiscountAmount = rawItems.fold<int>(0, (s, it) => s + it.discountAmount);
      final totalDiscountedQty = rawItems.fold<int>(0, (s, it) => s + it.discountedQuantity);
      final isAnySoldOut = entries.any((e) => e.soldOut);

      // Merge promo discounts
      final mergedPromos = <String, ({String campaignName, int discountAmount, int quantity, bool isGift})>{};
      for (final e in entries) {
        for (final p in e.promos) {
          final pKey = '${p.campaignName}_${p.isGift}';
          if (!mergedPromos.containsKey(pKey)) {
            mergedPromos[pKey] = p;
          } else {
            final old = mergedPromos[pKey]!;
            mergedPromos[pKey] = (
              campaignName: old.campaignName,
              discountAmount: old.discountAmount + p.discountAmount,
              quantity: old.quantity + p.quantity,
              isGift: old.isGift,
            );
          }
        }
      }

      final firstItem = rawItems.first;
      final consolidatedItem = firstItem.copyWith(
        quantity: totalQty,
        discountAmount: totalDiscountAmount,
        discountedQuantity: totalDiscountedQty,
        isSentKitchen: sentCount > 0 && unsentCount == 0,
      );

      // Ưu tiên chọn chỉ mục dòng chưa gửi bếp để thao tác tăng/giảm số lượng
      final primaryIndex = cartIndices.firstWhere(
        (idx) => idx < cart.length && !cart[idx].isSentKitchen,
        orElse: () => cartIndices.first,
      );

      branches.add(CartBranchItem(
        cartIndex: primaryIndex,
        cartIndices: cartIndices,
        item: consolidatedItem,
        rawItems: rawItems,
        promoDiscounts: mergedPromos.values.toList(),
        soldOut: isAnySoldOut,
        sentCount: sentCount,
        unsentCount: unsentCount,
      ));
    }

    groups[groupKey] = CartProductGroup(
      groupKey: groupKey,
      productId: branches.first.item.productId,
      productName: branches.first.item.name,
      branches: branches,
    );
  }

  return groupOrder.map((k) => groups[k]!).toList();
}

/// CustomPainter vẽ đường nối nhánh cây phân cấp (Tree branch connector thanh thoát)
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
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;

    final x = size.width / 2;
    const branchY = 12.0;

    if (isLast) {
      // Đường dọc từ đỉnh xuống gần branchY rồi uốn cong nhẹ sang phải
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x, (branchY - 6).clamp(0, size.height))
        ..quadraticBezierTo(x, branchY, x + 6, branchY)
        ..lineTo(size.width, branchY);
      canvas.drawPath(path, linePaint);
    } else {
      // Đường dọc xuyên suốt nhánh từ đầu đến cuối
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      // Đường ngang rẽ nhánh
      canvas.drawLine(Offset(x, branchY), Offset(size.width, branchY), linePaint);
    }

    // Nút tròn phân nhánh nhỏ gọn, tinh tế
    canvas.drawCircle(Offset(x, branchY), 3.0, dotPaint);
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
  final void Function(CartBranchItem branch)? onRemoveBranch;
  final void Function(CartBranchItem branch)? onEditNoteBranch;
  final void Function(CartBranchItem branch)? onDiscountBranch;
  final void Function(CartBranchItem branch)? onIncrementBranch;
  final void Function(CartBranchItem branch)? onDecrementBranch;

  const CartTreeGroupCard({
    super.key,
    required this.group,
    required this.onRemove,
    required this.onEditNote,
    required this.onDiscount,
    required this.onIncrement,
    required this.onDecrement,
    this.onRemoveGroup,
    this.onRemoveBranch,
    this.onEditNoteBranch,
    this.onDiscountBranch,
    this.onIncrementBranch,
    this.onDecrementBranch,
  });

  @override
  Widget build(BuildContext context) {
    // Nếu sản phẩm chỉ có 1 nhánh duy nhất: hiển thị thẻ đơn gọn gàng
    if (group.branches.length == 1) {
      final b = group.branches.first;
      final kitchenBadge = (b.sentCount > 0 && b.unsentCount > 0)
          ? 'Đã gửi bếp (${b.sentCount}/${b.totalQuantity})'
          : null;
      return CartItemCard(
        item: b.item,
        onRemove: () => onRemoveBranch != null ? onRemoveBranch!(b) : onRemove(b.cartIndex),
        onEditNote: () => onEditNoteBranch != null ? onEditNoteBranch!(b) : onEditNote(b.cartIndex),
        onDiscount: () => onDiscountBranch != null ? onDiscountBranch!(b) : onDiscount(b.cartIndex),
        onIncrement: () => onIncrementBranch != null ? onIncrementBranch!(b) : onIncrement(b.cartIndex),
        onDecrement: () => onDecrementBranch != null ? onDecrementBranch!(b) : onDecrement(b.cartIndex),
        soldOut: b.soldOut,
        promoDiscounts: b.promoDiscounts,
        kitchenBadgeLabel: kitchenBadge,
      );
    }

    // Sản phẩm có ≥ 2 nhánh: hiển thị cấu trúc Cây (Gốc + các Nhánh con thoáng mắt)
    return Card(
      elevation: 0.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.tc.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. GỐC SẢN PHẨM (ROOT HEADER)
          _buildRootHeader(context),

          const Divider(height: 1, thickness: 1),

          // 2. DANH SÁCH CÁC NHÁNH (BRANCHES - thoáng đãng, không đóng hộp riêng)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
            child: Column(
              children: [
                for (int i = 0; i < group.branches.length; i++) ...[
                  _buildBranchRow(
                    context,
                    branchIndex: i,
                    branch: group.branches[i],
                    isFirst: i == 0,
                    isLast: i == group.branches.length - 1,
                  ),
                  if (i < group.branches.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Divider(height: 10, thickness: 0.6, color: context.tc.borderLight),
                    ),
                ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: context.tc.primaryLight.withValues(alpha: 0.22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Biểu tượng gốc sản phẩm
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: context.tc.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.tc.borderLight),
            ),
            child: Icon(
              Icons.account_tree_rounded,
              size: 16,
              color: context.tc.primary,
            ),
          ),
          const SizedBox(width: 8),

          // Tên sản phẩm + Nhãn số nhánh & số phần
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.productName,
                  style: GoogleFonts.beVietnamPro(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: context.tc.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  '${group.branches.length} phân nhánh tùy chọn • ${group.totalQuantity} phần',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: context.tc.primaryDark,
                  ),
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
                    fontSize: 10,
                    color: context.tc.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                FormatUtils.vnd(group.effectiveTotal),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: group.hasAnyDiscount ? AppColors.success : context.tc.primary,
                ),
              ),
            ],
          ),

          // Nút xóa toàn bộ nhóm nếu có
          if (onRemoveGroup != null) ...[
            const SizedBox(width: 2),
            IconButton(
              tooltip: 'Xóa toàn bộ ${group.productName}',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(Icons.delete_sweep_outlined, size: 18, color: context.tc.textSecondary),
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

    return Stack(
      children: [
        // Cột vẽ đường kẻ cây phân cấp (Tree line mỏng gọn)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 20,
          child: CustomPaint(
            painter: TreeBranchPainter(
              isFirst: isFirst,
              isLast: isLast,
              lineColor: context.tc.primary.withValues(alpha: 0.35),
              nodeColor: context.tc.primary,
            ),
          ),
        ),

        // Thân nội dung của nhánh (không đóng khung hộp cứng nhắc)
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 2, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A. Thuộc tính biến thể / Tiêu đề nhánh + Trạng thái + Nút xóa
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Tag số thứ tự nhánh nhỏ gọn
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: context.tc.primaryLight.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: context.tc.primary.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        '#${branchIndex + 1}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: context.tc.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Biến thể (Size, Đường, Đá, Topping)
                    Expanded(
                      child: hasAttrs
                          ? Wrap(
                              spacing: 3,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
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
                            )
                          : Text(
                              'Tiêu chuẩn',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: context.tc.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                    ),

                    if (branch.soldOut && branch.sentCount == 0) ...[
                      const SizedBox(width: 4),
                      StatusBadge(
                        label: 'Hết',
                        color: context.tc.danger,
                        icon: Icons.warning_amber_rounded,
                        fontSize: 9.5,
                      ),
                    ],
                    if (branch.sentCount > 0 && branch.unsentCount == 0) ...[
                      const SizedBox(width: 4),
                      StatusBadge(
                        label: 'Bếp',
                        color: context.tc.success,
                        icon: Icons.check,
                        fontSize: 9.5,
                      ),
                    ] else if (branch.sentCount > 0 && branch.unsentCount > 0) ...[
                      const SizedBox(width: 4),
                      StatusBadge(
                        label: 'Bếp: ${branch.sentCount}/${branch.totalQuantity}',
                        color: context.tc.success,
                        icon: Icons.check,
                        fontSize: 9.5,
                      ),
                    ],

                    IconButton(
                      tooltip: 'Xóa phần #${branchIndex + 1}',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      icon: Icon(Icons.close_rounded, size: 16, color: context.tc.textSecondary),
                      onPressed: () => onRemoveBranch != null ? onRemoveBranch!(branch) : onRemove(branch.cartIndex),
                    ),
                  ],
                ),

                // B. Ghi chú của nhánh (nếu có)
                if (item.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  InkWell(
                    onTap: () => onEditNote(branch.cartIndex),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.tc.warningLight,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.tc.warning.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note, size: 13, color: context.tc.warningInk),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Ghi chú: ${item.note}',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                color: context.tc.warningInk,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // C. Giảm giá món thủ công
                if (item.hasDiscount) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: context.tc.dangerLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: context.tc.danger.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      CartItemCard.discountLabel(item),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10.5,
                        color: context.tc.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                // D. Giảm giá do chương trình khuyến mãi (Combo, Mua X tặng Y, ...)
                if (branch.promoDiscounts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  for (final promo in branch.promoDiscounts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFDBA74)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.card_giftcard_rounded, size: 13, color: Color(0xFFC2410C)),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                promo.isGift
                                    ? '🎁 Món tặng (100%): ${promo.campaignName}'
                                    : '🎁 Giảm KM: -${FormatUtils.vnd(promo.discountAmount)} (${promo.campaignName})',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 10.5,
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

                const SizedBox(height: 4),

                // E. Giá tiền + Nút Thao tác (icon vuông nhỏ không đè chữ) + Stepper
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Cột giá tiền (chiếm trọn không gian bên trái, không bao giờ bị đè)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${FormatUtils.vnd(item.unitPrice)} × ${item.quantity}',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: context.tc.textSecondary,
                                ),
                              ),
                              if (branch.hasAnyDiscount) ...[
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    FormatUtils.vnd(item.lineGross),
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 10,
                                      color: context.tc.textSecondary,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            FormatUtils.vnd(branch.effectiveTotal),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: branch.hasAnyDiscount ? AppColors.success : context.tc.primary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Nút icon Ghi chú (bật sáng khi đã có ghi chú)
                    _BranchIconBtn(
                      icon: Icons.edit_note_rounded,
                      tooltip: item.note.isEmpty ? 'Thêm ghi chú' : 'Sửa ghi chú',
                      isActive: item.note.isNotEmpty,
                      activeColor: context.tc.warningInk,
                      activeBgColor: context.tc.warningLight,
                      onTap: () => onEditNoteBranch != null ? onEditNoteBranch!(branch) : onEditNote(branch.cartIndex),
                    ),
                    const SizedBox(width: 4),

                    // Nút icon Giảm giá món (bật sáng đỏ khi đã giảm giá)
                    _BranchIconBtn(
                      icon: item.hasDiscount ? Icons.discount : Icons.discount_outlined,
                      tooltip: item.hasDiscount ? 'Đã giảm món' : 'Giảm món',
                      isActive: item.hasDiscount,
                      activeColor: context.tc.danger,
                      activeBgColor: context.tc.dangerLight,
                      onTap: () => onDiscountBranch != null ? onDiscountBranch!(branch) : onDiscount(branch.cartIndex),
                    ),
                    const SizedBox(width: 6),

                    // Bộ tăng giảm số lượng gọn gàng
                    QuantityStepper(
                      value: item.quantity,
                      onDecrement: () => onDecrementBranch != null ? onDecrementBranch!(branch) : onDecrement(branch.cartIndex),
                      onIncrement: () => onIncrementBranch != null ? onIncrementBranch!(branch) : onIncrement(branch.cartIndex),
                      buttonSize: 30,
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
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(3)),
      child: Text(
        label.trim(),
        style: TextStyle(fontSize: 9.5, color: textColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BranchIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final Color? activeColor;
  final Color? activeBgColor;
  final VoidCallback onTap;

  const _BranchIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.activeColor,
    this.activeBgColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isActive ? (activeColor ?? context.tc.primary) : context.tc.textSecondary;
    final bg = isActive ? (activeBgColor ?? context.tc.primaryLight) : context.tc.cardElevated;
    final border = isActive ? fg.withValues(alpha: 0.4) : context.tc.borderLight;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Icon(icon, size: 16, color: fg),
        ),
      ),
    );
  }
}
