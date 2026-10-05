// lib/core/services/auth_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../core/permissions/app_permissions.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _keyStoreCode = 'STORE_CODE';
  static const String _keyRememberStore = 'REMEMBER_STORE';
  static const String _keyUsername = 'USERNAME';
  static const String _keyRole = 'USER_ROLE';
  static const String _keyFullName = 'FULL_NAME';
  static const String _keyUid = 'UID';

  static const int maxFailedAttempts = 5;
  static const int lockoutDurationMs = 15 * 60 * 1000; // 15 phút

  final _fb = FirebaseService();
  FirebaseAuth? _authMock;
  FirebaseAuth get _firebaseAuth => _authMock ?? FirebaseAuth.instance;

  @visibleForTesting
  void setAuthMock(FirebaseAuth? mock) {
    _authMock = mock;
  }

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
  bool get mustChangePassword => _currentUser?.mustChangePassword ?? false;

  /// Kiểm tra người dùng hiện tại có quyền permKey
  bool can(String permissionKey) {
    if (_currentUser == null) return false;
    return _currentUser!.can(permissionKey, _cachedRoles);
  }

  /// Kiểm tra trạng thái khóa tạm thời
  static bool isLockoutActive(int? lockedUntil, int currentTimeMs) {
    if (lockedUntil == null) return false;
    return lockedUntil > currentTimeMs;
  }

  /// Tính số giây khóa tạm còn lại
  static int calculateRemainingLockoutSeconds(int? lockedUntil, int currentTimeMs) {
    if (lockedUntil == null || lockedUntil <= currentTimeMs) return 0;
    return ((lockedUntil - currentTimeMs) / 1000).ceil();
  }

  /// Lấy mã cửa hàng đã ghi nhớ từ bộ nhớ đệm
  Future<String?> getSavedStoreCode() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_keyRememberStore) ?? true;
    if (remember) {
      return prefs.getString(_keyStoreCode);
    }
    return null;
  }

  /// Lấy trạng thái cờ ghi nhớ mã cửa hàng
  Future<bool> getRememberStoreOption() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRememberStore) ?? true;
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

  /// Kiểm tra phiên đăng nhập tự động
  Future<bool> checkAutoLogin() async {
    try {
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser == null) return false;

      final prefs = await SharedPreferences.getInstance();
      final storeCode = prefs.getString(_keyStoreCode);
      if (storeCode == null || storeCode.isEmpty) return false;

      _currentStoreCode = storeCode.trim().toUpperCase();
      _fb.switchStore(_currentStoreCode);

      // Nạp hồ sơ từ Firebase Realtime Database
      final snap = await _fb.storeRef.child('users').child(fbUser.uid).get().timeout(const Duration(seconds: 5));
      if (snap.exists && snap.value != null && snap.value is Map) {
        final user = UserModel.fromMap(snap.value as Map, fbUser.uid);
        if (!user.isActive) {
          await _firebaseAuth.signOut();
          return false;
        }
        _currentUser = user;
        refreshRolesAndStoreInfo();
        notifyListeners();
        return true;
      }
    } catch (_) {
      // Khi lỗi mạng hoặc không nạp được hồ sơ, không tự động đăng nhập bừa bãi
    }
    return false;
  }

  /// Kiểm tra thời gian khóa tạm còn lại (tính bằng giây)
  Future<int?> getLockoutRemainingSeconds(String storeCode, String username) async {
    try {
      final snap = await _fb.storeRef
          .child('login_attempts')
          .child(username)
          .get()
          .timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null && snap.value is Map) {
        final map = snap.value as Map;
        final lockedUntil = (map['lockedUntil'] as num?)?.toInt() ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (isLockoutActive(lockedUntil, now)) {
          return calculateRemainingLockoutSeconds(lockedUntil, now);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Ghi nhận 1 lần đăng nhập thất bại
  Future<void> _recordFailedAttempt(String storeCode, String username) async {
    try {
      final ref = _fb.storeRef.child('login_attempts').child(username);
      final snap = await ref.get().timeout(const Duration(seconds: 3));
      int failedCount = 0;
      if (snap.exists && snap.value != null && snap.value is Map) {
        final map = snap.value as Map;
        failedCount = (map['failedCount'] as num?)?.toInt() ?? 0;
      }
      failedCount += 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      int lockedUntil = 0;

      if (failedCount >= maxFailedAttempts) {
        lockedUntil = now + lockoutDurationMs;
        _fb.logAction(AuditLogModel(
          timestamp: now,
          username: username,
          userFullName: username,
          userRole: 'UNKNOWN',
          action: 'LOGIN_ATTEMPT_LOCKED_OUT',
          targetType: 'AUTH',
          targetId: username,
          details: 'Tài khoản @$username bị khóa tạm 15 phút do nhập sai mật khẩu $failedCount lần liên tiếp',
        )).catchError((_) {});
      }

      await ref.set({
        'failedCount': failedCount,
        'lastFailedAt': now,
        'lockedUntil': lockedUntil,
      });
    } catch (_) {}
  }

  /// Xóa bộ đếm đăng nhập sai khi thành công
  Future<void> _resetLoginAttempts(String storeCode, String username) async {
    try {
      await _fb.storeRef.child('login_attempts').child(username).remove();
    } catch (_) {}
  }

  /// Đăng nhập tài khoản qua Firebase Authentication
  /// Tuân thủ hợp đồng: {username}.{storeCode}@tram.local
  /// Tuyệt đối KHÔNG có tài khoản fallback/cứng trong mã nguồn.
  Future<UserModel> login({
    required String storeCode,
    required String username,
    required String password,
    bool rememberStore = true,
  }) async {
    final cleanStore = storeCode.trim().toUpperCase();
    final cleanUser = AuthUtils.normalizeUsername(username);

    // 1. Kiểm tra validation cơ bản
    if (cleanStore.isEmpty) {
      throw const AuthException('Vui lòng nhập Mã Cửa Hàng.');
    }
    if (!AuthUtils.isValidUsername(cleanUser)) {
      throw const AuthException(
        'Tên đăng nhập không hợp lệ. Chỉ chấp nhận chữ thường không dấu (a-z), số (0-9), gạch dưới (_) hoặc gạch ngang (-), từ 3 đến 30 ký tự.',
      );
    }
    if (password.trim().isEmpty) {
      throw const AuthException('Vui lòng nhập Mật Khẩu.');
    }

    _currentStoreCode = cleanStore;
    _fb.switchStore(cleanStore);

    // 2. Kiểm tra khóa tạm thời do sai mật khẩu 5 lần liên tiếp
    final lockoutRemaining = await getLockoutRemainingSeconds(cleanStore, cleanUser);
    if (lockoutRemaining != null && lockoutRemaining > 0) {
      final minutes = (lockoutRemaining / 60).ceil();
      throw AuthException(
        'Tài khoản đã bị khóa tạm thời $minutes phút do nhập sai mật khẩu 5 lần liên tiếp. Vui lòng thử lại sau hoặc liên hệ Quản lý.',
      );
    }

    // 3. Chuẩn hóa Email Firebase Auth
    final email = AuthUtils.buildAuthEmail(cleanUser, cleanStore);

    // 4. Xác thực với Firebase Authentication
    UserCredential credential;
    try {
      credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 10));
    } on FirebaseAuthException catch (e) {
      await _recordFailedAttempt(cleanStore, cleanUser);
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential' || e.code == 'invalid-login-credentials') {
        throw const AuthException('Sai tài khoản hoặc mật khẩu.');
      } else if (e.code == 'network-request-failed') {
        throw const AuthException('Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng Internet và thử lại.');
      } else if (e.code == 'too-many-requests') {
        throw const AuthException('Quá nhiều yêu cầu không thành công. Hệ thống đang tạm hạn chế, vui lòng thử lại sau ít phút.');
      } else {
        throw AuthException('Đăng nhập thất bại: ${e.message ?? e.code}');
      }
    } on TimeoutException {
      throw const AuthException('Kết nối đến máy chủ quá chậm hoặc gián đoạn. Vui lòng kiểm tra đường truyền và thử lại.');
    } catch (e) {
      if (e is AuthException) rethrow;
      await _recordFailedAttempt(cleanStore, cleanUser);
      throw AuthException('Đăng nhập thất bại: ${e.toString()}');
    }

    final uid = credential.user?.uid;
    if (uid == null || uid.isEmpty) {
      throw const AuthException('Không lấy được mã định danh người dùng từ hệ thống xác thực.');
    }

    // 5. Nạp hồ sơ người dùng từ Realtime Database tại stores/{storeCode}/users/{uid}
    UserModel? userProfile;
    try {
      final snap = await _fb.storeRef.child('users').child(uid).get().timeout(const Duration(seconds: 6));
      if (snap.exists && snap.value != null && snap.value is Map) {
        userProfile = UserModel.fromMap(snap.value as Map, uid);
      } else {
        // Fallback kiểm tra node legacy stores/{storeCode}/users/{username}
        final legacySnap = await _fb.storeRef.child('users').child(cleanUser).get().timeout(const Duration(seconds: 4));
        if (legacySnap.exists && legacySnap.value != null && legacySnap.value is Map) {
          userProfile = UserModel.fromMap(legacySnap.value as Map, uid);
          // Tự động nâng cấp ghi hồ sơ sang key UID
          await _fb.storeRef.child('users').child(uid).set(userProfile.copyWith(uid: uid).toMap()).catchError((_) {});
        }
      }
    } on TimeoutException {
      await _firebaseAuth.signOut();
      throw const AuthException('Tải hồ sơ người dùng quá thời gian cho phép. Vui lòng thử lại.');
    } catch (e) {
      await _firebaseAuth.signOut();
      throw AuthException('Không thể đọc thông tin người dùng: $e');
    }

    if (userProfile == null) {
      await _firebaseAuth.signOut();
      throw AuthException('Không tìm thấy thông tin tài khoản nhân viên tại chi nhánh $cleanStore.');
    }

    // 6. Kiểm tra trạng thái khóa tài khoản
    if (!userProfile.isActive) {
      await _firebaseAuth.signOut();
      throw const AuthException('Tài khoản đã bị tạm khóa bởi chủ quán.');
    }

    // 7. Đăng nhập thành công -> Reset bộ đếm đăng nhập sai
    await _resetLoginAttempts(cleanStore, cleanUser);

    // 8. Cập nhật lastLoginAt và ghi nhận Audit Log
    final now = DateTime.now().millisecondsSinceEpoch;
    _fb.storeRef.child('users').child(userProfile.uid).child('lastLoginAt').set(now).catchError((_) {});

    _fb.logAction(AuditLogModel(
      timestamp: now,
      username: userProfile.username,
      userFullName: userProfile.fullName,
      userRole: userProfile.roleId,
      action: 'LOGIN',
      targetType: 'AUTH',
      targetId: userProfile.username,
      details: 'Đăng nhập thành công vào cửa hàng $cleanStore',
    )).catchError((_) {});

    // 9. Lưu phiên làm việc vào SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberStore, rememberStore);
    if (rememberStore) {
      await prefs.setString(_keyStoreCode, cleanStore);
    } else {
      await prefs.remove(_keyStoreCode);
    }
    await prefs.setString(_keyUsername, userProfile.username);
    await prefs.setString(_keyRole, userProfile.roleId);
    await prefs.setString(_keyFullName, userProfile.fullName);
    await prefs.setString(_keyUid, userProfile.uid);

    _currentUser = userProfile.copyWith(lastLoginAt: now);
    refreshRolesAndStoreInfo();
    notifyListeners();

    return _currentUser!;
  }

  /// Đổi mật khẩu tài khoản
  Future<void> changePassword({
    required String newPassword,
    bool isMandatory = false,
  }) async {
    final fbUser = _firebaseAuth.currentUser;
    if (fbUser == null || _currentUser == null) {
      throw const AuthException('Chưa đăng nhập hệ thống.');
    }
    if (newPassword.length < 6) {
      throw const AuthException('Mật khẩu mới phải có tối thiểu 6 ký tự.');
    }

    try {
      await fbUser.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const AuthException('Phiên làm việc đã quá hạn bảo mật. Vui lòng đăng nhập lại để đổi mật khẩu.');
      }
      throw AuthException('Đổi mật khẩu thất bại: ${e.message ?? e.code}');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    // Cập nhật mustChangePassword = false
    await _fb.storeRef.child('users').child(_currentUser!.uid).update({
      'mustChangePassword': false,
    }).catchError((_) {});

    final action = isMandatory ? 'CHANGE_PASSWORD_MANDATORY_SUCCESS' : 'CHANGE_PASSWORD_SUCCESS';
    _fb.logAction(AuditLogModel(
      timestamp: now,
      username: _currentUser!.username,
      userFullName: _currentUser!.fullName,
      userRole: _currentUser!.roleId,
      action: action,
      targetType: 'AUTH',
      targetId: _currentUser!.username,
      details: isMandatory ? 'Đổi mật khẩu bắt buộc lần đầu thành công' : 'Tự đổi mật khẩu thành công',
    )).catchError((_) {});

    _currentUser = _currentUser!.copyWith(mustChangePassword: false);
    notifyListeners();
  }

  /// Đăng xuất khỏi ca làm việc
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
        details: 'Đăng xuất khỏi ca làm việc tại $_currentStoreCode',
      )).catchError((_) {});
    }

    try {
      await _firebaseAuth.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyFullName);
    await prefs.remove(_keyUid);
    _currentUser = null;
    notifyListeners();
  }
}
