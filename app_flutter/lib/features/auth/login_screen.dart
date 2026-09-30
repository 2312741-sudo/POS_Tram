// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/firebase_service.dart';
import '../../data/models/app_models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _fb = FirebaseService();
  final _storeCodeCtrl = TextEditingController(text: 'TRAM01');
  final _usernameCtrl = TextEditingController(text: 'admin');
  final _passwordCtrl = TextEditingController(text: 'admin');

  List<StoreInfoModel> _availableStores = [];
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
    _loadStores();
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
      _navigateAfterLogin();
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

  Future<void> _handleLogin() async {
    final store = _storeCodeCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (store.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập đầy đủ Mã cửa hàng, Tài khoản và Mật khẩu.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _auth.login(storeCode: store, username: username, password: password);
      if (user != null && mounted) {
        _navigateAfterLogin();
      } else if (mounted) {
        setState(() => _errorMessage = 'Sai mã cửa hàng, tài khoản hoặc mật khẩu!');
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 3,
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
                    // App Logo (From Attendance App)
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
                      'Hệ Thống Quản Lý Gọi Món & Thu Ngân',
                      style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_errorMessage!, style: GoogleFonts.beVietnamPro(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
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
                        labelText: 'Tài khoản nhân viên *',
                        prefixIcon: Icon(Icons.person_outline),
                        hintText: 'admin, thungan, phucvu...',
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
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textSecondary),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    const SizedBox(height: 24),

                    // Login Button (Red Gradient)
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
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
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(
                                'ĐĂNG NHẬP',
                                style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    // Hint / Demo Credentials Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mặc định: Mã CH "TRAM01" • Admin "admin/admin" • Thu ngân "thungan/123"',
                              style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
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
