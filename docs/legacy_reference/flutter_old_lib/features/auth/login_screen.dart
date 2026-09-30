// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import 'dart:ui';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _loading = false;
  String? _error;
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgController.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    
    HapticFeedback.lightImpact();
    
    final user = await AuthService().login(
      _userCtrl.text.trim(),
      _passCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (user != null) {
      HapticFeedback.mediumImpact();
      if (user.isKitchen) {
        context.go('/kitchen');
      } else {
        context.go('/tables');
      }
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _error = 'Sai tài khoản hoặc mật khẩu!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedBuilder(
            animation: _bgController,
            builder: (_, __) => Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(
                    -0.5 + _bgController.value,
                    -0.3 + _bgController.value * 0.5,
                  ),
                  radius: 1.5,
                  colors: const [
                    Color(0xFF1A0F00),
                    Color(0xFF0F1117),
                    Color(0xFF050709),
                  ],
                ),
              ),
            ),
          ),

          // Glowing orbs
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: 20, duration: 4.seconds),

          Positioned(
            bottom: -50,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.secondary.withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: -20, duration: 5.seconds),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    _buildLogo(),
                    const SizedBox(height: 48),
                    // Login Card
                    _buildLoginCard(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset('assets/images/app_logo.jpg', fit: BoxFit.cover),
          ),
        )
        .animate()
        .scale(begin: const Offset(0.5, 0.5), duration: 600.ms, curve: Curves.elasticOut)
        .fadeIn(duration: 400.ms),

        const SizedBox(height: 20),

        Text(
          'TramApp',
          style: GoogleFonts.beVietnamPro(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            foreground: Paint()
              ..shader = const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
              ).createShader(const Rect.fromLTWH(0, 0, 200, 50)),
          ),
        )
        .animate(delay: 200.ms)
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.3, end: 0),

        const SizedBox(height: 8),

        Text(
          'Hệ thống quản lý nhà hàng',
          style: GoogleFonts.beVietnamPro(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        )
        .animate(delay: 400.ms)
        .fadeIn(duration: 500.ms),
      ],
    );
  }

  Widget _buildLoginCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.border.withOpacity(0.5),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Đăng nhập',
                  style: GoogleFonts.beVietnamPro(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Nhập thông tin để tiếp tục',
                  style: GoogleFonts.beVietnamPro(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),

                // Username field
                TextFormField(
                  controller: _userCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Tài khoản',
                    prefixIcon: const Icon(Icons.person_outline, color: AppColors.textSecondary, size: 20),
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v?.isEmpty ?? true) ? 'Vui lòng nhập tài khoản' : null,
                ),
                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textSecondary, size: 20),
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleLogin(),
                  validator: (v) => (v?.isEmpty ?? true) ? 'Vui lòng nhập mật khẩu' : null,
                ),

                // Error message
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _error!,
                          style: GoogleFonts.beVietnamPro(color: AppColors.danger, fontSize: 13),
                        ),
                      ],
                    ),
                  ).animate().shakeX(amount: 4, duration: 300.ms),
                ],

                const SizedBox(height: 24),

                // Login button
                SizedBox(
                  height: 52,
                  child: _loading
                    ? Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Đăng nhập',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                ),

                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'v2.0 — Flutter Edition',
                    style: GoogleFonts.beVietnamPro(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
    .animate(delay: 600.ms)
    .fadeIn(duration: 600.ms)
    .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic);
  }
}
