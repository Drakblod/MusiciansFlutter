import 'dart:convert';

/// Represents a single notification record stored in `userNotifications/{userId}/{notificationId}`.
class AppNotification {
  final String id;
  final String type;
  final String category; // 'messages' | 'events' | 'requests' | 'system'
  final String title;
  final String body;
  final int createdAt; // epoch milliseconds
  final bool isRead;
  final int? readAt; // epoch milliseconds
  final Map<String, dynamic> data;

  const AppNotification({
    required this.id,
    required this.type,
    this.category = 'system',
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.readAt,
    this.data = const {},
  });

  /// Derives category from type if category is not explicitly set or empty.
  static String resolveCategory(String? type, [String? explicitCategory]) {
    if (explicitCategory != null && explicitCategory.trim().isNotEmpty) {
      final cat = explicitCategory.trim().toLowerCase();
      if (['messages', 'events', 'requests', 'system'].contains(cat)) {
        return cat;
      }
    }
    if (type == null) return 'system';
    switch (type.toLowerCase()) {
      case 'direct_message':
      case 'session_message':
      case 'band_room_message':
      case 'band_section_chat':
        return 'messages';
      case 'event_invite':
      case 'event_reminder':
      case 'event_threshold':
      case 'event_milestone':
        return 'events';
      case 'sub_request_invite':
      case 'sub_request':
      case 'grouped_sub_request':
      case 'gig_finalized':
      case 'session_application':
      case 'session_application_status':
        return 'requests';
      default:
        return 'system';
    }
  }

  factory AppNotification.fromJson(dynamic json, [String? fallbackId]) {
    if (json is! Map) {
      return AppNotification(
        id: fallbackId ?? '',
        type: 'system',
        category: 'system',
        title: '',
        body: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    final rawMap = Map<String, dynamic>.from(json);
    final id = (rawMap['id'] ?? fallbackId ?? '').toString();
    final type = (rawMap['type'] ?? rawMap['Type'] ?? 'system').toString();
    final explicitCat = rawMap['category'] ?? rawMap['Category'];
    final category = resolveCategory(type, explicitCat?.toString());
    final title = (rawMap['title'] ?? rawMap['Title'] ?? '').toString();
    final body = (rawMap['body'] ?? rawMap['Body'] ?? '').toString();

    // Parse createdAt safely (epoch int, double, or ISO string)
    int createdAt = DateTime.now().millisecondsSinceEpoch;
    final rawCreatedAt = rawMap['createdAt'] ?? rawMap['CreatedAt'] ?? rawMap['timestamp'] ?? rawMap['Timestamp'];
    if (rawCreatedAt is int) {
      createdAt = rawCreatedAt;
    } else if (rawCreatedAt is double) {
      createdAt = rawCreatedAt.toInt();
    } else if (rawCreatedAt is String && rawCreatedAt.trim().isNotEmpty) {
      final parsedInt = int.tryParse(rawCreatedAt.trim());
      if (parsedInt != null) {
        createdAt = parsedInt;
      } else {
        final parsedDate = DateTime.tryParse(rawCreatedAt.trim());
        if (parsedDate != null) {
          createdAt = parsedDate.millisecondsSinceEpoch;
        }
      }
    }

    // Parse isRead safely
    final rawIsRead = rawMap['isRead'] ?? rawMap['IsRead'];
    final isRead = rawIsRead == true || rawIsRead == 'true';

    // Parse readAt safely
    int? readAt;
    final rawReadAt = rawMap['readAt'] ?? rawMap['ReadAt'];
    if (rawReadAt is int) {
      readAt = rawReadAt;
    } else if (rawReadAt is double) {
      readAt = rawReadAt.toInt();
    } else if (rawReadAt is String && rawReadAt.trim().isNotEmpty) {
      final parsedInt = int.tryParse(rawReadAt.trim());
      if (parsedInt != null) {
        readAt = parsedInt;
      } else {
        final parsedDate = DateTime.tryParse(rawReadAt.trim());
        if (parsedDate != null) {
          readAt = parsedDate.millisecondsSinceEpoch;
        }
      }
    }

    // Parse data safely
    Map<String, dynamic> data = {};
    final rawData = rawMap['data'] ?? rawMap['Data'];
    if (rawData is Map) {
      data = Map<String, dynamic>.from(rawData);
    } else if (rawData is String && rawData.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    return AppNotification(
      id: id,
      type: type,
      category: category,
      title: title,
      body: body,
      createdAt: createdAt,
      isRead: isRead,
      readAt: readAt,
      data: data,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'category': category,
      'title': title,
      'body': body,
      'createdAt': createdAt,
      'isRead': isRead,
      if (readAt != null) 'readAt': readAt,
      if (data.isNotEmpty) 'data': data,
    };
  }

  AppNotification copyWith({
    String? id,
    String? type,
    String? category,
    String? title,
    String? body,
    int? createdAt,
    bool? isRead,
    int? readAt,
    Map<String, dynamic>? data,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      category: category ?? this.category,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      data: data ?? this.data,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotification &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          category == other.category &&
          title == other.title &&
          body == other.body &&
          createdAt == other.createdAt &&
          isRead == other.isRead &&
          readAt == other.readAt;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        category,
        title,
        body,
        createdAt,
        isRead,
        readAt,
      );
}
