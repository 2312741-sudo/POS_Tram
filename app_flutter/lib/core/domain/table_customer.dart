// Khách tích điểm gắn với bàn: phục hồi từ node bàn khi vào lại màn hình order.
import '../../data/models/customer_model.dart';
import '../../data/models/table_model.dart';

class TableCustomerLogic {
  /// Dựng khách từ các trường lưu trên bàn (tên/SĐT hiển thị ngay, điểm chưa biết = 0
  /// cho tới khi tra lại số dư dùng chung). Null nếu bàn chưa gắn khách. Bàn đang TRỐNG mà
  /// còn sót khách (chọn khách rồi thoát khi chưa gọi món) → bỏ khách sót đó.
  static KmtCustomerModel? restore(TableModel t) {
    if (!t.inUse) {
      t.clearCustomer();
      return null;
    }
    if (!t.hasCustomer) return null;
    return KmtCustomerModel(
      id: t.customerId!,
      fullName: t.customerName ?? '',
      phone: t.customerPhone ?? '',
    );
  }

  /// Áp số dư dùng chung vừa tra được lên khách đã phục hồi. Trả false nếu không tra được
  /// (giữ tên/SĐT đã lưu, điểm coi là chưa biết).
  static bool applyMember(KmtCustomerModel c, {required bool found, int points = 0, int totalPoints = 0, String name = '', String phone = ''}) {
    if (!found) return false;
    c.currentPoints = points;
    if (totalPoints > c.totalPoints) c.totalPoints = totalPoints;
    return true;
  }

  /// Ghi khách (hoặc xóa khi null) lên bàn.
  static void writeToTable(TableModel t, KmtCustomerModel? c) {
    if (c == null) {
      t.clearCustomer();
    } else {
      t.setCustomer(id: c.id, name: c.fullName, phone: c.phone);
    }
  }
}
