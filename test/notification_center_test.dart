import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/models/app_notification.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/notification_center_screen.dart';
import 'package:musicians_flutter/views/home_screen.dart';
import 'package:musicians_flutter/widgets/custom_top_bar.dart';

class MockNotificationFirebaseService extends FirebaseService {
  List<AppNotification> _currentList = [];
  final StreamController<List<AppNotification>> _notifController =
      StreamController<List<AppNotification>>.broadcast();
  final StreamController<int> _unreadCountController =
      StreamController<int>.broadcast();

  final List<String> markedReadIds = [];
  int markAllReadCalls = 0;
  String _mockUserId = 'user_test_123';

  void emitNotifications(List<AppNotification> list) {
    _currentList = list;
    _notifController.add(list);
  }

  void emitUnreadCount(int count) {
    _unreadCountController.add(count);
  }

  @override
  String? get currentUserId => _mockUserId;

  void setMockUserId(String uid) {
    _mockUserId = uid;
  }

  @override
  Stream<List<AppNotification>> subscribeToUserNotifications([String? userId]) async* {
    yield _currentList;
    yield* _notifController.stream;
  }

  @override
  Stream<int> subscribeToUnreadNotificationCount([String? userId]) {
    return _unreadCountController.stream;
  }

  @override
  Stream<bool> subscribeToUnreadNotifications() {
    return Stream.value(false);
  }

  @override
  Future<void> markNotificationReadAsync(String notificationId) async {
    markedReadIds.add(notificationId);
  }

  @override
  Future<void> markAllNotificationsReadAsync() async {
    markAllReadCalls++;
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: userId ?? _mockUserId,
      displayName: 'Alex Test',
      email: 'alex@example.com',
    );
  }

  void dispose() {
    _notifController.close();
    _unreadCountController.close();
  }
}

class MockNotificationAppState extends AppState {
  final MockNotificationFirebaseService mockFirebase;
  int _customUnreadCount = 0;

  MockNotificationAppState(this.mockFirebase);

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => mockFirebase.currentUserId;

  @override
  int get unreadNotificationCount => _customUnreadCount;

