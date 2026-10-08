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

  // 7. Bàn chờ thanh toán (đã in tạm tính) – dùng cho chú thích sơ đồ bàn
  static const Color tableAwaitingPayment = Color(0xFF1C4E6B);
  static const Color tableAwaitingPaymentBg = Color(0xFFE3EFF7);

  // 8. Chữ trên nền tối (KDS bếp / dark theme)
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFFA7B1C2);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [brandPrimary, brandDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Alias tương thích ngược cho AppColors
typedef AppColors = TramColors;

/// KHOẢNG CÁCH CHUẨN (bội số 4) – dùng thay cho số "magic" trong padding/SizedBox
class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Vùng chạm tối thiểu theo khuyến nghị Material/Apple (dp)
  static const double minTapTarget = 44;

  /// Mốc chiều rộng bố cục
  static const double tabletBreakpoint = 720;
  static const double wideBreakpoint = 1024;
}

/// BO GÓC CHUẨN
class AppRadius {
  AppRadius._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
}

/// HỆ THỐNG THEME TRẠM (MATERIAL 3)
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => buildTheme(primaryColor: TramColors.brandPrimary, surfaceColor: TramColors.cardSurface);
  static ThemeData get ownerTheme => buildTheme(primaryColor: TramColors.ownerAccent, surfaceColor: TramColors.ownerSurface);
  static ThemeData get managerTheme => buildTheme(primaryColor: TramColors.managerAccent, surfaceColor: TramColors.managerSurface);

  /// Theme tối – dùng cho màn hình Bếp/Bar (KDS) và sẵn sàng cho chế độ tối toàn app.
  static ThemeData get darkTheme => buildTheme(
        primaryColor: TramColors.kitchenAccent,
        surfaceColor: TramColors.kitchenCard,
        brightness: Brightness.dark,
      );

  static ThemeData buildTheme({
    required Color primaryColor,
    required Color surfaceColor,
    Brightness brightness = Brightness.light,
  }) {
    final isDark = brightness == Brightness.dark;
    final textPrimary = isDark ? TramColors.darkTextPrimary : TramColors.textPrimary;
    final textSecondary = isDark ? TramColors.darkTextSecondary : TramColors.textSecondary;
    final scaffoldBg = isDark ? TramColors.kitchenBg : TramColors.background;
    final borderColor = isDark ? TramColors.kitchenCardBorder : TramColors.border;
    final borderLight = isDark ? TramColors.kitchenCardBorder : TramColors.borderLight;
    final inputFill = isDark ? const Color(0xFF111827) : Colors.white;

    final baseTextTheme = GoogleFonts.beVietnamProTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    ).copyWith(
      primary: primaryColor,
      onPrimary: Colors.white,
      secondary: TramColors.managerAccent,
      onSecondary: Colors.white,
      surface: surfaceColor,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: borderColor,
      outlineVariant: borderLight,
      error: TramColors.danger,
      onError: Colors.white,
    );

    TextStyle? tint(TextStyle? s, {FontWeight? w, Color? c}) =>
        s?.copyWith(fontWeight: w, color: c ?? textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      fontFamily: GoogleFonts.beVietnamPro().fontFamily,
      primaryColor: primaryColor,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,

      // Typography – cỡ chữ đủ lớn để đọc ở khoảng cách một cánh tay trên tablet
      textTheme: baseTextTheme.copyWith(
        displayLarge: tint(baseTextTheme.displayLarge, w: FontWeight.w800),
        displayMedium: tint(baseTextTheme.displayMedium, w: FontWeight.w800),
        displaySmall: tint(baseTextTheme.displaySmall, w: FontWeight.w800),
        headlineLarge: tint(baseTextTheme.headlineLarge, w: FontWeight.w700),
        headlineMedium: tint(baseTextTheme.headlineMedium, w: FontWeight.w700),
        headlineSmall: tint(baseTextTheme.headlineSmall, w: FontWeight.w700),
        titleLarge: tint(baseTextTheme.titleLarge, w: FontWeight.w700),
        titleMedium: tint(baseTextTheme.titleMedium, w: FontWeight.w600),
        titleSmall: tint(baseTextTheme.titleSmall, w: FontWeight.w600),
        bodyLarge: tint(baseTextTheme.bodyLarge),
        bodyMedium: tint(baseTextTheme.bodyMedium, c: textSecondary),
        bodySmall: tint(baseTextTheme.bodySmall, c: textSecondary),
        labelLarge: tint(baseTextTheme.labelLarge, w: FontWeight.w600),
        labelMedium: tint(baseTextTheme.labelMedium, w: FontWeight.w600),
        labelSmall: tint(baseTextTheme.labelSmall, w: FontWeight.w600, c: textSecondary),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? TramColors.kitchenCard : primaryColor,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
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
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(color: borderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // Buttons: Bo góc 12px, cao 52px (nút chính của POS – dễ bấm)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE4DED3),
          disabledForegroundColor: isDark ? TramColors.darkTextSecondary : TramColors.textDisabled,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
          textStyle: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
          textStyle: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? textPrimary : primaryColor,
          side: BorderSide(color: isDark ? borderColor : primaryColor, width: 1.5),
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
          textStyle: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? textPrimary : primaryColor,
          minimumSize: const Size(48, AppSpacing.minTapTarget),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
          textStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
        ),
      ),

      // Inputs: Bo góc 12px
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: TramColors.danger),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: TramColors.danger, width: 2),
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        labelStyle: GoogleFonts.beVietnamPro(color: textSecondary),
        floatingLabelStyle: GoogleFonts.beVietnamPro(color: isDark ? textPrimary : primaryColor, fontWeight: FontWeight.w600),
        hintStyle: GoogleFonts.beVietnamPro(color: TramColors.textDisabled),
        errorStyle: GoogleFonts.beVietnamPro(color: TramColors.danger, fontSize: 12),
      ),

      // Dialog: Bo góc 20px
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
        titleTextStyle: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
        contentTextStyle: GoogleFonts.beVietnamPro(fontSize: 14, color: textSecondary, height: 1.45),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      // BottomSheet: Bo góc 20px
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? TramColors.kitchenCard : Colors.white,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: borderColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),

      // SnackBar: nổi, bo góc, chữ rõ ràng
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF334155) : TramColors.textPrimary,
        contentTextStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
        actionTextColor: const Color(0xFFFFD58A),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        elevation: 4,
      ),

      // Chip
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
        side: BorderSide(color: borderLight),
        backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
        selectedColor: isDark ? primaryColor.withValues(alpha: 0.35) : TramColors.primaryLight,
        checkmarkColor: isDark ? Colors.white : primaryColor,
        labelStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary),
        secondaryLabelStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? Colors.white : primaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),

      // Tabs
      tabBarTheme: TabBarThemeData(
        labelColor: isDark ? Colors.white : primaryColor,
        unselectedLabelColor: textSecondary,
        indicatorColor: isDark ? Colors.white : primaryColor,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: borderLight,
        labelStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w500),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        minVerticalPadding: 10,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        titleTextStyle: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
        subtitleTextStyle: GoogleFonts.beVietnamPro(fontSize: 12.5, color: textSecondary),
      ),

      dividerTheme: DividerThemeData(color: borderLight, thickness: 1, space: 1),

      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        textStyle: GoogleFonts.beVietnamPro(fontSize: 14, color: textPrimary),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? TramColors.kitchenCard : surfaceColor,
        surfaceTintColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: TramColors.textPrimary.withValues(alpha: 0.92),
          borderRadius: AppRadius.brSm,
        ),
        textStyle: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.white),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: primaryColor),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryColor : null),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryColor : null),
      ),

      // Floating Action Button: Luôn dùng chữ và icon màu trắng rõ nét
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
        extendedTextStyle: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}
