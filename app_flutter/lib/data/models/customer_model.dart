// ==================== KIOTVIET CUSTOMER LOYALTY MODEL ====================
class KmtCustomerModel {
  final String id;
  final String code; // Mã khách hàng KiotViet (KH000001...)
  final String name;
  final String phone;
  final String gender;
  final String birthday;
  int currentPoints; // Điểm tích lũy hiện tại
  int totalPoints;   // Tổng điểm lịch sử
  final int? createdAt;

  KmtCustomerModel({
    required this.id,
    this.code = '',
    String? name,
    String? fullName,
    required this.phone,
    this.gender = 'Khác',
    this.birthday = '',
    this.currentPoints = 0,
    this.totalPoints = 0,
    this.createdAt,
  }) : name = fullName ?? name ?? '';

  String get fullName => name;
  String get groupName => currentPoints >= 500 ? 'VIP' : (currentPoints >= 100 ? 'Thân thiết' : 'Thành viên');

  factory KmtCustomerModel.fromMap(Map<dynamic, dynamic> map, String id) {
    return KmtCustomerModel(
      id: id,
      code: map['code']?.toString() ?? map['maKhachHang']?.toString() ?? '',
      name: map['name']?.toString() ?? map['tenKhachHang']?.toString() ?? '',
      phone: map['phone']?.toString() ?? map['dienThoai']?.toString() ?? '',
      gender: map['gender']?.toString() ?? map['gioiTinh']?.toString() ?? 'Khác',
      birthday: map['birthday']?.toString() ?? map['ngaySinh']?.toString() ?? '',
      currentPoints: (map['currentPoints'] as num?)?.toInt() ?? (map['diemHienTai'] as num?)?.toInt() ?? 0,
      totalPoints: (map['totalPoints'] as num?)?.toInt() ?? (map['tongDiem'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'phone': phone,
    'gender': gender,
    'birthday': birthday,
    'currentPoints': currentPoints,
    'totalPoints': totalPoints,
  };

  /// Hạng thành viên KiotViet dựa trên tổng điểm tích lũy
  String get memberTier {
    if (totalPoints >= 1000) return 'Kim Cương';
    if (totalPoints >= 500) return 'Vàng';
    if (totalPoints >= 200) return 'Bạc';
    return 'Thành Viên';
  }
}
