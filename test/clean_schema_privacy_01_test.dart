import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart' as auth;
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/utils/catalogue_profiles.dart';
import 'package:musicians_flutter/views/public_band_profile_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'membership_authority_hardening_01_test.dart' as authority;
import 'safe_catalogue_projections_01_test.dart' as catalogue;
import 'manage_requests_lifecycle_01_test.dart' as manage;
import 'registration_secondary_skills_01_test.dart' as fixtures;

class BandReadService extends FirebaseService {
  BandReadService({required super.membershipRead, required super.catalogueRead});
  String? uid = 'viewer';
  final identities = StreamController<String?>.broadcast(sync: true);
  @override
  String? get currentUserId => uid;
  @override
  Stream<String?> get catalogueIdentityChanges => identities.stream;
  void switchTo(String? next) { uid = next; identities.add(next); }
}

class RevocableRequestsService extends manage.ManageService {
  final access = StreamController<int>.broadcast(sync: true);
  @override
  Stream<int> subscribeToSubRequestResponseCount(String id) => access.stream;
}

class RevocableBandService extends authority.AuthorityService {
  final access = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> subscribeToBandProfileAccess(String id) => access.stream;
}

class RevocableBandState extends authority.AuthorityState {
  @override
  final RevocableBandService service = RevocableBandService();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async { setupFirebaseCoreMocks(); await Firebase.initializeApp(); });
  setUp(() {
    auth.FirebaseAuthPlatform.instance = fixtures.GateAuthPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('live authorization failure clears previously rendered Manage Requests data', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final service = RevocableRequestsService()..requests = [manage.request()];
    await manage.mount(tester, service);
    expect(find.text('View Responses (3)'), findsOneWidget);
    service.access.addError(const PrivateDataAccessException());
    await manage.settle(tester);
    expect(find.text('View Responses (3)'), findsNothing);
    expect(find.text('Requests are unavailable for your current access. Please try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await manage.unmount(tester);
    await service.access.close();
  });

  testWidgets('band membership loss removes the private edit profile immediately', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final state = RevocableBandState();
    await authority.mount(tester, state, EditBandInfoScreen(band: state.service.band));
    expect(find.byType(TextFormField), findsWidgets);
    state.service.access.add(false);
    await authority.pump(tester);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('This band is unavailable for your current access.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await state.service.access.close();
    state.dispose();
  });

  testWidgets('public band profile renders catalogue fields and no private band controls', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final state = catalogue.CatalogueState();
    final band = CatalogueProfiles.band('band', {
      'Name': 'Public band', 'Location': 'Paris, France', 'Description': 'Jazz quartet',
      'Contact': 'private-contact', 'RehearsalLocation': 'private-venue',
      'Members_band': {'member': {'Nickname': 'private-member'}},
    })!;
    await catalogue.mount(tester, state, PublicBandProfileScreen(band: band));
    expect(find.text('Public band'), findsOneWidget);
    expect(find.text('Jazz quartet'), findsOneWidget);
    expect(find.text('Paris, France'), findsOneWidget);
    for (final text in ['private-contact', 'private-venue', 'private-member', 'Delete Band', 'Save Changes']) {
      expect(find.text(text), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  for (final membership in [null, {'Status': 'inactive'}, {'Status': 'removed'}]) {
    test('nonmember band profile uses only sanitized public data: $membership', () async {
      final paths = <String>[];
      final service = BandReadService(membershipRead: (path) async {
        paths.add(path); return membership;
      }, catalogueRead: (path) async {
        paths.add(path);
        return {'Name': 'Public band', 'Location': 'Paris, France',
          'Contact': 'secret', 'Address': 'private street', 'RehearsalLocation': 'private venue',
          'Members_band': {'viewer': {'Role': 'Leader'}}, 'Events': {'private': true}};
      });
      addTearDown(service.identities.close);
      final band = await service.getBandInfoAsync('band');
      expect(paths, ['Bands/band/Members_band/viewer', 'publicBandProfiles/band']);
      expect(band!.name, 'Public band');
      expect(band.location, 'Paris, France');
      expect(band.membersBand, isEmpty);
      expect(band.contact, isNull);
      expect(band.address, isNull);
      expect(band.rehearsalLocation, isNull);
    });
  }

  test('membership permission denial never triggers a public or legacy fallback', () async {
    final paths = <String>[];
    final service = BandReadService(membershipRead: (path) async {
      paths.add(path);
      throw FirebaseException(plugin: 'firebase_database', code: 'permission-denied');
    }, catalogueRead: (path) async { paths.add(path); return null; });
    addTearDown(service.identities.close);
    await expectLater(service.getBandInfoAsync('band'), throwsA(isA<FirebaseException>()));
    expect(paths, ['Bands/band/Members_band/viewer']);
  });

  test('A to B to A rejects a pending private band result', () async {
    final pending = Completer<Object?>();
    final paths = <String>[];
    final service = BandReadService(membershipRead: (path) {
      paths.add(path); return pending.future;
    }, catalogueRead: (path) async { paths.add(path); return null; });
    addTearDown(service.identities.close);
    final result = service.getBandInfoAsync('band');
    service.switchTo('other'); service.switchTo('viewer');
    final check = expectLater(result, throwsStateError);
    pending.complete({'Status': 'active', 'Role': 'Member'});
    await check;
    expect(paths, ['Bands/band/Members_band/viewer']);
  });
}
