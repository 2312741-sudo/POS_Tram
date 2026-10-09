// lib/core/services/chamcong_auth_service.dart
//
// "Đăng nhập bằng Chấm Công Trạm": đăng nhập tài khoản chấm công trên Firebase app phụ
// "chamcong" (project chamcongtram) bằng Google / Apple / Email, lấy ID token, gửi lên
// Cloud Function chamCongSignIn của POS (app mặc định) để đổi lấy Custom Token POS.
// Phiên chấm công được đăng xuất ngay sau khi lấy token (không giữ hai phiên song song).
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../data/models/app_models.dart';
import '../config/chamcong_firebase_config.dart';
import 'auth_service.dart';

// ============================================================================
// MÔ HÌNH & PHÂN TÍCH PHẢN HỒI (thuần Dart — kiểm thử được không cần Firebase)
// ============================================================================

/// Phương thức đăng nhập tài khoản Chấm Công Trạm
enum ChamCongMethod { google, apple, email }

/// Yêu cầu đăng nhập chấm công (email/password chỉ dùng với [ChamCongMethod.email])
class ChamCongCredentialRequest {
  final ChamCongMethod method;
  final String? email;
  final String? password;
  const ChamCongCredentialRequest(this.method, {this.email, this.password});
}

class ChamCongAuthException implements Exception {
  /// Mã lỗi: INVALID_TOKEN, NOT_LINKED, NOT_ACTIVE_MEMBER, POS_ACCOUNT_DISABLED,
  /// ALREADY_LINKED, CANCELLED, NOT_CONFIGURED, NETWORK, ... hoặc mã FirebaseAuth
  final String code;
  final String message;
  const ChamCongAuthException(this.code, this.message);

  /// Người dùng tự hủy (đóng popup Google/Apple, đóng hộp chọn cửa hàng) → không hiện lỗi
  bool get isCancelled => code == ChamCongErrorCodes.cancelled;

  @override
  String toString() => message;
}

class ChamCongErrorCodes {
  static const invalidToken = 'INVALID_TOKEN';
  static const notLinked = 'NOT_LINKED';
  static const notActiveMember = 'NOT_ACTIVE_MEMBER';
  static const posAccountDisabled = 'POS_ACCOUNT_DISABLED';
  static const alreadyLinked = 'ALREADY_LINKED';
  static const posAccountConflict = 'POS_ACCOUNT_CONFLICT';
  static const notStoreOwner = 'NOT_STORE_OWNER';
  static const serverNotConfigured = 'SERVER_NOT_CONFIGURED';
  static const cancelled = 'CANCELLED';
  static const notConfigured = 'NOT_CONFIGURED';
  static const network = 'NETWORK';
  static const badResponse = 'BAD_RESPONSE';
}

/// Thông điệp tiếng Việt cho mã lỗi máy chủ (details.code) / mã nội bộ
String chamCongErrorMessage(String code, [String? fallback]) {
  switch (code) {
    case ChamCongErrorCodes.invalidToken:
      return 'Phiên đăng nhập Chấm Công Trạm không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại.';
    case ChamCongErrorCodes.notLinked:
      return 'Cửa hàng chấm công của bạn chưa được liên kết với POS. Nhờ chủ quán liên kết trong Cài đặt.';
    case ChamCongErrorCodes.notActiveMember:
      return 'Tài khoản chấm công của bạn chưa là thành viên đang hoạt động của cửa hàng nào. Liên hệ chủ quán để được duyệt.';
    case ChamCongErrorCodes.posAccountDisabled:
      return 'Tài khoản POS của bạn đã bị chủ quán tạm khóa.';
    case ChamCongErrorCodes.alreadyLinked:
      return 'Cửa hàng chấm công này đã được liên kết với một cửa hàng POS khác.';
    case ChamCongErrorCodes.posAccountConflict:
      return 'Tài khoản chấm công của bạn trùng với một tài khoản POS sẵn có. Nhờ chủ quán kiểm tra trong Quản lý nhân viên.';
    case ChamCongErrorCodes.notStoreOwner:
      return 'Tài khoản Chấm Công Trạm này không phải chủ của cửa hàng chấm công nào. Hãy đăng nhập bằng tài khoản chủ quán.';
    case ChamCongErrorCodes.serverNotConfigured:
      return 'Máy chủ chưa được cấu hình kết nối Chấm Công, liên hệ chủ quán.';
    case ChamCongErrorCodes.notConfigured:
      return 'Ứng dụng chưa được cấu hình đăng nhập Chấm Công Trạm.';
    case ChamCongErrorCodes.network:
      return 'Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng Internet và thử lại.';
    case ChamCongErrorCodes.badResponse:
      return 'Máy chủ trả về dữ liệu không hợp lệ. Vui lòng thử lại.';
    case ChamCongErrorCodes.cancelled:
      return 'Đã hủy đăng nhập.';
    // Lỗi đăng nhập Firebase Auth của app chấm công
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-email':
      return 'Email hoặc mật khẩu Chấm Công Trạm không đúng.';
    case 'user-disabled':
      return 'Tài khoản Chấm Công Trạm đã bị vô hiệu hóa.';
    case 'too-many-requests':
      return 'Đăng nhập sai quá nhiều lần. Vui lòng thử lại sau ít phút.';
    case 'network-request-failed':
      return 'Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng Internet và thử lại.';
    case 'account-exists-with-different-credential':
      return 'Email này đã đăng ký Chấm Công Trạm bằng phương thức khác. Hãy dùng đúng phương thức đã đăng ký.';
    case 'popup-blocked':
      return 'Trình duyệt đã chặn cửa sổ đăng nhập. Vui lòng cho phép popup và thử lại.';
    default:
      return fallback ?? 'Đăng nhập Chấm Công Trạm thất bại ($code).';
  }
}

