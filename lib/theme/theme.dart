import 'package:flutter/material.dart';

/// Design tokens; Material's scheme has no slot for most of them.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.bg,
    required this.card,
    required this.card2,
    required this.line,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.income,
    required this.expense,
  });

  final Color bg;
  final Color card;
  final Color card2;
  final Color line;
  final Color ink;
  final Color muted;

  /// Fill colour for primary actions.
  final Color accent;

  /// Accent used as text or strokes on [bg]; lime is too light for that in light mode.
  final Color accentInk;
  final Color onAccent;
  final Color income;
  final Color expense;

  static const dark = Tokens(
    bg: Color(0xFF0B0B0F),
    card: Color(0xFF16161D),
    card2: Color(0xFF22222B),
    line: Color(0xFF26262F),
    ink: Color(0xFFF4F4F6),
    muted: Color(0xFF8A8A96),
    accent: Color(0xFFC3F25C),
    accentInk: Color(0xFFC3F25C),
    onAccent: Color(0xFF0B0B0F),
    income: Color(0xFF4ADE80),
    expense: Color(0xFFFF6B6B),
  );

  static const light = Tokens(
    bg: Color(0xFFF4F4F1),
    card: Color(0xFFFFFFFF),
    card2: Color(0xFFEDEDE8),
    line: Color(0xFFE4E4DE),
    ink: Color(0xFF111114),
    muted: Color(0xFF75757F),
    accent: Color(0xFFC3F25C),
    accentInk: Color(0xFF4F7A00),
    onAccent: Color(0xFF0B0B0F),
    income: Color(0xFF16A34A),
    expense: Color(0xFFDC2626),
  );

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(Tokens? other, double t) => t < 0.5 || other == null ? this : other;
}

extension TokensX on BuildContext {
  Tokens get tokens => Theme.of(this).extension<Tokens>()!;
}

const gap = 16.0;
const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness b) {
  final t = b == Brightness.dark ? Tokens.dark : Tokens.light;
  final scheme = ColorScheme.fromSeed(seedColor: t.accent, brightness: b).copyWith(
    primary: t.accentInk,
    surface: t.bg,
    onSurface: t.ink,
    surfaceContainerHighest: t.card2,
    surfaceContainerLow: t.card,
    surfaceContainer: t.card,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    extensions: [t],
    splashFactory: NoSplash.splashFactory,
    highlightColor: t.ink.withValues(alpha: 0.04),
  );
  final text = base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink);
  return base.copyWith(
    textTheme: text,
    iconTheme: IconThemeData(color: t.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.line,
    ),
    dialogTheme: DialogThemeData(backgroundColor: t.card, surfaceTintColor: Colors.transparent),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.card2,
      hintStyle: TextStyle(color: t.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: t.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: t.accentInk)),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.card2,
      contentTextStyle: TextStyle(color: t.ink, fontWeight: FontWeight.w500),
      actionTextColor: t.accentInk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: t.line, space: 1),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.card2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    ),
  );
}
