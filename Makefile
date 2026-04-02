.PHONY: go-test go-macos go-ios go-android flutter-macos flutter-ios flutter-android \
	run-macos run-ios clean brand-assets check-brand-tools dev-macos

# ── Go builds ──

go-test:
	cd go && go test ./...

go-macos:
	mkdir -p build/go
	cd go && CGO_ENABLED=1 go build -buildmode=c-shared -ldflags="-s -w" -o ../build/go/libnodeneo.dylib ./cmd/cshared/

go-ios:
	@echo "==> Building libnodeneo.a for iOS arm64 (c-archive)..."
	@mkdir -p build/go/ios
	cd go && \
	  GOOS=ios GOARCH=arm64 CGO_ENABLED=1 \
	  CC="$$(xcrun --sdk iphoneos -f clang)" \
	  CGO_CFLAGS="-isysroot $$(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=13.0" \
	  CGO_LDFLAGS="-isysroot $$(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=13.0" \
	  GOROOT="$$(/opt/homebrew/bin/go env GOROOT)" \
	  PATH="$$(/opt/homebrew/bin/go env GOROOT)/bin:/opt/homebrew/bin:$$PATH" \
	  go build -buildmode=c-archive -ldflags="-s -w" -o ../build/go/ios/libnodeneo.a ./cmd/cshared/
	@echo "==> iOS static library: build/go/ios/libnodeneo.a"

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

run-ios: go-ios
	flutter run -d Phlame

clean:
	rm -rf build/
	flutter clean 2>/dev/null || true
