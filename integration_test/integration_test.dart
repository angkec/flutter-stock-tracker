import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Import test files
import 'features/navigation_test.dart' as navigation;
import 'features/watchlist_test.dart' as watchlist;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Run all integration tests
  // Note: The tests in features/ folder are manually written based on .feature files
  // because bdd_widget_test couldn't properly generate code from Chinese Gherkin steps
  navigation.main();
  watchlist.main();
}
