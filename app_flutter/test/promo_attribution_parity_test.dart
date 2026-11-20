// Đối chiếu chia khuyến mãi theo người bấm món app ↔ web: docs/promo_attribution_parity.json, kết quả mong đợi do web sinh.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/pricing_engine.dart';
import 'package:tram_flutter/core/reports/promo_attribution.dart';
import 'package:tram_flutter/data/models/bill_model.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/data/models/promotion_model.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';

File _doc(String name) {
  final f = File('../docs/$name');
  return f.existsSync() ? f : File('docs/$name');
}

int? _int(Object? v) => v is num ? v.toInt() : null;

PricingLineItem _line(Map<String, dynamic> m) => PricingLineItem(
      lineId: m['lineId'] as String,
      itemId: m['itemId'] as String,
      itemName: m['itemName'] as String?,
      groupId: m['groupId'] as String?,
      quantity: _int(m['quantity'])!,
      unitPrice: _int(m['unitPrice'])!,
      discountedQuantity: _int(m['discountedQuantity']) ?? 0,
      discountPercent: _int(m['discountPercent']) ?? 0,
      discountUnitAmount: _int(m['discountUnitAmount']) ?? 0,
      rewardCampaignId: m['rewardCampaignId'] as String?,
      toppingUnitPrice: _int(m['toppingUnitPrice']) ?? 0,
      toppingCount: _int(m['toppingCount']) ?? 0,
    );

void main() {
  final data = jsonDecode(_doc('promo_attribution_parity.json').readAsStringSync()) as Map<String, dynamic>;
  final expected = jsonDecode(_doc('promo_attribution_parity_expected.json').readAsStringSync()) as Map<String, dynamic>;
  final cashierMap = data['cashier'] as Map;
  final cashier = LineStaff(cashierMap['u'] as String, cashierMap['n'] as String);

  group('Đối chiếu chia khuyến mãi theo người bấm món app ↔ web', () {
    for (final raw in data['cases'] as List) {
      final c = raw as Map<String, dynamic>;
      test(c['name'] as String, () {
        final camps = [for (final m in c['campaigns'] as List) CampaignModel.fromMap(Map<String, dynamic>.from(m as Map))];
        final entries = [for (final e in c['lines'] as List) Map<String, dynamic>.from(e as Map)];
        final lines = [for (final e in entries) _line(Map<String, dynamic>.from(e['line'] as Map))];
        final staff = <String, LineStaff?>{
          for (final e in entries)
            (e['line'] as Map)['lineId'] as String:
                e['staff'] == null ? null : LineStaff((e['staff'] as Map)['u'] as String, (e['staff'] as Map)['n'] as String),
        };
        final quotes = CartCampaignPricing.quoteStackedLines(
          camps,
          lines,
          branchId: 'TRAM01',
          nowMs: _int(data['nowMs']),
          ignoreScheduleFor: {for (final k in camps) k.campaignId},
          dedicatedOnlyFor: {...((c['dedicated'] as List?) ?? const []).cast<String>()},
        );
        final delta = Map<String, dynamic>.from((c['storedDelta'] as Map?) ?? const {});
        final actual = {
          for (final k in camps)
            k.campaignId: [
              for (final s in PromoAttribution.shares(
                quotes[k.campaignId]!,
                lines,
                k.campaignId,
                (id) => staff[id],
                cashier,
                storedAmount: quotes[k.campaignId]!.totalPromotionDiscount + ((delta[k.campaignId] as num?)?.toInt() ?? 0),
              ))
                s.toMap(),
            ],
        };
        expect(jsonDecode(jsonEncode(actual)), expected[c['name']]);
      });
    }
  });

  group('Báo cáo khuyến mãi theo người bấm món', () {
    BillModel bill({List<Map<String, dynamic>>? items, List<Map<String, dynamic>>? discounts}) => BillModel.fromMap({
          'billCode': 'HD-1',
          'status': 'PAID',
          'finalAmount': 90000,
          'subTotal': 110000,
          'staffUsername': 'thu',
          'staffFullName': 'Thu ngân',
          'items': items ??
              [
                {'productId': 1, 'name': 'Trà đào', 'price': 30000, 'quantity': 2, 'orderedBy': 'an', 'orderedByName': 'An'},
                {'productId': 2, 'name': 'Bánh', 'price': 25000, 'quantity': 1, 'orderedBy': 'binh', 'orderedByName': 'Bình'},
              ],
          'discounts': discounts ?? const [],
        }, 'B1');

    test('lọc nhân viên lấy phần của người bấm món; hóa đơn cũ nhiều người bấm → thu ngân', () {
      final withShares = bill(discounts: [
        {
          'campaignId': 'combo', 'description': 'Combo', 'amount': 20000, 'comboCount': 2,
          'staffShares': [
            {'u': 'binh', 'n': 'Bình', 'amount': 10000, 'combo': 1},
            {'u': 'chi', 'n': 'Chi', 'amount': 10000, 'combo': 1},
          ],
        }
      ]);
      final forBinh = PromoAttribution.attributeBillsToStaff([withShares], PromoAttribution.matcher('binh'));
      expect(forBinh.single.discounts.single.amount, 10000);
      expect(forBinh.single.discounts.single.comboCount, 1);
      expect(PromoAttribution.attributeBillsToStaff([withShares], PromoAttribution.matcher('Thu ngân')).expand((b) => b.discounts), isEmpty);

      final old = bill(discounts: [{'campaignId': 'combo', 'description': 'Combo', 'amount': 20000, 'comboCount': 2}]);
      expect(PromoAttribution.discountShares(old, old.discounts.single),
          [const PromoStaffShare(u: 'thu', n: 'Thu ngân', amount: 20000, combo: 2)]);
      final oneOrderer = bill(
        items: [{'productId': 1, 'name': 'Trà đào', 'price': 30000, 'quantity': 2, 'orderedBy': 'an', 'orderedByName': 'An'}],
        discounts: [{'campaignId': 'combo', 'description': 'Combo', 'amount': 10000, 'comboCount': 1}],
      );
      expect(PromoAttribution.discountShares(oneOrderer, oneOrderer.discounts.single).single.u, 'an');
    });

    test('staffShares lưu / đọc lại trên hóa đơn', () {
      final d = BillDiscountModel(description: 'Combo', amount: 10000, campaignId: 'combo', comboCount: 1,
          staffShares: const [PromoStaffShare(u: 'binh', n: 'Bình', amount: 10000, combo: 1)]);
      expect(BillDiscountModel.fromMap(d.toMap()).staffShares, d.staffShares);
    });
  });
}