/// Chuyển lỗi callable thành [ChamCongAuthException] (ưu tiên details.code của máy chủ)
ChamCongAuthException mapChamCongFunctionsError(FirebaseFunctionsException e) {
  final details = e.details;
  final serverCode = details is Map ? details['code']?.toString() : null;
  if (serverCode != null && serverCode.isNotEmpty) {
    return ChamCongAuthException(serverCode, chamCongErrorMessage(serverCode, e.message));
  }
  switch (e.code) {
    case 'unavailable':
    case 'deadline-exceeded':
      return ChamCongAuthException(ChamCongErrorCodes.network, chamCongErrorMessage(ChamCongErrorCodes.network));
    case 'unauthenticated':
      return ChamCongAuthException(ChamCongErrorCodes.invalidToken, chamCongErrorMessage(ChamCongErrorCodes.invalidToken));
    case 'internal':
      // Thiếu quyền IAM phía máy chủ → lỗi internal không kèm mã
      return ChamCongAuthException(
          ChamCongErrorCodes.serverNotConfigured, chamCongErrorMessage(ChamCongErrorCodes.serverNotConfigured));
    case 'not-found':
      return ChamCongAuthException(e.code, 'Máy chủ chưa hỗ trợ đăng nhập Chấm Công Trạm. Vui lòng cập nhật hệ thống.');
    default:
      return ChamCongAuthException(e.code, e.message ?? 'Yêu cầu thất bại (${e.code}).');
  }
}

/// Mã lỗi hủy thao tác từ Google/Apple/Firebase Auth
bool isChamCongCancellation(Object e) {
  if (e is ChamCongAuthException) return e.isCancelled;
  if (e is FirebaseAuthException) {
    const codes = {
      'cancelled', 'canceled', 'web-context-cancelled', 'web-context-canceled',
      'popup-closed-by-user', 'user-cancelled', 'cancelled-popup-request', 'sign_in_canceled',
    };
    if (codes.contains(e.code)) return true;
  }
  final s = e.toString();
  return s.contains('sign_in_canceled') ||
      s.contains('popup-closed-by-user') ||
      s.contains('AuthorizationError error 1001') ||
      s.contains('canceled') ||
      s.contains('cancelled');
}

/// Lựa chọn cửa hàng POS (khi một tài khoản chấm công thuộc nhiều cửa hàng đã liên kết)
class ChamCongStoreOption {
  final String storeCode;
  final String storeName;
  const ChamCongStoreOption({required this.storeCode, required this.storeName});
}

/// Lựa chọn cửa hàng phía Chấm Công (khi chủ quán sở hữu nhiều cửa hàng chấm công)
class ChamCongWorkplaceOption {
  final String chamCongStoreId;
  final String name;
  final String code;
  const ChamCongWorkplaceOption({required this.chamCongStoreId, required this.name, this.code = ''});
}

/// Phản hồi chamCongSignIn
class ChamCongSignInResponse {
  final bool needsStoreChoice;
  final List<ChamCongStoreOption> stores;
  final String customToken;
  final String storeCode;
  final String uid;
  final String roleId;
  final bool isNewAccount;

