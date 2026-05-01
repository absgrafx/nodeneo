.PHONY: go-test go-macos go-ios go-ios-sim go-android flutter-macos flutter-ios flutter-android \
	run-macos run-ios run-ios-sim clean brand-assets check-brand-tools dev-macos \
	sim-grab sim-give ios-clean _ios-stamp-device _ios-stamp-sim

# ── Go builds ──

go-test:
	cd go && go test ./...

# Proxy-router version: if PROXY_ROUTER_DIR points at a local clone of
# Morpheus-Lumerin-Node (with tags fetched), git describe gives e.g.
# "v7.0.0-12-g00562be9" — base release tag + commits since + hash. Falls back
# to the pseudo-version hash already encoded in go.mod.
PROXY_ROUTER_DIR ?= $(realpath ../Morpheus-Lumerin-Node)
PR_VERSION ?= $(shell git -C "$(PROXY_ROUTER_DIR)" describe --tags --always --match 'v*' 2>/dev/null || echo "unknown")
PR_COMMIT  ?= $(shell cd go && grep 'MorpheusAIs/Morpheus-Lumerin-Node/proxy-router' go.mod | grep -oE '[0-9a-f]{12}$$' || echo "unknown")
GO_LDFLAGS  = -s -w \
  -X github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/internal/config.BuildVersion=$(PR_VERSION) \
  -X github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/internal/config.Commit=$(PR_COMMIT)

go-macos:
	mkdir -p build/go
	cd go && CGO_ENABLED=1 go build -buildmode=c-shared -ldflags="$(GO_LDFLAGS)" -o ../build/go/libnodeneo.dylib ./cmd/cshared/

go-ios:
	@echo "==> Building libnodeneo.a for iOS arm64 (c-archive)..."
	@mkdir -p build/go/ios
	cd go && \
	  GOOS=ios GOARCH=arm64 CGO_ENABLED=1 \
	  CC="$$(xcrun --sdk iphoneos -f clang)" \
	  CGO_CFLAGS="-isysroot $$(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=16.0" \
	  CGO_LDFLAGS="-isysroot $$(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=16.0" \
	  GOROOT="$$(/opt/homebrew/bin/go env GOROOT)" \
	  PATH="$$(/opt/homebrew/bin/go env GOROOT)/bin:/opt/homebrew/bin:$$PATH" \
	  go build -buildmode=c-archive -ldflags="$(GO_LDFLAGS)" -o ../build/go/ios/libnodeneo.a ./cmd/cshared/
	@echo "==> iOS static library: build/go/ios/libnodeneo.a"

go-ios-sim:
	@echo "==> Building libnodeneo.a for iOS Simulator arm64 (c-archive)..."
	@mkdir -p build/go/ios-sim
	cd go && \
	  GOOS=ios GOARCH=arm64 CGO_ENABLED=1 \
	  CC="$$(xcrun --sdk iphonesimulator -f clang)" \
	  CGO_CFLAGS="-isysroot $$(xcrun --sdk iphonesimulator --show-sdk-path) -arch arm64 -miphonesimulator-version-min=16.0" \
	  CGO_LDFLAGS="-isysroot $$(xcrun --sdk iphonesimulator --show-sdk-path) -arch arm64 -miphonesimulator-version-min=16.0" \
	  GOROOT="$$(/opt/homebrew/bin/go env GOROOT)" \
	  PATH="$$(/opt/homebrew/bin/go env GOROOT)/bin:/opt/homebrew/bin:$$PATH" \
	  go build -buildmode=c-archive -tags ios -ldflags="$(GO_LDFLAGS)" -o ../build/go/ios-sim/libnodeneo.a ./cmd/cshared/
	@echo "==> iOS Simulator static library: build/go/ios-sim/libnodeneo.a"

go-android:
	cd go && gomobile bind -target=android -o ../build/nodeneo.aar ./mobile/

# ── Flutter builds ──

flutter-macos:
	flutter build macos

flutter-ios:
	flutter build ios --no-codesign

flutter-android:
	flutter build apk

# ── Branding (poka-yoke: fail fast if cairosvg missing) ──

check-brand-tools:
	@python3 -c "import cairosvg" 2>/dev/null || (echo "Install: pip install cairosvg" && false)

# Regenerate PNGs, launcher icons (all platforms), native splash (Android/iOS/Web).
# Does not run flutter clean — use `make dev-macos` for full refresh.
brand-assets: check-brand-tools
	python3 tools/branding/render_launcher_icons.py
	dart run flutter_launcher_icons
	dart run flutter_native_splash:create

# ── Dev shortcuts ──

# Full refresh for macOS debug: clean, pub get, brand pipeline, Go dylib, flutter run.
#   make dev-macos
# Fast iteration without flutter clean:
#   SKIP_CLEAN=1 ./tools/dev_macos.sh
dev-macos:
	@chmod +x tools/dev_macos.sh
	@./tools/dev_macos.sh

run-macos: go-macos _copy-dylib-macos
	flutter run -d macos

_copy-dylib-macos:
	@echo "Ensuring dylib is in Frameworks..."
	@mkdir -p build/macos/Build/Products/Debug/Node Neo.app/Contents/Frameworks 2>/dev/null || true
	@cp build/go/libnodeneo.dylib build/macos/Build/Products/Debug/Node Neo.app/Contents/Frameworks/ 2>/dev/null || true

