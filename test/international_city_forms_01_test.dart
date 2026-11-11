// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_database_platform_interface/src/pigeon/messages.pigeon.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/city_location.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/city_search_service.dart';
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
  Object? saveError;
  Band? created,updated;
  @override Future<void> saveUserProfileAsync(String id,UserProfile profile) async {
    if (saveError case final error?) throw error;
    saved=profile;
  }
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

class ProfilePersistenceService extends FirebaseService {
  @override String get currentUserId => 'profile-owner';
  @override User? get currentUser => null;
  @override bool get isLoggedIn => false;
  @override Stream<String?> get catalogueIdentityChanges => const Stream.empty();
}

class ProfilePersistenceState extends AppState {
  ProfilePersistenceState():super(firebaseService:ProfilePersistenceService());
  UserProfile? profile;
  @override UserProfile? get currentUserProfile => profile;
  @override Future<void> refreshProfile() async {
    profile=await firebaseService.getUserProfileAsync();
  }
}

Future<void> mountForm(WidgetTester tester,Widget form,AppState state,CitySearchProvider? provider) async {
  tester.view.physicalSize=const Size(800,3000);tester.view.devicePixelRatio=1;
  addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
  final app=ChangeNotifierProvider<AppState>.value(value:state,child:MaterialApp(home:form));
  await tester.pumpWidget(provider==null?app:CitySearchProviderScope(provider:provider,child:app));
  await tester.pump();
}
Future<void> chooseBerlin(WidgetTester tester) async {
  await chooseCity(tester,'Ber','Berlin');
}
Future<void> chooseCity(WidgetTester tester,String query,String city) async {
  final field=find.descendant(of:find.byType(CityLocationPickerField),matching:find.byType(TextFormField));
  await tester.ensureVisible(field);await tester.enterText(field,query);
  await tester.pump(const Duration(milliseconds:350));await tester.pump();
  await tester.ensureVisible(find.text(city));await tester.tap(find.text(city));
  await tester.pump();
  await tester.tap(find.text('Confirm city'));await tester.pump();
}
Future<void> save(WidgetTester tester,String text) async {
  final button=find.text(text);
  await tester.ensureVisible(button);await tester.tap(button);await tester.pump();
}

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(() async {setupFirebaseCoreMocks();await Firebase.initializeApp();});
 testWidgets('Music Snippet title can be renamed repeatedly and removed without uploading', (tester) async {
  const url = 'https://example.test/never-display-this-filename.mp3';
  final state = FormState(UserProfile(
    userId: 'test_uid_123', displayName: 'Artist identity', instruments: ['Guitar'],
    mainInstrument: 'Guitar', audioSnippetUrl: url,
  ));
  final track = find.widgetWithText(TextFormField, 'Track name');
  Future<void> reopen() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await mountForm(tester, const EditProfileScreen(), state, null);
    await tester.ensureVisible(track);
  }
  expect(state.profile!.audioSnippetDisplayTitle, 'Music snippet');
  await reopen();
  expect(find.textContaining('never-display-this-filename'), findsNothing);
  await tester.enterText(track, '/local/private.mp3');
  await save(tester, 'Save Profile');
  expect(state.service.saved, isNull);
  expect(find.text('Use 1–80 characters. File paths and control characters are not allowed.'), findsOneWidget);
  await tester.enterText(track, '  First   Take / Reprise!  ');
  await save(tester, 'Save Profile');
  expect(state.service.saved!.audioSnippetTitle, 'First Take / Reprise!');
  expect(state.service.saved!.audioSnippetUrl, url);
  expect(state.service.saved!.displayName, 'Artist identity');

  state.profile = UserProfile.fromJson(state.service.saved!.toJson(), 'test_uid_123');
  await reopen();
  expect(find.text('First Take / Reprise!'), findsOneWidget);
  await tester.enterText(track, 'Final Take');
  await save(tester, 'Save Profile');
  expect(state.service.saved!.audioSnippetTitle, 'Final Take');
  expect(state.service.saved!.audioSnippetUrl, url);

  state.profile = state.service.saved;
  await reopen();
  final remove = find.byTooltip('Remove track');
  await tester.ensureVisible(remove);
  await tester.tap(remove);
  await tester.pump();
  expect(track, findsNothing);
  await save(tester, 'Save Profile');
  expect(state.service.saved!.audioSnippetTitle, isNull);
  expect(state.service.saved!.audioSnippetUrl, isNull);
 });
 testWidgets('confirmed Ljusdal saves in one callable and reloads before an ordinary edit', (tester) async {
  const functions=BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',StandardMessageCodec());
  const dbApi='dev.flutter.pigeon.firebase_database_platform_interface.FirebaseDatabaseHostApi';
  const query=BasicMessageChannel<Object?>('$dbApi.queryGet',FirebaseDatabaseHostApi.pigeonChannelCodec);
  const update=BasicMessageChannel<Object?>('$dbApi.databaseReferenceUpdate',FirebaseDatabaseHostApi.pigeonChannelCodec);
  const owner='users/profile-owner/';
  const location={'version':1,'precision':'city','confirmed':true,'city':'Ljusdal','country':'Sweden'};
  final info=<String,Object?>{'DisplayName':'Musician','Email':'account@example.test',
    'UserType':'Guitar','MainInstrument':'Guitar','Instruments':['Guitar','Piano'],'Genres':['Rock']};
  final mirror=<String,Object?>{};
  final messenger=tester.binding.defaultBinaryMessenger;
  var citySaves=0,clientWrites=0;
  messenger.setMockDecodedMessageHandler<Object?>(functions,(message) async {
    final request=(message as List).single as Map;
    final payload=Map<String,Object?>.from(request['parameters'] as Map);
    expect(request['region'],'europe-west1');
    switch(request['functionName']) {
      case 'startCatalogueCitySession': return [{'sessionToken':'test-session'}];
      case 'searchCatalogueCities': return [{'candidates':[{'placeId':'test-place','city':'Ljusdal','country':'Sweden'}]}];
      case 'resolveCatalogueCity': return [{'location':location,'nonce':'test-receipt'}];
      case 'commitUserCity':
        citySaves++;
        expect(payload['nonce'],'test-receipt');
        expect(payload['operationId'],'test-receipt');
        expect(payload['targetId'],'profile-owner');
        expect(payload['location'],location);
        final fields=Map<String,Object?>.from(payload['profile'] as Map);
        expect(fields['DisplayName'],'Updated musician');
        expect(fields['Instruments'],['Guitar','Piano']);
        expect(fields['Genres'],['Rock']);
        expect(fields.keys.toSet().intersection({'Email','PushToken','PublicLocation','Location'}),isEmpty);
        info.addAll({...fields,'PublicLocation':location,'Location':'Ljusdal, Sweden'});
        mirror['DisplayName']=fields['DisplayName'];
        return [{'success':true}];
      default: fail('Unexpected profile callable');
    }
  });
  messenger.setMockDecodedMessageHandler<Object?>(query,(message) async {
    final request=(message as List)[1] as QueryRequest;
    expect(request.path,startsWith(owner));
    final field=request.path.substring(owner.length);
    expect(field,isNot('info'),reason:'Owner profile loading must not read the legacy token parent.');
    expect(field.toLowerCase(),isNot(contains('pushtoken')));
    final value=field.startsWith('info/')?info[field.substring('info/'.length)]:mirror[field];
    return [{'snapshot':{'key':field.split('/').last,'value':value}}];
  });
  messenger.setMockDecodedMessageHandler<Object?>(update,(message) async {
    clientWrites++;
    final request=(message as List)[1] as UpdateRequest;
    expect(request.path,'/');
    expect(request.value['${owner}info/DisplayName'],'Ordinary edit');
    expect(request.value['${owner}DisplayName'],'Ordinary edit');
    expect(request.value.keys, everyElement(isNot(contains('Location'))));
    expect(request.value.keys, everyElement(isNot(contains('Email'))));
    info['DisplayName']=request.value['${owner}info/DisplayName'];
    return [null];
  });
  addTearDown(() {
    for(final channel in [functions,query,update]) {
      messenger.setMockDecodedMessageHandler<Object?>(channel,null);
    }
  });
  final state=ProfilePersistenceState();
  await tester.runAsync(state.refreshProfile);
  await mountForm(tester,const EditProfileScreen(),state,null);
  await tester.enterText(find.widgetWithText(TextFormField,'Musician'),'Updated musician');
  await chooseCity(tester,'Lju','Ljusdal');
  await save(tester,'Save Profile');
  await tester.pump(const Duration(milliseconds:350));
  expect(citySaves,1);
  expect(clientWrites,0);
  expect(info['PublicLocation'],location);
  await tester.runAsync(state.refreshProfile);
  expect(state.profile?.publicLocation?.label,'Ljusdal, Sweden');
  expect(state.profile?.publicLocation?.confirmationNonce,isNull);
  expect(state.profile?.email,'account@example.test');

  await tester.pumpWidget(const SizedBox.shrink());
  await mountForm(tester,const EditProfileScreen(),state,null);
  expect(find.text('Confirmed: Ljusdal, Sweden'),findsOneWidget);
  await tester.enterText(find.widgetWithText(TextFormField,'Updated musician'),'Ordinary edit');
  await save(tester,'Save Profile');
  await tester.pump(const Duration(milliseconds:350));
  expect(citySaves,1);
  expect(clientWrites,1);
  await tester.runAsync(state.refreshProfile);
  expect(state.profile?.displayName,'Ordinary edit');
  expect(state.profile?.publicLocation?.label,'Ljusdal, Sweden');
 });
 testWidgets('save denial displays safe feedback and retains the form', (tester) async {
  final state=FormState(UserProfile(userId:'test_uid_123',displayName:'Musician',userType:'Guitar'));
  state.service.saveError=FirebaseException(plugin:'firebase_database',code:'permission-denied',
    message:'raw permission diagnostics');
  await mountForm(tester,const EditProfileScreen(),state,picker.FakeCities());
  await save(tester,'Save Profile');
  expect(find.text('Failed to save profile: Please try again.'),findsOneWidget);
  expect(find.textContaining('raw permission diagnostics'),findsNothing);
  expect(find.byType(EditProfileScreen),findsOneWidget);
 });
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
