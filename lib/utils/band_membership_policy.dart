import '../models/band.dart';

class BandMembershipPolicy {
  BandMembershipPolicy._();

  static bool isRealId(String? id) {
    final value = id?.trim().toLowerCase() ?? '';
    return value.isNotEmpty &&
        !RegExp(r'[.#$\[\]/]').hasMatch(value) &&
        !RegExp(r'^(mock|demo)(?:[_-]|$)').hasMatch(value) &&
        !{'freelance', 'standalone', 'all', 'null', 'none', 'undefined'}.contains(value);
  }

  /// Existing user-band entries are candidate references, never permissions.
  /// The callback is read-only; normal discovery never reads the /Bands root.
  static Future<Map<String, String>> discover(
    String uid, Future<Object?> Function(String path) read,
  ) async {
    final index = await read('users/$uid/Bands');
    final Iterable<String> candidates;
    if (index is Map) {
      candidates = index.keys.map((key) => key.toString());
    } else if (index is List) {
      candidates = index.asMap().entries.where((entry) => entry.value != null)
          .map((entry) => entry.key.toString());
    } else {
      return const {};
    }
    final result = <String, String>{};
    for (final id in candidates.toSet().where(isRealId)) {
      final member = await read('Bands/$id/Members_band/$uid');
      if (member is! Map) continue;
      // Read small canonical metadata fields, not the band's events/member tree.
      final metadata = await Future.wait([
        read('Bands/$id/Name'),
        read('Bands/$id/isMock'),
        read('Bands/$id/isDemo'),
      ]);
      final name = metadata[0];
      if (name is! String || name.trim().isEmpty || metadata[1] == true || metadata[2] == true) continue;
      result[id] = name;
    }
    return result;
  }

  static bool isMember(Band? band, String? uid) =>
      uid != null && uid.isNotEmpty && band != null &&
      isRealId(band.id) && (band.name?.trim().isNotEmpty ?? false) &&
      band.membersBand.containsKey(uid);

  static bool canStaff(Band? band, String? uid) {
    if (!isMember(band, uid)) return false;
    final role = band!.membersBand[uid]!.role?.trim().toLowerCase();
    return role == 'leader' || role == 'admin';
  }
}
