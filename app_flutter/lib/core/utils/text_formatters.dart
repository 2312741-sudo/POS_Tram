// lib/core/utils/text_formatters.dart
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formatter tự động định dạng số với dấu phẩy ',' phân cách hàng nghìn khi gõ (VD: 100,000).
/// Tự động giữ vị trí con trỏ thông minh khi người dùng thêm hoặc xoá ký tự ở giữa chuỗi.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static final NumberFormat _formatter = NumberFormat('#,###', 'en_US');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }

    // Giới hạn độ dài để tránh tràn số (tối đa 15 chữ số = 999 nghìn tỷ VNĐ)
    if (digitsOnly.length > 15) {
      return oldValue;
    }

    final number = int.tryParse(digitsOnly);
    if (number == null) return oldValue;

    final newFormatted = _formatter.format(number);

    // Tính lại vị trí con trỏ theo số lượng chữ số đứng trước con trỏ
    final cursorIndex = newValue.selection.end.clamp(0, newValue.text.length);
    final textBeforeCursor = newValue.text.substring(0, cursorIndex);
    final digitsBeforeCursor = textBeforeCursor.replaceAll(RegExp(r'[^0-9]'), '').length;

    var newCursorIndex = 0;
    var digitsCount = 0;
    for (var i = 0; i < newFormatted.length; i++) {
      if (digitsCount >= digitsBeforeCursor) {
        newCursorIndex = i;
        break;
      }
      if (RegExp(r'[0-9]').hasMatch(newFormatted[i])) {
        digitsCount++;
      }
      newCursorIndex = i + 1;
    }

    return TextEditingValue(
      text: newFormatted,
      selection: TextSelection.collapsed(offset: newCursorIndex.clamp(0, newFormatted.length)),
    );
  }
}

/// Formatter tự động chuyển toàn bộ chữ thành IN HOA khi gõ (VD: nguyễn văn a -> NGUYỄN VĂN A)
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
