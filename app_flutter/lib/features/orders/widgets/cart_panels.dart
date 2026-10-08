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
  final VoidCallback onAddItems;

  const CartHeaderBar({
    super.key,
    required this.tableName,
    required this.zone,
    required this.guestCount,
    required this.onEditGuests,
    required this.onDecrementGuests,
    required this.onIncrementGuests,
    required this.onAddItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          // Bàn + khu vực (co giãn, cắt bớt khi tên dài)
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: AppRadius.brSm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.table_restaurant, size: 16, color: AppColors.primaryDark),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$tableName • $zone',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Số khách (chạm số để nhập nhanh)
          Tooltip(
            message: 'Số khách – chạm để nhập',
            child: QuantityStepper(
              value: guestCount,
              suffix: 'khách',
              onDecrement: onDecrementGuests,
              onIncrement: onIncrementGuests,
              onTapValue: onEditGuests,
              buttonSize: 36,
            ),
          ),
          const SizedBox(width: 8),

          // Thêm món
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm món'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            onPressed: onAddItems,
          ),
        ],
      ),
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

  const CartCustomerBar({
    super.key,
    required this.customer,
    required this.pointsUsed,
    required this.onLookup,
    required this.onUsePoints,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Material(
      color: AppColors.warningLight,
      child: InkWell(
        onTap: c == null ? onLookup : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              const Icon(Icons.person_pin, color: AppColors.warningInk, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: c == null
                    ? Text(
                        'Chạm để tìm khách & tích điểm',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.warningInk),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${c.fullName} • ${c.phone}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          Text(
                            'Điểm hiện có: ${c.currentPoints} điểm ${pointsUsed > 0 ? "(-$pointsUsed điểm đã dùng)" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
              ),
              if (c != null) ...[
                TextButton(
                  onPressed: onUsePoints,
                  child: Text(pointsUsed > 0 ? 'Đổi điểm' : 'Dùng điểm'),
                ),
                IconButton(
                  tooltip: 'Bỏ chọn khách',
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                  onPressed: onClear,
                ),
              ] else
                TextButton.icon(
                  onPressed: onLookup,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Tìm khách'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: AppColors.warningInk,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== SUMMARY + ACTIONS ====================
class CartSummaryPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hasUnsent = unsentCount > 0;

    final breakdown = <Widget>[
      AmountRow(label: 'Tổng tiền hàng', value: FormatUtils.vnd(subTotal)),
      if (itemDiscountTotal > 0)
        AmountRow(label: '− Giảm giá món', value: '-${FormatUtils.vnd(itemDiscountTotal)}', color: AppColors.success),
      ...appliedDiscounts.map((d) => AmountRow(
            label: '− ${d.promoCode ?? d.description}',
            value: '-${FormatUtils.vnd(d.amount)}',
            color: AppColors.success,
          )),
      if (pointsDiscount > 0)
        AmountRow(
          label: '− Điểm tích lũy ($pointsUsed điểm)',
          value: '-${FormatUtils.vnd(pointsDiscount)}',
          color: AppColors.success,
        ),
      if (vatRate > 0) AmountRow(label: 'VAT (${vatRate.toStringAsFixed(0)}%)', value: '+${FormatUtils.vnd(vatAmount)}'),
    ];

    final secondaryStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      textStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: sidePanel ? const Border(left: BorderSide(color: AppColors.borderLight)) : null,
        boxShadow: sidePanel
            ? null
            : const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Chi tiết – giới hạn chiều cao, cuộn được khi nhiều khuyến mãi / màn hình thấp
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: sidePanel ? 360 : 120),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: breakdown),
              ),
            ),
            const Divider(height: 16),

            // TỔNG THANH TOÁN – to, rõ, đọc được từ xa
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'TỔNG THANH TOÁN',
                    style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary, letterSpacing: 0.3),
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      FormatUtils.vnd(finalTotal),
                      style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 26, color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Hàng 1: Khuyến mãi, In tạm tính, Hủy đơn
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.discount_outlined, size: 18),
                    label: Text(
                      appliedDiscounts.isEmpty ? 'Khuyến mãi' : 'KM (${appliedDiscounts.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: secondaryStyle,
                    onPressed: onDiscount,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Tạm tính', maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: secondaryStyle.copyWith(
                      foregroundColor: const WidgetStatePropertyAll(AppColors.textPrimary),
                      side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border, width: 1.5)),
                    ),
                    onPressed: onPrePrint,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Hủy đơn', maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: secondaryStyle.copyWith(
                      foregroundColor: const WidgetStatePropertyAll(AppColors.danger),
                      side: WidgetStatePropertyAll(BorderSide(color: AppColors.danger.withValues(alpha: 0.5), width: 1.5)),
                    ),
                    onPressed: onCancel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Hàng 2: Gửi bếp & THANH TOÁN (nút chính lớn nhất)
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.soup_kitchen_outlined, size: 20),
                    label: Text(
                      hasUnsent ? 'Gửi bếp ($unsentCount)' : 'Đã gửi bếp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 56),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: hasUnsent ? onSendKitchen : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payments_outlined, size: 22),
                    label: const Text('THANH TOÁN', maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 56),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                    onPressed: cartEmpty ? null : onPay,
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
