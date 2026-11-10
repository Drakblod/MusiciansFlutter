import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/city_location.dart';
import 'package:musicians_flutter/services/city_search_service.dart';
import 'package:musicians_flutter/widgets/city_location_picker_field.dart';

class FakeCities implements CitySearchProvider {
  final searches = <String>[];
  final tokens = <String>[];
  Completer<List<CityCandidate>>? pending;
  bool fail = false;
  List<CityAttribution> attributions = const [];
  CityLocation? resolved = CityLocation.confirmed(city: 'Berlin', country: 'Germany', countryCode: 'de');
  final candidates = const [CityCandidate(placeId:'City123',city:'Berlin',country:'Germany')];
  @override
  Future<String> createSession() async => newCitySearchSessionToken();
  @override
  Future<List<CityCandidate>> search(String query, String token) async {
    searches.add(query); tokens.add(token);
    if (fail) { fail = false; throw StateError('offline'); }
    return pending?.future ?? candidates;
  }
  @override
  Future<CityLocation?> resolve(CityCandidate candidate, String token,
      {required String purpose,required String targetId,
       required String city,required String country}) async {
    tokens.add(token);
    return resolved==null?null:CityLocation.confirmed(city:city,country:country,
      confirmationNonce:'fake-grant',attributions:attributions);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  test('structured international city round-trips with Unicode, region and normalized code', () {
    for (final city in ['Berlin','Oslo','Växjö','Łódź','New York']) {
      final c = CityLocation.confirmed(city:city,region:'New York',country:'United States',countryCode:'us')!;
      expect(CityLocation.fromJson(c.toJson())!.label,'$city, New York, United States');
      expect(c.toJson(),isNot(contains('placeId')));
      expect(c.toJson(),isNot(contains('latitude')));
      expect(c.countryCode,'US');
    }
    expect(CityLocation.fromJson({'city':'Berlin','country':'Germany'}),isNull);
    expect(CityLocation.confirmed(city:'Berlin',country:'Germany')!.label,'Berlin, Germany');
  });

  Future<void> mount(WidgetTester tester, CitySearchProvider? provider, GlobalKey<FormState> key,
      ValueChanged<CityLocation?> onChanged, {CityLocation? initial}) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Form(key:key,
      child:SingleChildScrollView(child:CityLocationPickerField(
        provider:provider, purpose:'profile',targetId:()=>'test_uid',
        initialLocation:initial, onChanged:onChanged))))));
  }

  Future<void> confirmCity(WidgetTester tester) async {
    await tester.pump();
    await tester.tap(find.text('Confirm city'));
    await tester.pump();
  }

  for (final city in ['Ljusdal', 'Stockholm', 'Lidingö']) {
    testWidgets('$city confirms the selected callable result without retyping', (tester) async {
      const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
        StandardMessageCodec(),
      );
      const session = 'test-signed-app-session';
      const placeId = 'test-selected-place';
      const nonce = 'test-confirmation-receipt';
      final calls = <String>[];
      final query = city.substring(0, 3);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
        final request = (message as List).single as Map;
        final name = request['functionName'] as String;
        calls.add(name);
        expect(request['region'], 'europe-west1');
        switch (name) {
          case 'startCatalogueCitySession':
            expect(request['parameters'], isEmpty);
            return [{'sessionToken': session}];
          case 'searchCatalogueCities':
            expect(request['parameters'], {'query': query, 'sessionToken': session});
            return [{'candidates': [{'placeId': placeId, 'city': city, 'country': 'Sweden'}]}];
          case 'resolveCatalogueCity':
            expect(request['parameters'], {
              'placeId': placeId,
              'sessionToken': session,
              'purpose': 'profile',
              'targetId': 'test_uid',
              'city': city,
              'country': 'Sweden',
            });
            return [{
              'location': {'version': 1, 'precision': 'city', 'confirmed': true,
                'city': city, 'country': 'Sweden'},
              'nonce': nonce,
            }];
          default:
            fail('Unexpected city callable: $name');
        }
      });
      addTearDown(() => messenger.setMockDecodedMessageHandler<Object?>(channel, null));

      CityLocation? selected;
      final form = GlobalKey<FormState>();
      await mount(tester, null, form, (location) => selected = location);
      await tester.enterText(find.byType(TextFormField), query);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(form.currentState!.validate(), isFalse);
      await tester.tap(find.text(city));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'City')).controller!.text, city);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Country')).controller!.text, 'Sweden');
      await tester.tap(find.text('Confirm city'));
      await tester.pumpAndSettle();
      expect(calls, ['startCatalogueCitySession', 'searchCatalogueCities', 'resolveCatalogueCity']);
      expect(find.text('Confirmed: $city, Sweden'), findsOneWidget);
      expect(selected?.confirmationNonce, nonce);
      expect(form.currentState!.validate(), isTrue);
    });
  }

  testWidgets('typed text cannot submit; suggestion shows city/country; selection confirms; clear invalidates', (tester) async {
    final provider=FakeCities(), key=GlobalKey<FormState>(); CityLocation? selected;
    await mount(tester,provider,key,(value)=>selected=value);
    await tester.enterText(find.byType(TextFormField),'Ber');
    expect(key.currentState!.validate(),false);
    await tester.pump(const Duration(milliseconds:350)); await tester.pump();
    expect(find.text('Berlin'),findsOneWidget);
    expect(find.text('Germany'),findsOneWidget);
    expect(find.text('Google Maps'),findsOneWidget);
    await tester.tap(find.text('Berlin')); await confirmCity(tester);
    expect(selected!.label,'Berlin, Germany'); expect(key.currentState!.validate(),true);
    expect(provider.tokens.toSet().length,1);
    await tester.tap(find.byTooltip('Clear city')); await tester.pump();
    expect(selected,isNull); expect(key.currentState!.validate(),true);
  });

  testWidgets('Place Details attribution remains visible but never enters public JSON', (tester) async {
    tester.view.physicalSize=const Size(320,700);tester.view.devicePixelRatio=1;
    addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
    final provider=FakeCities()..attributions=[CityAttribution('City data partner',
      Uri.parse('https://example.test/source'))];
    final key=GlobalKey<FormState>();CityLocation? selected;
    await mount(tester,provider,key,(value)=>selected=value);
    await tester.enterText(find.byType(TextFormField),'Ber');
    await tester.pump(const Duration(milliseconds:350));await tester.pump();
    await tester.tap(find.text('Berlin'));await confirmCity(tester);
    expect(find.text('City data partner'),findsOneWidget);
    expect(selected!.toJson().containsKey('attributions'),false);
    expect(selected!.toJson().containsKey('confirmationNonce'),false);
    expect(tester.takeException(),isNull);
  });

  testWidgets('editing confirmed label invalidates selection', (tester) async {
    final provider=FakeCities(), key=GlobalKey<FormState>(); CityLocation? selected;
    final initial=CityLocation.confirmed(city:'Oslo',country:'Norway')!;
    await mount(tester,provider,key,(value)=>selected=value,initial:initial);
    expect(find.text('Confirmed: Oslo, Norway'),findsOneWidget);
    expect(key.currentState!.validate(),true);
    await tester.enterText(find.byType(TextFormField),'Oslo street');
    expect(selected,isNull);expect(key.currentState!.validate(),false);
  });

  testWidgets('stale query response is discarded and duplicate candidates collapse', (tester) async {
    final provider=FakeCities(),key=GlobalKey<FormState>();provider.pending=Completer<List<CityCandidate>>();
    await mount(tester,provider,key,(_)=>{});
    await tester.enterText(find.byType(TextFormField),'Ber');
    await tester.pump(const Duration(milliseconds:350));
    await tester.enterText(find.byType(TextFormField),'Oslo');
    provider.pending!.complete([provider.candidates.first,provider.candidates.first]);
    await tester.pump();
    expect(find.text('Berlin'),findsNothing);
    provider.pending=null;
    await tester.pump(const Duration(milliseconds:350));await tester.pump();
    expect(find.text('Berlin'),findsOneWidget);
  });

  testWidgets('provider error has retry and rejected venue cannot confirm', (tester) async {
    final provider=FakeCities()..fail=true;final key=GlobalKey<FormState>();CityLocation? selected;
    await mount(tester,provider,key,(value)=>selected=value);
    await tester.enterText(find.byType(TextFormField),'Ber');
    await tester.pump(const Duration(milliseconds:350));await tester.pump();
    expect(find.text('Retry'),findsOneWidget);
    await tester.tap(find.text('Retry'));await tester.pump();
    provider.resolved=null;
    await tester.tap(find.text('Berlin'));await confirmCity(tester);
    expect(selected,isNull);expect(key.currentState!.validate(),false);
  });

  testWidgets('keyboard Enter selects highlighted city and 320 px layout does not overflow', (tester) async {
    tester.view.physicalSize=const Size(320,700);tester.view.devicePixelRatio=1;
    addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
    final provider=FakeCities(),key=GlobalKey<FormState>();CityLocation? selected;
    await mount(tester,provider,key,(value)=>selected=value);
    await tester.enterText(find.byType(TextFormField),'Ber');
    await tester.pump(const Duration(milliseconds:350));await tester.pump();
    expect(find.text('Google Maps'),findsOneWidget);
    expect(tester.widget<Text>(find.text('Google Maps')).style?.fontSize,12);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await confirmCity(tester);
    expect(selected?.city,'Berlin');expect(tester.takeException(),isNull);
  });
}
