import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/city_location.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:musicians_flutter/widgets/city_location_picker_field.dart';
import 'international_city_picker_01_test.dart' as picker;

class FormService extends FirebaseService {
  @override
  Stream<bool> subscribeToBandProfileAccess(String bandId) => Stream.value(true);

  UserProfile? saved;
  Band? created,updated;
  @override Future<void> saveUserProfileAsync(String id,UserProfile profile) async { saved=profile; }
  @override Future<void> createBandAsync(String id,Band band) async { created=band; }
  @override Future<void> updateBandAsync(String id,Band band) async { updated=band; }
  @override Future<List<BandMember>> getBandMembersAsync(String id) async =>
    [BandMember(userId:'test_uid_123',role:'Leader',status:'active')];
  @override Future<UserProfile?> getUserProfileAsync([String? id]) async => null;
}
class FormState extends AppState {
  final FormService service=FormService();
  UserProfile? profile;
  FormState(this.profile);
  @override FirebaseService get firebaseService=>service;
  @override UserProfile? get currentUserProfile=>profile;
  @override String? get currentUserId=>'test_uid_123';
  @override String? get activeBandId=>'band_1';
  @override Future<void> refreshProfile() async {}
  @override void selectBand(String id,String name) {}
}

Future<void> mountForm(WidgetTester tester,Widget form,FormState state,picker.FakeCities provider) async {
  tester.view.physicalSize=const Size(800,3000);tester.view.devicePixelRatio=1;
  addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
  await tester.pumpWidget(CitySearchProviderScope(provider:provider,
    child:ChangeNotifierProvider<AppState>.value(value:state,
      child:MaterialApp(home:form))));
  await tester.pump();
}
Future<void> chooseBerlin(WidgetTester tester) async {
  final field=find.descendant(of:find.byType(CityLocationPickerField),matching:find.byType(TextFormField));
  await tester.ensureVisible(field);await tester.enterText(field,'Ber');
  await tester.pump(const Duration(milliseconds:350));await tester.pump();
  await tester.ensureVisible(find.text('Berlin'));await tester.tap(find.text('Berlin'));
  await tester.pump();
  await tester.enterText(find.widgetWithText(TextField,'City'),'Berlin');
  await tester.enterText(find.widgetWithText(TextField,'Country'),'Germany');
  await tester.tap(find.text('Confirm city'));await tester.pump();
}
Future<void> save(WidgetTester tester,String text) async {
  final button=find.text(text);
  await tester.ensureVisible(button);await tester.tap(button);await tester.pump();
}

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(() async {setupFirebaseCoreMocks();await Firebase.initializeApp();});
 testWidgets('Edit Profile restores structured city and saves replacement', (tester) async {
  final old=CityLocation.confirmed(city:'Oslo',country:'Norway')!;
  final state=FormState(UserProfile(userId:'test_uid_123',displayName:'Musician',email:'a@example.test',
    userType:'Guitar',instruments:['Guitar'],location:old.label,publicLocation:old));
  await mountForm(tester,const EditProfileScreen(),state,picker.FakeCities());
  expect(find.text('Confirmed: Oslo, Norway'),findsOneWidget);
  await chooseBerlin(tester);await save(tester,'Save Profile');
  expect(state.service.saved?.publicLocation?.label,'Berlin, Germany');
  expect(state.service.saved?.location,'Berlin, Germany');
 });
 testWidgets('Create Band saves confirmed city, not typed search', (tester) async {
  final state=FormState(null);await mountForm(tester,const CreateBandScreen(),state,picker.FakeCities());
  await chooseBerlin(tester);
  final name=find.widgetWithText(TextFormField,'Enter band name');
  await tester.enterText(name,'International Band');
  await save(tester,'Save Band');
  expect(state.service.created?.publicLocation?.label,'Berlin, Germany');
  expect(state.service.created?.location,'Berlin, Germany');
 });
 testWidgets('Create Band rejects typed city without provider confirmation', (tester) async {
  final state=FormState(null);await mountForm(tester,const CreateBandScreen(),state,picker.FakeCities());
  await tester.enterText(find.widgetWithText(TextFormField,'Enter band name'),'International Band');
  final field=find.descendant(of:find.byType(CityLocationPickerField),matching:find.byType(TextFormField));
  await tester.ensureVisible(field);await tester.enterText(field,'Made up city');
  await save(tester,'Save Band');
  expect(state.service.created,isNull);
  expect(find.text('Select and confirm a city.'),findsOneWidget);
 });
 testWidgets('Edit Band restores structured city and replaces whole contract', (tester) async {
  final old=CityLocation.confirmed(city:'Oslo',country:'Norway')!;
  final state=FormState(null);
  await mountForm(tester,EditBandInfoScreen(band:Band(id:'band_1',name:'Band',location:old.label,publicLocation:old,
    membersBand:{'test_uid_123':BandMember(userId:'test_uid_123',role:'Leader',status:'active')})),
    state,picker.FakeCities());
  expect(find.text('Confirmed: Oslo, Norway'),findsOneWidget);
  await chooseBerlin(tester);await save(tester,'Save Changes');
  expect(state.service.updated?.publicLocation?.label,'Berlin, Germany');
  expect(state.service.updated?.location,'Berlin, Germany');
 });
 testWidgets('legacy profile location is guidance, never confirmed automatically', (tester) async {
  final state=FormState(UserProfile(userId:'test_uid_123',displayName:'Musician',email:'a@example.test',
    userType:'Guitar',instruments:['Guitar'],location:'Private street 12, Oslo'));
  await mountForm(tester,const EditProfileScreen(),state,picker.FakeCities());
  expect(find.textContaining('Previous location (unverified)'),findsOneWidget);
  final pickerState=tester.state<CityLocationPickerFieldState>(find.byType(CityLocationPickerField));
  expect(pickerState.confirmedLocation,isNull);
 });
 testWidgets('clearing Edit Profile city saves no structured or legacy location', (tester) async {
  final old=CityLocation.confirmed(city:'Oslo',country:'Norway')!;
  final state=FormState(UserProfile(userId:'test_uid_123',displayName:'Musician',email:'a@example.test',
    userType:'Guitar',instruments:['Guitar'],location:old.label,publicLocation:old));
  await mountForm(tester,const EditProfileScreen(),state,picker.FakeCities());
  await tester.tap(find.byTooltip('Clear city'));await tester.pump();
  await save(tester,'Save Profile');
  expect(state.service.saved?.publicLocation,isNull);
  expect(state.service.saved?.location,isNull);
 });
 testWidgets('clearing Edit Band city saves no structured or legacy location', (tester) async {
  final old=CityLocation.confirmed(city:'Oslo',country:'Norway')!;
  final state=FormState(null);
  await mountForm(tester,EditBandInfoScreen(band:Band(id:'band_1',name:'Band',location:old.label,publicLocation:old,
    membersBand:{'test_uid_123':BandMember(userId:'test_uid_123',role:'Leader',status:'active')})),
    state,picker.FakeCities());
  await tester.tap(find.byTooltip('Clear city'));await tester.pump();
  await save(tester,'Save Changes');
  expect(state.service.updated?.publicLocation,isNull);
  expect(state.service.updated?.location,isNull);
 });
}
