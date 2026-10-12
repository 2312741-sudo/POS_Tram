// lib/core/domain/product_availability.dart
// Logic thuần (không Firebase/UI) cho chức năng "báo hết món".
// Nguồn song song: web/lib/product-availability.ts — giữ đồng bộ.
import '../../data/models/product_model.dart';

/// Giờ "đầu ngày" bán hàng: món báo "Hết đến hết ngày" tự bật lại lúc 05:00.
const int kSoldOutResetHour = 5;

/// Món có bán được tại thời điểm [now] không.
/// - isAvailable != false  => bán được (bỏ qua soldOutUntil cũ còn sót).
/// - isAvailable == false và có soldOutUntil đã qua  => bán được lại (không cần job server).
/// - isAvailable == false (kể cả dữ liệu cũ không có soldOutUntil)  => hết hàng.
bool isProductAvailable(ProductModel p, [DateTime? now]) {
  if (p.isAvailable) return true;
  final until = p.soldOutUntil;
  if (until == null) return false;
  return (now ?? DateTime.now()).millisecondsSinceEpoch >= until;
}

/// Trạng thái hết hàng đã quá hạn tự bật lại nhưng cờ cũ vẫn nằm trong DB (writer dọn dần).
bool isSoldOutStale(ProductModel p, [DateTime? now]) =>
    !p.isAvailable && isProductAvailable(p, now);

/// 05:00 sáng tiếp theo (theo giờ máy): sau 05:00 => 05:00 ngày mai; từ 00:00-04:59 => 05:00 hôm nay.
DateTime nextSoldOutReset(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, kSoldOutResetHour);
  return now.isBefore(today) ? today : DateTime(now.year, now.month, now.day + 1, kSoldOutResetHour);
}

/// Dữ liệu ghi vào products/{key} (dùng với update(); null = xóa trường).
Map<String, Object?> soldOutPatch({
  required bool soldOut,
  required String by,
  required DateTime now,
  bool untilNextReset = false,
}) {
  if (!soldOut) {
    return {'isAvailable': true, 'soldOutAt': null, 'soldOutBy': null, 'soldOutUntil': null};
  }
  final safeBy = by.length > 64 ? by.substring(0, 64) : by;
  return {
    'isAvailable': false,
    'soldOutAt': now.millisecondsSinceEpoch,
    'soldOutBy': safeBy,
    'soldOutUntil': untilNextReset ? nextSoldOutReset(now).millisecondsSinceEpoch : null,
  };
}

class ProductGroup {
  final String category;
  final List<ProductModel> items;
  const ProductGroup(this.category, this.items);
}

/// Gom món theo danh mục cho màn "Hết món" của bếp, có tìm kiếm và lọc "Đang hết".
List<ProductGroup> groupProductsForSoldOut(
  List<ProductModel> products, {
  String query = '',
  bool onlySoldOut = false,
  DateTime? now,
}) {
  final q = query.trim().toLowerCase();
  final byCat = <String, List<ProductModel>>{};
  for (final p in products) {
    if (onlySoldOut && isProductAvailable(p, now)) continue;
    if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !p.code.toLowerCase().contains(q)) continue;
    final cat = p.category.trim().isEmpty ? 'Khác' : p.category.trim();
    byCat.putIfAbsent(cat, () => []).add(p);
  }
  final cats = byCat.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final c in cats)
      ProductGroup(c, byCat[c]!..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))),
  ];
}

/// Số món đang hết (đã tính soldOutUntil).
int countSoldOut(Iterable<ProductModel> products, [DateTime? now]) =>
    products.where((p) => !isProductAvailable(p, now)).length;

/// Nhãn phụ dưới tên món: "Hết từ 14:05 · bep · tự bật lại 05:00 ngày mai".
String soldOutNote(ProductModel p) {
  if (p.isAvailable) return '';
  final parts = <String>[];
  final at = p.soldOutAt;
  if (at != null) {
    final d = DateTime.fromMillisecondsSinceEpoch(at);
    parts.add('Hết từ ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}');
  }
  if (p.soldOutBy != null && p.soldOutBy!.isNotEmpty) parts.add(p.soldOutBy!);
  if (p.soldOutUntil != null) parts.add('tự bật lại sáng mai');
  return parts.join(' · ');
}
