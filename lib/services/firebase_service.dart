import 'dart:math' show Random;
import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import '../config/feature_toggles.dart';
import '../models/user_profile.dart';
import '../models/band.dart';
import '../models/sub_request.dart';
import '../models/request_management_access.dart';
import '../models/message.dart';
import '../models/calendar_event.dart';
import '../models/agreement.dart';
import '../models/listing.dart';
import '../models/band_event.dart';
import '../models/event_room.dart';
import '../models/collab_session.dart';
import '../models/collab_studio.dart';
import '../models/app_notification.dart';
import '../models/public_calendar_event.dart';
import '../models/map_event_item.dart';
import '../utils/date_parser.dart';
import '../utils/secondary_skills_utils.dart';
import '../utils/band_membership_policy.dart';
import '../utils/catalogue_profiles.dart';
import 'storage_media_service.dart';

class PrivateDataAccessException implements Exception {
  const PrivateDataAccessException();
  @override
  String toString() => 'This information is unavailable for your current access.';
}

class FirebaseService {
  void _rethrowAccessDenied(Object error) {
    if (error is PrivateDataAccessException) throw error;
    if (error is FirebaseException &&
        {'permission-denied', 'permission_denied', 'unauthenticated'}.contains(error.code.toLowerCase())) {
      throw const PrivateDataAccessException();
    }
  }

  Future<T> _forCurrentSession<T>(Future<T> Function() operation) async {
    final uid = currentUserId;
    var stale = false;
    final subscription = catalogueIdentityChanges.listen((next) {
      if (next != uid) stale = true;
    });
    try {
      final result = await operation();
      if (stale || uid != currentUserId) throw const PrivateDataAccessException();
      return result;
    } catch (error) {
      _rethrowAccessDenied(error);
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }

  Stream<T> _sessionStream<T>(Stream<T> source, T clearedValue) {
    final uid = currentUserId;
    late StreamController<T> controller;
    StreamSubscription<T>? dataSubscription;
    StreamSubscription<String?>? identitySubscription;
    var stopped = false;
    void fail() {
      if (stopped || controller.isClosed) return;
      stopped = true;
      controller.add(clearedValue);
      controller.addError(const PrivateDataAccessException());
      unawaited(dataSubscription?.cancel());
      unawaited(identitySubscription?.cancel());
      unawaited(controller.close());
    }
    controller = StreamController<T>(onListen: () {
      identitySubscription = catalogueIdentityChanges.listen((next) {
        if (next != uid) fail();
      });
      dataSubscription = source.listen((value) {
        if (stopped) return;
        if (uid != currentUserId) { fail(); return; }
        controller.add(value);
      }, onError: (Object error) => fail());
    }, onCancel: () async {
      stopped = true;
      await dataSubscription?.cancel();
      await identitySubscription?.cancel();
    });
    return controller.stream;
  }

  // Optional read-only adapter for deterministic membership path tests.
  // Production callers use the existing authenticated RTDB reference.
  final Future<Object?> Function(String path)? _membershipRead;
  final Future<Object?> Function(String path)? _catalogueRead;
  FirebaseService({Future<Object?> Function(String path)? membershipRead,
    Future<Object?> Function(String path)? catalogueRead})
      : _membershipRead = membershipRead, _catalogueRead = catalogueRead;

  static final StreamController<Map<String, dynamic>>
  _notificationClickStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get notificationClickStream =>
      _notificationClickStreamController.stream;

  static const String databaseUrl =
      "https://musiciansapp-35f70-default-rtdb.europe-west1.firebasedatabase.app";

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Use the explicit Database URL for European Realtime Database instance
  // Use the explicit Database URL for European Realtime Database instance
  DatabaseReference _dbRef([String? path]) {
    final db = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: databaseUrl,
    );
    if (path == null || path.trim().isEmpty) {
      return db.ref();
    }
    return db.ref(path.trim());
  }

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  // ==========================================
  // 1. Authentication
  // ==========================================

  Future<UserCredential> loginAsync(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> registerAsync(
    String email,
    String password,
    String userType,
    String nickname, [
    String? level,
    List<String>? genres,
    List<String>? secondarySkills,
  ]) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final newAuthUser = credential.user;
    final userId = newAuthUser?.uid;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception(
        'Registration failed: Authentication did not return a valid user ID.',
      );
    }

    final trimmedUid = userId.trim();
    final trimmedNickname = nickname.trim();
    final trimmedEmail = email.trim();

    try {
      if (newAuthUser != null && trimmedNickname.isNotEmpty) {
        await newAuthUser.updateDisplayName(trimmedNickname);
      }

      final profile = UserProfile(
        userId: trimmedUid,
        userType: userType,
        nickname: trimmedNickname,
        displayName: trimmedNickname,
        email: newAuthUser?.email ?? trimmedEmail,
        location: null,
        level: level ?? 'C = INTERMEDIATE',
        about: 'Hey! I am a musician ready to play.',
        instruments: SecondarySkillsUtils.buildInstrumentsList(
          userType,
          secondarySkills ?? const [],
        ),
        genres: genres ?? const [],
      );

      await saveUserProfileAsync(trimmedUid, profile);
    } catch (e) { _rethrowAccessDenied(e);
      try {
        await newAuthUser?.delete();
      } catch (deleteError) { _rethrowAccessDenied(deleteError);
        await _auth.signOut();
        throw Exception(
          'Registration failed during profile setup ($e). '
          'Auth account cleanup failed: $deleteError. You have been signed out. Please try registering again.',
        );
      }
      rethrow;
    }