  const ChamCongSignInResponse._({
    required this.needsStoreChoice,
    this.stores = const [],
    this.customToken = '',
    this.storeCode = '',
    this.uid = '',
    this.roleId = '',
    this.isNewAccount = false,
  });

  /// Ném [ChamCongAuthException] (BAD_RESPONSE) nếu dữ liệu không hợp lệ
  factory ChamCongSignInResponse.fromData(dynamic data) {
    if (data is! Map) throw _badResponse();
    final status = data['status']?.toString();
    if (status == 'CHOOSE_STORE') {
      final raw = data['stores'];
      final stores = <ChamCongStoreOption>[];
      if (raw is List) {
        for (final s in raw) {
          if (s is Map) {
            final code = s['storeCode']?.toString().trim() ?? '';
            if (code.isEmpty) continue;
            final name = s['storeName']?.toString().trim() ?? '';
            stores.add(ChamCongStoreOption(storeCode: code, storeName: name.isEmpty ? code : name));
          }
        }
      }
      if (stores.isEmpty) throw _badResponse();
      return ChamCongSignInResponse._(needsStoreChoice: true, stores: stores);
    }
    if (status == 'OK') {
      final token = data['customToken']?.toString() ?? '';
      final storeCode = data['storeCode']?.toString().trim() ?? '';
      if (token.isEmpty || storeCode.isEmpty) throw _badResponse();
      return ChamCongSignInResponse._(
        needsStoreChoice: false,
        customToken: token,
        storeCode: storeCode,
        uid: data['uid']?.toString() ?? '',
        roleId: data['roleId']?.toString() ?? '',
        isNewAccount: data['isNewAccount'] == true,
      );
    }
    throw _badResponse();
  }
}

/// Phản hồi linkChamCongStore
class ChamCongLinkResponse {
  final bool linked;
  final List<ChamCongWorkplaceOption> choices;
  final String chamCongStoreId;
  final String chamCongStoreName;

  const ChamCongLinkResponse._({
    required this.linked,
    this.choices = const [],
    this.chamCongStoreId = '',
    this.chamCongStoreName = '',
  });

  bool get needsChoice => !linked;

  factory ChamCongLinkResponse.fromData(dynamic data) {
    if (data is! Map) throw _badResponse();
    final status = data['status']?.toString();
    if (status == 'LINKED') {
      return ChamCongLinkResponse._(
        linked: true,
        chamCongStoreId: data['chamCongStoreId']?.toString() ?? '',
        chamCongStoreName: data['chamCongStoreName']?.toString() ?? '',
      );
    }
    if (status == 'CHOOSE_CHAMCONG_STORE') {
      final raw = data['stores'];
      final choices = <ChamCongWorkplaceOption>[];
      if (raw is List) {
        for (final s in raw) {
          if (s is Map) {
            final id = s['chamCongStoreId']?.toString().trim() ?? '';
            if (id.isEmpty) continue;
            final name = s['name']?.toString().trim() ?? '';
            choices.add(ChamCongWorkplaceOption(
              chamCongStoreId: id,
              name: name.isEmpty ? id : name,
              code: s['code']?.toString() ?? '',
            ));
          }
        }
      }
      if (choices.isEmpty) throw _badResponse();
      return ChamCongLinkResponse._(linked: false, choices: choices);
    }
    throw _badResponse();
  }
}

/// Phản hồi getChamCongLinkStatus
class ChamCongLinkStatus {
  final bool linked;
  final String? chamCongStoreId;
  final String? chamCongStoreName;
  final int? linkedAt;
  final int provisionedCount;

  const ChamCongLinkStatus({
    required this.linked,
    this.chamCongStoreId,
    this.chamCongStoreName,
    this.linkedAt,
    this.provisionedCount = 0,
  });

