import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/firebase_service.dart';
import '../models/user_profile.dart';
import '../main.dart';
import '../models/band_event.dart';
import '../models/sub_request.dart';
import '../views/event_details_page.dart';
import '../views/sub_request_details_screen.dart';

class AppState extends ChangeNotifier {
  final FirebaseService firebaseService = FirebaseService();

  UserProfile? _currentUserProfile;
  String? _activeBandId;
  String? _activeBandName;
  bool _hasUnreadMessages = false;
  bool _isLoading = true;
  int _currentTab = 0;
  Map<String, int> _buttonClicks = {};
  Map<String, dynamic>? _pendingNotificationPayload;

  StreamSubscription<bool>? _unreadSubscription;

  AppState() {
    _listenToNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuthListener();
    });
  }

  void _listenToNotifications() {
    FirebaseService.notificationClickStream.listen((data) {
      if (firebaseService.isLoggedIn && _currentUserProfile != null) {
        _navigateToNotification(data);
      } else {
        _pendingNotificationPayload = data;
      }
    });
  }

  void handlePendingNotification() {
    if (_pendingNotificationPayload != null && firebaseService.isLoggedIn && _currentUserProfile != null) {
      final payload = _pendingNotificationPayload!;
      _pendingNotificationPayload = null;
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateToNotification(payload);
      });
    }
  }

  void _navigateToNotification(Map<String, dynamic> data) async {
    final type = data['type']?.toString();
    if (MyApp.navigatorKey.currentState == null) return;

    if (type == 'event_invite' || type == 'event_reminder' || type == 'event_threshold') {
      final bandId = data['bandId']?.toString();
      final eventId = data['eventId']?.toString();
      if (bandId != null && eventId != null) {
        final event = await firebaseService.getBandEventOnceAsync(bandId, eventId);
        if (event != null && MyApp.navigatorKey.currentState != null) {
          MyApp.navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => EventDetailsPage(
                bandId: bandId,
                eventId: eventId,
                initialEvent: event,
              ),
            ),
          );
        }
      }
    } else if (type == 'sub_request_invite') {
      final subRequestId = data['subRequestId']?.toString();
      if (subRequestId != null) {
        final list = await firebaseService.getAllSubRequestsAsync();
        final subRequest = list.firstWhere(
          (r) => (r.subRequestId ?? r.id) == subRequestId,
          orElse: () => SubRequest(id: subRequestId),
        );
        if (MyApp.navigatorKey.currentState != null) {
          MyApp.navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => SubRequestDetailsScreen(
                subRequest: subRequest,
              ),
            ),
          );
        }
      }
    }
  }

  UserProfile? get currentUserProfile => _currentUserProfile;
  String? get activeBandId => _activeBandId;
  String? get activeBandName => _activeBandName;
  bool get hasUnreadMessages => _hasUnreadMessages;
  bool get isLoading => _isLoading;
  String? get currentUserId => firebaseService.currentUserId;
  int get currentTab => _currentTab;
  Map<String, int> get buttonClicks => _buttonClicks;

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  void _initializeAuthListener() {
    // Check if user is already logged in on startup
    if (firebaseService.isLoggedIn) {
      _loadProfileAndSubscribe();
    } else {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProfileAndSubscribe() async {
    try {
      _currentUserProfile = await firebaseService.getUserProfileAsync();
      _subscribeToUnread();
      if (!kIsWeb) {
        unawaited(firebaseService.initializePushNotifications());
      }
      if (currentUserId != null) {
        await _loadButtonClicks();
        final bands = await firebaseService.getUserBandsAsync(currentUserId!);
        if (bands.isNotEmpty && _activeBandId == null) {
          final firstBandId = bands.keys.first;
          _activeBandId = firstBandId;
          _activeBandName = bands[firstBandId];
        }
      }
      handlePendingNotification();
    } catch (e) {
      debugPrint("Error loading profile: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribeToUnread() {
    _unreadSubscription?.cancel();
    _unreadSubscription = firebaseService.subscribeToUnreadNotifications().listen(
      (hasUnread) {
        _hasUnreadMessages = hasUnread;
        notifyListeners();
      },
      onError: (err) {
        debugPrint("Error in unread stream: $err");
      },
    );
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      await firebaseService.loginAsync(email, password);
      await _loadProfileAndSubscribe();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> register(
    String email,
    String password,
    String userType,
    String nickname,
  ) async {
    _isLoading = true;
    notifyListeners();
    try {
      await firebaseService.registerAsync(email, password, userType, nickname);
      await _loadProfileAndSubscribe();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      _unreadSubscription?.cancel();
      _unreadSubscription = null;
      await firebaseService.logoutAsync();
      _currentUserProfile = null;
      _activeBandId = null;
      _activeBandName = null;
      _hasUnreadMessages = false;
      _buttonClicks = {};
    } catch (e) {
      debugPrint("Error on logout: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectBand(String bandId, String bandName) {
    _activeBandId = bandId;
    _activeBandName = bandName;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (firebaseService.isLoggedIn) {
      _currentUserProfile = await firebaseService.getUserProfileAsync();
      if (currentUserId != null) {
        final bands = await firebaseService.getUserBandsAsync(currentUserId!);
        if (bands.isNotEmpty) {
          if (_activeBandId == null || !bands.containsKey(_activeBandId)) {
            final firstBandId = bands.keys.first;
            _activeBandId = firstBandId;
            _activeBandName = bands[firstBandId];
          }
        }
      }
      notifyListeners();
    }
  }

  Future<void> _loadButtonClicks() async {
    if (currentUserId != null) {
      try {
        final clicks = await firebaseService.getButtonClicksAsync(currentUserId!);
        _buttonClicks = clicks;
      } catch (e) {
        debugPrint("Error loading button clicks: $e");
      }
    }
  }

  Future<void> trackButtonClick(String buttonId) async {
    if (currentUserId == null) return;
    final currentCount = _buttonClicks[buttonId] ?? 0;
    final newCount = currentCount + 1;
    _buttonClicks[buttonId] = newCount;
    notifyListeners();
    try {
      await firebaseService.saveButtonClickAsync(currentUserId!, buttonId, newCount);
    } catch (e) {
      debugPrint("Error saving button click: $e");
    }
  }

  @override
  void dispose() {
    _unreadSubscription?.cancel();
    super.dispose();
  }
}
