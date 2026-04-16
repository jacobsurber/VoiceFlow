#!/bin/bash

required_apple_macro_plugins=()
required_apple_macro_plugins+=("SwiftDataMacros")
required_apple_macro_plugins+=("FoundationMacros")
required_apple_macro_plugins+=("PreviewsMacros")

active_developer_dir() {
  xcode-select -p 2>/dev/null || echo "unknown"
}

developer_dir_contains_macro_plugin() {
  local developer_dir="$1"
  local plugin_name="$2"

  if [ ! -d "$developer_dir" ]; then
    return 1
  fi

  find "$developer_dir" -iname "*${plugin_name}*" -print -quit 2>/dev/null | grep -q .
}

missing_apple_macro_plugins() {
  local developer_dir="$1"
  local missing_plugins=()
  local plugin_name

  for plugin_name in "${required_apple_macro_plugins[@]}"; do
    if ! developer_dir_contains_macro_plugin "$developer_dir" "$plugin_name"; then
      missing_plugins+=("$plugin_name")
    fi
  done

  if [ ${#missing_plugins[@]} -gt 0 ]; then
    printf '%s\n' "${missing_plugins[@]}"
  fi
}

swiftpm_can_load_scratch_package() {
  local scratch_dir

  scratch_dir=$(mktemp -d)
  if (
    cd "$scratch_dir" || exit 1
    swift package init --type executable >/dev/null 2>&1 || exit 1
    swift package dump-package >/dev/null 2>&1
  ); then
    rm -rf "$scratch_dir"
    return 0
  fi

  rm -rf "$scratch_dir"
  return 1
}

print_swiftpm_toolchain_error() {
  local manifest_output="$1"
  local developer_dir

  developer_dir=$(active_developer_dir)

  echo "❌ Swift Package Manager could not evaluate Package.swift."
  echo ""
  echo "The active Apple toolchain is failing before Whisp can build."
  echo "This machine cannot evaluate this manifest or a brand-new scratch package."
  echo ""
  echo "Active developer directory: $developer_dir"
  echo ""
  echo "Recommended fixes:"
  if [ "$developer_dir" = "/Library/Developer/CommandLineTools" ]; then
    echo "  1. Reinstall Command Line Tools:"
    echo "     sudo rm -rf /Library/Developer/CommandLineTools"
    echo "     xcode-select --install"
    echo "  2. Or install full Xcode and select it:"
    echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  else
    echo "  1. Reinstall or switch the active Xcode/Swift toolchain."
    echo "  2. Verify the toolchain with a scratch package:"
    echo "     swift package init --type executable"
    echo "     swift build"
  fi
  echo ""
  echo "Original SwiftPM error:"
  echo "$manifest_output" | sed -n '1,20p'
}

print_missing_macro_plugins_error() {
  local developer_dir="$1"
  local missing_plugins="$2"

  echo "❌ Whisp requires Apple Swift macro plugins that are not available in the active toolchain."
  echo ""
  echo "Whisp uses SwiftData, Foundation predicate, and SwiftUI preview macros during compilation."
  echo "The current developer directory can evaluate Package.swift, but it cannot load these plugins:"
  echo "$missing_plugins" | sed 's/^/  - /'
  echo ""
  echo "Active developer directory: $developer_dir"
  echo ""
  if [ "$developer_dir" = "/Library/Developer/CommandLineTools" ]; then
    echo "Recommended fix: install full Xcode, open it once, then select it:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "  sudo xcodebuild -runFirstLaunch"
  else
    echo "Recommended fix: switch to a full Xcode developer directory that includes Apple macro plugins."
    echo "If Xcode is installed in the default location, run:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "  sudo xcodebuild -runFirstLaunch"
  fi
  echo ""
  echo "If /Applications/Xcode.app does not exist, install Xcode from the App Store or Apple Developer downloads first."
}

ensure_swiftpm_manifest_is_healthy() {
  local project_dir="${1:-$PWD}"
  local developer_dir
  local manifest_output
  local missing_plugins

  if manifest_output=$(cd "$project_dir" && swift package dump-package 2>&1); then
    developer_dir=$(active_developer_dir)
    missing_plugins=$(missing_apple_macro_plugins "$developer_dir")

    if [ -n "$missing_plugins" ]; then
      print_missing_macro_plugins_error "$developer_dir" "$missing_plugins"
      return 1
    fi

    return 0
  fi

  if ! swiftpm_can_load_scratch_package; then
    print_swiftpm_toolchain_error "$manifest_output"
    return 1
  fi

  echo "$manifest_output"
  return 1
}
