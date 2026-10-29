import '../utils/currency_formatter.dart';
import 'canonical_location.dart';

class SubRequest {
  final String? id;
  final String? subRequestId;
  final String? slotId;
  final String? creatorUserId;
  final String? userId;
  final String? voicePart;
  final String? location;
  final String? city;
  final String? startTime;
  final String? endTime;
  final String? description;
  final String? date;
  final String? role;
  final String? requestType;
  final bool isPaid;
  final String? bandName;
  final String? rehearsalDayOfWeek;
  final bool isSelected;
  final int responseCount;
  final String? formattedTimeRange;
  final String? dateLabel;
  final String? level;
  final String? style;
  final Map<String, bool> responses;
  final double? latitude;
  final double? longitude;
  final LocationPrecision? locationPrecision;
  final String? placeId;
  final LocationResolutionStatus? locationStatus;
  final List<String>? targetUserIds;
  final String? eventId;
  final String? bandId;
  final String? replacedMemberId;
  final String? replacedMemberName;
  final String status; // 'draft', 'published', 'assigned', 'closed', 'cancelled'
  final String? assignedUserId;
  final String? assignedUserName;
  final int? assignedAt;
  final int? createdAt;
  final String? searchSource; // 'favorites' or 'search_all'
  final String? requestGroupId;
  final int? eventSequence;
  final String? eventTitle;
  final int? payAmount; // Exact integer whole currency units (e.g. 1500 SEK)
  final int? payAmountMinor; // Exact integer minor currency units (e.g. 150000 öre)
  final String? currency; // ISO currency code, e.g. 'SEK'
  final String? payDetails; // Payment-related information/details
  final Map<String, dynamic> extraFields;

  SubRequest({
    this.id,
    this.subRequestId,
    this.slotId,
    this.creatorUserId,
    this.userId,
    this.voicePart,
    this.location,
    this.city,
    this.startTime,
    this.endTime,
    this.description,
    this.date,
    this.role,
    this.requestType,
    this.isPaid = false,
    this.bandName,
    this.rehearsalDayOfWeek,
    this.isSelected = false,
    this.responseCount = 0,
    this.formattedTimeRange,
    this.dateLabel,
    this.level,
    this.style,
    this.responses = const {},
    this.latitude,
    this.longitude,
    this.locationPrecision,
    this.placeId,
    this.locationStatus,
    this.targetUserIds,
    this.eventId,
    this.bandId,
    this.replacedMemberId,
    this.replacedMemberName,
    this.status = 'published',
    this.assignedUserId,
    this.assignedUserName,
    this.assignedAt,
    this.createdAt,
    this.searchSource,
    this.requestGroupId,
    this.eventSequence,
    this.eventTitle,
    int? payAmount,
    int? payAmountMinor,
    this.currency,
    this.payDetails,
    this.extraFields = const {},
  })  : payAmount = payAmount ?? (payAmountMinor != null ? payAmountMinor ~/ 100 : null),
        payAmountMinor = payAmountMinor ?? (payAmount != null ? payAmount * 100 : null);

