import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:tram_flutter/core/utils/format_utils.dart';
import 'package:tram_flutter/core/utils/text_formatters.dart';

void main() {
  group('ThousandsSeparatorInputFormatter tests', () {
    final formatter = ThousandsSeparatorInputFormatter();

    test('formats plain digits with comma thousand separators', () {
      final res1 = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '500000', selection: TextSelection.collapsed(offset: 6)),
      );
      expect(res1.text, '500,000');
      expect(res1.selection.end, 7);

      final res2 = formatter.formatEditUpdate(
        const TextEditingValue(text: '500,000', selection: TextSelection.collapsed(offset: 7)),
        const TextEditingValue(text: '500,0000', selection: TextSelection.collapsed(offset: 8)),
      );
      expect(res2.text, '5,000,000');
      expect(res2.selection.end, 9);
    });

    test('handles empty and whitespace gracefully', () {
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '100,000'),
        const TextEditingValue(text: ''),
      );
      expect(res.text, '');
    });

    test('handles inserting digit with smart cursor positioning', () {
      // 999 -> type 1 at offset 1: 9|99 -> 9199 (offset 2) -> formatted: 9,1|99 (offset 3)
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '999', selection: TextSelection.collapsed(offset: 1)),
        const TextEditingValue(text: '9199', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(res.text, '9,199');
      expect(res.selection.end, 3);
    });
  });

  group('UpperCaseTextFormatter tests', () {
    final formatter = UpperCaseTextFormatter();

    test('automatically converts input text to all uppercase', () {
      final res = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'nguyễn văn anh', selection: TextSelection.collapsed(offset: 14)),
      );
      expect(res.text, 'NGUYỄN VĂN ANH');
      expect(res.selection.end, 14);
    });
  });

  group('FormatUtils comma methods', () {
    test('vndComma formats numbers with comma separator and đ suffix', () {
      expect(FormatUtils.vndComma(0), '0 đ');
      expect(FormatUtils.vndComma(1000), '1,000 đ');
      expect(FormatUtils.vndComma(500000), '500,000 đ');
      expect(FormatUtils.vndComma(12345678), '12,345,678 đ');
    });

    test('numberComma formats numbers with comma separator without unit', () {
      expect(FormatUtils.numberComma(500000), '500,000');
      expect(FormatUtils.numberComma(1000000), '1,000,000');
    });
  });
}
