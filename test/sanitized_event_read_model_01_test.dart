import 'dart:async';

import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/event_details_page.dart';
import 'package:musicians_flutter/views/event_results_page.dart';

BandEvent event(String id, {String title = 'Safe Concert'}) => BandEvent(
  id: id,
  title: title,
  description: 'Participant description',
  eventType: 'Concert',
  location: 'Participant venue',
  startDateTime: '2027-01-01T19:00:00Z',
  endDateTime: '2027-01-01T21:00:00Z',
  additionalNotes: '',
  createdBy: 'former_manager',
  createdAt: 1,
  updatedAt: 1,
  requireResponse: true,
);

class EventReadModelService extends FirebaseService {
  final StreamController<BandEvent?> memberEvents = StreamController.broadcast();
  bool manager = false;
  int managerLoads = 0;
  BandEvent? managerEvent;
  StreamController<BandEvent?>? managerUpdates;

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) =>
      memberEvents.stream;

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async =>
      managerEvent == null ? [] : [managerEvent!];

  @override
  Future<Band?> getPublicBandProfileAsync(String bandId) async => null;

  @override
  Future<Band?> getBandInfoAsync(String bandId) async => null;

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async => [];

  @override
  Future<bool> canManageBandEventAsync(String bandId) async => manager;

  @override
  Future<BandEvent?> getManagerBandEventOnceAsync(String bandId, String eventId) async {
    managerLoads++;
    return managerEvent;
  }

  @override
  Future<List<BandEvent>> getManagerBandEventsListAsync(String bandId) async =>
      managerEvent == null ? [] : [managerEvent!];

  @override
  Stream<BandEvent?> subscribeToManagerBandEvent(String bandId, String eventId) =>
      managerUpdates?.stream ?? Stream.value(managerEvent);
}

class EventReadModelState extends AppState {
  EventReadModelState(this.service);
  final EventReadModelService service;
  String? uid = 'member';
  String? selectedBand = 'band_1';
  void switchSession({String? userId, String? bandId}) {
    uid = userId;
    selectedBand = bandId;
    notifyListeners();
  }
  @override
  FirebaseService get firebaseService => service;
  @override
  String? get currentUserId => uid;
  @override
  String? get activeBandId => selectedBand;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Event Details ignores a passed canonical Event until its read model arrives', (tester) async {
    final service = EventReadModelService();
    final state = EventReadModelState(service);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state,
      child: MaterialApp(home: EventDetailsPage(bandId: 'band_1', eventId: 'event_1',
        initialEvent: event('event_1', title: 'Private canonical title')))));
    await tester.pump();
    expect(find.text('Private canonical title'), findsNothing);
    service.memberEvents.add(event('event_1'));
    await tester.pump();
    expect(find.textContaining('Safe Concert'), findsWidgets);
    expect(find.text('Private canonical title'), findsNothing);
    await service.memberEvents.close();
  });

  testWidgets('Event Details removes a revoked or deleted projection', (tester) async {
    final service = EventReadModelService();
    final state = EventReadModelState(service);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state,
      child: MaterialApp(home: EventDetailsPage(bandId: 'band_1', eventId: 'event_1',
        initialEvent: event('event_1')))));
    await tester.pump();
    service.memberEvents.add(event('event_1'));
    await tester.pump();
    service.memberEvents.add(null);
    await tester.pump();
    expect(find.text('Safe Concert'), findsNothing);
    expect(find.text('Event unavailable'), findsOneWidget);
    await service.memberEvents.close();
  });

  testWidgets('former manager fails closed before any manager Event load', (tester) async {
    final service = EventReadModelService()..managerEvent = event('event_1');
    final state = EventReadModelState(service);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state,
      child: const MaterialApp(home: EventResultsPage(bandId: 'band_1', eventId: 'event_1'))));
    await tester.pump();
    await tester.pump();
    expect(service.managerLoads, 0);
    expect(find.textContaining('Only current band leaders and admins'), findsOneWidget);
    await service.memberEvents.close();
  });

  testWidgets('current manager loads an exact manager projection', (tester) async {
    final service = EventReadModelService()
      ..manager = true
      ..managerEvent = event('event_1');
    final state = EventReadModelState(service);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state,
      child: const MaterialApp(home: EventResultsPage(bandId: 'band_1', eventId: 'event_1'))));
    await tester.pump();
    await tester.pump();
    expect(service.managerLoads, 1);
    await service.memberEvents.close();
  });

  testWidgets('Event Details clears rendered content on logout or band switch', (tester) async {
    final service = EventReadModelService();
    final state = EventReadModelState(service);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state,
      child: MaterialApp(home: EventDetailsPage(bandId: 'band_1', eventId: 'event_1',
        initialEvent: event('event_1')))));
    service.memberEvents.add(event('event_1'));
    await tester.pump();
    expect(find.textContaining('Safe Concert'), findsWidgets);
    state.switchSession(userId: null, bandId: null);
    await tester.pump();
    expect(find.textContaining('Safe Concert'), findsNothing);
    expect(find.text('Event unavailable'), findsOneWidget);
    await service.memberEvents.close();
  });

  testWidgets('Event Results clears manager content on user change', (tester) async {
    final service = EventReadModelService()
      ..manager = true
      ..managerEvent = event('event_1');
    final state = EventReadModelState(service);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state,
      child: const MaterialApp(home: EventResultsPage(bandId: 'band_1', eventId: 'event_1'))));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Safe Concert'), findsWidgets);
    state.switchSession(userId: 'another_user', bandId: 'band_2');
    await tester.pump();
    expect(find.textContaining('Safe Concert'), findsNothing);
    expect(find.text('Event results are no longer available.'), findsOneWidget);
    await service.memberEvents.close();
  });

  testWidgets('Event Results clears private data when manager authority is revoked', (tester) async {
    final service = EventReadModelService()
      ..manager = true
      ..managerEvent = event('event_1')
      ..managerUpdates = StreamController<BandEvent?>.broadcast();
    final state = EventReadModelState(service);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state,
      child: const MaterialApp(home: EventResultsPage(bandId: 'band_1', eventId: 'event_1'))));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Safe Concert'), findsWidgets);
    service.managerUpdates!.add(null);
    await tester.pump();
    expect(find.textContaining('Safe Concert'), findsNothing);
    expect(find.text('Event results are no longer available.'), findsOneWidget);
    await service.managerUpdates!.close();
    await service.memberEvents.close();
  });
}
