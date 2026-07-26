class UserProfile {
  final String? userType;
  final String? userId;
  final String? displayName;
  final String? nickname;
  final String? email;
  final List<String> instruments;
  final List<String> styles;
  final List<String> genres;
  final String? level;
  final String? location;
  final String? about;
  final String? contact;
  final String? history;
  final String? projects;
  final String? profilePictureUrl;
  final String? spotifyUrl;
  final String? youtubeUrl;
  final String? audioSnippetUrl;
  final List<String> collabRoles;
  final bool collabRemote;
  final String? collabBio;
  final String? mainInstrument;

  UserProfile({
    this.userType,
    this.userId,
    this.displayName,
    this.nickname,
    this.email,
    this.instruments = const [],
    this.styles = const [],
    this.genres = const [],
    this.level,
    this.location,
    this.about,
    this.contact,
    this.history,
    this.projects,
    this.profilePictureUrl,
    this.spotifyUrl,
    this.youtubeUrl,
    this.audioSnippetUrl,
    this.collabRoles = const [],
    this.collabRemote = false,
    this.collabBio,
    this.mainInstrument,
  });

  factory UserProfile.fromJson(Map<dynamic, dynamic> json) {
    return UserProfile(
      userType: json['UserType']?.toString(),
      userId: json['UserId']?.toString(),
      displayName: json['DisplayName']?.toString(),
      nickname: json['Nickname']?.toString(),
      email: json['Email']?.toString() ?? json['contact']?.toString(),
      instruments: _toList(json['Instruments']),
      styles: _toList(json['Styles']),
      genres: _toList(json['Genres']),
      level: json['Level']?.toString(),
      location: json['Location']?.toString(),
      about: json['About']?.toString(),
      contact: json['Contact']?.toString(),
      history: json['History']?.toString(),
      projects: json['Projects']?.toString(),
      profilePictureUrl: json['ProfilePictureUrl']?.toString(),
      spotifyUrl: json['SpotifyUrl']?.toString(),
      youtubeUrl: json['YoutubeUrl']?.toString(),
      audioSnippetUrl: json['AudioSnippetUrl']?.toString(),
      collabRoles: _toList(json['CollabRoles']),
      collabRemote: json['CollabRemote'] == true,
      collabBio: json['CollabBio']?.toString(),
      mainInstrument: json['MainInstrument']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'UserType': userType,
      'UserId': userId,
      'DisplayName': displayName,
      'Nickname': nickname,
      'Email': email,
      'Instruments': instruments,
      'Styles': styles,
      'Genres': genres,
      'Level': level,
      'Location': location,
      'About': about,
      'Contact': contact,
      'History': history,
      'Projects': projects,
      'ProfilePictureUrl': profilePictureUrl,
      'SpotifyUrl': spotifyUrl,
      'YoutubeUrl': youtubeUrl,
      'AudioSnippetUrl': audioSnippetUrl,
      'CollabRoles': collabRoles,
      'CollabRemote': collabRemote,
      'CollabBio': collabBio,
      'MainInstrument': mainInstrument,
    };
  }

  String get instrumentsStr => instruments.join(', ');
  String get stylesStr => styles.join(', ');
  bool get canMixMaster => styles.contains('Mixing') || styles.contains('Mastering');

  /// Returns top 3 main skills parsed from mainInstrument or fallback to first instrument
  List<String> get mainSkills {
    if (mainInstrument != null && mainInstrument!.isNotEmpty) {
      final parsed = mainInstrument!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final valid = parsed.where((item) => instruments.contains(item)).take(3).toList();
      if (valid.isNotEmpty) return valid;
    }
    if (instruments.isNotEmpty) {
      return [instruments.first];
    }
    if (userType != null && userType!.isNotEmpty) {
      return [userType!];
    }
    return [];
  }

  /// Returns remaining selected instruments/skills excluding mainSkills
  List<String> get secondarySkills {
    final mains = mainSkills.toSet();
    return instruments.where((item) => !mains.contains(item)).toList();
  }

  /// Single formatted string of main skills for headers and subtitles
  String get mainSkillsSubtitle {
    final skills = mainSkills;
    if (skills.isNotEmpty) {
      return skills.join(' • ');
    }
    return userType ?? 'Musician';
  }

  static List<String> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is Map) return val.values.map((e) => e.toString()).toList();
    return [val.toString()];
  }
}
