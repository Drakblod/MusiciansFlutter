enum CalendarEventType {
  rehearsal,
  concert,
  tour,
  other,
}

class CalendarEvent {
  final String? id;
  final String? bandId;
  final String? title;
  final String? description;
  final CalendarEventType type;
  final String? location;
  final String? creatorId;
  final String? creatorName;
  final bool isFinalized;
  final List<DateTime> proposedDates;
  final Map<String, List<String>> votes; // Date string -> List of UserIds
  final DateTime? date;
  final String? startTime;
  final String? endTime;
  final List<String> confirmedAttendees;

  CalendarEvent({
    this.id,
    this.bandId,
    this.title,
    this.description,
    this.type = CalendarEventType.other,
    this.location,
    this.creatorId,
    this.creatorName,
    this.isFinalized = false,
    this.proposedDates = const [],
    this.votes = const {},
    this.date,
    this.startTime,
    this.endTime,
    this.confirmedAttendees = const [],
  });

  factory CalendarEvent.fromJson(Map<dynamic, dynamic> json, String keyId) {
    // Parse type
    final typeStr = json['Type']?.toString().toLowerCase();
    CalendarEventType parsedType = CalendarEventType.other;
    if (typeStr != null) {
      if (typeStr.contains('rehearsal') || typeStr == '0') parsedType = CalendarEventType.rehearsal;
      else if (typeStr.contains('concert') || typeStr == '1') parsedType = CalendarEventType.concert;
      else if (typeStr.contains('tour') || typeStr == '2') parsedType = CalendarEventType.tour;
    }

    // Proposed dates
    final proposedRaw = json['ProposedDates'];
    List<DateTime> parsedProposed = [];
    if (proposedRaw is List) {
      for (var d in proposedRaw) {
        if (d != null) {
          final p = DateTime.tryParse(d.toString());
          if (p != null) parsedProposed.add(p);
        }
      }
    }

    // Votes
    final votesRaw = json['Votes'];
    Map<String, List<String>> parsedVotes = {};
    if (votesRaw is Map) {
      votesRaw.forEach((k, v) {
        if (v is List) {
          parsedVotes[k.toString()] = v.map((e) => e.toString()).toList();
        } else if (v is Map) {
          parsedVotes[k.toString()] = v.values.map((e) => e.toString()).toList();
        }
      });
    }

    // Confirmed attendees
    final attendeesRaw = json['ConfirmedAttendees'];
    List<String> parsedAttendees = [];
    if (attendeesRaw is List) {
      parsedAttendees = attendeesRaw.map((e) => e.toString()).toList();
    } else if (attendeesRaw is Map) {
      parsedAttendees = attendeesRaw.values.map((e) => e.toString()).toList();
    }

    return CalendarEvent(
      id: keyId,
      bandId: json['BandId']?.toString(),
      title: json['Title']?.toString(),
      description: json['Description']?.toString(),
      type: parsedType,
      location: json['Location']?.toString(),
      creatorId: json['CreatorId']?.toString(),
      creatorName: json['CreatorName']?.toString(),
      isFinalized: json['IsFinalized'] == true,
      proposedDates: parsedProposed,
      votes: parsedVotes,
      date: json['Date'] != null ? DateTime.tryParse(json['Date'].toString()) : null,
      startTime: json['StartTime']?.toString(),
      endTime: json['EndTime']?.toString(),
      confirmedAttendees: parsedAttendees,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'BandId': bandId,
      'Title': title,
      'Description': description,
      'Type': type.index,
      'Location': location,
      'CreatorId': creatorId,
      'CreatorName': creatorName,
      'IsFinalized': isFinalized,
      'ProposedDates': proposedDates.map((d) => d.toUtc().toIso8601String()).toList(),
      'Votes': votes,
      'Date': date?.toUtc().toIso8601String(),
      'StartTime': startTime,
      'EndTime': endTime,
      'ConfirmedAttendees': confirmedAttendees,
    };
  }
}
