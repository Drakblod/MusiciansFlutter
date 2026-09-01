import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../models/band.dart';
import '../models/sub_request.dart';
import '../models/message.dart';
import '../models/calendar_event.dart';
import '../models/agreement.dart';
import '../models/listing.dart';
import '../models/band_event.dart';
import '../models/event_room.dart';
import '../models/collab_session.dart';
import '../models/collab_studio.dart';
import '../utils/date_parser.dart';

class FirebaseService {
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
        email: trimmedEmail,
        location: null,
        level: level ?? 'C = INTERMEDIATE',
        about: 'Hey! I am a musician ready to play.',
        instruments: [userType],
      );

      await saveUserProfileAsync(trimmedUid, profile);
    } catch (e) {
      try {
        await newAuthUser?.delete();
      } catch (deleteError) {
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

    final updates = <String, dynamic>{};
    final allowedInfoKeys = {
      'DisplayName',
      'Email',
      'Level',
      'Location',
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

    final fields = <String, dynamic>{
      'DisplayName': profile.displayName,
      'Email': profile.email,
      'Level': profile.level,
      'Location': profile.location,
      'About': profile.about,
      'Instruments': profile.instruments,
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
    await updateUserProfileFields(trimmedUid, fields);
  }

  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    final targetId = userId ?? currentUserId;
    if (targetId == null) return null;

    final snapshot = await _dbRef('users/$targetId').get();
    if (snapshot.exists && snapshot.value is Map) {
      final rootMap = snapshot.value as Map;
      final infoMap = rootMap['info'] is Map ? rootMap['info'] as Map : {};
      return UserProfile(
        userId: targetId,
        userType:
            rootMap['UserType']?.toString() ?? infoMap['UserType']?.toString(),
        nickname:
            rootMap['Nickname']?.toString() ?? infoMap['Nickname']?.toString(),
        displayName:
            infoMap['DisplayName']?.toString() ??
            rootMap['DisplayName']?.toString(),
        email: infoMap['Email']?.toString() ?? infoMap['Contact']?.toString(),
        location: infoMap['Location']?.toString(),
        about: infoMap['About']?.toString(),
        level: infoMap['Level']?.toString(),
        instruments: _parseList(infoMap['Instruments']),
        styles: _parseList(infoMap['Styles']),
        genres: _parseList(infoMap['Genres']),
        contact: infoMap['Contact']?.toString(),
        history: infoMap['History']?.toString(),
        projects: infoMap['Projects']?.toString(),
        profilePictureUrl: infoMap['ProfilePictureUrl']?.toString(),
        spotifyUrl: infoMap['SpotifyUrl']?.toString(),
        youtubeUrl: infoMap['YoutubeUrl']?.toString(),
        audioSnippetUrl: infoMap['AudioSnippetUrl']?.toString(),
        collabRoles: _parseList(infoMap['CollabRoles']),
        collabRemote: infoMap['CollabRemote'] == true,
        collabBio: infoMap['CollabBio']?.toString(),
        mainInstrument: infoMap['MainInstrument']?.toString(),
      );
    }
    return null;
  }

  Future<List<UserProfile>> getAllUsersAsync() async {
    final snapshot = await _dbRef('users').get();
    final List<UserProfile> users = [];
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map;
      data.forEach((k, v) {
        if (v is Map) {
          final userId = k.toString();
          final rootMap = v;
          final infoMap = rootMap['info'] is Map ? rootMap['info'] as Map : {};
          users.add(
            UserProfile(
              userId: userId,
              userType:
                  rootMap['UserType']?.toString() ??
                  infoMap['UserType']?.toString(),
              nickname:
                  rootMap['Nickname']?.toString() ??
                  infoMap['Nickname']?.toString(),
              displayName:
                  infoMap['DisplayName']?.toString() ??
                  rootMap['DisplayName']?.toString(),
              location: infoMap['Location']?.toString(),
              about: infoMap['About']?.toString(),
              level: infoMap['Level']?.toString(),
              instruments: _parseList(infoMap['Instruments']),
              styles: _parseList(infoMap['Styles']),
              genres: _parseList(infoMap['Genres']),
              contact: infoMap['Contact']?.toString(),
              history: infoMap['History']?.toString(),
              projects: infoMap['Projects']?.toString(),
              profilePictureUrl: infoMap['ProfilePictureUrl']?.toString(),
              spotifyUrl: infoMap['SpotifyUrl']?.toString(),
              youtubeUrl: infoMap['YoutubeUrl']?.toString(),
              audioSnippetUrl: infoMap['AudioSnippetUrl']?.toString(),
              collabRoles: _parseList(infoMap['CollabRoles']),
              collabRemote: infoMap['CollabRemote'] == true,
              collabBio: infoMap['CollabBio']?.toString(),
              mainInstrument: infoMap['MainInstrument']?.toString(),
            ),
          );
        }
      });
    }
    return users;
  }

  Future<String> uploadAudioSnippetAsync(
    String userId,
    Uint8List? bytes,
    String? path,
  ) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profileAudio')
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
    } catch (e) {
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
          .child('profilePictures')
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
    } catch (e) {
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
    final snapshot = await _dbRef('users/$userId/Bands').get();
    final Map<String, String> bands = {};
    if (snapshot.exists) {
      final value = snapshot.value;
      if (value is Map) {
        value.forEach((k, v) {
          final bandId = k.toString();
          if (v is Map) {
            final name =
                v['Name']?.toString() ?? v['name']?.toString() ?? bandId;
            bands[bandId] = name;
          } else if (v is String) {
            bands[bandId] = v;
          } else {
            bands[bandId] = bandId;
          }
        });
      } else if (value is List) {
        for (int i = 0; i < value.length; i++) {
          final item = value[i];
          if (item != null) {
            if (item is Map) {
              final name =
                  item['Name']?.toString() ??
                  item['name']?.toString() ??
                  i.toString();
              bands[i.toString()] = name;
            } else {
              bands[i.toString()] = item.toString();
            }
          }
        }
      }
    }
    return bands;
  }

  Future<Band?> getBandInfoAsync(String bandId) async {
    final snapshot = await _dbRef('Bands/$bandId').get();
    if (snapshot.exists && snapshot.value is Map) {
      return Band.fromJson(snapshot.value as Map, bandId);
    }
    return null;
  }

  Future<void> createBandAsync(String userId, Band band) async {
    final bandNameKey = (band.name ?? 'My Band').replaceAll(' ', '_');
    final bandRef = _dbRef('Bands/$bandNameKey');

    final updatedBand = Band(
      id: bandNameKey,
      name: band.name,
      ensembleType: band.ensembleType,
      genres: band.genres,
      location: band.location,
      rehearsalLocation: band.rehearsalLocation,
      rehearsalDayOfWeek: band.rehearsalDayOfWeek,
      rehearsalStartTime: band.rehearsalStartTime,
      rehearsalEndTime: band.rehearsalEndTime,
      about: band.about,
      description: band.description,
      membersBand: {userId: BandMember(nickname: 'Leader', role: 'Leader')},
    );

    // Save globally
    await bandRef.set(updatedBand.toJson());
    // Assign Leader in global band members
    await _dbRef(
      'Bands/$bandNameKey/Members_band/$userId',
    ).set({'Nickname': 'Leader', 'Role': 'Leader'});
    // Link band in user's profile
    await _dbRef('users/$userId/Bands/$bandNameKey').set(updatedBand.toJson());
    // Add member to band conversation
    await _dbRef('bandconversations/$bandNameKey/members/$userId').set(true);
  }

  Future<void> updateBandAsync(String bandId, Band band) async {
    final updateData = {
      'Name': band.name,
      'EnsembleType': band.ensembleType,
      'Genres': band.genres,
      'Style_band': band.styleBand,
      'Level': band.level,
      'Location': band.location,
      'RehearsalLocation': band.rehearsalLocation,
      'RehearsalDayOfWeek': band.rehearsalDayOfWeek,
      'RehearsalStartTime': band.rehearsalStartTime,
      'RehearsalEndTime': band.rehearsalEndTime,
      'About': band.about,
      'Description': band.description,
    };

    // 1. Update root band reference
    await _dbRef('Bands/$bandId').update(updateData);

    // 2. Sync updates to user-specific band lists for all members
    final members = await getBandMembersAsync(bandId);
    for (final member in members) {
      final userId = member.userId;
      if (userId != null) {
        await _dbRef('users/$userId/Bands/$bandId').update(updateData);
      }
    }
  }

  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    final snapshot = await _dbRef('Bands/$bandId/Members_band').get();
    final List<BandMember> members = [];
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          members.add(BandMember.fromJson(v, k.toString()));
        }
      });
    }
    return members;
  }

  // ==========================================
  // 5. Substitute Requests
  // ==========================================

  Future<String?> saveSubRequestAsync(SubRequest request) async {
    final newRef = _dbRef('SubRequests').push();
    final key = newRef.key;
    if (key != null) {
      final updated = SubRequest(
        id: key,
        subRequestId: key,
        creatorUserId: currentUserId,
        userId: currentUserId,
        voicePart: request.voicePart,
        location: request.location,
        startTime: request.startTime,
        endTime: request.endTime,
        description: request.description,
        date: request.date,
        role: request.role,
        isPaid: request.isPaid,
        bandName: request.bandName,
        rehearsalDayOfWeek: request.rehearsalDayOfWeek,
        latitude: request.latitude,
        longitude: request.longitude,
        targetUserIds: request.targetUserIds,
        eventId: request.eventId,
        bandId: request.bandId,
      );

      // Save in root SubRequests
      await newRef.set(updated.toJson());

      // Save under user's profile SubRequests
      if (currentUserId != null) {
        await _dbRef(
          'users/$currentUserId/SubRequests/$key',
        ).set(updated.toJson());
      }
      return key;
    }
    return null;
  }

  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    final snapshot = await _dbRef('SubRequests').get();
    final List<SubRequest> requests = [];
    final selfId = currentUserId;
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          final req = SubRequest.fromJson(v, k.toString());
          final targets = req.targetUserIds;
          if (targets == null || targets.isEmpty) {
            requests.add(req);
          } else {
            if (selfId != null &&
                (targets.contains(selfId) || req.creatorUserId == selfId)) {
              requests.add(req);
            }
          }
        }
      });
    }
    return requests;
  }

  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async {
    final snapshot = await _dbRef('users/$userId/SubRequests').get();
    final List<SubRequest> requests = [];
    final selfId = currentUserId;
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          final req = SubRequest.fromJson(v, k.toString());
          final targets = req.targetUserIds;
          if (targets == null || targets.isEmpty) {
            requests.add(req);
          } else {
            if (selfId != null &&
                (targets.contains(selfId) || req.creatorUserId == selfId)) {
              requests.add(req);
            }
          }
        }
      });
    }
    return requests;
  }

  Future<List<SubRequest>> getSubRequestsForEventAsync(
    String bandId,
    String eventId,
  ) async {
    final all = await getAllSubRequestsAsync();
    return all.where((r) => r.bandId == bandId && r.eventId == eventId).toList();
  }

  Future<List<String>> saveSubRequestsBatchAsync(
    List<SubRequest> requests,
  ) async {
    final List<String> createdIds = [];
    final Map<String, dynamic> multiLocationUpdates = {};
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final req in requests) {
      final key = _dbRef('SubRequests').push().key;
      if (key == null) continue;
      createdIds.add(key);

      final updated = req.copyWith(
        id: key,
        subRequestId: key,
        slotId: req.slotId ?? key,
        creatorUserId: currentUserId,
        userId: currentUserId,
        createdAt: now,
        status: 'published',
      );

      final json = updated.toJson();
      multiLocationUpdates['SubRequests/$key'] = json;
      if (currentUserId != null) {
        multiLocationUpdates['users/$currentUserId/SubRequests/$key'] = json;
      }

      if (req.bandId != null && req.eventId != null) {
        final targets = req.targetUserIds;
        if (targets != null && targets.isNotEmpty) {
          for (final targetId in targets) {
            multiLocationUpdates[
                'Bands/${req.bandId}/Events/${req.eventId}/externalInvitees/$targetId'] = {
              'userId': targetId,
              'status': 'pending',
              'instrument': req.voicePart,
              'invitedAt': now,
              'source': 'subRequest',
              'subRequestId': key,
            };
          }
        }
      }
    }

    if (multiLocationUpdates.isNotEmpty) {
      await _dbRef('').update(multiLocationUpdates);
    }
    return createdIds;
  }

  Future<void> assignSubstituteCandidateAsync({
    required String subRequestId,
    required String candidateUserId,
    required String bandId,
    required String eventId,
    required String roleOrInstrument,
    String? candidateName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {};

    updates['SubRequests/$subRequestId/IsSelected'] = true;
    updates['SubRequests/$subRequestId/Status'] = 'assigned';
    updates['SubRequests/$subRequestId/AssignedUserId'] = candidateUserId;
    if (candidateName != null) {
      updates['SubRequests/$subRequestId/AssignedUserName'] = candidateName;
    }
    updates['SubRequests/$subRequestId/AssignedAt'] = now;

    if (currentUserId != null) {
      updates['users/$currentUserId/SubRequests/$subRequestId/IsSelected'] = true;
      updates['users/$currentUserId/SubRequests/$subRequestId/Status'] = 'assigned';
      updates['users/$currentUserId/SubRequests/$subRequestId/AssignedUserId'] = candidateUserId;
      if (candidateName != null) {
        updates['users/$currentUserId/SubRequests/$subRequestId/AssignedUserName'] = candidateName;
      }
      updates['users/$currentUserId/SubRequests/$subRequestId/AssignedAt'] = now;
    }

    updates['Bands/$bandId/Events/$eventId/externalInvitees/$candidateUserId/status'] = 'attending';
    updates['Bands/$bandId/Events/$eventId/externalInvitees/$candidateUserId/instrument'] = roleOrInstrument;
    updates['Bands/$bandId/Events/$eventId/updatedAt'] = now;

    await _dbRef('').update(updates);
  }

  Future<void> revokeSubstituteAssignmentAsync({
    required String subRequestId,
    required String candidateUserId,
    required String bandId,
    required String eventId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {};

    updates['SubRequests/$subRequestId/IsSelected'] = false;
    updates['SubRequests/$subRequestId/Status'] = 'published';
    updates['SubRequests/$subRequestId/AssignedUserId'] = null;
    updates['SubRequests/$subRequestId/AssignedUserName'] = null;
    updates['SubRequests/$subRequestId/AssignedAt'] = null;

    if (currentUserId != null) {
      updates['users/$currentUserId/SubRequests/$subRequestId/IsSelected'] = false;
      updates['users/$currentUserId/SubRequests/$subRequestId/Status'] = 'published';
      updates['users/$currentUserId/SubRequests/$subRequestId/AssignedUserId'] = null;
      updates['users/$currentUserId/SubRequests/$subRequestId/AssignedUserName'] = null;
      updates['users/$currentUserId/SubRequests/$subRequestId/AssignedAt'] = null;
    }

    updates['Bands/$bandId/Events/$eventId/externalInvitees/$candidateUserId/status'] = 'pending';
    updates['Bands/$bandId/Events/$eventId/updatedAt'] = now;

    await _dbRef('').update(updates);
  }

  Future<void> addResponseToSubRequestAsync(
    String subRequestId,
    String userId,
  ) async {
    await _dbRef('SubRequests/$subRequestId/Responses/$userId').set(true);

    try {
      final snapshot = await _dbRef('SubRequests/$subRequestId').get();
      if (snapshot.exists && snapshot.value is Map) {
        final subRequest = SubRequest.fromJson(
          snapshot.value as Map,
          subRequestId,
        );
        final bandId = subRequest.bandId;
        final eventId = subRequest.eventId;
        if (bandId != null &&
            eventId != null &&
            bandId.isNotEmpty &&
            eventId.isNotEmpty) {
          final profile = await getUserProfileAsync(userId);
          final invitee = ExternalInvitee(
            userId: userId,
            status: 'pending',
            instrument: profile?.instruments.isNotEmpty == true
                ? profile?.instruments.first
                : profile?.userType,
            invitedAt: DateTime.now().millisecondsSinceEpoch,
            source: 'subRequest',
            subRequestId: subRequestId,
            displayName: profile?.displayName ?? profile?.nickname,
          );
          await _dbRef(
            'Bands/$bandId/Events/$eventId/externalInvitees/$userId',
          ).set(invitee.toJson());
          await _dbRef(
            'Bands/$bandId/Events/$eventId/updatedAt',
          ).set(DateTime.now().millisecondsSinceEpoch);
        }
      }
    } catch (e) {
      print(
        "[FirebaseService] Error in addResponseToSubRequestAsync linking event: $e",
      );
    }
  }

  Future<bool> deleteSubRequestAsync(
    String creatorId,
    String subRequestId,
  ) async {
    try {
      if (creatorId.isEmpty || subRequestId.isEmpty) return false;

      // Delete from user's subrequests
      await _dbRef('users/$creatorId/SubRequests/$subRequestId').remove();

      // Delete from root SubRequests
      await _dbRef('SubRequests/$subRequestId').remove();

      return true;
    } catch (e) {
      print("[FirebaseService] Error deleting subrequest: $e");
      return false;
    }
  }

  Future<int> getSubRequestResponseCountAsync(String subRequestId) async {
    try {
      final snapshot = await _dbRef(
        'SubRequests/$subRequestId/Responses',
      ).get();
      if (snapshot.exists && snapshot.value is Map) {
        return (snapshot.value as Map).length;
      }
      return 0;
    } catch (e) {
      print("[FirebaseService] Error getting response count: $e");
      return 0;
    }
  }

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
    );
    if (conversationId.isNotEmpty &&
        message.text != null &&
        message.text!.isNotEmpty) {
      await sendConversationMessageAsync(
        conversationId,
        message.text!,
        receiverId,
        message.senderName ?? 'System',
      );
    }
    return conversationId;
  }

  // ==========================================
  // 6. Direct Chat Messages
  // ==========================================

  Future<String> createAgreementConversationAsync(
    String subRequestId,
    String applicantId,
  ) async {
    final result = await _functions
        .httpsCallable('createAgreementConversation')
        .call({'subRequestId': subRequestId, 'applicantId': applicantId});
    return result.data['conversationId']?.toString() ?? '';
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
    return result.data['conversationId']?.toString() ?? '';
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
    return _dbRef('conversations/$conversationId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        final agreementRaw = data['Agreement'] ?? data['agreement'];
        Agreement? agreement;
        if (agreementRaw is Map) {
          agreement = Agreement.fromJson(agreementRaw);
        }
        return {
          'participants': _parseList(
            data['Participants'] ?? data['participants'],
          ),
          'agreement': agreement,
        };
      }
      return null;
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
    } catch (e) {
      print("[FirebaseService] Error marking conversation as read: $e");
    }
  }

  Future<void> markBandSectionConversationReadAsync(String conversationId) async {
    try {
      await _functions.httpsCallable('markBandSectionConversationRead').call({
        'conversationId': conversationId,
      });
    } catch (e) {
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

  Future<List<Map<String, dynamic>>> getActiveConversationsAsync() async {
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

    return conversations;
  }

  // ==========================================
  // 7. Calendar Events
  // ==========================================

  Future<void> addBandEventAsync(CalendarEvent event) async {
    final bandId = event.bandId;
    if (bandId == null) return;

    final ref = _dbRef('BandEvents/$bandId').push();
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
      await ref.set(updated.toJson());
    }
  }

  Future<List<CalendarEvent>> getBandEventsAsync(String bandId) async {
    final snapshot = await _dbRef('BandEvents/$bandId').get();
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
          files[k.toString()] = {'FileName': fileName, 'FileUrl': fileUrl};
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
    String fileUrl,
  ) async {
    final ref = _dbRef('files/$bandId').push();
    await ref.set({'FileName': fileName, 'FileUrl': fileUrl});
  }

  Future<void> removeBandFileAsync(String bandId, String fileId) async {
    await _dbRef('files/$bandId/$fileId').remove();
  }

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
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('bandFiles')
          .child(bandId)
          .child('${DateTime.now().millisecondsSinceEpoch}_$fileName');

      final mimeType = _getMimeType(fileName);
      final metadata = SettableMetadata(contentType: mimeType);

      UploadTask uploadTask;
      if (bytes != null && bytes.isNotEmpty) {
        uploadTask = ref.putData(bytes, metadata);
      } else if (path != null && path.isNotEmpty) {
        uploadTask = ref.putFile(File(path), metadata);
      } else {
        throw Exception("Both file bytes and path are null for upload");
      }
      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      return url;
    } catch (e) {
      print("[FirebaseService] Error uploading band file: $e");
      rethrow;
    }
  }

  Future<void> savePushTokenAsync(String token) async {
    try {
      final userId = currentUserId;
      if (userId == null) return;
      await _dbRef('users/$userId/info/PushToken').set(token);
      print("[FirebaseService] Push Token saved for user $userId");
    } catch (e) {
      print("[FirebaseService] Error saving push token: $e");
    }
  }

  Future<void> initializePushNotifications() async {
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

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print("PUSH: Permission Granted");
      } else {
        print("PUSH: Permission Denied");
      }

      // Handle token refreshes
      messaging.onTokenRefresh.listen((token) async {
        print("PUSH: TOKEN REFRESHED: $token");
        await savePushTokenAsync(token);
      });

      // Get current token
      final currentToken = await messaging.getToken();
      if (currentToken != null && currentToken.isNotEmpty) {
        print("PUSH: Token already exists: $currentToken");
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
    } catch (e) {
      print("PUSH: ERROR Initializing: $e");
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
            .child('marketplaceImages')
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
      } catch (e) {
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
    'updatedAt',
  };

  Future<String> createBandEventAsync(String bandId, BandEvent event) async {
    final eventId =
        event.id ??
        _dbRef('Bands/$bandId/Events').push().key ??
        DateTime.now().millisecondsSinceEpoch.toString();
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
    );
    await _dbRef('Bands/$bandId/Events/$eventId').set(created.toJson());
    return eventId;
  }

  Future<void> updateBandEventAsync(
    String bandId,
    String eventId,
    Map<String, dynamic> editableFields,
  ) async {
    final eventRef = _dbRef('Bands/$bandId/Events/$eventId');
    final result = await eventRef.runTransaction((currentData) {
      if (currentData == null) {
        return Transaction.abort(); // Abort if event was deleted
      }
      if (currentData is Map) {
        final Map<String, dynamic> updatedMap = Map<String, dynamic>.from(
          currentData,
        );
        for (final key in _eventEditableWhitelist) {
          if (editableFields.containsKey(key)) {
            updatedMap[key] = editableFields[key];
          }
        }
        updatedMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
        return Transaction.success(updatedMap);
      }
      return Transaction.abort();
    });

    if (!result.committed) {
      throw Exception(
        "Failed to update event: Event $eventId does not exist or transaction aborted.",
      );
    }
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
      });
      return event.id!;
    }
  }

  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    final snapshot = await _dbRef('Bands/$bandId/Events').get();
    final List<BandEvent> list = [];
    if (snapshot.exists && snapshot.value is Map) {
      (snapshot.value as Map).forEach((k, v) {
        if (v is Map) {
          list.add(BandEvent.fromJson(v, k.toString()));
        }
      });
    }
    return list;
  }

  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) {
    return _dbRef('Bands/$bandId/Events/$eventId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        return BandEvent.fromJson(data, eventId);
      }
      return null;
    });
  }

  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    return _dbRef('Bands/$bandId/Events').onValue.map((event) {
      final List<BandEvent> list = [];
      final data = event.snapshot.value;
      if (data is Map) {
        data.forEach((k, v) {
          if (v is Map) {
            list.add(BandEvent.fromJson(v, k.toString()));
          }
        });
      }
      return list;
    });
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
    await _dbRef(
      'Bands/$bandId/Events/$eventId/updatedAt',
    ).set(DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> deleteBandEventAsync(String bandId, String eventId) async {
    await _dbRef('Bands/$bandId/Events/$eventId').remove();
  }

  Future<void> addBandMemberAsync(
    String bandId,
    String userId,
    String role,
    String nickname,
  ) async {
    await _dbRef(
      'Bands/$bandId/Members_band/$userId',
    ).set({'Nickname': nickname, 'Role': role});
    final band = await getBandInfoAsync(bandId);
    if (band != null) {
      await _dbRef('users/$userId/Bands/$bandId').set(band.toJson());
    }
    await _dbRef('bandconversations/$bandId/members/$userId').set(true);
  }

  Future<void> removeBandMemberAsync(String bandId, String userId) async {
    await _dbRef('Bands/$bandId/Members_band/$userId').remove();
    await _dbRef('users/$userId/Bands/$bandId').remove();
    await _dbRef('bandconversations/$bandId/members/$userId').remove();
  }

  Future<void> updateBandMemberRoleAsync(
    String bandId,
    String userId,
    String newRole,
  ) async {
    await _dbRef('Bands/$bandId/Members_band/$userId/Role').set(newRole);
  }

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
    final snapshot = await _dbRef('Bands/$bandId/Events/$eventId').get();
    if (snapshot.exists && snapshot.value is Map) {
      return BandEvent.fromJson(snapshot.value as Map, eventId);
    }
    return null;
  }

  Future<void> addExternalInviteesToEventAsync(
    String bandId,
    String eventId,
    List<String> userIds, {
    String? subRequestId,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final updates = <String, dynamic>{};
    for (final uid in userIds) {
      final profile = await getUserProfileAsync(uid);
      final invitee = ExternalInvitee(
        userId: uid,
        status: 'pending',
        instrument: profile?.instruments.isNotEmpty == true
            ? profile?.instruments.first
            : profile?.userType,
        invitedAt: timestamp,
        source: subRequestId != null ? 'subRequest' : null,
        subRequestId: subRequestId,
        displayName: profile?.displayName ?? profile?.nickname,
      );
      updates['Bands/$bandId/Events/$eventId/externalInvitees/$uid'] = invitee
          .toJson();
    }
    updates['Bands/$bandId/Events/$eventId/updatedAt'] = timestamp;
    await _dbRef().update(updates);
  }

  Future<void> updateExternalInviteeResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final updates = {'status': status, if (comment != null) 'comment': comment};
    await _dbRef(
      'Bands/$bandId/Events/$eventId/externalInvitees/$userId',
    ).update(updates);
    await _dbRef('Bands/$bandId/Events/$eventId/updatedAt').set(timestamp);
  }

  Future<void> lockBandEventAsync(String bandId, String eventId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final userId = currentUserId ?? '';
    await _dbRef('Bands/$bandId/Events/$eventId').update({
      'isLocked': true,
      'lockedAt': timestamp,
      'lockedBy': userId,
      'updatedAt': timestamp,
    });
  }

  Future<void> unlockBandEventAsync(String bandId, String eventId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await _dbRef('Bands/$bandId/Events/$eventId').update({
      'isLocked': false,
      'lockedAt': null,
      'lockedBy': null,
      'updatedAt': timestamp,
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

  Future<List<Band>> getAllBandsAsync() async {
    final snapshot = await _dbRef('Bands').get();
    final List<Band> list = [];
    if (snapshot.exists && snapshot.value is Map) {
      final map = snapshot.value as Map;
      map.forEach((k, v) {
        if (v is Map) {
          list.add(Band.fromJson(v, k.toString()));
        }
      });
    }
    return list;
  }

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
    await _dbRef('Collabs/Sessions/$id').set(newSession.toJson());
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

      multiLocationMap['$id'] = fullSession.toJson();
    }

    await _dbRef('Collabs/Sessions').update(multiLocationMap);
    return sessionIds;
  }

  Future<void> deleteCollabSessionAsync(String sessionId) async {
    await _dbRef('Collabs/Sessions/$sessionId').remove();
    await _dbRef('Collabs/Applications/$sessionId').remove();
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
  ) async {
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
  }

  Future<CollabSessionApplication?> getCollabSessionApplicationAsync(
    String sessionId,
    String applicantId,
  ) async {
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
  }

  Future<void> updateCollabApplicationStatusAsync(
    String sessionId,
    String applicantId,
    String status,
  ) async {
    try {
      await _functions.httpsCallable('updateSessionApplicationStatus').call({
        'sessionId': sessionId,
        'applicantId': applicantId,
        'status': status,
      });
    } catch (e) {
      debugPrint('updateSessionApplicationStatus error, using direct DB update: $e');
      await _dbRef(
        'Collabs/Applications/$sessionId/$applicantId/Status',
      ).set(status);

      if (status == 'accepted') {
        final sessionSnapshot = await _dbRef('Collabs/Sessions/$sessionId').get();
        if (sessionSnapshot.exists && sessionSnapshot.value is Map) {
          final sessionData = sessionSnapshot.value as Map;
          final chatId = sessionData['SessionChatId']?.toString() ??
              sessionData['sessionChatId']?.toString();
          if (chatId != null && chatId.isNotEmpty) {
            try {
              await addParticipantToSessionChatAsync(
                sessionId: sessionId,
                chatId: chatId,
                participantId: applicantId,
              );
            } catch (err) {
              debugPrint('Error adding accepted participant to session chat: $err');
            }
          }
        }
      }
    }
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

    // Direct write to /Collabs/Sessions/$sessionId/Responses/$userId governed by RTDB security rules
    await _dbRef('Collabs/Sessions/$sessionId/Responses/$userId')
        .set(response.toJson());
  }

  // Session Chat
  Future<String> createSessionChatRoomAsync({
    required String sessionId,
    required String sessionTitle,
    required String createdBy,
  }) async {
    try {
      final result = await _functions.httpsCallable('createSessionConversation').call({
        'sessionId': sessionId,
        'sessionTitle': sessionTitle,
      });
      final convId = result.data['conversationId']?.toString() ?? '';
      if (convId.isNotEmpty) {
        return convId;
      }
    } catch (e) {
      debugPrint('createSessionConversation error, fallback to direct DB: $e');
    }

    final ref = _dbRef('conversations').push();
    final chatId = ref.key!;
    final nowIso = DateTime.now().toIso8601String();

    final convData = {
      'conversationType': 'session_chat',
      'sessionId': sessionId,
      'sessionTitle': sessionTitle,
      'createdBy': createdBy,
      'participants': {
        createdBy: true,
      },
      'Participants': [createdBy],
      'createdTimestamp': nowIso,
    };

    await ref.set(convData);
    await _dbRef('Collabs/Sessions/$sessionId/SessionChatId').set(chatId);
    await _dbRef('userConversations/$createdBy/$chatId').set({
      'conversationType': 'session_chat',
      'sessionId': sessionId,
      'otherUserId': '',
      'otherUserName': sessionTitle,
      'lastMessageText': '',
      'lastMessageTimestamp': nowIso,
      'hasUnread': false,
    });

    return chatId;
  }

  Future<void> addParticipantToSessionChatAsync({
    required String sessionId,
    required String chatId,
    required String participantId,
  }) async {
    final sessionSnapshot = await _dbRef('Collabs/Sessions/$sessionId').get();
    String sessionTitle = 'Session Chat';
    if (sessionSnapshot.exists && sessionSnapshot.value is Map) {
      final sData = sessionSnapshot.value as Map;
      sessionTitle = sData['Title']?.toString() ?? sData['title']?.toString() ?? 'Session Chat';
    }

    final nowIso = DateTime.now().toIso8601String();
    await _dbRef('conversations/$chatId/participants/$participantId').set(true);
    await _dbRef('userConversations/$participantId/$chatId').set({
      'conversationType': 'session_chat',
      'sessionId': sessionId,
      'otherUserId': '',
      'otherUserName': sessionTitle,
      'lastMessageText': 'You joined the session chat',
      'lastMessageTimestamp': nowIso,
      'hasUnread': true,
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
    final roomId = ref.key!;
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

    await ref.set(eventRoom.toJson());
    await _dbRef('Bands/$bandId/Events/$eventId/temporaryRoomId').set(roomId);
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
    await _dbRef('Bands/$bandId/eventRooms/$roomId/members/$userId').set(role);
  }

  Future<void> closeOrDeleteEventRoomAsync(
    String bandId,
    String roomId,
    bool deleteRoom,
  ) async {
    if (deleteRoom) {
      await _dbRef('Bands/$bandId/eventRooms/$roomId').remove();
    } else {
      await _dbRef('Bands/$bandId/eventRooms/$roomId/isClosed').set(true);
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
    } on FirebaseFunctionsException catch (e) {
      return {
        'status': 'error',
        'code': e.code,
        'message': e.message ?? e.toString(),
        'successCount': 0,
      };
    } catch (e) {
      return {
        'status': 'error',
        'code': 'unknown',
        'message': e.toString(),
        'successCount': 0,
      };
    }
  }
}
