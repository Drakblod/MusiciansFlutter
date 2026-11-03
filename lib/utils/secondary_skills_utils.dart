/// REGISTRATION-SECONDARY-SKILLS-01 — Centralized Secondary Skills contract.
///
/// Canonical persisted representation (no new RTDB key):
///   /users/{uid}/info/UserType     -> Primary Skill
///   /users/{uid}/info/Instruments  -> [Primary Skill, ...Secondary Skills]
///
/// `Instruments` is already read by every existing matching consumer
/// (Find Gigs client filtering, `sendSubRequestNotification`,
/// `onSubRequestGroupPublished`, `publishSubRequestGroup` audience indexing),
/// so Secondary Skills participate in matching without a parallel field.
class SecondarySkillsUtils {
  SecondarySkillsUtils._();

  /// Placeholder / pseudo-role values that must never be treated as skills.
  static const Set<String> _placeholderValuesLower = {
    'browse musicians',
    'browse profiles',
    'browse_musicians',
    'null',
    'n/a',
    'na',
    'none',
    'undefined',
  };

  static bool _isPlaceholder(String value) =>
      _placeholderValuesLower.contains(value.trim().toLowerCase());

  /// Normalizes a raw list of Secondary Skills:
  /// - trims values
  /// - removes empty, whitespace-only and placeholder values
  /// - deduplicates case-insensitively, preserving first-selected order
  /// - removes the Primary Skill (case-insensitive)
  static List<String> normalize(
    Iterable<String?> raw, {
    String? primarySkill,
  }) {
    final primaryLower = primarySkill?.trim().toLowerCase() ?? '';
    final seen = <String>{};
    final result = <String>[];
    for (final value in raw) {
      if (value == null) continue;
      final trimmed = value.trim();
      if (trimmed.isEmpty || _isPlaceholder(trimmed)) continue;
      final lower = trimmed.toLowerCase();
      if (primaryLower.isNotEmpty && lower == primaryLower) continue;
      if (seen.add(lower)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  /// Reconciles Secondary Skills after the Primary Skill changes:
  /// the new Primary Skill is removed; all other valid skills are preserved.
  static List<String> reconcileWithPrimary(
    List<String> secondarySkills,
    String? newPrimarySkill,
  ) {
    return normalize(secondarySkills, primarySkill: newPrimarySkill);
  }

  /// Builds the canonical persisted `Instruments` list:
  /// Primary Skill first, followed by normalized Secondary Skills.
  static List<String> buildInstrumentsList(
    String primarySkill,
    Iterable<String?> secondarySkills,
  ) {
    final primary = primarySkill.trim();
    final secondary = normalize(secondarySkills, primarySkill: primary);
    return [
      if (primary.isNotEmpty && !_isPlaceholder(primary)) primary,
      ...secondary,
    ];
  }
}