  factory ChamCongLinkStatus.fromData(dynamic data) {
    if (data is! Map) throw _badResponse();
    final rawAt = data['linkedAt'];
    final int? linkedAt = rawAt is num ? rawAt.toInt() : int.tryParse(rawAt?.toString() ?? '');
    final rawCount = data['provisionedCount'];
    final count = rawCount is num ? rawCount.toInt() : int.tryParse(rawCount?.toString() ?? '') ?? 0;
    String? opt(String k) {
      final v = data[k]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return ChamCongLinkStatus(
      linked: data['linked'] == true,
      chamCongStoreId: opt('chamCongStoreId'),
      chamCongStoreName: opt('chamCongStoreName'),
      linkedAt: linkedAt,
      provisionedCount: count,
    );
  }
}

/// Phản hồi unlinkChamCongStore → wasLinked
bool parseUnlinkResponse(dynamic data) {
  if (data is! Map || data['status']?.toString() != 'UNLINKED') throw _badResponse();
  return data['wasLinked'] != false;
}

ChamCongAuthException _badResponse() =>
    ChamCongAuthException(ChamCongErrorCodes.badResponse, chamCongErrorMessage(ChamCongErrorCodes.badResponse));

/// Hộp chọn cửa hàng POS; trả về storeCode hoặc null nếu hủy
typedef ChamCongStorePicker = Future<String?> Function(List<ChamCongStoreOption> stores);

/// Hộp chọn cửa hàng chấm công; trả về chamCongStoreId hoặc null nếu hủy
typedef ChamCongWorkplacePicker = Future<String?> Function(List<ChamCongWorkplaceOption> stores);

// ============================================================================
// DỊCH VỤ
// ============================================================================

class ChamCongAuthService {
  static final ChamCongAuthService _instance = ChamCongAuthService._internal();
  factory ChamCongAuthService() => _instance;
  ChamCongAuthService._internal();

  static const String _functionsRegion = 'asia-southeast1';
  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: _functionsRegion);

  ChamCongFirebaseConfig? _config;
  FirebaseApp? _app;

  /// Ứng dụng đã có cấu hình Firebase chamcongtram hay chưa (để ẩn/hiện nút)
  Future<bool> isConfigured() async => (await ChamCongFirebaseConfig.load()) != null;

  /// Apple chỉ hỗ trợ trên iOS/macOS
  static bool get supportsApple =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  /// Google: web (popup) và Android/iOS/macOS (google_sign_in)
  static bool get supportsGoogle =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<FirebaseAuth> _chamCongAuth() async {
    if (_app == null) {
      _config ??= await ChamCongFirebaseConfig.load();
      final cfg = _config;
      if (cfg == null) {
        throw ChamCongAuthException(ChamCongErrorCodes.notConfigured, chamCongErrorMessage(ChamCongErrorCodes.notConfigured));
      }
      final existing = Firebase.apps.where((a) => a.name == kChamCongAppName);
      _app = existing.isNotEmpty
          ? existing.first
          : await Firebase.initializeApp(name: kChamCongAppName, options: cfg.options);
    }
    return FirebaseAuth.instanceFor(app: _app!);
  }

