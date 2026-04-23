import 'package:flutter/widgets.dart';

/// Form-factor (window-size) helpers for responsive layout decisions.
///
/// Use **form factor** for layout choices (columns, tile density, gutter
/// widths). Use [PlatformCaps] for capability gating (which features exist
/// at all). The two concerns are orthogonal — a macOS window dragged to
/// 400 px wide is `compact`, an iPad in landscape is `expanded`.
///
/// Breakpoints follow Material 3 window size classes:
///   <  600 px  → compact  (phone portrait, narrow window)
///   600-839    → medium   (phone landscape, small tablet, narrow desktop)
///   >= 840     → expanded (tablet, desktop)
///
/// ### Policy
///
/// 1. **Prefer homogeneity.** If the compact design is also good at wider
///    widths, use it everywhere. Divergence is a cost we pay reluctantly.
/// 2. **Cap growth, don't stretch.** Prefer `ConstrainedBox(maxWidth: ...)`
///    on lists/forms so `expanded` reads proportionally rather than
///    stretching compact designs across 2000 px.
/// 3. **Branch on form factor, not platform.** `isCompact(ctx)` — not
///    `Platform.isIOS` — decides if a list wraps to two lines.
/// 4. **Inline first; split files when divergence exceeds ~30 percent.**
///    Small branches stay inside the widget. Full-layout divergence
///    (nav rail vs bottom nav, master-detail vs stack) moves to sibling
///    files: `foo_screen.dart` (router) + `_compact.dart` + `_expanded.dart`.
///
/// See `.ai-docs/ui_responsive_design.md` for the full decision guide.
enum FormFactor { compact, medium, expanded }

class Breakpoints {
  Breakpoints._();

  /// Width in logical pixels below which the UI is treated as `compact`.
  static const double compact = 600;

  /// Width in logical pixels below which the UI is treated as `medium`.
  static const double medium = 840;

  /// Upper bound we clamp content to on expanded displays. Keeps lists,
  /// chat columns, and settings accordions readable on 2K/4K monitors.
  static const double maxContentWidth = 960;
}

/// Classifies the current [BuildContext]'s width into a [FormFactor].
FormFactor formFactorOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < Breakpoints.compact) return FormFactor.compact;
  if (width < Breakpoints.medium) return FormFactor.medium;
  return FormFactor.expanded;
}

/// Convenience: true when the current context is phone-portrait sized.
bool isCompact(BuildContext context) =>
    formFactorOf(context) == FormFactor.compact;

/// Convenience: true when the current context is tablet/desktop sized.
bool isExpanded(BuildContext context) =>
    formFactorOf(context) == FormFactor.expanded;

/// Convenience: anything at or above the `medium` breakpoint — i.e. NOT
/// phone-portrait. Useful for "hide drawer toggle" / "show side panel" flows.
bool isAtLeastMedium(BuildContext context) =>
    formFactorOf(context) != FormFactor.compact;

/// Picks a value based on form factor. Falls back to [compact] if a
/// wider tier is not supplied — so callers only specify overrides they
/// actually care about.
///
/// ```dart
/// final gutter = pickByFormFactor(
///   context,
///   compact: 12.0,
///   expanded: 24.0,
/// );
/// ```
T pickByFormFactor<T>(
  BuildContext context, {
  required T compact,
  T? medium,
  T? expanded,
}) {
  switch (formFactorOf(context)) {
    case FormFactor.compact:
      return compact;
    case FormFactor.medium:
      return medium ?? compact;
    case FormFactor.expanded:
      return expanded ?? medium ?? compact;
  }
}

/// Wraps [child] in a [Center] + [ConstrainedBox] so content is capped at
/// [Breakpoints.maxContentWidth] on expanded displays. Use on scrollable
/// lists, settings pages, and chat columns to prevent tiles stretching
/// across ultra-wide windows.
class MaxContentWidth extends StatelessWidget {
  final Widget child;
  final double? maxWidth;

  const MaxContentWidth({super.key, required this.child, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? Breakpoints.maxContentWidth,
        ),
        child: child,
      ),
    );
  }
}
