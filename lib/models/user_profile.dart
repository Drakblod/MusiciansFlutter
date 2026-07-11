class UserProfile {
  final String? userType;
  final String? userId;
  final String? displayName;
  final String? nickname;
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

  UserProfile({
    this.userType,
    this.userId,
    this.displayName,
    this.nickname,
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
  });

  factory UserProfile.fromJson(Map<dynamic, dynamic> json) {
    return UserProfile(
      userType: json['UserType']?.toString(),
      userId: json['UserId']?.toString(),
      displayName: json['DisplayName']?.toString(),
      nickname: json['Nickname']?.toString(),
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'UserType': userType,
      'UserId': userId,
      'DisplayName': displayName,
      'Nickname': nickname,
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
    };
  }

  String get instrumentsStr => instruments.join(', ');
  String get stylesStr => styles.join(', ');
  bool get canMixMaster => styles.contains('Mixing') || styles.contains('Mastering');

  static List<String> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is Map) return val.values.map((e) => e.toString()).toList();
    return [val.toString()];
  }
}
