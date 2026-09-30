// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// BỘ MÀU CHUẨN HỆ SINH THÁI TRẠM (TRAM ECOSYSTEM DESIGN SYSTEM v1.1.0)
/// Theo mục 4.1 của BO_QUY_TAC_CHUNG_HE_SINH_THAI_TRAM.md
class TramColors {
  TramColors._();

  // 1. Nhận diện thương hiệu Trạm (Brand & Signature)
  static const Color logoRed = Color(0xFFCB2D2E); // Đỏ cờ nhận diện logo, không tự ý nhuộm toàn UI
  static const Color brandPrimary = Color(0xFF7E2930); // Đỏ mận giao diện chính, đăng nhập, nút chung
  static const Color brandDark = Color(0xFF5C1F24); // Đỏ mận đậm
  static const Color brandSurface = Color(0xFFF6EFDF); // Nền kem ấm đặc trưng Trạm
  static const Color cardSurface = Color(0xFFFFFEF9); // Mặt nền thẻ trắng ngà sáng rõ
  static const Color background = Color(0xFFF8F4EE); // Nền ấm dịu mắt

  // 2. Màu vai trò phân quyền (Role Accents & Surfaces)
  // Chủ Quán (Owner)
  static const Color ownerAccent = Color(0xFF171717); // Đen quyền uy, mạnh mẽ
  static const Color ownerDark = Color(0xFF050505);
  static const Color ownerSurface = Color(0xFFF7F7F5);
  static const Color ownerTint = Color(0xFFEDEBE6);

  // Quản Lý Ca (Manager 1 & Manager 2)
  static const Color managerAccent = Color(0xFF126CC3); // Xanh dương tươi tác nghiệp ca trực
  static const Color managerDark = Color(0xFF095AA8);
  static const Color managerSurface = Color(0xFFF7FAFE);
  static const Color managerTint = Color(0xFFE8F3FE);

  // Nhân Viên (Employee)
  static const Color employeeAccent = Color(0xFF7E2930);
  static const Color employeeSurface = Color(0xFFFFF9F9);

  // 3. Màu trạng thái nghiệp vụ chuẩn (Semantic Status Colors)
  static const Color success = Color(0xFF146A65); // Xanh ngọc đậm (thành công, hoàn tất, bàn trống)
  static const Color successSurface = Color(0xFFE6F4F2);
  static const Color warning = Color(0xFFD97706); // Hổ phách (chờ làm, đặt trước)
  static const Color warningInk = Color(0xFF805214); // Chữ nâu đậm cảnh báo
  static const Color warningSurface = Color(0xFFFBEFD4);
  static const Color danger = Color(0xFFB4232C); // Đỏ nguy hiểm (lỗi, hủy món, hủy bill)
  static const Color dangerSurface = Color(0xFFFDE8E9);
  static const Color info = Color(0xFF1C4E6B); // Xanh thẫm (thông tin, đơn giao)
  static const Color infoSurface = Color(0xFFE3EFF7);

  // 4. Trạng thái phòng bàn KiotViet FnB
  static const Color tableEmpty = Color(0xFF146A65); // Bàn trống: Xanh ngọc
  static const Color tableEmptyBg = Color(0xFFE6F4F2);
  static const Color tableInUse = Color(0xFF7E2930); // Bàn có khách: Đỏ mận
  static const Color tableInUseBg = Color(0xFFFFF0F2);
  static const Color tableReserved = Color(0xFFD97706); // Bàn đặt trước: Vàng hổ phách
  static const Color tableReservedBg = Color(0xFFFBEFD4);

  // 5. Màn hình KDS Bếp/Bar Dark Mode
  static const Color kitchenBg = Color(0xFF0F172A);
  static const Color kitchenCard = Color(0xFF1E293B);
  static const Color kitchenCardBorder = Color(0xFF334155);
  static const Color kitchenAccent = Color(0xFFE8192F);

  // 6. Chữ, viền và đổ bóng
  static const Color textPrimary = Color(0xFF1C1A2D);
  static const Color textSecondary = Color(0xFF5D5B63);
  static const Color border = Color(0xFFD8CFBD);
  static const Color borderLight = Color(0xFFECE5D8);
  static const Color shadow = Color(0x14000000);

  // Backward-compatibility aliases for legacy AppColors
  static const Color primary = brandPrimary;
  static const Color primaryLight = Color(0xFFFBECEE);
  static const Color primaryDark = brandDark;
  static const Color card = cardSurface;
  static const Color cardElevated = Color(0xFFFBF8F2);
  static const Color surface = brandSurface;
  static const Color textDisabled = Color(0xFF9E9CA3);
  static const Color textHint = Color(0xFF9E9CA3);
  static const Color accent = managerAccent;
  static const Color tableEmptyBorder = tableEmpty;
  static const Color tableInUseBorder = tableInUse;
  static const Color successLight = successSurface;
  static const Color warningLight = warningSurface;
  static const Color dangerLight = dangerSurface;
  static const Color infoLight = infoSurface;
  static const Color secondary = managerAccent;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [brandPrimary, brandDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Alias tương thích ngược cho AppColors
typedef AppColors = TramColors;

/// HỆ THỐNG THEME TRẠM (MATERIAL 3)
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => buildTheme(primaryColor: TramColors.brandPrimary, surfaceColor: TramColors.cardSurface);
  static ThemeData get ownerTheme => buildTheme(primaryColor: TramColors.ownerAccent, surfaceColor: TramColors.ownerSurface);
  static ThemeData get managerTheme => buildTheme(primaryColor: TramColors.managerAccent, surfaceColor: TramColors.managerSurface);

  static ThemeData buildTheme({
    required Color primaryColor,
    required Color surfaceColor,
  }) {
    final baseTextTheme = GoogleFonts.beVietnamProTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        onPrimary: Colors.white,
        surface: surfaceColor,
        background: TramColors.background,
        error: TramColors.danger,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: TramColors.background,
      fontFamily: GoogleFonts.beVietnamPro().fontFamily,
      primaryColor: primaryColor,

      // Typography
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(fontWeight: FontWeight.w800, color: TramColors.textPrimary),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700, color: TramColors.textPrimary),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: TramColors.textPrimary),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: TramColors.textPrimary),
        titleMedium: baseTextTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: TramColors.textPrimary),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: TramColors.textPrimary),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: TramColors.textSecondary),
        labelLarge: baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.beVietnamPro(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),

      // Card: Bo góc 16px, viền nhẹ
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: TramColors.borderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // Buttons: Bo góc 12px, cao 52px
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor, width: 1.5),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // Inputs: Bo góc 12px
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TramColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TramColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TramColors.danger),
        ),
        labelStyle: GoogleFonts.beVietnamPro(color: TramColors.textSecondary),
        hintStyle: GoogleFonts.beVietnamPro(color: TramColors.textDisabled),
      ),

      // Dialog: Bo góc 20px
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // BottomSheet: Bo góc 20px
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // Chip
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
    );
  }
}
