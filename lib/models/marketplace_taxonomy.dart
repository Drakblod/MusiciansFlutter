import 'listing.dart';

class MarketplaceCategoryItem {
  final String id;
  final String label;
  final String intent;

  const MarketplaceCategoryItem({
    required this.id,
    required this.label,
    required this.intent,
  });
}

class MarketplaceTaxonomy {
  static const String intentLookingFor = 'looking_for';
  static const String intentOffering = 'offering';

  static const String labelLookingFor = "I'M LOOKING FOR";
  static const String labelOffering = "I'M OFFERING";

  static const String subtitleLookingFor =
      'Find instruments, services, spaces, teachers and other music resources.';
  static const String subtitleOffering =
      'Find requests from musicians who need instruments, services or expertise.';

  // Exact 8 options for "I'M LOOKING FOR" in exact specified order
  static const List<MarketplaceCategoryItem> lookingForCategories = [
    MarketplaceCategoryItem(
      id: 'instrument_gear',
      label: 'Instrument/Gear',
      intent: intentLookingFor,
    ),
    MarketplaceCategoryItem(
      id: 'teacher_school',
      label: 'Teacher/School',
      intent: intentLookingFor,
    ),
    MarketplaceCategoryItem(
      id: 'learning_materials',
      label: 'Learning Materials',
      intent: intentLookingFor,
    ),
    MarketplaceCategoryItem(
      id: 'music_services',
      label: 'Music Services',
      intent: intentLookingFor,
    ),
    MarketplaceCategoryItem(
      id: 'studio',
      label: 'Studio',
      intent: intentLookingFor,
    ),
    MarketplaceCategoryItem(
      id: 'engineer_producer',
      label: 'Engineer/Producer',
      intent: intentLookingFor,
    ),
    MarketplaceCategoryItem(
      id: 'rehearsal_space',
      label: 'Rehearsal Space',
      intent: intentLookingFor,
    ),
    MarketplaceCategoryItem(
      id: 'other_services',
      label: 'Other Services',
      intent: intentLookingFor,
    ),
  ];

  // Exact 8 options for "I'M OFFERING" in exact specified order
  static const List<MarketplaceCategoryItem> offeringCategories = [
    MarketplaceCategoryItem(
      id: 'instrument_gear',
      label: 'Instruments/Gear',
      intent: intentOffering,
    ),
    MarketplaceCategoryItem(
      id: 'repairs',
      label: 'Repairs',
      intent: intentOffering,
    ),
    MarketplaceCategoryItem(
      id: 'lessons_school',
      label: 'Lessons/School',
      intent: intentOffering,
    ),
    MarketplaceCategoryItem(
      id: 'music_services',
      label: 'Music Services',
      intent: intentOffering,
    ),
    MarketplaceCategoryItem(
      id: 'recording_production',
      label: 'Recording/Production',
      intent: intentOffering,
    ),
    MarketplaceCategoryItem(
      id: 'promotion',
      label: 'Promotion',
      intent: intentOffering,
    ),
    MarketplaceCategoryItem(
      id: 'management',
      label: 'Management',
      intent: intentOffering,
    ),
    MarketplaceCategoryItem(
      id: 'other_services',
      label: 'Other Services',
      intent: intentOffering,
    ),
  ];

  static List<MarketplaceCategoryItem> getCategoriesForIntent(String intent) {
    if (intent == intentLookingFor) {
      return lookingForCategories;
    } else if (intent == intentOffering) {
      return offeringCategories;
    }
    return const [];
  }

  static String getIntentLabel(String? intent) {
    if (intent == intentLookingFor) {
      return labelLookingFor;
    } else if (intent == intentOffering) {
      return labelOffering;
    }
    return 'MARKETPLACE';
  }

  static String getCategoryLabel(String? intent, String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return 'General';
    final categories = getCategoriesForIntent(intent ?? '');
    for (final item in categories) {
      if (item.id == categoryId) return item.label;
    }
    // Check both lists if intent not specified or category not in that intent
    for (final item in lookingForCategories) {
      if (item.id == categoryId) return item.label;
    }
    for (final item in offeringCategories) {
      if (item.id == categoryId) return item.label;
    }
    return categoryId;
  }

