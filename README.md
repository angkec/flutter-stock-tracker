# stock_rtwatcher

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Testing Notes

- This project supports parallel test execution (for example: `flutter test -j 8`).
- Test database isolation is configured in `test/flutter_test_config.dart`.
- The test bootstrap assigns a per-process temporary SQLite directory, which prevents cross-worker DB lock/contention issues.
