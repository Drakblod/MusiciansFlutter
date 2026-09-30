import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/event_room.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:provider/provider.dart';

class MockFirebaseServiceForHoldTest extends Fake implements FirebaseService {
  final Map<String, dynamic> mockBandData = {
    'BandName': 'Rock Legends',
    'UserRole': 'Leader',
    'Members_band': {
      'user_leader': {
        'Role': 'Leader',
        'Nickname': 'Alex Leader',
        'Instrument': 'Vocals',
        'Status': 'active',
      },
      'user_injured': {
        'Role': 'Member',
        'Nickname': 'Dave Drummer',
        'Instrument': 'Drums',
        'Status': 'on_hold',
      },
      'user_active': {
        'Role': 'Member',
        'Nickname': 'Gary Guitar',
        'Instrument': 'Guitar',
        'Status': 'active',
      },
    },
  };

  final Map<String, UserProfile> userProfiles = {
    'user_leader': UserProfile(
      userId: 'user_leader',
      displayName: 'Alex Leader',
      mainInstrument: 'Vocals',
    ),
    'user_injured': UserProfile(
      userId: 'user_injured',
      displayName: 'Dave Drummer',
      mainInstrument: 'Drums',
    ),
    'user_active': UserProfile(
      userId: 'user_active',
      displayName: 'Gary Guitar',
      mainInstrument: 'Guitar',
    ),
  };

  String? lastUpdatedUserId;
  String? lastUpdatedStatus;

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return Band.fromJson(mockBandData, bandId);
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    final raw = mockBandData['Members_band'] as Map<String, dynamic>?;
    if (raw == null) return [];
    return raw.entries.map((e) => BandMember.fromJson(e.value as Map<dynamic, dynamic>, e.key)).toList();
  }

  @override
  Future<Map<String, Map<String, String>>> getBandFilesAsync(String bandId) async {
    return {};
  }

  @override
  Stream<List<Message>> subscribeToBandMessages(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<EventRoom>> subscribeToBandEventRooms(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<Map<String, dynamic>>> subscribeToGigsNews(String bandId) {
    return Stream.value([]);
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return {'band_123': 'Rock Legends'};
  }

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async {
    return 'Leader';
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    if (userId == null) return userProfiles['user_leader'];
    return userProfiles[userId];
  }

  @override
  Future<void> updateBandMemberStatusAsync(String bandId, String userId, String newStatus) async {
    lastUpdatedUserId = userId;
    lastUpdatedStatus = newStatus;
    if (mockBandData['Members_band'] != null &&
        mockBandData['Members_band'][userId] != null) {
      mockBandData['Members_band'][userId]['Status'] = newStatus;
    }
  }

  @override
  Future<void> removeBandMemberAsync(String bandId, String userId) async {
    mockBandData['Members_band']?.remove(userId);
  }

  @override
  Future<void> updateBandAsync(String bandId, Band band) async {}
}

class MockAppStateForHoldTest extends Fake with ChangeNotifier implements AppState {
  final MockFirebaseServiceForHoldTest mockFirebase = MockFirebaseServiceForHoldTest();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => 'user_leader';

  @override
  String? get activeBandId => 'band_123';

  @override
  String? get activeBandName => 'Rock Legends';

  @override
  UserProfile? get currentUserProfile => UserProfile(
    userId: 'user_leader',
    displayName: 'Alex Leader',
    mainInstrument: 'Vocals',
  );

  @override
  bool get hasUnreadMessages => false;

  @override
  int get unreadNotificationCount => 0;

  @override
  List<String> get selectedBubbles => ['find_musicians', 'band_room', 'create_event'];

  @override
  void selectBand(String bandId, String bandName) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BandMember status & on-hold model tests', () {
    test('BandMember correctly parses active vs on_hold status', () {
      final activeMember = BandMember.fromJson({
        'Role': 'Member',
        'Status': 'active',
      }, 'user1');
      expect(activeMember.isOnHold, isFalse);
      expect(activeMember.isActive, isTrue);

      final holdMember = BandMember.fromJson({
        'Role': 'Member',
        'Status': 'on_hold',
      }, 'user2');
      expect(holdMember.isOnHold, isTrue);
      expect(holdMember.isActive, isFalse);

      final tempOffMember = BandMember.fromJson({
        'Role': 'Member',
        'Status': 'temporarily_off',
      }, 'user3');
      expect(tempOffMember.isOnHold, isTrue);
      expect(tempOffMember.isActive, isFalse);
    });

    test('BandMember toJson retains Status field', () {
      final member = BandMember(
        userId: 'u1',
        role: 'Guitarist',
        status: 'on_hold',
      );
      final json = member.toJson();
      expect(json['Status'], 'on_hold');
      expect(json['Role'], 'Guitarist');
    });
  });

  group('BandRoomChatScreen On Hold UI tests', () {
    late MockAppStateForHoldTest appState;

    setUp(() {
      appState = MockAppStateForHoldTest();
    });

    testWidgets('renders ON HOLD badge on on-hold members in Members tab', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const BandRoomChatScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Members tab (tab index 3)
      final membersTab = find.text('Members');
      expect(membersTab, findsOneWidget);
      await tester.tap(membersTab);
      await tester.pumpAndSettle();

      // Verify members are listed
      expect(find.text('Dave Drummer'), findsOneWidget);
      expect(find.text('Gary Guitar'), findsOneWidget);

      // Verify ON HOLD badge is displayed for Dave Drummer
      expect(find.text('ON HOLD'), findsWidgets);
    });

    testWidgets('Leader can toggle member on-hold status', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const BandRoomChatScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Go to Members tab
      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();

      // Find reactivate button for Dave Drummer (who is currently on_hold)
      final playIcons = find.byIcon(Icons.play_arrow_rounded);
      expect(playIcons, findsWidgets);

      await tester.tap(playIcons.first);
      await tester.pumpAndSettle();

      expect(appState.mockFirebase.lastUpdatedUserId, 'user_injured');
      expect(appState.mockFirebase.lastUpdatedStatus, 'active');
    });
  });

  group('EditBandInfoScreen On Hold UI tests', () {
    late MockAppStateForHoldTest appState;

    setUp(() {
      appState = MockAppStateForHoldTest();
    });

    testWidgets('displays ON HOLD badge for on-hold members in EditBandInfoScreen', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));

      final band = Band(
        id: 'band_123',
        name: 'Rock Legends',
        userRole: 'Leader',
        membersBand: {
          'user_leader': BandMember(userId: 'user_leader', role: 'Leader', status: 'active'),
          'user_injured': BandMember(userId: 'user_injured', role: 'Member', status: 'on_hold'),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: EditBandInfoScreen(band: band),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify ON HOLD badge is present
      expect(find.text('ON HOLD'), findsOneWidget);
    });
  });
}
