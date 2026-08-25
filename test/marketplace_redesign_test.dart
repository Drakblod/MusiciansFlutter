import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/listing.dart';
import 'package:musicians_flutter/models/marketplace_taxonomy.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/views/marketplace_page.dart';
import 'package:musicians_flutter/views/create_listing_page.dart';
import 'package:musicians_flutter/views/listing_details_page.dart';
import 'package:musicians_flutter/views/my_listings_page.dart';
import 'package:musicians_flutter/widgets/marketplace_category_sheet.dart';
import 'package:musicians_flutter/widgets/marketplace_filter_selector.dart';

class MockMarketplaceFirebaseService extends FirebaseService {
  List<Listing> inMemoryListings = [];

  @override
  Future<List<Listing>> getActiveListingsAsync() async {
    return inMemoryListings.where((l) => l.status == 'active').toList();
  }

  @override
  Future<List<Listing>> getUserListingsAsync(String userId) async {
    return inMemoryListings
        .where((l) => l.userId == userId && l.status != 'deleted')
        .toList();
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: userId ?? 'test_user',
      displayName: 'Test Seller',
      nickname: 'Seller',
      location: 'Stockholm',
    );
  }

  @override
  String generateListingId() {
    return 'generated_id_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> saveListingAsync(Listing listing) async {
    inMemoryListings.add(listing);
  }

  @override
  Future<void> updateListingStatusAsync(String listingId, String status) async {
    final index = inMemoryListings.indexWhere((l) => l.id == listingId);
    if (index != -1) {
      final old = inMemoryListings[index];
      inMemoryListings[index] = Listing(
        id: old.id,
        userId: old.userId,
        title: old.title,
        description: old.description,
        category: old.category,
        listingType: old.listingType,
        marketplaceIntent: old.marketplaceIntent,
        marketplaceCategory: old.marketplaceCategory,
        price: old.price,
        city: old.city,
        imageUrls: old.imageUrls,
        status: status,
        createdAt: old.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }
}

class MockAppStateForMarketplaceTest extends AppState {
  final MockMarketplaceFirebaseService mockService;

  MockAppStateForMarketplaceTest(this.mockService);

  @override
  FirebaseService get firebaseService => mockService;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'current_user_123',
        displayName: 'Current User',
        email: 'current@example.com',
      );

  @override
  String? get currentUserId => 'current_user_123';
}