  @override
  void setUnreadNotificationCountForTest(int count) {
    _customUnreadCount = count;
    notifyListeners();
  }

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: mockFirebase.currentUserId ?? 'user_test_123',
        displayName: 'Alex Test',
        email: 'alex@example.com',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('AppNotification Model Tests', () {
    test('1. Deserializes full JSON with all fields properly', () {
      final json = {
        'id': 'notif_100',
        'type': 'event_invite',
        'category': 'events',
        'title': 'New Event Invite',
        'body': 'You are invited to rehearsal',
        'createdAt': 1690000000000,
        'isRead': false,
        'readAt': null,
        'data': {
          'bandId': 'band_1',
          'eventId': 'event_1',
        },
      };

      final notif = AppNotification.fromJson(json, 'notif_100');
      expect(notif.id, 'notif_100');
      expect(notif.type, 'event_invite');
      expect(notif.category, 'events');
      expect(notif.title, 'New Event Invite');
      expect(notif.body, 'You are invited to rehearsal');
      expect(notif.createdAt, 1690000000000);
      expect(notif.isRead, false);
      expect(notif.readAt, isNull);
      expect(notif.data['bandId'], 'band_1');
    });

    test('2. Resolves category correctly across all supported notification types', () {
      expect(AppNotification.resolveCategory('direct_message'), 'messages');
      expect(AppNotification.resolveCategory('band_room_message'), 'messages');
      expect(AppNotification.resolveCategory('band_section_chat'), 'messages');
      expect(AppNotification.resolveCategory('session_message'), 'messages');

      expect(AppNotification.resolveCategory('event_invite'), 'events');
      expect(AppNotification.resolveCategory('event_reminder'), 'events');
      expect(AppNotification.resolveCategory('event_threshold'), 'events');

      expect(AppNotification.resolveCategory('sub_request_invite'), 'requests');
      expect(AppNotification.resolveCategory('grouped_sub_request'), 'requests');
      expect(AppNotification.resolveCategory('gig_finalized'), 'requests');
      expect(AppNotification.resolveCategory('session_application'), 'requests');
      expect(AppNotification.resolveCategory('session_application_status'), 'requests');

      expect(AppNotification.resolveCategory('sound_test'), 'system');
      expect(AppNotification.resolveCategory('unknown_custom_type'), 'system');
      expect(AppNotification.resolveCategory(null), 'system');
    });

    test('3. Handles various timestamp formats resiliently', () {
      // Milliseconds int
      final n1 = AppNotification.fromJson({
        'createdAt': 1700000000000,
      }, 'n1');
      expect(n1.createdAt, 1700000000000);

      // ISO-8601 string
      final n2 = AppNotification.fromJson({
        'createdAt': '2026-09-17T12:00:00.000Z',
      }, 'n2');
      final dt = DateTime.fromMillisecondsSinceEpoch(n2.createdAt);
      expect(dt.year, 2026);
      expect(dt.month, 9);

      // Null or invalid fallback
      final n3 = AppNotification.fromJson({
        'createdAt': null,
      }, 'n3');
      expect(n3.createdAt, isPositive);
    });

    test('4. copyWith updates fields correctly', () {
      final notif = AppNotification(
        id: 'n_orig',
        type: 'event_invite',
        category: 'events',
        title: 'Original',
        body: 'Body',
        createdAt: 1700000000000,
        isRead: false,
      );

      final updated = notif.copyWith(isRead: true, readAt: 1700000005000);
      expect(updated.id, 'n_orig');
      expect(updated.title, 'Original');
      expect(updated.isRead, true);
      expect(updated.readAt, 1700000005000);
    });

    test('5. toJson produces valid map structure', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final notif = AppNotification(
        id: 'n_json',
        type: 'gig_finalized',
        category: 'requests',
        title: 'Gig Finalized',
        body: 'You are booked!',
        createdAt: now,
        isRead: true,
        readAt: now,
        data: {'subRequestId': 'sub_123'},
      );

      final json = notif.toJson();
      expect(json['id'], 'n_json');
      expect(json['type'], 'gig_finalized');
      expect(json['category'], 'requests');
      expect(json['title'], 'Gig Finalized');
      expect(json['isRead'], true);
      expect(json['data']['subRequestId'], 'sub_123');
    });
  });

  group('NotificationCenterView Component Tests', () {
    testWidgets('1. Renders NotificationCenterView with header, unread count, and tabs', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final notifications = [
        AppNotification(
          id: 'n1',
          type: 'event_invite',
          category: 'events',
          title: 'Gig Invitation',
          body: 'You have been invited to Summer Fest',
          createdAt: now - 300000,
          isRead: false,
        ),
        AppNotification(
          id: 'n2',
          type: 'direct_message',
          category: 'messages',
          title: 'Message from Alex',
          body: 'Hey, are you free tomorrow?',
          createdAt: now - 3600000,
          isRead: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: NotificationCenterView(
              notifications: notifications,
              isLoading: false,
              unreadCount: 1,
              onMarkAllRead: () {},
              onNotificationTap: (_) {},
            ),
          ),
        ),
      );

      // Verify Header and Badges
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Mark all as read'), findsOneWidget);

      // Verify Category Filter Tabs
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);

      // Both notifications should be visible in 'All' tab
      expect(find.text('Gig Invitation'), findsOneWidget);
      expect(find.text('Message from Alex'), findsOneWidget);
    });

    testWidgets('2. Category filtering switches views properly', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final notifications = [
        AppNotification(
          id: 'n_event',
          type: 'event_invite',
          category: 'events',
          title: 'Event Note',
          body: 'Event body',
          createdAt: now - 600000,
          isRead: false,
        ),
        AppNotification(
          id: 'n_msg',
          type: 'direct_message',
          category: 'messages',
          title: 'Direct Note',
          body: 'Direct body',
          createdAt: now - 1200000,
          isRead: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: NotificationCenterView(
              notifications: notifications,
              isLoading: false,
              unreadCount: 2,
              onMarkAllRead: () {},
              onNotificationTap: (_) {},
            ),
          ),
        ),
      );

      // Both visible initially
      expect(find.text('Event Note'), findsOneWidget);
      expect(find.text('Direct Note'), findsOneWidget);

      // Tap 'Messages' tab
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      expect(find.text('Direct Note'), findsOneWidget);
      expect(find.text('Event Note'), findsNothing);

      // Tap 'Events' tab
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      expect(find.text('Event Note'), findsOneWidget);
      expect(find.text('Direct Note'), findsNothing);

      // Tap 'Requests' tab (empty)
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();

      expect(find.text('No notifications in this category.'), findsOneWidget);
    });

    testWidgets('3. Tap on notification triggers callback with correct item', (tester) async {
      AppNotification? tappedItem;
      final notif = AppNotification(
        id: 'n_tap_1',
        type: 'session_application',
        category: 'requests',
        title: 'Session Application',
        body: 'New request to join session',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isRead: false,
        data: {'sessionId': 'sess_999'},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: NotificationCenterView(
              notifications: [notif],
              isLoading: false,
              unreadCount: 1,
              onMarkAllRead: () {},
              onNotificationTap: (item) {
                tappedItem = item;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Session Application'));
      await tester.pumpAndSettle();

      expect(tappedItem, isNotNull);
      expect(tappedItem!.id, 'n_tap_1');
      expect(tappedItem!.data['sessionId'], 'sess_999');
    });

    testWidgets('4. "Mark all as read" button triggers callback', (tester) async {
      bool markAllCalled = false;
      final notif = AppNotification(
        id: 'n_mark_1',
        type: 'event_reminder',
        category: 'events',
        title: 'RSVP Reminder',
        body: 'Reminder body',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isRead: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: NotificationCenterView(
              notifications: [notif],
              isLoading: false,
              unreadCount: 1,
              onMarkAllRead: () {
                markAllCalled = true;
              },
              onNotificationTap: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();

      expect(markAllCalled, isTrue);
    });

    testWidgets('5. Renders cleanly on narrow 320px viewport without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now().millisecondsSinceEpoch;
      final notifs = List.generate(
        5,
        (index) => AppNotification(
          id: 'n_$index',
          type: 'event_invite',
          category: 'events',
          title: 'Long Title For Notification Event Number $index',
          body: 'This is a long description to ensure wrapping works correctly on 320px screens without any RenderFlex overflow.',
          createdAt: now - (index * 3600000),
          isRead: index % 2 == 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: NotificationCenterView(
              notifications: notifs,
              isLoading: false,
              unreadCount: 3,
              onMarkAllRead: () {},
              onNotificationTap: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('CustomTopBar Notification Bell & Badge Tests', () {
    testWidgets('1. Bell icon is present in CustomTopBar without badge when unread is 0', (tester) async {
      final mockService = MockNotificationFirebaseService();
      final appState = MockNotificationAppState(mockService);
      appState.setUnreadNotificationCountForTest(0);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const Scaffold(
              appBar: CustomTopBar(),
              body: SizedBox(),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('2. Badge displays exact count for 1 to 99', (tester) async {
      final mockService = MockNotificationFirebaseService();
      final appState = MockNotificationAppState(mockService);
      appState.setUnreadNotificationCountForTest(5);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const Scaffold(
              appBar: CustomTopBar(),
              body: SizedBox(),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      appState.setUnreadNotificationCountForTest(99);
      await tester.pumpAndSettle();
      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('3. Badge displays 99+ when unread count is 100 or greater', (tester) async {
      final mockService = MockNotificationFirebaseService();
      final appState = MockNotificationAppState(mockService);
      appState.setUnreadNotificationCountForTest(100);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const Scaffold(
              appBar: CustomTopBar(),
              body: SizedBox(),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('Compact Notification Panel Integration Tests', () {
    testWidgets('1. Desktop viewport (>600px): opens right-aligned dialog and dismisses on close', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockService = MockNotificationFirebaseService();
      final appState = MockNotificationAppState(mockService);
      appState.setUnreadNotificationCountForTest(2);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const Scaffold(
              appBar: CustomTopBar(),
              body: SizedBox(),
            ),
          ),
        ),
      );

      // Tap the notification bell in top bar
      await tester.tap(find.byIcon(Icons.notifications_outlined), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Panel title should be visible in the open dialog
      expect(find.text('NOTIFICATIONS'), findsOneWidget);

      // Tap close button in header
      await tester.tap(find.byIcon(Icons.close_rounded), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Panel should now be closed
      expect(find.text('NOTIFICATIONS'), findsNothing);
    });

    testWidgets('2. Mobile viewport (<=600px): opens bottom sheet and dismisses on close', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockService = MockNotificationFirebaseService();
      final appState = MockNotificationAppState(mockService);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const Scaffold(
              appBar: CustomTopBar(),
              body: SizedBox(),
            ),
          ),
        ),
      );

      // Tap the notification bell in top bar
      await tester.tap(find.byIcon(Icons.notifications_outlined), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Bottom sheet should display notification header
      expect(find.text('NOTIFICATIONS'), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(Icons.close_rounded), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('NOTIFICATIONS'), findsNothing);
    });

    testWidgets('3. Tapping notification item in panel triggers action, marks as read, and closes panel', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockService = MockNotificationFirebaseService();
      final appState = MockNotificationAppState(mockService);

      final notif = AppNotification(
        id: 'notif_panel_1',
        type: 'event_invite',
        category: 'events',
        title: 'Panel Event Invite',
        body: 'Click here to inspect details',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isRead: false,
        data: {'bandId': 'b1', 'eventId': 'e1'},
      );

      AppNotification? tappedItem;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showNotificationPanel(
                          context,
                          onNotificationTapForTest: (item) {
                            tappedItem = item;
                          },
                        );
                      },
                      child: const Text('Open Panel'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Emit notification stream event
      mockService.emitNotifications([notif]);

      // Open panel
      await tester.tap(find.text('Open Panel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Panel Event Invite'), findsOneWidget);

      // Tap the notification item
      await tester.tap(find.text('Panel Event Invite'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Panel should close and test callback should have received item
      expect(find.text('NOTIFICATIONS'), findsNothing);
      expect(tappedItem, isNotNull);
      expect(tappedItem!.id, 'notif_panel_1');
    });

    testWidgets('4. HomeView no longer contains full-width Notifications card', (tester) async {
      final mockService = MockNotificationFirebaseService();
      final appState = MockNotificationAppState(mockService);
      appState.setUnreadNotificationCountForTest(5);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const Scaffold(
              body: HomeScreen(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In standard HomeView, there should NOT be a "5 unread notifications" card
      expect(find.text('5 unread notifications'), findsNothing);
      expect(find.text('No unread notifications'), findsNothing);
    });
  });
}