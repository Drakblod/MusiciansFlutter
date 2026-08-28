/// Centralized taxonomy for Genres/Band Types.
class GenresTaxonomy {
  /// Complete master taxonomy map used across profile, band creation, and editing.
  static const Map<String, List<String>> categoryMap = {
    '🎸 Rock, Pop, R&B, Hip Hop, etc': [
      'Rock',
      'Pop',
      'R&B',
      'Hip Hop',
      'Electronic Dance Music (EDM)',
      'Soul',
      'Funk',
      'Country',
      'Reggae',
      'Latin',
      'Indie / Alternative',
    ],
    '🗣️ Choir': [
      'Choir',
      'Medieval',
      'Renaissance',
      'Baroque',
      'Classical',
      'Romanticism',
      'Impressionism',
      'Modernism',
      'Contemporary',
      'Barbershop',
      'Gospel',
      'Pop',
    ],
    '🎼 Classical': [
      'Classical',
      'Medieval',
      'Renaissance',
      'Baroque',
      'Romanticism',
      'Impressionism',
      'Modernism',
      'Contemporary',
    ],
    '🎺 Wind, Concert & Brass Band': [
      'Wind Band',
      'Concert Band',
      'Brass Band',
      'Classical',
      'March & Ceremonial',
      'Contemporary',
      'Film & Popular',
      'Crossover',
    ],
    '🎷 Jazz': [
      'Jazz',
      'New Orleans/Dixieland',
      'Swing',
      'Bebop',
      'Cool',
      'Hardbop',
      'Free Jazz/Avantgarde',
      'Fusion',
      'Latin',
      'Modern/Contemporary',
    ],
    '🥁 Big Band': [
      'Big Band',
      'Mainstream (Basie, Miller, Sinatra, etc)',
      'New Orleans/Dixieland',
      'Swing',
      'Bebop',
      'Latin',
      'Fusion',
      'Modern/Contemporary',
      'Free Jazz/Avantgarde',
    ],
    '🌍 World Music': [
      'African',
      'Latin',
      'Caribbean',
      'Middle Eastern & Arabic',
      'South Asian',
      'East Asian',
      'Celtic & European',
      'Indigenous',
      'Global Fusion',
    ],
  };

  /// Allowed category keys for Create Session in exact required order.
  static const List<String> sessionCategoryKeys = [
    '🎸 Rock, Pop, R&B, Hip Hop, etc',
    '🎷 Jazz',
    '🌍 World Music',
  ];

  /// Filtered taxonomy for Create Session derived directly from master categoryMap.
  static Map<String, List<String>> get createSessionCategoryMap {
    final Map<String, List<String>> subset = {};
    for (final key in sessionCategoryKeys) {
      if (categoryMap.containsKey(key)) {
        subset[key] = categoryMap[key]!;
      }
    }
    return subset;
  }
}
