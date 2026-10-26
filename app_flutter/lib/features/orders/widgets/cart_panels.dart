// lib/features/orders/widgets/cart_panels.dart
//
// Các khối giao diện của màn hình giỏ hàng / thanh toán (OrderCartScreen):
//  - CartHeaderBar     : thông tin bàn + số khách + nút "Thêm món"
//  - CartCustomerBar   : khách hàng tích điểm (CRM)
//  - CartSummaryPanel  : bảng tổng tiền + thanh nút thao tác (Gửi bếp / Thanh toán)
// Chỉ hiển thị; tính toán và nghiệp vụ nằm ở màn hình cha.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';
import '../../../widgets/common_widgets.dart';

// ==================== HEADER ====================
class CartHeaderBar extends StatelessWidget {
  final String tableName;
  final String zone;
  final int guestCount;
  final VoidCallback onEditGuests;
  final VoidCallback? onDecrementGuests;
  final VoidCallback onIncrementGuests;
  final VoidCallback? onAddItems;

  /// Chế độ hiển thị dạng cây (Nhánh) hay dạng phẳng (Danh sách)
  final bool treeViewMode;
  final ValueChanged<bool>? onToggleTreeViewMode;
  final int totalQty;
  final int uniqueProductsCount;

  const CartHeaderBar({
    super.key,
    required this.tableName,
    required this.zone,
    required this.guestCount,
    required this.onEditGuests,
    required this.onDecrementGuests,
    required this.onIncrementGuests,
    this.onAddItems,
    this.treeViewMode = true,
    this.onToggleTreeViewMode,
    this.totalQty = 0,
    this.uniqueProductsCount = 0,
  });

