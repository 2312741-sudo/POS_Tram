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

  DatabaseReference get _root => _getRoot();
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
      // Kiểm tra node gốc /users fallback tương thích
      final rootSnap = await _root.child('users').child(username).get().timeout(const Duration(seconds: 3));
      if (rootSnap.exists && rootSnap.value != null && rootSnap.value is Map) {
        return UserModel.fromMap(rootSnap.value as Map, username);
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
  Stream<List<UserModel>> usersStream() {
    return usersRef.onValue.map<List<UserModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null || event.snapshot.value is! Map) {
        return <UserModel>[];
      }
      final map = event.snapshot.value as Map;
      return map.entries
          .where((e) => e.value is Map)
          .map((e) => UserModel.fromMap(e.value as Map, e.key.toString()))
          .toList();
    }).handleError((_) => <UserModel>[]);
  }

  Future<List<UserModel>> getUsers() async {
    try {
      final snap = await usersRef.get().timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null && snap.value is Map) {
        final map = snap.value as Map;
        return map.entries
            .where((e) => e.value is Map)
            .map((e) => UserModel.fromMap(e.value as Map, e.key.toString()))
            .toList();
      }
      // Fallback node gốc /users tương thích
      final rootSnap = await _root.child('users').get().timeout(const Duration(seconds: 2));
      if (rootSnap.exists && rootSnap.value != null && rootSnap.value is Map) {
        final map = rootSnap.value as Map;
        return map.entries
            .where((e) => e.value is Map)
            .map((e) => UserModel.fromMap(e.value as Map, e.key.toString()))
            .toList();
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

  /// Xóa người dùng theo UID hoặc username
  Future<void> deleteUser(String identifier) async {
    final directSnap = await usersRef.child(identifier).get().timeout(const Duration(seconds: 2));
    if (directSnap.exists) {
      await usersRef.child(identifier).remove();
      return;
    }

    // Nếu identifier là username mà khóa là UID, tìm duyệt qua danh sách để xóa đúng node
    final allSnap = await usersRef.get().timeout(const Duration(seconds: 3));
    if (allSnap.exists && allSnap.value != null && allSnap.value is Map) {
      final map = allSnap.value as Map;
      for (final entry in map.entries) {
        if (entry.value is Map) {
          final uMap = entry.value as Map;
          if (uMap['username']?.toString() == identifier || entry.key.toString() == identifier) {
            await usersRef.child(entry.key.toString()).remove();
            return;
          }
        }
      }
    }
  }
}
