// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_scan/main.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // Build the app and ensure it doesn't throw during build.
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MainApp(cameras: [], navigatorKey: key));

    // Basic smoke check: main scaffold is present
    expect(find.byType(MainApp), findsOneWidget);
  });
}
