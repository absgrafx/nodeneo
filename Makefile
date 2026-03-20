.PHONY: go-test go-macos go-ios go-android flutter-macos flutter-ios run-macos run-ios clean

# ── Go builds ──

go-test:
	cd go && go test ./...

go-macos:
	mkdir -p build/go
	cd go && CGO_ENABLED=1 go build -buildmode=c-shared -ldflags="-s -w" -o ../build/go/libredpill.dylib ./cmd/cshared/

go-ios:
	cd go && gomobile bind -target=ios -o ../build/Redpill.xcframework ./mobile/

go-android:
	cd go && gomobile bind -target=android -o ../build/redpill.aar ./mobile/

# ── Flutter builds ──

flutter-macos:
	flutter build macos

flutter-ios:
	flutter build ios --no-codesign

flutter-android:
	flutter build apk

# ── Dev shortcuts ──

run-macos: go-macos _copy-dylib-macos
	flutter run -d macos

_copy-dylib-macos:
	@echo "Ensuring dylib is in Frameworks..."
	@mkdir -p build/macos/Build/Products/Debug/redpill.app/Contents/Frameworks 2>/dev/null || true
	@cp build/go/libredpill.dylib build/macos/Build/Products/Debug/redpill.app/Contents/Frameworks/ 2>/dev/null || true

run-ios: go-ios
	flutter run -d iphone

clean:
	rm -rf build/
	flutter clean 2>/dev/null || true
