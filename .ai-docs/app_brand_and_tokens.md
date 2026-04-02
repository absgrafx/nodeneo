# App display name & token / chain artwork

## Product name (UI)

- **Single source of truth:** [`lib/constants/app_brand.dart`](../lib/constants/app_brand.dart) — change **`AppBrand.displayName`** (default **`Morpheus`**).
- That string drives: **home AppBar**, **lock screen** headline, **MaterialApp.title**, **Network** explainer copy, **Face ID / Touch ID** reason string, etc.
- **Splash / launcher icons** are PNGs from [`assets/branding/`](../assets/branding/README.md) — rerun `make brand-assets` or `make dev-macos` after changing vectors.
- Internal identifiers (Dart `NodeNeoApp`, package name `nodeneo`, bundle IDs `com.absgrafx.nodeneo`) reflect the current project name.

### Naming ideas (same list as in `app_brand.dart`)

| Name       | Vibe |
|-----------|------|
| **Morpheus** | Ecosystem / marketplace alignment (current default). |
| **Lattice**  | Network mesh, many providers. |
| **Veridian** | Emerald “signal” brand. |
| **Ascent**   | Wings / upward. |
| **Cipher**   | Privacy-forward. |
| **MorChat**  | Explicit chat product. |

---

## Token symbols + Base “chain overlay” chip

Raster tokens live in **`assets/branding/`** and are wired in [`lib/widgets/crypto_token_icons.dart`](../lib/widgets/crypto_token_icons.dart):

| Asset | Role |
|-------|------|
| **`token_mor_base_square.png`** | MOR: Morpheus green diagonal gradient + `MOR_WHITE_256.png` (generated). |
| **`token_eth_base_square.png`** | ETH: Ethereum blue gradient + `eth-diamond-(purple).png` (generated). |
| **`base_chip.png`** | Base badge in the corner (`BaseNetworkBadge`). Prefer a **square** PNG so the circular clip looks even. |

**Regenerate** the two `token_*` squares after editing the source PNGs:

```bash
python3 tools/branding/compose_token_squares.py
```

Script: [`tools/branding/compose_token_squares.py`](../tools/branding/compose_token_squares.py) (requires **Pillow**).

---

## iPhone: preview in Xcode & device run

See **[`.ai-docs/ios_device_signing.md`](ios_device_signing.md)** — section **“Preview & run from Xcode”** at the top, then signing and **§7 Go library on iOS** (FFI) before expecting full app behavior on hardware.