  factory SubRequest.fromJson(Map<dynamic, dynamic> json, String keyId) {
    final responsesRaw = json['Responses'];
    final Map<String, bool> parsedResponses = {};
    if (responsesRaw is Map) {
      responsesRaw.forEach((k, v) {
        parsedResponses[k.toString()] = v == true;
      });
    }

    final parsedCity = json['City']?.toString() ?? json['city']?.toString();
    final canonicalLoc = CanonicalLocation.fromJson(json);
    final parsedLat = canonicalLoc.latitude;
    final parsedLng = canonicalLoc.longitude;
    final parsedPrecision = canonicalLoc.precision;
    final parsedPlaceId = canonicalLoc.placeId;
    final parsedLocStatus = canonicalLoc.status;

    final targetUserIdsRaw = json['TargetUserIds'];
    List<String>? parsedTargetUserIds;
    if (targetUserIdsRaw is List) {
      parsedTargetUserIds = targetUserIdsRaw.map((e) => e.toString()).toList();
    } else if (targetUserIdsRaw is Map) {
      parsedTargetUserIds = targetUserIdsRaw.values.map((e) => e.toString()).toList();
    }

    final isSelected = json['IsSelected'] == true || json['isSelected'] == true;
    final explicitStatus = json['Status']?.toString() ?? json['status']?.toString();
    final derivedStatus = explicitStatus ?? (isSelected ? 'assigned' : 'published');

    final explicitSource = json['SearchSource']?.toString();
    final derivedSource = explicitSource ??
        (parsedTargetUserIds != null && parsedTargetUserIds.isNotEmpty
            ? 'favorites'
            : 'search_all');

    const knownKeys = {
      'id',
      'SubRequestId',
      'SlotId',
      'CreatorUserId',
      'UserId',
      'VoicePart',
      'Location',
      'StartTime',
      'EndTime',
      'Description',
      'Date',
      'Role',
      'IsPaid',
      'BandName',
      'RehearsalDayOfWeek',
      'IsSelected',
      'ResponseCount',
      'FormattedTimeRange',
      'DateLabel',
      'Level',
      'Style',
      'Responses',
      'Latitude',
      'Longitude',
      'TargetUserIds',
      'LocationPrecision',
      'locationPrecision',
      'PlaceId',
      'placeId',
      'LocationStatus',
      'locationStatus',
      'lat',
      'lng',
      'lon',
      'Lat',
      'Lng',
      'Lon',
      'eventId',
      'bandId',
      'EventId',
      'BandId',
      'ReplacedMemberId',
      'ReplacedMemberName',
      'Status',
      'AssignedUserId',
      'AssignedUserName',
      'AssignedAt',
      'CreatedAt',
      'SearchSource',
      'RequestGroupId',
      'requestGroupId',
      'EventSequence',
      'eventSequence',
      'EventTitle',
      'eventTitle',
      'PayAmount',
      'payAmount',
      'Currency',
      'currency',
      'PayDetails',
      'payDetails',
      'RequestType',
      'requestType',
    };

    final Map<String, dynamic> extra = {};
    json.forEach((k, v) {
      final keyStr = k.toString();
      if (!knownKeys.contains(keyStr)) {
        extra[keyStr] = v;
      }
    });

    final rawPayAmountMinor = json['PayAmountMinor'] ?? json['payAmountMinor'];
    final parsedPayAmountMinor = rawPayAmountMinor is int
        ? rawPayAmountMinor
        : int.tryParse(rawPayAmountMinor?.toString() ?? '');

    final rawPayAmount = json['PayAmount'] ?? json['payAmount'];
    final parsedLegacyPayAmount = rawPayAmount is int
        ? rawPayAmount
        : int.tryParse(rawPayAmount?.toString() ?? '');

    // Canonical PayAmountMinor wins if both exist; fallback to legacy PayAmount * 100
    final effectiveMinor = parsedPayAmountMinor ?? (parsedLegacyPayAmount != null ? parsedLegacyPayAmount * 100 : null);

    final isNewMember = SubRequest.isNewMemberRecord(json);
    final String derivedRequestType;
    if (isNewMember) {
      derivedRequestType = 'New Member';
    } else {
      final rawRequestType = json['RequestType']?.toString() ?? json['requestType']?.toString();
      if (rawRequestType != null && rawRequestType.trim().isNotEmpty) {
        final norm = rawRequestType.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
        if (norm == 'other') {
          derivedRequestType = 'Other';
        } else {
          derivedRequestType = 'Substitute';
        }
      } else {
        derivedRequestType = 'Substitute';
      }
    }

    return SubRequest(
      id: keyId,
      subRequestId: json['SubRequestId']?.toString() ?? json['subRequestId']?.toString() ?? keyId,
      slotId: json['SlotId']?.toString() ?? json['slotId']?.toString() ?? json['SubRequestId']?.toString() ?? json['subRequestId']?.toString() ?? keyId,
      creatorUserId: json['CreatorUserId']?.toString() ?? json['creatorUserId']?.toString(),
      userId: json['UserId']?.toString() ?? json['userId']?.toString(),
      voicePart: json['VoicePart']?.toString() ?? json['voicePart']?.toString() ?? json['Instrument']?.toString() ?? json['instrument']?.toString(),
      location: json['Location']?.toString() ?? json['location']?.toString(),
      city: parsedCity,
      startTime: json['StartTime']?.toString() ?? json['startTime']?.toString(),
      endTime: json['EndTime']?.toString() ?? json['endTime']?.toString(),
      description: json['Description']?.toString() ?? json['description']?.toString(),
      date: json['Date']?.toString() ?? json['date']?.toString(),
      role: json['Role']?.toString() ?? json['role']?.toString(),
      requestType: derivedRequestType,
      isPaid: json['IsPaid'] == true || json['isPaid'] == true,
      bandName: json['BandName']?.toString() ?? json['bandName']?.toString(),
      rehearsalDayOfWeek: json['RehearsalDayOfWeek']?.toString() ?? json['rehearsalDayOfWeek']?.toString(),
      isSelected: isSelected,
      responseCount: json['ResponseCount'] is int
          ? json['ResponseCount'] as int
          : (json['responseCount'] is int ? json['responseCount'] as int : parsedResponses.length),
      formattedTimeRange: json['FormattedTimeRange']?.toString() ?? json['formattedTimeRange']?.toString(),
      dateLabel: json['DateLabel']?.toString() ?? json['dateLabel']?.toString(),
      level: json['Level']?.toString() ?? json['level']?.toString(),
      style: json['Style']?.toString() ?? json['style']?.toString(),
      responses: parsedResponses,
      latitude: parsedLat,
      longitude: parsedLng,
      locationPrecision: parsedPrecision,
      placeId: parsedPlaceId,
      locationStatus: parsedLocStatus,
      targetUserIds: parsedTargetUserIds,
      eventId: json['eventId']?.toString() ?? json['EventId']?.toString(),
      bandId: json['bandId']?.toString() ?? json['BandId']?.toString(),
      replacedMemberId: json['ReplacedMemberId']?.toString() ?? json['replacedMemberId']?.toString(),
      replacedMemberName: json['ReplacedMemberName']?.toString() ?? json['replacedMemberName']?.toString(),
      status: derivedStatus,
      assignedUserId: json['AssignedUserId']?.toString() ?? json['assignedUserId']?.toString(),
      assignedUserName: json['AssignedUserName']?.toString() ?? json['assignedUserName']?.toString(),
      assignedAt: json['AssignedAt'] is int
          ? json['AssignedAt'] as int
          : (json['assignedAt'] is int
              ? json['assignedAt'] as int
              : int.tryParse(json['AssignedAt']?.toString() ?? json['assignedAt']?.toString() ?? '')),
      createdAt: json['CreatedAt'] is int
          ? json['CreatedAt'] as int
          : (json['createdAt'] is int
              ? json['createdAt'] as int
              : int.tryParse(json['CreatedAt']?.toString() ?? json['createdAt']?.toString() ?? '')),
      searchSource: derivedSource,
      requestGroupId: json['RequestGroupId']?.toString() ?? json['requestGroupId']?.toString(),
      eventSequence: json['EventSequence'] is int
          ? json['EventSequence'] as int
          : (json['eventSequence'] is int
              ? json['eventSequence'] as int
              : int.tryParse(json['EventSequence']?.toString() ?? json['eventSequence']?.toString() ?? '')),
      eventTitle: json['EventTitle']?.toString() ?? json['eventTitle']?.toString(),
      payAmountMinor: effectiveMinor,
      currency: json['Currency']?.toString() ?? json['currency']?.toString() ?? (json['IsPaid'] == true || json['isPaid'] == true ? 'SEK' : null),
      payDetails: json['PayDetails']?.toString() ?? json['payDetails']?.toString(),
      extraFields: extra,
    );
  }

