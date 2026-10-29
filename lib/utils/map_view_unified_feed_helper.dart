import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/sub_request.dart';
import '../views/gig_map_page.dart' show MapEventType, MapCategory, MapEventTypeHelper;
import 'date_parser.dart';
import 'map_event_activity_helper.dart';

/// Centralized presentation classification for every Map View item.
/// Every displayed item resolves to exactly one source kind.
enum MapItemKind {
  event,
  eventSchedulePart,
  staffingRequest,
  newMemberRequest,
  musicPromotion,
  liveBroadcast,
  mockDemo,
}

/// Represents a processed, deduplicated, and collision-resolved visual map marker item.
class UnifiedMapMarkerItem {
  final String id;
  final SubRequest primaryGig;
  final List<SubRequest> groupedGigs;
  final MapItemKind kind;
  final LatLng position;
  final LatLng originalPosition;
  final bool isLive;

  const UnifiedMapMarkerItem({
    required this.id,
    required this.primaryGig,
    this.groupedGigs = const [],
    required this.kind,
    required this.position,
    required this.originalPosition,
    this.isLive = false,
  });
}

/// Classifies any [SubRequest] or map entity into its canonical [MapItemKind].
/// Uses canonical fields only; never searches arbitrary description text.
MapItemKind classifyMapItem(SubRequest item) {
  final id = item.id ?? '';

  // 1. Mock / Demo Fixtures
  if (id.startsWith('mock_') || item.subRequestId?.startsWith('mock_') == true) {
    return MapItemKind.mockDemo;
  }

  // 2. Go Live Broadcasts
  if (item.extraFields['isLiveBroadcast'] == true ||
      id.startsWith('live:') ||
      item.extraFields['broadcastId'] != null) {
    return MapItemKind.liveBroadcast;
  }

  // 3. Automatic Event Projections (Band Events & Public Calendar Events)
  final isEventProj = item.extraFields['isEventProjection'] == true ||
      id.startsWith('event:') ||
      item.extraFields['eventSource'] != null;
  if (isEventProj) {
    final schedulePartId = item.extraFields['schedulePartId']?.toString();
    final hasSchedulePart = schedulePartId != null && schedulePartId.trim().isNotEmpty;
    final segments = id.split(':');
    final isMultiPartId = (id.startsWith('event:public:') && segments.length >= 4) ||
        (id.startsWith('event:private:') && segments.length >= 5);
    if (hasSchedulePart || isMultiPartId) {
      return MapItemKind.eventSchedulePart;
    }
    return MapItemKind.event;
  }

  // 4. Manual Music Promotion Pins (created via Map View upload)
  final notifMode = (item.extraFields['NotificationMode'] ?? item.extraFields['notificationMode'])?.toString();
  final role = item.role?.toString().toLowerCase();
  final reqType = item.requestType?.toString().toLowerCase();
  final rawEventType = item.extraFields['eventType']?.toString().toLowerCase();

  final isMusicPromotion = notifMode == 'map_pin' ||
      role == 'map_pin' ||
      rawEventType == 'gigpromo' ||
      rawEventType == 'gig_promo' ||
      reqType == 'gig promo' ||
      reqType == 'music promotion';

  if (isMusicPromotion) {
    return MapItemKind.musicPromotion;
  }

  // 5. Staffing Searches: New Member vs Substitute Request
  final isNewMember = item.isNewMember ||
      reqType == 'new member' ||
      reqType == 'newmember' ||
      rawEventType == 'newmember' ||
      rawEventType == 'new_member';

  if (isNewMember) {
    return MapItemKind.newMemberRequest;
  }

  // 6. Otherwise: Staffing Request (Substitute request, open band positions)
  return MapItemKind.staffingRequest;
}

