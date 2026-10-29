// lib/core/reports/topping_split.dart
//
// Tách một dòng món thành MÓN GỐC + từng TOPPING để báo cáo hàng hóa đếm số bán / doanh thu topping riêng.
// Bản TypeScript song song: web/lib/topping-split.ts (giữ cùng quy tắc, cùng kết quả trên docs/report_golden.json).
//
//  - Món gốc = (price + sizeExtraPrice) × số lượng.
//  - Mỗi topping = đơn giá topping × số lượng. Đơn giá: giá món topping trong thực đơn (tra theo tên) → chia đều
//    toppingPrice. Có toppingPrice thì các đơn giá được co giãn cho khớp đúng tổng đó.
//  - Giảm giá cả dòng chia theo tỉ lệ tiền giữa món gốc và các topping (tổng không đổi).
//  - Giá vốn topping (danh mục topping / món topping) chuyển sang dòng topping; món gốc giữ giá vốn của chính nó.
import '../../data/models/order_item_model.dart';
import '../../data/models/product_model.dart';

class LinePart {
  final bool isTopping;
  /// Khóa gộp: món gốc do nơi gọi tự quyết; topping = 'topping:id' hoặc 'topping:<tên>'
  final String key;
  final String name;
  final int productId;
  final String code;
  final String category;
  final String unit;
  final int quantity;
  final int grossRevenue;
  final int itemDiscount;
  final int costPrice;
  final String parentName;

  const LinePart({
    required this.isTopping,
    required this.key,
    required this.name,
    this.productId = 0,
    this.code = '',
    this.category = '',
    this.unit = '',
    required this.quantity,
    required this.grossRevenue,
    required this.itemDiscount,
    required this.costPrice,
    this.parentName = '',
  });
}

String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Tra món topping trong thực đơn theo tên (ưu tiên món đánh dấu topping khi trùng tên)
ProductModel? findToppingProduct(String name, Map<int, ProductModel>? productsMap) {
  if (productsMap == null || productsMap.isEmpty) return null;
  final k = _norm(name);
  ProductModel? found;
  for (final p in productsMap.values) {
    if (_norm(p.name) != k) continue;
    if (found == null || (!found.isTopping && p.isTopping)) found = p;
  }
  return found;
}

/// Chia [total] theo trọng số (làm tròn, phần dư dồn vào phần tử cuối) — khớp allocate() bên TS
List<int> allocateByWeight(int total, List<int> weights) {
  if (weights.isEmpty) return const [];
  final sum = weights.fold<int>(0, (s, w) => s + w);
  if (sum <= 0) {
    final each = total ~/ weights.length;
    return [for (var i = 0; i < weights.length; i++) i == weights.length - 1 ? total - each * (weights.length - 1) : each];
  }
  var acc = 0;
  final out = <int>[];
  for (var i = 0; i < weights.length; i++) {
    if (i == weights.length - 1) {
      out.add(total - acc);
    } else {
      final v = (total * weights[i] / sum).round();
      acc += v;
      out.add(v);
    }
  }
  return out;
}

/// [mainUnitCost] = giá vốn MỘT phần của món gốc (không gồm topping);
/// [toppingCostOf] = giá vốn một phần topping theo tên (null = không rõ → tra món topping trong thực đơn).
List<LinePart> splitLineParts(
  OrderItemModel it, {
  required String mainKey,
  required int mainUnitCost,
  Map<int, ProductModel>? productsMap,
  int? Function(String name)? toppingCostOf,
}) {
  final qty = it.quantity > 0 ? it.quantity : 1;
  final tops = it.selectedToppings.where((t) => t.trim().isNotEmpty).toList();
  final lookups = [for (final t in tops) findToppingProduct(t, productsMap)];

  final known = [for (final p in lookups) p?.price ?? 0];
  final toppingUnitTotal = it.toppingPrice > 0 ? it.toppingPrice : known.fold<int>(0, (s, p) => s + p);
  final topUnits = tops.isEmpty ? const <int>[] : allocateByWeight(toppingUnitTotal, known);
  final topGross = [for (final u in topUnits) u * qty];
  final topGrossSum = topGross.fold<int>(0, (s, g) => s + g);

  final totalGross = it.unitPrice * qty;
  final mainGross = totalGross - topGrossSum < 0 ? 0 : totalGross - topGrossSum;
  final rawDiscount = it.lineDiscountTotal;
  final discount = rawDiscount < 0 ? 0 : (rawDiscount > mainGross + topGrossSum ? mainGross + topGrossSum : rawDiscount);
  final discounts = allocateByWeight(discount, [mainGross, ...topGross]);

  final parts = <LinePart>[
    LinePart(
      isTopping: false,
      key: mainKey,
      name: it.name,
      productId: it.productId,
      quantity: qty,
      grossRevenue: mainGross,
      itemDiscount: discounts.isEmpty ? 0 : discounts[0],
      costPrice: mainUnitCost * qty,
    ),
  ];
  for (var i = 0; i < tops.length; i++) {
    final p = lookups[i];
    final unitCost = toppingCostOf?.call(tops[i]) ?? p?.costPrice ?? 0;
    parts.add(LinePart(
      isTopping: true,
      key: p != null && p.id > 0 ? 'topping:id:${p.id}' : 'topping:${_norm(tops[i])}',
      name: tops[i],
      productId: p != null && p.id > 0 ? p.id : 0,
      code: p?.code ?? '',
      category: (p != null && p.category.isNotEmpty && p.category != 'Khác') ? p.category : 'Topping',
      unit: (p != null && p.unit.isNotEmpty) ? p.unit : 'Phần',
      quantity: qty,
      grossRevenue: topGross[i],
      itemDiscount: discounts[i + 1],
      costPrice: unitCost * qty,
      parentName: it.name,
    ));
  }
  return parts;
}
