import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Palette ────────────────────────────────────────────────────────────────────
// Warm sage green primary + cream backgrounds = premium organic farm feel
class AppColors {
  // Primary — warm sage green (not clinical forest green)
  static const primary     = Color(0xFF3D6B4F);
  static const primaryLight= Color(0xFF5A8F6A);
  static const primaryDark = Color(0xFF274535);

  // Accent — warm terracotta/amber (replaces jarring orange)
  static const secondary   = Color(0xFFD4845A);
  static const accent      = Color(0xFFC9A96E); // warm gold

  // Backgrounds — warm cream/sand (not cool gray-blue)
  static const background  = Color(0xFFFAF7F2); // warm cream
  static const surface     = Color(0xFFF5F0E8); // warm sand
  static const cardBg      = Color(0xFFFFFFFC); // off-white

  // Text
  static const textPrimary   = Color(0xFF1C2B22); // deep forest
  static const textSecondary = Color(0xFF5C6B5E); // muted sage

  // Status — simplified 2-tone system
  static const success = Color(0xFF3D6B4F); // same as primary
  static const warning = Color(0xFFD4845A); // terracotta
  static const error   = Color(0xFFBF4040); // muted red

  // Shadow — warm brown tint instead of cold black
  static const shadow = Color(0x14603010);
}

// ── Theme ──────────────────────────────────────────────────────────────────────
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary:       AppColors.primary,
      onPrimary:     Colors.white,
      secondary:     AppColors.secondary,
      onSecondary:   Colors.white,
      surface:       AppColors.background,
      onSurface:     AppColors.textPrimary,
      error:         AppColors.error,
      onError:       Colors.white,
    ),
  );

  // Typography: Poppins body + DM Serif Display headings
  final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).copyWith(
    displayLarge:  GoogleFonts.dmSerifDisplay(fontSize: 36, color: AppColors.textPrimary, height: 1.2),
    displayMedium: GoogleFonts.dmSerifDisplay(fontSize: 28, color: AppColors.textPrimary, height: 1.3),
    displaySmall:  GoogleFonts.dmSerifDisplay(fontSize: 22, color: AppColors.textPrimary, height: 1.3),
    headlineLarge: GoogleFonts.dmSerifDisplay(fontSize: 26, color: AppColors.textPrimary),
    headlineMedium:GoogleFonts.dmSerifDisplay(fontSize: 20, color: AppColors.textPrimary),
    headlineSmall: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    titleLarge:    GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleMedium:   GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleSmall:    GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
    bodyLarge:     GoogleFonts.poppins(fontSize: 15, color: AppColors.textPrimary),
    bodyMedium:    GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
    bodySmall:     GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
    labelLarge:    GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    labelMedium:   GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
    labelSmall:    GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
  );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.background,

    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.poppins(
        fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.25), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.2), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      labelStyle: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 14),
      hintStyle: GoogleFonts.poppins(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 14),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: AppColors.cardBg,
      shadowColor: AppColors.shadow,
      surfaceTintColor: Colors.transparent,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.cardBg,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary.withValues(alpha: 0.6),
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 11),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cardBg,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primary, size: 22);
        }
        return IconThemeData(color: AppColors.textSecondary.withValues(alpha: 0.6), size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary);
        }
        return GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.6));
      }),
    ),

    dividerTheme: DividerThemeData(
      color: AppColors.textSecondary.withValues(alpha: 0.1),
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.poppins(
          fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      contentTextStyle: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      // No shape override — lets extended FABs use their natural pill/stadium shape
    ),
  );
}
