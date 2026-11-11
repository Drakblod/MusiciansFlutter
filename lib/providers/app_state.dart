import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import '../models/user_profile.dart';
import '../models/band.dart';
import '../utils/band_membership_policy.dart';
import '../models/app_notification.dart';
import '../main.dart';
import '../utils/notification_router.dart';

class AppState extends ChangeNotifier {
  final FirebaseService firebaseService;

  UserProfile? _currentUserProfile;
  String? _activeBandId;
  String? _activeBandName;
  String? _bandOwnerUid;
  Map<String, String> _authorizedBands = {};
  int _bandReadGeneration = 0;
  int _membershipMutationEpoch = 0;
  Object? _membershipUiOperation;
  Future<Map<String, String>>? _bandLoad;
  String? _bandLoadUid;
  bool _bandSessionEnding = false;
  final Map<String, Future<Band?>> _bandVerificationLoads = {};
  bool _hasUnreadMessages = false;
  int _unreadNotificationCount = 0;
  List<AppNotification> _userNotifications = [];
  bool _isLoading = true;
  int _currentTab = 0;
  Map<String, int> _buttonClicks = {};
  late final NotificationRouter notificationRouter = NotificationRouter(
    firebaseService,
    () => MyApp.navigatorKey.currentState,
    selectBand: (id) => selectBand(id, _authorizedBands[id] ?? 'Band Room'),
    isReady: () => _currentUserProfile != null && !_isLoading,
  );
  StreamSubscription<Map<String, dynamic>>? _notificationOpens;
  StreamSubscription<Map<String, dynamic>>? _foregroundNotifications;
  StreamSubscription? _userNotificationsSubscription;

  static const List<String> validBubbleIds = [
    'find_musicians',
    'browse_musicians',
    'find_gigs',
    'create_event',
    'collabs',
    'event_calendar',
    'band_room',
    'marketplace',
  ];

  static List<String> validateAndSanitizeBubbles(List<String>? raw) {
    const defaultBubbles = ['find_musicians', 'band_room', 'find_gigs'];
    if (raw == null) return List.from(defaultBubbles);

    final sanitized = <String>[];
    for (final id in raw) {
      if (validBubbleIds.contains(id) && !sanitized.contains(id)) {
        sanitized.add(id);
      }
    }

    if (sanitized.length == 3) {
      return sanitized;
    }
    return List.from(defaultBubbles);
  }

  List<String> _selectedBubbles = [
    'find_musicians',
    'band_room',
    'find_gigs',
  ];
  List<String> get selectedBubbles => _selectedBubbles;

  StreamSubscription<bool>? _unreadSubscription;

