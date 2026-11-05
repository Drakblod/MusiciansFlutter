import '../models/band.dart';

class BandMembershipPolicy {
  BandMembershipPolicy._();

  // A hold pauses RSVP obligations, not band access. Missing status is legacy active.
  static bool isValidStatus(Object? status) => status == null ||
      (status is String && {'active', 'on_hold', 'temporarily_off'}.contains(status.trim().toLowerCase()));

  static bool isRealId(String? id) {
    final value = id?.trim().toLowerCase() ?? '';
    return value.isNotEmpty &&
        !RegExp(r'[.#$\[\]/]').hasMatch(value) &&
        !RegExp(r'^(mock|demo)(?:[_-]|$)').hasMatch(value) &&
        !{'freelance', 'standalone', 'all', 'null', 'none', 'undefined'}.contains(value);
  }

  /// Server-owned entries are candidate references, never permissions.
  /// The callback is read-only; normal discovery never reads the /Bands root.
  static Future<Map<String, String>> discover(
    String uid, Future<Object?> Function(String path) read,
  ) async {
    final index = await read('userBandMembershipIndex/$uid');
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
      if (member is! Map || !isValidStatus(member['Status'] ?? member['status'])) continue;
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
      band.membersBand.containsKey(uid) && isValidStatus(band.membersBand[uid]!.status);

  static bool canStaff(Band? band, String? uid) {
    if (!isMember(band, uid)) return false;
    return canManageMember(band!.membersBand[uid]);
  }
  static bool canManageMember(BandMember? member) {
    if (member == null || !isValidStatus(member.status)) return false;
    final role = member.role?.trim().toLowerCase();
    return role == 'leader' || role == 'admin';
  }

}
