import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const DriverFleetApp());
    // Verify app renders the Home Page title
    expect(find.text('Home Page'), findsOneWidget);
  });
}
