import 'package:firebase_database/firebase_database.dart';
import '../models/app_models.dart';

class AuthRepository {
  final DatabaseReference Function() _getRoot;
  final DatabaseReference Function() _getUsersRef;
  final DatabaseReference Function() _getRolesRef;

  AuthRepository({
    required DatabaseReference Function() getRoot,
    required DatabaseReference Function() getUsersRef,
    required DatabaseReference Function() getRolesRef,
  })  : _getRoot = getRoot,
        _getUsersRef = getUsersRef,
        _getRolesRef = getRolesRef;

  DatabaseReference get root => _getRoot();
  DatabaseReference get usersRef => _getUsersRef();
  DatabaseReference get rolesRef => _getRolesRef();

  // ==================== AUTH ====================
  /// Tra cứu người dùng theo UID hoặc username để nạp hồ sơ sau khi xác thực Firebase Auth
  Future<UserModel?> getUserByUid(String uid) async {
    try {
      final snap = await usersRef.child(uid).get().timeout(const Duration(seconds: 4));
      if (snap.exists && snap.value != null && snap.value is Map) {
        return UserModel.fromMap(snap.value as Map, uid);
      }
    } catch (_) {}
    return null;
  }

  Future<UserModel?> getUserByUsername(String username) async {
    try {
      final allSnap = await usersRef.get().timeout(const Duration(seconds: 4));
      if (allSnap.exists && allSnap.value != null && allSnap.value is Map) {
        final allMap = allSnap.value as Map;
        for (final entry in allMap.entries) {
          if (entry.value is Map) {
            final u = UserModel.fromMap(entry.value as Map, entry.key.toString());
            if (u.username.toLowerCase() == username.toLowerCase()) {
              return u;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Hàm đăng nhập kế thừa (chỉ tra cứu dữ liệu hồ sơ, xác thực chính thức qua Firebase Auth)
  Future<UserModel?> login(String username, String password) async {
    // Không so sánh mật khẩu thô trong DB. Hàm này chuyển sang tìm hồ sơ người dùng.
    return getUserByUsername(username);
  }

  // ==================== ROLES ====================
  Stream<List<RoleModel>> rolesStream() {
    return rolesRef.onValue.map<List<RoleModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <RoleModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
          .map((e) => RoleModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList();
    }).handleError((_) => <RoleModel>[]);
  }

  Future<List<RoleModel>> getRoles() async {
    try {
      final snap = await rolesRef.get().timeout(const Duration(seconds: 2));
      if (!snap.exists || snap.value == null) return [];
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      return map.entries
          .map((e) => RoleModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRole(RoleModel role) async {
    await rolesRef.child(role.id).set(role.toMap());
  }

  Future<void> deleteRole(String roleId) async {
    await rolesRef.child(roleId).remove();
  }

  // ==================== USERS ====================
  /// Khử trùng lặp danh sách người dùng theo tên đăng nhập (lowercase).
  /// Trường hợp RTDB tồn tại đồng thời node theo username (cũ) và node theo Auth UID,
  /// giữ lại bản ghi có Auth UID chuẩn và đầy đủ thông tin nhất.
  static List<UserModel> deduplicateUsers(List<UserModel> list) {
    final Map<String, UserModel> byUsername = {};
    for (final u in list) {
      final uname = u.username.trim().toLowerCase();
      if (uname.isEmpty) {
        byUsername[u.uid.isNotEmpty ? u.uid : 'anon_${u.hashCode}'] = u;
        continue;
      }
      final existing = byUsername[uname];
      if (existing == null) {
        byUsername[uname] = u;
      } else {
        final uHasRealUid = u.uid.isNotEmpty && u.uid.trim().toLowerCase() != uname;
        final exHasRealUid = existing.uid.isNotEmpty && existing.uid.trim().toLowerCase() != uname;
        if (uHasRealUid && !exHasRealUid) {
          byUsername[uname] = u;
        } else if (!exHasRealUid && (u.isRootOwner && !existing.isRootOwner)) {
          byUsername[uname] = u;
        }
      }
    }
    return byUsername.values.toList();
  }

  Stream<List<UserModel>> usersStream() {
    return usersRef.onValue.map<List<UserModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null || event.snapshot.value is! Map) {
        return <UserModel>[];
      }
      final map = event.snapshot.value as Map;
      final rawList = map.entries
          .where((e) => e.value is Map)
          .map((e) => UserModel.fromMap(e.value as Map, e.key.toString()))
          .toList();
      return deduplicateUsers(rawList);
    }).handleError((_) => <UserModel>[]);
  }

  Future<List<UserModel>> getUsers() async {
    try {
      final snap = await usersRef.get().timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null && snap.value is Map) {
        final map = snap.value as Map;
        final rawList = map.entries
            .where((e) => e.value is Map)
            .map((e) => UserModel.fromMap(e.value as Map, e.key.toString()))
            .toList();

        // Tự động dọn dẹp node thừa dạng stores/{code}/users/{username} nếu đã có node stores/{code}/users/{uid}
        for (final entry in map.entries) {
          if (entry.value is Map) {
            final keyStr = entry.key.toString().trim();
            final uMap = entry.value as Map;
            final uname = (uMap['username']?.toString() ?? '').trim().toLowerCase();
            if (uname.isNotEmpty && keyStr.toLowerCase() == uname) {
              // Node này dùng username làm key. Kiểm tra xem có node khác có cùng username mà key là UID không.
              final hasUidNode = map.entries.any((other) =>
                  other.key.toString().trim() != keyStr &&
                  other.value is Map &&
                  ((other.value as Map)['username']?.toString() ?? '').trim().toLowerCase() == uname);
              if (hasUidNode) {
                // Xoá node thừa để không còn 2 tài khoản trùng lặp trong database
                usersRef.child(keyStr).remove().catchError((_) {});
              }
            }
          }
        }

        return deduplicateUsers(rawList);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Lưu người dùng theo khóa UID duy nhất (hoặc username nếu chưa có UID)
  /// Tuyệt đối KHÔNG lưu trữ mật khẩu vào Realtime Database
  Future<void> saveUser(UserModel user) async {
    final key = user.uid.isNotEmpty ? user.uid : user.username;
    await usersRef.child(key).set(user.toMap());
  }

  /// Xóa người dùng theo UID hoặc username (xóa sạch mọi node trùng username)
  Future<void> deleteUser(String identifier) async {
    final cleanId = identifier.trim().toLowerCase();
    final directSnap = await usersRef.child(identifier).get().timeout(const Duration(seconds: 2));
    if (directSnap.exists) {
      await usersRef.child(identifier).remove();
    }

    final allSnap = await usersRef.get().timeout(const Duration(seconds: 3));
    if (allSnap.exists && allSnap.value != null && allSnap.value is Map) {
      final map = allSnap.value as Map;
      for (final entry in map.entries) {
        if (entry.value is Map) {
          final uMap = entry.value as Map;
          final uname = (uMap['username']?.toString() ?? '').trim().toLowerCase();
          final keyStr = entry.key.toString().trim().toLowerCase();
          if (uname == cleanId || keyStr == cleanId) {
            await usersRef.child(entry.key.toString()).remove();
          }
        }
      }
    }
  }
}