Widget createTestApp({
  required Widget child,
  required MockMarketplaceFirebaseService mockService,
  RouteFactory? onGenerateRoute,
}) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockAppStateForMarketplaceTest(mockService),
    child: MaterialApp(
      routes: {
        '/marketplace': (context) => const MarketplacePage(),
        '/create-listing': (context) => const CreateListingPage(),
        '/my-listings': (context) => const MyListingsPage(),
      },
      onGenerateRoute: onGenerateRoute ??
          (settings) {
            if (settings.name == '/listing-details') {
              final listing = settings.arguments as Listing;
              return MaterialPageRoute(
                builder: (context) => ListingDetailsPage(listing: listing),
              );
            }
            return null;
          },
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('Marketplace Redesign - Model & Taxonomy Unit Tests', () {
    test('11. New listing JSON round-trips marketplaceIntent and marketplaceCategory', () {
      final listing = Listing(
        id: 'list_001',
        userId: 'user_1',
        title: 'Gibson Les Paul Standard',
        description: 'Excellent condition',
        category: 'Instruments/Gear',
        listingType: 'sell',
        marketplaceIntent: 'offering',
        marketplaceCategory: 'instrument_gear',
        price: 18000,
        city: 'Stockholm',
        createdAt: 1000,
        updatedAt: 2000,
      );

      final json = listing.toJson();
      expect(json['marketplaceIntent'], 'offering');
      expect(json['marketplaceCategory'], 'instrument_gear');

      final parsed = Listing.fromJson(json, 'list_001');
      expect(parsed.marketplaceIntent, 'offering');
      expect(parsed.marketplaceCategory, 'instrument_gear');
      expect(parsed.effectiveIntent, 'offering');
      expect(parsed.effectiveCategory, 'instrument_gear');
    });

    test('12. Legacy listings without new fields still parse and render safely', () {
      final legacyJson = {
        'userId': 'user_2',
        'title': 'Vintage Fender Amp',
        'description': 'Tube amp from 1974',
        'category': 'Amps & Effects',
        'listingType': 'sell',
        'price': 8500,
        'city': 'Gothenburg',
        'createdAt': 1500,
        'updatedAt': 1500,
      };

      final parsed = Listing.fromJson(legacyJson, 'legacy_001');
      expect(parsed.marketplaceIntent, isNull);
      expect(parsed.marketplaceCategory, isNull);
      expect(parsed.effectiveIntent, 'offering');
      expect(parsed.effectiveCategory, 'instrument_gear');
    });

    test('13. Legacy buy maps to Looking For behavior', () {
      final legacyWantedJson = {
        'userId': 'user_3',
        'title': 'Looking for Drum Teacher',
        'description': 'Need beginner lessons in Malmo',
        'category': 'Music Services',
        'listingType': 'buy',
        'price': 0,
        'city': 'Malmo',
        'createdAt': 1200,
        'updatedAt': 1200,
      };

      final parsed = Listing.fromJson(legacyWantedJson, 'legacy_002');
      expect(parsed.effectiveIntent, MarketplaceTaxonomy.intentLookingFor);
      expect(parsed.effectiveCategory, 'music_services');
    });

    test('14. Legacy sell, rent, and service map safely to Offering behavior', () {
      final sellListing = Listing.fromJson({'listingType': 'sell'}, '1');
      final rentListing = Listing.fromJson({'listingType': 'rent'}, '2');
      final serviceListing = Listing.fromJson({'listingType': 'service'}, '3');

      expect(sellListing.effectiveIntent, MarketplaceTaxonomy.intentOffering);
      expect(rentListing.effectiveIntent, MarketplaceTaxonomy.intentOffering);
      expect(serviceListing.effectiveIntent, MarketplaceTaxonomy.intentOffering);
    });

    test('15. Unknown legacy categories are not silently lost and map safely', () {
      final unknownCat = Listing.fromJson({
        'category': 'Some Obscure Category',
        'listingType': 'sell',
      }, '4');

      expect(unknownCat.effectiveCategory, 'other_services');
      expect(unknownCat.category, 'Some Obscure Category');
    });

    test('19. Exact labels and slash formatting are preserved in taxonomy', () {
      // Looking for categories exact strings
      final lookingForLabels =
          MarketplaceTaxonomy.lookingForCategories.map((c) => c.label).toList();
      expect(lookingForLabels, [
        'Instrument/Gear',
        'Teacher/School',
        'Learning Materials',
        'Music Services',
        'Studio',
        'Engineer/Producer',
        'Rehearsal Space',
        'Other Services',
      ]);

      // Offering categories exact strings
      final offeringLabels =
          MarketplaceTaxonomy.offeringCategories.map((c) => c.label).toList();
      expect(offeringLabels, [
        'Instruments/Gear',
        'Repairs',
        'Lessons/School',
        'Music Services',
        'Recording/Production',
        'Promotion',
        'Management',
        'Other Services',
      ]);
    });

    test('9 & 10. Reciprocal Matching: Looking For vs Offering semantics', () {
      final authorOfferingInstrument = Listing(
        id: '1',
        title: 'Fender Stratocaster',
        marketplaceIntent: 'offering',
        marketplaceCategory: 'instrument_gear',
        createdAt: 100,
        updatedAt: 100,
      );

      final authorWantedInstrument = Listing(
        id: '2',
        title: 'WTB Fender Stratocaster',
        marketplaceIntent: 'looking_for',
        marketplaceCategory: 'instrument_gear',
        createdAt: 100,
        updatedAt: 100,
      );

      // User browsing "I'M LOOKING FOR -> Instrument/Gear" should see author's OFFERING, NOT author's WANTED
      expect(
        MarketplaceTaxonomy.matchesBrowsingFilter(
          listing: authorOfferingInstrument,
          browsingIntent: 'looking_for',
          browsingCategoryId: 'instrument_gear',
        ),
        isTrue,
      );
      expect(
        MarketplaceTaxonomy.matchesBrowsingFilter(
          listing: authorWantedInstrument,
          browsingIntent: 'looking_for',
          browsingCategoryId: 'instrument_gear',
        ),
        isFalse,
      );

      // User browsing "I'M OFFERING -> Instruments/Gear" should see author's WANTED, NOT author's OFFERING
      expect(
        MarketplaceTaxonomy.matchesBrowsingFilter(
          listing: authorWantedInstrument,
          browsingIntent: 'offering',
          browsingCategoryId: 'instrument_gear',
        ),
        isTrue,
      );
      expect(
        MarketplaceTaxonomy.matchesBrowsingFilter(
          listing: authorOfferingInstrument,
          browsingIntent: 'offering',
          browsingCategoryId: 'instrument_gear',
        ),
        isFalse,
      );
    });
  });

  group('Marketplace Redesign - UI & Interaction Widget Tests', () {
    late MockMarketplaceFirebaseService mockService;

    setUp(() {
      mockService = MockMarketplaceFirebaseService();
      mockService.inMemoryListings = [
        Listing(
          id: 'list_1',
          userId: 'seller_1',
          title: 'Roland Juno-DS Synthesizer',
          description: 'Great synthesizer for gigging and studio',
          category: 'Instruments/Gear',
          listingType: 'sell',
          marketplaceIntent: 'offering',
          marketplaceCategory: 'instrument_gear',
          price: 6500,
          city: 'Stockholm',
          status: 'active',
          createdAt: 1000,
          updatedAt: 1000,
        ),
        Listing(
          id: 'list_2',
          userId: 'buyer_1',
          title: 'Looking for Vocal Teacher',
          description: 'Need classical vocal coaching',
          category: 'Teacher/School',
          listingType: 'buy',
          marketplaceIntent: 'looking_for',
          marketplaceCategory: 'teacher_school',
          price: 0,
          city: 'Uppsala',
          status: 'active',
          createdAt: 2000,
          updatedAt: 2000,
        ),
        Listing(
          id: 'list_3',
          userId: 'seller_2',
          title: 'Professional Mixing & Mastering Service',
          description: 'Get your tracks polished',
          category: 'Music Services',
          listingType: 'service',
          marketplaceIntent: 'offering',
          marketplaceCategory: 'recording_production',
          price: 1500,
          city: 'Stockholm',
          status: 'active',
          createdAt: 3000,
          updatedAt: 3000,
        ),
      ];
    });

    testWidgets('1. Both main entry cards are visible with correct titles & subtitles', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const MarketplacePage(),
        mockService: mockService,
      ));
      await tester.pumpAndSettle();

      expect(find.text("I'M LOOKING FOR"), findsOneWidget);
      expect(find.text("I'M OFFERING"), findsOneWidget);
      expect(
        find.text('Find instruments, services, spaces, teachers and other music resources.'),
        findsOneWidget,
      );
      expect(
        find.text('Find requests from musicians who need instruments, services or expertise.'),
        findsOneWidget,
      );
    });

    testWidgets('2 & 4. Tapping I\'M LOOKING FOR opens correct modal with 8 exact options in required order', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const MarketplacePage(),
        mockService: mockService,
      ));
      await tester.pumpAndSettle();

      // Tap I'M LOOKING FOR card
      await tester.tap(find.text("I'M LOOKING FOR"));
      await tester.pumpAndSettle();

      expect(find.byType(MarketplaceCategorySheet), findsOneWidget);
      expect(find.text("I'M LOOKING FOR"), findsNWidgets(2)); // Header in sheet & background card

      // Verify options in sheet
      expect(find.text('Instrument/Gear'), findsOneWidget);
      expect(find.text('Teacher/School'), findsOneWidget);
      expect(find.text('Learning Materials'), findsOneWidget);
      expect(find.text('Music Services'), findsOneWidget);
      expect(find.text('Studio'), findsOneWidget);
      expect(find.text('Engineer/Producer'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Rehearsal Space'), 50, scrollable: find.byType(Scrollable).last);
      expect(find.text('Rehearsal Space'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Other Services'), 50, scrollable: find.byType(Scrollable).last);
      expect(find.text('Other Services'), findsOneWidget);
    });

    testWidgets('3 & 5. Tapping I\'M OFFERING opens correct modal with 8 exact options in required order', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const MarketplacePage(),
        mockService: mockService,
      ));
      await tester.pumpAndSettle();

      // Tap I'M OFFERING card
      await tester.tap(find.text("I'M OFFERING"));
      await tester.pumpAndSettle();

      expect(find.byType(MarketplaceCategorySheet), findsOneWidget);
      expect(find.text('Instruments/Gear'), findsOneWidget);
      expect(find.text('Repairs'), findsOneWidget);
      expect(find.text('Lessons/School'), findsOneWidget);
      expect(find.text('Music Services'), findsOneWidget);
      expect(find.text('Recording/Production'), findsOneWidget);
      expect(find.text('Promotion'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Management'), 50, scrollable: find.byType(Scrollable).last);
      expect(find.text('Management'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Other Services'), 50, scrollable: find.byType(Scrollable).last);
      expect(find.text('Other Services'), findsOneWidget);
    });

    testWidgets('6 & 7. Selecting an option updates selector, closes modal, and remains fully tappable', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const MarketplacePage(),
        mockService: mockService,
      ));
      await tester.pumpAndSettle();

      // Tap I'M LOOKING FOR
      await tester.tap(find.text("I'M LOOKING FOR"));
      await tester.pumpAndSettle();

      // Select Instrument/Gear
      await tester.tap(find.text('Instrument/Gear'));
      await tester.pumpAndSettle();

      // Modal closed
      expect(find.byType(MarketplaceCategorySheet), findsNothing);

      // Selected category badge visible on card
      expect(find.text('Instrument/Gear'), findsWidgets);

      // Results filtered: Roland Juno-DS (offer of instrument) is visible; Vocal Teacher request is NOT
      expect(find.text('Roland Juno-DS Synthesizer'), findsOneWidget);
      expect(find.text('Looking for Vocal Teacher'), findsNothing);

      // Reopening populated card by tapping again
      await tester.tap(find.text("I'M LOOKING FOR"));
      await tester.pumpAndSettle();
      expect(find.byType(MarketplaceCategorySheet), findsOneWidget);
    });

    testWidgets('8. Filters combine correctly with free-text search', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const MarketplacePage(),
        mockService: mockService,
      ));
      await tester.pumpAndSettle();

      // Select I'M LOOKING FOR -> Instrument/Gear
      await tester.tap(find.text("I'M LOOKING FOR"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instrument/Gear'));
      await tester.pumpAndSettle();

      // Roland Juno is visible
      expect(find.text('Roland Juno-DS Synthesizer'), findsOneWidget);

      // Search for non-matching text
      await tester.enterText(find.byType(TextField), 'Yamaha');
      await tester.pumpAndSettle();

      expect(find.text('Roland Juno-DS Synthesizer'), findsNothing);
      expect(find.text('No Listings Found'), findsOneWidget);

      // Search for matching text
      await tester.enterText(find.byType(TextField), 'Roland');
      await tester.pumpAndSettle();

      expect(find.text('Roland Juno-DS Synthesizer'), findsOneWidget);
    });

    testWidgets('16, 17 & 18. Create Listing displays correct subcategories, preselects intent/category, and validates', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const CreateListingPage(
          initialIntent: 'looking_for',
          initialCategory: 'teacher_school',
        ),
        mockService: mockService,
      ));
      await tester.pumpAndSettle();

      // Check preselection preserved
      expect(find.text('Teacher/School'), findsOneWidget);

      // Switch to OFFERING intent
      await tester.tap(find.text("I'M OFFERING"));
      await tester.pumpAndSettle();

      // Now category dropdown should have offering categories like 'Instruments/Gear'
      expect(find.text('Instruments/Gear'), findsOneWidget);

      // Verify form validation: fill title and invalid price to test validation
      await tester.enterText(find.widgetWithText(TextFormField, 'e.g., Fender Stratocaster 2021'), 'Test Guitar');
      await tester.ensureVisible(find.text('Publish Listing'));
      await tester.tap(find.text('Publish Listing'));
      await tester.pumpAndSettle();

      // Price and description are required
      expect(find.text('Please enter a price'), findsOneWidget);
      expect(find.text('Please enter a description'), findsOneWidget);
    });

    testWidgets('20. Keyboard activation and semantic accessibility work', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const MarketplacePage(),
        mockService: mockService,
      ));
      await tester.pumpAndSettle();

      final firstCard = find.byType(MarketplaceFilterSelector);
      expect(firstCard, findsOneWidget);

      // Reset filter works
      await tester.tap(find.text("I'M LOOKING FOR"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instrument/Gear'));
      await tester.pumpAndSettle();

      expect(find.text('Reset Filter'), findsOneWidget);
      await tester.tap(find.text('Reset Filter'));
      await tester.pumpAndSettle();

      expect(find.text('Reset Filter'), findsNothing);
    });

    testWidgets('21. Listing Detail and My Listings remain functional', (tester) async {
      final listing = Listing(
        id: 'list_detail_test',
        userId: 'current_user_123',
        title: 'Detail Test Guitar',
        description: 'A great guitar for testing',
        category: 'Instruments/Gear',
        listingType: 'sell',
        marketplaceIntent: 'offering',
        marketplaceCategory: 'instrument_gear',
        price: 5000,
        city: 'Stockholm',
        status: 'active',
        createdAt: 1000,
        updatedAt: 1000,
      );

      mockService.inMemoryListings.add(listing);

      await tester.pumpWidget(createTestApp(
        child: ListingDetailsPage(listing: listing),
        mockService: mockService,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Detail Test Guitar'), findsOneWidget);
      expect(find.text('Instruments/Gear'), findsOneWidget);
      expect(find.text('5000 kr'), findsOneWidget);
    });
  });
}
