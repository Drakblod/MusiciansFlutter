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

  factory UserProfile.fromJson(
    Map<dynamic, dynamic> json, [
    String? keyUserId,
  ]) {
    final Map<dynamic, dynamic> infoMap = (json['info'] is Map)
        ? (json['info'] as Map)
        : json;

    return UserProfile(
      userId:
          keyUserId ??
          json['UserId']?.toString() ??
          infoMap['UserId']?.toString(),
      userType:
          infoMap['UserType']?.toString() ??
          json['UserType']?.toString() ??
          infoMap['userType']?.toString() ??
          json['userType']?.toString(),
      nickname:
          infoMap['Nickname']?.toString() ??
          json['Nickname']?.toString() ??
          infoMap['nickname']?.toString() ??
          json['nickname']?.toString(),
      displayName:
          infoMap['DisplayName']?.toString() ??
          json['DisplayName']?.toString() ??
          infoMap['displayName']?.toString() ??
          json['displayName']?.toString(),
      email:
          infoMap['Email']?.toString() ??
          json['Email']?.toString() ??
          infoMap['Contact']?.toString() ??
          infoMap['contact']?.toString(),
      instruments: _toList(infoMap['Instruments'] ?? json['Instruments']),
      styles: _toList(infoMap['Styles'] ?? json['Styles']),
      genres: _toList(infoMap['Genres'] ?? json['Genres']),
      level: (infoMap['Level'] ?? json['Level'])?.toString(),
      location: (infoMap['Location'] ?? json['Location'])?.toString(),
      about: (infoMap['About'] ?? json['About'])?.toString(),
      contact: (infoMap['Contact'] ?? json['Contact'])?.toString(),
      history: (infoMap['History'] ?? json['History'])?.toString(),
      projects: (infoMap['Projects'] ?? json['Projects'])?.toString(),
      profilePictureUrl:
          (infoMap['ProfilePictureUrl'] ?? json['ProfilePictureUrl'])
              ?.toString(),
      spotifyUrl: (infoMap['SpotifyUrl'] ?? json['SpotifyUrl'])?.toString(),
      youtubeUrl: (infoMap['YoutubeUrl'] ?? json['YoutubeUrl'])?.toString(),
      audioSnippetUrl: (infoMap['AudioSnippetUrl'] ?? json['AudioSnippetUrl'])
          ?.toString(),
      collabRoles: _toList(infoMap['CollabRoles'] ?? json['CollabRoles']),
      collabRemote: (infoMap['CollabRemote'] ?? json['CollabRemote']) == true,
      collabBio: (infoMap['CollabBio'] ?? json['CollabBio'])?.toString(),
      mainInstrument: (infoMap['MainInstrument'] ?? json['MainInstrument'])
          ?.toString(),
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
  bool get canMixMaster =>
      styles.contains('Mixing') || styles.contains('Mastering');

  /// Returns top 3 main skills parsed from mainInstrument or fallback to first instrument
  List<String> get mainSkills {
    List<String> result = [];
    if (mainInstrument != null && mainInstrument!.isNotEmpty) {
      final parsed = mainInstrument!
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final valid = parsed
          .where((item) => instruments.contains(item))
          .take(3)
          .toList();
      if (valid.isNotEmpty) result = valid;
    }
    if (result.isEmpty && instruments.isNotEmpty) {
      result = [instruments.first];
    }
    if (result.isEmpty && userType != null && userType!.isNotEmpty) {
      result = [userType!];
    }
    return result
        .where(
          (s) =>
              s != 'Browse Musicians' &&
              s != 'Browse Profiles' &&
              s != 'browse_musicians',
        )
        .toList();
  }

  /// Returns remaining selected instruments/skills excluding mainSkills
  List<String> get secondarySkills {
    final mains = mainSkills.toSet();
    return instruments
        .where(
          (item) =>
              !mains.contains(item) &&
              item != 'Browse Musicians' &&
              item != 'Browse Profiles' &&
              item != 'browse_musicians',
        )
        .toList();
  }

  /// Single formatted string of main skills for headers and subtitles
  String get mainSkillsSubtitle {
    final skills = mainSkills;
    if (skills.isNotEmpty) {
      return skills.join(' • ');
    }
    if (userType != null &&
        userType!.isNotEmpty &&
        userType != 'Browse Musicians' &&
        userType != 'Browse Profiles' &&
        userType != 'browse_musicians') {
      return userType!;
    }
    return 'Musician';
  }

  static List<String> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is Map) return val.values.map((e) => e.toString()).toList();
    return [val.toString()];
  }
}
