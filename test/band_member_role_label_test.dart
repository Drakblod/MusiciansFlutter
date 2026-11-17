import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/utils/band_member_role_label.dart';

void main() {
  test('formats only the exact Bandleader membership role', () {
    expect(bandMemberRoleLabel('Leader'), 'Bandleader');
    expect(bandMemberRoleLabel(' LEADER '), 'Bandleader');
    for (final role in ['Admin', 'Member', 'MOD', 'Leader helper', 'BANDLEADER']) {
      expect(bandMemberRoleLabel(role), role);
    }
    expect(bandMemberRoleLabel(null), 'Member');
  });
}
