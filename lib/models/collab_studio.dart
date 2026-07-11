class CollabStudio {
  final String? id;
  final String name;
  final String description;
  final String location;
  final List<String> genres;
  final String? facilities;
  final String? contactInfo;
  final String creatorId;
  final int createdAt;
  final int updatedAt;

  CollabStudio({
    this.id,
    required this.name,
    required this.description,
    required this.location,
    this.genres = const [],
    this.facilities,
    this.contactInfo,
    required this.creatorId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CollabStudio.fromJson(Map<dynamic, dynamic> json, String keyId) {
    return CollabStudio(
      id: keyId,
      name: json['Name']?.toString() ?? '',
      description: json['Description']?.toString() ?? '',
      location: json['Location']?.toString() ?? '',
      genres: _toList(json['Genres']),
      facilities: json['Facilities']?.toString(),
      contactInfo: json['ContactInfo']?.toString(),
      creatorId: json['CreatorId']?.toString() ?? '',
      createdAt: json['CreatedAt'] is int ? json['CreatedAt'] as int : 0,
      updatedAt: json['UpdatedAt'] is int ? json['UpdatedAt'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Name': name,
      'Description': description,
      'Location': location,
      'Genres': genres,
      'Facilities': facilities,
      'ContactInfo': contactInfo,
      'CreatorId': creatorId,
      'CreatedAt': createdAt,
      'UpdatedAt': updatedAt,
    };
  }

  static List<String> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is Map) return val.values.map((e) => e.toString()).toList();
    return [val.toString()];
  }
}