  AppState({FirebaseService? firebaseService})
      : firebaseService = firebaseService ?? FirebaseService() {
    _listenToNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuthListener();
      if (!kIsWeb) {
        unawaited(Future<void>.sync(this.firebaseService.listenForNativeNotifications)
            .catchError((Object _) {}));
      }
      loadSelectedBubbles();
      loadMapThemePref();
    });
  }

  bool _isWhiteMapTheme = true;
  bool get isWhiteMapTheme => _isWhiteMapTheme;

  /// Session-cached set of subRequestIds the current user has applied to.
  /// Updated when Find Gigs or Map View details card resolves or submits an application.
  final Set<String> _sessionAppliedSubRequestIds = {};
  Set<String> get sessionAppliedSubRequestIds =>
      Set.unmodifiable(_sessionAppliedSubRequestIds);

  bool hasAppliedToSubRequest(String? subRequestId) {
    if (subRequestId == null || subRequestId.trim().isEmpty) return false;
    return _sessionAppliedSubRequestIds.contains(subRequestId.trim());
  }

  void markSubRequestApplied(String subRequestId) {
    final clean = subRequestId.trim();
    if (clean.isEmpty) return;
    if (_sessionAppliedSubRequestIds.add(clean)) {
      notifyListeners();
    }
  }

  void markSubRequestsApplied(Iterable<String> subRequestIds, {bool notify = true}) {
    bool changed = false;
    for (final raw in subRequestIds) {
      final clean = raw.trim();
      if (clean.isNotEmpty && _sessionAppliedSubRequestIds.add(clean)) {
        changed = true;
      }
    }
    if (changed && notify) {
      notifyListeners();
    }
  }

  void clearSessionAppliedSubRequestsForTest() {
    _sessionAppliedSubRequestIds.clear();
  }

  Future<void> loadMapThemePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('map_view_is_white_theme');
      if (saved != null) {
        _isWhiteMapTheme = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> toggleMapTheme() async {
    _isWhiteMapTheme = !_isWhiteMapTheme;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('map_view_is_white_theme', _isWhiteMapTheme);
    } catch (_) {}
  }

  Future<void> setMapTheme(bool isWhite) async {
    if (_isWhiteMapTheme == isWhite) return;
    _isWhiteMapTheme = isWhite;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('map_view_is_white_theme', isWhite);
    } catch (_) {}
  }

  Future<void> loadSelectedBubbles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('home_selected_bubbles');
    _selectedBubbles = validateAndSanitizeBubbles(raw);
    notifyListeners();
  }

  Future<void> updateSelectedBubbles(List<String> bubbleIds) async {
    _selectedBubbles = validateAndSanitizeBubbles(bubbleIds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('home_selected_bubbles', _selectedBubbles);
    notifyListeners();
  }

  void _listenToNotifications() {
    _notificationOpens = FirebaseService.notificationClickStream
        .listen(notificationRouter.receiveNativeOpen);
    _foregroundNotifications = FirebaseService.foregroundNotifications
        .listen(notificationRouter.receiveForeground);
  }

  void handlePendingNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notificationRouter.resumeNativeOpen();
    });
  }

  UserProfile? get currentUserProfile => _currentUserProfile;
  String? get activeBandId => !_bandSessionEnding && _bandOwnerUid == currentUserId &&
      _authorizedBands.containsKey(_activeBandId) ? _activeBandId : null;
  String? get activeBandName => activeBandId == null ? null : _activeBandName;
  bool get hasAuthorizedBand => activeBandId != null;
  bool get hasUnreadMessages => _hasUnreadMessages;
  int get unreadNotificationCount => _unreadNotificationCount;
  bool get isLoading => _isLoading;
  String? get currentUserId => firebaseService.currentUserId;
  int get currentTab => _currentTab;
  Map<String, int> get buttonClicks => _buttonClicks;

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  List<AppNotification> get userNotifications => _userNotifications;
  set userNotifications(List<AppNotification> value) {
    _userNotifications = value;
    _unreadNotificationCount = value.where((n) => !n.isRead).length;
    notifyListeners();
  }

  /// Map of unread activity counts per feature destination derived from user notifications.
  Map<String, int> get unreadActivityCounts {
    final counts = <String, int>{};
    for (final notif in userNotifications) {
      if (!notif.isRead) {
        final fid = notif.effectiveFeatureId;
        if (fid != null && fid.isNotEmpty) {
          counts[fid] = (counts[fid] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  /// Whether there is any unread activity for the given feature destination.
  bool hasUnreadActivity(String featureId) {
    return unreadActivityCount(featureId) > 0;
  }

  /// Number of unread notifications for the given feature destination.
  int unreadActivityCount(String featureId) {
    return unreadActivityCounts[featureId] ?? 0;
  }

  int get unreadSubResponsesCount => unreadActivityCount('find_musicians');
  bool get hasUnreadSubResponses => hasUnreadActivity('find_musicians');

  int get unreadGigsCount => unreadActivityCount('find_gigs');
  bool get hasUnreadGigs => hasUnreadActivity('find_gigs');

  int get unreadBandRoomCount => unreadActivityCount('band_room');
  bool get hasUnreadBandRoom => hasUnreadActivity('band_room');

  int get unreadCollabsCount => unreadActivityCount('collabs');
  bool get hasUnreadCollabs => hasUnreadActivity('collabs');

  /// Marks all unread notifications matching [featureId] as read.
  Future<void> markFeatureAsRead(String featureId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;
    for (int i = 0; i < _userNotifications.length; i++) {
      final n = _userNotifications[i];
      if (!n.isRead && n.effectiveFeatureId == featureId) {
        _userNotifications[i] = n.copyWith(isRead: true, readAt: now);
        changed = true;
      }
    }
    if (changed) {
      _unreadNotificationCount = _userNotifications.where((n) => !n.isRead).length;
      notifyListeners();
    }
    await firebaseService.markFeatureNotificationsReadAsync(featureId);
  }

  void setUserNotificationsForTest(List<AppNotification> notifs) {
    _userNotifications = notifs;
    _unreadNotificationCount = notifs.where((n) => !n.isRead).length;
    notifyListeners();
  }

  void toggleTestUnreadNotification() {
    if (_unreadNotificationCount == 0) {
      _unreadNotificationCount = 1;
    } else {
      _unreadNotificationCount = 0;
    }
    notifyListeners();
  }

  void _clearProfileState() {
    _membershipMutationEpoch++;
    _membershipUiOperation = null;
    _currentUserProfile = null;
    _bandReadGeneration++;
    _bandLoad = null;
    _bandLoadUid = null;
    _bandVerificationLoads.clear();
    _bandOwnerUid = null;
    _authorizedBands = {};
    _activeBandId = null;
    _activeBandName = null;
    _hasUnreadMessages = false;
    _unreadNotificationCount = 0;
    _userNotifications = [];
    _buttonClicks = {};
    _sessionAppliedSubRequestIds.clear();
    _unreadSubscription?.cancel();
    _unreadSubscription = null;
    _userNotificationsSubscription?.cancel();
    _userNotificationsSubscription = null;
  }

  void _initializeAuthListener() {
    // Check if user is already logged in on startup
    if (firebaseService.isLoggedIn) {
      _loadProfileAndSubscribe();
    } else {
      _clearProfileState();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProfileAndSubscribe() async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      _clearProfileState();
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final profile = await firebaseService.getUserProfileAsync(uid);
      if (currentUserId == uid) {
        _currentUserProfile = profile;
        _subscribeToUnread();
        if (!kIsWeb) {
          unawaited(firebaseService.initializePushNotifications());
        }
        await _loadButtonClicks();
        if (currentUserId != uid) return;
        await refreshBandMemberships();
        if (currentUserId != uid) return;
        handlePendingNotification();
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribeToUnread() {
    try {
      _unreadSubscription?.cancel();
      _unreadSubscription = firebaseService
          .subscribeToUnreadNotifications()
          .listen(
            (hasUnread) {
              _hasUnreadMessages = hasUnread;
              notifyListeners();
            },
            onError: (err) {
              debugPrint("Error in unread stream: $err");
            },
          );
    } catch (e) {
      debugPrint("Error subscribing to unread notifications: $e");
    }

    try {
      _userNotificationsSubscription?.cancel();
      _userNotificationsSubscription = firebaseService
          .subscribeToUserNotifications()
          .listen(
            (notifs) {
              _userNotifications = notifs;
              _unreadNotificationCount = notifs.where((n) => !n.isRead).length;
              notifyListeners();
            },
            onError: (err) {
              debugPrint("Error in user notifications stream: $err");
            },
          );
    } catch (e) {
      debugPrint("Error subscribing to user notifications: $e");
    }
  }

  Future<void> login(String email, String password) async {
    _bandSessionEnding = false;
    // LoginScreen owns attempt loading; AuthGate must retain the form.
    _clearProfileState();
    notifyListeners();
    try {
      await firebaseService.loginAsync(email, password);
      await _loadProfileAndSubscribe();
    } catch (e) {
      _clearProfileState();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> register(
    String email,
    String password,
    String userType,
    String nickname, [
    String? level,
    List<String>? genres,
    List<String>? secondarySkills,
  ]) async {
    _bandSessionEnding = false;
    _isLoading = true;
    _clearProfileState();
    notifyListeners();
    try {
      await firebaseService.registerAsync(
        email,
        password,
        userType,
        nickname,
        level,
        genres,
        secondarySkills,
      );
      await _loadProfileAndSubscribe();
    } catch (e) {
      _clearProfileState();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    notificationRouter.clearForeground();
    _bandSessionEnding = true;
    _isLoading = true;
    _clearProfileState();
    notifyListeners();
    try {
      await firebaseService.logoutAsync();
    } catch (e) {
      debugPrint("Error on logout: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteCurrentAccount() async {
    final uid = currentUserId;
    final epoch = _membershipMutationEpoch;
    final token = Object();
    _membershipUiOperation = token;
    var clearedOwnSession = false;
    _isLoading = true;
    notifyListeners();
    try {
      _unreadSubscription?.cancel();
      _userNotificationsSubscription?.cancel();
      await firebaseService.deleteUserAccountAsync();
      if (currentUserId != uid || _membershipMutationEpoch != epoch) {
        throw StateError('Your session changed. Please try again.');
      }
      _clearProfileState();
      clearedOwnSession = true;
    } catch (e) {
      debugPrint("Error on deleteCurrentAccount: $e");
      rethrow;
    } finally {
      if (clearedOwnSession || identical(_membershipUiOperation,token)) {
        _membershipUiOperation = null;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> deleteBand(String bandId) async {
    final uid = currentUserId;
    final epoch = _membershipMutationEpoch;
    final token = Object();
    _membershipUiOperation = token;
    _isLoading = true;
    notifyListeners();
    try {
      await firebaseService.deleteBandAsync(bandId);
      if (currentUserId != uid || _membershipMutationEpoch != epoch) {
        throw StateError('Your session or selected band changed. Please try again.');
      }
      if (_activeBandId == bandId) {
        _activeBandId = null;
        _activeBandName = null;
      }
      await refreshProfile();
      if (currentUserId != uid || _membershipMutationEpoch != epoch) {
        throw StateError('Your session or selected band changed. Please try again.');
      }
    } catch (e) {
      debugPrint("Error on deleteBand: $e");
      rethrow;
    } finally {
      if (identical(_membershipUiOperation,token)) {
        _membershipUiOperation = null;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void selectBand(String bandId, String bandName) {
    if (_bandOwnerUid != currentUserId || !_authorizedBands.containsKey(bandId)) {
      return;
    }
    if (_activeBandId != bandId) _membershipMutationEpoch++;
    _activeBandId = bandId;
    _activeBandName = _authorizedBands[bandId];
    notifyListeners();
  }

  Future<Map<String, String>> refreshBandMemberships() {
    if (_bandSessionEnding) {
      return Future.value(const <String, String>{});
    }
    final uid = currentUserId;
    if (_bandLoad != null && _bandLoadUid == uid) return _bandLoad!;
    _bandLoadUid = uid;
    final request = _readBandMemberships();
    _bandLoad = request;
    return request.whenComplete(() {
      if (identical(_bandLoad, request)) _bandLoad = null;
    });
  }

  Future<Map<String, String>> _readBandMemberships() async {
    final uid = currentUserId;
    final generation = ++_bandReadGeneration;
    if (_bandOwnerUid != uid) {
      _bandVerificationLoads.clear();
      _authorizedBands = {};
      _activeBandId = null;
      _activeBandName = null;
      _bandOwnerUid = uid;
    }
    if (uid == null || uid.isEmpty) return const {};
    final Map<String, String> bands;
    try {
      // Convert synchronous service failures into Future errors so listeners
      // are never notified while a membership gate is mounting.
      bands = await Future.sync(() => firebaseService.getUserBandsAsync(uid));
    } catch (_) {
      if (currentUserId == uid && generation == _bandReadGeneration) {
        _authorizedBands = {};
        _activeBandId = null;
        _activeBandName = null;
        notifyListeners();
      }
      rethrow;
    }
    if (currentUserId != uid || generation != _bandReadGeneration) return const {};
    _authorizedBands = Map.fromEntries(bands.entries.where((entry) =>
      BandMembershipPolicy.isRealId(entry.key) && entry.value.trim().isNotEmpty));
    if (!_authorizedBands.containsKey(_activeBandId)) {
      _activeBandId = _authorizedBands.keys.firstOrNull;
    }
    _activeBandName = _authorizedBands[_activeBandId];
    notifyListeners();
    return Map.unmodifiable(_authorizedBands);
  }

  Future<Band?> resolveAuthorizedBand(String? requestedBandId, {bool requireManager = false}) async {
    final uid = currentUserId;
    final bands = await refreshBandMemberships();
    if (uid == null || currentUserId != uid) return null;
    final bandId = requestedBandId ?? activeBandId;
    if (bandId == null || !bands.containsKey(bandId)) return null;
    final generation = _bandReadGeneration;
    final verificationKey = '$uid/$bandId/$generation';
    final band = await _bandVerificationLoads.putIfAbsent(verificationKey, () {
      return firebaseService.getBandInfoAsync(bandId).whenComplete(() {
        _bandVerificationLoads.remove(verificationKey);
      });
    });
    if (generation != _bandReadGeneration || currentUserId != uid || !BandMembershipPolicy.isMember(band, uid) ||
        (requireManager && !BandMembershipPolicy.canStaff(band, uid))) {
      return null;
    }
    selectBand(bandId, band!.name!);
    return band;
  }

  Future<void> refreshProfile() async {
    if (firebaseService.isLoggedIn) {
      final uid = currentUserId;
      final profile = await firebaseService.getUserProfileAsync(uid);
      if (uid == null || currentUserId != uid) return;
      _currentUserProfile = profile;
      await refreshBandMemberships();
      if (currentUserId != uid) return;
      notifyListeners();
    }
  }

  Future<void> _loadButtonClicks() async {
    if (currentUserId != null) {
      try {
        final clicks = await firebaseService.getButtonClicksAsync(
          currentUserId!,
        );
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
      await firebaseService.saveButtonClickAsync(
        currentUserId!,
        buttonId,
        newCount,
      );
    } catch (e) {
      debugPrint("Error saving button click: $e");
    }
  }

  @override
  void dispose() {
    notificationRouter.clearForeground();
    unawaited(_notificationOpens?.cancel());
    unawaited(_foregroundNotifications?.cancel());
    _unreadSubscription?.cancel();
    super.dispose();
  }
}
