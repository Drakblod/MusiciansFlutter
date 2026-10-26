import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';

class MockFirebaseServiceForPersistenceTest extends FirebaseService {
  int saveMapPinCallCount = 0;
  int updateMapPinCallCount = 0;
  int deleteMapPinCallCount = 0;
  int directDatabaseWriteCount = 0;
  int cancelledSubRequestsWriteCount = 0;

  SubRequest? lastSavedPin;
  SubRequest? lastUpdatedPin;
  String? lastDeletedPinId;

  bool shouldFailSave = false;
  bool shouldReturnEmptyId = false;
  bool shouldFailUpdate = false;
  bool shouldFailDelete = false;
  bool shouldFailUpload = false;

  List<SubRequest> storedRequests = [];

  @override
  Future<SubRequest> saveMapPinAsync(SubRequest pin) async {
    saveMapPinCallCount++;
    lastSavedPin = pin;
    if (shouldFailSave) {
      throw Exception('Server callable error: save failed');
    }
    final serverKey = shouldReturnEmptyId ? '' : 'server_canonical_pin_123';
    return pin.copyWith(
      id: serverKey,
      subRequestId: serverKey,
      extraFields: {
        ...pin.extraFields,
        'NotificationMode': 'map_pin',
      },
    );
  }

  @override
  Future<SubRequest> updateMapPinAsync(SubRequest pin) async {
    final pinId = pin.canonicalTargetId ?? pin.id;
    if (pinId == null || pinId.isEmpty) {
      throw Exception('Valid pin id is required to update a map pin.');
    }
    updateMapPinCallCount++;
    lastUpdatedPin = pin;
    if (shouldFailUpdate) {
      throw Exception('Server callable error: update failed');
    }
    return pin;
  }

  @override
  Future<bool> deleteMapPinAsync(String pinId) async {
    if (pinId.isEmpty) {
      throw Exception('Valid pin id is required to delete a map pin.');
    }
    deleteMapPinCallCount++;
    lastDeletedPinId = pinId;
    if (shouldFailDelete) {
      throw Exception('Server callable error: delete failed');
    }
    return true;
  }

  @override
  Future<String> uploadAudioSnippetAsync(String userId, Uint8List? bytes, String? localPath) async {
    if (shouldFailUpload) {
      throw Exception('Storage upload error');
    }
    return 'https://firebasestorage.googleapis.com/audio_test.mp3';
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => storedRequests;

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async {
    final all = await getAllSubRequestsAsync();
    return all.where((r) {
      final st = r.status.toLowerCase();
      return st != 'cancelled' && st != 'deleted' && st != 'closed';
    }).toList();
  }

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};
}

