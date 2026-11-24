import 'package:flutter/material.dart';

import '../data/genres_taxonomy.dart';
import 'searchable_category_multi_select_sheet.dart';

class GenrePicker {
  static bool isStandard(String genre) {
    final key = genre.trim().toLowerCase();
    return GenresTaxonomy.categoryMap.values.any(
      (options) => options.any((option) => option.toLowerCase() == key),
    );
  }

  // Existing band metadata count limit in membership_authority.js.
  static Future<List<String>?> showForBand(
    BuildContext context,
    List<String> selected,
  ) =>
      show(context, selected, maxSelection: 100);

  static Future<List<String>?> show(
    BuildContext context,
    List<String> selected, {
    int? maxSelection,
  }) {
    return SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Genres/Band Types',
      categoryMap: GenresTaxonomy.categoryMap,
      initialSelected: selected,
      maxSelection: maxSelection,
      // Existing band metadata and public catalogue limit per genre.
      customOptionMaxLength: 200,
    );
  }
}
