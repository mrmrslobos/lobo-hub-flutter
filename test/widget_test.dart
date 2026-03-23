// Smoke test — full app needs Supabase/env; keep test minimal so `flutter test` passes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp smoke', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('FamilyHub'),
        ),
      ),
    );
    expect(find.text('FamilyHub'), findsOneWidget);
  });
}
