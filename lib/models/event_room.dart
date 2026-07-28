class EventRoom {
  final String roomId;
  final String eventId;
  final String bandId;
  final String name;
  final int createdAt;
  final String createdBy;
  final bool isTemporary;
  final bool isClosed;
  final Map<String, String> members; // userId -> role/status (e.g. 'leader', 'attending', 'substitute')

  EventRoom({
    required this.roomId,
    required this.eventId,
    required this.bandId,
    required this.name,
    required this.createdAt,
    required this.createdBy,
    this.isTemporary = true,
    this.isClosed = false,
    this.members = const {},
  });

  factory EventRoom.fromJson(Map<dynamic, dynamic> json, String id) {
    final Map<String, String> parsedMembers = {};
    final rawMembers = json['members'];
    if (rawMembers is Map) {
      rawMembers.forEach((k, v) {
        parsedMembers[k.toString()] = v?.toString() ?? 'member';
      });
    }

    return EventRoom(
      roomId: id,
      eventId: json['eventId']?.toString() ?? '',
      bandId: json['bandId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Event Room',
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : int.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
      createdBy: json['createdBy']?.toString() ?? '',
      isTemporary: json['isTemporary'] != false,
      isClosed: json['isClosed'] == true,
      members: parsedMembers,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'bandId': bandId,
      'name': name,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'isTemporary': isTemporary,
      'isClosed': isClosed,
      'members': members,
    };
  }
}
