import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/product_model.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';

// Dữ liệu thật TRẠM CHANH: món tạo từ web không có id số (id = 0) nên mọi dòng của chúng mang productId 0.
ProductModel _p(int id, String name, String category, {String? key, String code = ''}) =>
    ProductModel(id: id, name: name, price: 20000, category: category, unit: 'ly', code: code, dbKey: key);

void main() {
  final products = [
    _p(0, 'Bánh gấu', 'SNACK', key: '-P3oQPJ8TeyxJoLJ4d1h'),
    _p(0, 'Trà olong - Tắc', 'TRÀ TRÁI CÂY', key: '-P3oRQhglBsZh6YHCTy8', code: 'DR202600193'),
    _p(1, 'Trà Olong - Chanh tươi', 'TRÀ TRÁI CÂY'),
  ];
  OrderItemModel line(int id, String name) => OrderItemModel(productId: id, name: name, price: 20000);

  test('productId 0 tra theo tên, không lấy nhầm món id 0 khác', () {
    final tac = CartCampaignPricing.resolveProduct(line(0, 'Trà olong - Tắc'), products);
    expect(tac?.category, 'TRÀ TRÁI CÂY');
    expect(tac?.dbKey, '-P3oRQhglBsZh6YHCTy8');
    final banh = CartCampaignPricing.resolveProduct(line(0, 'Bánh gấu'), products);
    expect(banh?.category, 'SNACK');
  });

  test('lines(): dòng Trà tắc có đúng nhóm / mã / khóa để khớp combo', () {
    final l = CartCampaignPricing.lines([line(0, 'Trà olong - Tắc')], products).first;
    expect(l.groupId, 'TRÀ TRÁI CÂY');
    expect(l.itemCode, 'DR202600193');
    expect(l.dbKey, '-P3oRQhglBsZh6YHCTy8');
  });

  test('id hợp lệ khớp tên; id trùng tên khác thì ưu tiên tên', () {
    expect(CartCampaignPricing.resolveProduct(line(1, 'Trà Olong - Chanh tươi'), products)?.name, 'Trà Olong - Chanh tươi');
    expect(CartCampaignPricing.resolveProduct(line(1, 'Bánh gấu'), products)?.name, 'Bánh gấu');
    expect(CartCampaignPricing.resolveProduct(line(0, 'Món lạ'), products), isNull);
  });
}
