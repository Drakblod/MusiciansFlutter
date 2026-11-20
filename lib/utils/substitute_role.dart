import '../data/skills_taxonomy.dart';

bool isBandleaderRole(String role) =>
    SkillsTaxonomy.resolveCanonicalPersistedValue(role) ==
    SkillsTaxonomy.featuredRolePersistedValue;
