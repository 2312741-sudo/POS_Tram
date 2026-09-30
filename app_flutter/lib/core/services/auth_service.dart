// lib/core/services/auth_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../core/permissions/app_permissions.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _keyStoreCode = 'STORE_CODE';
  static const String _keyUsername = 'USERNAME';
  static const String _keyRole = 'USER_ROLE';
  static const String _keyFullName = 'FULL_NAME';

  final _fb = FirebaseService();

  String _currentStoreCode = 'TRAM01';
  String get currentStoreCode => _currentStoreCode;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  List<RoleModel> _cachedRoles = [];
  List<RoleModel> get cachedRoles => _cachedRoles;

  StoreInfoModel? _currentStoreInfo;
  StoreInfoModel? get currentStoreInfo => _currentStoreInfo;

  bool get isLoggedIn => _currentUser != null;
  bool get isRootOwner => _currentUser?.isRootOwner ?? false;
  bool get isKitchen => _currentUser?.roleId == 'ROLE_KITCHEN' || _currentUser?.roleId == 'daubep';
  UserRole get currentRole => _currentUser?.role ?? UserRole.employee;
  bool get isOwner => isRootOwner || currentRole.isOwner;
  bool get isManager => currentRole.isManager;
  bool get canAccessManagerHub => isOwner || isManager || can(AppPermissions.viewReports);

  /// Kiểm tra xem người dùng hiện tại có được cấp quyền cụ thể hay không
  bool can(String permissionKey) {
    if (_currentUser == null) return false;
    return _currentUser!.can(permissionKey, _cachedRoles);
  }

  Future<void> switchStore(String newStoreCode) async {
    _currentStoreCode = newStoreCode.trim().toUpperCase();
    _fb.switchStore(_currentStoreCode);
    _currentStoreInfo = StoreInfoModel(
      storeCode: _currentStoreCode,
      storeName: _currentStoreCode == 'TRAM02'
          ? 'POS Trạm - Chi nhánh 02 (Sài Gòn)'
          : (_currentStoreCode == 'TRAM01' ? 'POS Trạm - Trụ sở 01 (Đà Lạt)' : 'POS Trạm - Chi nhánh $_currentStoreCode'),
    );
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStoreCode, _currentStoreCode);
    await refreshRolesAndStoreInfo();
    notifyListeners();
  }

  Future<void> refreshRolesAndStoreInfo() async {
    try {
      _cachedRoles = await _fb.getRoles().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      _currentStoreInfo = await _fb.getStoreInfo().timeout(const Duration(seconds: 3));
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final storeCode = prefs.getString(_keyStoreCode);
    final username = prefs.getString(_keyUsername);
    final role = prefs.getString(_keyRole);
    final fullName = prefs.getString(_keyFullName);

    if (storeCode != null && storeCode.isNotEmpty && username != null && username.isNotEmpty) {
      _currentStoreCode = storeCode;
      _fb.switchStore(storeCode);

      final isOwner = role == 'ROLE_OWNER' || role == 'OWNER';
      _currentUser = UserModel(
        username: username,
        fullName: fullName ?? username,
        password: '',
        roleId: role ?? 'ROLE_STAFF',
        isRootOwner: isOwner,
      );

      // Refresh in background without blocking
      refreshRolesAndStoreInfo();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<UserModel?> login({
    required String storeCode,
    required String username,
    required String password,
  }) async {
    final cleanStore = storeCode.trim().toUpperCase();
    final cleanUser = username.trim();
    _currentStoreCode = cleanStore;
    _fb.switchStore(cleanStore);

    UserModel? loggedUser;

    // 1. Try Firebase online login with strict 3-second timeout
    try {
      loggedUser = await _fb.login(cleanUser, password).timeout(const Duration(seconds: 3));
    } catch (_) {
      loggedUser = null;
    }

    // 2. If online is slow or offline, provide instant fallback authentication
    if (loggedUser == null) {
      if ((cleanUser == 'admin' && password == 'admin') ||
          (cleanUser == 'thungan' && password == '123') ||
          (cleanUser == 'phucvu' && password == '123') ||
          (cleanUser == 'daubep' && password == '123') ||
          (cleanUser == 'ti' && password == '123') ||
          (cleanUser == 'ta' && password == '123') ||
          (cleanUser == 'v' && password == '123')) {
        final isAdm = cleanUser == 'admin' || cleanUser == 'ti';
        final isKit = cleanUser == 'daubep' || cleanUser == 'v';
        final rId = isAdm ? 'ROLE_OWNER' : (isKit ? 'ROLE_KITCHEN' : 'ROLE_CASHIER');

        String fName = cleanUser;
        if (cleanUser == 'admin') fName = 'Chủ Quán (Admin)';
        if (cleanUser == 'thungan') fName = 'Nguyễn Thu Ngân';
        if (cleanUser == 'ti') fName = 'Đức Tín (Manager)';
        if (cleanUser == 'ta') fName = 'Thanh Tâm (Staff)';
        if (cleanUser == 'v') fName = 'Công Vinh (Bếp)';

        loggedUser = UserModel(
          username: cleanUser,
          fullName: fName,
          password: password,
          roleId: rId,
          isRootOwner: isAdm,
          customPermissions: cleanUser == 'thungan' ? [AppPermissions.mergeSplitTable] : [],
        );
      }
    }

    if (loggedUser != null) {
      if (!loggedUser.isActive) {
        throw Exception('Tài khoản đã bị tạm khóa bởi chủ quán!');
      }

      _currentUser = loggedUser;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyStoreCode, cleanStore);
      await prefs.setString(_keyUsername, loggedUser.username);
      await prefs.setString(_keyRole, loggedUser.roleId);
      await prefs.setString(_keyFullName, loggedUser.fullName);

      // Async background sync (fire-and-forget, does not block UI)
      _fb.logAction(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: loggedUser.username,
        userFullName: loggedUser.fullName,
        userRole: loggedUser.roleId,
        action: 'LOGIN',
        targetType: 'AUTH',
        targetId: loggedUser.username,
        details: 'Đăng nhập thành công vào cửa hàng $cleanStore',
      )).catchError((_) {});

      refreshRolesAndStoreInfo();
      notifyListeners();
      return loggedUser;
    }

    return null;
  }

  Future<void> logout() async {
    if (_currentUser != null) {
      _fb.logAction(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: _currentUser!.username,
        userFullName: _currentUser!.fullName,
        userRole: _currentUser!.roleId,
        action: 'LOGOUT',
        targetType: 'AUTH',
        targetId: _currentUser!.username,
        details: 'Đăng xuất khỏi ca làm việc',
      )).catchError((_) {});
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyFullName);
    _currentUser = null;
    notifyListeners();
  }
}
