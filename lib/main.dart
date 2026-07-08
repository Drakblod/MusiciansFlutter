import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'models/user_profile.dart';
import 'models/sub_request.dart';

import 'views/login_screen.dart';
import 'views/register_screen.dart';
import 'views/main_navigation_wrapper.dart';
import 'views/inbox_screen.dart';
import 'views/chat_detail_screen.dart';
import 'views/edit_profile_screen.dart';
import 'views/calendar_screen.dart';
import 'views/musician_profile_screen.dart';
import 'views/find_sub_screen.dart';
import 'views/create_band_screen.dart';
import 'views/browse_musicians_screen.dart';
import 'views/find_gigs_screen.dart';
import 'views/band_room_chat_screen.dart';
import 'views/profile_tab_screen.dart';
import 'views/sub_request_responses_screen.dart';
import 'views/sub_request_response_details_screen.dart';
import 'views/receipt_screen.dart';
import 'views/producer_search_screen.dart';
import 'views/gig_map_page.dart';
import 'views/sub_request_details_screen.dart';
import 'views/marketplace_page.dart';
import 'views/create_listing_page.dart';
import 'views/listing_details_page.dart';
import 'views/my_listings_page.dart';
import 'models/listing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Custom error handler to present errors on screen in release mode
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    runApp(ErrorApp(error: details.toString()));
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    runApp(ErrorApp(error: "$error\n$stack"));
    return true;
  };

  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyDsIItykulJQ-Nw0lg_DCZvCUxyD_Z1HYo",
          authDomain: "musiciansapp-35f70.firebaseapp.com",
          databaseURL: "https://musiciansapp-35f70-default-rtdb.europe-west1.firebasedatabase.app",
          projectId: "musiciansapp-35f70",
          storageBucket: "musiciansapp-35f70.firebasestorage.app",
          messagingSenderId: "674065132924",
          appId: "1:674065132924:web:e4e3bd93847249b68488f9",
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e, stack) {
    debugPrint("Firebase initialization error: $e");
    runApp(ErrorApp(error: "Firebase Init Error: $e\n$stack"));
    return;
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Musicians Only',
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        routes: {
          '/': (context) => const AuthGate(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/main-nav': (context) => const MainNavigationWrapper(),
          '/inbox': (context) => const InboxScreen(),
          '/edit-profile': (context) => const EditProfileScreen(),
          '/find-sub': (context) => const FindSubScreen(),
          '/create-band': (context) => const CreateBandScreen(),
          '/browse-musicians': (context) => const BrowseMusiciansScreen(),
          '/favorites': (context) => const BrowseMusiciansScreen(favoritesOnly: true),
          '/find-gigs': (context) => const FindGigsScreen(),
          '/band-room': (context) => const BandRoomChatScreen(),
          '/profile': (context) => const ProfileTabScreen(),
          '/producer-search': (context) => const ProducerSearchScreen(),
          '/gig-map': (context) => const GigMapPage(),
          '/marketplace': (context) => const MarketplacePage(),
          '/create-listing': (context) => const CreateListingPage(),
          '/my-listings': (context) => const MyListingsPage(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/listing-details') {
            final listing = settings.arguments as Listing;
            return MaterialPageRoute(
              builder: (context) => ListingDetailsPage(
                listing: listing,
              ),
              settings: settings,
            );
          }

          // Dynamic Routing with specific custom arguments
          if (settings.name == '/chat-detail') {
            final args = settings.arguments as Map<String, dynamic>? ?? {};
            return MaterialPageRoute(
              builder: (context) => ChatDetailScreen(
                conversationId: args['conversationId'] ?? '',
                receiverId: args['receiverId'] ?? '',
                receiverName: args['receiverName'] ?? 'Chat',
              ),
              settings: settings,
            );
          }

          if (settings.name == '/calendar') {
            final bandId = settings.arguments as String?;
            return MaterialPageRoute(
              builder: (context) => CalendarScreen(
                bandId: bandId,
              ),
              settings: settings,
            );
          }

          if (settings.name == '/profile-detail') {
            final musician = settings.arguments as UserProfile;
            return MaterialPageRoute(
              builder: (context) => MusicianProfileScreen(
                musician: musician,
              ),
              settings: settings,
            );
          }

          if (settings.name == '/sub-request-responses') {
            final args = settings.arguments as Map<String, dynamic>? ?? {};
            return MaterialPageRoute(
              builder: (context) => SubRequestResponsesScreen(
                bandId: args['bandId'] ?? '',
              ),
              settings: settings,
            );
          }

          if (settings.name == '/sub-request-response-details') {
            final args = settings.arguments as Map<String, dynamic>? ?? {};
            return MaterialPageRoute(
              builder: (context) => SubRequestResponseDetailsScreen(
                subRequest: args['subRequest'] as SubRequest,
              ),
              settings: settings,
            );
          }

          if (settings.name == '/gig-details') {
            final subRequest = settings.arguments as SubRequest;
            return MaterialPageRoute(
              builder: (context) => SubRequestDetailsScreen(
                subRequest: subRequest,
              ),
              settings: settings,
            );
          }

          if (settings.name == '/receipt') {
            final args = settings.arguments as Map<String, dynamic>? ?? {};
            return MaterialPageRoute(
              builder: (context) => ReceiptScreen(
                name: args['name'] ?? '',
                voicePart: args['voicePart'] ?? '',
                date: args['date'] ?? '',
                startTime: args['startTime'] ?? '',
                endTime: args['endTime'] ?? '',
                conversationId: args['conversationId'] ?? '',
                receiverUserId: args['receiverUserId'] ?? '',
              ),
              settings: settings,
            );
          }

          return null; // Let initialRoute / routes handle standard declarations
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    if (appState.isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: const Center(
            child: CircularProgressIndicator(
              color: AppTheme.primaryAccent,
            ),
          ),
        ),
      );
    }

    if (appState.currentUserProfile != null) {
      return const MainNavigationWrapper();
    } else {
      return const LoginScreen();
    }
  }
}

class ErrorApp extends StatelessWidget {
  final String error;
  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF1E0B36),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Initialization/Runtime Error Details:",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      error,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
