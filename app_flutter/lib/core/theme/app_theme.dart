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

  // 7. Bàn chờ thanh toán (đã in tạm tính) – tím, đồng bộ với web
  //    (web/app/globals.css: --table-awaiting / --table-awaiting-bg).
  static const Color tableAwaitingPayment = Color(0xFF5B3FB0);
  static const Color tableAwaitingPaymentBg = Color(0xFFEEE9FA);

  // 7b. Trạng thái bàn ở chế độ tối: [màu nhận diện] đủ đậm cho chữ trắng
  //     (≥ 4.5:1) và nổi trên nền thẻ tối; [Ink] = chữ màu trạng thái trên nền tối.
  static const Color tableEmptyDark = Color(0xFF1B8279);
  static const Color tableEmptyInkDark = Color(0xFF5CC8BE);
  static const Color tableInUseDark = Color(0xFFC0505A);
  static const Color tableInUseBgDark = Color(0xFF3B2226);
  static const Color tableInUseInkDark = Color(0xFFF0A8AE);
  static const Color tableAwaitingPaymentDark = Color(0xFF7B5FD0);
  static const Color tableAwaitingPaymentBgDark = Color(0xFF2A2240); // = web dark --table-awaiting-bg
  static const Color tableAwaitingPaymentInkDark = Color(0xFFB39DF2); // = web dark --table-awaiting
  static const Color tableReservedDark = Color(0xFFA8650F);
  static const Color tableReservedBgDark = Color(0xFF3A2C12);
  static const Color tableReservedInkDark = Color(0xFFF6C26B);

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

/// TOKEN MÀU THEO CHẾ ĐỘ SÁNG/TỐI.
///
/// `TramColors` là hằng số (const) chỉ đúng cho giao diện sáng. Màn hình cần
/// hỗ trợ chế độ tối dùng `context.tc.<token>` – giá trị tự đổi theo theme.
@immutable
class TramTokens extends ThemeExtension<TramTokens> {
  const TramTokens({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.textDisabled,
    required this.card,
    required this.cardElevated,
    required this.background,
    required this.surface,
    required this.border,
    required this.borderLight,
    required this.success,
    required this.successLight,
    required this.warning,
    required this.warningInk,
    required this.warningLight,
    required this.danger,
    required this.dangerLight,
    required this.info,
    required this.infoLight,
    required this.shadow,
  });

  /// Màu thương hiệu (nền nút, icon nhấn mạnh).
  final Color primary;

  /// Chữ nhấn mạnh màu thương hiệu (đậm ở chế độ sáng, sáng ở chế độ tối).
  final Color primaryDark;

  /// Nền nhạt màu thương hiệu (chip chọn, badge).
  final Color primaryLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color textDisabled;

  /// Nền thẻ / bề mặt chính (thay cho Colors.white).
  final Color card;

  /// Nền phụ hơi khác thẻ (ô nhóm, dòng xen kẽ).
  final Color cardElevated;
  final Color background;

  /// Nền kem đặc trưng Trạm.
  final Color surface;
  final Color border;
  final Color borderLight;
  final Color success;
  final Color successLight;
  final Color warning;
  final Color warningInk;
  final Color warningLight;
  final Color danger;
  final Color dangerLight;
  final Color info;
  final Color infoLight;
  final Color shadow;

  static const TramTokens light = TramTokens(
    primary: TramColors.brandPrimary,
    primaryDark: TramColors.brandDark,
    primaryLight: TramColors.primaryLight,
    textPrimary: TramColors.textPrimary,
    textSecondary: TramColors.textSecondary,
    textHint: TramColors.textHint,
    textDisabled: TramColors.textDisabled,
    card: TramColors.cardSurface,
    cardElevated: TramColors.cardElevated,
    background: TramColors.background,
    surface: TramColors.brandSurface,
    border: TramColors.border,
    borderLight: TramColors.borderLight,
    success: TramColors.success,
    successLight: TramColors.successSurface,
    warning: TramColors.warning,
    warningInk: TramColors.warningInk,
    warningLight: TramColors.warningSurface,
    danger: TramColors.danger,
    dangerLight: TramColors.dangerSurface,
    info: TramColors.info,
    infoLight: TramColors.infoSurface,
    shadow: TramColors.shadow,
  );

