import 'package:flutter/material.dart';

/// Brand colours. These are the few values that genuinely mean the same thing
/// in both themes — the brand purple, and the semantic status colours.
///
/// Everything that has to change between light and dark lives in [AppPalette]
/// instead, so no widget decides for itself what "grey text" or "a border"
/// looks like.
class AppColors {
  static const primary = Color(0xFF6C5CE7);
  static const primarySoft = Color(0xFFEDE9FF);
  static const background = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111827);

  /// Kept so older call sites still compile. New code should read
  /// `context.palette.textSecondary`, which has enough contrast in both
  /// themes; this fixed grey only does in light mode.
  @Deprecated('Use context.palette.textSecondary')
  static const muted = Color(0xFF6B7280);

  static const danger = Color(0xFFE5484D);
  static const success = Color(0xFF30A46C);
  static const amber = Color(0xFFE8A33D);
  static const blue = Color(0xFF3B82F6);
}

/// Every colour that differs between light and dark, in one place.
///
/// Read it as `context.palette.…`. Adding a surface or a state here, rather
/// than writing `Colors.black.withValues(...)` at the call site, is what keeps
/// dark mode correct when a new screen is added.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceSunken,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.border,
    required this.divider,
    required this.hover,
    required this.selected,
    required this.gridLine,
    required this.danger,
    required this.success,
    required this.warning,
    required this.info,
  });

  final Brightness brightness;

  /// The page behind everything.
  final Color background;

  /// Cards, sheets, dialogs, menus.
  final Color surface;

  /// A panel that sits on [background] but reads as a container — a board
  /// list column, a filter chip.
  final Color surfaceVariant;

  /// A well inside a [surface], such as an unscheduled card on the calendar.
  final Color surfaceSunken;

  final Color textPrimary;

  /// Secondary and meta text. Checked to clear 4.5:1 against both
  /// [background] and [surface] in its own theme.
  final Color textSecondary;
  final Color textDisabled;

  final Color border;
  final Color divider;

  /// Hover and focus wash, and the fill behind a selected row.
  final Color hover;
  final Color selected;

  /// The hour and day rules in the calendar grid. Lighter than [divider]
  /// because they repeat 24 times down the screen.
  final Color gridLine;

  final Color danger;
  final Color success;
  final Color warning;
  final Color info;

  bool get isDark => brightness == Brightness.dark;

  /// A tint of [color] to sit behind text of that same colour — the category
  /// chip, the calendar event, the holiday pill.
  ///
  /// Dark mode needs a stronger tint than light to read as a surface at all,
  /// which is the single most common dark-mode bug in this kind of UI.
  Color tint(Color color) => color.withValues(alpha: isDark ? 0.22 : 0.12);

  /// A readable version of a user-chosen category colour on this theme's
  /// surfaces. Saturated colours picked in light mode go muddy on dark, so
  /// they are lifted toward white instead of used raw.
  Color onTint(Color color) {
    if (!isDark) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(hsl.lightness.clamp(0.0, 1.0) < 0.62 ? 0.72 : hsl.lightness).toColor();
  }

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEDEFF3),
    surfaceSunken: Color(0xFFF4F5F7),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF5A6372),
    textDisabled: Color(0xFF9CA3AF),
    border: Color(0xFFE2E5EA),
    divider: Color(0xFFE8EAEE),
    hover: Color(0x0D000000),
    selected: Color(0x146C5CE7),
    gridLine: Color(0xFFE8EAEE),
    danger: Color(0xFFD7373C),
    success: Color(0xFF1F8A57),
    warning: Color(0xFFB4741D),
    info: Color(0xFF2563EB),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0F1014),
    surface: Color(0xFF1C1D23),
    surfaceVariant: Color(0xFF17181D),
    surfaceSunken: Color(0xFF121317),
    textPrimary: Color(0xFFF2F3F5),
    // 6.3:1 on the card surface, 10:1 on the page background.
    textSecondary: Color(0xFF9CA3B0),
    textDisabled: Color(0xFF6B7280),
    border: Color(0xFF2E3039),
    divider: Color(0xFF26282F),
    hover: Color(0x14FFFFFF),
    selected: Color(0x2E6C5CE7),
    gridLine: Color(0xFF24262D),
    danger: Color(0xFFFF6369),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFF5B952),
    info: Color(0xFF6AA5FF),
  );

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceSunken,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? border,
    Color? divider,
    Color? hover,
    Color? selected,
    Color? gridLine,
    Color? danger,
    Color? success,
    Color? warning,
    Color? info,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      hover: hover ?? this.hover,
      selected: selected ?? this.selected,
      gridLine: gridLine ?? this.gridLine,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textDisabled: c(textDisabled, other.textDisabled),
      border: c(border, other.border),
      divider: c(divider, other.divider),
      hover: c(hover, other.hover),
      selected: c(selected, other.selected),
      gridLine: c(gridLine, other.gridLine),
      danger: c(danger, other.danger),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      info: c(info, other.info),
    );
  }
}

/// `context.palette.textSecondary` — the one way a widget should ask for a
/// colour that depends on the theme.
extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ??
      (Theme.of(this).brightness == Brightness.dark ? AppPalette.dark : AppPalette.light);
}

/// Same lookup from a [ThemeData], for the few places that already hold one.
extension AppPaletteTheme on ThemeData {
  AppPalette get palette =>
      extension<AppPalette>() ??
      (brightness == Brightness.dark ? AppPalette.dark : AppPalette.light);
}

ThemeData buildAppTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final palette = isDark ? AppPalette.dark : AppPalette.light;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
    surface: palette.surface,
    onSurface: palette.textPrimary,
    error: palette.danger,
    outline: palette.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [palette],
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.surface,
    dividerColor: palette.divider,
    dividerTheme: DividerThemeData(color: palette.divider, space: 1, thickness: 1),
    hoverColor: palette.hover,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: palette.textPrimary,
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    // Menus and dropdowns default to a light surface even under a dark theme
    // when they are left unset, which is the white-dropdown-in-dark-mode bug.
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: palette.textPrimary, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(color: palette.textPrimary),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? palette.surfaceVariant : AppColors.ink,
      contentTextStyle: TextStyle(color: isDark ? palette.textPrimary : Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? palette.surfaceVariant : AppColors.ink,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      textStyle: TextStyle(color: isDark ? palette.textPrimary : Colors.white, fontSize: 12),
    ),
    listTileTheme: ListTileThemeData(
      textColor: palette.textPrimary,
      iconColor: palette.textSecondary,
      selectedColor: AppColors.primary,
      selectedTileColor: palette.selected,
    ),
    iconTheme: IconThemeData(color: palette.textSecondary),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: palette.border, width: 1.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return palette.textDisabled;
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(Colors.white),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(palette.border),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? palette.surfaceVariant : palette.surface,
      hintStyle: TextStyle(color: palette.textDisabled),
      labelStyle: TextStyle(color: palette.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.divider),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: palette.surfaceVariant,
        disabledForegroundColor: palette.textDisabled,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: palette.textDisabled,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: palette.border),
        foregroundColor: palette.textPrimary,
        disabledForegroundColor: palette.textDisabled,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
          bodyColor: palette.textPrimary,
          displayColor: palette.textPrimary,
        ),
  );
}
