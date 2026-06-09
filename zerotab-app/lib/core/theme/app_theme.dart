import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Design tokens — ZeroTab 11/10 Premium System ──────────

class AppColors {
  // ── Background scale — purple-warm near-black ──
  // Never pure black — the violet warmth makes surfaces feel alive
  static const bgVoid   = Color(0xFF080710);  // void — deepest
  static const bg       = Color(0xFF0C0B17);  // base page background
  static const bg2      = Color(0xFF121020);  // raised surface / phone bg
  static const bg3      = Color(0xFF18162C);  // card / float
  static const bg4      = Color(0xFF201E38);  // elevated card / hover / input

  // ── Borders ──
  static const border   = Color(0x0FFFFFFF);  // ~6% white
  static const border2  = Color(0x1CFFFFFF);  // ~11% white

  // ── Text ──
  static const text     = Color(0xFFF2F0FC);  // primary — slightly violet-white
  static const text2    = Color(0xFFA09CB8);  // secondary
  static const text3    = Color(0xFF5E5A75);  // tertiary / labels

  // ── Brand / Primary ──
  // Shifted warmer vs old #7B6FFF → more commanding violet authority
  static const accent   = Color(0xFF7B5FFF);  // primary CTA & brand
  static const accent2  = Color(0xFF9D8FFF);  // labels / soft accent
  static const accentSoft = Color(0x147B5FFF); // ~8% accent fill

  // ── AI / Insight — teal is exclusively reserved for AI ──
  static const teal     = Color(0xFF00C4A8);
  static const tealSoft = Color(0x1400C4A8);  // ~8%

  // ── Semantic ──
  // Gold for debt/warning — empowerment framing, not anxiety-red
  static const gold     = Color(0xFFE8A422);
  static const goldSoft = Color(0x14E8A422);

  // Green for positive financial momentum
  static const green    = Color(0xFF1EBF7A);
  static const greenSoft = Color(0x141EBF7A);

  // Red only for true errors/failures — not debt
  static const red      = Color(0xFFE04A3F);
  static const redSoft  = Color(0x14E04A3F);

  // Coral — secondary alert
  static const coral    = Color(0xFFFF6B5B);
  static const coralSoft = Color(0x14FF6B5B);

  // ── Data-viz / asset-class series ──
  // A deliberate, harmonious categorical palette defined ONCE. Charts and
  // asset-class UI read these so no screen ever invents its own series
  // colours (this is what kills the foreign blue #3B82F6 / orange #FFAA00).
  static const dataStocks    = accent;            // violet
  static const dataMF        = teal;              // teal
  static const dataETF       = Color(0xFF4F9DF7); // calm periwinkle-blue (in-palette)
  static const dataCommodity = gold;              // gold
  static const dataOther     = Color(0xFF8C88A8); // muted lavender-grey
  static const dataPalette   = <Color>[
    dataStocks, dataMF, dataETF, dataCommodity, coral, dataOther,
  ];

  // ── Net-worth card gradient ──
  static const nwGrad1  = Color(0xFF130F2E);
  static const nwGrad2  = Color(0xFF0C0A1E);

  // Legacy aliases (keep for backwards compat)
  static const amber     = gold;
  static const amberSoft = goldSoft;
  static const pink      = Color(0xFFFF6B9D);
  static const pinkSoft  = Color(0x14FF6B9D);
}

class AppRadius {
  static const double xs   = 6;
  static const double sm   = 10;
  static const double md   = 12;   // chips/buttons
  static const double lg   = 16;   // inner cards
  static const double xl   = 20;   // standard cards
  static const double xxl  = 24;   // hero cards
  static const double pill = 44;   // pill shapes
}

class AppSpacing {
  static const double sp4  = 4;
  static const double sp8  = 8;
  static const double sp12 = 12;
  static const double sp16 = 16;
  static const double sp20 = 20;   // screen edge margin
  static const double sp24 = 24;   // section gaps
  static const double sp32 = 32;
  static const double sp40 = 40;
}

