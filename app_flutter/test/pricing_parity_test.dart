// Đối chiếu khuyến mãi app ↔ web: chạy docs/pricing_parity.json qua engine Dart (CartCampaignPricing.quoteStackedLines)
// và so với docs/pricing_parity_expected.json — file mong đợi do engine web sinh ra (web/test/pricing-parity.test.ts).
// Test này đỏ = app tính khác web.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/pricing_engine.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
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
      itemCode: m['itemCode'] as String?,
      groupId: m['groupId'] as String?,
      quantity: _int(m['quantity'])!,
      unitPrice: _int(m['unitPrice'])!,
      discountedQuantity: _int(m['discountedQuantity']) ?? 0,
      discountPercent: _int(m['discountPercent']) ?? 0,
      discountUnitAmount: _int(m['discountUnitAmount']) ?? 0,
      orderedAtMs: _int(m['orderedAtMs']),
      rewardCampaignId: m['rewardCampaignId'] as String?,
      toppingUnitPrice: _int(m['toppingUnitPrice']) ?? 0,
      toppingCount: _int(m['toppingCount']) ?? 0,
    );

Map<String, dynamic> _snapshot(PriceQuoteModel q) {
  Map<String, int?> allocs(Map<String, int> a) {
    final keys = a.keys.where((k) => a[k] != 0).toList()..sort();
    return {for (final k in keys) k: a[k]};
  }

  return {
    'total': q.totalPromotionDiscount,
    'applied': q.appliedCampaignIds.isNotEmpty,
    'lines': {for (final lb in q.lineBenefits) if (lb.discountMoney != 0) lb.lineId: lb.discountMoney},
    'rewards': [for (final r in q.rewardBenefits) [r.lineId, r.discountMoney, r.quantity]],
    'bill': [for (final b in q.billBenefits) [b.tierId, b.discountMoney, allocs(b.lineAllocations)]],
    'reasons': [for (final r in q.reasons) r.reasonCode],
  };
}

void main() {
  final scenarios = jsonDecode(_doc('pricing_parity.json').readAsStringSync()) as Map<String, dynamic>;
  final expected = jsonDecode(_doc('pricing_parity_expected.json').readAsStringSync()) as Map<String, dynamic>;

  group('Đối chiếu khuyến mãi app ↔ web (docs/pricing_parity.json)', () {
    for (final raw in scenarios['cases'] as List) {
      final c = raw as Map<String, dynamic>;
      test(c['name'] as String, () {
        final camps = [
          for (final m in c['campaigns'] as List) CampaignModel.fromMap(Map<String, dynamic>.from(m as Map)),
        ];
        final res = CartCampaignPricing.quoteStackedLines(
          camps,
          [for (final l in c['lines'] as List) _line(Map<String, dynamic>.from(l as Map))],
          branchId: c['branchId'] as String,
          guestCount: _int(c['guestCount']),
          customerBirthday: c['customerBirthday'] as String?,
          nowMs: _int(c['nowMs']),
          ignoreScheduleFor: {...(c['ignoreScheduleFor'] as List).cast<String>()},
          dedicatedOnlyFor: {...(c['dedicatedOnlyFor'] as List).cast<String>()},
        );
        final actual = {for (final k in camps) k.campaignId: _snapshot(res[k.campaignId]!)};
        // So qua JSON để kiểu số / thứ tự khóa giống hệt bên web
        expect(jsonDecode(jsonEncode(actual)), expected[c['name']]);
      });
    }
  });
}
