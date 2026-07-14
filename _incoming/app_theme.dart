// lib/ui/app_theme.dart
//
// FILE 12 — "Quiet Luxury" design system. One source of truth for color,
// space, stroke, and type. No widget in the app declares a raw hex or a
// magic padding: it references these tokens or it is wrong.
//
// Design position:
//  - Obsidian canvas (0xFF111111): true-black-adjacent for OLED power
//    draw without the smearing artifacts of pure #000 on LTPO panels.
//  - Monochrome by default. Color is INFORMATION, not decoration: exactly
//    two accents exist (emerald = verified-safe, amber = hardware
//    warning), and they may only appear as 1–2 px indicator strokes —
//    never as fills, never as text blocks, never as gradients.
//  - Space is the hierarchy. The 8 px grid is law; emphasis comes from
//    negative space and weight, not from boxes and shadows.

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Color tokens
// ---------------------------------------------------------------------------

abstract final class AuraColors {
  /// Canvas.
  static const Color obsidian = Color(0xFF111111);

  /// Raised surface (cards) — one perceptual step above canvas. Elevation
  /// through luminance, never through shadow.
  static const Color carbon = Color(0xFF181818);

  /// Primary typography.
  static const Color type = Color(0xFFFFFFFF);

  /// Secondary typography — 70% white.
  static const Color typeDim = Color(0xB3FFFFFF);

  /// Tertiary / disabled typography — 40% white.
  static const Color typeFaint = Color(0x66FFFFFF);

  /// Structural borders and labels.
  static const Color slate = Color(0xFF777777);

  /// Sub-structural hairlines (25% slate) — row separators.
  static const Color hairline = Color(0x40777777);

  /// Operational accent: verified-safe states (compute eligible,
  /// secure mesh). Indicator strokes only.
  static const Color emerald = Color(0xFF2FBF71);

  /// Operational accent: hardware warnings (thermal, power, network
  /// trust). Indicator strokes only.
  static const Color amber = Color(0xFFD9A441);

  /// Scrim for blocking transition overlays (80% obsidian).
  static const Color scrim = Color(0xCC111111);
}

// ---------------------------------------------------------------------------
// Space + stroke tokens (the 8 px grid)
// ---------------------------------------------------------------------------

abstract final class AuraSpace {
  static const double s1 = 8;
  static const double s2 = 16;
  static const double s3 = 24;
  static const double s4 = 32;
  static const double s5 = 48;
}

abstract final class AuraStroke {
  /// Hairline separators inside content.
  static const double hair = 0.5;

  /// Structural borders (the spec's stark 1 px slate).
  static const double line = 1.0;

  /// Accent indicator strokes — the ONLY sanctioned use of color.
  static const double indicator = 2.0;
}

// ---------------------------------------------------------------------------
// Type scale
// ---------------------------------------------------------------------------

abstract final class AuraType {
  /// Hero status typography (compute cockpit state word).
  static const TextStyle display = TextStyle(
    color: AuraColors.type,
    fontSize: 34,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );

  /// Section titles.
  static const TextStyle title = TextStyle(
    color: AuraColors.type,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// Primary reading text.
  static const TextStyle body = TextStyle(
    color: AuraColors.type,
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  /// Secondary reading text.
  static const TextStyle bodyDim = TextStyle(
    color: AuraColors.typeDim,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  /// Uppercase micro-labels (section markers, states).
  static const TextStyle label = TextStyle(
    color: AuraColors.slate,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w600,
  );

  /// Numeric metrics — tabular figures so columns never shimmer.
  static const TextStyle metric = TextStyle(
    color: AuraColors.type,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Large numeric readouts (watt-hours, match strength).
  static const TextStyle metricLarge = TextStyle(
    color: AuraColors.type,
    fontSize: 24,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Spotlight command line.
  static const TextStyle input = TextStyle(
    color: AuraColors.type,
    fontSize: 16,
    height: 1.25,
    letterSpacing: 0.2,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle inputHint = TextStyle(
    color: AuraColors.slate,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w400,
  );
}

// ---------------------------------------------------------------------------
// ThemeData
// ---------------------------------------------------------------------------

abstract final class AuraTheme {
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AuraColors.obsidian,
      canvasColor: AuraColors.obsidian,

      // Quiet: no ink splashes, no highlight flares. Feedback comes from
      // state change and haptics, not from material ripples.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: const Color(0x0DFFFFFF),

      colorScheme: const ColorScheme.dark(
        surface: AuraColors.obsidian,
        onSurface: AuraColors.type,
        primary: AuraColors.type,
        onPrimary: AuraColors.obsidian,
        secondary: AuraColors.slate,
        outline: AuraColors.slate,
        error: AuraColors.amber,
      ),

      textTheme: const TextTheme(
        displaySmall: AuraType.display,
        titleMedium: AuraType.title,
        bodyMedium: AuraType.body,
        bodySmall: AuraType.bodyDim,
        labelSmall: AuraType.label,
      ),

      dividerTheme: const DividerThemeData(
        color: AuraColors.hairline,
        thickness: AuraStroke.hair,
        space: AuraStroke.hair,
      ),

      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AuraColors.type,
        selectionColor: Color(0x33FFFFFF),
        selectionHandleColor: AuraColors.type,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AuraColors.carbon,
        contentTextStyle: AuraType.bodyDim,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero, // Geometry stays honest.
          side: BorderSide(color: AuraColors.slate, width: AuraStroke.line),
        ),
        elevation: 0,
      ),

      // Premium toggle: white thumb; the track is the accent surface —
      // low-luminance emerald when opted in, outlined void when out.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AuraColors.type
              : AuraColors.slate,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0x332FBF71)
              : Colors.transparent,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AuraColors.emerald
              : AuraColors.slate,
        ),
        trackOutlineWidth:
            const WidgetStatePropertyAll(AuraStroke.line),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AuraColors.slate,
        linearTrackColor: AuraColors.hairline,
      ),
    );
  }
}
