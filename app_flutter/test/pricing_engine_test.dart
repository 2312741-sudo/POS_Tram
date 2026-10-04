import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/pricing_engine.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';

CampaignModel _createCampaign({
  required String id,
  required String type,
  List<CampaignTier>? tiers,
  List<CampaignBuyCondition>? buyConditions,
  List<String>? itemIds,
  bool stackable = true,
  int priority = 0,
  int createdAt = 0,
}) {
  return CampaignModel(
    campaignId: id,
    programCode: id,
    name: id,
    description: '',
    campaignType: type,
    schedule: CampaignSchedule(
      absoluteStart: 0,
      absoluteEnd: 9999999999999,
      excludedDates: [],
    ),
    branchIds: [],
    includedCustomerIds: [],
    excludedCustomerIds: [],
    includedItemIds: itemIds ?? [],
    includedGroupIds: [],
    excludedItemIds: [],
    tiers: tiers ?? [],
    buyConditions: buyConditions ?? [],
    budgetMoney: null,
    maxUses: null,
    maxUsesPerCustomer: null,
    warnRepeatedCustomer: false,
    hasCodes: false,
    autoApply: true,
    stackingMode: stackable ? 'ENABLED' : 'DISABLED',
    priority: priority,
    active: true,
    createdAt: createdAt,
    updatedAt: createdAt,
    createdBy: 'test',
    version: 1,
  );
}

