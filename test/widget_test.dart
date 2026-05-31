// This is a basic Flutter widget test for the login screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';

import 'package:musicians_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('Login screen elements smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Verify that our login title "Musicians Only" is present.
    expect(find.text('Musicians Only'), findsOneWidget);
    
    // Verify that the email and password labels are present.
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    // Verify there is a submit button with the text "Login"
    expect(find.text('Login'), findsOneWidget);
    
    // Verify registration link is visible
    expect(find.text('Register here'), findsOneWidget);
  });
}


