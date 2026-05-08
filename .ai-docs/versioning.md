# Versioning policy

Single source of truth for how Node Neo numbers releases on the App Store,
TestFlight, GitHub Releases, the macOS DMG filename, and the in-app About
screen. All five surfaces have to agree, but only the in-app preview label
is allowed to differ from the public release name — and only by a build
number suffix.

## TL;DR

- `pubspec.yaml`'s `version:` line names the **upcoming** release.
- Both workflows derive the iOS / macOS version from that single line.
- Dev builds and main builds share the same `X.Y.Z` and disambiguate via
  build number.
- After a `main` release ships, **immediately bump `pubspec.yaml`** to the
  next planned version on `dev`. Skipping this step would replay the same
  `X.Y.Z` from dev forever.

## What App Store Connect actually constrains

| Apple field | Meaning | Constraint |
|---|---|---|
| `CFBundleShortVersionString` | The "3.4.0" users see in the App Store | **Three integers `X.Y.Z`**, no suffixes. Strictly validated on every upload. |
| `CFBundleVersion` | The "(5)" build number — internal | Any string in TestFlight; must be **numeric** for App Store review. |
| `(short, build)` pair | The (3.4.0, 5) tuple | **Globally unique** forever per app record. Apple will reject re-uploads of an existing pair. |
| Once shipped to App Store | `(short, build)` for that release | You can never go *backwards* in either component for that app. |

So `3.4.0-dev` is illegal; `3.4.0` for both dev and main is legal as long
as the build numbers differ. Build numbers come from `GITHUB_RUN_NUMBER`,
which is monotonic across the whole repo, so dev and main builds never
collide on the same build number even when both target the same `X.Y.Z`.

## How the workflows produce versions

Both `.github/workflows/build-ios.yml` and `.github/workflows/build-macos.yml`
extract `X.Y.Z` from `pubspec.yaml`:

```bash
VPUB=$(grep -E '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
# Validates against ^[0-9]+\.[0-9]+\.[0-9]+$ — no -dev, no -rc, no extras.
```

| Field | Value | Source |
|---|---|---|
| `--build-name` (Flutter) → `CFBundleShortVersionString` | `3.4.0` | `pubspec.yaml` |
| `--build-number` (Flutter) → `CFBundleVersion` | `42` | `GITHUB_RUN_NUMBER` |
| `--dart-define=BUILD_CHANNEL` | `stable` on main, `preview` on dev | branch |

The Flutter `--build-name` / `--build-number` flags rewrite the iOS
`Info.plist` and the macOS `Info.plist` at archive time, so the OS-level
version is identical for both channels. **The only difference between a
dev and main build of the same commit is the in-app display label and the
DMG filename.**

## What the user sees

| Surface | Stable build (main) | Preview build (dev / local) |
|---|---|---|
| App Store entry | `3.4.0` | n/a (not published) |
| TestFlight build list | `3.4.0 (42)` | `3.4.0 (5)` |
| iOS About screen | `v3.4.0` | `v3.4.0+5` |
| macOS About screen | `v3.4.0` | `v3.4.0+5` |
| macOS DMG filename | `Node Neo-3.4.0-macOS.dmg` | `Node Neo-3.4.0+5-macOS.dmg` |
| iOS workflow IPA artifact | `nodeneo-3.4.0-ios.ipa` | `nodeneo-3.4.0+5-ios.ipa` |
| Git tag | `v3.4.0` | `v3.4.0-dev` |
| GitHub Release | `Node Neo v3.4.0` (with DMG) | not created |

The `+N` suffix on previews is the visual cue — it matches `pubspec.yaml`'s
own `name+build` notation, mirrors ASC's `(N)` build-number convention,
and makes it impossible to confuse a CI/local preview build for a shipped
release. The word "dev" is not exposed to users; they just see "+5" and
know it's a pre-release.

The mechanism: `lib/constants/app_brand.dart` exports

```dart
static const String buildChannel = String.fromEnvironment(
  'BUILD_CHANNEL', defaultValue: 'preview');

static String formatVersion(String version, String buildNumber) {
  if (isStableBuild || buildNumber.isEmpty) return 'v$version';
  return 'v$version+$buildNumber';
}
```

The default `preview` means a developer running `flutter run` locally
sees the same `+N` suffix that dev-branch CI builds show, so the local
binary is never mistaken for a release.

## When does `Z` (the patch digit) move?

Apple's intent for SemVer triple `Major.Minor.Patch`:

| Move | Trigger |
|---|---|
| `Major++` | Breaking, incompatible change (rare for a consumer app) |
| `Minor++` | A new release cut. Everything in `dev` since the last release rolls into the next minor: `3.3.0` → `3.4.0`. |
| `Patch++` | **Hotfix against a shipped release**. `3.4.0` is in the App Store, a critical bug is found, you ship `3.4.1` straight to App Review. Patch increments are reserved for this case. |

What `Z` is *not* for: tracking dev iterations. That's what build numbers
exist for. If we incremented `Z` per dev commit, every commit would create
a new ASC version slot and the App Store Connect version-history view
would fill up with dozens of `3.3.N` versions that never shipped to anyone.

## When to bump `pubspec.yaml`

`pubspec.yaml` is the source of truth for the **upcoming** release name.
Bump it in exactly two situations:

### After every `main` release

The moment the `main` workflow finishes publishing `v3.4.0` to the App
Store / GitHub Releases, open a one-line PR against `dev` that bumps
`pubspec.yaml`:

```yaml
# Before:  version: 3.4.0+1
# After:   version: 3.5.0+1
```

(Or `3.4.1+1` if you're going to do a patch line — see `release_process.md`.)
The `+1` resets to `1` because build numbers come from `GITHUB_RUN_NUMBER`
and don't actually read the pubspec build component; the `+N` in pubspec
is purely a placeholder.

Without this bump, every dev commit after a release would keep uploading
to the same `(3.4.0, run_number)` slot. ASC accepts it, but the slot is
already shipped, so the next "real" release-cut PR would have nowhere
clean to land — you'd be forced to bump pubspec at PR-cut time, which
breaks the property that any commit on `dev` between two releases reads
correctly.

### When deciding the next release will be a major / patch instead of minor

Default cadence is minor bumps (3.3.0 → 3.4.0 → 3.5.0). If a cycle's
work warrants a major bump, edit `pubspec.yaml` and the next `dev` build
will display the new target version. For patch-line work (`3.4.0` shipped,
hotfix branch), keep `dev` on `3.5.0` and create a `release/3.4.x` branch
that bumps to `3.4.1+1` separately.

## Hard rules

- **Never** put `-dev`, `-rc1`, or any other suffix in
  `CFBundleShortVersionString` — Apple rejects the upload.
- **Never** decrement either `X.Y.Z` or the build number on iOS once a
  given pair has been uploaded to ASC. ASC remembers forever.
- **Never** ship a dev binary to a tester with `BUILD_CHANNEL=stable` —
  the `+N` suffix is the only thing telling them it's a preview.
- **Always** bump `pubspec.yaml` immediately after a main release lands.
  This is a step in `.ai-docs/release_process.md`; don't skip it.
- **Always** update the `pubspec.yaml` version in the same commit /
  release PR — never split version-bumps across commits, the workflow
  validates against the value present at workflow trigger time.
