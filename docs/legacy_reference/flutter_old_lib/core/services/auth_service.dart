// lib/core/services/auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _keyUsername = 'USERNAME';
  static const String _keyRole = 'USER_ROLE';
  static const String _keyFullName = 'FULL_NAME';

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isManager => _currentUser?.isManager ?? false;
  bool get isStaff => _currentUser?.isStaff ?? false;
  bool get isKitchen => _currentUser?.isKitchen ?? false;

  Future<bool> checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_keyUsername);
    final role = prefs.getString(_keyRole);
    final fullName = prefs.getString(_keyFullName);
    if (username != null && role != null) {
      _currentUser = UserModel(
        username: username,
        password: '',
        fullName: fullName ?? username,
        role: role,
      );
      return true;
    }
    return false;
  }

  Future<UserModel?> login(String username, String password) async {
    final user = await FirebaseService().login(username, password);
    if (user != null) {
      _currentUser = user;
      await _saveSession(user);
      // Log audit
      await FirebaseService().logAction(AuditLogModel(
        action: 'LOGIN',
        username: user.username,
        userRole: user.role,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: 'Đăng nhập thành công',
      ));
    }
    return user;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser != null) {
      await FirebaseService().logAction(AuditLogModel(
        action: 'LOGOUT',
        username: _currentUser!.username,
        userRole: _currentUser!.role,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: 'Đăng xuất',
      ));
    }
    await prefs.clear();
    _currentUser = null;
  }

  Future<void> _saveSession(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, user.username);
    await prefs.setString(_keyRole, user.role);
    await prefs.setString(_keyFullName, user.fullName);
  }
}

// lib/core/services/audit_service.dart
class AuditService {
  static final AuditService _instance = AuditService._internal();
  factory AuditService() => _instance;
  AuditService._internal();

  final _fb = FirebaseService();

  Future<void> log({
    required String action,
    required String username,
    required String userRole,
    required String details,
    String? targetId,
  }) async {
    await _fb.logAction(AuditLogModel(
      action: action,
      username: username,
      userRole: userRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      details: details,
      targetId: targetId,
    ));
  }
}