  Widget _buildToggleBtn(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final fg = isSelected ? context.tc.primaryDark : context.tc.textSecondary;
    final bg = isSelected ? context.tc.primaryLight : Colors.transparent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        color: bg,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 3),
            Text(
              title,
              style: GoogleFonts.beVietnamPro(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.tc.card,
        border: Border(bottom: BorderSide(color: context.tc.borderLight)),
      ),
      child: Row(
        children: [
          // Nút chuyển chế độ xem (Nhánh / Danh sách) siêu gọn
          if (onToggleTreeViewMode != null) ...[
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: context.tc.cardElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.tc.borderLight),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildToggleBtn(
                    context,
                    title: 'Nhánh',
                    icon: Icons.account_tree_outlined,
                    isSelected: treeViewMode,
                    onTap: () => onToggleTreeViewMode!(true),
                  ),
                  Container(width: 1, height: 14, color: context.tc.borderLight),
                  _buildToggleBtn(
                    context,
                    title: 'Danh sách',
                    icon: Icons.format_list_bulleted,
                    isSelected: !treeViewMode,
                    onTap: () => onToggleTreeViewMode!(false),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],

          // Nhãn tổng số phần món
          if (totalQty > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(
                color: context.tc.primaryLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '$totalQty phần',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.tc.primaryDark,
                ),
              ),
            ),

          const Spacer(),

          // Số khách (chạm số để nhập nhanh) - nút gọn 28px
          Tooltip(
            message: 'Số khách – chạm để nhập',
            child: QuantityStepper(
              value: guestCount,
              suffix: 'khách',
              onDecrement: onDecrementGuests,
              onIncrement: onIncrementGuests,
              onTapValue: onEditGuests,
              buttonSize: 28,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== TÍCH ĐIỂM THEO GIÁ TRỊ HÓA ĐƠN ====================
/// Dòng xem trước: "Tích điểm: +N điểm", "Điểm: X → Y sau thanh toán", hạng. Tỷ lệ 0/chưa đặt → gợi ý cấu hình.
class LoyaltyEarnPreview extends StatelessWidget {
  final KmtCustomerModel customer;
  final int pointsUsed;
  final int earnPoints;
  final double earnRate;
  final List<LoyaltyTier> tiers;
  final VoidCallback? onConfigure;

  /// Đ mỗi điểm (để báo hóa đơn tối thiểu có điểm khi +0)
  final int redeemRate;

  /// Chưa tra được số dư điểm (mất mạng…): không hiển thị "điểm → điểm" sai.
  final bool pointsUnknown;

  /// Đơn đang dùng khuyến mãi khóa tích điểm
  final bool pointsBlocked;

  const LoyaltyEarnPreview({
    super.key,
    this.pointsUnknown = false,
    this.pointsBlocked = false,
    required this.customer,
    required this.pointsUsed,
    required this.earnPoints,
    required this.earnRate,
    required this.tiers,
    this.onConfigure,
    this.redeemRate = 1000,
  });

  @override
  Widget build(BuildContext context) {
    final after = customer.currentPoints - pointsUsed + earnPoints;
    final tier = LoyaltyTier.nameFor(customer.totalPoints + earnPoints, tiers);
    final style = GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.success, fontWeight: FontWeight.w600);
    if (earnRate <= 0) {
      return Row(children: [
        Expanded(child: Text('Chưa cấu hình tỷ lệ tích điểm', style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.warningInk, fontWeight: FontWeight.w600))),
        if (onConfigure != null) TextButton(onPressed: onConfigure, child: const Text('Cài đặt')),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tích điểm: +$earnPoints điểm', style: style.copyWith(fontWeight: FontWeight.w800)),
        if (pointsBlocked)
          Text('Đơn dùng khuyến mãi không tích điểm — chỉ gắn thông tin khách vào đơn', style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.warningInk, fontWeight: FontWeight.w600))
        else if (earnPoints == 0)
          Text('Hóa đơn chưa đủ giá trị để có điểm (từ ${(redeemRate * 50 / earnRate).ceil()}đ được 1 điểm)', style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary)),
        if (pointsUnknown)
          Text('Điểm hiện có: chưa tải được • sẽ +$earnPoints điểm khi thanh toán', style: style)
        else
          Text('Điểm: ${customer.currentPoints} → $after sau thanh toán • Hạng: $tier', style: style),
      ],
    );
  }
}

// ==================== CUSTOMER (CRM) ====================
class CartCustomerBar extends StatelessWidget {
  final KmtCustomerModel? customer;
  final int pointsUsed;
  final VoidCallback onLookup;
  final VoidCallback onUsePoints;
  final VoidCallback onClear;
  final VoidCallback? onEdit;
  final int earnPoints;
  final double earnRate;
  final List<LoyaltyTier> tiers;
  final VoidCallback? onConfigureRate;
  final int redeemRate;
  final bool pointsUnknown;
  final bool pointsBlocked;
  final VoidCallback? onRetryPoints;

  const CartCustomerBar({
    super.key,
    this.pointsUnknown = false,
    this.pointsBlocked = false,
    this.onRetryPoints,
    required this.customer,
    required this.pointsUsed,
    required this.onLookup,
    required this.onUsePoints,
    required this.onClear,
    this.onEdit,
    this.earnPoints = 0,
    this.earnRate = 1,
    this.tiers = const [],
    this.onConfigureRate,
    this.redeemRate = 1000,
  });

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Material(
      color: context.tc.warningLight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.person_pin, color: context.tc.warningInk, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: c == null
                  ? InkWell(
                      onTap: onLookup,
                      child: Text(
                        'Chạm để tìm khách & tích điểm',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.tc.warningInk),
                      ),
                    )
                  : InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${c.fullName} • ${c.phone}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.beVietnamPro(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.tc.textPrimary),
                          ),
                          if (pointsUnknown)
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Điểm hiện có: chưa tải được',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.warningInk, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (onRetryPoints != null)
                                  InkWell(
                                    onTap: onRetryPoints,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      child: Text('Thử lại', style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.w800, color: context.tc.warningInk, decoration: TextDecoration.underline)),
                                    ),
                                  ),
                              ],
                            )
                          else
                            Text(
                              'Điểm: ${c.currentPoints} ${pointsUsed > 0 ? "(-$pointsUsed đã dùng)" : ""} • +$earnPoints điểm',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.success, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
            ),
            if (c != null) ...[
              if (onEdit != null)
                IconButton(
                  tooltip: 'Sửa thông tin khách',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.edit_outlined, size: 18, color: context.tc.textSecondary),
                  onPressed: onEdit,
                ),
              const SizedBox(width: 4),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: GoogleFonts.beVietnamPro(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                onPressed: onUsePoints,
                child: Text(pointsUsed > 0 ? 'Đổi điểm' : 'Dùng điểm'),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Bỏ chọn khách',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(Icons.close, size: 18, color: context.tc.textSecondary),
                onPressed: onClear,
              ),
            ] else
              TextButton.icon(
                onPressed: onLookup,
                icon: const Icon(Icons.search, size: 15),
                label: const Text('Tìm khách'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: context.tc.warningInk,
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: GoogleFonts.beVietnamPro(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== SUMMARY + ACTIONS ====================
class CartSummaryPanel extends StatefulWidget {
  final int subTotal;
  final int itemDiscountTotal;
  final List<BillDiscountModel> appliedDiscounts;
  final int pointsUsed;
  final int pointsDiscount;
  final double vatRate;
  final int vatAmount;
  final int finalTotal;
  final int unsentCount;
  final bool cartEmpty;
  final VoidCallback onDiscount;
  final VoidCallback? onPrePrint;
  final VoidCallback onCancel;
  final VoidCallback? onSendKitchen;
  final VoidCallback? onPay;
  /// true khi hiển thị ở cột bên phải trên tablet (không cần bóng đổ phía trên)
  final bool sidePanel;

  const CartSummaryPanel({
    super.key,
    required this.subTotal,
    required this.itemDiscountTotal,
    required this.appliedDiscounts,
    required this.pointsUsed,
    required this.pointsDiscount,
    required this.vatRate,
    required this.vatAmount,
    required this.finalTotal,
    required this.unsentCount,
    required this.cartEmpty,
    required this.onDiscount,
    required this.onPrePrint,
    required this.onCancel,
    required this.onSendKitchen,
    required this.onPay,
    this.sidePanel = false,
  });

  @override
  State<CartSummaryPanel> createState() => _CartSummaryPanelState();
}

class _CartSummaryPanelState extends State<CartSummaryPanel> {
  bool _expandedBreakdown = false;

  @override
  Widget build(BuildContext context) {
    final hasUnsent = widget.unsentCount > 0;
    final totalPromoDiscount = widget.itemDiscountTotal +
        widget.appliedDiscounts.fold(0, (sum, d) => sum + d.amount) +
        widget.pointsDiscount;
    final hasDiscountsOrVat = totalPromoDiscount > 0 || widget.vatAmount > 0;

    final breakdown = <Widget>[
      AmountRow(label: 'Tổng tiền hàng', value: FormatUtils.vnd(widget.subTotal)),
      if (widget.itemDiscountTotal > 0)
        AmountRow(label: '− Giảm giá món', value: '-${FormatUtils.vnd(widget.itemDiscountTotal)}', color: context.tc.success),
      ...widget.appliedDiscounts.map((d) => AmountRow(
            label: '− ${d.promoCode ?? d.description}',
            value: '-${FormatUtils.vnd(d.amount)}',
            color: context.tc.success,
          )),
      if (widget.pointsDiscount > 0)
        AmountRow(
          label: '− Điểm tích lũy (${widget.pointsUsed} điểm)',
          value: '-${FormatUtils.vnd(widget.pointsDiscount)}',
          color: context.tc.success,
        ),
      if (widget.vatRate > 0) AmountRow(label: 'VAT (${widget.vatRate.toStringAsFixed(0)}%)', value: '+${FormatUtils.vnd(widget.vatAmount)}'),
    ];

    final secondaryStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
      textStyle: GoogleFonts.beVietnamPro(fontSize: 11.5, fontWeight: FontWeight.w600),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: context.tc.card,
        border: widget.sidePanel ? Border(left: BorderSide(color: context.tc.borderLight)) : null,
        boxShadow: widget.sidePanel
            ? null
            : const [BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tablet hoặc khi bấm xem chi tiết: hiện bảng breakdown
            if (widget.sidePanel || _expandedBreakdown) ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.sidePanel ? 360 : 140),
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: breakdown),
                ),
              ),
              const Divider(height: 12),
            ],

            // Dòng thu gọn khi có giảm giá / VAT mà không mở rộng
            if (!widget.sidePanel && !_expandedBreakdown && hasDiscountsOrVat) ...[
              InkWell(
                onTap: () => setState(() => _expandedBreakdown = true),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        'Tiền gốc: ${FormatUtils.vnd(widget.subTotal)}',
                        style: GoogleFonts.beVietnamPro(fontSize: 11.5, color: context.tc.textSecondary),
                      ),
                      if (totalPromoDiscount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• Giảm: -${FormatUtils.vnd(totalPromoDiscount)}',
                          style: GoogleFonts.beVietnamPro(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.tc.success),
                        ),
                      ],
                      if (widget.vatAmount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• VAT: +${FormatUtils.vnd(widget.vatAmount)}',
                          style: GoogleFonts.beVietnamPro(fontSize: 11.5, color: context.tc.textSecondary),
                        ),
                      ],
                      const Spacer(),
                      Icon(Icons.keyboard_arrow_down, size: 16, color: context.tc.textSecondary),
                    ],
                  ),
                ),
              ),
            ],

            // TỔNG THANH TOÁN – số to rõ nét
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (!widget.sidePanel && _expandedBreakdown)
                  InkWell(
                    onTap: () => setState(() => _expandedBreakdown = false),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.keyboard_arrow_up, size: 18, color: context.tc.textSecondary),
                    ),
                  ),
                Text(
                  'TỔNG THANH TOÁN',
                  style: GoogleFonts.beVietnamPro(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: context.tc.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    FormatUtils.vnd(widget.finalTotal),
                    style: GoogleFonts.beVietnamPro(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: context.tc.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Thanh nút chức năng siêu gọn (KM, Tạm tính, Hủy đơn) - Chiều cao 32px
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.discount_outlined, size: 15),
                    label: Text(
                      widget.appliedDiscounts.isEmpty ? 'Khuyến mãi' : 'KM (${widget.appliedDiscounts.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: secondaryStyle,
                    onPressed: widget.onDiscount,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined, size: 15),
                    label: const Text('Tạm tính', maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: secondaryStyle.copyWith(
                      foregroundColor: WidgetStatePropertyAll(context.tc.textPrimary),
                      side: WidgetStatePropertyAll(BorderSide(color: context.tc.border, width: 1.2)),
                    ),
                    onPressed: widget.onPrePrint,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 15),
                    label: const Text('Hủy đơn', maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: secondaryStyle.copyWith(
                      foregroundColor: WidgetStatePropertyAll(context.tc.danger),
                      side: WidgetStatePropertyAll(BorderSide(color: context.tc.danger.withValues(alpha: 0.4), width: 1.2)),
                    ),
                    onPressed: widget.onCancel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Nút hành động chính - Chiều cao 44px
            Row(
              children: [
                if (hasUnsent) ...[
                  Expanded(
                    flex: 4,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
                      label: Text(
                        'Gửi bếp (${widget.unsentCount})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        textStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      onPressed: widget.onSendKitchen,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  flex: hasUnsent ? 5 : 1,
                  child: ElevatedButton.icon(
                    icon: Icon(hasUnsent ? Icons.payments_outlined : Icons.check_circle_outline, size: 19),
                    label: Text(
                      hasUnsent ? 'THANH TOÁN' : 'THANH TOÁN (${FormatUtils.vnd(widget.finalTotal)})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.tc.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                    onPressed: widget.cartEmpty ? null : widget.onPay,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
