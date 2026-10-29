// lib/features/orders/widgets/combo_reward_picker_sheet.dart
// Màn hình chọn món giảm giá cho chương trình Combo (Mua X tặng/giảm Y).
// Giới hạn số lượng món được chọn theo số lượng món điều kiện (nước) trong giỏ hàng.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/campaign_models.dart';
import '../../../data/models/product_model.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ComboRewardPickerSheet extends StatefulWidget {
  final CampaignModel campaign;
  final int maxAllowedUnits;
  final int waterCount;
  final List<ProductModel> candidateProducts;
  final int discountPerUnit;
  final String benefitDescription;

  const ComboRewardPickerSheet({
    super.key,
    required this.campaign,
    required this.maxAllowedUnits,
    required this.waterCount,
    required this.candidateProducts,
    this.discountPerUnit = 0,
    this.benefitDescription = '',
  });

  @override
  State<ComboRewardPickerSheet> createState() => _ComboRewardPickerSheetState();
}

class _ComboRewardPickerSheetState extends State<ComboRewardPickerSheet> {
  final Map<int, int> _quantities = {};
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  int get _totalSelected => _quantities.values.fold(0, (sum, q) => sum + q);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _increment(ProductModel product) {
    if (_totalSelected >= widget.maxAllowedUnits) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã chọn tối đa ${widget.maxAllowedUnits} món giảm giá theo số lượng nước trong đơn.',
            style: GoogleFonts.beVietnamPro(fontSize: 13),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }
    setState(() {
      _quantities[product.id] = (_quantities[product.id] ?? 0) + 1;
    });
  }

  void _decrement(ProductModel product) {
    final current = _quantities[product.id] ?? 0;
    if (current <= 0) return;
    setState(() {
      if (current == 1) {
        _quantities.remove(product.id);
      } else {
        _quantities[product.id] = current - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final filtered = widget.candidateProducts.where((p) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q);
    }).toList();

    // Gom nhóm theo danh mục
    final Map<String, List<ProductModel>> grouped = {};
    for (final p in filtered) {
      final cat = p.category.trim().isNotEmpty ? p.category.trim() : 'Món giảm giá';
      grouped.putIfAbsent(cat, () => []).add(p);
    }

    final isMaxReached = _totalSelected >= widget.maxAllowedUnits;
    final estimatedDiscount = widget.discountPerUnit > 0 ? _totalSelected * widget.discountPerUnit : 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tc.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.sandwich, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chọn món giảm giá Combo',
                          style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold, color: tc.textPrimary),
                        ),
                        Text(
                          widget.campaign.name,
                          style: GoogleFonts.beVietnamPro(fontSize: 12, color: tc.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(context, null),
                    tooltip: 'Đóng',
                  ),
                ],
              ),
            ),

            // Info & Limit Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMaxReached ? AppColors.success.withValues(alpha: 0.1) : AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isMaxReached ? AppColors.success.withValues(alpha: 0.3) : AppColors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isMaxReached ? LucideIcons.circleCheck : LucideIcons.info,
                    size: 20,
                    color: isMaxReached ? AppColors.success : AppColors.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Đơn có ${widget.waterCount} món nước • Tối đa ${widget.maxAllowedUnits} món giảm giá',
                          style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: tc.textPrimary),
                        ),
                        if (widget.benefitDescription.isNotEmpty)
                          Text(
                            widget.benefitDescription,
                            style: GoogleFonts.beVietnamPro(fontSize: 11, color: tc.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isMaxReached ? AppColors.success : AppColors.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '$_totalSelected / ${widget.maxAllowedUnits}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar (if more than 4 products)
            if (widget.candidateProducts.length > 4)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Tìm món giảm giá...',
                    prefixIcon: const Icon(LucideIcons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

            // Product List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Không tìm thấy món giảm giá phù hợp trong thực đơn.',
                          style: GoogleFonts.beVietnamPro(color: tc.textSecondary, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: grouped.keys.length,
                      itemBuilder: (context, gIdx) {
                        final catName = grouped.keys.elementAt(gIdx);
                        final products = grouped[catName]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 6),
                              child: Text(
                                catName.toUpperCase(),
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            ...products.map((p) {
                              final qty = _quantities[p.id] ?? 0;
                              final discountedPrice = widget.discountPerUnit > 0
                                  ? (p.price - widget.discountPerUnit).clamp(0, p.price)
                                  : p.price;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: qty > 0 ? AppColors.primary.withValues(alpha: 0.05) : tc.card,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: qty > 0 ? AppColors.primary.withValues(alpha: 0.4) : tc.borderLight,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: tc.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              if (widget.discountPerUnit > 0 && discountedPrice < p.price) ...[
                                                Text(
                                                  FormatUtils.vnd(p.price),
                                                  style: GoogleFonts.beVietnamPro(
                                                    fontSize: 11,
                                                    color: tc.textSecondary,
                                                    decoration: TextDecoration.lineThrough,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  FormatUtils.vnd(discountedPrice),
                                                  style: GoogleFonts.beVietnamPro(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.danger,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.danger.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    '-${FormatUtils.vnd(widget.discountPerUnit)}',
                                                    style: GoogleFonts.beVietnamPro(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.danger,
                                                    ),
                                                  ),
                                                ),
                                              ] else ...[
                                                Text(
                                                  FormatUtils.vnd(p.price),
                                                  style: GoogleFonts.beVietnamPro(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Stepper
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(LucideIcons.circleMinus),
                                          color: qty > 0 ? AppColors.danger : tc.borderLight,
                                          iconSize: 26,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          onPressed: qty > 0 ? () => _decrement(p) : null,
                                        ),
                                        Container(
                                          constraints: const BoxConstraints(minWidth: 28),
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: Text(
                                            '$qty',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: qty > 0 ? AppColors.primary : tc.textSecondary,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(LucideIcons.circlePlus),
                                          color: !isMaxReached ? AppColors.primary : tc.borderLight,
                                          iconSize: 26,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          onPressed: () => _increment(p),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: tc.card,
                border: Border(top: BorderSide(color: tc.borderLight)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -3),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (estimatedDiscount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Ước tính giảm ($_totalSelected combo):',
                            style: GoogleFonts.beVietnamPro(fontSize: 12, color: tc.textSecondary),
                          ),
                          Text(
                            '-${FormatUtils.vnd(estimatedDiscount)}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            'Hủy',
                            style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _totalSelected > 0
                              ? () {
                                  final chosen = <ProductModel, int>{};
                                  for (final entry in _quantities.entries) {
                                    if (entry.value <= 0) continue;
                                    final p = widget.candidateProducts.firstWhere((x) => x.id == entry.key);
                                    chosen[p] = entry.value;
                                  }
                                  Navigator.pop(context, chosen);
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: tc.borderLight,
                            disabledForegroundColor: tc.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: Text(
                            _totalSelected > 0
                                ? 'Xác nhận ($_totalSelected món)'
                                : 'Chọn tối đa ${widget.maxAllowedUnits} món',
                            style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