// ── ThemeData ─────────────────────────────────────────────

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary:     AppColors.accent,
        secondary:   AppColors.teal,
        surface:     AppColors.bg2,
        error:       AppColors.red,
        onPrimary:   Colors.white,
        onSecondary: Colors.white,
        onSurface:   AppColors.text,
        onError:     Colors.white,
      ),
      textTheme: _buildTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.text2),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xF4121020),
        selectedItemColor: AppColors.accent2,
        unselectedItemColor: AppColors.text3,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: AppColors.bg3,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg3,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        hintStyle: const TextStyle(
          fontFamily: 'DMSans',
          color: AppColors.text3,
          fontSize: 15,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border2),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bg3,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(
          color: AppColors.text2,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    final base = const TextTheme(
      // ── Display — net worth hero numbers ──
      // Tight -2px tracking creates the institutional Bloomberg-terminal feel
      displayLarge: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 48,
        fontWeight: FontWeight.w700,
        letterSpacing: -2.0,
        color: AppColors.text,
        height: 1.0,
      ),
      displayMedium: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
        color: AppColors.text,
        height: 1.0,
      ),
      // ── Headlines ──
      headlineLarge: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: AppColors.text,
        height: 1.2,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: AppColors.text,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: AppColors.text,
      ),
      // ── Titles ──
      titleLarge: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.text,
      ),
      titleMedium: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.text,
      ),
      titleSmall: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.text,
      ),
      // ── Body ──
      bodyLarge: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.text2,
        height: 1.6,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.text2,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.text3,
        height: 1.4,
      ),
      // ── Labels ──
      labelLarge: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.text2,
        letterSpacing: 0.08,
      ),
      labelMedium: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.text3,
        letterSpacing: 0.08,
      ),
      labelSmall: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: AppColors.text3,
        letterSpacing: 0.10,
      ),
    );

    return GoogleFonts.dmSansTextTheme(base).copyWith(
      displayLarge: GoogleFonts.dmSans(textStyle: base.displayLarge),
      displayMedium: GoogleFonts.dmSans(textStyle: base.displayMedium),
      headlineLarge: GoogleFonts.dmSans(textStyle: base.headlineLarge),
      headlineMedium: GoogleFonts.dmSans(textStyle: base.headlineMedium),
      headlineSmall: GoogleFonts.dmSans(textStyle: base.headlineSmall),
      titleLarge: GoogleFonts.dmSans(textStyle: base.titleLarge),
      titleMedium: GoogleFonts.dmSans(textStyle: base.titleMedium),
      titleSmall: GoogleFonts.dmSans(textStyle: base.titleSmall),
      bodyLarge: GoogleFonts.dmSans(textStyle: base.bodyLarge),
      bodyMedium: GoogleFonts.dmSans(textStyle: base.bodyMedium),
      bodySmall: GoogleFonts.dmSans(textStyle: base.bodySmall),
      labelLarge: GoogleFonts.dmSans(textStyle: base.labelLarge),
      labelMedium: GoogleFonts.dmSans(textStyle: base.labelMedium),
      labelSmall: GoogleFonts.dmSans(textStyle: base.labelSmall),
    );
  }
}

// ── Text style helpers ────────────────────────────────────
extension AppTextStyles on BuildContext {
  TextStyle get displayStyle  => Theme.of(this).textTheme.displayLarge!;
  TextStyle get display2Style => Theme.of(this).textTheme.displayMedium!;
  TextStyle get h1Style       => Theme.of(this).textTheme.headlineLarge!;
  TextStyle get h2Style       => Theme.of(this).textTheme.headlineMedium!;
  TextStyle get h3Style       => Theme.of(this).textTheme.headlineSmall!;
  TextStyle get bodyStyle     => Theme.of(this).textTheme.bodyLarge!;
  TextStyle get body2Style    => Theme.of(this).textTheme.bodyMedium!;
  TextStyle get captionStyle  => Theme.of(this).textTheme.bodySmall!;
  TextStyle get labelStyle    => Theme.of(this).textTheme.labelMedium!;

  // DM Mono for IDs, tickers, XIRR, codes — tabular+lining so digits never shift
  TextStyle monoStyle({
    double fontSize = 13,
    Color color = AppColors.text,
    FontWeight weight = FontWeight.w500,
  }) =>
    GoogleFonts.dmMono(
      fontSize: fontSize,
      color: color,
      letterSpacing: 0.2,
      fontWeight: weight,
      fontFeatures: const [FontFeature.tabularFigures(), FontFeature.liningFigures()],
    );

  // Money — DM Sans with tabular + lining figures. EVERY rupee amount routes
  // through this so columns align and numbers never jitter as they animate.
  TextStyle money({
    double fontSize = 15,
    Color color = AppColors.text,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = -0.3,
  }) =>
    GoogleFonts.dmSans(
      fontSize: fontSize,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures(), FontFeature.liningFigures()],
    );
}

// ── Common decorations ────────────────────────────────────
class AppDecorations {
  /// Standard card decoration
  static BoxDecoration card({Color? color, double radius = AppRadius.xl}) =>
    BoxDecoration(
      color: color ?? AppColors.bg3,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border, width: 1),
    );

  /// Accent gradient card (net-worth, hero sections)
  static BoxDecoration accentCard({double radius = AppRadius.xxl}) =>
    BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.nwGrad1, AppColors.nwGrad2],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Color(0x337B5FFF), width: 1),
    );

  /// AI insight teal card
  static BoxDecoration insightCard({double radius = AppRadius.xxl}) =>
    BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0C1C19), Color(0xFF090E0D)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Color(0x3300C4A8), width: 1),
    );

  /// Net-worth hero gradient (home hero card)
  static BoxDecoration heroCard({double radius = AppRadius.xxl}) =>
    BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
        colors: [Color(0xFF130F2E), Color(0xFF0F0D21), Color(0xFF0C0A1E)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x2E7B5FFF)),
    );

  /// Settle-up "you're owed" — derived from green
  static BoxDecoration owedCard({double radius = AppRadius.xxl}) =>
    BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF0C1F16), Color(0xFF08100C)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x3D1EBF7A)),
    );

  /// Settle-up "you owe" — derived from red
  static BoxDecoration oweCard({double radius = AppRadius.xxl}) =>
    BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF21100E), Color(0xFF130807)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x3DE04A3F)),
    );

  /// Icon container — colored soft bg
  static BoxDecoration iconContainer(Color color, {double radius = AppRadius.md}) =>
    BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(radius),
    );
}
