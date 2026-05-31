import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Color Palette
  static const Color backgroundStart = Color(0xFF090714);
  static const Color backgroundEnd = Color(0xFF0E0C20);
  static const Color primaryAccent = Color(0xFF7B61FF);
  static const Color secondaryAccent = Color(0xFF9E8BFF);
  static const Color cardBackground = Color(0xFF16132D);
  static const Color inputBackground = Color(0xFF1E1A3A);
  
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8E8C9A);
  static const Color textMuted = Color(0xFF5E5C6A);
  
  static const Color success = Color(0xFF2ECC71);
  static const Color danger = Color(0xFFE74C3C);
  static const Color warning = Color(0xFFF1C40F);

  // Gradient definitions
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [backgroundStart, backgroundEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryAccent, Color(0xFF5236FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ThemeData configuration
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent, // Controlled by Gradient in Scaffold wrapper
      primaryColor: primaryAccent,
      cardColor: cardBackground,
      hintColor: textSecondary,
      textTheme: TextTheme(
        headlineLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: textSecondary,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textMuted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: GoogleFonts.inter(color: textSecondary, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: textPrimary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2E2A4E), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryAccent, width: 1.5),
        ),
      ),
      buttonTheme: const ButtonThemeData(
        buttonColor: primaryAccent,
        textTheme: ButtonTextTheme.primary,
      ),
    );
  }
}
