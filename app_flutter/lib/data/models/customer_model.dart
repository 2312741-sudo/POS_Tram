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
    // Parse createdAt timestamp or int
    int? createdTimestamp;
    final rawCreated = map['ngay_tao'] ?? map['ngayTao'] ?? map['createdAt'];
    if (rawCreated != null) {
      if (rawCreated is int) {
        createdTimestamp = rawCreated;
      } else if (rawCreated is num) {
        createdTimestamp = rawCreated.toInt();
      } else {
        try {
          createdTimestamp = DateTime.parse(rawCreated.toString()).millisecondsSinceEpoch;
        } catch (_) {}
      }
    }

    return KmtCustomerModel(
      id: id,
      code: map['ma_khach_hang']?.toString() ??
          map['maKhachHang']?.toString() ??
          map['code']?.toString() ??
          id,
      name: map['ho_ten']?.toString() ??
          map['hoTen']?.toString() ??
          map['name']?.toString() ??
          map['tenKhachHang']?.toString() ??
          '',
      phone: map['so_dien_thoai']?.toString() ??
          map['soDienThoai']?.toString() ??
          map['phone']?.toString() ??
          map['dienThoai']?.toString() ??
          '',
      gender: map['gioi_tinh']?.toString() ??
          map['gioiTinh']?.toString() ??
          map['gender']?.toString() ??
          'Khác',
      birthday: map['ngay_sinh']?.toString() ??
          map['ngaySinh']?.toString() ??
          map['birthday']?.toString() ??
          '',
      currentPoints: (map['diem_hien_tai'] as num?)?.toInt() ??
          (map['diemHienTai'] as num?)?.toInt() ??
          (map['currentPoints'] as num?)?.toInt() ??
          0,
      totalPoints: (map['tongDiem'] as num?)?.toInt() ??
          (map['totalPoints'] as num?)?.toInt() ??
          (map['diem_hien_tai'] as num?)?.toInt() ??
          (map['currentPoints'] as num?)?.toInt() ??
          0,
      createdAt: createdTimestamp,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'ma_khach_hang': code.isNotEmpty ? code : id,
    'code': code.isNotEmpty ? code : id,
    'ho_ten': name,
    'name': name,
    'so_dien_thoai': phone,
    'phone': phone,
    'gioi_tinh': gender,
    'gender': gender,
    'ngay_sinh': birthday,
    'birthday': birthday,
    'diem_hien_tai': currentPoints,
    'currentPoints': currentPoints,
    'totalPoints': totalPoints,
    'ho_ten_upper': name.toUpperCase(),
    'ngay_cap_nhat': DateTime.now().millisecondsSinceEpoch,
  };

  /// Hạng thành viên KiotViet dựa trên tổng điểm tích lũy
  String get memberTier {
    if (totalPoints >= 1000) return 'Kim Cương';
    if (totalPoints >= 500) return 'Vàng';
    if (totalPoints >= 200) return 'Bạc';
    return 'Thành Viên';
  }
}