    return credential;
  }

  String? get currentUserId => _auth.currentUser?.uid;

  User? get currentUser => _auth.currentUser;

  bool get isLoggedIn => _auth.currentUser != null;

  Future<void> logoutAsync() async {
    await _auth.signOut();
  }

  // ==========================================
  // 2. User Profiles
  // ==========================================

  Future<void> updateUserProfileFields(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    final trimmedUid = userId.trim();
    if (trimmedUid.isEmpty) {
      throw ArgumentError(
        'userId cannot be empty when updating profile fields.',
      );
    }

    if (trimmedUid != currentUserId) {
      throw StateError('You can only update your own profile.');
    }

    final updates = <String, dynamic>{};
    final allowedInfoKeys = {
      'DisplayName',
      'Email',
      'Level',
      'About',
      'Instruments',
      'Styles',
      'Genres',
      'Contact',
      'History',
      'Projects',
      'ProfilePictureUrl',
      'SpotifyUrl',
      'YoutubeUrl',
      'AudioSnippetUrl',
      'CollabRoles',
      'CollabRemote',
      'CollabBio',
      'MainInstrument',
      'UserType',
      'Nickname',
    };

    fields.forEach((key, value) {
      if (allowedInfoKeys.contains(key)) {
        updates['users/$trimmedUid/info/$key'] = value;
        if (key == 'UserType' || key == 'Nickname' || key == 'DisplayName') {
          updates['users/$trimmedUid/$key'] = value;
        }
      }
    });

    if (updates.isNotEmpty) {
      await _dbRef().update(updates);
    }
  }

  Future<void> saveUserProfileAsync(String userId, UserProfile profile) async {
    final trimmedUid = userId.trim();
    if (trimmedUid.isEmpty) {
      throw ArgumentError('userId cannot be empty when saving user profile.');
    }
    if (trimmedUid != currentUserId) {
      throw StateError('You can only update your own profile.');
    }

    final fields = <String, dynamic>{
      'DisplayName': profile.displayName,
      'Level': profile.level,
      'About': profile.about,
      'Instruments': SecondarySkillsUtils.buildInstrumentsList(
        profile.primarySkill, profile.secondarySkills,
      ),
      'Styles': profile.styles,
      'Genres': profile.genres,
      'Contact': profile.contact ?? profile.email,
      'History': profile.history,
      'Projects': profile.projects,
      'ProfilePictureUrl': profile.profilePictureUrl,
      'SpotifyUrl': profile.spotifyUrl,
      'YoutubeUrl': profile.youtubeUrl,
      'AudioSnippetUrl': profile.audioSnippetUrl,
      'CollabRoles': profile.collabRoles,
      'CollabRemote': profile.collabRemote,
      'CollabBio': profile.collabBio,
      'MainInstrument': profile.mainInstrument,
      if (profile.userType != null) 'UserType': profile.userType,
      if (profile.nickname != null) 'Nickname': profile.nickname,
    };
    final city = profile.publicLocation;
    if (city?.confirmationNonce != null) {
      await _functions.httpsCallable('commitUserCity').call({
        'nonce': city!.confirmationNonce,
        // The confirmation nonce is unique to this grant and keeps a network
        // retry on the same one-use operation.
        'operationId': city.confirmationNonce,
        'location': city.toJson(),
        'targetId': trimmedUid,
        'profile': fields,
      });
    } else if (profile.clearPublicLocation) {
      await _functions.httpsCallable('commitUserCity').call({
        'clear': true,
        'targetId': trimmedUid,
        'profile': fields,
      });
    } else {
      if (profile.email != null) fields['Email'] = profile.email;
      await updateUserProfileFields(trimmedUid, fields);
    }
  }

  Stream<String?> get catalogueIdentityChanges => _auth.authStateChanges().map((user) => user?.uid);

  Future<Object?> _readPublicCatalogue(String path) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Sign in to browse profiles.');
    var stale = false;
    final subscription = catalogueIdentityChanges.listen((next) { if (next != uid) stale = true; });
    try {
      final value = _catalogueRead != null ? await _catalogueRead(path) : (await _dbRef(path).get()).value;
      if (stale || currentUserId != uid) throw StateError('Your session changed.');
      return value;
    } finally { unawaited(subscription.cancel()); }
  }

  Future<List<UserProfile>> getPublicUserProfilesAsync() async =>
      CatalogueProfiles.users(await _readPublicCatalogue('publicUserProfiles'));
  Future<List<Band>> getPublicBandProfilesAsync() async =>
      CatalogueProfiles.bands(await _readPublicCatalogue('publicBandProfiles'));
  Future<UserProfile?> getPublicUserProfileAsync(String userId) async {
    if (!CatalogueProfiles.validId(userId)) return null;
    return CatalogueProfiles.user(userId, await _readPublicCatalogue('publicUserProfiles/$userId'));
  }
  Future<Band?> getPublicBandProfileAsync(String bandId) async {
    if (!CatalogueProfiles.validId(bandId)) return null;
    return CatalogueProfiles.band(bandId, await _readPublicCatalogue('publicBandProfiles/$bandId'));
  }

  Future<UserProfile?> getUserProfileAsync([String? userId]) => _forCurrentSession(() async {
    final targetId = userId ?? currentUserId;
    if (targetId == null) return null;
    if (targetId != currentUserId) return getPublicUserProfileAsync(targetId);
    const fields = ['info', 'UserType', 'Nickname', 'DisplayName'];
    final snapshots = await Future.wait(fields.map((field) =>
        _dbRef('users/$targetId/$field').get()));
    if (targetId != currentUserId) throw StateError('Your session changed.');
    final data = <String, dynamic>{};
    for (var i = 0; i < fields.length; i++) {
      if (snapshots[i].exists) data[fields[i]] = snapshots[i].value;
    }
    return data.isEmpty ? null : UserProfile.fromJson(data, targetId);
  });

  // Compatibility entry points for all existing discovery/picker consumers.
  Future<List<UserProfile>> getAllUsersAsync() => getPublicUserProfilesAsync();

  Future<String> uploadAudioSnippetAsync(
    String userId,
    Uint8List? bytes,
    String? path,
  ) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('publicMedia/profileAudio')
          .child(userId)
          .child('snippet_${DateTime.now().millisecondsSinceEpoch}.mp3');

      UploadTask uploadTask;
      if (bytes != null) {
        uploadTask = ref.putData(
          bytes,
          SettableMetadata(contentType: 'audio/mpeg'),
        );
      } else if (path != null) {
        uploadTask = ref.putFile(File(path));
      } else {
        throw Exception("Both audio bytes and path are null for upload");
      }
      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      return url;
    } catch (e) { _rethrowAccessDenied(e);
      print("[FirebaseService] Error uploading audio snippet: $e");
      rethrow;
    }
  }

  Future<String> uploadProfilePictureAsync(
    String userId,
    Uint8List? bytes,
    String? path,
  ) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('publicMedia/profilePictures')
          .child(userId)
          .child(
            'profile_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );

      UploadTask uploadTask;
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      if (bytes != null) {
        uploadTask = ref.putData(bytes, metadata);
      } else if (path != null && !kIsWeb) {
        uploadTask = ref.putFile(File(path), metadata);
      } else {
        throw Exception("Both picture bytes and path are null for upload");
      }
      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      return url;
    } catch (e) { _rethrowAccessDenied(e);
      print("[FirebaseService] Error uploading profile picture: $e");
      rethrow;
    }
  }

  List<String> _parseList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is Map) return val.values.map((e) => e.toString()).toList();
    return [val.toString()];
  }

  // ==========================================
  // 3. Favorites
  // ==========================================

  Future<bool> isFavoriteAsync(String targetUserId) async {
    final selfId = currentUserId;
    if (selfId == null) return false;
    final snapshot = await _dbRef(
      'users/$selfId/Favorites/$targetUserId',
    ).get();
    return snapshot.exists && snapshot.value == true;
  }

  Future<void> toggleFavoriteAsync(String targetUserId, bool isFavorite) async {
    final selfId = currentUserId;
    if (selfId == null) return;
    if (isFavorite) {
      await _dbRef('users/$selfId/Favorites/$targetUserId').set(true);
    } else {
      await _dbRef('users/$selfId/Favorites/$targetUserId').remove();
    }
  }

  Future<List<String>> getFavoriteUserIdsAsync() async {
    final selfId = currentUserId;
    if (selfId == null) return [];
    final snapshot = await _dbRef('users/$selfId/Favorites').get();
    if (!snapshot.exists || snapshot.value is! Map) return [];
    final map = snapshot.value as Map;
    return map.keys.map((k) => k.toString()).toList();
  }

  // ==========================================
  // 4. Bands
  // ==========================================

  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return BandMembershipPolicy.discover(userId, (path) async {
      final adapter = _membershipRead;
      if (adapter != null) return adapter(path);
      return (await _dbRef(path).get()).value;
    });
  }

  Future<Band?> getBandInfoAsync(String bandId) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Sign in to view bands.');
    if (!CatalogueProfiles.validId(bandId)) return null;
    var stale = false;
    final subscription = catalogueIdentityChanges.listen((next) {
      if (next != uid) stale = true;
    });
    Future<Object?> read(String path) async {
      final value = _membershipRead != null
          ? await _membershipRead(path)
          : (await _dbRef(path).get()).value;
      if (stale || currentUserId != uid) throw StateError('Your session changed.');
      return value;
    }
    try {
    final membership = await read('Bands/$bandId/Members_band/$uid');
    if (membership is! Map || !BandMembershipPolicy.isValidStatus(
        membership['Status'] ?? membership['status'])) {
      final band = await getPublicBandProfileAsync(bandId);
      if (stale || currentUserId != uid) throw StateError('Your session changed.');
      return band;
    }
    // Band metadata and roster are read as exact leaves. A whole-band read
    // would also transfer every canonical Event and its private descendants.
    const fields = [
      'Name','EnsembleType','Genres','Qualification','RehearsalLocation',
      'RehearsalDayOfWeek','RehearsalDate','RehearsalTime',
      'RehearsalStartTime','RehearsalEndTime','Description','About','UserRole',
      'Location','PublicLocation','RehearsalDateTime','Members_band',
      'Style_band','Style','Level','Address','Contact','Members','History',
      'ConcertsProjects',
    ];
    final values = await Future.wait(fields.map((field) => read('Bands/$bandId/$field')));
    final data = <String, dynamic>{};
    for (var index = 0; index < fields.length; index++) {
      if (values[index] != null) data[fields[index]] = values[index];
    }
    return data.isEmpty ? null : Band.fromJson(data, bandId);
    } finally {
      await subscription.cancel();
    }
  }

  Stream<bool> subscribeToBandProfileAccess(String bandId) => _sessionStream(
    _dbRef('Bands/$bandId/Members_band').onValue.map((_) => true), false,
  );

  /// One server-owned mutation; production never falls back to protected RTDB writes.
  Future<void> mutateBandMembershipAsync(Map<String, dynamic> payload) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Please sign in first.');
    await _functions.httpsCallable('mutateBandMembership').call(payload);
    if (currentUserId != uid) {
      throw StateError('Your session changed. Please try again.');
    }
  }

  String _membershipOperationId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}';
  final _membershipPendingOperations = <String, String>{};
  Future<void> _submitMembershipMutation(Map<String, dynamic> payload) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Please sign in first.');
    final body = Map<String, dynamic>.of(payload)..remove('operationId');
    final fingerprint = '$uid/$body';
    final id = _membershipPendingOperations.putIfAbsent(
      fingerprint,
      () => payload['operationId'] as String? ?? _membershipOperationId(),
    );
    await mutateBandMembershipAsync({...payload, 'operationId': id});
    if (currentUserId != uid) {
      throw StateError('Your session changed. Please try again.');
    }
    _membershipPendingOperations.remove(fingerprint);
  }

  Future<void> createBandAsync(String userId, Band band) async {
    if (userId != currentUserId) {
      throw StateError('You can only create a band as yourself.');
    }
    final bandId = (band.name ?? 'My Band').replaceAll(' ', '_');
    final metadata = band.toJson();
    if(band.publicLocation != null && band.publicLocation!.confirmationNonce == null){
      metadata.remove('PublicLocation');metadata.remove('Location');
    }
    await _submitMembershipMutation({
      'action': 'create', 'bandId': bandId,
      // A stable creation ID makes a retry safe after an uncertain network result.
      'operationId': 'create_$userId', 'metadata': metadata,
      if(band.publicLocation?.confirmationNonce != null)
        'cityGrantNonce':band.publicLocation!.confirmationNonce,
      'initialMembers': band.membersBand.entries
          .where((e) => e.key != userId)
          .map(
            (e) => {
              'userId': e.key,
              'role': e.value.role ?? 'Member',
              'nickname': e.value.nickname ?? 'Member',
            },
          )
          .toList(),
    });
  }

  Future<void> updateBandAsync(String bandId, Band band) {
    final metadata=band.toJson();
    if(band.publicLocation != null && band.publicLocation!.confirmationNonce == null){
      metadata.remove('PublicLocation');metadata.remove('Location');
    }
    return _submitMembershipMutation({
        'action': 'metadata',
        'bandId': bandId,
        'operationId': _membershipOperationId(),
        'metadata': metadata,
        if(band.publicLocation?.confirmationNonce != null)
          'cityGrantNonce':band.publicLocation!.confirmationNonce,
      });
  }

  Future<List<BandMember>> getBandMembersAsync(String bandId) => _forCurrentSession(() async {
    final snapshot = await _dbRef('Bands/$bandId/Members_band').get();
    final List<BandMember> members = [];
    if (snapshot.exists && snapshot.value is Map) {
      final seenUserIds = <String>{};
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          final member = BandMember.fromJson(v, k.toString());
          final uid = member.userId;
          if (uid != null && uid.isNotEmpty) {
            if (seenUserIds.add(uid)) {
              members.add(member);
            }
          } else {
            members.add(member);
          }
        }
      });
    }
    return members;
  });

  // ==========================================
  // 5. Substitute Requests
  // ==========================================
  // SUB REQUESTS / GIGS (Multi-Path Synced)
  // ==========================================

  Future<String?> saveSubRequestAsync(SubRequest request) async {
    final newRef = _dbRef('SubRequests').push();
    final key = newRef.key ?? 'sub_${DateTime.now().millisecondsSinceEpoch}';
    final requestGroupId = request.requestGroupId ?? 'grp_$key';
    final updated = SubRequest(
      id: key,
      subRequestId: key,
      slotId: request.slotId ?? key,
      creatorUserId: currentUserId,
      userId: currentUserId,
      voicePart: request.voicePart,
      location: request.location,
      startTime: request.startTime,
      endTime: request.endTime,
      description: request.description,
      date: request.date,
      role: request.role,
      requestType: request.requestType,
      isPaid: request.isPaid,
      bandName: request.bandName,
      rehearsalDayOfWeek: request.rehearsalDayOfWeek,
      latitude: request.latitude,
      longitude: request.longitude,
      targetUserIds: request.targetUserIds,
      eventId: request.eventId,
      bandId: request.bandId,
      style: request.style,
      level: request.level,
      eventTitle: request.eventTitle,
      payAmount: request.payAmount,
      currency: request.currency,
      requestGroupId: requestGroupId,
      status: 'published',
      extraFields: request.extraFields,
    );

    await publishSubRequestGroupAsync(
      bandId: updated.bandId,
      requestGroupId: requestGroupId,
      requests: [updated],
      bandName: updated.bandName,
    );

    return key;
  }

  /// Saves an ordinary Map View music pin via server-owned callable createMapPin.
  /// Writes exclusively to SubRequests/{generatedId} with NotificationMode: 'map_pin'.
  /// Does NOT write to BandEvents/PublishedSubRequests or users/{uid}/SubRequests,
  /// ensuring ordinary music pins never collide with staffing requests or feeds.
  Future<SubRequest> saveMapPinAsync(SubRequest pin) async {
    final payload = <String, dynamic>{
      'latitude': pin.latitude,
      'longitude': pin.longitude,
      'eventType': pin.resolvedEventType ?? pin.extraFields['eventType'] ?? pin.extraFields['EventType'] ?? 'gigConcert',
      if (pin.location != null) 'location': pin.location,
      if (pin.date != null) 'date': pin.date,
      if (pin.startTime != null) 'startTime': pin.startTime,
      if (pin.endTime != null) 'endTime': pin.endTime,
      if (pin.description != null) 'description': pin.description,
      if (pin.bandName != null) 'bandName': pin.bandName,
      if (pin.bandId != null) 'bandId': pin.bandId,
      if (pin.style != null) 'style': pin.style,
      if (pin.extraFields['genre'] != null) 'genre': pin.extraFields['genre'],
      if (pin.extraFields['venue'] != null) 'venue': pin.extraFields['venue'],
      if (pin.extraFields['subCategory'] != null) 'subCategory': pin.extraFields['subCategory'],
      if (pin.audioSnippetUrl != null) 'audioSnippetUrl': pin.audioSnippetUrl,
      if (pin.audioSnippetTitle != null) 'audioSnippetTitle': pin.audioSnippetTitle,
      if (pin.extraFields['infoAudioTrack'] != null) 'infoAudioTrack': pin.extraFields['infoAudioTrack'],
    };

    try {
      final callable = _functions.httpsCallable('createMapPin');
      final result = await callable.call(payload);
      final resData = result.data is Map ? Map<dynamic, dynamic>.from(result.data as Map) : <dynamic, dynamic>{};
      final pinId = resData['id']?.toString() ?? '';
      if (pinId.isEmpty) {
        throw Exception('Server did not return a valid pin ID.');
      }
      final pinPayload = resData['pin'] is Map ? Map<dynamic, dynamic>.from(resData['pin'] as Map) : <dynamic, dynamic>{};
      return SubRequest.fromJson(pinPayload, pinId);
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Error creating Map Pin via createMapPin: $e');
      rethrow;
    }
  }

  /// Updates an ordinary Map View music pin via server-owned callable updateMapPin.
  Future<SubRequest> updateMapPinAsync(SubRequest pin) async {
    final pinId = pin.canonicalTargetId ?? pin.id;
    if (pinId == null || pinId.isEmpty) {
      throw Exception('Valid pin id is required to update a map pin.');
    }

    final payload = <String, dynamic>{
      'id': pinId,
      if (pin.latitude != null) 'latitude': pin.latitude,
      if (pin.longitude != null) 'longitude': pin.longitude,
      if (pin.location != null) 'location': pin.location,
      if (pin.date != null) 'date': pin.date,
      if (pin.startTime != null) 'startTime': pin.startTime,
      if (pin.endTime != null) 'endTime': pin.endTime,
      if (pin.description != null) 'description': pin.description,
      if (pin.bandName != null) 'bandName': pin.bandName,
      if (pin.style != null) 'style': pin.style,
      if (pin.extraFields['genre'] != null) 'genre': pin.extraFields['genre'],
      if (pin.extraFields['venue'] != null) 'venue': pin.extraFields['venue'],
      if (pin.audioSnippetUrl != null) 'audioSnippetUrl': pin.audioSnippetUrl,
      if (pin.audioSnippetTitle != null) 'audioSnippetTitle': pin.audioSnippetTitle,
      if (pin.extraFields['infoAudioTrack'] != null) 'infoAudioTrack': pin.extraFields['infoAudioTrack'],
    };

    try {
      final callable = _functions.httpsCallable('updateMapPin');
      final result = await callable.call(payload);
      final resData = result.data is Map ? Map<dynamic, dynamic>.from(result.data as Map) : <dynamic, dynamic>{};
      final pinPayload = resData['pin'] is Map ? Map<dynamic, dynamic>.from(resData['pin'] as Map) : <dynamic, dynamic>{};
      return SubRequest.fromJson(pinPayload, pinId);
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Error updating Map Pin via updateMapPin: $e');
      rethrow;
    }
  }

  /// Securely deletes an ordinary Map View music pin via server-owned callable deleteMapPin.
  Future<bool> deleteMapPinAsync(String pinId) async {
    if (pinId.isEmpty) {
      throw Exception('Valid pin id is required to delete a map pin.');
    }
    try {
      final callable = _functions.httpsCallable('deleteMapPin');
      final result = await callable.call({'id': pinId});
      final resData = result.data is Map ? Map<dynamic, dynamic>.from(result.data as Map) : <dynamic, dynamic>{};
      return resData['success'] == true;
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Error deleting Map Pin via deleteMapPin: $e');
      rethrow;
    }
  }

  Future<List<SubRequest>> getUserSubRequestFeedAsync() => _forCurrentSession(() async {
    final selfId = currentUserId;
    if (selfId == null) return [];

    final Map<String, SubRequest> combined = {};

    // 1. Always load all accessible public subrequests
    try {
      final all = await getAllSubRequestsAsync();
      for (final r in all) {
        final id = r.subRequestId ?? r.id;
        final st = r.status.toLowerCase();
        if (st == 'cancelled' || st == 'deleted' || st == 'closed') continue;
        if (id != null && id.isNotEmpty) {
          combined[id] = r;
        }
      }
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Error loading all subrequests: $e');
    }

    // 2. Also load any targeted feed entries
    try {
      final feedSnap = await _dbRef('userSubRequestFeed/$selfId').get();
      if (feedSnap.exists && feedSnap.value is Map) {
        for (final entry in (feedSnap.value as Map).entries) {
          final id = entry.key.toString();
          if (!combined.containsKey(id)) {
            final req = await getSubRequestAsync(id);
            if (req != null) {
              final st = req.status.toLowerCase();
              if (st != 'cancelled' && st != 'deleted' && st != 'closed') {
                combined[id] = req;
              }
            }
          }
        }
      }
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Error loading userSubRequestFeed: $e');
    }

    return combined.values.toList();
  });

  Future<List<SubRequest>> getAllSubRequestsAsync() => _forCurrentSession(() async {
    final List<SubRequest> requests = [];
    final selfId = currentUserId;
    final Set<String> seenIds = {};

    void addValidRequest(SubRequest req) {
      final id = req.subRequestId ?? req.id;
      if (id == null || id.isEmpty) return;
      if (seenIds.contains(id)) return;
      final st = req.status.toLowerCase();
      if (st == 'cancelled' || st == 'deleted' || st == 'closed') return;

      seenIds.add(id);
      requests.add(req);
    }

    // 1. Load truly public requests from /publicSubRequests
    try {
      final pubSnap = await _dbRef('publicSubRequests').get();
      if (pubSnap.exists && pubSnap.value is Map) {
        (pubSnap.value as Map).forEach((k, v) {
          if (v is Map) {
            final req = SubRequest.fromJson(v, k.toString());
            addValidRequest(req);
          }
        });
      }
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Error reading publicSubRequests: $e');
    }

    // 2. Load targeted requests for current user from /userSubRequestFeed/$selfId
    if (selfId != null && selfId.isNotEmpty) {
      try {
        final userFeedSnap = await _dbRef('userSubRequestFeed/$selfId').get();
        if (userFeedSnap.exists && userFeedSnap.value is Map) {
          (userFeedSnap.value as Map).forEach((k, v) {
            if (v is Map) {
              final req = SubRequest.fromJson(v, k.toString());
              addValidRequest(req);
            }
          });
        }
      } catch (e) { _rethrowAccessDenied(e);
        debugPrint('[FirebaseService] Error reading userSubRequestFeed: $e');
      }

      // 3. Load creator requests for current user from /creatorSubRequestFeed/$selfId
      try {
        final creatorFeedSnap = await _dbRef('creatorSubRequestFeed/$selfId').get();
        if (creatorFeedSnap.exists && creatorFeedSnap.value is Map) {
          (creatorFeedSnap.value as Map).forEach((k, v) {
            if (v is Map) {
              final req = SubRequest.fromJson(v, k.toString());
              addValidRequest(req);
            }
          });
        }
      } catch (e) { _rethrowAccessDenied(e);
        debugPrint('[FirebaseService] Error reading creatorSubRequestFeed: $e');
      }
    }

    return requests;
  });

  /// Real-time stream of merged, deduplicated, authorized SubRequests for Map View and feeds.
  /// Exactly one listener per authorized feed.
  /// Subscriptions are cleanly cancelled when the stream subscriber cancels.
  Stream<List<SubRequest>> getSubRequestFeedStream({String? targetUserId}) {
    final selfId = targetUserId ?? currentUserId;
    late StreamController<List<SubRequest>> controller;

    StreamSubscription<DatabaseEvent>? publicSub;
    StreamSubscription<DatabaseEvent>? userSub;
    StreamSubscription<DatabaseEvent>? creatorSub;

    final Map<String, SubRequest> publicMap = {};
    final Map<String, SubRequest> userMap = {};
    final Map<String, SubRequest> creatorMap = {};

    void emitMerged() {
      if (controller.isClosed) return;
      final List<SubRequest> merged = [];
      final Set<String> seenIds = {};

      void addIfValid(SubRequest r) {
        final id = r.subRequestId ?? r.id;
        if (id != null && !seenIds.contains(id) && r.isLive) {
          seenIds.add(id);
          merged.add(r);
        }
      }

      for (final r in publicMap.values) {
        addIfValid(r);
      }
      for (final r in userMap.values) {
        addIfValid(r);
      }
      for (final r in creatorMap.values) {
        addIfValid(r);
      }

      controller.add(merged);
    }

    controller = StreamController<List<SubRequest>>(
      onListen: () {
        publicSub = _dbRef('publicSubRequests').onValue.listen((event) {
          publicMap.clear();
          if (event.snapshot.exists && event.snapshot.value is Map) {
            (event.snapshot.value as Map).forEach((k, v) {
              if (v is Map) {
                try {
                  publicMap[k.toString()] = SubRequest.fromJson(v, k.toString());
                } catch (accessError) { _rethrowAccessDenied(accessError);}
              }
            });
          }
          emitMerged();
        }, onError: (e) {
          controller.addError(const PrivateDataAccessException());
        });

        if (selfId != null && selfId.isNotEmpty) {
          userSub = _dbRef('userSubRequestFeed/' + selfId).onValue.listen((event) {
            userMap.clear();
            if (event.snapshot.exists && event.snapshot.value is Map) {
              (event.snapshot.value as Map).forEach((k, v) {
                if (v is Map) {
                  try {
                    userMap[k.toString()] = SubRequest.fromJson(v, k.toString());
                  } catch (accessError) { _rethrowAccessDenied(accessError);}
                }
              });
            }
            emitMerged();
          }, onError: (e) {
            controller.addError(const PrivateDataAccessException());
          });

          creatorSub = _dbRef('creatorSubRequestFeed/' + selfId).onValue.listen((event) {
            creatorMap.clear();
            if (event.snapshot.exists && event.snapshot.value is Map) {
              (event.snapshot.value as Map).forEach((k, v) {
                if (v is Map) {
                  try {
                    creatorMap[k.toString()] = SubRequest.fromJson(v, k.toString());
                  } catch (accessError) { _rethrowAccessDenied(accessError);}
                }
              });
            }
            emitMerged();
          }, onError: (e) {
            controller.addError(const PrivateDataAccessException());
          });
        }
      },
      onCancel: () {
        publicSub?.cancel();
        publicSub = null;
        userSub?.cancel();
        userSub = null;
        creatorSub?.cancel();
        creatorSub = null;
        publicMap.clear();
        userMap.clear();
        creatorMap.clear();
      },
    );

    return _sessionStream(controller.stream, <SubRequest>[]);
  }


  /// MAP-VIEW-FEED-03B: Real-time stream of server-owned public Music Promotion pins for Map View.
  /// Reads directly from sanitized server projection /publicMapPinFeed.
  /// Zero access to canonical /SubRequests collection.
  /// Exactly one underlying RTDB listener per stream subscription. Cancelled cleanly when subscriber cancels.
  /// Performs ZERO database writes while reading.
  Stream<List<SubRequest>> getMapPinFeedStream() {
    late StreamController<List<SubRequest>> controller;
    StreamSubscription<DatabaseEvent>? pinSub;
    final Map<String, SubRequest> pinMap = {};

    void emitPins() {
      if (controller.isClosed) return;
      controller.add(pinMap.values.toList());
    }

    controller = StreamController<List<SubRequest>>(
      onListen: () {
        pinSub = _dbRef('publicMapPinFeed').onValue.listen((event) {
          pinMap.clear();
          if (event.snapshot.exists && event.snapshot.value is Map) {
            (event.snapshot.value as Map).forEach((k, v) {
              if (v is Map) {
                try {
                  final status = (v['Status'] ?? v['status'] ?? '').toString().toLowerCase();
                  if (status != 'cancelled' && status != 'deleted' && status != 'closed') {
                    pinMap[k.toString()] = SubRequest.fromJson(v, k.toString());
                  }
                } catch (accessError) { _rethrowAccessDenied(accessError);}
              }
            });
          }
          emitPins();
        }, onError: (e) {
          debugPrint('[FirebaseService] publicMapPinFeed stream error: $e');
        });
      },
      onCancel: () {
        pinSub?.cancel();
        pinSub = null;
        pinMap.clear();
      },
    );

    return controller.stream;
  }

  /// MAP-VIEW-FEED-02: Lifecycle-managed Event feed stream for Map View.
  /// Merges publicMapEventFeed and userMapEventFeed/{userId}.
  /// Exactly one listener per feed. Subscriptions are cleanly cancelled when caller cancels.
  /// Tolerates private feed permission errors without terminating the public feed.
  /// Performs ZERO database writes while reading.
  Stream<List<MapEventItem>> getMapEventFeedStream({String? targetUserId}) {
    final selfId = targetUserId ?? currentUserId;
    late StreamController<List<MapEventItem>> controller;

    StreamSubscription<DatabaseEvent>? publicSub;
    StreamSubscription<DatabaseEvent>? userSub;

    final Map<String, MapEventItem> publicMap = {};
    final Map<String, MapEventItem> userMap = {};

    void emitMerged() {
      if (controller.isClosed) return;
      final List<MapEventItem> merged = [];
      final Set<String> seenIds = {};

      void addIfValid(MapEventItem item) {
        if (!seenIds.contains(item.mapItemId)) {
          seenIds.add(item.mapItemId);
          merged.add(item);
        }
      }

      for (final item in publicMap.values) {
        addIfValid(item);
      }
      for (final item in userMap.values) {
        addIfValid(item);
      }

      controller.add(merged);
    }

    controller = StreamController<List<MapEventItem>>(
      onListen: () {
        // 1. Subscribe once to publicMapEventFeed
        publicSub = _dbRef('publicMapEventFeed').onValue.listen((event) {
          publicMap.clear();
          if (event.snapshot.exists && event.snapshot.value is Map) {
            (event.snapshot.value as Map).forEach((k, v) {
              if (v is Map) {
                try {
                  publicMap[k.toString()] = MapEventItem.fromJson(v, k.toString());
                } catch (accessError) { _rethrowAccessDenied(accessError);}
              }
            });
          }
          emitMerged();
        }, onError: (e) {
          debugPrint('[FirebaseService] publicMapEventFeed stream notice: $e');
        });

        // 2. Subscribe once to userMapEventFeed/{selfId} if user is authenticated
        if (selfId != null && selfId.trim().isNotEmpty) {
          userSub = _dbRef('userMapEventFeed/${selfId.trim()}').onValue.listen((event) {
            userMap.clear();
            if (event.snapshot.exists && event.snapshot.value is Map) {
              (event.snapshot.value as Map).forEach((k, v) {
                if (v is Map) {
                  try {
                    userMap[k.toString()] = MapEventItem.fromJson(v, k.toString());
                  } catch (accessError) { _rethrowAccessDenied(accessError);}
                }
              });
            }
            emitMerged();
          }, onError: (e) {
            debugPrint('[FirebaseService] userMapEventFeed stream notice (tolerated): $e');
          });
        }
      },
      onCancel: () {
        publicSub?.cancel();
        publicSub = null;
        userSub?.cancel();
        userSub = null;
        publicMap.clear();
        userMap.clear();
      },
    );

    return controller.stream;
  }


  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) => _forCurrentSession(() async {
    final List<SubRequest> requests = [];
    final selfId = currentUserId;

    if (userId == selfId && selfId != null && selfId.isNotEmpty) {
      try {
        final creatorSnap = await _dbRef('creatorSubRequestFeed/$userId').get();
        if (creatorSnap.exists && creatorSnap.value is Map) {
          (creatorSnap.value as Map).forEach((k, v) {
            if (v is Map) {
              final req = SubRequest.fromJson(v, k.toString());
              final st = req.status.toLowerCase();
              if (st != 'cancelled' && st != 'deleted' && st != 'closed') {
                requests.add(req);
              }
            }
          });
        }
      } catch (e) { _rethrowAccessDenied(e);
        debugPrint("[FirebaseService] Error loading creatorSubRequestFeed/$userId: $e");
      }
    } else {
      // For other users, return authorized requests from the merged feed created by that user
      final all = await getAllSubRequestsAsync();
      return all.where((r) => r.creatorUserId == userId || r.userId == userId).toList();
    }

    return requests;
  });

  Future<List<SubRequest>> getSubRequestsForEventAsync(
    String bandId,
    String eventId,
  ) async {
    final all = await getAllSubRequestsAsync();
    return all.where((r) {
      if (r.eventId != eventId) return false;
      if (bandId.isNotEmpty && r.bandId != null && r.bandId!.isNotEmpty && r.bandId != bandId) {
        return false;
      }
      return true;
    }).toList();
  }

  String _sanitizeRtdbKey(String input) {
    return input.replaceAll(RegExp(r'[\.\#\$\[\]\/\s]'), '_');
  }

  Future<List<String>> saveSubRequestsBatchAsync(List<SubRequest> requests) async {
    if (requests.isEmpty) return [];
    final groupId = requests.first.requestGroupId ?? _dbRef('SubRequests').push().key!;
    return publishSubRequestGroupAsync(bandId: requests.first.bandId,
      requestGroupId: groupId, requests: requests);
  }

  Future<List<String>> publishSubRequestGroupAsync({
    required String? bandId,
    required String requestGroupId,
    required List<SubRequest> requests,
    String? bandName,
  }) async {
    final currentUserId = _auth.currentUser?.uid;
    final now = DateTime.now().millisecondsSinceEpoch;
    final List<SubRequest> updatedRequests = [];

    for (final req in requests) {
      final cleanBandId = req.bandId != null ? _sanitizeRtdbKey(req.bandId!) : (currentUserId != null ? _sanitizeRtdbKey(currentUserId) : 'band');
      final cleanEventId = req.eventId != null ? _sanitizeRtdbKey(req.eventId!) : 'standalone';
      final cleanSlotId = req.slotId != null ? _sanitizeRtdbKey(req.slotId!) : '${DateTime.now().millisecondsSinceEpoch}';

      final key = (req.subRequestId != null &&
              req.subRequestId!.isNotEmpty &&
              !req.subRequestId!.startsWith('slot_') &&
              !req.subRequestId!.startsWith('initial_') &&
              !req.subRequestId!.startsWith('draft_'))
          ? req.subRequestId!
          : 'sub_${cleanBandId}_${cleanEventId}_${cleanSlotId}_$now';

      final updated = req.copyWith(
        id: key,
        subRequestId: key,
        slotId: req.slotId ?? key,
        creatorUserId: currentUserId,
        userId: currentUserId,
        createdAt: req.createdAt ?? now,
        status: 'published',
      );
      updatedRequests.add(updated);
    }

    // Server-owned Cloud Function for atomic canonical publication and feed projections
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('publishSubRequestGroup');
    await callable.call<Map<dynamic, dynamic>>({
      'bandId': bandId,
      'requestGroupId': requestGroupId,
      'bandName': bandName,
      'slots': updatedRequests.map((r) => r.toJson()).toList(),
    });

    return updatedRequests
        .map((r) => r.subRequestId ?? r.slotId ?? r.id ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  String? _lastAssignedAgreementConversationId;
  String? get lastAssignedAgreementConversationId => _lastAssignedAgreementConversationId;

  Future<void> assignSubstituteCandidateAsync({
    required String subRequestId,
    required String candidateUserId,
    required String bandId,
    required String eventId,
    required String roleOrInstrument,
    String? candidateName,
    String? slotId,
    String? replacedMemberId,
    String? replacedMemberName,
  }) async {
    final actualSlotId = (slotId != null && slotId.isNotEmpty) ? slotId : subRequestId;
    _lastAssignedAgreementConversationId = null;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('assignSubstitute');
      final result = await callable.call<Map<String, dynamic>>({
        'subRequestId': subRequestId,
        'candidateUserId': candidateUserId,
        'candidateName': candidateName,
        'bandId': bandId,
        'eventId': eventId,
        'roleOrInstrument': roleOrInstrument,
        'slotId': actualSlotId,
        'replacedMemberId': replacedMemberId,
        'replacedMemberName': replacedMemberName,
      });
      final convId = result.data['conversationId']?.toString() ?? '';
      _lastAssignedAgreementConversationId = convId.isNotEmpty ? convId : null;
    } on FirebaseFunctionsException catch (e) { _rethrowAccessDenied(e);
      if (e.code == 'already-exists') {
        throw StateError('Assignment conflict: Slot $subRequestId has already been assigned to another candidate.');
      }
      rethrow;
    }
  }

  Future<void> revokeSubstituteAssignmentAsync({
    required String subRequestId,
    required String candidateUserId,
    required String bandId,
    required String eventId,
    String? slotId,
  }) async {
    final actualSlotId = (slotId != null && slotId.isNotEmpty) ? slotId : subRequestId;

    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('revokeSubstituteAssignment');
    await callable.call<Map<String, dynamic>>({
      'subRequestId': subRequestId,
      'candidateUserId': candidateUserId,
      'bandId': bandId,
      'eventId': eventId,
      'slotId': actualSlotId,
    });
  }

  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) => _forCurrentSession(() async {
    final uid = userId.trim();
    if (uid.isEmpty || uid != currentUserId) {
      throw StateError('Sign in to view your applications.');
    }
    final snap = await _dbRef('users/$uid/AppliedSubRequests').get();
    if (uid != currentUserId) throw StateError('Your session changed.');
    return snap.value is Map
        ? (snap.value as Map).keys.map((k) => k.toString()).toSet()
        : {};
  });

  /// One-shot lookup of the current user's applied state for the specific subRequestIds
  /// shown in an opened Map View details card.
  /// Does NOT create persistent RTDB listeners and only reads user-authorized nodes.
  Future<Set<String>> resolveAppliedSubRequestIdsForCardAsync({
    required String userId,
    required Iterable<String> subRequestIds,
  }) => _forCurrentSession(() async {
    final uid = userId.trim();
    final targetIds = subRequestIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (uid.isEmpty || targetIds.isEmpty) return {};

    final resolved = <String>{};

    // 1. Check user's own AppliedSubRequests map via getUserAppliedSubRequestIdsAsync
    final userApplied = await getUserAppliedSubRequestIdsAsync(uid);
    for (final id in targetIds) {
      if (userApplied.contains(id)) {
        resolved.add(id);
      }
    }

    // 2. For any remaining IDs, check the user's own authorized leaf SubRequests/$id/Responses/$uid
    final remaining = targetIds.difference(resolved);
    for (final id in remaining) {
        final leafSnap = await _dbRef('SubRequests/$id/Responses/$uid').get();
        if (uid != currentUserId) throw StateError('Your session changed.');
        if (leafSnap.exists &&
            (leafSnap.value == true ||
                leafSnap.value == 'true' ||
                leafSnap.value is Map)) {
          resolved.add(id);
        }
    }

    return resolved;
  });

  /// One-shot check whether [userId] is a Leader or Admin of [bandId].
  Future<bool> isBandLeaderOrAdminAsync(String bandId, String userId) async {
    final uid = userId.trim();
    if (uid != currentUserId || !BandMembershipPolicy.isRealId(bandId)) {
      return false;
    }
    try {
      final bands = await getUserBandsAsync(uid);
      if (currentUserId != uid || !bands.containsKey(bandId)) return false;
      final path = 'Bands/$bandId/Members_band/$uid';
      final raw = _membershipRead != null
          ? await _membershipRead(path)
          : (await _dbRef(path).get()).value;
      return currentUserId == uid &&
          raw is Map &&
          _isCanonicalManager(raw, uid);
    } catch (accessError) { _rethrowAccessDenied(accessError);
      return false;
    }
  }

  Future<void> addResponseToSubRequestAsync(String subRequestId, String userId) async {
    final uid = currentUserId;
    if (uid == null || uid != userId) throw StateError('Sign in to respond.');
    await _functions.httpsCallable('respondToSubRequest').call({'subRequestId': subRequestId});
    if (currentUserId != uid) throw StateError('Your session changed.');
  }

  Future<RequestManagementAccess> authorizeRequestManagement({
    String? bandId, String? requestId, String? expectedCreatorId,
    bool Function()? isCurrent,
  }) => _forCurrentSession(() async {
    final uid = currentUserId;
    if (uid == null) throw const PrivateDataAccessException();
    var sessionChanged = false;
    final identitySubscription = catalogueIdentityChanges.listen((next) {
      if (next != uid) sessionChanged = true;
    });
    try {
    bool current() => !sessionChanged && uid == currentUserId && (isCurrent?.call() ?? true);
    if (requestId == null) {
      if (bandId == 'freelance' || bandId == 'standalone') {
        return RequestManagementAccess(userId: uid, bandId: bandId!);
      }
      if (!BandMembershipPolicy.isRealId(bandId) ||
          !await isBandLeaderOrAdminAsync(bandId!, uid)) {
        throw const PrivateDataAccessException();
      }
      return RequestManagementAccess(userId: uid, bandId: bandId);
    }
    if (!CatalogueProfiles.validId(requestId)) throw const PrivateDataAccessException();
    // Read only authorization metadata. Rules independently authorize each leaf;
    // never fetch request bodies, response IDs/counts or profiles at this stage.
    Future<Object?> read(String path) async {
      if (!current()) throw const PrivateDataAccessException();
      final value = _membershipRead != null ? await _membershipRead(path) : (await _dbRef(path).get()).value;
      if (!current()) throw const PrivateDataAccessException();
      return value;
    }
    const fields = ['BandId','bandId','CreatorUserId','creatorUserId','UserId','userId',
      'createdBy','NotificationMode','notificationMode'];
    final values = await Future.wait(fields.map((f) => read('SubRequests/$requestId/$f')));
    if (!current()) throw const PrivateDataAccessException();
    final headers = <String,Object?>{for (var i=0;i<fields.length;i++) fields[i]:values[i]};
    Object? canonical(String a,String b) {
      if (headers[a] != null && headers[b] != null && headers[a] != headers[b]) {
        throw const PrivateDataAccessException();
      }
      return headers[a] ?? headers[b];
    }
    final ownerBand = canonical('BandId','bandId');
    final creator = canonical('CreatorUserId','creatorUserId') ??
        canonical('UserId','userId') ?? headers['createdBy'];
    if (headers['NotificationMode'] == 'map_pin' || headers['notificationMode'] == 'map_pin' ||
        ownerBand is! String || creator is! String || !CatalogueProfiles.validId(creator) ||
        (bandId != null && bandId != ownerBand) ||
        (expectedCreatorId != null && expectedCreatorId != creator)) {
      throw const PrivateDataAccessException();
    }
    final freelance = ownerBand == 'freelance' || ownerBand == 'standalone';
    if (freelance ? creator != uid :
        (!BandMembershipPolicy.isRealId(ownerBand) || !await isBandLeaderOrAdminAsync(ownerBand,uid))) {
      throw const PrivateDataAccessException();
    }
    if (!current()) throw const PrivateDataAccessException();
    final value = await read('SubRequests/$requestId');
    if (!current() || value is! Map) throw const PrivateDataAccessException();
    final raw = value;
    if (headers.entries.any((entry) => raw[entry.key] != entry.value)) {
      throw const PrivateDataAccessException();
    }
    return RequestManagementAccess(userId:uid,bandId:ownerBand,
      request:SubRequest.fromJson(raw,requestId),headers:headers);
    } finally {
      await identitySubscription.cancel();
    }
  });

  Stream<bool> watchRequestManagementAccess(RequestManagementAccess access) {
    final subscriptions = <StreamSubscription>[];
    late StreamController<bool> controller;
    void fail() { if (!controller.isClosed) controller.add(false); }
    controller = StreamController<bool>(onListen: () {
      if (currentUserId != access.userId) { fail(); return; }
      subscriptions.add(catalogueIdentityChanges.listen((uid) {
        if (uid != access.userId) fail();
      },onError:(Object _) => fail()));
      if (BandMembershipPolicy.isRealId(access.bandId)) {
        subscriptions.add(_dbRef('Bands/${access.bandId}/Members_band/${access.userId}').onValue.listen((event) {
          final value=event.snapshot.value;
          if (value is! Map || !_isCanonicalManager(value,access.userId)) fail();
        },onError:(Object _) => fail()));
      }
      final id=access.request?.subRequestId ?? access.request?.id;
      if (id != null) {
        for (final entry in access.headers.entries) {
          subscriptions.add(_dbRef('SubRequests/$id/${entry.key}').onValue.listen((event) {
            if (event.snapshot.value != entry.value) fail();
          },onError:(Object _) => fail()));
        }
      }
    },onCancel:() async {
      for (final subscription in subscriptions) { await subscription.cancel(); }
    });
    return controller.stream;
  }

  bool _isCanonicalManager(Map raw,String uid) {
    String normalized(Object? value) => value is String ? value.trim().toLowerCase() : '';
    for (final pair in [['Role','role'],['Status','status']]) {
      if (raw[pair[0]] != null && raw[pair[1]] != null &&
          normalized(raw[pair[0]]) != normalized(raw[pair[1]])) {
        return false;
      }
    }
    return BandMembershipPolicy.canManageMember(BandMember.fromJson(raw,uid));
  }

  Future<SubRequest?> getSubRequestAsync(String subRequestId) => _forCurrentSession(() async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Sign in to view requests.');
    for (final path in ['creatorSubRequestFeed/$uid/$subRequestId',
      'userSubRequestFeed/$uid/$subRequestId', 'publicSubRequests/$subRequestId',
      if (FeatureToggles.enableMapView) 'publicMapPinFeed/$subRequestId',
      'SubRequests/$subRequestId']) {
      final snapshot = await _dbRef(path).get();
      if (currentUserId != uid) throw StateError('Your session changed.');
      if (snapshot.value is Map) {
        final request = SubRequest.fromJson(snapshot.value as Map, subRequestId);
        if (!FeatureToggles.enableMapView && request.isMapOnlyPin) return null;
        return {'cancelled', 'deleted'}.contains(request.status.toLowerCase()) ? null : request;
      }
    }
    return null;
  });

  Future<bool> deleteSubRequestAsync(
    String creatorId,
    String subRequestId,
  ) async {
      if (subRequestId.isEmpty) return false;

      final uid = currentUserId;
      if (uid == null) return false;
      await _functions.httpsCallable('deleteSubRequest').call({'subRequestId': subRequestId});
      return currentUserId == uid;
  }

  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String subRequestId) => _forCurrentSession(() async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Sign in to manage responses.');
    final snapshot = await _dbRef('SubRequests/$subRequestId/Responses').get();
    if (currentUserId != uid) throw StateError('Your session changed.');
    return snapshot.value is Map ? Map<String, dynamic>.from(snapshot.value as Map) : {};
  });

  Future<int> getSubRequestResponseCountAsync(String subRequestId) async {
    final responses = await getSubRequestResponsesAsync(subRequestId);
    return responses.length;
  }

  Stream<int> subscribeToSubRequestResponseCount(String subRequestId) =>
      _sessionStream(_dbRef('SubRequests/$subRequestId/Responses').onValue.map(
        (event) => event.snapshot.value is Map ? (event.snapshot.value as Map).length : 0,
      ), 0);

  Future<String> createAgreementChatAsync(
    String senderId,
    String receiverId,
    Agreement agreement,
    Message message,
  ) async {
    final subRequestId = agreement.subRequestId ?? '';
    final conversationId = await createAgreementConversationAsync(
      subRequestId,
      receiverId,
      agreement: agreement,
    );
    return conversationId;
  }

  // ==========================================
  // 6. Direct Chat Messages
  // ==========================================

  Future<String> createAgreementConversationAsync(
    String subRequestId,
    String applicantId, {
    Agreement? agreement,
  }) async {
    if (subRequestId.isEmpty || applicantId.isEmpty) {
      throw ArgumentError('subRequestId and applicantId must not be empty.');
    }
    final result = await _functions
        .httpsCallable('createAgreementConversation')
        .call({
          'subRequestId': subRequestId,
          'applicantId': applicantId,
        });
    final convId = result.data['conversationId']?.toString() ?? '';
    if (convId.isEmpty) {
      throw StateError('Server failed to return conversationId for agreement.');
    }
    return convId;
  }

  // ==========================================
  // 6. Direct Chat Messages
  // ==========================================

  Future<String> getOrCreateDirectConversationAsync(
    String userId1, [
    String? userId2,
  ]) async {
    final targetUserId = (userId2 != null && userId2.isNotEmpty)
        ? (userId1 == currentUserId ? userId2 : userId1)
        : userId1;

    final result = await _functions
        .httpsCallable('getOrCreateDirectConversation')
        .call({'otherUserId': targetUserId});
    final convId = result.data['conversationId']?.toString() ?? '';
    if (convId.isEmpty) throw StateError('The conversation could not be opened.');
    return convId;
  }

  Future<void> sendConversationMessageAsync(
    String conversationId,
    String text,
    String receiverUserId,
    String senderName,
  ) async {
      await _functions.httpsCallable('sendDirectMessage').call({
        'conversationId': conversationId,
        'text': text,
        'receiverUserId': receiverUserId,
      });
  }

  Stream<Map<String, dynamic>?> subscribeToConversationMetadata(
    String conversationId,
  ) {
    return _dbRef('conversations/$conversationId').onValue.asyncMap((event) async {
      Agreement? agreement;
      List<dynamic>? participants;

      final data = event.snapshot.value;
      if (data is Map) {
        final agreementRaw = data['Agreement'] ?? data['agreement'];
        if (agreementRaw is Map) {
          try {
            agreement = Agreement.fromJson(agreementRaw);
          } catch (accessError) { _rethrowAccessDenied(accessError);}
        }
        participants = _parseList(
          data['Participants'] ?? data['participants'],
        );
      }

      return {
        'participants': participants ?? [],
        'agreement': agreement,
      };
    });
  }

  Stream<List<Message>> subscribeToMessages(String conversationId) {
    return _dbRef(
      'conversations/$conversationId/messages',
    ).orderByChild('Timestamp').onValue.map((event) {
      final List<Message> list = [];
      final data = event.snapshot.value;
      if (data is Map) {
        data.forEach((k, v) {
          if (v is Map) {
            list.add(
              Message.fromJson(v, k.toString(), currentUserId: currentUserId),
            );
          }
        });
        // Sort chronologically
        list.sort(
          (a, b) => (a.timestamp ?? DateTime.now()).compareTo(
            b.timestamp ?? DateTime.now(),
          ),
        );
      }
      return list;
    });
  }

  Future<void> markConversationAsRead(String conversationId) async {
    try {
      await _functions.httpsCallable('markDirectConversationRead').call({
        'conversationId': conversationId,
      });
    } catch (e) { _rethrowAccessDenied(e);
      print("[FirebaseService] Error marking conversation as read: $e");
    }
  }

  Future<void> markBandSectionConversationReadAsync(String conversationId) async {
    try {
      await _functions.httpsCallable('markBandSectionConversationRead').call({
        'conversationId': conversationId,
      });
    } catch (e) { _rethrowAccessDenied(e);
      print("[FirebaseService] Error marking band section conversation as read: $e");
    }
  }

  Future<String> createBandSectionConversationAsync({
    required String bandId,
    required String groupName,
    required List<String> participantIds,
    String? sectionKey,
    String? sourceInstrument,
  }) async {
    final result = await _functions.httpsCallable('createBandSectionConversation').call({
      'bandId': bandId,
      'groupName': groupName,
      'participantIds': participantIds,
      if (sectionKey != null) 'sectionKey': sectionKey,
      if (sourceInstrument != null) 'sourceInstrument': sourceInstrument,
    });
    return result.data['conversationId']?.toString() ?? '';
  }

  Future<String> sendBandSectionMessageAsync({
    required String conversationId,
    required String text,
    String? replyToText,
    String? replyToSenderName,
  }) async {
    final result = await _functions.httpsCallable('sendBandSectionMessage').call({
      'conversationId': conversationId,
      'text': text,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
    });
    return result.data['messageId']?.toString() ?? '';
  }

  Future<void> manageBandSectionConversationAsync({
    required String conversationId,
    required String action,
    String? groupName,
    List<String>? participantIds,
  }) async {
    await _functions.httpsCallable('manageBandSectionConversation').call({
      'conversationId': conversationId,
      'action': action,
      if (groupName != null) 'groupName': groupName,
      if (participantIds != null) 'participantIds': participantIds,
    });
  }

  Stream<Map<String, dynamic>?> subscribeToBandSectionMetadata(String conversationId) {
    return _dbRef('conversations/$conversationId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        return {
          'conversationId': conversationId,
          'conversationType': data['conversationType']?.toString() ?? 'band_section',
          'bandId': data['bandId']?.toString(),
          'bandName': data['bandName']?.toString() ?? 'Band',
          'groupName': data['groupName']?.toString() ?? 'Section Chat',
          'createdBy': data['createdBy']?.toString(),
          'participantCount': data['participantCount'] is int
              ? data['participantCount'] as int
              : int.tryParse(data['participantCount']?.toString() ?? '0') ?? 0,
          'participants': (data['participants'] is Map)
              ? Map<String, dynamic>.from(data['participants'] as Map)
              : <String, dynamic>{},
          'admins': (data['admins'] is Map)
              ? Map<String, dynamic>.from(data['admins'] as Map)
              : <String, dynamic>{},
          'sectionKey': data['sectionKey']?.toString(),
          'sourceInstrument': data['sourceInstrument']?.toString(),
          'createdTimestamp': data['createdTimestamp']?.toString(),
          'updatedTimestamp': data['updatedTimestamp']?.toString(),
        };
      }
      return null;
    });
  }

  Stream<bool> subscribeToUnreadNotifications() {
    final selfId = currentUserId;
    if (selfId == null) return Stream.value(false);

    return _dbRef('userConversations/$selfId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        for (var convId in data.keys) {
          final item = data[convId];
          if (item is Map && item['hasUnread'] == true) {
            return true;
          }
        }
      }
      return false;
    });
  }

  Future<bool> hasAnyUnreadMessagesAsync() async {
    final selfId = currentUserId;
    if (selfId == null) return false;

    final snapshot = await _dbRef('userConversations/$selfId').get();
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map;
      for (var convId in data.keys) {
        final item = data[convId];
        if (item is Map && item['hasUnread'] == true) {
          return true;
        }
      }
    }
    return false;
  }

  Stream<List<AppNotification>> subscribeToUserNotifications([String? userId]) {
    final uid = userId ?? currentUserId;
    if (uid == null || uid != currentUserId) return Stream.value([]);
    return _sessionStream(_dbRef('userNotifications/$uid').onValue.map((event) {
      if (uid != currentUserId) return <AppNotification>[];
      final value = event.snapshot.value;
      if (value is! Map) return <AppNotification>[];
      final result = <AppNotification>[];
      value.forEach((key, item) {
        if (item is Map) result.add(AppNotification.fromJson(item, key.toString()));
      });
      return result;
    }), <AppNotification>[]);
  }

  Stream<int> subscribeToUnreadNotificationCount([String? userId]) {
    final uid = userId ?? currentUserId;
    if (uid == null || uid.isEmpty) return Stream.value(0);

    return subscribeToUserNotifications(uid).map((notifications) {
      return notifications.where((n) => !n.isRead).length;
    });
  }

  Future<void> markNotificationReadAsync(String notificationId) async {
    await _functions.httpsCallable('markNotificationRead').call({'notificationId': notificationId});
  }

  Future<void> markFeatureNotificationsReadAsync(String featureId) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return;
    try {
      final callable = _functions.httpsCallable('markFeatureNotificationsRead');
      await callable.call<Map<String, dynamic>>({
        'featureId': featureId,
      });
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] markFeatureNotificationsRead error: $e');
    }
  }

  Future<void> markAllNotificationsReadAsync() async {
    await _functions.httpsCallable('markAllNotificationsRead').call();
  }

  Future<List<Map<String, dynamic>>> getActiveConversationsAsync() => _forCurrentSession(() async {
    final selfId = currentUserId;
    if (selfId == null) return [];

    final snapshot = await _dbRef('userConversations/$selfId').get();
    final List<Map<String, dynamic>> conversations = [];

    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map;
      for (var entry in data.entries) {
        final convId = entry.key.toString();
        final item = entry.value;
        if (item is Map) {
          final convType = item['conversationType']?.toString() ?? 'direct';
          final isGroup = convType == 'band_section';

          if (isGroup) {
            final groupName = item['groupName']?.toString() ?? 'Section Chat';
            final bandName = item['bandName']?.toString() ?? 'Band';
            final bandId = item['bandId']?.toString();
            final participantCount = item['participantCount'] is int
                ? item['participantCount'] as int
                : int.tryParse(item['participantCount']?.toString() ?? '0') ?? 0;
            final sectionKey = item['sectionKey']?.toString();
            final sourceInstrument = item['sourceInstrument']?.toString();

            final rawTs = item['lastMessageTimestamp'] ??
                item['lastMessageTime'] ??
                item['createdTimestamp'] ??
                item['CreatedTimestamp'];
            final parsedDt = parseDateTime(rawTs);

            conversations.add({
              'conversationId': convId,
              'isGroup': true,
              'conversationType': 'band_section',
              'groupName': groupName,
              'bandName': bandName,
              'bandId': bandId,
              'participantCount': participantCount,
              'sectionKey': sectionKey,
              'sourceInstrument': sourceInstrument,
              'otherUserName': groupName,
              'otherUserId': '',
              'lastMessageSenderName': item['lastMessageSenderName']?.toString(),
              'lastMessageSenderId': item['lastMessageSenderId']?.toString(),
              'lastMessageText': item['lastMessageText']?.toString() ?? 'No messages yet',
              'lastMessageTimestamp': item['lastMessageTimestamp']?.toString() ?? '',
              'timestamp': parsedDt,
              'hasUnread': item['hasUnread'] == true,
            });
            continue;
          }

          if (convType == 'session_chat') {
            final sessionTitle = item['otherUserName']?.toString() ??
                item['title']?.toString() ??
                'Session Chat';
            final sessionId = item['sessionId']?.toString() ?? '';
            final rawTs = item['lastMessageTimestamp'] ??
                item['lastMessageTime'] ??
                item['createdTimestamp'] ??
                item['CreatedTimestamp'];
            final parsedDt = parseDateTime(rawTs);

            conversations.add({
              'conversationId': convId,
              'isGroup': false,
              'isSessionChat': true,
              'sessionId': sessionId,
              'otherUserId': '',
              'otherUserName': sessionTitle,
              'lastMessageText': item['lastMessageText']?.toString() ?? 'No messages yet',
              'lastMessageTimestamp': item['lastMessageTimestamp']?.toString() ?? '',
              'timestamp': parsedDt,
              'hasUnread': item['hasUnread'] == true,
              'conversationType': 'session_chat',
            });
            continue;
          }

          final otherUserId = item['otherUserId']?.toString();
          if (otherUserId == null || otherUserId.isEmpty) continue;

          String otherUserName = "Musician";
          String? profilePic;
          final profile = await getUserProfileAsync(otherUserId);
          if (profile != null) {
            otherUserName =
                profile.displayName ?? profile.nickname ?? "Musician";
            profilePic = profile.profilePictureUrl;
          }

          final rawTs =
              item['lastMessageTimestamp'] ??
              item['lastMessageTime'] ??
              item['createdTimestamp'] ??
              item['CreatedTimestamp'];
          final parsedDt = parseDateTime(rawTs);

          // Parse agreement if attached or in agreements map
          final agreementRaw = item['agreement'] ?? item['Agreement'];
          Agreement? agreement;
          if (agreementRaw is Map) {
            try {
              agreement = Agreement.fromJson(agreementRaw);
            } catch (accessError) { _rethrowAccessDenied(accessError);}
          }

          conversations.add({
            'conversationId': convId,
            'isGroup': false,
            'otherUserId': otherUserId,
            'otherUserName': otherUserName,
            'otherUserProfilePicture': profilePic,
            'lastMessageText':
                item['lastMessageText']?.toString() ?? 'No messages yet',
            'lastMessageTimestamp':
                item['lastMessageTimestamp']?.toString() ?? '',
            'timestamp': parsedDt,
            'hasUnread': item['hasUnread'] == true,
            'conversationType': convType,
            'agreement': agreement,
          });
        }
      }
    }

    conversations.sort((a, b) {
      if (a['hasUnread'] != b['hasUnread']) {
        return (a['hasUnread'] == true) ? -1 : 1;
      }
      final dtA = a['timestamp'] as DateTime?;
      final dtB = b['timestamp'] as DateTime?;

      if (dtA != null && dtB != null) {
        return dtB.compareTo(dtA);
      }
      if (dtA != null && dtB == null) {
        return -1;
      }
      if (dtA == null && dtB != null) {
        return 1;
      }
      return 0;
    });

    if (currentUserId != selfId) throw StateError('Your session changed.');
    return conversations;
  });

  // ==========================================
  // 7. Calendar Events
  // ==========================================

  Future<void> addBandEventAsync(CalendarEvent event) async {
    final bandId = event.bandId;
    if (bandId == null) return;

    final ref = _dbRef('Bands/$bandId/Calendar').push();
    final key = ref.key;
    if (key != null) {
      final updated = CalendarEvent(
        id: key,
        bandId: bandId,
        title: event.title,
        description: event.description,
        type: event.type,
        location: event.location,
        creatorId: currentUserId,
        creatorName: event.creatorName,
        isFinalized: event.isFinalized,
        proposedDates: event.proposedDates,
        date: event.date,
        startTime: event.startTime,
        endTime: event.endTime,
      );
      await _functions.httpsCallable('mutateBandEvent').call({
        'action':'saveCalendar', 'bandId':bandId, 'eventId':key, 'event':updated.toJson()});
    }
  }

  Future<List<CalendarEvent>> getBandEventsAsync(String bandId) async {
    final uid=currentUserId;
    if(uid==null)return [];
    final snapshot = await _dbRef('bandMemberCalendarEvents/$bandId').get();
    if(currentUserId!=uid)return [];
    final List<CalendarEvent> events = [];
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          events.add(CalendarEvent.fromJson(v, k.toString()));
        }
      });
    }
    return events;
  }

  // ==========================================
  // 8. Band Room Chat & Files Integration
  // ==========================================

  Stream<List<Message>> subscribeToBandMessages(String bandId) {
    return _dbRef(
      'bandconversations/$bandId/messages',
    ).orderByChild('Timestamp').onValue.map((event) {
      final List<Message> list = [];
      final data = event.snapshot.value;
      if (data is Map) {
        data.forEach((k, v) {
          if (v is Map) {
            list.add(
              Message.fromJson(v, k.toString(), currentUserId: currentUserId),
            );
          }
        });
        list.sort(
          (a, b) => (a.timestamp ?? DateTime.now()).compareTo(
            b.timestamp ?? DateTime.now(),
          ),
        );
      }
      return list;
    });
  }

  Future<void> sendBandMessageAsync(
    String bandId,
    String text,
    String senderName, {
    String? replyToText,
    String? replyToSenderName,
  }) async {
    final selfId = currentUserId;
    if (selfId == null) return;

    final msgRef = _dbRef('bandconversations/$bandId/messages').push();
    final key = msgRef.key;

    final message = Message(
      id: key,
      senderId: selfId,
      text: text,
      timestamp: DateTime.now(),
      senderName: senderName,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
    );

    await msgRef.set(message.toJson());
  }

  Future<Map<String, Map<String, String>>> getBandFilesAsync(
    String bandId,
  ) async {
    final snapshot = await _dbRef('files/$bandId').get();
    final Map<String, Map<String, String>> files = {};
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          final fileName =
              v['FileName']?.toString() ??
              v['fileName']?.toString() ??
              'Uploaded File';
          final fileUrl =
              v['FileUrl']?.toString() ?? v['fileUrl']?.toString() ?? '';
          final category =
              v['Category']?.toString() ?? v['category']?.toString() ?? '';
          final Map<String, String> fileData = {
            'FileName': fileName,
            'FileUrl': fileUrl,
            'UploadedBy': v['UploadedBy']?.toString() ?? '',
          };
          if (category.isNotEmpty) {
            fileData['Category'] = category;
          }
          files[k.toString()] = fileData;
        } else if (v is String) {
          files[k.toString()] = {'FileName': v, 'FileUrl': ''};
        }
      });
    }
    return files;
  }

  Future<void> addBandFileAsync(
    String bandId,
    String fileName,
    String fileUrl, [
    String? category,
  ]) async {
    final id = _mediaId(fileUrl);
    await _forCurrentSession(() => StorageMediaService().registerBandFile(id, category ?? '', bandId));
  }

  String _mediaId(String handle) {
    if (!RegExp(r'^secure-media:[a-f0-9]{32}$').hasMatch(handle)) {
      throw const PrivateDataAccessException();
    }
    return handle.substring(13);
  }

  Future<Uint8List> downloadBandFileAsync(String fileUrl) =>
      _forCurrentSession(() => StorageMediaService().download(_mediaId(fileUrl)));

  Future<void> removeBandFileAsync(String bandId, String fileId) =>
      _forCurrentSession(() => StorageMediaService().delete(fileId, bandId: bandId));

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase().trim();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> uploadBandFileAsync(
    String bandId,
    Uint8List? bytes,
    String? path,
    String fileName,
  ) async {
    final data = bytes ?? (path != null && !kIsWeb ? await File(path).readAsBytes() : null);
    if (data == null || data.isEmpty) throw ArgumentError('A file is required.');
    return _forCurrentSession(() async {
      final id = await StorageMediaService().upload(kind: 'band', bandId: bandId,
          bytes: data, fileName: fileName, contentType: _getMimeType(fileName));
      return 'secure-media:$id';
    });
  }

  Future<String> uploadMapAudioAsync(String userId, Uint8List? bytes, String? path,
      {String? bandId}) async {
    if (userId != currentUserId) throw const PrivateDataAccessException();
    final data = bytes ?? (path != null && !kIsWeb ? await File(path).readAsBytes() : null);
    if (data == null || data.isEmpty) throw ArgumentError('Audio is required.');
    return _forCurrentSession(() async {
      final id = await StorageMediaService().upload(kind: 'map', bandId: bandId,
          bytes: data, fileName: 'audio.mp3', contentType: 'audio/mpeg');
      return 'secure-media:$id';
    });
  }

  Future<void> savePushTokenAsync(String token) async {
    try {
      final userId = currentUserId;
      if (userId == null) return;
      await _dbRef('users/$userId/info/PushToken').set(token);
      print("[FirebaseService] Push Token saved for user $userId");
    } catch (e) { _rethrowAccessDenied(e);
      print("[FirebaseService] Error saving push token: $e");
    }
  }

  Future<void> initializePushNotifications() async {
    if (kIsWeb) return;
    try {
      print("PUSH: Initializing Push Notification Service...");
      final messaging = FirebaseMessaging.instance;

      // Request permissions
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // On iOS, present alert banner, badge, and sound even when app is in foreground
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        print("PUSH: Permission Granted (${settings.authorizationStatus.name})");
      } else {
        print("PUSH: Permission Not Authorized (${settings.authorizationStatus.name})");
      }

      // Handle token refreshes
      messaging.onTokenRefresh.listen((token) async {
        print("PUSH: TOKEN REFRESHED: $token");
        await savePushTokenAsync(token);
      });

      // On iOS, wait for APNs device token before calling getToken()
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await messaging.getAPNSToken();
        int attempts = 0;
        while (apnsToken == null && attempts < 20) {
          await Future.delayed(const Duration(milliseconds: 500));
          apnsToken = await messaging.getAPNSToken();
          attempts++;
        }
        print("PUSH: iOS APNs Token received: ${apnsToken != null} (attempts: $attempts)");
        if (apnsToken == null) {
          print("PUSH: [WARNING] APNs token is null from iOS. Device may be missing Push Notifications capability or running with free developer team.");
        }
      }

      // Get current token with retry logic for iOS readiness
      String? currentToken;
      try {
        currentToken = await messaging.getToken();
      } catch (e) { _rethrowAccessDenied(e);
        print("PUSH: First getToken attempt failed: $e, retrying in 2 seconds...");
        await Future.delayed(const Duration(seconds: 2));
        try {
          currentToken = await messaging.getToken();
        } catch (e2) { _rethrowAccessDenied(e2);
          print("PUSH: Second getToken attempt failed: $e2");
        }
      }

      if (currentToken != null && currentToken.isNotEmpty) {
        print("PUSH: Token obtained: $currentToken");
        await savePushTokenAsync(currentToken);
      }

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("PUSH: NOTIFICATION RECEIVED: ${message.data}");
      });

      // Opened from background listener
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print("PUSH: NOTIFICATION OPENED: ${message.data}");
        _notificationClickStreamController.add(message.data);
      });

      // Handle terminated app launch from notification
      FirebaseMessaging.instance.getInitialMessage().then((
        RemoteMessage? message,
      ) {
        if (message != null) {
          print(
            "PUSH: TERMINATED APP LAUNCH FROM NOTIFICATION: ${message.data}",
          );
          _notificationClickStreamController.add(message.data);
        }
      });
    } catch (e) { _rethrowAccessDenied(e);
      print("PUSH: ERROR Initializing: $e");
    }
  }

  Future<Map<String, dynamic>> sendTestPushNotificationAsync({
    required String soundType,
    String? customToken,
    bool broadcastToAll = false,
  }) async {
    try {
      final callable = _functions.httpsCallable('sendTestPushNotification');
      final result = await callable.call<Map<String, dynamic>>({
        'soundType': soundType,
        'broadcastToAll': broadcastToAll,
        if (customToken != null && customToken.trim().isNotEmpty)
          'customToken': customToken.trim(),
      });
      return Map<String, dynamic>.from(result.data);
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint("Error calling sendTestPushNotification: $e");
      rethrow;
    }
  }

  // ==========================================
  // 9. Marketplace
  // ==========================================

  Future<List<String>> uploadListingImagesAsync(
    String listingId,
    List<XFile> images,
  ) async {
    List<String> urls = [];
    for (int i = 0; i < images.length; i++) {
      try {
        final image = images[i];
        final ref = FirebaseStorage.instance
            .ref()
            .child('publicMedia/marketplaceImages')
            .child(currentUserId ?? (throw const PrivateDataAccessException()))
            .child(listingId)
            .child('image_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg');

        UploadTask uploadTask;
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          uploadTask = ref.putData(
            bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
        } else {
          uploadTask = ref.putFile(File(image.path));
        }
        final snapshot = await uploadTask;
        final url = await snapshot.ref.getDownloadURL();
        urls.add(url);
      } catch (e) { _rethrowAccessDenied(e);
        print("[FirebaseService] Error uploading image: $e");
        rethrow;
      }
    }
    return urls;
  }

  String generateListingId() {
    return _dbRef('marketplaceListings').push().key!;
  }

  Future<void> saveListingAsync(Listing listing) async {
    final key = listing.id ?? _dbRef('marketplaceListings').push().key;
    if (key != null) {
      final updated = Listing(
        id: key,
        userId: listing.userId ?? currentUserId,
        title: listing.title,
        description: listing.description,
        category: listing.category,
        listingType: listing.listingType,
        marketplaceIntent: listing.marketplaceIntent,
        marketplaceCategory: listing.marketplaceCategory,
        price: listing.price,
        city: listing.city,
        imageUrls: listing.imageUrls,
        status: listing.status,
        createdAt: listing.createdAt,
        updatedAt: listing.updatedAt,
      );
      await _dbRef('marketplaceListings/$key').set(updated.toJson());
    }
  }

  Future<void> updateListingAsync(Listing listing) async {
    if (listing.id == null) return;
    await _dbRef('marketplaceListings/${listing.id}').set(listing.toJson());
  }

  Future<void> updateListingStatusAsync(String listingId, String status) async {
    await _dbRef('marketplaceListings/$listingId/status').set(status);
    await _dbRef(
      'marketplaceListings/$listingId/updatedAt',
    ).set(DateTime.now().millisecondsSinceEpoch);
  }

  Future<List<Listing>> getActiveListingsAsync() async {
    // Limit to latest 100 listings by key (chronological push ID) to optimize queries.
    final query = _dbRef('marketplaceListings').orderByKey().limitToLast(100);

    final snapshot = await query.get();
    final List<Listing> listings = [];
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          final listing = Listing.fromJson(v, k.toString());
          if (listing.status == 'active') {
            listings.add(listing);
          }
        }
      });
    }
    listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return listings;
  }

  Future<List<Listing>> getUserListingsAsync(String userId) async {
    final snapshot = await _dbRef('marketplaceListings').get();
    final List<Listing> listings = [];
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          final listing = Listing.fromJson(v, k.toString());
          if (listing.userId == userId && listing.status != 'deleted') {
            listings.add(listing);
          }
        }
      });
    }
    listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return listings;
  }

  Future<void> reportListingAsync(
    String listingId,
    String reportedByUserId,
    String reason,
  ) async {
    final ref = _dbRef('reportedListings').push();
    await ref.set({
      'listingId': listingId,
      'reportedByUserId': reportedByUserId,
      'reason': reason,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // ==========================================
  // 10. Band Room Events (Spond-like)
  // ==========================================

  static const Set<String> _eventEditableWhitelist = {
    'title',
    'description',
    'eventType',
    'location',
    'startDateTime',
    'endDateTime',
    'additionalNotes',
    'requireResponse',
    'rsvpDeadline',
    'reminderIntervalHours',
    'rehearsals',
    'externalInvitees',
    'substituteAssignments',
    'excludedMemberIds',
    'latitude',
    'longitude',
    'locationPrecision',
    'city',
    'placeId',
    'locationStatus',
    'updatedAt',
  };

  String generateEventId(String bandId) {
    return _dbRef('Bands/$bandId/Events').push().key ??
        DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<String> createBandEventAsync(String bandId, BandEvent event) async {
    final eventId = (event.id != null && event.id!.isNotEmpty)
        ? event.id!
        : generateEventId(bandId);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final created = BandEvent(
      id: eventId,
      title: event.title,
      description: event.description,
      eventType: event.eventType,
      location: event.location,
      startDateTime: event.startDateTime,
      endDateTime: event.endDateTime,
      additionalNotes: event.additionalNotes,
      createdBy: event.createdBy.isNotEmpty
          ? event.createdBy
          : (currentUserId ?? ''),
      createdAt: event.createdAt != 0 ? event.createdAt : timestamp,
      updatedAt: timestamp,
      requireResponse: event.requireResponse,
      responses: event.responses,
      rsvpDeadline: event.rsvpDeadline,
      reminderIntervalHours: event.reminderIntervalHours,
      temporaryRoomId: event.temporaryRoomId,
      parentEventId: event.parentEventId,
      subEventSequence: event.subEventSequence,
      rehearsals: event.rehearsals,
      scheduleResponses: event.scheduleResponses,
      externalInvitees: event.externalInvitees,
      substituteAssignments: event.substituteAssignments,
      excludedMemberIds: event.excludedMemberIds,
      latitude: event.latitude,
      longitude: event.longitude,
      locationPrecision: event.locationPrecision,
      city: event.city,
      placeId: event.placeId,
      locationStatus: event.locationStatus,
    );
    await _functions.httpsCallable('mutateBandEvent').call({
      'action':'save','bandId':bandId,'eventId':eventId,'event':created.toJson(),
    });
    return eventId;
  }

  Future<void> updateBandEventAsync(
    String bandId,
    String eventId,
    Map<String, dynamic> editableFields,
  ) async {
    final Map<String, dynamic> updateMap = {};
    for (final key in _eventEditableWhitelist) {
      if (editableFields.containsKey(key)) {
        updateMap[key] = editableFields[key];
      }
    }
    updateMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _functions.httpsCallable('mutateBandEvent').call({
      'action':'save','bandId':bandId,'eventId':eventId,'event':updateMap,
    });
  }

  Future<String> saveBandEventAsync(String bandId, BandEvent event) async {
    if (event.id == null || event.id!.isEmpty) {
      return await createBandEventAsync(bandId, event);
    } else {
      await updateBandEventAsync(bandId, event.id!, {
        'title': event.title,
        'description': event.description,
        'eventType': event.eventType,
        'location': event.location,
        'startDateTime': event.startDateTime,
        'endDateTime': event.endDateTime,
        'additionalNotes': event.additionalNotes,
        'requireResponse': event.requireResponse,
        'rsvpDeadline': event.rsvpDeadline,
        'reminderIntervalHours': event.reminderIntervalHours,
        'rehearsals': event.rehearsals.map((r) => r.toJson()).toList(),
        'externalInvitees': event.externalInvitees.map((k, v) => MapEntry(k, v.toJson())),
        'substituteAssignments': event.substituteAssignments.map((k, v) => MapEntry(k, v.toJson())),
        'excludedMemberIds': event.excludedMemberIds,
        if (event.latitude != null) 'latitude': event.latitude,
        if (event.longitude != null) 'longitude': event.longitude,
        'locationPrecision': event.locationPrecision,
        if (event.city != null && event.city!.isNotEmpty) 'city': event.city,
        if (event.placeId != null && event.placeId!.isNotEmpty) 'placeId': event.placeId,
        if (event.locationStatus != null && event.locationStatus!.isNotEmpty) 'locationStatus': event.locationStatus,
      });
      return event.id!;
    }
  }

  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    final uid = currentUserId;
    if (uid == null) return [];
    final snapshots = await Future.wait([
      _dbRef('bandMemberEvents/$bandId').get(),
      _dbRef('userEventReadModels/$uid/$bandId').get(),
    ]);
    if (currentUserId != uid) return [];
    final snapshot = snapshots[0];
    final own = snapshots[1].value is Map ? snapshots[1].value as Map : const {};
    final List<BandEvent> list = [];
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          list.add(_eventFromReadModel(v, own[k], k.toString()));
        }
      });
    }
    return list;
  }

  BandEvent _eventFromReadModel(Map event, Object? own, String eventId) {
    final merged = Map<dynamic, dynamic>.from(event);
    if (own is Map) {
      for (final field in [
        'Responses','ScheduleResponses','externalInvitees','excludedMemberIds',
      ]) {
        if (own.containsKey(field)) merged[field] = own[field];
      }
    }
    return BandEvent.fromJson(merged, eventId);
  }

  Future<bool> canManageBandEventAsync(String bandId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    final snapshot = await _dbRef('Bands/$bandId/Members_band/$uid').get();
    if (currentUserId != uid || snapshot.value is! Map) return false;
    return BandMembershipPolicy.canManageMember(
        BandMember.fromJson(snapshot.value as Map, uid));
  }

  Future<BandEvent?> getManagerBandEventOnceAsync(String bandId, String eventId) async {
    final uid = currentUserId;
    if (uid == null || !await canManageBandEventAsync(bandId)) return null;
    final snapshot = await _dbRef('bandManagerEvents/$bandId/$eventId').get();
    if (currentUserId != uid || snapshot.value is! Map) return null;
    return BandEvent.fromJson(snapshot.value as Map, eventId);
  }

  Future<List<BandEvent>> getManagerBandEventsListAsync(String bandId) async {
    final uid = currentUserId;
    if (uid == null || !await canManageBandEventAsync(bandId)) return [];
    final snapshot = await _dbRef('bandManagerEvents/$bandId').get();
    if (currentUserId != uid || snapshot.value is! Map) return [];
    final result = <BandEvent>[];
    (snapshot.value as Map).forEach((id,value) {
      if (value is Map) result.add(BandEvent.fromJson(value,id.toString()));
    });
    return result;
  }

  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) {
    final uid = currentUserId;
    if (uid == null) return Stream.value(null);
    return _watchBandEvent(bandId,eventId,uid);
  }

  Stream<BandEvent?> _watchBandEvent(String bandId,String eventId,String uid) async* {
    final member = await _dbRef('Bands/$bandId/Members_band/$uid').get();
    if (currentUserId != uid) return;
    final active = member.value is Map && BandMembershipPolicy.isValidStatus(
        (member.value as Map)['Status'] ?? (member.value as Map)['status']);
    if (!active) {
      yield* _dbRef('userEventReadModels/$uid/$bandId/$eventId').onValue.map((event) {
        if (currentUserId != uid) return null;
        final data=event.snapshot.value;
        return data is Map ? BandEvent.fromJson(data,eventId) : null;
      });
      return;
    }
    late StreamController<BandEvent?> controller;
    StreamSubscription<DatabaseEvent>? memberSub,userSub,authoritySub;
    StreamSubscription<User?>? authSub;
    Object? base,own;
    bool baseReady=false;
    bool activeMember=true;
    void emit() {
      if(controller.isClosed)return;
      if(currentUserId!=uid || !activeMember){controller.add(null);return;}
      if(!baseReady)return;
      controller.add(base is Map ? _eventFromReadModel(base as Map,own,eventId) : null);
    }
    controller=StreamController<BandEvent?>(onListen:(){
      authoritySub=_dbRef('Bands/$bandId/Members_band/$uid').onValue.listen((event){
        final value=event.snapshot.value;
        activeMember=currentUserId==uid && value is Map &&
            BandMembershipPolicy.isValidStatus(value['Status'] ?? value['status']);
        if(!activeMember)emit();
      },onError:(Object error){
        activeMember=false;
        if(!controller.isClosed){controller.add(null);controller.addError(error);}
      });
      memberSub=_dbRef('bandMemberEvents/$bandId/$eventId').onValue.listen((event){
        baseReady=true;base=event.snapshot.value;emit();
      },onError:(Object error){controller.add(null);controller.addError(error);});
      userSub=_dbRef('userEventReadModels/$uid/$bandId/$eventId').onValue.listen((event){
        own=event.snapshot.value;emit();
      },onError:(Object error){controller.add(null);controller.addError(error);});
      authSub=_auth.authStateChanges().listen((user){
        if(user?.uid!=uid && !controller.isClosed)controller.add(null);
      });
    },onCancel:() async {
      await memberSub?.cancel();await userSub?.cancel();await authoritySub?.cancel();
      await authSub?.cancel();
    });
    yield* controller.stream;
  }

  Stream<BandEvent?> subscribeToManagerBandEvent(String bandId,String eventId) async* {
    final uid=currentUserId;
    if(uid==null || !await canManageBandEventAsync(bandId)) {
      yield null;return;
    }
    late StreamController<BandEvent?> controller;
    StreamSubscription<DatabaseEvent>? authoritySub,eventSub;
    StreamSubscription<User?>? authSub;
    bool managerAuthorized=false;
    controller=StreamController<BandEvent?>(onListen:(){
      authoritySub=_dbRef('Bands/$bandId/Members_band/$uid').onValue.listen((event){
        final value=event.snapshot.value;
        final authorized=currentUserId==uid && value is Map &&
            BandMembershipPolicy.canManageMember(BandMember.fromJson(value,uid));
        managerAuthorized=authorized;
        if(!authorized){
          eventSub?.cancel();eventSub=null;
          if(!controller.isClosed)controller.add(null);
          return;
        }
        eventSub ??= _dbRef('bandManagerEvents/$bandId/$eventId').onValue.listen((event){
          if(controller.isClosed){
            return;
          }
          final data=event.snapshot.value;
          controller.add(managerAuthorized && currentUserId==uid && data is Map
              ? BandEvent.fromJson(data,eventId) : null);
        },onError:(Object error){
          if(!controller.isClosed){controller.add(null);controller.addError(error);}
        });
      },onError:(Object error){
        if(!controller.isClosed){controller.add(null);controller.addError(error);}
      });
      authSub=_auth.authStateChanges().listen((user){
        if(user?.uid!=uid && !controller.isClosed)controller.add(null);
      });
    },onCancel:() async {
      await authoritySub?.cancel();await eventSub?.cancel();await authSub?.cancel();
    });
    yield* controller.stream;
  }

  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    final uid=currentUserId;
    if(uid==null)return Stream.value([]);
    late StreamController<List<BandEvent>> controller;
    StreamSubscription<DatabaseEvent>? memberSub,userSub,authoritySub;
    StreamSubscription<User?>? authSub;
    Object? base,own;
    bool activeMember=false;
    void emit(){
      if(controller.isClosed)return;
      if(currentUserId!=uid || !activeMember){controller.add([]);return;}
      final result=<BandEvent>[];
      final ownMap=own is Map ? own as Map : const {};
      if (base is Map) {
        (base as Map).forEach((id, value) {
          if (value is Map) {
            result.add(_eventFromReadModel(value, ownMap[id], id.toString()));
          }
        });
      }
      controller.add(result);
    }
    controller=StreamController<List<BandEvent>>(onListen:(){
      authoritySub=_dbRef('Bands/$bandId/Members_band/$uid').onValue.listen((event){
        final value=event.snapshot.value;
        activeMember=currentUserId==uid && value is Map &&
            BandMembershipPolicy.isValidStatus(value['Status'] ?? value['status']);
        emit();
      },onError:(Object error){
        activeMember=false;
        if(!controller.isClosed){controller.add([]);controller.addError(error);}
      });
      memberSub=_dbRef('bandMemberEvents/$bandId').onValue.listen((event){
        base=event.snapshot.value;emit();
      },onError:(Object error){controller.add([]);controller.addError(error);});
      userSub=_dbRef('userEventReadModels/$uid/$bandId').onValue.listen((event){
        own=event.snapshot.value;emit();
      },onError:(Object error){controller.add([]);controller.addError(error);});
      authSub=_auth.authStateChanges().listen((user){
        if(user?.uid!=uid && !controller.isClosed)controller.add([]);
      });
    },onCancel:() async {
      await memberSub?.cancel();await userSub?.cancel();await authoritySub?.cancel();
      await authSub?.cancel();
    });
    return controller.stream;
  }

  Future<Map<String, SubstituteAssignment>> getSubstituteAssignmentsAsync(
    String bandId,
    String eventId,
  ) async {
    try {
      if (!await canManageBandEventAsync(bandId)) return {};
      final snap = await _dbRef('bandManagerEvents/$bandId/$eventId/substituteAssignments').get();
      final Map<String, SubstituteAssignment> assignments = {};
      if (snap.exists && snap.value is Map) {
        (snap.value as Map).forEach((k, v) {
          if (v is Map) {
            assignments[k.toString()] = SubstituteAssignment.fromJson(v, k.toString());
          }
        });
      }
      return assignments;
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Error getting substitute assignments: $e');
      return {};
    }
  }

  Future<void> updateEventResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    await _dbRef('Bands/$bandId/Events/$eventId/Responses/$userId').set({
      'status': status,
      'timestamp': timestamp,
      if (comment != null) 'comment': comment,
    });
  }

  Future<void> updateScheduleItemResponseAsync(
    String bandId,
    String eventId,
    String scheduleItemId,
    String userId,
    String status, {
    String? uncertainReason,
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    await _dbRef(
      'Bands/$bandId/Events/$eventId/ScheduleResponses/$scheduleItemId/$userId',
    ).set({
      'status': status,
      'timestamp': timestamp,
      if (uncertainReason != null) 'uncertainReason': uncertainReason,
    });
  }

  Future<void> deleteBandEventAsync(String bandId, String eventId) async {
    await _functions.httpsCallable('mutateBandEvent').call({
      'action':'delete','bandId':bandId,'eventId':eventId,
    });
  }

  Future<void> addBandMemberAsync(
    String bandId,
    String userId,
    String role,
    String nickname,
  ) => _submitMembershipMutation({
    'action': 'add',
    'bandId': bandId,
    'userId': userId,
    'role': role,
    'nickname': nickname,
    'operationId': _membershipOperationId(),
  });

  Future<void> removeBandMemberAsync(String bandId, String userId) =>
      _submitMembershipMutation({
        'action': userId == currentUserId ? 'leave' : 'remove',
        'bandId': bandId,
        'userId': userId,
        'operationId': _membershipOperationId(),
      });

  Future<void> leaveBandAsync(String bandId) => _submitMembershipMutation({
    'action': 'leave',
    'bandId': bandId,
    'operationId': _membershipOperationId(),
  });

  Future<void> updateBandMemberRoleAsync(
    String bandId,
    String userId,
    String newRole,
  ) => _submitMembershipMutation({
    'action': newRole.trim().toLowerCase() == 'leader' ? 'transfer' : 'role',
    'bandId': bandId,
    'userId': userId,
    'role': newRole,
    'operationId': _membershipOperationId(),
  });

  Future<void> updateBandMemberStatusAsync(
    String bandId,
    String userId,
    String newStatus,
  ) => _submitMembershipMutation({
    'action': 'status',
    'bandId': bandId,
    'userId': userId,
    'status': newStatus,
    'operationId': _membershipOperationId(),
  });

  Future<void> postGigsNewsAsync(
    String bandId,
    Map<String, dynamic> data,
  ) async {
    final ref = _dbRef('Bands/$bandId/GigsNews').push();
    final updatedData = {
      ...data,
      'id': ref.key,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await ref.set(updatedData);
  }

  Stream<List<Map<String, dynamic>>> subscribeToGigsNews(String bandId) {
    return _dbRef('Bands/$bandId/GigsNews').onValue.map((event) {
      final List<Map<String, dynamic>> list = [];
      final data = event.snapshot.value;
      if (data is Map) {
        data.forEach((k, v) {
          if (v is Map) {
            final map = Map<String, dynamic>.from(v);
            map['id'] = k.toString();
            list.add(map);
          }
        });
      }
      list.sort(
        (a, b) => (b['timestamp'] as num? ?? 0).compareTo(
          a['timestamp'] as num? ?? 0,
        ),
      );
      return list;
    });
  }

  Future<void> deleteGigsNewsAsync(String bandId, String postId) async {
    await _dbRef('Bands/$bandId/GigsNews/$postId').remove();
  }

  // ==========================================
  // 12. Button Click Tracking Metrics
  // ==========================================

  Future<Map<String, int>> getButtonClicksAsync(String userId) async {
    final snapshot = await _dbRef('users/$userId/metrics/buttonClicks').get();
    if (!snapshot.exists || snapshot.value == null) {
      return {};
    }
    final Map<String, int> result = {};
    if (snapshot.value is Map) {
      final map = snapshot.value as Map;
      map.forEach((key, value) {
        if (value is int) {
          result[key.toString()] = value;
        } else if (value is num) {
          result[key.toString()] = value.toInt();
        }
      });
    }
    return result;
  }

  Future<void> saveButtonClickAsync(
    String userId,
    String buttonId,
    int count,
  ) async {
    await _dbRef('users/$userId/metrics/buttonClicks/$buttonId').set(count);
  }

  Future<BandEvent?> getBandEventOnceAsync(
    String bandId,
    String eventId,
  ) async {
    final uid=currentUserId;
    if(uid==null)return null;
    // Read the exact own projection first. A denial is surfaced and never
    // retried against canonical Event data.
    final own=await _dbRef('userEventReadModels/$uid/$bandId/$eventId').get();
    if(currentUserId!=uid)return null;
    if(own.value is Map)return BandEvent.fromJson(own.value as Map,eventId);
    final member=await _dbRef('bandMemberEvents/$bandId/$eventId').get();
    if(currentUserId!=uid)return null;
    return member.value is Map ? BandEvent.fromJson(member.value as Map,eventId) : null;
  }

  Future<void> addExternalInviteesToEventAsync(
    String bandId,
    String eventId,
    List<String> userIds, {
    String? subRequestId,
  }) async {
    if(subRequestId!=null)throw StateError('Staffing invitations use the SubRequest callable.');
    await _functions.httpsCallable('mutateBandEvent').call({
      'action':'addInvitees','bandId':bandId,'eventId':eventId,'userIds':userIds,
    });
  }

  Future<void> updateExternalInviteeResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {
    try {
      if(currentUserId!=userId)throw StateError('Your session changed.');
      await _functions.httpsCallable('mutateBandEvent').call({
        'action':'inviteResponse','bandId':bandId,'eventId':eventId,
        'status':status,'comment':comment,
      });
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] updateExternalInviteeResponseAsync notice: $e');
    }
  }

  Future<void> lockBandEventAsync(String bandId, String eventId) async {
    await _functions.httpsCallable('mutateBandEvent').call({
      'action':'lock','bandId':bandId,'eventId':eventId,
    });
  }

  Future<void> unlockBandEventAsync(String bandId, String eventId) async {
    await _functions.httpsCallable('mutateBandEvent').call({
      'action':'unlock','bandId':bandId,'eventId':eventId,
    });
  }

  Future<String?> getUserBandRoleAsync(String bandId, String userId) async {
    final snapshot = await _dbRef(
      'Bands/$bandId/Members_band/$userId/Role',
    ).get();
    if (snapshot.exists) {
      return snapshot.value?.toString();
    }
    return null;
  }

  Future<List<Band>> getAllBandsAsync() => getPublicBandProfilesAsync();

  // ==========================================
  // 10. Collabs MVP Methods
  // ==========================================

  // Studios
  Future<void> saveCollabStudioAsync(CollabStudio studio) async {
    final id = studio.id ?? _dbRef('Collabs/Studios').push().key;
    if (id == null) return;
    final updatedStudio = CollabStudio(
      id: id,
      name: studio.name,
      description: studio.description,
      location: studio.location,
      genres: studio.genres,
      facilities: studio.facilities,
      contactInfo: studio.contactInfo,
      creatorId: studio.creatorId,
      createdAt: studio.createdAt == 0
          ? DateTime.now().millisecondsSinceEpoch
          : studio.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _dbRef('Collabs/Studios/$id').set(updatedStudio.toJson());
  }

  Future<void> deleteCollabStudioAsync(String studioId) async {
    await _dbRef('Collabs/Studios/$studioId').remove();
  }

  Future<List<CollabStudio>> getCollabStudiosAsync() async {
    final snapshot = await _dbRef('Collabs/Studios').get();
    final List<CollabStudio> studios = [];
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map;
      data.forEach((k, v) {
        if (v is Map) {
          studios.add(CollabStudio.fromJson(v, k.toString()));
        }
      });
    }
    return studios;
  }

  // Sessions
  Future<String> createCollabSessionAsync(CollabSession session) async {
    final id = session.id ?? _dbRef('Collabs/Sessions').push().key;
    if (id == null) throw Exception('Failed to generate session ID');
    final now = DateTime.now().millisecondsSinceEpoch;
    final newSession = CollabSession(
      id: id,
      title: session.title,
      description: session.description,
      sessionType: session.sessionType,
      sessionCategory: session.sessionCategory,
      isDateFlexible: session.isDateFlexible,
      startDateTime: session.startDateTime,
      endDateTime: session.endDateTime,
      location: session.location,
      genres: session.genres,
      lookingForRoles: session.lookingForRoles,
      lookingForInstruments: session.lookingForInstruments,
      creatorId: session.creatorId,
      createdAt: session.createdAt == 0 ? now : session.createdAt,
      updatedAt: now,
      status: session.status,
      requireResponse: session.requireResponse,
      rsvpDeadline: session.rsvpDeadline,
      reminderIntervalHours: session.reminderIntervalHours,
      responses: session.responses,
      parentSessionId: session.parentSessionId,
      subSessionSequence: session.subSessionSequence,
      sessionChatId: session.sessionChatId,
    );
    await _dbRef('Collabs/Sessions/$id').set(newSession.toJson()..remove('Responses'));
    return id;
  }

  Future<void> updateCollabSessionAsync(
    String sessionId,
    CollabSession updatedSession,
  ) async {
    final ref = _dbRef('Collabs/Sessions/$sessionId');

    final Map<String, dynamic> updates = {
      'Title': updatedSession.title,
      'Description': updatedSession.description,
      'SessionType': updatedSession.sessionType,
      'SessionCategory': updatedSession.sessionCategory,
      'IsDateFlexible': updatedSession.isDateFlexible,
      'StartDateTime': updatedSession.startDateTime,
      'EndDateTime': updatedSession.endDateTime,
      'Location': updatedSession.location,
      'Genres': updatedSession.genres,
      'RequireResponse': updatedSession.requireResponse,
      'RsvpDeadline': updatedSession.rsvpDeadline,
      'ReminderIntervalHours': updatedSession.reminderIntervalHours,
      'UpdatedAt': DateTime.now().millisecondsSinceEpoch,
      'Status': updatedSession.status,
    };

    if (updatedSession.lookingForRoles.isNotEmpty) {
      updates['LookingForRoles'] = updatedSession.lookingForRoles;
    }
    if (updatedSession.lookingForInstruments.isNotEmpty) {
      updates['LookingForInstruments'] = updatedSession.lookingForInstruments;
    }

    await ref.update(updates);
  }

  Future<void> saveCollabSessionAsync(CollabSession session) async {
    if (session.id == null || session.id!.isEmpty) {
      await createCollabSessionAsync(session);
    } else {
      await updateCollabSessionAsync(session.id!, session);
    }
  }

  Future<List<String>> createCollabSessionGroupAsync(
    List<CollabSession> sessions,
  ) async {
    if (sessions.isEmpty) return [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final parentId = sessions.first.id ?? _dbRef('Collabs/Sessions').push().key!;
    final List<String> sessionIds = [];
    final Map<String, dynamic> multiLocationMap = {};

    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final id = (i == 0) ? parentId : (_dbRef('Collabs/Sessions').push().key!);
      sessionIds.add(id);

      final fullSession = CollabSession(
        id: id,
        title: s.title,
        description: s.description,
        sessionType: s.sessionType,
        sessionCategory: s.sessionCategory,
        isDateFlexible: s.isDateFlexible,
        startDateTime: s.startDateTime,
        endDateTime: s.endDateTime,
        location: s.location,
        genres: s.genres,
        lookingForRoles: s.lookingForRoles,
        lookingForInstruments: s.lookingForInstruments,
        creatorId: s.creatorId,
        createdAt: s.createdAt == 0 ? now : s.createdAt,
        updatedAt: now,
        status: s.status,
        requireResponse: s.requireResponse,
        rsvpDeadline: s.rsvpDeadline,
        reminderIntervalHours: s.reminderIntervalHours,
        responses: s.responses,
        parentSessionId: (sessions.length > 1) ? parentId : null,
        subSessionSequence: (sessions.length > 1) ? i + 1 : null,
        sessionChatId: s.sessionChatId,
      );

      multiLocationMap['$id'] = fullSession.toJson()..remove('Responses');
    }

    await _dbRef('Collabs/Sessions').update(multiLocationMap);
    return sessionIds;
  }

  Future<void> deleteCollabSessionAsync(String sessionId) async {
    await _dbRef().update({
      'Collabs/Sessions/$sessionId': null,
      'Collabs/Applications/$sessionId': null,
      'Collabs/SessionResponses/$sessionId': null,
    });
  }

  Future<List<CollabSession>> getCollabSessionsAsync() async {
    final snapshot = await _dbRef('Collabs/Sessions').get();
    final List<CollabSession> sessions = [];
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map;
      data.forEach((k, v) {
        if (v is Map) {
          sessions.add(CollabSession.fromJson(v, k.toString()));
        }
      });
    }
    return sessions;
  }

  // Applications
  Future<void> applyToCollabSessionAsync(
    String sessionId,
    String userId,
    CollabSessionApplication application,
  ) async {
    await _dbRef(
      'Collabs/Applications/$sessionId/$userId',
    ).set(application.toJson());
  }

  Future<List<CollabSessionApplication>> getCollabSessionApplicationsAsync(
    String sessionId,
  ) => _forCurrentSession(() async {
    final snapshot = await _dbRef('Collabs/Applications/$sessionId').get();
    final List<CollabSessionApplication> apps = [];
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map;
      data.forEach((k, v) {
        if (v is Map) {
          apps.add(CollabSessionApplication.fromJson(v, k.toString()));
        }
      });
    }
    return apps;
  });

  Future<CollabSessionApplication?> getCollabSessionApplicationAsync(
    String sessionId,
    String applicantId,
  ) => _forCurrentSession(() async {
    final snapshot = await _dbRef(
      'Collabs/Applications/$sessionId/$applicantId',
    ).get();
    if (snapshot.exists && snapshot.value is Map) {
      return CollabSessionApplication.fromJson(
        snapshot.value as Map,
        applicantId,
      );
    }
    return null;
  });

  Future<void> updateCollabApplicationStatusAsync(
    String sessionId,
    String applicantId,
    String status,
  ) async {
    await _functions.httpsCallable('updateSessionApplicationStatus').call({
      'sessionId': sessionId, 'applicantId': applicantId, 'status': status,
    });
  }

  Future<void> cancelCollabSessionApplicationAsync(
    String sessionId,
    String applicantId,
  ) async {
    final app = await getCollabSessionApplicationAsync(sessionId, applicantId);
    if (app != null && app.status == 'pending') {
      await _dbRef('Collabs/Applications/$sessionId/$applicantId').remove();
    }
  }

  // Session RSVP Responses
  Future<void> submitSessionRsvpResponseAsync({
    required String sessionId,
    required String userId,
    required String status,
    String? comment,
    String? uncertainReason,
  }) async {
    final response = EventResponse(
      status: status,
      timestamp: DateTime.now(),
      comment: comment,
      uncertainReason: uncertainReason,
    );

    // Direct write to /Collabs/SessionResponses/$sessionId/$userId governed by RTDB security rules
    await _dbRef('Collabs/SessionResponses/$sessionId/$userId')
        .set(response.toJson());
  }

  // Session Chat
  Future<String> createSessionChatRoomAsync({
    required String sessionId,
    required String sessionTitle,
    required String createdBy,
  }) async {
    final result = await _functions.httpsCallable('createSessionConversation').call({
      'sessionId': sessionId, 'sessionTitle': sessionTitle,
    });
    final id = result.data['conversationId']?.toString() ?? '';
    if (id.isEmpty) throw StateError('The session chat could not be opened.');
    return id;
  }

  Future<void> addParticipantToSessionChatAsync({
    required String sessionId,
    required String chatId,
    required String participantId,
  }) async {
    await _functions.httpsCallable('updateSessionApplicationStatus').call({
      'sessionId': sessionId, 'applicantId': participantId, 'status': 'accepted',
    });
  }

  // ==========================================
  // Temporary Event Rooms
  // ==========================================

  Future<String> createTemporaryEventRoomAsync({
    required String bandId,
    required String eventId,
    required String roomName,
    required String createdBy,
    List<String> initialMembers = const [],
  }) async {
    final ref = _dbRef('Bands/$bandId/eventRooms').push();
    final roomId = ref.key ?? 'room_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final Map<String, String> membersMap = {createdBy: 'leader'};
    for (final memberId in initialMembers) {
      if (memberId.isNotEmpty) {
        membersMap[memberId] = 'member';
      }
    }

    final eventRoom = EventRoom(
      roomId: roomId,
      eventId: eventId,
      bandId: bandId,
      name: roomName,
      createdAt: timestamp,
      createdBy: createdBy,
      isTemporary: true,
      isClosed: false,
      members: membersMap,
    );

    try {
      await ref.set(eventRoom.toJson());
      await _functions.httpsCallable('mutateBandEvent').call({
        'action':'setRoom','bandId':bandId,'eventId':eventId,'roomId':roomId,
      });
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] createTemporaryEventRoomAsync notice: $e');
    }
    return roomId;
  }

  Stream<List<EventRoom>> subscribeToBandEventRooms(String bandId) {
    return _dbRef('Bands/$bandId/eventRooms').onValue.map((event) {
      final List<EventRoom> rooms = [];
      final data = event.snapshot.value;
      if (data is Map) {
        data.forEach((k, v) {
          if (v is Map) {
            rooms.add(EventRoom.fromJson(v, k.toString()));
          }
        });
      }
      rooms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rooms;
    });
  }

  Future<void> addMemberToEventRoomAsync(
    String bandId,
    String roomId,
    String userId, [
    String role = 'member',
  ]) async {
    try {
      await _dbRef('Bands/$bandId/eventRooms/$roomId/members/$userId').set(role);
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] addMemberToEventRoomAsync notice: $e');
    }
  }

  Future<void> closeOrDeleteEventRoomAsync(
    String bandId,
    String roomId,
    bool deleteRoom,
  ) async {
    try {
      if (deleteRoom) {
        await _dbRef('Bands/$bandId/eventRooms/$roomId').remove();
      } else {
        await _dbRef('Bands/$bandId/eventRooms/$roomId/isClosed').set(true);
      }
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] closeOrDeleteEventRoomAsync notice: $e');
    }
  }

  // ==========================================
  // God Mode / Admin Reminder Triggers
  // ==========================================

  Future<Map<String, dynamic>> triggerEventReminderAsync(
    String bandId,
    String eventId,
    String reminderType, // '24h', '48h', '72h', 'last'
  ) async {
    try {
      final callable = _functions.httpsCallable('triggerEventReminder');
      final result = await callable.call({
        'bandId': bandId,
        'eventId': eventId,
        'reminderType': reminderType,
      });

      if (result.data is Map) {
        return Map<String, dynamic>.from(result.data as Map);
      }
      return {'status': 'completed', 'successCount': 0};
    } on FirebaseFunctionsException catch (e) { _rethrowAccessDenied(e);
      return {
        'status': 'error',
        'code': e.code,
        'message': e.message ?? e.toString(),
        'successCount': 0,
      };
    } catch (e) { _rethrowAccessDenied(e);
      return {
        'status': 'error',
        'code': 'unknown',
        'message': e.toString(),
        'successCount': 0,
      };
    }
  }

  Future<void> saveSubRequestPublicationAsync(String publicationId, Map<String, dynamic> manifest) async {
    await _dbRef('subRequestPublications/$publicationId').set(manifest);
  }

  // ==========================================
  // Account & Band Deletion
  // ==========================================

  Future<void> deleteUserAccountAsync() async {
    final uid = currentUserId;
    if (uid == null) {
      throw Exception('User is not logged in.');
    }

    await _functions.httpsCallable('deleteUserAccount').call();

    // The server deletes the authenticated caller; never delete whichever client
    // account happens to be current after this asynchronous operation.
  }

  Future<void> deleteBandAsync(String bandId) async {
    if (currentUserId == null) throw StateError('Please sign in first.');
    await _functions.httpsCallable('deleteBand').call({'bandId': bandId});
  }

  // ==========================================

  // Public Calendar Events
  // ==========================================

  Future<String> savePublicCalendarEventAsync(PublicCalendarEvent event) async {
    final eventId = (event.id.isNotEmpty && !event.id.startsWith('mock_'))
        ? event.id
        : (_dbRef('PublicEvents').push().key ?? 'event_${DateTime.now().millisecondsSinceEpoch}');

    final updatedEvent = event.copyWith(
      id: eventId,
      createdBy: (event.createdBy != null && event.createdBy!.isNotEmpty)
          ? event.createdBy
          : currentUserId,
      createdAt: event.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      isMock: false,
    );

    final json = updatedEvent.toJson();

    // 1. Save under user's node first (guaranteed permitted by users/$userId rules)
    final uid = currentUserId;
    if (uid != null) {
      try {
        await _dbRef('users/$uid/PublicEvents/$eventId').set(json);
      } catch (e) { _rethrowAccessDenied(e);
        debugPrint('[FirebaseService] Could not save users/$uid/PublicEvents: $e');
      }
    }

    // 2. Save under global /PublicEvents
    try {
      await _dbRef('PublicEvents/$eventId').set(json);
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Global PublicEvents write notice: $e');
      if (uid == null) {
        rethrow;
      }
    }

    return eventId;
  }

  Future<List<PublicCalendarEvent>> getPublicCalendarEventsAsync() async {
    final Map<String, PublicCalendarEvent> eventsMap = {};

    // 1. Try global PublicEvents
    try {
      final snapshot = await _dbRef('PublicEvents').get();
      if (snapshot.exists && snapshot.value is Map) {
        (snapshot.value as Map).forEach((key, value) {
          if (value is Map) {
            try {
              eventsMap[key.toString()] = PublicCalendarEvent.fromJson(value, key.toString());
            } catch (e) { _rethrowAccessDenied(e);
              debugPrint('Error parsing PublicCalendarEvent ($key): $e');
            }
          }
        });
      }
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('Notice: could not read global PublicEvents: $e');
    }

    // 2. Merge user's personal PublicEvents if available
    final uid = currentUserId;
    if (uid != null) {
      try {
        final userSnap = await _dbRef('users/$uid/PublicEvents').get();
        if (userSnap.exists && userSnap.value is Map) {
          (userSnap.value as Map).forEach((key, value) {
            if (value is Map) {
              try {
                eventsMap[key.toString()] = PublicCalendarEvent.fromJson(value, key.toString());
              } catch (accessError) { _rethrowAccessDenied(accessError);}
            }
          });
        }
      } catch (accessError) { _rethrowAccessDenied(accessError);}
    }

    return eventsMap.values.toList();
  }

  Future<void> deletePublicCalendarEventAsync(String eventId) async {
    // 1. Remove from global PublicEvents
    try {
      await _dbRef('PublicEvents/$eventId').remove();
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint('[FirebaseService] Notice: could not remove global PublicEvents/$eventId: $e');
    }

    // 2. Remove from user's personal PublicEvents
    final uid = currentUserId;
    if (uid != null) {
      try {
        await _dbRef('users/$uid/PublicEvents/$eventId').remove();
      } catch (e) { _rethrowAccessDenied(e);
        debugPrint('[FirebaseService] Notice: could not remove users/$uid/PublicEvents/$eventId: $e');
      }
    }
  }

  Future<String> uploadPublicEventCoverImageAsync(
    XFile image, [
    String? eventId,
  ]) async {
    try {
      final id = eventId ?? 'event_${DateTime.now().millisecondsSinceEpoch}';
      final ref = FirebaseStorage.instance
          .ref()
          .child('publicMedia/publicEventImages')
          .child(currentUserId ?? (throw const PrivateDataAccessException()))
          .child(id)
          .child('cover_${DateTime.now().millisecondsSinceEpoch}.jpg');

      UploadTask uploadTask;
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        uploadTask = ref.putData(bytes, metadata);
      } else {
        uploadTask = ref.putFile(File(image.path), metadata);
      }

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      return url;
    } catch (e) { _rethrowAccessDenied(e);
      debugPrint("Error uploading public event cover image: $e");
      rethrow;
    }
  }
}