/// Returns a stable, collision-free marker ID prefixed with its source namespace.
String getNamespacedMarkerId(SubRequest item) {
  final kind = classifyMapItem(item);
  final rawId = (item.canonicalTargetId ?? item.id ?? '').trim();
  switch (kind) {
    case MapItemKind.event:
    case MapItemKind.eventSchedulePart:
      return rawId.startsWith('event:') ? rawId : 'event:$rawId';
    case MapItemKind.musicPromotion:
      return rawId.startsWith('map_pin:') ? rawId : 'map_pin:$rawId';
    case MapItemKind.liveBroadcast:
      return rawId.startsWith('live:') ? rawId : 'live:$rawId';
    case MapItemKind.mockDemo:
      return rawId.startsWith('mock:') ? rawId : 'mock:$rawId';
    case MapItemKind.newMemberRequest:
    case MapItemKind.staffingRequest:
      return rawId.startsWith('subrequest:') ? rawId : 'subrequest:$rawId';
  }
}

/// Returns the deduplication key for an item.
/// Ensures public and private projections of the same Event deduplicate deterministically.
/// Different bands with the same eventId remain separate.
/// Accidental collisions between public events and band events remain separate.
String getDeduplicationKey(SubRequest item) {
  final kind = classifyMapItem(item);
  if (kind == MapItemKind.event || kind == MapItemKind.eventSchedulePart) {
    final eventId = item.eventId ?? item.extraFields['eventId']?.toString() ?? item.id ?? '';
    final partId = item.extraFields['schedulePartId']?.toString() ?? '';
    final bandId = (item.bandId ?? item.extraFields['bandId'] ?? item.extraFields['originBandId'] ?? item.extraFields['canonicalBandId'])?.toString().trim();

    if (bandId != null && bandId.isNotEmpty) {
      // Band-scoped event identity
      return 'event_dedup:band:$bandId:$eventId:$partId';
    } else {
      // Pure public calendar event
      return 'event_dedup:public:$eventId:$partId';
    }
  }
  if (kind == MapItemKind.staffingRequest || kind == MapItemKind.newMemberRequest) {
    final subId = item.subRequestId ?? item.id ?? '';
    return 'sub_dedup:$subId';
  }
  return getNamespacedMarkerId(item);
}

/// Returns the primary [MapCategory] for a given [MapItemKind].
MapCategory getCategoryForKind(MapItemKind kind) {
  switch (kind) {
    case MapItemKind.event:
    case MapItemKind.eventSchedulePart:
    case MapItemKind.musicPromotion:
    case MapItemKind.liveBroadcast:
    case MapItemKind.mockDemo:
      return MapCategory.music;
    case MapItemKind.staffingRequest:
    case MapItemKind.newMemberRequest:
      return MapCategory.subAndMember;
  }
}

/// Evaluates whether an item's start date falls within the local calendar week of [now].
/// Uses standard Monday-to-Sunday calendar boundaries.
/// Returns false if the item has no date or is undated.
bool isDateWithinLocalCalendarWeek(SubRequest item, {DateTime? now}) {
  final current = now ?? DateTime.now();

  DateTime? eventDate;
  if (item.extraFields['startDateTime'] != null) {
    eventDate = parseDateTime(item.extraFields['startDateTime']);
  }
  if (eventDate == null && item.date != null && item.date!.trim().isNotEmpty) {
    final d = item.date!.trim();
    if (d.contains('T')) {
      eventDate = parseDateTime(d);
    } else {
      eventDate = DateTime.tryParse(d);
    }
  }

  // Undated promotion pins or items missing a date never match "This Week"
  if (eventDate == null) {
    return false;
  }

  final localDate = eventDate.toLocal();
  final localNow = current.toLocal();

  // Calculate local week start (Monday 00:00:00) and end (Sunday 23:59:59.999)
  final startOfWeek = DateTime(localNow.year, localNow.month, localNow.day - (localNow.weekday - 1));
  final endOfWeek = DateTime(localNow.year, localNow.month, localNow.day + (7 - localNow.weekday), 23, 59, 59, 999);

  final isInWeek = !localDate.isBefore(startOfWeek) && !localDate.isAfter(endOfWeek);
  if (!isInWeek) return false;

  // Must also be currently visible (not already ended/expired)
  return isMapEventVisible(item, now: current);
}