  /// Maps legacy listingType ('buy', 'sell', 'rent', 'service') to intent
  static String mapLegacyListingType(String? listingType) {
    if (listingType == 'buy') {
      return intentLookingFor;
    }
    return intentOffering;
  }

  /// Maps legacy category string to modern category ID
  static String mapLegacyCategory(String? category, {String? intent}) {
    if (category == null || category.isEmpty) return 'other_services';
    switch (category) {
      case 'Instruments':
      case 'Amps & Effects':
        return 'instrument_gear';
      case 'Studio & Recording':
        return intent == intentLookingFor ? 'studio' : 'recording_production';
      case 'Rehearsal Spaces':
        return 'rehearsal_space';
      case 'Music Services':
        return 'music_services';
      case 'Other':
      default:
        return 'other_services';
    }
  }

  /// Returns true if a listing matches the user's browsing filter.
  ///
  /// Browsing semantics:
  /// - User browsing `I'M LOOKING FOR` wants to find what authors are `OFFERING`.
  /// - User browsing `I'M OFFERING` wants to find requests from authors `LOOKING FOR`.
  static bool matchesBrowsingFilter({
    required Listing listing,
    required String? browsingIntent,
    required String? browsingCategoryId,
  }) {
    if (browsingIntent == null) return true;

    final effectiveIntent = listing.effectiveIntent;
    final effectiveCategory = listing.effectiveCategory;

    if (browsingIntent == intentLookingFor) {
      // User is looking for something -> we want listings where author is offering
      if (effectiveIntent != intentOffering) return false;

      if (browsingCategoryId == null || browsingCategoryId.isEmpty) return true;

      // Check reciprocal match
      switch (browsingCategoryId) {
        case 'instrument_gear':
          return effectiveCategory == 'instrument_gear';
        case 'teacher_school':
          return effectiveCategory == 'lessons_school';
        case 'learning_materials':
          return effectiveCategory == 'lessons_school' ||
              effectiveCategory == 'other_services' ||
              effectiveCategory == 'learning_materials';
        case 'music_services':
          return effectiveCategory == 'music_services' ||
              effectiveCategory == 'repairs' ||
              effectiveCategory == 'promotion' ||
              effectiveCategory == 'management';
        case 'studio':
          return effectiveCategory == 'recording_production' ||
              effectiveCategory == 'studio';
        case 'engineer_producer':
          return effectiveCategory == 'recording_production' ||
              effectiveCategory == 'engineer_producer';
        case 'rehearsal_space':
          return effectiveCategory == 'rehearsal_space' ||
              effectiveCategory == 'recording_production' ||
              listing.category == 'Rehearsal Spaces';
        case 'other_services':
          return effectiveCategory == 'other_services' ||
              effectiveCategory == 'repairs' ||
              effectiveCategory == 'promotion' ||
              effectiveCategory == 'management';
        default:
          return effectiveCategory == browsingCategoryId;
      }
    } else if (browsingIntent == intentOffering) {
      // User is offering something -> we want requests where author is looking for
      if (effectiveIntent != intentLookingFor) return false;

      if (browsingCategoryId == null || browsingCategoryId.isEmpty) return true;

      switch (browsingCategoryId) {
        case 'instrument_gear':
          return effectiveCategory == 'instrument_gear';
        case 'repairs':
          return effectiveCategory == 'instrument_gear' ||
              effectiveCategory == 'music_services' ||
              effectiveCategory == 'other_services';
        case 'lessons_school':
          return effectiveCategory == 'teacher_school' ||
              effectiveCategory == 'learning_materials' ||
              effectiveCategory == 'lessons_school';
        case 'music_services':
          return effectiveCategory == 'music_services' ||
              effectiveCategory == 'other_services';
        case 'recording_production':
          return effectiveCategory == 'studio' ||
              effectiveCategory == 'engineer_producer' ||
              effectiveCategory == 'recording_production';
        case 'promotion':
          return effectiveCategory == 'music_services' ||
              effectiveCategory == 'other_services' ||
              effectiveCategory == 'promotion';
        case 'management':
          return effectiveCategory == 'music_services' ||
              effectiveCategory == 'other_services' ||
              effectiveCategory == 'management';
        case 'other_services':
          return effectiveCategory == 'other_services';
        default:
          return effectiveCategory == browsingCategoryId;
      }
    }

    return true;
  }
}
