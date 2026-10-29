import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubRequest Response Count Isolation', () {
    test('External invitees belonging to another subrequest on the same event are not counted', () {
      final currentSubRequestId = 'sub_Deku_Tree_Bongo_freelance_event_draft_initial_0_1793234211885';
      final otherSubRequestId = 'sub_Deku_Tree_Bongo_freelance_event_draft_initial_0';

      final externalInviteesRaw = {
        'user_past_1': {
          'displayName': 'MatsHtest_26',
          'source': 'subRequest',
          'status': 'pending',
          'subRequestId': otherSubRequestId,
        },
        'user_past_2': {
          'displayName': 'KristoferE26',
          'source': 'subRequest',
          'status': 'attending',
          'subRequestId': otherSubRequestId,
        },
        'user_past_3': {
          'displayName': 'AlexHTest',
          'source': 'subRequest',
          'status': 'attending',
          'subRequestId': otherSubRequestId,
        },
      };

      final Map<String, dynamic> combined = {};
      externalInviteesRaw.forEach((k, v) {
        if (v is Map) {
          final linkedSubId = v['subRequestId'] ?? v['SubRequestId'];
          if (linkedSubId != null && linkedSubId.toString() == currentSubRequestId) {
            combined[k.toString()] = true;
          }
        }
      });

      expect(combined.length, 0, reason: 'New request must not inherit replies from previous subrequests');

      // Now add a genuine response for the current subrequest
      final currentInviteesRaw = Map<String, dynamic>.from(externalInviteesRaw);
      currentInviteesRaw['user_new_1'] = {
        'displayName': 'New Musician',
        'source': 'subRequest',
        'status': 'attending',
        'subRequestId': currentSubRequestId,
      };

      final Map<String, dynamic> combinedWithCurrent = {};
      currentInviteesRaw.forEach((k, v) {
        if (v is Map) {
          final linkedSubId = v['subRequestId'] ?? v['SubRequestId'];
          if (linkedSubId != null && linkedSubId.toString() == currentSubRequestId) {
            combinedWithCurrent[k.toString()] = true;
          }
        }
      });

      expect(combinedWithCurrent.length, 1);
      expect(combinedWithCurrent.containsKey('user_new_1'), true);
    });
  });
}
