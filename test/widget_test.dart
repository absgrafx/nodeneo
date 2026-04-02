import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeneo/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const NodeNeoApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
