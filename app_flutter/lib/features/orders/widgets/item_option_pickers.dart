// lib/features/orders/widgets/item_option_pickers.dart
//
// Phần chọn topping THEO NHÓM trong bảng chỉnh món (dùng chung order_cart_screen & order_list_screen).
// Chỉ dùng khi chi nhánh đã cấu hình danh mục note & topping (xem core/domain/item_options.dart).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/domain/item_options.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/topping_utils.dart';

class ToppingGroupsSection extends StatelessWidget {
  final List<ToppingGroup> groups;
  final List<String> selected;

  /// Topping đã chọn từ trước nhưng không còn trong danh mục (giữ nguyên, cho phép bỏ)
  final List<String> extras;
  final void Function(ToppingGroup group, String name) onToggle;

  /// Tăng / giảm số phần của một topping đã chọn (nhóm cho chọn nhiều)
  final void Function(ToppingGroup group, String name) onIncrement;
  final void Function(String name) onDecrement;
  final void Function(String name) onRemoveExtra;
  final VoidCallback onClearAll;

  const ToppingGroupsSection({
    super.key,
    required this.groups,
    required this.selected,
    required this.onToggle,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemoveExtra,
    required this.onClearAll,
    this.extras = const [],
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final g in groups) {
      final rule = !g.multi
          ? 'chọn 1'
          : (g.max > 0 ? 'tối đa ${g.max}' : '');
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(
          rule.isEmpty ? g.name : '${g.name} ($rule)',
          style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ));
      final unitsInGroup = g.items.fold<int>(0, (a, t) => a + toppingCount(selected, t.name));
      final groupFull = g.multi && g.max > 0 && unitsInGroup >= g.max;
      children.add(Wrap(
        spacing: 8,
        runSpacing: 4,
        children: g.items.map((t) {
          final count = toppingCount(selected, t.name);
          final price = t.price > 0 ? ' (+${FormatUtils.vnd(t.price)})' : '';
          if (g.multi && count > 0) {
            return ToppingStepperChip(
              label: '${t.name}$price',
              count: count,
              canIncrement: !groupFull,
              onIncrement: () => onIncrement(g, t.name),
              onDecrement: () => onDecrement(t.name),
            );
          }
          return FilterChip(
            label: Text('${t.name}$price'),
            selected: count > 0,
            selectedColor: context.tc.primaryLight,
            labelStyle: TextStyle(
              color: count > 0 ? context.tc.primaryDark : context.tc.textPrimary,
              fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
            onSelected: (_) => onToggle(g, t.name),
          );
        }).toList(),
      ));
      children.add(const SizedBox(height: 10));
    }
    if (extras.isNotEmpty) {
      children.add(Text('Đã chọn (ngoài danh mục)', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)));
      children.add(const SizedBox(height: 6));
      children.add(Wrap(
        spacing: 8,
        children: extras
            .where(selected.contains)
            .map((n) => InputChip(
                  label: Text(n, style: const TextStyle(fontSize: 12)),
                  onDeleted: () => onRemoveExtra(n),
                ))
            .toList(),
      ));
      children.add(const SizedBox(height: 10));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Topping thêm:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
            if (selected.isNotEmpty)
              TextButton(
                onPressed: onClearAll,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                child: Text('Bỏ chọn hết', style: TextStyle(fontSize: 11, color: context.tc.danger)),
              ),
          ],
        ),
        ...children,
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Chip topping đã chọn có nút − / + để lấy nhiều phần cùng một topping (− về 0 = bỏ topping)
class ToppingStepperChip extends StatelessWidget {
  final String label;
  final int count;
  final bool canIncrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const ToppingStepperChip({
    super.key,
    required this.label,
    required this.count,
    required this.onIncrement,
    required this.onDecrement,
    this.canIncrement = true,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    Widget btn(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 16, color: onTap == null ? tc.textHint : tc.primaryDark),
          ),
        );
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: tc.primaryLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tc.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: tc.primaryDark, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 4),
          btn(Icons.remove, onDecrement),
          Text('$count', style: TextStyle(color: tc.primaryDark, fontWeight: FontWeight.w800, fontSize: 13)),
          btn(Icons.add, canIncrement ? onIncrement : null),
        ],
      ),
    );
  }
}
