import 'package:flutter/material.dart';

/// Smart Food Finder palette (approved direction): forest green, warm ivory,
/// appetite coral, warm gold and charcoal, with dark-mode counterparts.
@immutable
class FinderColors {
  final Color forest, onForest, ivory, coral, gold, charcoal, paleGreen, card, muted, success, successBg, warn, warnBg, goldBg, outline;
  const FinderColors._({
    required this.forest,
    required this.onForest,
    required this.ivory,
    required this.coral,
    required this.gold,
    required this.charcoal,
    required this.paleGreen,
    required this.card,
    required this.muted,
    required this.success,
    required this.successBg,
    required this.warn,
    required this.warnBg,
    required this.goldBg,
    required this.outline,
  });

  static const light = FinderColors._(
    forest: Color(0xFF173C32),
    onForest: Color(0xFFFAF7F1),
    ivory: Color(0xFFFAF7F1),
    coral: Color(0xFFF16A46),
    gold: Color(0xFFEABF67),
    charcoal: Color(0xFF242B28),
    paleGreen: Color(0xFFE6F0E7),
    card: Color(0xFFFFFFFF),
    muted: Color(0xFF5E6762),
    success: Color(0xFF1E6B47),
    successBg: Color(0xFFDDEFE2),
    warn: Color(0xFFA9431F),
    warnBg: Color(0xFFFBE5DC),
    goldBg: Color(0xFFF8EBCC),
    outline: Color(0xFFE2DED4),
  );

  static const dark = FinderColors._(
    forest: Color(0xFF1F4A3E),
    onForest: Color(0xFFF2EEE6),
    ivory: Color(0xFF121614),
    coral: Color(0xFFF38A6C),
    gold: Color(0xFFE2C27E),
    charcoal: Color(0xFFF0ECE4),
    paleGreen: Color(0xFF1C2B25),
    card: Color(0xFF1A201D),
    muted: Color(0xFFB4BCB7),
    success: Color(0xFF8FD3AE),
    successBg: Color(0xFF173528),
    warn: Color(0xFFF4A68C),
    warnBg: Color(0xFF3A231B),
    goldBg: Color(0xFF3A3220),
    outline: Color(0xFF2E3833),
  );

  static FinderColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

String rupees(int paise) => paise % 100 == 0 ? '₹${paise ~/ 100}' : '₹${(paise / 100).toStringAsFixed(2)}';