void main() {
  group('Pricing Engine Tests', () {
    test('A-08: Bill discount basic - percent capped', () {
      var lines = [PricingLineItem(lineId: '1', itemId: 'A', quantity: 1, unitPrice: 100000)];
      var campaigns = [
        _createCampaign(
          id: 'C1',
          type: 'BILLDISCOUNT',
          tiers: [
            CampaignTier(
              tierId: 'T1',
              conditionBasis: 'TOTALAMOUNT',
              threshold: 0,
              benefitMode: 'PERCENT',
              value: 3000,
              maxDiscountMoney: 20000,
              maxRewardQty: 0,
              rewardItemIds: [],
              sortOrder: 1,
            )
          ],
        )
      ];

      var input = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines);
      var result = calculatePrice(
        input: input,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );

      expect(result.grossMoney, 100000);
      expect(result.totalDiscountMoney, 20000);
      expect(result.netMoney, 80000);
    });

    test('A-08: Bill discount basic - fixed capped at bill amount', () {
      var lines = [PricingLineItem(lineId: '1', itemId: 'A', quantity: 1, unitPrice: 100000)];
      var campaigns = [
        _createCampaign(
          id: 'C2',
          type: 'BILLDISCOUNT',
          tiers: [
            CampaignTier(
              tierId: 'T1',
              conditionBasis: 'TOTALAMOUNT',
              threshold: 0,
              benefitMode: 'FIXED',
              value: 200000,
              maxDiscountMoney: 0,
              maxRewardQty: 0,
              rewardItemIds: [],
              sortOrder: 1,
            )
          ],
        )
      ];

      var input = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines);
      var result = calculatePrice(
        input: input,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );

      expect(result.totalDiscountMoney, 100000);
      expect(result.netMoney, 0);
    });

    test('A-09: Guest count condition', () {
      var lines = [PricingLineItem(lineId: '1', itemId: 'A', quantity: 1, unitPrice: 100000)];
      var campaigns = [
        _createCampaign(
          id: 'C3',
          type: 'BILLDISCOUNT',
          tiers: [
            CampaignTier(
              tierId: 'T1',
              conditionBasis: 'GUESTCOUNT',
              threshold: 4,
              benefitMode: 'FIXED',
              value: 10000,
              maxDiscountMoney: 0,
              maxRewardQty: 0,
              rewardItemIds: [],
              sortOrder: 1,
            )
          ],
        )
      ];

      var input1 = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines);
      var result1 = calculatePrice(
        input: input1,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result1.totalDiscountMoney, 0);
      expect(result1.reasons.any((r) => r.campaignId == 'C3' && r.reasonCode == 'GUEST_COUNT_REQUIRED'), true);

      var input2 = PricingInput(branchId: 'B1', guestCount: 5, serverNowMs: 0, lines: lines);
      var result2 = calculatePrice(
        input: input2,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result2.totalDiscountMoney, 10000);
      expect(result2.appliedCampaignIds.contains('C3'), true);
    });

    test('A-11: Buy 2 X Get 1 Y', () {
      var campaigns = [
        _createCampaign(
          id: 'C4',
          type: 'BUYXGETY',
          buyConditions: [
            CampaignBuyCondition(
              conditionId: 'BC1',
              buyItemIds: ['X'],
              requiredBuyQty: 2,
              rewardItemIds: ['Y'],
              rewardQty: 1,
              benefitMode: 'FREEITEM',
              value: 0,
              multiplyByBundle: true,
            )
          ],
        ),
        _createCampaign(
          id: 'C5',
          type: 'BUYXGETY',
          buyConditions: [
            CampaignBuyCondition(
              conditionId: 'BC2',
              buyItemIds: ['X'],
              requiredBuyQty: 2,
              rewardItemIds: ['Y'],
              rewardQty: 1,
              benefitMode: 'FREEITEM',
              value: 0,
              multiplyByBundle: false,
            )
          ],
        )
      ];

      var lines1 = [
        PricingLineItem(lineId: '1', itemId: 'X', quantity: 5, unitPrice: 10000),
        PricingLineItem(lineId: '2', itemId: 'Y', quantity: 2, unitPrice: 10000), 
      ];
      var input1 = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines1);
      var result1 = calculatePrice(
        input: input1,
        activeCampaigns: [campaigns[0]],
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result1.appliedCampaignIds.contains('C4'), true);

      var input2 = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines1);
      var result2 = calculatePrice(
        input: input2,
        activeCampaigns: [campaigns[1]],
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result2.appliedCampaignIds.contains('C5'), true);

      var lines2 = [PricingLineItem(lineId: '1', itemId: 'X', quantity: 1, unitPrice: 10000)];
      var input3 = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines2);
      var result3 = calculatePrice(
        input: input3,
        activeCampaigns: [campaigns[0]],
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result3.appliedCampaignIds.contains('C4'), false);
    });

    test('A-12: X=Y edge case', () {
      var campaigns = [
        _createCampaign(
          id: 'C6',
          type: 'BUYXGETY',
          buyConditions: [
            CampaignBuyCondition(
              conditionId: 'BC1',
              buyItemIds: ['X'],
              requiredBuyQty: 2,
              rewardItemIds: ['X'],
              rewardQty: 1,
              benefitMode: 'FREEITEM',
              value: 0,
              multiplyByBundle: true,
            )
          ],
        )
      ];

      var lines1 = [PricingLineItem(lineId: '1', itemId: 'X', quantity: 3, unitPrice: 10000)];
      var input1 = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines1);
      var result1 = calculatePrice(
        input: input1,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result1.appliedCampaignIds.contains('C6'), true);

      var lines2 = [PricingLineItem(lineId: '1', itemId: 'X', quantity: 2, unitPrice: 10000)];
      var input2 = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines2);
      var result2 = calculatePrice(
        input: input2,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result2.appliedCampaignIds.contains('C6'), false);
    });

    test('A-13: Fixed price rule', () {
      var campaigns = [
        _createCampaign(
          id: 'C7',
          type: 'ITEMPRICERULE',
          itemIds: ['A'],
          tiers: [
            CampaignTier(
              tierId: 'T1',
              conditionBasis: 'TOTALAMOUNT',
              threshold: 0,
              benefitMode: 'FIXEDPRICE',
              value: 20000,
              maxDiscountMoney: 0,
              maxRewardQty: 0,
              rewardItemIds: [],
              sortOrder: 1,
            )
          ],
        )
      ];

      var lines1 = [PricingLineItem(lineId: '1', itemId: 'A', quantity: 1, unitPrice: 30000)];
      var input1 = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines1);
      var result1 = calculatePrice(
        input: input1,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result1.totalDiscountMoney, 10000);
      expect(result1.netMoney, 20000);

      var lines2 = [PricingLineItem(lineId: '1', itemId: 'A', quantity: 1, unitPrice: 15000)];
      var input2 = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines2);
      var result2 = calculatePrice(
        input: input2,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result2.totalDiscountMoney, 0);
      expect(result2.netMoney, 15000);
    });

    test('A-19: No-stack bill discount selection', () {
      var lines = [PricingLineItem(lineId: '1', itemId: 'A', quantity: 1, unitPrice: 100000)];
      var campaigns = [
        _createCampaign(
          id: 'C8',
          type: 'BILLDISCOUNT',
          stackable: false,
          priority: 1,
          createdAt: 1,
          tiers: [
            CampaignTier(
              tierId: 'T1',
              conditionBasis: 'TOTALAMOUNT',
              threshold: 0,
              benefitMode: 'FIXED',
              value: 10000,
              maxDiscountMoney: 0,
              maxRewardQty: 0,
              rewardItemIds: [],
              sortOrder: 1,
            )
          ],
        ),
        _createCampaign(
          id: 'C9',
          type: 'BILLDISCOUNT',
          stackable: false,
          priority: 2,
          createdAt: 2,
          tiers: [
            CampaignTier(
              tierId: 'T1',
              conditionBasis: 'TOTALAMOUNT',
              threshold: 0,
              benefitMode: 'FIXED',
              value: 15000,
              maxDiscountMoney: 0,
              maxRewardQty: 0,
              rewardItemIds: [],
              sortOrder: 1,
            )
          ],
        )
      ];

      var input = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines);
      var result = calculatePrice(
        input: input,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );
      expect(result.totalDiscountMoney, 15000);
      expect(result.appliedCampaignIds.contains('C9'), true);
      expect(result.appliedCampaignIds.contains('C8'), false);
    });

    test('A-21: Bill discount allocation', () {
      var lines = [
        PricingLineItem(lineId: '1', itemId: 'A', quantity: 1, unitPrice: 1000),
        PricingLineItem(lineId: '2', itemId: 'B', quantity: 1, unitPrice: 1000),
        PricingLineItem(lineId: '3', itemId: 'C', quantity: 1, unitPrice: 1000),
      ];
      var campaigns = [
        _createCampaign(
          id: 'C10',
          type: 'BILLDISCOUNT',
          tiers: [
            CampaignTier(
              tierId: 'T1',
              conditionBasis: 'TOTALAMOUNT',
              threshold: 0,
              benefitMode: 'FIXED',
              value: 10,
              maxDiscountMoney: 0,
              maxRewardQty: 0,
              rewardItemIds: [],
              sortOrder: 1,
            )
          ],
        )
      ];

      var input = PricingInput(branchId: 'B1', serverNowMs: 0, lines: lines);
      var result = calculatePrice(
        input: input,
        activeCampaigns: campaigns,
        counters: {},
        customerCounters: {},
        voucherByCode: null,
      );

      expect(result.totalDiscountMoney, 10);
      var billBenefits = result.billBenefits;
      expect(billBenefits.length, 1);
      
      var allocs = billBenefits.first.lineAllocations.values.toList();
      allocs.sort((a, b) => b.compareTo(a));
      expect(allocs[0], 4);
      expect(allocs[1], 3);
      expect(allocs[2], 3);
    });
  });
}
