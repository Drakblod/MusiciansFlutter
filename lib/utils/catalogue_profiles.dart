import '../models/user_profile.dart';
import '../models/band.dart';

/// Strict projection decoding. Never deserialize private profile/band descendants.
class CatalogueProfiles {
  static bool validId(String id) =>
      id.isNotEmpty &&
      id.length <= 128 &&
      !RegExp(r'[.#$\[\]/\x00-\x1f\x7f]').hasMatch(id);
  static String? text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
  static List<String> list(Object? v) =>
      v is List ? v.whereType<String>().toList() : const [];
  static Iterable<MapEntry<String, Map>> entries(Object? value) sync* {
    final Iterable<MapEntry<dynamic, dynamic>> raw;
    if (value is Map) {
      raw = value.entries;
    } else if (value is List) {
      raw = value.asMap().entries;
    } else {
      raw = const [];
    }
    final seen = <String>{};
    for (final entry in raw) {
      final id = entry.key.toString();
      if (validId(id) && entry.value is Map && seen.add(id)) {
        yield MapEntry(id, entry.value as Map);
      }
    }
  }

  static UserProfile? user(String id, Object? value) {
    if (!validId(id) || value is! Map) return null;
    return UserProfile(
      userId: id,
      displayName: text(value['DisplayName']),
      nickname: text(value['Nickname']),
      userType: text(value['UserType']),
      mainInstrument: text(value['MainInstrument']),
      instruments: list(value['Instruments']),
      genres: list(value['Genres']),
      styles: list(value['Styles']),
      level: text(value['Level']),
      location: text(value['Location']),
      about: text(value['About']),
      profilePictureUrl: text(value['ProfilePictureUrl']),
      spotifyUrl: text(value['SpotifyUrl']),
      youtubeUrl: text(value['YoutubeUrl']),
      audioSnippetUrl: text(value['AudioSnippetUrl']),
      audioSnippetTitle: UserProfile.normalizeAudioSnippetTitle(value['AudioSnippetTitle']),
      collabRoles: list(value['CollabRoles']),
      collabRemote: value['CollabRemote'] == true,
      collabBio: text(value['CollabBio']),
    );
  }

  static Band? band(String id, Object? value) {
    if (!validId(id) || value is! Map) return null;
    final count = value['activeMemberCount'];
    return Band(
      id: id,
      name: text(value['Name']),
      ensembleType: text(value['EnsembleType']),
      about: text(value['About']),
      description: text(value['Description']),
      location: text(value['Location']),
      genres: list(value['Genres']),
      styleBand: list(value['Style_band']),
      style: text(value['Style']),
      level: text(value['Level']),
      qualification: text(value['Qualification']),
      activeMemberCount: count is int && count >= 0 ? count : null,
    );
  }

  /// Discovery matching deliberately excludes email/contact, even on owner models.
  static bool matchesUserQuery(UserProfile user, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      user.displayName,
      user.nickname,
      user.location,
      ...user.matchingSkills,
    ].whereType<String>().any((value) => value.toLowerCase().contains(q));
  }

  static List<UserProfile> users(Object? value) => [
    for (final e in entries(value)) user(e.key, e.value)!,
  ];
  static List<Band> bands(Object? value) => [
    for (final e in entries(value)) band(e.key, e.value)!,
  ];
}
