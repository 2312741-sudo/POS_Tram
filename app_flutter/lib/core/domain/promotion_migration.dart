import '../../data/models/app_models.dart';
import '../../data/models/campaign_models.dart';

/// Tiện ích chuyển đổi dữ liệu KM cũ (PromotionModel) sang mới (CampaignModel)
class PromotionMigration {
  /// Convert legacy PromotionModel → CampaignModel
  static CampaignModel fromLegacy(PromotionModel old) {
    final campaignType = mapLegacyType(old.type);
    final isVoucher = old.type == 'VOUCHER' || old.code.isNotEmpty;
    
    return CampaignModel(
      campaignId: 'CAM_MIGRATE_${old.id}',
      programCode: 'MIG_${old.id}', // Auto-generated code for migration
      name: old.name,
      description: old.description,
      campaignType: campaignType.toMap(),
      schedule: buildScheduleFromLegacy(old),
      branchIds: const [], // Empty means all branches
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: old.targetProductId != null ? [old.targetProductId.toString()] : const [],
      includedGroupIds: const [], // targetCategory is ignored as it was dead code in old calculateDiscount
      excludedItemIds: const [],
      tiers: buildTiersFromLegacy(old),
      buyConditions: const [],
      budgetMoney: null,
      maxUses: old.maxUsage > 0 ? old.maxUsage : null,
      maxUsesPerCustomer: null,
      warnRepeatedCustomer: false,
      hasCodes: isVoucher,
      autoApply: !isVoucher,
      requireStaffNote: old.requireStaffNote,
      stackingMode: StackingMode.disabled.toMap(),
      priority: 999, // default low priority
      active: old.isActive,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      createdBy: 'migration_bot',
      version: 1,
      legacyPromotionId: old.id,
    );
  }

  /// Convert new CampaignModel back to legacy format for backward compat
  static PromotionModel toLegacy(CampaignModel campaign) {
    String oldType = 'PERCENT_BILL';
    int value = 0;
    int maxDiscount = 0;
    int minBill = 0;
    String code = '';

    final type = CampaignType.fromMap(campaign.campaignType);
    if (campaign.tiers.isNotEmpty) {
      final tier = campaign.tiers.first;
      minBill = tier.threshold;
      maxDiscount = tier.maxDiscountMoney;
      
      final benefitMode = BenefitMode.fromMap(tier.benefitMode);
      
      if (type == CampaignType.billDiscount) {
        if (campaign.hasCodes) {
          oldType = 'VOUCHER';
          value = benefitMode == BenefitMode.percent ? (tier.value > 100 ? tier.value ~/ 100 : tier.value) : tier.value;
        } else if (benefitMode == BenefitMode.percent) {
          oldType = 'PERCENT_BILL';
          value = tier.value > 100 ? tier.value ~/ 100 : tier.value;
        } else if (benefitMode == BenefitMode.fixed) {
          oldType = 'FIXED_BILL';
          value = tier.value;
        }
      } else if (type == CampaignType.itemPriceRule) {
        if (benefitMode == BenefitMode.percent) {
          oldType = 'PERCENT_ITEM';
          value = tier.value > 100 ? tier.value ~/ 100 : tier.value;
        } else if (benefitMode == BenefitMode.fixed) {
          oldType = 'FIXED_ITEM';
          value = tier.value;
        }
      }
    }

    return PromotionModel(
      id: campaign.legacyPromotionId ?? campaign.campaignId,
      code: code,
      name: campaign.name,
      description: campaign.description,
      type: oldType,
      value: value,
      maxDiscountAmount: maxDiscount,
      minBillAmount: minBill,
      targetCategory: campaign.includedGroupIds.isNotEmpty ? campaign.includedGroupIds.first : null,
      targetProductId: campaign.includedItemIds.isNotEmpty ? int.tryParse(campaign.includedItemIds.first) : null,
      includedItemIds: campaign.includedItemIds,
      includedGroupIds: campaign.includedGroupIds,
      startDate: campaign.schedule.absoluteStart ?? 0,
      endDate: campaign.schedule.absoluteEnd ?? 0,
      isActive: campaign.active,
      usageCount: 0,
      maxUsage: campaign.maxUses ?? 0,
      requireStaffNote: campaign.requireStaffNote,
    );
  }

  /// Determine the new CampaignType from legacy type string
  static CampaignType mapLegacyType(String legacyType) {
    switch (legacyType) {
      case 'PERCENT_BILL': return CampaignType.billDiscount;
      case 'FIXED_BILL': return CampaignType.billDiscount;
      case 'PERCENT_ITEM': return CampaignType.itemPriceRule;
      case 'FIXED_ITEM': return CampaignType.itemPriceRule;
      case 'VOUCHER': return CampaignType.billDiscount;
      default: return CampaignType.billDiscount;
    }
  }

  /// Determine BenefitMode from legacy type
  static BenefitMode mapLegacyBenefitMode(String legacyType) {
    if (legacyType.startsWith('PERCENT') || legacyType == 'VOUCHER') {
      return BenefitMode.percent;
    }
    return BenefitMode.fixed;
  }

  /// Build tiers from legacy values
  static List<CampaignTier> buildTiersFromLegacy(PromotionModel old) {
    final benefitMode = mapLegacyBenefitMode(old.type);
    
    int value = old.value;
    if (benefitMode == BenefitMode.percent) {
      value = old.value * 100; // basis points
    }

    return [
      CampaignTier(
        tierId: 'TIER_1',
        conditionBasis: ConditionBasis.totalAmount.toMap(),
        threshold: old.minBillAmount,
        benefitMode: benefitMode.toMap(),
        value: value,
        maxDiscountMoney: old.maxDiscountAmount,
        maxRewardQty: 0,
        rewardItemIds: const [],
        sortOrder: 1,
      )
    ];
  }

  /// Build schedule from legacy dates
  static CampaignSchedule buildScheduleFromLegacy(PromotionModel old) {
    return CampaignSchedule(
      absoluteStart: old.startDate > 0 ? old.startDate : null,
      absoluteEnd: old.endDate > 0 ? old.endDate : null,
    );
  }

  /// Validate migration result
  static List<String> validateMigration(PromotionModel old, CampaignModel converted) {
    List<String> warnings = [];

    if (old.type == 'VOUCHER') {
      warnings.add('VOUCHER type ambiguous: using PERCENT based on legacy calculateDiscount behavior');
    }
    
    if (old.targetCategory != null && old.targetCategory!.isNotEmpty) {
      warnings.add('targetCategory not migrated (was dead code in legacy)');
    }

    if (old.usageCount > 0) {
      warnings.add('usageCount may be inaccurate due to race condition in legacy incrementPromotionUsage');
    }

    return warnings;
  }
}
