// lib/core/domain/zone_plan.dart
//
// Thiết lập khu vực bàn — LOGIC THUẦN (không đụng Firebase).
// Bản TypeScript song song: web/lib/zones.ts (giữ hai bản cùng quy tắc và cùng hình dạng RTDB).
//
// Đường dẫn trong [ZonePlan.updates] TƯƠNG ĐỐI với node stores/{chi nhánh}:
//   'zones/{khu}' và 'tables/{khu}_{tên bàn}'  (giá trị null = xóa).
// Tầng repository ghi chúng bằng MỘT update đa đường dẫn kèm một bản ghi nhật ký.

import 'dart:math' as math;

/// Một bàn thô đọc từ RTDB: khóa node + toàn bộ giá trị (giữ nguyên mọi trường khi đổi khu).
class ZoneTableRecord {
  final String key;
  final Map<String, dynamic> value;
  const ZoneTableRecord(this.key, this.value);
}

/// Người thực hiện thao tác (ghi vào nhật ký).
class ZoneAuditActor {
  final String username;
  final String fullName;
  final String role;
  const ZoneAuditActor({required this.username, this.fullName = '', this.role = ''});
}

/// Kết quả lập kế hoạch: lỗi (nếu có) hoặc các đường dẫn cần ghi.
class ZonePlan {
  final String? error;
  final Map<String, dynamic> updates;
  final int affected;
  const ZonePlan._(this.error, this.updates, this.affected);
  factory ZonePlan.fail(String message) => ZonePlan._(message, const {}, 0);
  factory ZonePlan.ok(Map<String, dynamic> updates, {int affected = 0}) => ZonePlan._(null, updates, affected);
  bool get isOk => error == null;
}

final RegExp _forbiddenKeyChars = RegExp(r'[.#$/\[\]]');

/// Tên khu: không rỗng, ≤ 40 ký tự, không ký tự cấm của khóa RTDB, không trùng (không phân biệt hoa thường)
String? validateZoneName(String name, List<String> existing) {
  final n = name.trim();
  if (n.isEmpty) return 'Vui lòng nhập tên khu vực';
  if (n.length > 40) return 'Tên khu vực tối đa 40 ký tự';
  if (_forbiddenKeyChars.hasMatch(n)) return 'Tên khu vực không được chứa các ký tự . # \$ / [ ]';
  if (existing.any((z) => z.trim().toLowerCase() == n.toLowerCase())) return 'Khu "$n" đã tồn tại';
  return null;
}

/// Tiền tố tên bàn: thành một phần khóa node nên không được chứa ký tự cấm
String? validateTablePrefix(String prefix) {
  final p = prefix.trim();
  if (p.length > 20) return 'Tiền tố tên bàn tối đa 20 ký tự';
  if (_forbiddenKeyChars.hasMatch(p)) return 'Tiền tố tên bàn không được chứa các ký tự . # \$ / [ ]';
  return null;
}

/// Số bàn tạo nhanh: số nguyên trong khoảng [min, 100]
String? validateTableCount(int count, {int min = 0}) {
  if (count < min || count > 100) return 'Số bàn tạo nhanh từ $min đến 100';
  return null;
}

/// Tên bàn tuần tự "Bàn 01".."Bàn 12" (rộng tối thiểu 2 chữ số), bỏ qua tên đã có trong khu
List<String> nextTableNames(String prefix, int count, List<String> taken) {
  final takenLower = taken.map((n) => n.trim().toLowerCase()).toSet();
  final width = math.max(2, (count + taken.length).toString().length);
  final base = prefix.trim().isEmpty ? 'Bàn' : prefix.trim();
  final out = <String>[];
  for (var i = 1; out.length < count && i < 10000; i++) {
    final name = '$base ${i.toString().padLeft(width, '0')}';
    if (!takenLower.contains(name.toLowerCase())) out.add(name);
  }
  return out;
}

/// Bàn đang "bận": đang dùng, hoặc còn giỏ món (không rỗng)
bool isTableInUse(Map<String, dynamic> value) {
  if (value['inUse'] == true) return true;
  final o = value['currentOrderJson'];
  return o is String && o.isNotEmpty;
}

String _zoneOf(ZoneTableRecord t) => (t.value['zone'] ?? '').toString();
String _nameOf(ZoneTableRecord t) => (t.value['name'] ?? t.key).toString();
List<ZoneTableRecord> _tablesOfZone(List<ZoneTableRecord> tables, String zone) =>
    tables.where((t) => _zoneOf(t) == zone).toList();

