#!/bin/bash

cd "$(dirname "$0")"
cd ..

WORKSPACE="Litext.xcworkspace"

function test_build() {
	SCHEME=$1
	DESTINATION=$2
	echo "[*] test build for $SCHEME on $DESTINATION"
	xcodebuild -scheme "$SCHEME" -workspace $WORKSPACE -destination "$DESTINATION" \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		| xcbeautify --disable-logging
	EXIT_CODE=${PIPESTATUS[0]}
	echo "[*] finished with exit code $EXIT_CODE"
	if [ $EXIT_CODE -ne 0 ]; then
		echo "[!] failed to build $SCHEME for $DESTINATION"
		exit 1
	fi
}

function test_scheme() {
	SCHEME=$1
	DESTINATION=$2
	shift 2
	echo "[*] test $SCHEME on $DESTINATION"
	LITEXT_SCREENSHOT_DIR="${LITEXT_SCREENSHOT_DIR:-$PWD/Artworks/RenderingAudit}" \
		xcodebuild test -scheme "$SCHEME" -workspace $WORKSPACE -destination "$DESTINATION" \
		"$@" \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		| xcbeautify --disable-logging
	EXIT_CODE=${PIPESTATUS[0]}
	echo "[*] finished with exit code $EXIT_CODE"
	if [ $EXIT_CODE -ne 0 ]; then
		echo "[!] failed to test $SCHEME for $DESTINATION"
		exit 1
	fi
}

function first_available_ios_simulator_id() {
	SCHEME=${1:-OhMyLitext}
	xcodebuild -scheme "$SCHEME" -workspace "$WORKSPACE" -showdestinations 2>/dev/null \
		| awk -F '[{},]' '
			/platform:iOS Simulator/ && /name:iPhone/ {
				for (field = 1; field <= NF; field++) {
					gsub(/^ +| +$/, "", $field)
					if ($field ~ /^id:/) {
						sub(/^id:/, "", $field)
						print $field
						exit
					}
				}
			}
		'
}

# to reset all cache
# rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/org.llvm.clang/ModuleCache"
# rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/org.llvm.clang.$(whoami)/ModuleCache"
# rm -rf ~/Library/Developer/Xcode/DerivedData/*
# rm -rf ~/Library/Caches/com.apple.dt.Xcode/*
# rm -rf ~/Library/Caches/org.swift.swiftpm
# rm -rf ~/Library/org.swift.swiftpm

test_build "OhMyLitext" "generic/platform=macOS"
test_build "OhMyLitext" "generic/platform=macOS,variant=Mac Catalyst"
test_build "OhMyLitext" "generic/platform=iOS"
test_build "OhMyLitext" "generic/platform=iOS Simulator"
test_build "OhMyLitext" "generic/platform=tvOS"
test_build "OhMyLitext" "generic/platform=tvOS Simulator"
test_build "OhMyLitext" "generic/platform=xrOS"
test_build "OhMyLitext" "generic/platform=xrOS Simulator"
test_build "OhMyLitextWatch Watch App" "generic/platform=watchOS"
test_build "OhMyLitextWatch Watch App" "generic/platform=watchOS Simulator"

test_scheme "OhMyLitext" "platform=macOS" "-only-testing:OhMyLitextTests"

IOS_SIMULATOR_ID=$(first_available_ios_simulator_id "OhMyLitext")
if [ -z "$IOS_SIMULATOR_ID" ]; then
	echo "[!] failed to locate an available iPhone simulator"
	exit 1
fi
test_scheme "OhMyLitext" "id=$IOS_SIMULATOR_ID"
