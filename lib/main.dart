import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'models/user_profile.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState(),
      child: MaterialApp(
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
          '/find-gigs': (context) => const FindGigsScreen(),
          '/band-room': (context) => const BandRoomChatScreen(),
          '/profile': (context) => const ProfileTabScreen(),
        },
        onGenerateRoute: (settings) {
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
