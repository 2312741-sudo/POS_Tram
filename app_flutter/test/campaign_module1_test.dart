import 'package:flutter_test/flutter_test.dart';
import '../lib/data/models/campaign_models.dart';
import '../lib/core/domain/pricing_engine.dart';
import '../lib/core/domain/promotion_migration.dart';
import '../lib/data/models/app_models.dart';

void main() {
  group('Module 1: Campaign TimeSlot & Schedule (Happy hours & daysOfWeek)', () {
    test('CampaignTimeSlot containsTime correctly checks standard and overnight intervals', () {
      final slot1 = CampaignTimeSlot(startTime: '08:00', endTime: '11:00');
      expect(slot1.containsTime(8, 0), true);
      expect(slot1.containsTime(10, 30), true);
      expect(slot1.containsTime(11, 0), true);
      expect(slot1.containsTime(11, 1), false);
      expect(slot1.containsTime(7, 59), false);

      final slotOvernight = CampaignTimeSlot(startTime: '22:00', endTime: '02:00');
      expect(slotOvernight.containsTime(22, 30), true);
      expect(slotOvernight.containsTime(1, 15), true);
      expect(slotOvernight.containsTime(12, 0), false);
    });

    test('CampaignModel isEligibleAt verifies daysOfWeek (1=T2 .. 7=CN)', () {
      // 2026-10-12 is Monday (weekday = 1)
      // 2026-10-18 is Sunday (weekday = 7)
      final mondayMs = DateTime(2026, 10, 12, 10, 0).millisecondsSinceEpoch;
      final sundayMs = DateTime(2026, 10, 18, 10, 0).millisecondsSinceEpoch;

      final campaign = CampaignModel(
        campaignId: 'c_dow',
        programCode: 'KM_DOW',
        name: 'Chỉ áp dụng Thứ 2',
        description: '',
        campaignType: CampaignType.billDiscount.toMap(),
        schedule: CampaignSchedule(
          daysOfWeek: [1], // Chỉ Thứ 2
        ),
        branchIds: [],
        includedCustomerIds: [],
        excludedCustomerIds: [],
        includedItemIds: [],
        includedGroupIds: [],
        excludedItemIds: [],
        tiers: [],
        buyConditions: [],
        warnRepeatedCustomer: false,
        hasCodes: false,
        autoApply: true,
        requireStaffNote: false,
        stackingMode: 'DISABLED',
        priority: 1,
        active: true,
        createdAt: 0,
        updatedAt: 0,
        createdBy: 'test',
        version: 1,
      );

      expect(campaign.isEligibleAt(mondayMs), true);
      expect(campaign.isEligibleAt(sundayMs), false);
    });

    test('CampaignModel isEligibleAt verifies happy hours (timeSlots)', () {
      // 10:30 inside slot, 15:00 outside slot
      final timeInside = DateTime(2026, 10, 12, 10, 30).millisecondsSinceEpoch;
      final timeOutside = DateTime(2026, 10, 12, 15, 0).millisecondsSinceEpoch;

      final campaign = CampaignModel(
        campaignId: 'c_hh',
        programCode: 'KM_HH',
        name: 'Happy Hour 09h - 11h',
        description: '',
        campaignType: CampaignType.billDiscount.toMap(),
        schedule: CampaignSchedule(
          timeSlots: [
            CampaignTimeSlot(startTime: '09:00', endTime: '11:00'),
          ],
        ),
        branchIds: [],
        includedCustomerIds: [],
        excludedCustomerIds: [],
        includedItemIds: [],
        includedGroupIds: [],
        excludedItemIds: [],
        tiers: [],
        buyConditions: [],
        warnRepeatedCustomer: false,
        hasCodes: false,
        autoApply: true,
        requireStaffNote: false,
        stackingMode: 'DISABLED',
        priority: 1,
        active: true,
        createdAt: 0,
        updatedAt: 0,
        createdBy: 'test',
        version: 1,
      );

      expect(campaign.isEligibleAt(timeInside), true);
      expect(campaign.isEligibleAt(timeOutside), false);
    });
  });

  group('Module 1: requireStaffNote flag', () {
    test('CampaignModel preserves requireStaffNote in map round-trip', () {
      final campaign = CampaignModel(
        campaignId: 'c_note',
        programCode: 'KM_NOTE',
        name: 'Bắt buộc ghi chú',
        description: '',
        campaignType: CampaignType.billDiscount.toMap(),
        schedule: CampaignSchedule(),
        branchIds: [],
        includedCustomerIds: [],
        excludedCustomerIds: [],
        includedItemIds: [],
        includedGroupIds: [],
        excludedItemIds: [],
        tiers: [],
        buyConditions: [],
        warnRepeatedCustomer: false,
        hasCodes: true,
        autoApply: false,
        requireStaffNote: true,
        stackingMode: 'DISABLED',
        priority: 1,
        active: true,
        createdAt: 0,
        updatedAt: 0,
        createdBy: 'test',
        version: 1,
      );

      final map = campaign.toMap();
      expect(map['requireStaffNote'], true);

      final restored = CampaignModel.fromMap(map);
      expect(restored.requireStaffNote, true);
    });

    test('PromotionMigration round-trip supports requireStaffNote', () {
      final old = PromotionModel(
        id: 'p_note',
        name: 'Promo Note',
        type: 'VOUCHER',
        value: 10,
        startDate: 0,
        endDate: 0,
        requireStaffNote: true,
      );

      final campaign = PromotionMigration.fromLegacy(old);
      expect(campaign.requireStaffNote, true);

      final restored = PromotionMigration.toLegacy(campaign);
      expect(restored.requireStaffNote, true);
    });
  });

  group('Module 1: Pricing with item/group filters & discount calculation', () {
    test('Bill discount applies only to eligible items/groups and calculates % with cap', () {
      final campaign = CampaignModel(
        campaignId: 'c_discount',
        programCode: 'KM_DISC',
        name: 'Giảm 20% nhóm Trà sữa tối đa 30k',
        description: '',
        campaignType: CampaignType.billDiscount.toMap(),
        schedule: CampaignSchedule(),
        branchIds: [],
        includedCustomerIds: [],
        excludedCustomerIds: [],
        includedItemIds: [],
        includedGroupIds: ['TRA_SUA'],
        excludedItemIds: [],
        tiers: [
          CampaignTier(
            tierId: 't1',
            conditionBasis: ConditionBasis.totalAmount.toMap(),
            threshold: 50000,
            benefitMode: BenefitMode.percent.toMap(),
            value: 2000, // 20% in basis points
            maxDiscountMoney: 30000, // trần 30k
            maxRewardQty: 0,
            rewardItemIds: [],
            sortOrder: 1,
          )
        ],
        buyConditions: [],
        warnRepeatedCustomer: false,
        hasCodes: false,
        autoApply: true,
        requireStaffNote: false,
        stackingMode: 'DISABLED',
        priority: 1,
        active: true,
        createdAt: 0,
        updatedAt: 0,
        createdBy: 'test',
        version: 1,
      );

      // Input: 2 items: 1 Trà sữa (price 200k), 1 Bánh (price 100k)
      // Base for trà sữa is 200k >= 50k threshold
      // 20% of 200k = 40k, but maxDiscountMoney = 30k -> discount = 30k
      final input = PricingInput(
        branchId: 'TRAM01',
        serverNowMs: DateTime.now().millisecondsSinceEpoch,
        lines: [
          PricingLineItem(
            lineId: 'l1',
            itemId: 'prod_ts',
            groupId: 'TRA_SUA',
            quantity: 1,
            unitPrice: 200000,
          ),
          PricingLineItem(
            lineId: 'l2',
            itemId: 'prod_cake',
            groupId: 'BANH',
            quantity: 1,
            unitPrice: 100000,
          ),
        ],
      );

      final quote = calculatePrice(
        input: input,
        activeCampaigns: [campaign],
        counters: {},
        customerCounters: {},
      );

      expect(quote.totalPromotionDiscount, 30000);
      expect(quote.netMoney, 300000 - 30000);
    });

    test('Bill discount applies fixed VND amount when condition is met', () {
      final campaign = CampaignModel(
        campaignId: 'c_fixed',
        programCode: 'KM_FIXED',
        name: 'Giảm 25k cho đơn từ 100k',
        description: '',
        campaignType: CampaignType.billDiscount.toMap(),
        schedule: CampaignSchedule(),
        branchIds: [],
        includedCustomerIds: [],
        excludedCustomerIds: [],
        includedItemIds: [],
        includedGroupIds: [],
        excludedItemIds: [],
        tiers: [
          CampaignTier(
            tierId: 't1',
            conditionBasis: ConditionBasis.totalAmount.toMap(),
            threshold: 100000,
            benefitMode: BenefitMode.fixed.toMap(),
            value: 25000, // 25k VND
            maxDiscountMoney: 0,
            maxRewardQty: 0,
            rewardItemIds: [],
            sortOrder: 1,
          )
        ],
        buyConditions: [],
        warnRepeatedCustomer: false,
        hasCodes: false,
        autoApply: true,
        requireStaffNote: false,
        stackingMode: 'DISABLED',
        priority: 1,
        active: true,
        createdAt: 0,
        updatedAt: 0,
        createdBy: 'test',
        version: 1,
      );

      final input = PricingInput(
        branchId: 'TRAM01',
        serverNowMs: DateTime.now().millisecondsSinceEpoch,
        lines: [
          PricingLineItem(
            lineId: 'l1',
            itemId: 'prod_1',
            quantity: 2,
            unitPrice: 60000, // Total 120k >= 100k
          ),
        ],
      );

      final quote = calculatePrice(
        input: input,
        activeCampaigns: [campaign],
        counters: {},
        customerCounters: {},
      );

      expect(quote.totalPromotionDiscount, 25000);
      expect(quote.netMoney, 120000 - 25000);
    });
  });
}
