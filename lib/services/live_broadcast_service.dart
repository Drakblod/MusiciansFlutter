import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/live_broadcast.dart';

/// Credentials and room info needed by a client to connect to LiveKit.
class LiveBroadcastSessionToken {
  final String token;
  final String serverUrl;
  final String roomName;
  final LiveBroadcastParticipantRole role;
  final String broadcastId;

  const LiveBroadcastSessionToken({
    required this.token,
    required this.serverUrl,
    required this.roomName,
    required this.role,
    required this.broadcastId,
  });

  factory LiveBroadcastSessionToken.fromMap(Map<dynamic, dynamic> map) {
    return LiveBroadcastSessionToken(
      token: (map['token'] ?? '').toString(),
      serverUrl: (map['serverUrl'] ?? '').toString(),
      roomName: (map['roomName'] ?? '').toString(),
      role: LiveBroadcastParticipantRole.fromString(map['role']?.toString()),
      broadcastId: (map['broadcastId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'token': token,
      'serverUrl': serverUrl,
      'roomName': roomName,
      'role': role.toDbValue(),
      'broadcastId': broadcastId,
    };
  }
}

/// Abstract contract for live broadcast management.
abstract class ILiveBroadcastService {
  /// Request server-side creation of a live broadcast and obtain a publisher token.
  Future<LiveBroadcastSessionToken> startLiveBroadcast({
    required String bandId,
    required String title,
    required LatLng location,
    String? description,
    String? genre,
  });

  /// Request a subscriber-only listener token to join an ongoing broadcast.
  Future<LiveBroadcastSessionToken> joinLiveBroadcast({
    required String broadcastId,
  });

  /// Request authoritative termination of a live broadcast.
  Future<void> stopLiveBroadcast({
    required String broadcastId,
  });

  /// Stream of all currently active broadcasts across the platform.
  Stream<List<LiveBroadcast>> streamActiveBroadcasts();

  /// Stream for a specific broadcast by ID.
  Stream<LiveBroadcast?> streamBroadcast(String broadcastId);
}

/// Production implementation of ILiveBroadcastService using Firebase Functions & RTDB.
class LiveBroadcastService implements ILiveBroadcastService {
  final FirebaseFunctions _functions;
  final FirebaseDatabase _database;

  static const String databaseUrl =
      "https://musiciansapp-35f70-default-rtdb.europe-west1.firebasedatabase.app";

  LiveBroadcastService({
    FirebaseFunctions? functions,
    FirebaseDatabase? database,
  })  : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
        _database = database ??
            FirebaseDatabase.instanceFor(
              app: FirebaseDatabase.instance.app,
              databaseURL: databaseUrl,
            );

  @override
  Future<LiveBroadcastSessionToken> startLiveBroadcast({
    required String bandId,
    required String title,
    required LatLng location,
    String? description,
    String? genre,
  }) async {
    final callable = _functions.httpsCallable('startLiveBroadcast');
    final response = await callable.call<Map<dynamic, dynamic>>({
      'bandId': bandId,
      'title': title,
      'latitude': location.latitude,
      'longitude': location.longitude,
      if (description != null) 'description': description,
      if (genre != null) 'genre': genre,
    });

    final data = response.data;
    return LiveBroadcastSessionToken.fromMap(data);
  }

  @override
  Future<LiveBroadcastSessionToken> joinLiveBroadcast({
    required String broadcastId,
  }) async {
    final callable = _functions.httpsCallable('joinLiveBroadcast');
    final response = await callable.call<Map<dynamic, dynamic>>({
      'broadcastId': broadcastId,
    });

    final data = response.data;
    return LiveBroadcastSessionToken.fromMap(data);
  }

  @override
  Future<void> stopLiveBroadcast({
    required String broadcastId,
  }) async {
    final callable = _functions.httpsCallable('stopLiveBroadcast');
    await callable.call<void>({
      'broadcastId': broadcastId,
    });
  }

  @override
  Stream<List<LiveBroadcast>> streamActiveBroadcasts() {
    return _database.ref('LiveBroadcasts').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return <LiveBroadcast>[];

      final List<LiveBroadcast> list = [];
      raw.forEach((key, val) {
        if (val is Map) {
          final broadcast = LiveBroadcast.fromMap(key.toString(), val);
          if (broadcast.isActive) {
            list.add(broadcast);
          }
        }
      });
      return list;
    });
  }

  @override
  Stream<LiveBroadcast?> streamBroadcast(String broadcastId) {
    return _database.ref('LiveBroadcasts/$broadcastId').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return null;
      return LiveBroadcast.fromMap(broadcastId, raw);
    });
  }
}
