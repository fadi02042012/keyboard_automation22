import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_automation/main.dart';

void main() {
  testWidgets('App starts with empty steps', (WidgetTester tester) async {
    await tester.pumpWidget(const KeyboardAutomationApp());
    expect(find.text('لا توجد خطوات'), findsOneWidget);
  });
}