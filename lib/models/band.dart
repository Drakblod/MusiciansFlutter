class Band {
  final String? id;
  final String? ensembleType;
  final String? name;
  final List<String> genres;
  final String? qualification;
  final String? rehearsalLocation;
  final String? rehearsalDayOfWeek;
  final String? rehearsalDate; // ISO string
  final String? rehearsalTime;
  final String? rehearsalStartTime;
  final String? rehearsalEndTime;
  final String? description;
  final String? about;
  final String? userRole;
  final String? location;
  final String? rehearsalDateTime;
  final Map<String, BandMember> membersBand;
  final List<String> styleBand;
  final String? style;
  final String? level;
  final String? address;
  final String? contact;
  final String? members;
  final String? history;
  final String? concertsProjects;

  Band({
    this.id,
    this.ensembleType,
    this.name,
    this.genres = const [],
    this.qualification,
    this.rehearsalLocation,
    this.rehearsalDayOfWeek,
    this.rehearsalDate,
    this.rehearsalTime,
    this.rehearsalStartTime,
    this.rehearsalEndTime,
    this.description,
    this.about,
    this.userRole,
    this.location,
    this.rehearsalDateTime,
    this.membersBand = const {},
    this.styleBand = const [],
    this.style,
    this.level,
    this.address,
    this.contact,
    this.members,
    this.history,
    this.concertsProjects,
  });

  factory Band.fromJson(Map<dynamic, dynamic> json, String keyId) {
    // Parse members
    final membersRaw = json['Members_band'];
    final Map<String, BandMember> parsedMembers = {};
    if (membersRaw is Map) {
      membersRaw.forEach((k, v) {
        if (v is Map) {
          parsedMembers[k.toString()] = BandMember.fromJson(v);
        }
      });
    }

    return Band(
      id: keyId,
      ensembleType: json['EnsembleType']?.toString(),
      name: json['Name']?.toString(),
      genres: _toList(json['Genres']),
      qualification: json['Qualification']?.toString(),
      rehearsalLocation: json['RehearsalLocation']?.toString(),
      rehearsalDayOfWeek: json['RehearsalDayOfWeek']?.toString(),
      rehearsalDate: json['RehearsalDate']?.toString(),
      rehearsalTime: json['RehearsalTime']?.toString(),
      rehearsalStartTime: json['RehearsalStartTime']?.toString(),
      rehearsalEndTime: json['RehearsalEndTime']?.toString(),
      description: json['Description']?.toString(),
      about: json['About']?.toString(),
      userRole: json['UserRole']?.toString(),
      location: json['Location']?.toString(),
      rehearsalDateTime: json['RehearsalDateTime']?.toString(),
      membersBand: parsedMembers,
      styleBand: _toList(json['Style_band']),
      style: json['Style']?.toString(),
      level: json['Level']?.toString(),
      address: json['Address']?.toString(),
      contact: json['Contact']?.toString(),
      members: json['Members']?.toString(),
      history: json['History']?.toString(),
      concertsProjects: json['ConcertsProjects']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> membersMap = {};
    membersBand.forEach((k, v) {
      membersMap[k] = v.toJson();
    });

    return {
      'EnsembleType': ensembleType,
      'Name': name,
      'Genres': genres,
      'Qualification': qualification,
      'RehearsalLocation': rehearsalLocation,
      'RehearsalDayOfWeek': rehearsalDayOfWeek,
      'RehearsalDate': rehearsalDate,
      'RehearsalTime': rehearsalTime,
      'RehearsalStartTime': rehearsalStartTime,
      'RehearsalEndTime': rehearsalEndTime,
      'Description': description,
      'About': about,
      'UserRole': userRole,
      'Location': location,
      'RehearsalDateTime': rehearsalDateTime,
      'Members_band': membersMap,
      'Style_band': styleBand,
      'Style': style,
      'Level': level,
      'Address': address,
      'Contact': contact,
      'Members': members,
      'History': history,
      'ConcertsProjects': concertsProjects,
    };
  }

  static List<String> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is Map) return val.values.map((e) => e.toString()).toList();
    return [val.toString()];
  }
}

class BandMember {
  final String? nickname;
  final String? role;

  BandMember({this.nickname, this.role});

  factory BandMember.fromJson(Map<dynamic, dynamic> json) {
    return BandMember(
      nickname: json['Nickname']?.toString(),
      role: json['Role']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Nickname': nickname,
      'Role': role,
    };
  }
}
