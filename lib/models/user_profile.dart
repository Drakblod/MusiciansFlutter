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
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? country;
  final int? locationUpdatedAt;

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
    this.latitude,
    this.longitude,
    this.city,
    this.country,
    this.locationUpdatedAt,
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
      latitude: json['Latitude'] is num ? (json['Latitude'] as num).toDouble() : null,
      longitude: json['Longitude'] is num ? (json['Longitude'] as num).toDouble() : null,
      city: json['City']?.toString(),
      country: json['Country']?.toString(),
      locationUpdatedAt: json['LocationUpdatedAt'] is int ? json['LocationUpdatedAt'] as int : null,
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
      'Latitude': latitude,
      'Longitude': longitude,
      'City': city,
      'Country': country,
      'LocationUpdatedAt': locationUpdatedAt,
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
