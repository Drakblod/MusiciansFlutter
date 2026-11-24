import 'package:flutter/material.dart';

import '../data/genres_taxonomy.dart';
import 'searchable_category_multi_select_sheet.dart';

class BandGenrePicker {
  static bool isStandard(String genre) {
    final key = genre.trim().toLowerCase();
    return GenresTaxonomy.categoryMap.values.any(
      (options) => options.any((option) => option.toLowerCase() == key),
    );
  }

  static Future<List<String>?> show(
    BuildContext context,
    List<String> selected,
  ) {
    return SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Genres/Band Types',
      categoryMap: GenresTaxonomy.categoryMap,
      initialSelected: selected,
      // Existing band metadata limits in membership_authority.js.
      maxSelection: 100,
      customOptionMaxLength: 200,
    );
  }
}