  /// Đăng nhập tài khoản chấm công, lấy ID token rồi đăng xuất ngay phiên chấm công.
  Future<String> obtainChamCongIdToken(ChamCongCredentialRequest req) async {
    final auth = await _chamCongAuth();
    GoogleSignIn? google;
    try {
      User? user;
      switch (req.method) {
        case ChamCongMethod.email:
          final email = req.email?.trim() ?? '';
          final pass = req.password ?? '';
          if (email.isEmpty || pass.isEmpty) {
            throw const ChamCongAuthException('invalid-input', 'Vui lòng nhập Email và Mật khẩu Chấm Công Trạm.');
          }
          user = (await auth.signInWithEmailAndPassword(email: email, password: pass)).user;
          break;
        case ChamCongMethod.google:
          if (kIsWeb) {
            final provider = GoogleAuthProvider()
              ..addScope('email')
              ..setCustomParameters({'prompt': 'select_account'});
            user = (await auth.signInWithPopup(provider)).user;
          } else {
            final isApple = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
            google = GoogleSignIn(
              scopes: const ['email'],
              clientId: isApple ? _config?.options.iosClientId : null,
              serverClientId: _config?.googleServerClientId,
            );
            // Luôn cho chọn lại tài khoản (máy POS dùng chung giữa nhiều nhân viên)
            try {
              await google.signOut();
            } catch (_) {}
            final account = await google.signIn();
            if (account == null) {
              throw ChamCongAuthException(ChamCongErrorCodes.cancelled, chamCongErrorMessage(ChamCongErrorCodes.cancelled));
            }
            final gAuth = await account.authentication;
            final credential = GoogleAuthProvider.credential(idToken: gAuth.idToken, accessToken: gAuth.accessToken);
            user = (await auth.signInWithCredential(credential)).user;
          }
          break;
        case ChamCongMethod.apple:
          final provider = AppleAuthProvider()
            ..addScope('email')
            ..addScope('name');
          user = kIsWeb
              ? (await auth.signInWithPopup(provider)).user
              : (await auth.signInWithProvider(provider)).user;
          break;
      }
      final token = await user?.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw ChamCongAuthException(ChamCongErrorCodes.invalidToken, chamCongErrorMessage(ChamCongErrorCodes.invalidToken));
      }
      return token;
    } on ChamCongAuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      if (isChamCongCancellation(e)) {
        throw ChamCongAuthException(ChamCongErrorCodes.cancelled, chamCongErrorMessage(ChamCongErrorCodes.cancelled));
      }
      throw ChamCongAuthException(e.code, chamCongErrorMessage(e.code, 'Đăng nhập Chấm Công Trạm thất bại: ${e.message ?? e.code}'));
    } catch (e) {
      if (isChamCongCancellation(e)) {
        throw ChamCongAuthException(ChamCongErrorCodes.cancelled, chamCongErrorMessage(ChamCongErrorCodes.cancelled));
      }
      throw ChamCongAuthException('sign-in-failed', 'Đăng nhập Chấm Công Trạm thất bại: $e');
    } finally {
      // Không giữ hai phiên song song: đăng xuất app chấm công (và Google) sau khi lấy token
      try {
        await auth.signOut();
      } catch (_) {}
      if (google != null) {
        try {
          await google.signOut();
        } catch (_) {}
      }
    }
  }

  Future<dynamic> _call(String name, Map<String, dynamic> payload) async {
    try {
      final callable = _functions.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<dynamic>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      throw mapChamCongFunctionsError(e);
    } on TimeoutException {
      throw ChamCongAuthException(ChamCongErrorCodes.network, chamCongErrorMessage(ChamCongErrorCodes.network));
    }
  }

  /// Toàn bộ luồng "Đăng nhập bằng Chấm Công Trạm" vào POS
  Future<UserModel> signInToPos(
    ChamCongCredentialRequest req, {
    required ChamCongStorePicker pickStore,
  }) async {
    final idToken = await obtainChamCongIdToken(req);

    var resp = ChamCongSignInResponse.fromData(await _call('chamCongSignIn', {'idToken': idToken}));
    if (resp.needsStoreChoice) {
      final chosen = await pickStore(resp.stores);
      if (chosen == null || chosen.isEmpty) {
        throw ChamCongAuthException(ChamCongErrorCodes.cancelled, chamCongErrorMessage(ChamCongErrorCodes.cancelled));
      }
      resp = ChamCongSignInResponse.fromData(await _call('chamCongSignIn', {'idToken': idToken, 'storeCode': chosen}));
      if (resp.needsStoreChoice) throw _badResponse();
    }

    try {
      return await AuthService().loginWithCustomToken(
        storeCode: resp.storeCode,
        customToken: resp.customToken,
        loginDetails: resp.isNewAccount
            ? 'Đăng nhập lần đầu bằng Chấm Công Trạm (tài khoản tự cấp)'
            : 'Đăng nhập bằng Chấm Công Trạm',
      );
    } on AuthException catch (e) {
      throw ChamCongAuthException('pos-sign-in-failed', e.message);
    }
  }

  /// Chủ quán liên kết cửa hàng POS hiện tại với cửa hàng chấm công mình sở hữu
  Future<ChamCongLinkResponse> linkStore(
    ChamCongCredentialRequest req, {
    required String storeCode,
    required ChamCongWorkplacePicker pickWorkplace,
  }) async {
    final idToken = await obtainChamCongIdToken(req);
    var resp = ChamCongLinkResponse.fromData(
        await _call('linkChamCongStore', {'storeCode': storeCode, 'idToken': idToken}));
    if (resp.needsChoice) {
      final chosen = await pickWorkplace(resp.choices);
      if (chosen == null || chosen.isEmpty) {
        throw ChamCongAuthException(ChamCongErrorCodes.cancelled, chamCongErrorMessage(ChamCongErrorCodes.cancelled));
      }
      resp = ChamCongLinkResponse.fromData(await _call(
          'linkChamCongStore', {'storeCode': storeCode, 'idToken': idToken, 'chamCongStoreId': chosen}));
      if (resp.needsChoice) throw _badResponse();
    }
    return resp;
  }

  /// Trả về true nếu trước đó đang liên kết (máy chủ: {status:"UNLINKED", wasLinked})
  Future<bool> unlinkStore(String storeCode) async {
    final data = await _call('unlinkChamCongStore', {'storeCode': storeCode});
    return parseUnlinkResponse(data);
  }

  Future<ChamCongLinkStatus> getLinkStatus(String storeCode) async {
    return ChamCongLinkStatus.fromData(await _call('getChamCongLinkStatus', {'storeCode': storeCode}));
  }
}
