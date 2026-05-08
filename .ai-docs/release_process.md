# Node Neo release process

Top-to-bottom checklist for cutting a release. Originally lived at
`.cursor/rules/release-process.mdc`; moved here in 2026-05 so it stays
visible (the `.cursor/` folder is gitignored to keep IDE configuration
local to each developer).

Every step has an explicit command. **Don't skip validation, the version
check, the SDK pin, or the post-release pubspec bump** — each has bitten
us at least once.

CI shape to keep in mind:

- `.github/workflows/build-macos.yml` — push to `dev` builds an unsigned
  DMG artifact (preview filename: `Node Neo-3.4.0+42-macOS.dmg`); push
  to `main` signs + notarizes and publishes a GitHub Release.
- `.github/workflows/build-ios.yml` — push to `dev` uploads to TestFlight
  Internal Group; push to `main` uploads to TestFlight + creates the
  GitHub Release alongside the DMG.

On `main` the entire `RELEASE_NOTES.md` becomes the GitHub Release body,
so we keep that file from growing unbounded — see step 6a.

**Step 5 may block on a human.** If `proxy-router/mobile/` was touched
in this cycle, those changes have to ride the upstream
`MorpheusAIs/Morpheus-Lumerin-Node` PR-to-`dev` workflow first. Stop and
report when the upstream PR is open; resume from step 5c after a human
merges it.

## 1. Inventory + decide the next version

```bash
cd /Volumes/moon/repo/personal_mor/nodeneo
git status --short
git log --oneline -10
git tag -l "v[0-9]*" --sort=-v:refname | head -5
grep '^version:' pubspec.yaml
```

`pubspec.yaml`'s `version:` line is the **upcoming** release name (see
`versioning.md`). Both workflows derive `CFBundleShortVersionString`
and the DMG filename from it. **Always check the actual tags + pubspec,
not an assumption.** Examples:

| pubspec says | Last shipped | Next release on `main` |
|---|---|---|
| `3.4.0+1` | `v3.3.0` | `v3.4.0` (just push to main) |
| `3.4.0+1` | `v3.4.0` | **STOP** — pubspec needs bumping (step 9 was skipped) |

If pubspec wasn't bumped after the last release, do that as a tiny
preamble PR before the actual release work. See step 9.

## 2. Scan for stale references

Before touching docs, grep for repo names, branch names, or paths that
shouldn't appear in current-state material:

```bash
# Adjust patterns to whatever the prior naming was.
rg "absgrafx/Morpheus|feat-external_embedding|absgrafx fork" -l
```

Distinguish current-state docs (README, llms.txt, .ai-docs/architecture.md,
.ai-docs/plan.md, .ai-docs/handoff_context.md, Makefile, CI workflow) from
historical material (older RELEASE_NOTES sections, plan.md decision log).
**Only update current-state.** Historical entries describe what was true
at the time and should not be retconned.

## 3. Create the feature branch

Branch off `dev`. Naming follows existing convention — pick the closest:

| Prefix    | Use for                                |
|-----------|----------------------------------------|
| `feat/`   | New capability or behaviour            |
| `fix/`    | Bug fix                                |
| `docs/`   | Docs/release-notes only                |
| `chore/`  | Tooling, deps, internal cleanup        |
| `cicd/`   | CI/CD pipeline changes                 |

```bash
git checkout dev
git pull
git checkout -b <type>/<short-topic>
```

Keep the branch name version-agnostic (e.g. `feat/gateway-cursor-zed`,
not `feat/v3.2.0-gateway`). If the version retargets later, the branch
survives.

## 4. Update current-state docs

Look at every file below and update only what reflects current state today:

