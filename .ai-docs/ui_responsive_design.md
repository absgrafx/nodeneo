# UI Responsive Design Policy

> How Node Neo handles the tension between **one design** and **every
> screen size** — from a 390 px iPhone to a 2560 px ultrawide monitor —
> without chasing custom elements across an infinite pixel space.

*Last updated: 2026-04-23*

---

## TL;DR

1. Use `FormFactor` (compact / medium / expanded), not `Platform.isXxx`,
   for layout decisions.
2. **Prefer homogeneity.** If the compact design looks good wider, ship
   it everywhere. The two-line model tile is the canonical example.
3. **Cap, don't stretch.** Wrap lists and forms in `MaxContentWidth`
   so `expanded` reads proportionally — never pixels wide.
4. Inline small branches. Split files only when `compact` and `expanded`
   diverge structurally (e.g. nav rail vs bottom nav).
5. Run the **New Screen Checklist** below before every screen merges.

---

## Why three buckets, not N breakpoints

Flutter and the web both tempt you to sprinkle `if (width > 1040) ...`
everywhere. That scales badly — you end up with a UI that is subtly
different at every window size and drifts between platforms.

Node Neo commits to exactly **three form factors**, matching the
Material 3 window-size-classes convention:

| Form factor | Width (logical px) | Typical surface                          |
|-------------|--------------------|------------------------------------------|
| `compact`   | `< 600`            | iPhone portrait, narrow desktop window   |
| `medium`    | `600-839`          | iPhone landscape, small tablet, split view |
| `expanded`  | `>= 840`           | iPad, macOS / Linux / Windows desktop    |

Three buckets, three designs to maintain, three sets of screenshots to
review. Anything more granular is a bug.

Canonical upper bound: content is **capped at 960 px** (`MaxContentWidth`)
so an ultrawide monitor doesn't stretch a 400 px-design to the horizon.

---

## Form factor vs platform capability

Two different concerns, two different services. Do not mix them.

| Question                                   | Use                                     |
|--------------------------------------------|-----------------------------------------|
| *"How wide is this context right now?"*    | `formFactorOf(context)` / `isCompact()` |
| *"Does this platform support X feature?"*  | `PlatformCaps.supportsX`                |

- Form factor can **change mid-session** (resize a macOS window, rotate
  an iPad). Read it via `BuildContext` so the widget rebuilds.
- Platform capability is **static** for a session. Read it once.

Examples:

```dart
// Layout — form factor only.
final tileTwoLine = isCompact(context);

// Capability — platform only.
if (PlatformCaps.supportsMcp) {
  MenuItem('MCP server settings');
}

// Never do this — conflates layout with feature gating:
if (Platform.isIOS) { ... }    // BAD for layout
if (MediaQuery.sizeOf(context).width < 600) hideDeveloperApi(); // BAD
```

---

## The four tools in `lib/services/form_factor.dart`

1. **`formFactorOf(context)`** — returns the `FormFactor` enum. Use when
   you need to branch on more than two cases.
2. **`isCompact(context)` / `isExpanded(context)` / `isAtLeastMedium(context)`**
   — boolean shortcuts for the common branches. Prefer these.
3. **`pickByFormFactor(context, compact: ..., expanded: ...)`** — picks
   a value by form factor. Missing tiers fall back to `compact`, so you
   only override what actually differs.
4. **`MaxContentWidth(child: ...)`** — wraps content in a centered
   `ConstrainedBox(maxWidth: 960)`. **Use on every scrollable screen.**

### Example

```dart
@override
Widget build(BuildContext context) {
  return MaxContentWidth(
    child: ListView(
      padding: EdgeInsets.symmetric(
        horizontal: pickByFormFactor(context, compact: 12, expanded: 24),
      ),
      children: [...],
    ),
  );
}
```

---

## Design principles

### 1. Homogeneity first

If the compact design reads well at wide widths, ship it on every form
factor. Two-line tiles, generous tap targets, vertical stacks of fields —
these are all readable on desktop too. You gain: one design to maintain,
one screenshot to review, one mental model for the user.

**Example — the model list:**

The iPhone two-line tile (`_ModelTile` in `home_screen.dart`) was
originally a compact-only fix. We keep it on every platform because
readability at 1440 px is still excellent — we just cap the list's
`maxWidth` so the tile doesn't stretch.

### 2. Cap, don't stretch

The fastest way to make a mobile-first design feel broken on desktop is
to let it span the viewport. A 48 px tap target becomes a 2000 px visual
bar — silly. Always cap:

```dart
MaxContentWidth(child: listView)  // lists, forms, chat columns
```

Default cap is 960 px; override via `maxWidth:` when a specific screen
wants more or less.

### 3. Branch on form factor, not platform

For layout decisions, `Platform.isIOS` is wrong — an iPad app running
full-screen has desktop-class width; a macOS window dragged narrow
has phone-class width. Branch on the actual width:

```dart
// Good:
if (isCompact(context)) { useBottomNav() } else { useNavRail() }

// Bad:
if (Platform.isIOS) { useBottomNav() }
```

### 4. Inline first, split when painful

Small, local differences live inside the widget. Big structural
differences (nav style, master-detail vs single column, dialog vs
bottom sheet) get their own files.

| Divergence size             | Pattern                                       |
|-----------------------------|-----------------------------------------------|
| One property (padding, maxLines, columns) | `pickByFormFactor` inline      |
| One section (a panel swaps position)      | `if (isExpanded) ... else ...` inline |
| Whole-screen structure (nav, layout)      | Split files (see below)        |

**Split-file pattern:**

```
lib/screens/foo/
  foo_screen.dart            ← public entry, picks variant
  foo_screen_compact.dart    ← phone layout
  foo_screen_expanded.dart   ← tablet/desktop layout
  _foo_shared.dart           ← shared widgets / state
```

```dart
// foo_screen.dart
@override
Widget build(BuildContext context) {
  return isExpanded(context)
      ? const FooScreenExpanded()
      : const FooScreenCompact();
}
```

Rule of thumb: if the two variants share less than ~70 percent of their
tree, split. Otherwise keep them inline.

---

## Current screen inventory

As of the v7.0.0 merge, every screen lives in a single file and uses
`compact` layouts. This table is the migration tracker — tick each
off as it becomes form-factor-aware.

| Screen                          | Form-factor aware? | Plan                                     |
|---------------------------------|--------------------|------------------------------------------|
| `onboarding_screen.dart`        | No                 | Inline — cap max width; no layout change |
| `home_screen.dart`              | Tiles, partial     | Cap model list width; nav unchanged      |
| `chat_screen.dart`              | No                 | Cap chat column; drawer stays until split |
| `conversation_transcript_screen.dart` | No           | Cap max width                            |
| `wallet_screen.dart`            | No                 | Cap; no structural change planned        |
| `sessions_screen.dart`          | No                 | Cap; tiles stay two-line                 |
| `expert_screen.dart`            | No                 | Cap; accordions stay vertical            |
| `network_settings_screen.dart`  | No                 | Cap; accordions stay vertical            |
| `backup_reset_screen.dart`      | No                 | Cap; no change                           |
| `about_screen.dart`             | No                 | Cap; no change                           |
| `app_lock*_screen.dart`         | No                 | Cap; PIN pad stays compact               |
| `wallet_security_actions.dart`  | No                 | Cap; no change                           |

When a screen *would benefit* from expanded-class divergence (chat
with a persistent conversation list on desktop; home with model
detail pane on the side), promote it to the split-file pattern.

---

## New Screen Checklist

Before merging a new screen, verify:

- [ ] The outermost scrollable is wrapped in `MaxContentWidth` (or the
      screen explicitly documents why it wants to span full width).
- [ ] Any `Platform.is*` usage is routed through `PlatformCaps`, not
      used for layout.
- [ ] Any width-based branching is expressed via `formFactorOf` /
      `isCompact` / `pickByFormFactor` — not bare `MediaQuery.sizeOf`.
- [ ] The screen renders at **390 x 844** (iPhone 15 portrait) without
      overflow warnings.
- [ ] The screen renders at **1440 x 900** (MacBook) with content
      centered and capped, not stretched.
- [ ] If the screen diverges structurally between `compact` and
      `expanded`, it follows the split-file pattern (router +
      `_compact.dart` + `_expanded.dart`).
- [ ] Tap targets remain **>= 44 px** on `compact` and `medium`.
- [ ] Font sizes are **relative** (use `theme.textTheme.*`), not
      hardcoded in a way that breaks larger accessibility scaling.

---

## What *not* to do

- Do not introduce new breakpoints. If you need a fourth size, have a
  design conversation first — we add it to `Breakpoints` or we don't
  have it.
- Do not add `if (Platform.isMacOS) ...` blocks to widgets. That is a
  sign the logic belongs in `PlatformCaps` or `formFactorOf`.
- Do not hardcode widths ("800 px" in a `SizedBox`). Use
  `MaxContentWidth` or `pickByFormFactor`.
- Do not split a screen into compact/expanded files just because you
  *can*. Inline until the divergence ratio crosses ~30 percent.

---

## References

- Material 3 window size classes:
  <https://m3.material.io/foundations/layout/applying-layout/window-size-classes>
- Apple Human Interface Guidelines — layout:
  <https://developer.apple.com/design/human-interface-guidelines/layout>
- `lib/services/form_factor.dart` — source of truth for breakpoints
- `lib/services/platform_caps.dart` — source of truth for capabilities
- `.ai-docs/architecture.md` — overall architecture
- `.ai-docs/platform_expansion.md` — per-platform feature matrix