/// Thêm khu mới kèm N bàn
ZonePlan planZoneCreate({
  required String zoneName,
  required String prefix,
  required int count,
  required List<String> declaredZones,
  required List<ZoneTableRecord> tables,
}) {
  final zone = zoneName.trim();
  final err = validateZoneName(zone, declaredZones) ?? validateTablePrefix(prefix) ?? validateTableCount(count);
  if (err != null) return ZonePlan.fail(err);
  final names = nextTableNames(prefix, count, const []);
  final keys = tables.map((t) => t.key).toSet();
  if (names.any((n) => keys.contains('${zone}_$n'))) {
    return ZonePlan.fail('Đã có bàn trùng khóa trong khu "$zone" — hãy đổi tên khu hoặc tiền tố');
  }
  final updates = <String, dynamic>{'zones/$zone': {'name': zone}};
  for (final n in names) {
    updates['tables/${zone}_$n'] = {'name': n, 'zone': zone, 'inUse': false, 'currentOrderJson': ''};
  }
  return ZonePlan.ok(updates, affected: names.length);
}

/// Thêm N bàn vào khu đã có. Tên bàn tiếp nối, không trùng bàn đang có trong khu.
ZonePlan planAddTables({
  required String zoneName,
  required String prefix,
  required int count,
  required List<String> declaredZones,
  required List<ZoneTableRecord> tables,
}) {
  final zone = zoneName.trim();
  if (!declaredZones.contains(zone) && _tablesOfZone(tables, zone).isEmpty) {
    return ZonePlan.fail('Khu "$zone" không tồn tại');
  }
  final err = validateTablePrefix(prefix) ?? validateTableCount(count, min: 1);
  if (err != null) return ZonePlan.fail(err);
  final taken = _tablesOfZone(tables, zone).map(_nameOf).toList();
  final names = nextTableNames(prefix, count, taken);
  final keys = tables.map((t) => t.key).toSet();
  final updates = <String, dynamic>{'zones/$zone/name': zone};
  for (final n in names) {
    final key = '${zone}_$n';
    if (keys.contains(key)) return ZonePlan.fail('Bàn "$n" đã tồn tại trong khu "$zone"');
    updates['tables/$key'] = {'name': n, 'zone': zone, 'inUse': false, 'currentOrderJson': ''};
  }
  return ZonePlan.ok(updates, affected: names.length);
}

/// Đổi tên khu: chuyển khu node + mọi bàn thuộc khu sang khóa mới (khu_tên) trong MỘT update.
/// Từ chối khi tên mới trùng khu khác, khóa bàn đích bị chiếm, hoặc có bàn đang dùng / còn giỏ món.
ZonePlan planZoneRename({
  required String oldName,
  required String newName,
  required List<String> declaredZones,
  required List<ZoneTableRecord> tables,
}) {
  final oldZ = oldName.trim();
  final newZ = newName.trim();
  if (newZ == oldZ) return ZonePlan.fail('Tên khu không thay đổi');
  final err = validateZoneName(newZ, declaredZones.where((z) => z.trim() != oldZ).toList());
  if (err != null) return ZonePlan.fail(err);

  final movers = _tablesOfZone(tables, oldZ);
  final busy = movers.where((t) => isTableInUse(t.value)).length;
  if (busy > 0) {
    return ZonePlan.fail('Khu "$oldZ" còn $busy bàn đang dùng hoặc còn món — hãy dọn bàn trước khi đổi tên');
  }

  final keys = tables.map((t) => t.key).toSet();
  final updates = <String, dynamic>{
    'zones/$oldZ': null,
    'zones/$newZ': {'name': newZ},
  };
  for (final t in movers) {
    final name = _nameOf(t);
    final newKey = '${newZ}_$name';
    // Khóa đích đã có bàn khác thì từ chối; giữ nguyên khóa của chính nó thì được
    if (keys.contains(newKey) && newKey != t.key) {
      return ZonePlan.fail('Bàn "$name" đã tồn tại trong khu "$newZ"');
    }
    updates['tables/${t.key}'] = null;
    updates['tables/$newKey'] = {...t.value, 'zone': newZ};
  }
  return ZonePlan.ok(updates, affected: movers.length);
}

/// Xóa khu: chỉ khi không còn bàn nào thuộc khu (tránh làm mất bàn / đơn đang mở)
ZonePlan planZoneDelete({required String zoneName, required List<ZoneTableRecord> tables}) {
  final zone = zoneName.trim();
  final n = _tablesOfZone(tables, zone).length;
  if (n > 0) return ZonePlan.fail('Khu "$zone" còn $n bàn — hãy chuyển hoặc xóa các bàn trước');
  return ZonePlan.ok({'zones/$zone': null});
}

/// Nội dung một bản ghi nhật ký thao tác khu/bàn (khớp rules audit_logs: khóa mới, có timestamp)
Map<String, dynamic> zoneAuditEntry({
  required String action,
  required String targetType,
  required String targetId,
  required String details,
  required ZoneAuditActor actor,
  required String storeCode,
  required int now,
}) =>
    {
      'timestamp': now,
      'username': actor.username,
      'userFullName': actor.fullName.isEmpty ? actor.username : actor.fullName,
      'userRole': actor.role,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'storeCode': storeCode,
      'details': details,
    };