/// Pure filtering policy function for Map View.
/// Evaluates whether [item] matches the active [mainCategory], [subCategory], and [instrumentQuery].
bool isItemMatchingFilter({
  required SubRequest item,
  required String? mainCategory,
  required String? subCategory,
  required String instrumentQuery,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();

  // 1. Client-side visibility check: expired/past items are hidden
  if (!isMapEventVisible(item, now: current)) {
    return false;
  }

  final kind = classifyMapItem(item);

  // 2. Primary Category Filter
  if (mainCategory == 'Music') {
    // Show: Events, schedule parts, Music Promotion pins, active Go Live broadcasts, mock demos
    // Do NOT show: staffing or new member requests
    if (kind == MapItemKind.staffingRequest || kind == MapItemKind.newMemberRequest) {
      return false;
    }

    // Secondary subfilter under Music
    if (subCategory != null && subCategory != 'All Music') {
      final eventType = MapEventTypeHelper.getEventType(item);
      if (subCategory == 'Gigs / Rehearsals') {
        final isGigOrRehearsal = eventType == MapEventType.gigConcert ||
            eventType == MapEventType.concert ||
            eventType == MapEventType.rehearsal;
        if (!isGigOrRehearsal) return false;
      } else if (subCategory == 'Gig' || subCategory == 'Gigs') {
        if (eventType != MapEventType.gigConcert) return false;
      } else if (subCategory == 'Concert' || subCategory == 'Concerts') {
        if (eventType != MapEventType.concert) return false;
      } else if (subCategory == 'Rehearsal' || subCategory == 'Rehearsals') {
        if (eventType != MapEventType.rehearsal) return false;
      } else if (subCategory == 'Jam Sessions' || subCategory == 'Jam Session') {
        if (eventType != MapEventType.jamSession) return false;
      } else if (subCategory == 'Demos / Recordings' || subCategory == 'Recorded Music') {
        final isDemoOrRecording = kind == MapItemKind.musicPromotion ||
            eventType == MapEventType.recordedMusic ||
            eventType == MapEventType.jamSession;
        if (!isDemoOrRecording) return false;
      } else if (subCategory == 'Live Gigs / Rehearsals') {
        final isEligible = eventType == MapEventType.gigConcert ||
            eventType == MapEventType.concert ||
            eventType == MapEventType.rehearsal;
        if (!isEligible || !isMapEventCurrentlyActive(item, now: current)) {
          return false;
        }
      }
    }
    return true;
  }

  if (mainCategory == 'Sub & Member Search') {
    // Show: eligible open Substitute requests and New Member requests
    // Do NOT show: Events, Music Promotion pins, Go Live broadcasts
    if (kind != MapItemKind.staffingRequest && kind != MapItemKind.newMemberRequest) {
      return false;
    }

    // Secondary subfilter under Sub & Member Search
    if (subCategory != null &&
        subCategory != 'All Sub/Member' &&
        subCategory != 'All Sub & Member') {
      if (subCategory == 'Substitutes' || subCategory == 'Substitute' || subCategory == 'Subs') {
        if (kind != MapItemKind.staffingRequest) return false;
      } else if (subCategory == 'New Members' || subCategory == 'New Member') {
        if (kind != MapItemKind.newMemberRequest) return false;
      } else if (subCategory == 'Paid Gigs' || subCategory == 'Paid') {
        if (!item.isPaid && item.payAmount == null) return false;
      }
    }

    // Instrument search query
    if (instrumentQuery.trim().isNotEmpty) {
      final q = instrumentQuery.trim().toLowerCase();
      final vp = (item.voicePart ?? '').toLowerCase();
      final r = (item.role ?? '').toLowerCase();
      final d = (item.description ?? '').toLowerCase();
      if (!vp.contains(q) && !r.contains(q) && !d.contains(q)) {
        return false;
      }
    }

    return true;
  }

  if (mainCategory == 'This Week' || mainCategory == 'THIS WEEK') {
    // Show only items within current local calendar week
    return isDateWithinLocalCalendarWeek(item, now: current);
  }

  // When no category is selected ('All' mode):
  return true;
}

/// Processes raw feeds into unified, deduplicated, and collision-resolved marker items.
///
/// Rules:
/// 1. Group staffing requests with the same `requestGroupId` into ONE visual marker.
/// 2. Multi-part events render one marker per schedule part; container parent is omitted.
/// 3. Public and private projections of the same Event deduplicate deterministically.
/// 4. Separate items at the exact same location are separated via deterministic radial offsets.
List<UnifiedMapMarkerItem> processUnifiedMapItems({
  required List<SubRequest> staffingAndPromoItems,
  required List<SubRequest> eventItems,
  List<SubRequest> liveBroadcastItems = const [],
  List<SubRequest> mockItems = const [],
  DateTime? now,
}) {
  final current = now ?? DateTime.now();

  // Combine all items
  final allCandidates = <SubRequest>[
    ...staffingAndPromoItems,
    ...eventItems,
    ...liveBroadcastItems,
    ...mockItems,
  ];

  // 1. Filter out invalid coordinates and expired items
  final validItems = allCandidates.where((item) {
    if (item.latitude == null || item.longitude == null) return false;
    if (!item.latitude!.isFinite || !item.longitude!.isFinite) return false;
    if (item.latitude! < -90.0 || item.latitude! > 90.0) return false;
    if (item.longitude! < -180.0 || item.longitude! > 180.0) return false;
    return isMapEventVisible(item, now: current);
  }).toList();

  // 2. Deterministic Deduplication:
  // Public/private copies of the same Event deduplicate into one entry (preferring private band projection).
  final dedupedMap = <String, SubRequest>{};
  for (final item in validItems) {
    final key = getDeduplicationKey(item);
    if (!dedupedMap.containsKey(key)) {
      dedupedMap[key] = item;
    } else {
      final existing = dedupedMap[key]!;
      // Prefer private band projection over public projection
      final existingIsPublic = existing.extraFields['eventSource'] == 'public_calendar' || (existing.id ?? '').startsWith('event:public:');
      final newIsPrivate = item.extraFields['eventSource'] == 'private_band' || (item.id ?? '').startsWith('event:private:');
      if (existingIsPublic && newIsPrivate) {
        dedupedMap[key] = item;
      }
    }
  }

  final dedupedList = dedupedMap.values.toList();

  // 3. Multi-part Event Parent Omission:
  // If schedule parts exist for an event, omit the standalone container parent marker.
  final eventsWithParts = <String>{};
  for (final item in dedupedList) {
    final kind = classifyMapItem(item);
    if (kind == MapItemKind.eventSchedulePart) {
      final evId = item.eventId ?? item.extraFields['eventId']?.toString();
      if (evId != null && evId.isNotEmpty) {
        eventsWithParts.add(evId);
      }
    }
  }

  final itemsFilteredOfParentEvents = dedupedList.where((item) {
    final kind = classifyMapItem(item);
    if (kind == MapItemKind.event) {
      final evId = item.eventId ?? item.extraFields['eventId']?.toString();
      if (evId != null && eventsWithParts.contains(evId)) {
        return false; // Parent container omitted because schedule parts exist
      }
    }
    return true;
  }).toList();

  // 4. Staffing Grouping:
  // Multiple slots with the same requestGroupId within the same band/creator scope form ONE visual marker.
  // Independent bands/creators with colliding requestGroupId strings are kept strictly isolated.
  final groupedStaffing = <String, List<SubRequest>>{};
  final standaloneItems = <SubRequest>[];

  for (final item in itemsFilteredOfParentEvents) {
    final kind = classifyMapItem(item);
    if (kind == MapItemKind.staffingRequest || kind == MapItemKind.newMemberRequest) {
      final groupId = item.requestGroupId?.trim();
      if (groupId != null && groupId.isNotEmpty) {
        final ownerScope = (item.bandId ?? item.creatorUserId ?? '').trim();
        final groupKey = ownerScope.isNotEmpty ? '${ownerScope}_$groupId' : groupId;
        groupedStaffing.putIfAbsent(groupKey, () => []).add(item);
        continue;
      }
    }
    standaloneItems.add(item);
  }

  final preCollisionMarkers = <UnifiedMapMarkerItem>[];

  // Add grouped staffing items
  groupedStaffing.forEach((groupKey, groupMembers) {
    // Partition groupMembers by geographic proximity so differing locations never collapse into one pin
    final clusters = <LatLng, List<SubRequest>>{};
    for (final member in groupMembers) {
      final pos = LatLng(member.latitude!, member.longitude!);
      LatLng? matchedPos;
      for (final cPos in clusters.keys) {
        if ((cPos.latitude - pos.latitude).abs() < 0.02 && (cPos.longitude - pos.longitude).abs() < 0.02) {
          matchedPos = cPos;
          break;
        }
      }
      if (matchedPos != null) {
        clusters[matchedPos]!.add(member);
      } else {
        clusters[pos] = [member];
      }
    }

    clusters.forEach((clusterPos, members) {
      // Sort members deterministically so primary gig is always the same
      members.sort((a, b) => (a.id ?? '').compareTo(b.id ?? ''));
      final primary = members.first;
      final subKey = clusters.length > 1
          ? '${groupKey}_${clusterPos.latitude.toStringAsFixed(2)}_${clusterPos.longitude.toStringAsFixed(2)}'
          : groupKey;
      final markerId = 'reqgrp_$subKey';
      final kind = classifyMapItem(primary);
      final origPos = LatLng(primary.latitude!, primary.longitude!);
      final renderedPos = computeStableMarkerPosition(origPos, markerId);
      preCollisionMarkers.add(UnifiedMapMarkerItem(
        id: markerId,
        primaryGig: primary,
        groupedGigs: members,
        kind: kind,
        position: renderedPos,
        originalPosition: origPos,
        isLive: isMapEventCurrentlyActive(primary, now: current),
      ));
    });
  });

  // Add standalone items
  for (final item in standaloneItems) {
    final markerId = getNamespacedMarkerId(item);
    final kind = classifyMapItem(item);
    final origPos = LatLng(item.latitude!, item.longitude!);
    final renderedPos = computeStableMarkerPosition(origPos, markerId);
    preCollisionMarkers.add(UnifiedMapMarkerItem(
      id: markerId,
      primaryGig: item,
      groupedGigs: [item],
      kind: kind,
      position: renderedPos,
      originalPosition: origPos,
      isLive: isMapEventCurrentlyActive(item, now: current),
    ));
  }

  // Sort final marker list deterministically by ID
  preCollisionMarkers.sort((a, b) => a.id.compareTo(b.id));
  return preCollisionMarkers;
}

/// Dual 32-bit deterministic hash mixer for continuous marker offset calculations.
class MarkerHash {
  final int hashA;
  final int hashB;
  const MarkerHash(this.hashA, this.hashB);

  factory MarkerHash.fromId(String id) {
    // 32-bit FNV-1a for hashA
    var a = 0x811c9dc5;
    for (var i = 0; i < id.length; i++) {
      a ^= id.codeUnitAt(i);
      a = (a * 0x01000193) & 0xFFFFFFFF;
    }

    // Secondary Murmur3-like mix for hashB
    var b = 0x9e3779b9;
    for (var i = id.length - 1; i >= 0; i--) {
      b ^= id.codeUnitAt(i);
      b = (b * 0x85ebca6b) & 0xFFFFFFFF;
      b ^= (b >> 13);
      b = (b * 0xc2b2ae35) & 0xFFFFFFFF;
      b ^= (b >> 16);
    }

    return MarkerHash(a, b);
  }
}

/// Computes a stable, deterministic polar offset for an item at a shared location.
/// Derived strictly from [originalPosition] and [markerId].
/// Completely independent of list ordering, item count, or other items.
LatLng computeStableMarkerPosition(LatLng originalPosition, String markerId) {
  final hashes = MarkerHash.fromId(markerId);

  // Continuous angle in [0, 2*pi) over 32-bit integer space (billions of discrete angles)
  final angle = ((hashes.hashA & 0x7FFFFFFF) / 0x7FFFFFFF) * (2 * math.pi);

  // Continuous radius between 12m and 28m
  const double minRadius = 0.00012; // ~13 meters
  const double maxRadius = 0.00028; // ~31 meters
  final radius = minRadius + (((hashes.hashB & 0x7FFFFFFF) / 0x7FFFFFFF) * (maxRadius - minRadius));

  final latOffset = radius * math.cos(angle);
  final cosLat = math.cos(originalPosition.latitude * math.pi / 180.0);
  final lngOffset = (cosLat.abs() > 0.0001)
      ? (radius / cosLat) * math.sin(angle)
      : radius * math.sin(angle);

  return LatLng(
    originalPosition.latitude + latOffset,
    originalPosition.longitude + lngOffset,
  );
}

/// Backward compatibility alias for [computeStableMarkerPosition].
LatLng computeStableCollisionOffset(LatLng originalPosition, String markerId) {
  return computeStableMarkerPosition(originalPosition, markerId);
}

/// Centralized bitmap cache for Map View marker icons.
/// Keyed by kind, eventType, live active/static, blink phase, color/theme, and scale.
class UnifiedMarkerIconCache {
  static final UnifiedMarkerIconCache instance = UnifiedMarkerIconCache._();
  UnifiedMarkerIconCache._();

  static const int maxCacheEntries = 256;
  final Map<String, BitmapDescriptor> _cache = {};
  int _bitmapGenerationCount = 0;

  int get generationCount => _bitmapGenerationCount;
  int get cachedIconCount => _cache.length;

  void resetStats() {
    _bitmapGenerationCount = 0;
  }

  void clear() {
    _cache.clear();
    _bitmapGenerationCount = 0;
  }

  static String buildCacheKey({
    required MapItemKind kind,
    required MapEventType eventType,
    required bool isLive,
    required bool blinkPhase,
    required bool isDarkTheme,
    double scale = 1.0,
  }) {
    return '${kind.name}:${eventType.name}:$isLive:$blinkPhase:$isDarkTheme:$scale';
  }

  Future<BitmapDescriptor> getOrCreateIcon({
    required MapItemKind kind,
    required MapEventType eventType,
    required bool isLive,
    required bool blinkPhase,
    required bool isDarkTheme,
    double scale = 1.0,
    required Future<BitmapDescriptor> Function() generator,
  }) async {
    final key = buildCacheKey(
      kind: kind,
      eventType: eventType,
      isLive: isLive,
      blinkPhase: blinkPhase,
      isDarkTheme: isDarkTheme,
      scale: scale,
    );

    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    _bitmapGenerationCount++;
    final icon = await generator();
    putIcon(key, icon);
    return icon;
  }

  BitmapDescriptor? getCachedIcon({
    required MapItemKind kind,
    required MapEventType eventType,
    required bool isLive,
    required bool blinkPhase,
    required bool isDarkTheme,
    double scale = 1.0,
  }) {
    final key = buildCacheKey(
      kind: kind,
      eventType: eventType,
      isLive: isLive,
      blinkPhase: blinkPhase,
      isDarkTheme: isDarkTheme,
      scale: scale,
    );
    return _cache[key];
  }

  void putIcon(String key, BitmapDescriptor icon) {
    if (_cache.length >= maxCacheEntries && !_cache.containsKey(key)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = icon;
  }
}