  String get formattedPayAmount {
    if (!isPaid) return '';
    final minorUnits = payAmountMinor ?? ((payAmount ?? 0) * 100);
    if (minorUnits <= 0) return 'Paid';
    final curr = currency ?? 'SEK';
    final formatted = CurrencyFormatter.formatMinorUnits(
      minorUnits,
      currencyCode: curr,
    );
    return 'Paid · $formatted';
  }

  String? get resolvedEventType =>
      extraFields['eventType']?.toString() ??
      extraFields['EventType']?.toString();

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{...extraFields};
    map.addAll({
      'SubRequestId': subRequestId,
      'subRequestId': subRequestId,
      'SlotId': slotId ?? subRequestId,
      'slotId': slotId ?? subRequestId,
      'CreatorUserId': creatorUserId,
      'creatorUserId': creatorUserId,
      'UserId': userId,
      'userId': userId,
      'VoicePart': voicePart,
      'voicePart': voicePart,
      'Location': location,
      'location': location,
      if (city != null) 'City': city,
      'StartTime': startTime,
      'EndTime': endTime,
      'Description': description,
      'Date': date,
      'Role': role,
      if (requestType != null) 'RequestType': requestType,
      'IsPaid': isPaid,
      if (payAmountMinor != null) 'PayAmountMinor': payAmountMinor,
      if (currency != null) 'Currency': currency,
      'BandName': bandName,
      'RehearsalDayOfWeek': rehearsalDayOfWeek,
      'IsSelected': isSelected,
      'ResponseCount': responseCount,
      'FormattedTimeRange': formattedTimeRange,
      'DateLabel': dateLabel,
      'Level': level,
      'Style': style,
      'Responses': responses,
      'Latitude': latitude,
      'latitude': latitude,
      'Longitude': longitude,
      'longitude': longitude,
      if (locationPrecision != null) 'LocationPrecision': locationPrecision!.name,
      if (locationPrecision != null) 'locationPrecision': locationPrecision!.name,
      if (placeId != null && placeId!.isNotEmpty) 'PlaceId': placeId,
      if (placeId != null && placeId!.isNotEmpty) 'placeId': placeId,
      if (locationStatus != null) 'LocationStatus': locationStatus!.name,
      if (locationStatus != null) 'locationStatus': locationStatus!.name,
      'TargetUserIds': targetUserIds,
      'targetUserIds': targetUserIds,
      'eventId': eventId,
      'bandId': bandId,
      if (replacedMemberId != null) 'ReplacedMemberId': replacedMemberId,
      if (replacedMemberName != null) 'ReplacedMemberName': replacedMemberName,
      'Status': status,
      'status': status,
      if (assignedUserId != null) 'AssignedUserId': assignedUserId,
      if (assignedUserName != null) 'AssignedUserName': assignedUserName,
      if (assignedAt != null) 'AssignedAt': assignedAt,
      if (createdAt != null) 'CreatedAt': createdAt,
      if (searchSource != null) 'SearchSource': searchSource,
      if (requestGroupId != null) 'RequestGroupId': requestGroupId,
      if (eventSequence != null) 'EventSequence': eventSequence,
      if (eventTitle != null) 'EventTitle': eventTitle,
      if (payAmount != null) 'PayAmount': payAmount,
      if (currency != null) 'Currency': currency,
      if (payDetails != null && payDetails!.trim().isNotEmpty) 'PayDetails': payDetails,
    });
    return map;
  }

  SubRequest copyWith({
    String? id,
    String? subRequestId,
    String? slotId,
    String? creatorUserId,
    String? userId,
    String? voicePart,
    String? location,
    String? city,
    String? startTime,
    String? endTime,
    String? description,
    String? date,
    String? role,
    String? requestType,
    bool? isPaid,
    String? bandName,
    String? rehearsalDayOfWeek,
    bool? isSelected,
    int? responseCount,
    String? formattedTimeRange,
    String? dateLabel,
    String? level,
    String? style,
    Map<String, bool>? responses,
    double? latitude,
    double? longitude,
    LocationPrecision? locationPrecision,
    String? placeId,
    LocationResolutionStatus? locationStatus,
    List<String>? targetUserIds,
    String? eventId,
    String? bandId,
    String? replacedMemberId,
    String? replacedMemberName,
    String? status,
    String? assignedUserId,
    String? assignedUserName,
    int? assignedAt,
    int? createdAt,
    String? searchSource,
    String? requestGroupId,
    int? eventSequence,
    String? eventTitle,
    int? payAmount,
    String? currency,
    String? payDetails,
    Map<String, dynamic>? extraFields,
  }) {
    return SubRequest(
      id: id ?? this.id,
      subRequestId: subRequestId ?? this.subRequestId,
      slotId: slotId ?? this.slotId,
      creatorUserId: creatorUserId ?? this.creatorUserId,
      userId: userId ?? this.userId,
      voicePart: voicePart ?? this.voicePart,
      location: location ?? this.location,
      city: city ?? this.city,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      description: description ?? this.description,
      date: date ?? this.date,
      role: role ?? this.role,
      requestType: requestType ?? this.requestType,
      isPaid: isPaid ?? this.isPaid,
      bandName: bandName ?? this.bandName,
      rehearsalDayOfWeek: rehearsalDayOfWeek ?? this.rehearsalDayOfWeek,
      isSelected: isSelected ?? this.isSelected,
      responseCount: responseCount ?? this.responseCount,
      formattedTimeRange: formattedTimeRange ?? this.formattedTimeRange,
      dateLabel: dateLabel ?? this.dateLabel,
      level: level ?? this.level,
      style: style ?? this.style,
      responses: responses ?? this.responses,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationPrecision: locationPrecision ?? this.locationPrecision,
      placeId: placeId ?? this.placeId,
      locationStatus: locationStatus ?? this.locationStatus,
      targetUserIds: targetUserIds ?? this.targetUserIds,
      eventId: eventId ?? this.eventId,
      bandId: bandId ?? this.bandId,
      replacedMemberId: replacedMemberId ?? this.replacedMemberId,
      replacedMemberName: replacedMemberName ?? this.replacedMemberName,
      status: status ?? this.status,
      assignedUserId: assignedUserId ?? this.assignedUserId,
      assignedUserName: assignedUserName ?? this.assignedUserName,
      assignedAt: assignedAt ?? this.assignedAt,
      createdAt: createdAt ?? this.createdAt,
      searchSource: searchSource ?? this.searchSource,
      requestGroupId: requestGroupId ?? this.requestGroupId,
      eventSequence: eventSequence ?? this.eventSequence,
      eventTitle: eventTitle ?? this.eventTitle,
      payAmount: payAmount ?? this.payAmount,
      currency: currency ?? this.currency,
      payDetails: payDetails ?? this.payDetails,
      extraFields: extraFields ?? this.extraFields,
    );
  }

  /// Optional audio preview snippet URL or local asset path
  String? get audioSnippetUrl => (extraFields['audioSnippetUrl'] ??
          extraFields['audioUrl'] ??
          extraFields['audioAssetPath'])
      ?.toString();

  /// Title or descriptor for the attached audio snippet
  String? get audioSnippetTitle =>
      (extraFields['audioSnippetTitle'] ?? extraFields['audioTitle'])
          ?.toString();

  /// Whether an audio preview snippet is available
  bool get hasAudioSnippet =>
      audioSnippetUrl != null && audioSnippetUrl!.trim().isNotEmpty;

  /// Optional venue or performance hall name (e.g. Fasching, Stampen, Nefertiti)
  String? get venue =>
      (extraFields['venue'] ?? extraFields['Venue'] ?? extraFields['venueName'])
          ?.toString();

  /// Canonical identifier for map targeting, selection, markers, and audio focus.
  /// Prioritizes [id], falls back to [subRequestId]. Returns null if neither is present or non-empty.
  String? get canonicalTargetId {
    final candidateId = id?.trim();
    if (candidateId != null && candidateId.isNotEmpty) return candidateId;
    final candidateSub = subRequestId?.trim();
    if (candidateSub != null && candidateSub.isNotEmpty) return candidateSub;
    return null;
  }

  /// Whether this is an ordinary Map View pin that should not appear in staffing flows.
  bool get isMapOnlyPin =>
      extraFields['NotificationMode'] == 'map_pin' ||
      extraFields['notificationMode'] == 'map_pin';

  bool get isMapPin => isMapOnlyPin;

  /// Centralized normalized classifier recognizing all New Member representation variants
  /// without misclassifying Substitute, Other, direct invitations, or map pins.
  static bool isNewMemberRecord(dynamic item) {
    if (item == null) return false;

    if (item is SubRequest) {
      final mode = (item.extraFields['NotificationMode'] ?? item.extraFields['notificationMode'])?.toString().trim().toLowerCase();
      if (mode == 'map_pin') return false;

      final reqType = item.requestType?.trim();
      if (reqType != null && reqType.isNotEmpty) {
        final clean = reqType.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
        if (clean == 'newmember') return true;
        if (clean == 'substitute' || clean == 'sub' || clean == 'other') return false;
      }

      final role = item.role?.trim();
      if (role != null && role.isNotEmpty) {
        final cleanRole = role.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
        if (cleanRole == 'newmember') return true;
      }

      final eventType = (item.extraFields['eventType'] ?? item.extraFields['EventType'])?.toString().trim();
      if (eventType != null && eventType.isNotEmpty) {
        final cleanEvent = eventType.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
        if (cleanEvent == 'newmember') return true;
      }

      return false;
    }

    if (item is Map) {
      final mode = (item['NotificationMode'] ?? item['notificationMode'])?.toString().trim().toLowerCase();
      if (mode == 'map_pin') return false;

      final rawReqType = (item['RequestType'] ?? item['requestType'])?.toString().trim();
      if (rawReqType != null && rawReqType.isNotEmpty) {
        final clean = rawReqType.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
        if (clean == 'newmember') return true;
        if (clean == 'substitute' || clean == 'sub' || clean == 'other') return false;
      }

      final rawRole = (item['Role'] ?? item['role'])?.toString().trim();
      if (rawRole != null && rawRole.isNotEmpty) {
        final cleanRole = rawRole.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
        if (cleanRole == 'newmember') return true;
      }

      final extra = item['extraFields'] is Map ? item['extraFields'] as Map : null;
      final rawEvent = (item['EventType'] ?? item['eventType'] ?? (extra != null ? (extra['eventType'] ?? extra['EventType']) : null))?.toString().trim();
      if (rawEvent != null && rawEvent.isNotEmpty) {
        final cleanEvent = rawEvent.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
        if (cleanEvent == 'newmember') return true;
      }

      return false;
    }

    return false;
  }

  /// Whether this request represents a New Member recruitment search.
  bool get isNewMember => SubRequest.isNewMemberRecord(this);

  /// Whether this request is active and live (published).
  bool get isLive => status == 'published';

  CanonicalLocation get canonicalLocation {
    return CanonicalLocation(
      locationLabel: location ?? venue ?? '',
      latitude: latitude,
      longitude: longitude,
      precision: locationPrecision ?? LocationPrecision.exact,
      placeId: placeId,
      status: (latitude != null && longitude != null)
          ? (locationStatus ?? LocationResolutionStatus.resolved)
          : LocationResolutionStatus.unresolved,
    );
  }
}
