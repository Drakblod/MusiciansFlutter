import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/firebase_service.dart';
import '../models/user_profile.dart';

class AppState extends ChangeNotifier {
  final FirebaseService firebaseService = FirebaseService();

  UserProfile? _currentUserProfile;
  String? _activeBandId;
  String? _activeBandName;
  bool _hasUnreadMessages = false;
  bool _isLoading = false;
  int _currentTab = 0;

  StreamSubscription<bool>? _unreadSubscription;

  AppState() {
    _initializeAuthListener();
  }

  UserProfile? get currentUserProfile => _currentUserProfile;
  String? get activeBandId => _activeBandId;
  String? get activeBandName => _activeBandName;
  bool get hasUnreadMessages => _hasUnreadMessages;
  bool get isLoading => _isLoading;
  String? get currentUserId => firebaseService.currentUserId;
  int get currentTab => _currentTab;

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  void _initializeAuthListener() {
    _isLoading = true;
    notifyListeners();

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
        final bands = await firebaseService.getUserBandsAsync(currentUserId!);
        if (bands.isNotEmpty && _activeBandId == null) {
          final firstBandId = bands.keys.first;
          _activeBandId = firstBandId;
          _activeBandName = bands[firstBandId];
        }
      }
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

  @override
  void dispose() {
    _unreadSubscription?.cancel();
    super.dispose();
  }
}
