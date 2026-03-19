import 'package:flutter_test/flutter_test.dart';
import 'package:redpill/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const RedPillApp());
    expect(find.text('RedPill'), findsOneWidget);
  });
}
