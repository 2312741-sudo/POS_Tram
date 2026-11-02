import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_integrity.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/bill_model.dart';

/// Số khách trên báo cáo = tổng số khách thật trên hóa đơn (trước đây màn Cuối ngày = số hóa đơn).
void main() {
  BillModel bill(String id, Object? guests) => BillModel.fromMap({
        'billCode': id, 'status': 'PAID', 'tableName': 'Bàn 1', 'finalAmount': 100000, 'subTotal': 100000,
        if (guests != null) 'guestCount': guests,
      }, id);

  test('đọc số khách trên hóa đơn; hóa đơn cũ không có → 1', () {
    expect(bill('A', 4).guests, 4);
    expect(bill('B', '2').guests, 2);
    expect(bill('C', null).guests, 1);
    final bills = [bill('A', 4), bill('B', 2), bill('C', null)];
    expect(bills.fold<int>(0, (s, b) => s + ReportCalculator.getGuestCount(b)), 7);
  });

  test('ghi lại hóa đơn (hủy / hoàn tiền) giữ số khách', () {
    final rec = BillRecordBuilder.build(bill('A', 4), storeCode: 'TRAM01', storeName: 'Trạm');
    expect(rec['guestCount'], 4);
  });

  test('khuyến mãi theo món (tặng chanh, giảm 16K xoài, combo) là giảm giá MÓN; giảm % hóa đơn là giảm giá ĐƠN', () {
    final b = BillModel.fromMap({
      'billCode': 'HD-9', 'status': 'PAID', 'tableName': 'Bàn 1', 'subTotal': 215000, 'totalDiscount': 81000, 'finalAmount': 134000,
      'items': [
        {'productId': 1, 'name': 'Bánh', 'price': 40000, 'quantity': 2, 'lineDiscountTotal': 5000, 'discountAmount': 5000, 'discountedQuantity': 1, 'discountUnitAmount': 5000},
      ],
      'discounts': [
        {'campaignId': 'G', 'description': 'Tặng chanh Grab', 'amount': 22000, 'campaignType': 'ORDERVALUEITEMBENEFIT'},
        {'campaignId': 'X', 'description': 'Giảm 16K xoài', 'amount': 16000, 'campaignType': 'ORDER_VALUE_ITEM_BENEFIT'},
        {'campaignId': 'C', 'description': 'Combo', 'amount': 10000, 'campaignType': 'BUYXGETY'},
        {'campaignId': 'B', 'description': 'Hoa hồng 20%', 'amount': 28000, 'campaignType': 'BILLDISCOUNT'},
      ],
    }, 'B9');
    expect(b.promoItemDiscount, 48000);
    expect(b.reportItemDiscount, 5000 + 48000);
    expect(b.reportOrderDiscount, 81000 - 53000);
    final o = ReportCalculator.calculateOverviewReport([b]);
    expect(o.itemDiscounts, 53000);
    expect(o.billDiscounts, 28000);
  });
}
