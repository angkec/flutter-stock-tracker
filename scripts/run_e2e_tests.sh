#!/bin/bash
set -e

echo "=== E2E Test Runner ==="

# Generate BDD tests from feature files (if needed)
# Note: bdd_widget_test doesn't work well with Chinese Gherkin steps,
# so we use manually written test files instead
# echo "Generating BDD tests..."
# flutter pub run build_runner build --delete-conflicting-outputs

# Determine platform
PLATFORM=${1:-"macos"}

echo "Running e2e tests on $PLATFORM..."

case $PLATFORM in
  ios)
    flutter test integration_test/ -d "iPhone"
    ;;
  android)
    flutter test integration_test/ -d "emulator"
    ;;
  macos)
    flutter test integration_test/ -d "macos"
    ;;
  *)
    echo "Usage: $0 [ios|android|macos]"
    exit 1
    ;;
esac

echo "=== E2E Tests Complete ==="
