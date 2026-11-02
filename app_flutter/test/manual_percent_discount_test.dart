import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/promotion_model.dart';

void main() {
  test('giảm % thủ công: lưu / đọc lại manualPercent', () {
    final d = BillDiscountModel(description: 'Giảm giá thủ công (100%)', amount: 50000, manualPercent: 100);
    final back = BillDiscountModel.fromMap(d.toMap());
    expect(back.manualPercent, 100);
    expect(back.effectiveManualPercent, 100);
  });
  test('bản ghi cũ: đọc % từ mô tả; giảm số tiền / CTKM thì không', () {
    expect(BillDiscountModel(description: 'Giảm giá thủ công (100%)', amount: 1).effectiveManualPercent, 100);
    expect(BillDiscountModel(description: 'Giảm giá thủ công (20%)', amount: 1).effectiveManualPercent, 20);
    expect(BillDiscountModel(description: 'Giảm giá thủ công (20.000đ)', amount: 1).effectiveManualPercent, isNull);
    expect(BillDiscountModel(description: 'Giảm giá thủ công (20%)', amount: 1, campaignId: 'C1').effectiveManualPercent, isNull);
  });
}
