import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/domain/promotion_migration.dart';
import '../lib/data/models/app_models.dart';
import '../lib/data/models/campaign_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PromotionMigration', () {
    test('PERCENT_BILL → BILL_DISCOUNT conversion with correct benefitBps', () {
      final old = PromotionModel(
        id: 'p1',
        name: 'Giảm 10%',
        type: 'PERCENT_BILL',
        value: 10,
        maxDiscountAmount: 50000,
        minBillAmount: 100000,
        startDate: 1000,
        endDate: 2000,
        isActive: true,
      );

      final campaign = PromotionMigration.fromLegacy(old);

      expect(campaign.campaignType, CampaignType.billDiscount.toMap());
      expect(campaign.tiers.length, 1);
      
      final tier = campaign.tiers.first;
      expect(tier.benefitMode, BenefitMode.percent.toMap());
      expect(tier.value, 1000); // 10 * 100
      expect(tier.maxDiscountMoney, 50000);
      expect(tier.threshold, 100000);
    });

    test('FIXED_BILL → BILL_DISCOUNT conversion with correct benefitFixedMoney', () {
      final old = PromotionModel(
        id: 'p2',
        name: 'Giảm 25k',
        type: 'FIXED_BILL',
        value: 25000,
        minBillAmount: 150000,
        startDate: 1000,
        endDate: 2000,
        isActive: true,
      );

      final campaign = PromotionMigration.fromLegacy(old);

      expect(campaign.campaignType, CampaignType.billDiscount.toMap());
      expect(campaign.tiers.length, 1);
      
      final tier = campaign.tiers.first;
      expect(tier.benefitMode, BenefitMode.fixed.toMap());
      expect(tier.value, 25000);
      expect(tier.threshold, 150000);
    });

    test('PERCENT_ITEM → ITEM_PRICE_RULE conversion', () {
      final old = PromotionModel(
        id: 'p3',
        name: 'Giảm món 20%',
        type: 'PERCENT_ITEM',
        value: 20,
        targetProductId: 123,
        startDate: 1000,
        endDate: 2000,
        isActive: true,
      );

      final campaign = PromotionMigration.fromLegacy(old);

      expect(campaign.campaignType, CampaignType.itemPriceRule.toMap());
      expect(campaign.includedItemIds, ['123']);
      expect(campaign.tiers.first.benefitMode, BenefitMode.percent.toMap());
      expect(campaign.tiers.first.value, 2000);
    });

    test('FIXED_ITEM → ITEM_PRICE_RULE conversion', () {
      final old = PromotionModel(
        id: 'p4',
        name: 'Giảm món 10k',
        type: 'FIXED_ITEM',
        value: 10000,
        targetProductId: 456,
        startDate: 1000,
        endDate: 2000,
        isActive: true,
      );

      final campaign = PromotionMigration.fromLegacy(old);

      expect(campaign.campaignType, CampaignType.itemPriceRule.toMap());
      expect(campaign.includedItemIds, ['456']);
      expect(campaign.tiers.first.benefitMode, BenefitMode.fixed.toMap());
      expect(campaign.tiers.first.value, 10000);
    });

    test('VOUCHER ambiguity produces warning', () {
      final old = PromotionModel(
        id: 'v1',
        name: 'Voucher 15%',
        type: 'VOUCHER',
        code: 'SALE15',
        value: 15,
        startDate: 1000,
        endDate: 2000,
        isActive: true,
      );

      final campaign = PromotionMigration.fromLegacy(old);
      expect(campaign.hasCodes, true);
      expect(campaign.autoApply, false);

      final warnings = PromotionMigration.validateMigration(old, campaign);
      expect(warnings.any((w) => w.contains('VOUCHER type ambiguous')), true);
    });

    test('schedule migration with start/end dates', () {
      final old = PromotionModel(
        id: 's1',
        name: 'Schedule test',
        type: 'PERCENT_BILL',
        value: 10,
        startDate: 1600000000,
        endDate: 1700000000,
        isActive: true,
      );

      final campaign = PromotionMigration.fromLegacy(old);
      expect(campaign.schedule.absoluteStart, 1600000000);
      expect(campaign.schedule.absoluteEnd, 1700000000);
    });

    test('round-trip: toLegacy(fromLegacy(x)) produces equivalent result', () {
      final old = PromotionModel(
        id: 'r1',
        name: 'Round trip',
        type: 'PERCENT_BILL',
        value: 10,
        maxDiscountAmount: 30000,
        minBillAmount: 50000,
        startDate: 1000,
        endDate: 2000,
        isActive: true,
        maxUsage: 100,
      );

      final campaign = PromotionMigration.fromLegacy(old);
      final restored = PromotionMigration.toLegacy(campaign);

      expect(restored.id, old.id);
      expect(restored.name, old.name);
      expect(restored.type, old.type);
      expect(restored.value, old.value);
      expect(restored.maxDiscountAmount, old.maxDiscountAmount);
      expect(restored.minBillAmount, old.minBillAmount);
      expect(restored.startDate, old.startDate);
      expect(restored.endDate, old.endDate);
      expect(restored.isActive, old.isActive);
      expect(restored.maxUsage, old.maxUsage);
    });

    test('validation catches known issues', () {
      final old = PromotionModel(
        id: 'warn1',
        name: 'Warnings test',
        type: 'VOUCHER',
        value: 10,
        targetCategory: 'DRINKS',
        usageCount: 5,
        startDate: 0,
        endDate: 0,
        isActive: true,
      );

      final campaign = PromotionMigration.fromLegacy(old);
      final warnings = PromotionMigration.validateMigration(old, campaign);

      expect(warnings.length, 3);
      expect(warnings.any((w) => w.contains('VOUCHER type ambiguous')), true);
      expect(warnings.any((w) => w.contains('targetCategory not migrated')), true);
      expect(warnings.any((w) => w.contains('usageCount may be inaccurate')), true);
    });

    test('VoucherModel deserializes Web schema and serializes to dual-platform schema', () {
      // Simulating data written by Web Admin
      final webData = {
        'voucherId': 'VOU_123',
        'campaignId': 'CAM_999',
        'code': 'CHAOBAN20',
        'status': 'ISSUED',
        'createdAt': 1700000000000,
      };

      final voucher = VoucherModel.fromMap(webData);
      expect(voucher.voucherId, 'VOU_123');
      expect(voucher.normalizedCode, 'CHAOBAN20');
      expect(voucher.state, VoucherState.released.toMap());
      expect(voucher.isUsable, true);

      // Serializing produces both code and normalizedCode, status and state
      final serialized = voucher.toMap();
      expect(serialized['code'], 'CHAOBAN20');
      expect(serialized['normalizedCode'], 'CHAOBAN20');
      expect(serialized['status'], 'ISSUED');
      expect(serialized['state'], VoucherState.released.toMap());
    });

    test('CampaignTier parses Web Admin schema correctly', () {
      // Web admin writes thresholdValue, benefitValue, maxBenefitValue, benefitType
      final webTierData = {
        'tierIndex': 0,
        'thresholdType': 'ORDER_VALUE',
        'thresholdValue': 150000,
        'benefitType': 'DISCOUNT_PERCENT',
        'benefitValue': 20,
        'maxBenefitValue': 50000,
      };

      final tier = CampaignTier.fromMap(webTierData);
      expect(tier.threshold, 150000);
      expect(tier.value, 20);
      expect(tier.maxDiscountMoney, 50000);
      expect(tier.benefitMode, BenefitMode.percent.toMap());

      final campaign = CampaignModel(
        campaignId: 'CAM_WEB_1',
        programCode: 'KM0001',
        name: 'Giảm 20% đơn từ 150k',
        description: '',
        campaignType: CampaignType.billDiscount.toMap(),
        schedule: CampaignSchedule(),
        branchIds: [],
        includedCustomerIds: [],
        excludedCustomerIds: [],
        includedItemIds: [],
        includedGroupIds: [],
        excludedItemIds: [],
        tiers: [tier],
        buyConditions: [],
        budgetMoney: null,
        maxUses: null,
        maxUsesPerCustomer: null,
        warnRepeatedCustomer: false,
        hasCodes: true,
        autoApply: false,
        stackingMode: 'STACKABLE',
        priority: 1,
        active: true,
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        createdBy: 'Admin',
        version: 1,
      );

      final legacy = PromotionMigration.toLegacy(campaign);
      expect(legacy.value, 20);
      expect(legacy.minBillAmount, 150000);
      expect(legacy.maxDiscountAmount, 50000);
      expect(legacy.type, 'VOUCHER');
    });
  });
}
