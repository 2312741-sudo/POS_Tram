// lib/core/services/auth_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../core/permissions/app_permissions.dart';

class AuthException implements Exception {
  final String message;

  /// Số giây khóa tạm còn lại (chỉ có khi máy chủ trả về lỗi khóa tạm do nhập sai nhiều lần)
  final int? lockoutSeconds;
  const AuthException(this.message, {this.lockoutSeconds});

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

  static const String _functionsRegion = 'asia-southeast1';
  FirebaseFunctions? _functionsMock;
  FirebaseFunctions get _functions => _functionsMock ?? FirebaseFunctions.instanceFor(region: _functionsRegion);

  @visibleForTesting
  void setFunctionsMock(FirebaseFunctions? mock) {
    _functionsMock = mock;
  }

  // Không mặc định cứng mã cửa hàng: được gán khi đăng nhập / tự đăng nhập / đổi chi nhánh
  String _currentStoreCode = '';
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
      // Tên tạm thời; tên thật được nạp từ storeInfo trong refreshRolesAndStoreInfo()
      storeName: 'POS Trạm - Chi nhánh $_currentStoreCode',
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

  /// Gọi Cloud Function staffSignIn: máy chủ kiểm tra khóa tạm, xác minh mật khẩu,
  /// ghi nhận lần sai (stores/{storeCode}/login_attempts chỉ Admin SDK truy cập được)
  /// và trả về Custom Token nếu hợp lệ.
  Future<String> _requestSignInToken(String storeCode, String username, String password) async {
    try {
      final callable = _functions.httpsCallable(
        'staffSignIn',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );
      final result = await callable.call<dynamic>({
        'storeCode': storeCode,
        'username': username,
        'password': password,
      });
      final data = result.data;
      final token = data is Map ? data['token']?.toString() : null;
      if (token == null || token.isEmpty) {
        throw const AuthException('Máy chủ không trả về phiên đăng nhập hợp lệ. Vui lòng thử lại.');
      }
      return token;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'resource-exhausted':
          final details = e.details;
          final seconds = details is Map ? (details['remainingSeconds'] as num?)?.toInt() : null;
          if (seconds != null && seconds > 0) {
            final minutes = (seconds / 60).ceil();
            throw AuthException(
              'Tài khoản đã bị khóa tạm thời do nhập sai mật khẩu $maxFailedAttempts lần liên tiếp. Vui lòng thử lại sau $minutes phút hoặc liên hệ Quản lý.',
              lockoutSeconds: seconds,
            );
          }
          throw AuthException(e.message ?? 'Hệ thống đang tạm hạn chế đăng nhập. Vui lòng thử lại sau ít phút.');
        case 'unauthenticated':
          throw const AuthException('Sai tài khoản hoặc mật khẩu.');
        case 'permission-denied':
        case 'invalid-argument':
        case 'failed-precondition':
          throw AuthException(e.message ?? 'Đăng nhập thất bại.');
        case 'unavailable':
        case 'deadline-exceeded':
          throw const AuthException('Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng Internet và thử lại.');
        default:
          throw AuthException('Đăng nhập thất bại: ${e.message ?? e.code}');
      }
    }
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

    // 2-4. Xác thực phía máy chủ (Cloud Function staffSignIn): kiểm tra khóa tạm 15 phút
    //      sau 5 lần sai liên tiếp, xác minh mật khẩu, rồi đăng nhập bằng Custom Token.
    UserCredential credential;
    try {
      final token = await _requestSignInToken(cleanStore, cleanUser, password).timeout(const Duration(seconds: 25));
      credential = await _firebaseAuth.signInWithCustomToken(token).timeout(const Duration(seconds: 10));
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        throw const AuthException('Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng Internet và thử lại.');
      } else if (e.code == 'too-many-requests') {
        throw const AuthException('Quá nhiều yêu cầu không thành công. Hệ thống đang tạm hạn chế, vui lòng thử lại sau ít phút.');
      }
      throw AuthException('Đăng nhập thất bại: ${e.message ?? e.code}');
    } on TimeoutException {
      throw const AuthException('Kết nối đến máy chủ quá chậm hoặc gián đoạn. Vui lòng kiểm tra đường truyền và thử lại.');
    } catch (e) {
      throw AuthException('Đăng nhập thất bại: ${e.toString()}');
    }

    return _completeSignIn(
      rawUid: credential.user?.uid,
      storeCode: cleanStore,
      rememberStore: rememberStore,
      loginDetails: 'Đăng nhập thành công vào cửa hàng $cleanStore',
    );
  }

  /// Đăng nhập bằng Custom Token do máy chủ cấp (vd: chamCongSignIn — Đăng nhập bằng Chấm Công Trạm).
  /// Dùng chung đường hậu đăng nhập với [login]: nạp hồ sơ, kiểm tra khóa, ghi nhớ cửa hàng, audit log.
  Future<UserModel> loginWithCustomToken({
    required String storeCode,
    required String customToken,
    bool? rememberStore,
    String loginDetails = 'Đăng nhập bằng Chấm Công Trạm',
  }) async {
    final cleanStore = storeCode.trim().toUpperCase();
    if (cleanStore.isEmpty) {
      throw const AuthException('Máy chủ không trả về mã cửa hàng hợp lệ.');
    }
    final remember = rememberStore ?? await getRememberStoreOption();

    _currentStoreCode = cleanStore;
    _fb.switchStore(cleanStore);

    UserCredential credential;
    try {
      credential = await _firebaseAuth.signInWithCustomToken(customToken).timeout(const Duration(seconds: 10));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        throw const AuthException('Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng Internet và thử lại.');
      }
      throw AuthException('Đăng nhập thất bại: ${e.message ?? e.code}');
    } on TimeoutException {
      throw const AuthException('Kết nối đến máy chủ quá chậm hoặc gián đoạn. Vui lòng kiểm tra đường truyền và thử lại.');
    }

    return _completeSignIn(
      rawUid: credential.user?.uid,
      storeCode: cleanStore,
      rememberStore: remember,
      loginDetails: '$loginDetails vào cửa hàng $cleanStore',
    );
  }

  /// Đường hậu đăng nhập dùng chung (sau khi signInWithCustomToken thành công):
  /// nạp hồ sơ RTDB, kiểm tra khóa tài khoản, ghi lastLoginAt + audit log, lưu phiên.
  Future<UserModel> _completeSignIn({
    required String? rawUid,
    required String storeCode,
    required bool rememberStore,
    required String loginDetails,
  }) async {
    final cleanStore = storeCode;
    final uid = rawUid;
    if (uid == null || uid.isEmpty) {
      throw const AuthException('Không lấy được mã định danh người dùng từ hệ thống xác thực.');
    }

    // 5. Nạp hồ sơ người dùng từ Realtime Database tại stores/{storeCode}/users/{uid}
    UserModel? userProfile;
    try {
      final snap = await _fb.storeRef.child('users').child(uid).get().timeout(const Duration(seconds: 6));
      if (snap.exists && snap.value != null && snap.value is Map) {
        userProfile = UserModel.fromMap(snap.value as Map, uid);
      }
      // Lưu ý: client KHÔNG được tự tạo/nâng cấp hồ sơ (rules chặn tự đăng ký).
      // Hồ sơ legacy theo username phải được chuyển bằng scripts/migrate_legacy_users.
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

    // 7. Bộ đếm đăng nhập sai đã được máy chủ (staffSignIn) xóa khi xác thực thành công

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
      details: loginDetails,
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
