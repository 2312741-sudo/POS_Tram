// lib/features/orders/widgets/delete_reason_dialog.dart
//
// Hộp thoại chọn LÝ DO khi xóa / giảm số lượng món ĐÃ LƯU trên bàn.
// Lý do: "Khách đổi món", "Khách hủy món", "Nhập sai", "Hết món/hết nguyên liệu",
// "Khác" (bắt buộc nhập nội dung). Trả về chuỗi lý do cuối cùng hoặc null nếu bỏ qua.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/domain/deleted_items.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';

Future<String?> showDeleteItemReasonDialog(
  BuildContext context, {
  required String itemName,
  required int quantity,
  required int amount,
  required String tableName,
  bool sentToKitchen = false,
  bool isLastItem = false,
  bool isReduce = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DeleteReasonDialog(
      itemName: itemName,
      quantity: quantity,
      amount: amount,
      tableName: tableName,
      sentToKitchen: sentToKitchen,
      isLastItem: isLastItem,
      isReduce: isReduce,
    ),
  );
}

class _DeleteReasonDialog extends StatefulWidget {
  final String itemName;
  final int quantity;
  final int amount;
  final String tableName;
  final bool sentToKitchen;
  final bool isLastItem;
  final bool isReduce;

  const _DeleteReasonDialog({
    required this.itemName,
    required this.quantity,
    required this.amount,
    required this.tableName,
    required this.sentToKitchen,
    required this.isLastItem,
    required this.isReduce,
  });

  @override
  State<_DeleteReasonDialog> createState() => _DeleteReasonDialogState();
}

class _DeleteReasonDialogState extends State<_DeleteReasonDialog> {
  String? _reason;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  String? get _resolved => DeleteItemReasons.resolve(_reason, otherText: _otherCtrl.text);

  @override
  Widget build(BuildContext context) {
    final title = widget.isReduce ? 'Giảm số lượng món' : 'Xóa món khỏi đơn';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.delete_outline, color: context.tc.danger, size: 24),
          const SizedBox(width: 8),
          Flexible(child: Text(title, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16))),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Xóa ${widget.quantity} x "${widget.itemName}" (${FormatUtils.vnd(widget.amount)}) khỏi bàn ${widget.tableName}.',
                style: GoogleFonts.beVietnamPro(fontSize: 14),
              ),
              if (widget.sentToKitchen) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.tc.warningLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.tc.warning),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: context.tc.warning, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Món này đã gửi bếp, việc hủy món sẽ được ghi nhật ký kiểm toán.',
                          style: GoogleFonts.beVietnamPro(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text('Lý do xóa món *', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: DeleteItemReasons.all.map((r) {
                  final selected = _reason == r;
                  return ChoiceChip(
                    label: Text(r, style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.tc.textPrimary)),
                    selected: selected,
                    selectedColor: context.tc.primary,
                    backgroundColor: context.tc.cardElevated,
                    onSelected: (v) => setState(() => _reason = v ? r : null),
                  );
                }).toList(),
              ),
              if (_reason == DeleteItemReasons.other) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _otherCtrl,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(hintText: 'Nhập lý do cụ thể (bắt buộc)...', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (widget.isLastItem) ...[
                const SizedBox(height: 10),
                Text(
                  'Đây là món cuối cùng. Xóa xong đơn sẽ được ghi nhận là ĐÃ HỦY và bàn về trạng thái TRỐNG.',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.primary, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bỏ qua')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: context.tc.danger),
          onPressed: _resolved == null ? null : () => Navigator.pop(context, _resolved),
          child: const Text('Xác nhận xóa', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
