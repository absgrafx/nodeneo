import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Single source of truth for every external URL the app opens. Three reasons
/// to keep all of them in one file:
///
/// 1. **Reviewer + privacy auditing** — the App Store reviewer (and anyone
///    auditing what data leaves the device) can read a single class to see
///    every hostname the binary will ever open.
/// 2. **`nodeneo.ai` rebrand safety** — if the marketing site ever moves,
///    one constant changes and the whole app updates.
/// 3. **Consistency of launch behaviour** — every site link uses
///    `LaunchMode.externalApplication` so the user lands in their default
///    browser, not in an in-app web view that could cache cookies.
///
/// Nothing in this file fires on its own. Callers wire `launch()` into a
/// button / list-tile `onTap`. The single helper at the bottom keeps the
/// `url_launcher` boilerplate (and the failure path) out of every UI file.
class ExternalLinks {
  ExternalLinks._();

  // ── nodeneo.ai marketing + legal site ────────────────────────────────
  //
  // Maintained alongside the app in absgrafx/Morpheus-Infra
  // (`environments/00-absgrafx-prd/04-nodeneo.ai/website/`). Adding or
  // renaming a page there means updating the matching constant here;
  // every page is required to exist for App Store submission (Apple
  // checks the linked Privacy / Support / Terms URLs on every
  // submission cycle).

  /// Marketing landing page.
  static const String home = 'https://nodeneo.ai/';

  /// Founder-voiced "why does Node Neo exist" essay. Linked from
  /// Settings → Help & Resources.
  static const String why = 'https://nodeneo.ai/why.html';

  /// Calm 25-minute walkthrough from "I know nothing about crypto" to
  /// "my first chat is open". Linked from onboarding (under the PK input)
  /// and Settings → Help & Resources.
  static const String onramp = 'https://nodeneo.ai/onramp.html';

  /// Quick-start checklist for users who already have a wallet and just
  /// need the install + first-chat flow. Linked from Settings → Help &
  /// Resources.
  static const String quickStart = 'https://nodeneo.ai/start.html';

  /// Architecture / trust-model / TEE deep-dive. Currently linked only
  /// indirectly (privacy.html and the TEE badge on the home screen).
  static const String deepDive = 'https://nodeneo.ai/deep-dive.html';

  /// **App Store required.** Privacy policy URL filed on the App Store
  /// Connect record. Linked from About screen (Privacy row).
  static const String privacy = 'https://nodeneo.ai/privacy.html';

  /// **App Store required.** Terms of service URL filed on the App
  /// Store Connect record. Linked from About screen (Terms row).
  static const String terms = 'https://nodeneo.ai/terms.html';

  /// **App Store required.** Support URL filed on the App Store Connect
  /// record. FAQ + a `mailto:` to support@nodeneo.ai. Linked from About
  /// screen (Support row) and Settings → Help & Resources.
  static const String support = 'https://nodeneo.ai/support.html';

  /// Direct mail link for support inquiries. Used as a fallback target
  /// when the user explicitly wants to email rather than open the web
  /// support page.
  static const String supportMailto =
      'mailto:support@nodeneo.ai?subject=Node%20Neo%20support';

  // ── External ecosystem links (third parties we already linked from
  // existing screens — kept here so they're inventoried in one place
  // alongside the nodeneo.ai surfaces). ──

  /// Public source repo. Linked from About screen.
  static const String github = 'https://github.com/absgrafx/nodeneo';

  /// Latest published release page (DMG download for macOS, version
  /// reference for everyone else).
  static const String githubReleases =
      'https://github.com/absgrafx/nodeneo/releases/latest';

  /// Existing TEE explainer hosted on the Morpheus tech site. Already
  /// referenced from `home_screen.dart` next to the TEE badge.
  static const String morpheusTeeExplainer = 'https://tech.mor.org/tee.html';

  /// Existing session explainer hosted on the Morpheus tech site.
  /// Already referenced from `wallet_screen.dart`.
  static const String morpheusSessionExplainer =
      'https://tech.mor.org/session.html';

  // ── Helper ───────────────────────────────────────────────────────────

  /// Opens [url] in the platform's default browser (or default mail
  /// client for `mailto:` URIs). Returns `true` if the URL launched,
  /// `false` if the platform refused (e.g. no handler registered for
  /// the scheme); on `false`, surfaces a brief snackbar so the user
  /// isn't left wondering why nothing happened.
  ///
  /// Pass `context` to enable the snackbar fallback. Without it the
  /// helper is silent on failure (suitable for fire-and-forget call
  /// sites that don't have a `BuildContext` handy).
  static Future<bool> launch(String url, {BuildContext? context}) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t open $url'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return ok;
  }
}