- `README.md` — install/build paragraphs, platform table, dependency line
- `llms.txt` — companion repo and links sections
- `.ai-docs/architecture.md` — integration strategy paragraph
- `.ai-docs/plan.md` — dependencies table (don't edit historical decision log)
- `.ai-docs/handoff_context.md` — top metadata, repos table, file-tree comment, date stamp
- `Makefile` — any `grep` patterns that scrape `go.mod`
- `.github/workflows/*.yml` — clone URLs, regex patterns, env carve-outs

Bundle IDs like `com.absgrafx.nodeneo` and the `github.com/absgrafx/nodeneo`
module path are correct — leave them.

## 5. Lock the SDK pseudo-version to upstream dev

CI runs `go build` from a clean checkout with **no sibling clone**, so
the local `replace github.com/.../proxy-router => ../../Morpheus-Lumerin-Node/proxy-router`
must be commented out and the `require` line must hold a real
pseudo-version that the public Go module proxy can resolve. If you skip
this, both the dev artifact build and the main release build die on
`replacement directory does not exist`.

### 5a. If `proxy-router/mobile/` changed this cycle

Per `.cursor/rules/proxy-router-workflow.mdc` (kept as a `.cursor` rule
because it's an AI-agent workflow file, not a developer ritual; the rule
itself is on disk in every dev's working copy), SDK changes go upstream
**before** the Node Neo release pin. Do this in `../Morpheus-Lumerin-Node`,
not in nodeneo:

```bash
cd /Volumes/moon/repo/personal_mor/Morpheus-Lumerin-Node
git fetch origin
git checkout -b mobile/<feature> origin/dev
# ...the SDK changes are already in your working tree from local iteration...
git add proxy-router/mobile/...
git commit -m "feat(proxy-router/mobile): <what>"
git push -u origin mobile/<feature>
gh pr create --base dev --repo MorpheusAIs/Morpheus-Lumerin-Node \
  --title "feat(proxy-router/mobile): <what>" \
  --body  "<why + testing>"
```

**Stop and wait for a human merge to upstream `dev`.** Don't pin against
the feature branch — that defeats the point of the review gate. When the
merge lands, capture the new HEAD:

```bash
cd /Volumes/moon/repo/personal_mor/Morpheus-Lumerin-Node
git fetch origin
git log -1 --format='%cI %H' origin/dev    # capture both timestamp and hash
```

### 5b. If no SDK changes this cycle

Still re-pin. Other people may have merged into upstream `dev` since the
last release, and shipping with a stale pseudo-version means the embedded
`proxy-router/internal/config.Commit` ldflag in the binary lies about
what's actually running.

### 5c. Apply the pin in `nodeneo/go/go.mod`

Two states matter:

| `replace` line | `require` version             | Mode                        |
|----------------|-------------------------------|-----------------------------|
| Active         | `v0.0.0-00010101000000-...`   | Local iteration (mid-cycle) |
| Commented      | `v0.0.0-<date>-<commit12>`    | Pinned (release-ready)      |

To transition from "local iteration" to "pinned":

```bash
cd /Volumes/moon/repo/personal_mor/nodeneo/go

# 1. Comment out the replace line in go.mod (it shadows require — kills CI)
#    The line currently reads:
#    replace github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router => ../../Morpheus-Lumerin-Node/proxy-router
#    Change to:
#    // replace github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router => ../../Morpheus-Lumerin-Node/proxy-router

# 2. Pin the require line to upstream dev HEAD
go get github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router@<commit12>
go mod tidy
```

**First-time-from-placeholder escape hatch.** If `go get` fails with
`invalid version: unknown revision 000000000000`, the require line still
holds the placeholder and Go can't bootstrap. Compute the pseudo-version
manually and write it directly:

```
v0.0.0-<UTC commit time as YYYYMMDDHHMMSS>-<commit12>
```

Example: commit `697c3b596059` made at `2026-04-30T16:42:34Z` →
`v0.0.0-20260430164234-697c3b596059`. Then:

```bash
go mod download github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router
go mod tidy
```

### 5d. Sanity check the build pipeline scrapes the right hash

The Makefile/CI extract the embedded version with:

```
grep 'MorpheusAIs/Morpheus-Lumerin-Node/proxy-router' go.mod | grep -oE '[0-9a-f]{12}$'
```

Run that locally — it should return the new commit hash, **not** anything
from the commented-out replace line. The commented `replace` ends with
`proxy-router` (no 12-char hex), so it's filtered out automatically, but
verify before pushing.

### 5e. Re-uncomment is for the NEXT cycle, not this PR

Don't re-uncomment the replace before merging. The release PR must merge
in pinned mode. Uncommenting belongs in a **separate** post-release commit
when active SDK iteration resumes — typically rolled into the first
`mobile/<feature>` PR of the next cycle.

## 6. Doc rotation ritual (the important one)

Three files move in lockstep when work ships. All three must be updated in
the same release commit.

### 6a. `RELEASE_NOTES.md`

The CI release step does:
```
cat RELEASE_NOTES.md >> /tmp/release-notes.md      # full file
printf '\n---\n\n' >> /tmp/release-notes.md
cat <asset-table>   >> /tmp/release-notes.md
gh release create "$TAG_NAME" "$DMG_PATH" --notes-file /tmp/release-notes.md
```

So the entire file becomes every future Release page body. The file is a
**reset-each-release** document: keep exactly one fully-expanded section
(the latest), and demote everything older to a one-line row in the
`## Previous Releases` table.

Each cut:
1. Add a new top section `## What's New in vX.Y.Z` with the full breakdown
   (sections grouped by area — Gateway, App Lock, Network, iOS Impact,
   Engineering, etc. — whatever shape the cycle's work warrants)
2. Demote the previously-top section to a one-line row in the
   `## Previous Releases` table. Each row needs a link to
   `https://github.com/absgrafx/nodeneo/releases/tag/vX.Y.Z` plus optional
   PR links `[#NN](.../pull/NN)`. Full detail stays pinned to that tag's
   GitHub Release page.

### 6b. `.ai-docs/architecture.md` "Recently Shipped"

Architecture.md owns the **long-form record** of completed work. The
`## Recently Shipped` section at the bottom of the file holds the running
history; per-release entries stay there indefinitely so future contributors
can search "when did we ship X?" without spelunking through old GitHub
releases.

Each cut:
1. If a `### Next release (in progress)` block exists at the top of
   *Recently Shipped*, rename it to `### vX.Y.Z — YYYY-MM-DD` and trim any
   "to be validated" caveats now that the work is shipping.
2. Otherwise add a new `### vX.Y.Z — YYYY-MM-DD` block above the previous
   release entry with a paragraph + bullet list per shipped item.
3. **Also** propagate any architectural changes inline (e.g. a new service
   added to the Onboarding & Wallet section, a new layer in the layered
   diagram, an updated Tech Stack row). The "Recently Shipped" log is the
   *historical* record; the prose above it must reflect *current* state.

### 6c. `.ai-docs/feature_backlog.md`

The backlog is **open items only**. As soon as a feature ships, its
description moves to architecture.md → Recently Shipped, and the backlog
entry is deleted (not moved to a `Recently Shipped` subsection — that
content lives in architecture.md now).

Each cut:
1. For every backlog item that shipped this cycle, delete its section
   wholesale. If there are residual open follow-ups (telemetry, a deferred
   polish item), leave a small "Open Questions / Follow-ups" stub under a
   renamed heading that points readers at the architecture.md entry for
   the shipped capability. Do NOT keep the full "What shipped" prose —
   it's redundant with architecture.md.
2. Update the `*Last updated:*` stamp at the bottom.
3. Renumber the remaining items if the deletion left gaps and the order
   no longer reads naturally.

## 7. Validate before pushing

Always all three (don't skip Flutter just because Go passed):

```bash
cd go && go vet ./... && go test ./internal/gateway/... ./internal/store/... && cd ..
flutter analyze lib/<files-you-touched>
```

Filter pre-existing Flutter findings against `dev`:
```bash
git diff dev -- <file> | grep -E '^@@'   # confirm hunks don't include the linted line
```

If the Morpheus-Lumerin-Node SDK was touched, cross-compile for iOS:
```bash
cd go && GOOS=ios GOARCH=arm64 CGO_ENABLED=1 go vet ./...
```

The `dsymutil … operation not permitted` error on `cmd/cshared` linking is
a known macOS sandbox issue, not a code problem — `go vet` is the canonical
check.

## 8. Commit, push, open PR (dev)

```bash
git add -A
git status --short                         # sanity
```

Always use a HEREDOC for the commit body so formatting survives:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): vX.Y.Z — <headline>

<2-3 sentence summary of why>

<bullet list of grouped changes by area>

<closing line: validation status, iOS impact note>
EOF
)"
git push -u origin <branch>                # first push
```

**Confirm the active `gh` account has push access to `absgrafx/nodeneo`**
before opening the PR — `gh auth status` will print which account is
active. If multiple accounts are set up, switch with `gh auth switch -u
<account>` before running `gh pr create`.

```bash
gh pr create --base dev --head <branch> \
  --title "<type>(<scope>): vX.Y.Z — <headline>" \
  --body "$(cat <<'EOF'
## Summary
<1-2 sentences>

### <Section per area>
- bullet
- bullet

## iOS impact
<gateway/SDK is gated, etc.>

## Test plan
- [x] go vet ./... clean
- [x] go test ./internal/gateway/... ./internal/store/... green
- [x] flutter analyze on touched files (no new findings)
- [ ] Smoke: <manual checks user will do>

## Follow-up
After merge to dev and validation, open dev → main PR to ship vX.Y.Z.
EOF
)"
```

When this PR merges to `dev`:

- macOS: an unsigned preview DMG `Node Neo-X.Y.Z+RUN-macOS.dmg` is
  uploaded as a workflow artifact (14-day retention).
- iOS: a signed IPA `X.Y.Z(RUN)` is uploaded to TestFlight Internal
  Group. The build appears in App Store Connect → TestFlight within
  10–30 minutes.
- The in-app About screen on both platforms shows `vX.Y.Z+RUN`.

Smoke-test the dev preview before promoting.

## 9. Promote to main + post-release pubspec bump

After the user validates the dev preview (TestFlight install, smoke test):

### 9a. Open dev → main PR

```bash
gh pr create --base main --head dev \
  --title "Release vX.Y.Z" \
  --body "Promotes dev → main to ship vX.Y.Z. See RELEASE_NOTES.md for the full breakdown.

Validation on dev:
- [ ] CI build succeeded (DMG artifact present)
- [ ] TestFlight install passed smoke tests
"
```

When that PR lands on `main`, both workflows run again on the merge commit:

- iOS: re-uploads as `X.Y.Z(NEW_RUN)` to TestFlight (build number bumps,
  short version stays). The in-app About screen now shows just `vX.Y.Z`
  (no `+RUN` suffix) because `BUILD_CHANNEL=stable`.
- macOS: signed + notarized DMG `Node Neo-X.Y.Z-macOS.dmg` (no `+RUN`)
  attached to a new GitHub Release tagged `vX.Y.Z`. Body is
  `RELEASE_NOTES.md` + asset table.

### 9b. Post-release pubspec bump (CRITICAL — don't skip)

The instant the `main` Release exists, open a one-line PR against `dev`:

```bash
git checkout dev
git pull
git checkout -b chore/bump-pubspec-vX.Y+1.0
```

Edit `pubspec.yaml`:
```yaml
# Before:  version: X.Y.Z+1
# After:   version: X.(Y+1).0+1     # or X.Y.(Z+1)+1 for a patch line
```

The default cadence is to bump the **minor** to set up the next feature
release. Patch bumps are only for hotfix branches against an already-shipped
release (see `versioning.md`).

```bash
git commit -am "chore: bump pubspec to X.(Y+1).0+1 — start next release cycle"
gh pr create --base dev --head HEAD \
  --title "chore: bump pubspec to next release version" \
  --body "Post-release housekeeping after vX.Y.Z shipped to App Store / GitHub Releases.
With this merged, dev builds will read vX.(Y+1).0+RUN until the next release-cut PR.
See .ai-docs/versioning.md for the policy."
```

**If you skip this step**, every subsequent dev push will keep uploading
to the already-shipped `vX.Y.Z` slot. ASC accepts it (build numbers still
increment), but the in-app version label and DMG filename stop reflecting
"the work in progress toward the next release" — they'll keep saying
`vX.Y.Z+RUN`, which is exactly the version we just shipped.

### 9c. Post-release SDK iteration resume (optional)

If you intend to actively iterate on `proxy-router/mobile/` again, the
first `mobile/<feature>` branch of the next cycle is also where the
`replace` line in `go/go.mod` gets re-uncommented. See step 5e.

## Hard rules

- **Never** push directly to `dev` or `main`. PR everything.
- **Never** `--amend` a commit that has already been pushed. New commit
  on the branch is correct — the PR auto-updates.
- **Never** rewrite historical RELEASE_NOTES sections. They describe what
  was true at the time; collapse them, don't edit the substance.
- **Never** label the new release before checking `git tag -l` and
  `pubspec.yaml`. We've burned a cycle on this — `v3.1.0` had already
  shipped when we were calling the new work `v3.1.0`.
- **Never** ship a release with the local SDK `replace` line still active.
  The release commit must be in pinned mode (real pseudo-version, replace
  commented). Step 5 enforces this; CI cannot resolve the local sibling
  path.
- **Never** pin against an SDK feature branch. Pin only against a merged
  commit on upstream `dev`. SDK code changes themselves follow the
  cross-repo PR path in `.cursor/rules/proxy-router-workflow.mdc`.
- **Never** put `-dev`, `-rc1`, or any other suffix in
  `CFBundleShortVersionString`. Apple rejects the upload. The `+RUN`
  suffix in pubspec is for the build component only and never reaches
  the iOS short-version field.
- **Always** run step 9b (pubspec bump) immediately after a `main`
  release. The whole versioning policy in `versioning.md` depends on
  this happening every cycle.
