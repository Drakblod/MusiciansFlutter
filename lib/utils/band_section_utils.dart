import '../models/band.dart';
import '../models/user_profile.dart';

class BandSectionSuggestion {
  final String sectionName;
  final String sectionKey;
  final List<String> memberUserIds;
  final List<String> memberNames;

  const BandSectionSuggestion({
    required this.sectionName,
    required this.sectionKey,
    required this.memberUserIds,
    required this.memberNames,
  });

  int get memberCount => memberUserIds.length;
}

class BandSectionUtils {
  /// Resolves the deterministic effective instrument/skill for a user:
  /// 1. First valid primary/main skill from UserProfile.mainSkills
  /// 2. Otherwise the first valid value in UserProfile.instruments
  /// 3. Otherwise null (Unknown / excluded from automatic suggestions)
  static String? resolveEffectiveInstrument(UserProfile? profile) {
    if (profile == null) return null;

    final mainSkills = profile.mainSkills;
    for (final skill in mainSkills) {
      final trimmed = skill.trim();
      if (trimmed.isNotEmpty &&
          trimmed.toLowerCase() != 'browse musicians' &&
          trimmed.toLowerCase() != 'browse profiles' &&
          trimmed.toLowerCase() != 'browse_musicians' &&
          trimmed.toLowerCase() != 'musician') {
        return trimmed;
      }
    }

    final instruments = profile.instruments;
    for (final inst in instruments) {
      final trimmed = inst.trim();
      if (trimmed.isNotEmpty &&
          trimmed.toLowerCase() != 'browse musicians' &&
          trimmed.toLowerCase() != 'browse profiles' &&
          trimmed.toLowerCase() != 'browse_musicians' &&
          trimmed.toLowerCase() != 'musician') {
        return trimmed;
      }
    }

    return null;
  }

  /// Normalizes an instrument name for comparison: whitespace-trimmed and lowercased.
  /// Treats 'Trumpet', 'trumpet', and 'TRUMPET' as identical.
  /// Does NOT merge distinct instruments (e.g. 'Trumpet' vs 'Piccolo Trumpet').
  static String normalizeInstrumentKey(String instrument) {
    return instrument.trim().toLowerCase();
  }

  /// Generates deterministic section suggestions from a band's roster and profiles.
  static List<BandSectionSuggestion> generateSectionSuggestions({
    required List<BandMember> members,
    required Map<String, UserProfile> userProfiles,
  }) {
    final Map<String, String> canonicalNames = {};
    final Map<String, List<String>> sectionUserIds = {};
    final Map<String, List<String>> sectionNames = {};

    for (final member in members) {
      final uid = member.userId;
      if (uid == null || uid.isEmpty) continue;

      final profile = userProfiles[uid];
      final instrument = resolveEffectiveInstrument(profile);
      if (instrument == null || instrument.isEmpty) continue;

      final key = normalizeInstrumentKey(instrument);
      canonicalNames.putIfAbsent(key, () => instrument);
      sectionUserIds.putIfAbsent(key, () => []).add(uid);

      final displayName = profile?.displayName ??
          profile?.nickname ??
          member.nickname ??
          'Musician';
      sectionNames.putIfAbsent(key, () => []).add(displayName);
    }

    final List<BandSectionSuggestion> suggestions = [];
    for (final key in sectionUserIds.keys) {
      final uids = sectionUserIds[key]!;
      final names = sectionNames[key]!;
      final canonical = canonicalNames[key]!;

      suggestions.add(
        BandSectionSuggestion(
          sectionName: canonical,
          sectionKey: key,
          memberUserIds: uids,
          memberNames: names,
        ),
      );
    }

    // Sort by member count descending, then alphabetically
    suggestions.sort((a, b) {
      final countCompare = b.memberCount.compareTo(a.memberCount);
      if (countCompare != 0) return countCompare;
      return a.sectionName.toLowerCase().compareTo(b.sectionName.toLowerCase());
    });

    return suggestions;
  }
}