# Tracks the last iOS slice we built for so switching between device and
# simulator auto-wipes the cross-arch caches Flutter shares between targets.
# Without this, native asset hooks (e.g. objective_c.framework, used by Dart
# FFI plugins) silently keep the wrong slice — a device install then fails
# with "code signature 0xe8008014 / invalid signature" on a simulator binary,
# and a simulator install fails with "linking object built for iOS-simulator"
# on a device binary. Symptom showed up the first time we bounced between
# `make run-ios-sim` (iPad) and `make run-ios` (Phlame) on the same checkout.
IOS_ARCH_STAMP := build/.last-ios-arch

_ios-stamp-device:
	@mkdir -p build
	@if [ -f $(IOS_ARCH_STAMP) ] && [ "$$(cat $(IOS_ARCH_STAMP))" != "device" ]; then \
	  echo "==> iOS arch switched (sim → device): wiping cross-arch caches..."; \
	  rm -rf build/native_assets/ios build/ios; \
	fi
	@echo device > $(IOS_ARCH_STAMP)

_ios-stamp-sim:
	@mkdir -p build
	@if [ -f $(IOS_ARCH_STAMP) ] && [ "$$(cat $(IOS_ARCH_STAMP))" != "sim" ]; then \
	  echo "==> iOS arch switched (device → sim): wiping cross-arch caches..."; \
	  rm -rf build/native_assets/ios build/ios; \
	fi
	@echo sim > $(IOS_ARCH_STAMP)

run-ios: _ios-stamp-device go-ios
	flutter run -d Phlame

SIM_DEVICE ?= iPhone 16 Pro
run-ios-sim: _ios-stamp-sim go-ios-sim
	@echo "==> Symlinking simulator lib for Xcode..."
	@mkdir -p build/go/ios
	@cp build/go/ios-sim/libnodeneo.a build/go/ios/libnodeneo.a
	@# Boot the chosen sim if it isn't already (Flutter only sees booted sims).
	@if ! xcrun simctl list devices booted | grep -q "$(SIM_DEVICE)"; then \
	  echo "==> Booting $(SIM_DEVICE)..."; \
	  xcrun simctl boot "$(SIM_DEVICE)" 2>/dev/null || true; \
	  open -a Simulator; \
	  printf "    waiting for boot"; \
	  for i in 1 2 3 4 5 6 7 8 9 10; do \
	    if xcrun simctl list devices booted | grep -q "$(SIM_DEVICE)"; then echo " ✓"; break; fi; \
	    printf "."; sleep 1; \
	  done; \
	fi
	flutter run -d "$(SIM_DEVICE)"

clean:
	rm -rf build/
	flutter clean 2>/dev/null || true

# Manual escape hatch when the iOS build state is wedged (codesign errors,
# stale Pods, "Could not find Runner.app" because Flutter's expected output
# path drifted). Wipes all iOS-derived artefacts but keeps Go and macOS
# caches. Run before `make run-ios` / `make run-ios-sim` if anything iOS
# starts behaving inexplicably.
ios-clean:
	rm -rf build/ios build/native_assets/ios build/.last-ios-arch ios/Pods ios/Podfile.lock ios/.symlinks
	@echo "==> iOS build state cleaned (Pods, frameworks, native_assets, arch stamp)"

# ── Simulator clipboard helpers ──
# macOS Simulator's "Edit → Automatically Sync Pasteboard" only fires on focus
# change, which is flaky during a copy-paste-into-Cursor workflow. These two
# targets force the transfer explicitly using xcrun simctl pb{copy,paste}.
#
#   make sim-grab    Sim clipboard → Mac clipboard (e.g. after tapping
#                    "Copy Key" inside the running app on the simulator).
#   make sim-give    Mac clipboard → Sim clipboard (e.g. paste your real
#                    wallet private key into an iOS text field on the sim).
#
# Auto-detects the first booted iOS simulator. Override with SIM_UDID=<udid>.
SIM_UDID ?= $(shell xcrun simctl list devices booted -j 2>/dev/null | \
	python3 -c "import json,sys; d=json.load(sys.stdin).get('devices',{}); \
uds=[v['udid'] for k in d for v in d[k] if v.get('state')=='Booted' and ('iPhone' in v.get('name','') or 'iPad' in v.get('name',''))]; \
print(uds[0] if uds else '')" 2>/dev/null)

sim-grab:
	@if [ -z "$(SIM_UDID)" ]; then echo "==> No booted iOS simulator. Boot one with 'xcrun simctl boot <udid>' first."; exit 1; fi
	@xcrun simctl pbpaste $(SIM_UDID) | pbcopy
	@printf "==> Sim → Mac clipboard ✓  ("
	@pbpaste | tr -d '\n' | head -c 60
	@LEN=$$(pbpaste | wc -c | tr -d ' '); printf "%s\n" "  · $$LEN bytes)"

sim-give:
	@if [ -z "$(SIM_UDID)" ]; then echo "==> No booted iOS simulator. Boot one with 'xcrun simctl boot <udid>' first."; exit 1; fi
	@pbpaste | xcrun simctl pbcopy $(SIM_UDID)
	@printf "==> Mac → Sim clipboard ✓  ("
	@pbpaste | tr -d '\n' | head -c 60
	@LEN=$$(pbpaste | wc -c | tr -d ' '); printf "%s\n" "  · $$LEN bytes — long-press an iOS text field and tap Paste)"
