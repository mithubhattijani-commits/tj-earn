import 'package:flutter/material.dart';

/// Dark premium + gold theme (Jaani, 2 Nov 2026) — matches the TJ Earn
/// promo poster mockup: deep-navy surfaces, gold accents, and gold coin
/// highlights for the "Watch & Earn" rewards look.
class TjEarnTheme {
  /// Primary gold accent (poster gold).
  static const Color gold = Color(0xFFFFD76A);

  /// Deeper gold for filled highlights.
  static const Color goldDeep = Color(0xFF9C7A1F);

  /// Hero gradient stops (balance card): deep navy tones.
  static const Color navyTop = Color(0xFF1B2140);
  static const Color navyBottom = Color(0xFF0B0E22);

  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: navyBottom,
        useMaterial3: true,
      );
}