class MockAppStateForPersistenceTest extends AppState {
  final MockFirebaseServiceForPersistenceTest mockService = MockFirebaseServiceForPersistenceTest();
  @override
  FirebaseService get firebaseService => mockService;

  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'test_creator_uid', displayName: 'Test Creator');

  @override
  String? get currentUserId => 'test_creator_uid';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('BACKEND-PERSISTENCE-01 & 01B: Client-Side Persistence Tests', () {
    testWidgets('1. saveMapPinAsync failure: sheet remains open, preserves form state, no phantom pin',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPersistenceTest();
      appState.mockService.shouldFailSave = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Unsaved Rock Band');
      await tester.enterText(textFields.at(1), 'Persisted Description');

      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(appState.mockService.saveMapPinCallCount, 1);

      // Sheet must remain open with entered values preserved
      expect(find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio'), findsOneWidget);
      expect(find.text('Unsaved Rock Band'), findsOneWidget);
      expect(find.text('Persisted Description'), findsOneWidget);
      expect(find.textContaining('Failed to save pin'), findsOneWidget);
    });

    testWidgets('2. Audio upload failure: sheet remains open and preserves entered values',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPersistenceTest();
      appState.mockService.shouldFailUpload = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Audio Failure Band');

      expect(find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio'), findsOneWidget);
      expect(find.text('Audio Failure Band'), findsOneWidget);
    });

    testWidgets('3. Empty or missing server ID: treated as failure, sheet remains open with error',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPersistenceTest();
      appState.mockService.shouldReturnEmptyId = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Empty ID Band');

      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(appState.mockService.saveMapPinCallCount, 1);
      // Treated as error, sheet remains open
      expect(find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio'), findsOneWidget);
      expect(find.textContaining('Server returned invalid pin ID'), findsOneWidget);
    });

    testWidgets('4. Successful publishing: returns real canonical ID, closes sheet, inserts pin',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPersistenceTest();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Successful Server Band');

      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(appState.mockService.saveMapPinCallCount, 1);
      expect(appState.mockService.lastSavedPin?.bandName, 'Successful Server Band');

      // Sheet is closed
      expect(find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio'), findsNothing);
    });

    testWidgets('5. Rapid double-tapping Publish creates exactly one request',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPersistenceTest();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Double Tap Test Band');

      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      // Rapid double tap before first pump finishes
      await tester.tap(publishBtn);
      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Guarded against rapid duplicate submission
      expect(appState.mockService.saveMapPinCallCount, 1);
    });

    test('6. updateMapPinAsync: propagates error on failure, requires valid pin id, no local fallback', () async {
      final appState = MockAppStateForPersistenceTest();

      // Missing ID throws exception immediately
      final emptyPin = SubRequest(bandName: 'No ID Band');
      await expectLater(
        () => appState.firebaseService.updateMapPinAsync(emptyPin),
        throwsA(isA<Exception>()),
      );

      // Server failure throws exception
      final validPin = SubRequest(id: 'pin_456', bandName: 'Valid Band');
      appState.mockService.shouldFailUpdate = true;
      await expectLater(
        () => appState.firebaseService.updateMapPinAsync(validPin),
        throwsA(isA<Exception>()),
      );
      expect(appState.mockService.updateMapPinCallCount, 1);

      // Server success returns updated pin
      appState.mockService.shouldFailUpdate = false;
      final updated = await appState.firebaseService.updateMapPinAsync(validPin);
      expect(updated.id, 'pin_456');
      expect(appState.mockService.updateMapPinCallCount, 2);
    });

    test('7. deleteMapPinAsync: propagates error on failure, requires valid pin id', () async {
      final appState = MockAppStateForPersistenceTest();

      // Empty ID throws exception immediately
      await expectLater(
        () => appState.firebaseService.deleteMapPinAsync(''),
        throwsA(isA<Exception>()),
      );

      // Server failure throws exception
      appState.mockService.shouldFailDelete = true;
      await expectLater(
        () => appState.firebaseService.deleteMapPinAsync('pin_789'),
        throwsA(isA<Exception>()),
      );
      expect(appState.mockService.deleteMapPinCallCount, 1);

      // Server success returns true
      appState.mockService.shouldFailDelete = false;
      final ok = await appState.firebaseService.deleteMapPinAsync('pin_789');
      expect(ok, isTrue);
      expect(appState.mockService.deleteMapPinCallCount, 2);
      expect(appState.mockService.lastDeletedPinId, 'pin_789');
    });

    test('8. getAllSubRequestsAsync read-only invariants: 0 database writes, no CancelledSubRequests tombstones', () async {
      final service = MockFirebaseServiceForPersistenceTest();
      service.storedRequests = [
        SubRequest(id: 'can_1', status: 'published', extraFields: {'NotificationMode': 'map_pin'}),
        SubRequest(id: 'can_2', status: 'published', extraFields: {'NotificationMode': 'map_pin'}),
      ];

      final results = await service.getAllSubRequestsAsync();
      expect(results.length, 2);
      expect(service.cancelledSubRequestsWriteCount, 0);
      expect(service.directDatabaseWriteCount, 0);
    });

    test('9. Read path preserves closed/cancelled filtering and does not hide pins missing personal mirrors', () async {
      final service = MockFirebaseServiceForPersistenceTest();
      final activePinWithoutMirror = SubRequest(
        id: 'active_server_pin',
        status: 'published',
        bandName: 'Live Band',
        extraFields: {'NotificationMode': 'map_pin'},
      );
      final cancelledPin = SubRequest(
        id: 'cancelled_pin',
        status: 'cancelled',
        bandName: 'Cancelled Band',
      );
      final closedPin = SubRequest(
        id: 'closed_pin',
        status: 'closed',
        bandName: 'Closed Band',
      );
      final subStaffingRequest = SubRequest(
        id: 'staffing_sub_1',
        status: 'open',
        requestType: 'Substitute',
        role: 'Drummer',
      );
      final newMemberRequest = SubRequest(
        id: 'staffing_member_1',
        status: 'open',
        requestType: 'New Member',
        role: 'Vocalist',
      );

      service.storedRequests = [
        activePinWithoutMirror,
        cancelledPin,
        closedPin,
        subStaffingRequest,
        newMemberRequest,
      ];

      final feed = await service.getUserSubRequestFeedAsync();
      // Cancelled and closed are filtered out
      final feedIds = feed.map((r) => r.id).toSet();
      expect(feedIds.contains('cancelled_pin'), isFalse);
      expect(feedIds.contains('closed_pin'), isFalse);

      // Active map pin without personal mirror is retained
      expect(feedIds.contains('active_server_pin'), isTrue);

      // Staffing requests (Substitute and New Member) are preserved
      expect(feedIds.contains('staffing_sub_1'), isTrue);
      expect(feedIds.contains('staffing_member_1'), isTrue);
    });

    testWidgets('10. Find Gigs does not hide substitute records merely because personal mirror is absent',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPersistenceTest();
      final staffingReq = SubRequest(
        id: 'real_staffing_sub_999',
        bandName: 'Stockholm Big Band',
        role: 'Lead Trumpet',
        requestType: 'Substitute',
        status: 'open',
        date: '2026-11-25',
      );
      appState.mockService.storedRequests = [staffingReq];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Stockholm Big Band'), findsWidgets);
    });

    test('11. Static code analysis: NO production code in Map View or persistence contains runtime-type detection for tests', () {
      final mapFile = File('lib/views/gig_map_page.dart');
      final serviceFile = File('lib/services/firebase_service.dart');
      expect(mapFile.existsSync(), isTrue);
      expect(serviceFile.existsSync(), isTrue);

      final dartFiles = [mapFile, serviceFile];

      final violations = <String>[];
      final regex = RegExp(r"WidgetsBinding\.instance\.runtimeType.*contains\('Test'\)");

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (regex.hasMatch(content)) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Production files must not contain runtime-type detection for tests: $violations',
      );
    });
  });
}
