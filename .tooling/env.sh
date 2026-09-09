#!/usr/bin/env bash
# Masroufi project-local toolchain env — source this, never install/use $HOME paths.
# Usage: source .tooling/env.sh
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export FLUTTER_ROOT="$PROJECT_ROOT/.tooling/flutter-sdk"
export ANDROID_SDK_ROOT="$PROJECT_ROOT/.tooling/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export JAVA_HOME="$PROJECT_ROOT/.tooling/jdk17"
export PUB_CACHE="$PROJECT_ROOT/.tooling/pub-cache"
export GRADLE_USER_HOME="$PROJECT_ROOT/.tooling/gradle-home"
export GOMODCACHE="$PROJECT_ROOT/.tooling/go/pkg/mod"
export GOPATH="$PROJECT_ROOT/.tooling/go"

export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

# Safety: refuse to run if old HOME SDK paths are in play
for p in "$HOME/flutter" "$HOME/Android" "$HOME/jdk17" "$HOME/.masroufi"; do
  if [ -e "$p" ]; then
    echo "WARNING: stale HOME path still exists: $p (should be removed)" >&2
  fi
done
