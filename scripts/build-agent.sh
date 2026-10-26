#!/bin/bash
# Xcode build phase: compile the Android helper and embed it in the app resources.
set -euo pipefail

ROOT="${SRCROOT:?Run this script as the Xcode Build Android agent phase.}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
ANDROID_JAR="$SDK/platforms/android-36/android.jar"
D8="$SDK/build-tools/36.0.0/d8"
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home)}"
export PATH="$JAVA_HOME/bin:$PATH"
if [[ ! -f "$ANDROID_JAR" || ! -x "$D8" ]]; then
  echo 'error: Install Android SDK platform 36 and Build Tools 36.0.0. Set ANDROID_SDK_ROOT for a custom SDK location.' >&2
  exit 1
fi
BUILD_DIR="${DERIVED_FILE_DIR:?}/android-agent"
RESOURCES="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
mkdir -p "$BUILD_DIR" "$RESOURCES"
# These directories contain only this build phase's generated files.
rm -rf "$BUILD_DIR/stubs" "$BUILD_DIR/classes" "$BUILD_DIR/dex"
mkdir -p "$BUILD_DIR/stubs" "$BUILD_DIR/classes" "$BUILD_DIR/dex"
stub_sources=()
while IFS= read -r -d '' source; do stub_sources+=("$source"); done < <(find "$ROOT/Android/stubs" -name '*.java' -print0)
javac -source 8 -target 8 -cp "$ANDROID_JAR" -d "$BUILD_DIR/stubs" "${stub_sources[@]}"
jar cf "$BUILD_DIR/hidden-api-stubs.jar" -C "$BUILD_DIR/stubs" .
agent_sources=()
while IFS= read -r -d '' source; do agent_sources+=("$source"); done < <(find "$ROOT/Android/src" -name '*.java' ! -name '*Test.java' -print0)
javac -source 8 -target 8 -cp "$ANDROID_JAR:$BUILD_DIR/hidden-api-stubs.jar" -d "$BUILD_DIR/classes" "${agent_sources[@]}"
if [[ "${WEFT_ANDROID_TESTS:-NO}" == YES ]]; then
  test_sources=()
  while IFS= read -r -d '' source; do test_sources+=("$source"); done < <(find "$ROOT/Android/src" -name '*Test.java' -print0)
  mkdir -p "$BUILD_DIR/tests"
  javac -source 8 -target 8 -cp "$BUILD_DIR/classes" -d "$BUILD_DIR/tests" "${test_sources[@]}"
  java -cp "$BUILD_DIR/classes:$BUILD_DIR/tests" io.baiyanwu.weft.ParserTest
  java -cp "$BUILD_DIR/classes:$BUILD_DIR/tests" io.baiyanwu.weft.AbsoluteMouseReportTest
  java -cp "$BUILD_DIR/classes:$BUILD_DIR/tests" io.baiyanwu.weft.MouseButtonMapperTest
  java -cp "$BUILD_DIR/classes:$BUILD_DIR/tests" io.baiyanwu.weft.KeyboardReportTest
fi
classes=()
while IFS= read -r -d '' source; do classes+=("$source"); done < <(find "$BUILD_DIR/classes" -name '*.class' -print0)
"$D8" --lib "$ANDROID_JAR" --classpath "$BUILD_DIR/hidden-api-stubs.jar" --min-api 26 --output "$BUILD_DIR/dex" "${classes[@]}"
cp "$BUILD_DIR/dex/classes.dex" "$RESOURCES/weft-agent.dex"
