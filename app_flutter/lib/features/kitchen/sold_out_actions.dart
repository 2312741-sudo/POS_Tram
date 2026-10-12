// lib/features/kitchen/sold_out_actions.dart
// Ghi trạng thái "báo hết món" + nhật ký thao tác (dùng chung cho màn bếp và POS).
import '../../core/domain/product_availability.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

/// Người dùng hiện tại có được bật/tắt món hết hàng không (mã quyền TOGGLE_ITEM_AVAILABILITY).
bool canToggleAvailability([AuthService? auth]) =>
    (auth ?? AuthService()).can(AppPermissions.toggleItemAvailability);

class SoldOutActions {
  SoldOutActions({FirebaseService? fb, AuthService? auth})
      : _fb = fb ?? FirebaseService(),
        _auth = auth ?? AuthService();

  final FirebaseService _fb;
  final AuthService _auth;

  /// Báo hết ([soldOut]=true) hoặc bật lại. Ném lỗi nếu ghi thất bại (nơi gọi hoàn tác giao diện).
  Future<void> setSoldOut(ProductModel p, bool soldOut, {bool untilNextReset = false}) async {
    final user = _auth.currentUser;
    final username = user?.username ?? '';
    final now = DateTime.now();
    await _fb.updateProductAvailability(
      p,
      soldOutPatch(soldOut: soldOut, by: username, now: now, untilNextReset: untilNextReset),
      storeCode: _auth.currentStoreCode,
    );
    await _log(p.name, soldOut ? 'SET_SOLD_OUT' : 'SET_AVAILABLE',
        soldOut ? 'Bếp báo hết ${p.name}' : 'Bật lại ${p.name}', now);
  }

  /// Bật lại nhiều món cùng lúc; trả về số món bật lại thành công.
  Future<int> restoreAll(List<ProductModel> products) async {
    final now = DateTime.now();
    var ok = 0;
    await Future.wait(products.map((p) async {
      try {
        await _fb.updateProductAvailability(
          p,
          soldOutPatch(soldOut: false, by: _auth.currentUser?.username ?? '', now: now),
          storeCode: _auth.currentStoreCode,
        );
        ok++;
      } catch (_) {}
    }));
    if (ok > 0) {
      await _log('', 'SET_AVAILABLE', 'Bật lại tất cả món hết ($ok món)', now);
    }
    return ok;
  }

  /// Dọn cờ hết hàng đã quá hạn (soldOutUntil đã qua). Lỗi bị nuốt: chỉ là dọn dẹp.
  Future<void> clearStale(Iterable<ProductModel> products) async {
    final now = DateTime.now();
    for (final p in products.where((p) => isSoldOutStale(p, now))) {
      try {
        await _fb.updateProductAvailability(
          p,
          soldOutPatch(soldOut: false, by: '', now: now),
          storeCode: _auth.currentStoreCode,
        );
      } catch (_) {}
    }
  }

  Future<void> _log(String productName, String action, String details, DateTime now) {
    final user = _auth.currentUser;
    return _fb.logAction(AuditLogModel(
      action: action,
      username: user?.username ?? '',
      userFullName: user?.fullName ?? '',
      userRole: user?.roleId ?? '',
      targetType: 'PRODUCT',
      targetId: productName,
      timestamp: now.millisecondsSinceEpoch,
      details: details,
      extra: productName.isEmpty ? null : {'productName': productName},
    ));
  }
}