  /// Bảng màu tối: nền than ấm, màu trạng thái được làm sáng để đạt tương phản
  /// ≥ 3:1 trên nền tối nhưng vẫn đủ đậm cho chữ trắng trên nút.
  static const TramTokens dark = TramTokens(
    primary: Color(0xFFC0505A),
    primaryDark: Color(0xFFF0A8AE),
    primaryLight: Color(0xFF3B2226),
    textPrimary: Color(0xFFF1EEF0),
    textSecondary: Color(0xFFB8B2BC),
    textHint: Color(0xFF8A848F),
    textDisabled: Color(0xFF6E6973),
    card: Color(0xFF1F1E23),
    cardElevated: Color(0xFF28272D),
    background: Color(0xFF151418),
    surface: Color(0xFF2B2629),
    border: Color(0xFF45414B),
    borderLight: Color(0xFF322F37),
    success: Color(0xFF1F8F86),
    successLight: Color(0xFF15302D),
    warning: Color(0xFFE08A1A),
    warningInk: Color(0xFFF6C26B),
    warningLight: Color(0xFF3A2C12),
    danger: Color(0xFFE5484D),
    dangerLight: Color(0xFF3D1C20),
    info: Color(0xFF3D8BC0),
    infoLight: Color(0xFF162A3A),
    shadow: Color(0x40000000),
  );

