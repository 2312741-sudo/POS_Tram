// lib/features/menu_management/attachment_picker.dart
//
// Chọn "Danh mục note áp dụng" / "Nhóm topping áp dụng" cho NHÓM MÓN hoặc MÓN.
// Giá trị null = kế thừa (món: từ nhóm món; nhóm món: không gắn); danh sách (kể cả rỗng) = tùy chỉnh.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/domain/item_options.dart';
import '../../core/theme/app_theme.dart';

class AttachmentPicker extends StatelessWidget {
  final String title;
  final IconData icon;

  /// (id, tên) các nhóm đang có của chi nhánh (kể cả đã tắt, ghi chú trong tên)
  final List<(String, String)> options;

  /// null = kế thừa
  final List<String>? value;
  final bool isProduct;

  /// Tên danh mục thừa hưởng (hiển thị khi kế thừa), nếu có
  final String? inheritedLabel;
  final ValueChanged<List<String>?> onChanged;

  const AttachmentPicker({
    super.key,
    required this.title,
    required this.icon,
    required this.options,
    required this.value,
    required this.onChanged,
    this.isProduct = true,
    this.inheritedLabel,
  });

  @override
  Widget build(BuildContext context) {
    final custom = value != null;
    final inheritText = isProduct
        ? 'Kế thừa từ nhóm món${inheritedLabel == null ? '' : ': $inheritedLabel'}'
        : 'Không gắn (chỉ ô ghi chú tự do)';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.tc.cardElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: context.tc.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 13))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: custom ? context.tc.primaryLight : context.tc.border.withAlpha(80),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(custom ? 'Tùy chỉnh' : (isProduct ? 'Kế thừa' : 'Chưa gắn'),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: context.tc.textPrimary)),
            ),
          ]),
          if (isProduct)
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: false,
              groupValue: custom,
              title: Text(inheritText, style: const TextStyle(fontSize: 12)),
              onChanged: (_) => onChanged(null),
            ),
          if (isProduct)
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: true,
              groupValue: custom,
              title: const Text('Tùy chỉnh cho món này', style: TextStyle(fontSize: 12)),
              onChanged: (_) => onChanged(value ?? <String>[]),
            ),
          if (custom || !isProduct) ...[
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Chưa có nhóm nào — tạo ở màn "Danh mục note & topping".',
                    style: TextStyle(fontSize: 11, color: context.tc.textSecondary)),
              ),
            for (final o in options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: context.tc.primary,
                title: Text(o.$2, style: const TextStyle(fontSize: 12)),
                value: (value ?? const []).contains(o.$1),
                onChanged: (v) {
                  final cur = List<String>.from(value ?? const []);
                  if (v == true) {
                    if (!cur.contains(o.$1)) cur.add(o.$1);
                  } else {
                    cur.remove(o.$1);
                  }
                  onChanged(cur);
                },
              ),
            if (custom && (value ?? const []).where((e) => e != kNoGroups).isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(isProduct ? 'Không chọn nhóm nào = món này KHÔNG có mục này.' : 'Không chọn nhóm nào = không gắn.',
                    style: TextStyle(fontSize: 11, color: context.tc.textSecondary)),
              ),
          ],
        ],
      ),
    );
  }
}
