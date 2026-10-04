// lib/features/auth/login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/firebase_service.dart';
import '../../data/models/app_models.dart';
import 'change_password_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _fb = FirebaseService();
  final _storeCodeCtrl = TextEditingController(text: 'TRAM01');
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  List<StoreInfoModel> _availableStores = [];
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberStore = true;
  String? _errorMessage;
  int? _lockoutSecondsRemaining;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _initSavedStoreCode();
    _checkAutoLogin();
    _loadStores();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _storeCodeCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSavedStoreCode() async {
    final savedCode = await _auth.getSavedStoreCode();
    final remember = await _auth.getRememberStoreOption();
    if (mounted) {
      setState(() {
        _rememberStore = remember;
        if (savedCode != null && savedCode.isNotEmpty) {
          _storeCodeCtrl.text = savedCode;
        }
      });
    }
  }

  Future<void> _loadStores() async {
    final stores = await _fb.getAllStores();
    if (mounted && stores.isNotEmpty) {
      setState(() => _availableStores = stores);
    }
  }

  Future<void> _checkAutoLogin() async {
    final ok = await _auth.checkAutoLogin();
    if (ok && mounted) {
      final user = _auth.currentUser;
      if (user != null && user.mustChangePassword) {
        _showMandatoryChangePassword();
      } else {
        _navigateAfterLogin();
      }
    }
  }

  void _navigateAfterLogin() {
    if (_auth.isKitchen) {
      context.go('/kitchen');
    } else if (_auth.canAccessManagerHub) {
      context.go('/manager-hub');
    } else {
      context.go('/tables');
    }
  }

  void _showMandatoryChangePassword() {
    ChangePasswordDialog.show(
      context,
      isMandatory: true,
      onSuccess: () {
        if (mounted) _navigateAfterLogin();
      },
    );
  }

  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    setState(() => _lockoutSecondsRemaining = seconds);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_lockoutSecondsRemaining != null && _lockoutSecondsRemaining! > 1) {
          _lockoutSecondsRemaining = _lockoutSecondsRemaining! - 1;
        } else {
          _lockoutSecondsRemaining = null;
          _errorMessage = null;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleLogin() async {
    final store = _storeCodeCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (store.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập đầy đủ Mã cửa hàng, Tên đăng nhập và Mật khẩu.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _auth.login(
        storeCode: store,
        username: username,
        password: password,
        rememberStore: _rememberStore,
      );

      if (mounted) {
        if (user.mustChangePassword) {
          _showMandatoryChangePassword();
        } else {
          _navigateAfterLogin();
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
        // Kiểm tra xem có phải lỗi khóa tạm hay không để đếm ngược
        final remaining = await _auth.getLockoutRemainingSeconds(store, username);
        if (remaining != null && remaining > 0) {
          _startLockoutCountdown(remaining);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLockedOut = _lockoutSecondsRemaining != null && _lockoutSecondsRemaining! > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 4,
              shadowColor: AppColors.shadow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.border, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App Logo
                    Container(
                      width: 88,
                      height: 88,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                        border: Border.all(color: AppColors.border, width: 1.5),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'assets/images/logo.jpg',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.primaryLight,
                              child: const Icon(Icons.restaurant_menu, size: 40, color: AppColors.primary),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'POS TRẠM',
                      style: GoogleFonts.beVietnamPro(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hệ Thống Bán Hàng & Quản Lý Chi Nhánh',
                      style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),

                    // Error or Lockout Banner
                    if (isLockedOut) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined, color: AppColors.warning, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Tài khoản đang bị khóa tạm. Vui lòng thử lại sau ${(_lockoutSecondsRemaining! ~/ 60)} phút ${(_lockoutSecondsRemaining! % 60)} giây.',
                                style: GoogleFonts.beVietnamPro(color: AppColors.warningInk, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.dangerLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.beVietnamPro(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Store Code Input
                    TextField(
                      controller: _storeCodeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Mã Cửa Hàng (Store Code) *',
                        prefixIcon: Icon(Icons.storefront_outlined),
                        hintText: 'VD: TRAM01, TRAM02',
                      ),
                    ),
                    if (_availableStores.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _availableStores.map((s) {
                          final isSelected = _storeCodeCtrl.text.trim().toUpperCase() == s.storeCode;
                          return ChoiceChip(
                            label: Text(
                              '${s.storeCode} (${s.storeName.split("-").last.trim()})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            onSelected: (_) {
                              setState(() {
                                _storeCodeCtrl.text = s.storeCode;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Username Input
                    TextField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên đăng nhập *',
                        prefixIcon: Icon(Icons.person_outline),
                        hintText: 'VD: thungan1, ql_kho...',
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Password Input
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu *',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      onSubmitted: (_) => isLockedOut ? null : _handleLogin(),
                    ),
                    const SizedBox(height: 10),

                    // Remember Store Option Checkbox
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberStore,
                          activeColor: AppColors.primary,
                          onChanged: (val) {
                            setState(() => _rememberStore = val ?? true);
                          },
                        ),
                        Text(
                          'Ghi nhớ mã cửa hàng',
                          style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Login Button (Red Gradient)
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: isLockedOut ? null : AppColors.primaryGradient,
                        color: isLockedOut ? Colors.grey.shade400 : null,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isLockedOut
                            ? null
                            : [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (_isLoading || isLockedOut) ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(
                                isLockedOut ? 'TÀI KHOẢN ĐANG KHÓA TẠM' : 'ĐĂNG NHẬP',
                                style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
