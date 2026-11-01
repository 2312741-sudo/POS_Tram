// lib/core/domain/topping_ref.dart
//
// Tra món topping từ một tham chiếu trong cấu hình (categories.allowedToppingIds / products.allowedToppings).
// Web lưu KHÓA RTDB của món (products/{key}, vd push id "-Nx…" hoặc tên khóa); dữ liệu cũ có thể là id số,
// mã món hoặc tên. Khớp mọi định danh qua ProductModel.matchesTarget (id, tên, mã, dbKey).
import '../../data/models/product_model.dart';

class ToppingRef {
  ToppingRef._();

  /// Món topping khớp [ref] trong thực đơn, rồi trong [defaults]; null nếu không tìm thấy.
  /// Ưu tiên món đánh dấu topping khi trùng định danh với món thường.
  static ProductModel? find(String ref, List<ProductModel> products, {List<ProductModel> defaults = const []}) {
    final r = ref.trim();
    if (r.isEmpty) return null;
    ProductModel? hit;
    for (final p in products) {
      if (!p.matchesTarget(r)) continue;
      if (hit == null || (!hit.isTopping && p.isTopping)) hit = p;
    }
    if (hit != null) return hit;
    for (final p in defaults) {
      if (p.matchesTarget(r)) return p;
    }
    return null;
  }
}
