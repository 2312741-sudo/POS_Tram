import '../../data/models/app_models.dart';
import '../../data/models/campaign_models.dart';
import '../../data/models/inventory_models.dart';

/// Kết quả validation trước khi thanh toán
class CheckoutValidation {
  final bool canProceed;
  final List<CheckoutWarning> warnings;
  final List<CheckoutError> errors;
  
  CheckoutValidation({
    required this.canProceed,
    this.warnings = const [],
    this.errors = const [],
  });
}

class CheckoutWarning {
  final String code;
  final String message;
  
  CheckoutWarning(this.code, this.message);
}

class CheckoutError {
  final String code;
  final String message;
  
  CheckoutError(this.code, this.message);
}

class CheckoutValidator {
  /// Validate trước khi thanh toán
  static CheckoutValidation validate({
    required BillModel bill,
    required List<CampaignModel> appliedCampaigns,
    required Map<String, CampaignCountersModel> counters,
    List<StockBalanceModel>? stockBalances,
    List<CatalogItemModel>? catalogItems,
  }) {
    final warnings = <CheckoutWarning>[];
    final errors = <CheckoutError>[];
    
    // 1. Validate bill amounts
    if (bill.items.isEmpty) {
      errors.add(CheckoutError('EMPTY_ITEMS', 'Đơn hàng không có sản phẩm'));
    }
    
    if (bill.finalAmount < 0) {
      errors.add(CheckoutError('NEGATIVE_AMOUNT', 'Tổng tiền không được âm'));
    }
    
    if (bill.totalDiscount > bill.subTotal) {
      errors.add(CheckoutError('DISCOUNT_EXCEEDS_SUBTOTAL', 'Giảm giá không được vượt quá tạm tính'));
    }
    
    // 4. Validate payment method
    if (bill.paymentMethod.isEmpty) {
      errors.add(CheckoutError('EMPTY_PAYMENT_METHOD', 'Chưa chọn phương thức thanh toán'));
    }
    
    // 5. Validate discount integrity
    int sumLineDiscounts = 0;
    for (final item in bill.items) {
      sumLineDiscounts += item.discountAmount;
      if (item.discountAmount > (item.quantity * item.price)) {
        errors.add(CheckoutError('LINE_DISCOUNT_EXCEEDS_TOTAL', 'Giảm giá dòng ${item.name} vượt quá thành tiền'));
      }
    }
    
    if (sumLineDiscounts != bill.totalDiscount) {
      errors.add(CheckoutError('DISCOUNT_MISMATCH', 'Tổng giảm giá dòng không khớp tổng giảm giá hóa đơn'));
    }
    
    // 2. Validate campaign budgets
    for (final campaign in appliedCampaigns) {
      final counter = counters[campaign.campaignId];
      if (counter != null) {
        if ((campaign.budgetMoney ?? 0) > 0) {
          final spent = counter.spentMoney;
          final thisDiscount = bill.totalDiscount; // Simplification, should map per campaign if possible
          if (spent + thisDiscount > campaign.budgetMoney!) {
            warnings.add(CheckoutWarning('BUDGET_EXCEEDED', 'Chương trình ${campaign.name} vượt ngân sách'));
          }
        }
        
        if ((campaign.maxUses ?? 0) > 0) {
          if (counter.committedUseCount >= campaign.maxUses!) {
            errors.add(CheckoutError('QUOTA_EXHAUSTED', 'Chương trình ${campaign.name} đã hết lượt sử dụng'));
          }
        }
      }
    }
    
    // 3. Validate stock (warning only, don't block)
    if (stockBalances != null && catalogItems != null) {
      // Simplified stock check logic
      for (final item in bill.items) {
        final catalogItem = catalogItems.firstWhere(
          (c) => c.itemId == item.productId.toString(), 
          orElse: () => CatalogItemModel(
            itemId: '', name: '', baseUnitId: '', costPrice: 0,
            createdAt: 0, updatedAt: 0, trackStock: false
          )
        );
        
        if (catalogItem.trackStock && (catalogItem.kind == 'MADE_TO_ORDER' || catalogItem.kind == 'MANUFACTURED')) {
          // This would require more detailed recipe evaluation, simplified for now
          // If a balance exists, check it
          final balance = stockBalances.firstWhere(
            (b) => b.itemId == item.productId.toString(), 
            orElse: () => StockBalanceModel(
              balanceId: '', branchId: '', itemId: '',
              onHandQty: 0, reservedQty: 0, inventoryValue: 0, averageCostScaled: 0, 
              lastEventSeq: 0, updatedAt: 0
            )
          );
          
          if (balance.balanceId.isNotEmpty && balance.availableQty < item.quantity) {
             warnings.add(CheckoutWarning('LOW_STOCK', 'Sản phẩm ${item.name} thiếu ${item.quantity - balance.availableQty} tồn kho'));
          }
        }
      }
    }
    
    final canProceed = errors.isEmpty;
    return CheckoutValidation(canProceed: canProceed, warnings: warnings, errors: errors);
  }
  
  /// Quick validate just the bill structure (no external data needed)
  static CheckoutValidation validateBillStructure(BillModel bill) {
    return validate(
      bill: bill, 
      appliedCampaigns: [], 
      counters: {}
    );
  }
}
