# Pre-LLC legal-doc archive — 2026-05-01

These are the original `TERMS.md` and `PRIVACY.md` drafted on **2026-05-01**, before ABSGrafx LLC was formed (filed in South Dakota on 2026-05-07).

They are kept here for two reasons:

1. **Git-history continuity** — anyone diffing repo legal docs across the LLC-formation transition can read the predecessor here without spelunking through `git log`.
2. **Audit trail** — the only consumer-installable build that carried these as the operative consumer Terms / Privacy was the macOS-only release cycle through `v3.3.0`. Any reviewer (App Store, attorney, future investor) asking "what did your legal docs say at version X?" can read the answer here.

## What changed at the 2026-05-07 cutover

- **Publisher attribution** — `absgrafx` (lowercase, "an independent publisher") → `ABSGrafx LLC` (South Dakota legal entity)
- **Governing law** — already named South Dakota; venue clause stays "courts located in South Dakota" (no specific county) given the principal's full-time-RV / Box Elder PMB domicile
- **Source of truth** — moved from the in-repo `TERMS.md` / `PRIVACY.md` files to <https://nodeneo.ai/terms.html> and <https://nodeneo.ai/privacy.html>. The repo files are now thin pointer stubs.
- **Contact channels** — split into two intentional surfaces:
  - `support@nodeneo.ai` — user-facing app channel (what App Store reviewers, end users, and in-app links see)
  - `nodeneo@absgrafx.com` — LLC business inbox (security disclosure, source-code-level inquiries, anything addressed to the LLC as an entity rather than to the app)

The substantive obligations on either side (zero data collection, self-custody disclaimer, MIT for source, $100 USD liability cap, AS-IS warranty disclaimer, individual-disputes-only) carry over unchanged.

## What is the operative document today

| For | Read |
|---|---|
| The consumer Terms of Use the App Store binary subjects users to | <https://nodeneo.ai/terms.html> |
| The consumer Privacy Policy the App Store binary commits to | <https://nodeneo.ai/privacy.html> |
| The MIT license on the source code | [`/LICENSE`](../../../LICENSE) |
| The repo-level pointer stubs | [`/TERMS.md`](../../../TERMS.md) · [`/PRIVACY.md`](../../../PRIVACY.md) |

This folder is a snapshot. Do not edit these files in place. If the canonical website docs ever change in a way that needs a new historical bookmark, archive them under a new dated subfolder (`legal/archive/YYYY-MM-DD-<reason>/`).
