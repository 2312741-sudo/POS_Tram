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
  Future<UserModel?> login(String username, String password) async {
    try {
      final snap = await usersRef.child(username).get().timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        final user = UserModel.fromMap(map);
        if (user.password == password) return user;
      }
      final allSnap = await usersRef.get().timeout(const Duration(seconds: 3));
      if (allSnap.exists && allSnap.value != null) {
        final allMap = Map<dynamic, dynamic>.from(allSnap.value as Map);
        for (final entry in allMap.entries) {
          final u = UserModel.fromMap(Map<dynamic, dynamic>.from(entry.value));
          if (u.username.toLowerCase() == username.toLowerCase() && u.password == password) {
            return u;
          }
        }
      }
      // Check root /users fallback
      final rootSnap = await _root.child('users').child(username).get().timeout(const Duration(seconds: 2));
      if (rootSnap.exists && rootSnap.value != null) {
        final map = Map<dynamic, dynamic>.from(rootSnap.value as Map);
        final user = UserModel.fromMap(map);
        if (user.password == password) return user;
      }
      return null;
    } catch (_) {
      return null;
    }
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
      if (!event.snapshot.exists || event.snapshot.value == null) return <UserModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.values.map((e) => UserModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
    }).handleError((_) => <UserModel>[]);
  }

  Future<List<UserModel>> getUsers() async {
    try {
      final snap = await usersRef.get().timeout(const Duration(seconds: 2));
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        return map.values.map((e) => UserModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
      }
      // Fallback root /users
      final rootSnap = await _root.child('users').get().timeout(const Duration(seconds: 2));
      if (rootSnap.exists && rootSnap.value != null) {
        final map = Map<dynamic, dynamic>.from(rootSnap.value as Map);
        return map.values.map((e) => UserModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveUser(UserModel user) async {
    await usersRef.child(user.username).set(user.toMap());
  }

  Future<void> deleteUser(String username) async {
    await usersRef.child(username).remove();
  }
}