  /// Chuyển một màu nền nhạt sang nền tối cùng tông (giữ hue, giảm bão hoà).
  static Color darkTint(Color light, double lightness) {
    final hsl = HSLColor.fromColor(light);
    if (hsl.saturation < 0.08) {
      return HSLColor.fromAHSL(light.a, 260, 0.06, lightness - 0.04).toColor();
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.0, 0.38))
        .withLightness(lightness)
        .toColor();
  }

  @override
  TramTokens copyWith({Color? primary, Color? card, Color? background}) => TramTokens(
        primary: primary ?? this.primary,
        primaryDark: primaryDark,
        primaryLight: primaryLight,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textHint: textHint,
        textDisabled: textDisabled,
        card: card ?? this.card,
        cardElevated: cardElevated,
        background: background ?? this.background,
        surface: surface,
        border: border,
        borderLight: borderLight,
        success: success,
        successLight: successLight,
        warning: warning,
        warningInk: warningInk,
        warningLight: warningLight,
        danger: danger,
        dangerLight: dangerLight,
        info: info,
        infoLight: infoLight,
        shadow: shadow,
      );

  @override
  TramTokens lerp(ThemeExtension<TramTokens>? other, double t) {
    if (other is! TramTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TramTokens(
      primary: l(primary, other.primary),
      primaryDark: l(primaryDark, other.primaryDark),
      primaryLight: l(primaryLight, other.primaryLight),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textHint: l(textHint, other.textHint),
      textDisabled: l(textDisabled, other.textDisabled),
      card: l(card, other.card),
      cardElevated: l(cardElevated, other.cardElevated),
      background: l(background, other.background),
      surface: l(surface, other.surface),
      border: l(border, other.border),
      borderLight: l(borderLight, other.borderLight),
      success: l(success, other.success),
      successLight: l(successLight, other.successLight),
      warning: l(warning, other.warning),
      warningInk: l(warningInk, other.warningInk),
      warningLight: l(warningLight, other.warningLight),
      danger: l(danger, other.danger),
      dangerLight: l(dangerLight, other.dangerLight),
      info: l(info, other.info),
      infoLight: l(infoLight, other.infoLight),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// Truy cập nhanh token màu theo theme hiện tại: `context.tc.textPrimary`.
extension TramThemeContext on BuildContext {
  TramTokens get tc => Theme.of(this).extension<TramTokens>() ?? TramTokens.light;
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Nền nhạt có sắc màu (vd. `Colors.amber.shade50`): giữ nguyên ở chế độ sáng,
  /// chuyển thành nền tối cùng tông màu ở chế độ tối để chữ sáng vẫn đọc rõ.
  Color bg(Color light) => isDarkMode ? TramTokens.darkTint(light, 0.17) : light;

  /// Viền nhạt có sắc màu (vd. `Colors.amber.shade200`) – bản tối hơi sáng hơn nền.
  Color line(Color light) => isDarkMode ? TramTokens.darkTint(light, 0.32) : light;

  /// Chữ/icon đậm có sắc màu (vd. `Colors.green.shade800`): giữ nguyên ở chế độ
  /// sáng, làm sáng lên ở chế độ tối để đạt tương phản trên nền tối.
  Color ink(Color light) {
    if (!isDarkMode) return light;
    final hsl = HSLColor.fromColor(light);
    return hsl.lightness >= 0.7 ? light : hsl.withLightness(0.74).toColor();
  }
}

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

  /// Theme tối toàn app (chế độ tối do người dùng chọn trong Cài đặt giao diện).
  static ThemeData get appDarkTheme => buildTheme(
        primaryColor: TramTokens.dark.primary,
        surfaceColor: TramTokens.dark.card,
        brightness: Brightness.dark,
      );

  /// Theme tối riêng cho màn hình Bếp/Bar (KDS) – nền slate, nhấn đỏ tươi.
  static ThemeData get darkTheme => buildTheme(
        primaryColor: TramColors.kitchenAccent,
        surfaceColor: TramColors.kitchenCard,
        brightness: Brightness.dark,
        tokens: TramTokens.dark.copyWith(
          primary: TramColors.kitchenAccent,
          card: TramColors.kitchenCard,
          background: TramColors.kitchenBg,
        ),
        scaffoldOverride: TramColors.kitchenBg,
        borderOverride: TramColors.kitchenCardBorder,
      );

  static ThemeData buildTheme({
    required Color primaryColor,
    required Color surfaceColor,
    Brightness brightness = Brightness.light,
    TramTokens? tokens,
    Color? scaffoldOverride,
    Color? borderOverride,
  }) {
    final isDark = brightness == Brightness.dark;
    final t = tokens ?? (isDark ? TramTokens.dark : TramTokens.light);
    final textPrimary = t.textPrimary;
    final textSecondary = t.textSecondary;
    final scaffoldBg = scaffoldOverride ?? t.background;
    final borderColor = borderOverride ?? t.border;
    final borderLight = borderOverride ?? t.borderLight;
    final inputFill = isDark ? (scaffoldOverride ?? t.background) : Colors.white;
    final darkElevated = isDark ? t.cardElevated : Colors.white;

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
      error: t.danger,
      onError: Colors.white,
      surfaceContainerLowest: isDark ? t.background : Colors.white,
      surfaceContainerLow: isDark ? t.card : TramColors.cardSurface,
      surfaceContainer: t.cardElevated,
      surfaceContainerHigh: isDark ? t.cardElevated : TramColors.borderLight,
      surfaceContainerHighest: isDark ? t.border : TramColors.border,
      primaryContainer: t.primaryLight,
      onPrimaryContainer: t.primaryDark,
      errorContainer: t.dangerLight,
      onErrorContainer: isDark ? const Color(0xFFFFB4B7) : TramColors.danger,
    );

    TextStyle? tint(TextStyle? s, {FontWeight? w, Color? c}) =>
        s?.copyWith(fontWeight: w, color: c ?? textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: <ThemeExtension<dynamic>>[t],
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
        backgroundColor: isDark ? t.card : primaryColor,
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
          disabledBackgroundColor: isDark ? t.border : const Color(0xFFE4DED3),
          disabledForegroundColor: isDark ? t.textSecondary : TramColors.textDisabled,
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
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: t.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: t.danger, width: 2),
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        labelStyle: GoogleFonts.beVietnamPro(color: textSecondary),
        floatingLabelStyle: GoogleFonts.beVietnamPro(color: isDark ? textPrimary : primaryColor, fontWeight: FontWeight.w600),
        hintStyle: GoogleFonts.beVietnamPro(color: isDark ? t.textHint : TramColors.textDisabled),
        errorStyle: GoogleFonts.beVietnamPro(color: t.danger, fontSize: 12),
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
        backgroundColor: isDark ? surfaceColor : Colors.white,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: borderColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),

      // SnackBar: nổi, bo góc, chữ rõ ràng
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? t.border : TramColors.textPrimary,
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
        backgroundColor: darkElevated,
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
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: (isDark ? t.border : TramColors.textPrimary).withValues(alpha: 0.95),
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

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryColor : null),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceColor,
        selectedIconTheme: IconThemeData(color: isDark ? Colors.white : primaryColor),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        indicatorColor: t.primaryLight,
        selectedLabelTextStyle: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white : primaryColor),
        unselectedLabelTextStyle: GoogleFonts.beVietnamPro(fontSize: 12, color: textSecondary),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.primaryLight,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: isDark ? Colors.white : primaryColor,
        unselectedItemColor: textSecondary,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? t.primaryLight : null),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? (isDark ? Colors.white : primaryColor) : textPrimary),
        ),
      ),

      expansionTileTheme: ExpansionTileThemeData(
        iconColor: textSecondary,
        collapsedIconColor: textSecondary,
        textColor: textPrimary,
        collapsedTextColor: textPrimary,
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surfaceColor),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: primaryColor,
        headerForegroundColor: Colors.white,
      ),

      timePickerTheme: TimePickerThemeData(backgroundColor: surfaceColor),

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
