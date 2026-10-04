import '../../data/models/inventory_models.dart';

class StockEngine {
  /// Tính giá vốn bình quân gia quyền khi nhập hàng
  /// newAvgCost = (oldQty * oldAvgCost + newQty * newUnitCost) / (oldQty + newQty)
  static int calculateMovingWeightedAverage({
    required int oldQty,
    required int oldAvgCostScaled,  // *100
    required int newQty,
    required int newUnitCostScaled,  // *100
  }) {
    if (oldQty + newQty == 0) return 0;
    if (newQty == 0) return oldAvgCostScaled;
    final total = (oldQty.toDouble() * oldAvgCostScaled + newQty.toDouble() * newUnitCostScaled);
    return (total / (oldQty + newQty)).round();
  }

  /// Tính nguyên liệu cần tiêu thụ cho 1 món
  /// Returns map of {ingredientItemId: requiredQty}
  static Map<String, int> calculateRecipeConsumption({
    required RecipeVersionModel recipe,
    required int quantity,  // số món bán
  }) {
    final result = <String, int>{};
    for (final ing in recipe.ingredients) {
      final qty = ing.quantityBase * quantity;
      result[ing.itemId] = (result[ing.itemId] ?? 0) + qty;
    }
    return result;
  }

  /// Kiểm tra tồn kho đủ cho đơn hàng
  static List<StockShortage> checkStockAvailability({
    required Map<String, int> requiredIngredients,  // from calculateRecipeConsumption
    required Map<String, StockBalanceModel> balances,
  }) {
    final shortages = <StockShortage>[];
    for (final entry in requiredIngredients.entries) {
      final balance = balances[entry.key];
      final available = balance?.availableQty ?? 0;
      if (available < entry.value) {
        shortages.add(StockShortage(
          itemId: entry.key,
          required: entry.value,
          available: available,
          shortage: entry.value - available,
        ));
      }
    }
    return shortages;
  }

  /// Validate inventory document before completion
  static List<String> validateDocument(InventoryDocumentModel doc) {
    final errors = <String>[];
    if (doc.lines.isEmpty) errors.add('Phiếu không có dòng hàng');
    if (doc.status != 'DRAFT') errors.add('Chỉ duyệt phiếu tạm');
    for (final line in doc.lines) {
      if (line.quantity <= 0) errors.add('Dòng ${line.itemName}: số lượng phải > 0');
      if (line.unitPrice < 0) errors.add('Dòng ${line.itemName}: đơn giá không hợp lệ');
    }
    return errors;
  }
}

class StockShortage {
  final String itemId;
  final int required;
  final int available;
  final int shortage;
  
  StockShortage({
    required this.itemId,
    required this.required,
    required this.available,
    required this.shortage,
  });
}
