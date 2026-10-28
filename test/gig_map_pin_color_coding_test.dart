import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/models/sub_request.dart';

void main() {
  group('Map Pin Color Coding & Event Type Classification Tests (Owner Specification)', () {
    test('1. Category Music: Gig/Concert/Live Performance is Orange (#F97316)', () {
      final gig = SubRequest(
        role: 'Rock Guitarist Needed',
        requestType: 'Gig',
        description: 'Live gig performance this Friday evening',
        extraFields: {'eventType': 'gigConcert'},
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.gigConcert);
      expect(MapEventTypeHelper.getCategory(type), MapCategory.music);
      expect(MapEventTypeHelper.getLabel(type), 'Gig');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFFF97316));
      expect(MapEventTypeHelper.getIcon(type), Icons.music_note_rounded);
    });

    test('2. Category Music: Rehearsal is Röd (#EF4444)', () {
      final gig = SubRequest(
        role: 'Horn Section',
        requestType: 'Rehearsal',
        description: 'Weekly band rehearsal in studio',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.rehearsal);
      expect(MapEventTypeHelper.getCategory(type), MapCategory.music);
      expect(MapEventTypeHelper.getLabel(type), 'Rehearsal');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFFEF4444));
      expect(MapEventTypeHelper.getIcon(type), Icons.groups_rounded);
    });

    test('3. Category Music: Jam Session is Turkos (#06B6D4)', () {
      final gig = SubRequest(
        role: 'Open Jam',
        requestType: 'Jam Session',
        description: 'Open stage jazz jam session',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.jamSession);
      expect(MapEventTypeHelper.getCategory(type), MapCategory.music);
      expect(MapEventTypeHelper.getLabel(type), 'Jam Session');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFF06B6D4));
      expect(MapEventTypeHelper.getIcon(type), Icons.groups_rounded);
    });

    test('4. Category Music: Recorded Music is Mörkblå (#2563EB)', () {
      final gig = SubRequest(
        role: 'Studio Recording',
        requestType: 'Recording Session',
        description: 'Studio recording session for EP',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.recordedMusic);
      expect(MapEventTypeHelper.getCategory(type), MapCategory.music);
      expect(MapEventTypeHelper.getLabel(type), 'Recorded Music');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFF2563EB));
      expect(MapEventTypeHelper.getIcon(type), Icons.album_rounded);
    });

    test('5. Category Gig Promo: Gig Promo is Lila (#A855F7)', () {
      final gig = SubRequest(
        role: 'Festival Promo',
        requestType: 'Gig Promo',
        description: 'Promo for upcoming festival tour',
        extraFields: {'eventType': 'gigPromo'},
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.gigPromo);
      expect(MapEventTypeHelper.getCategory(type), MapCategory.gigPromo);
      expect(MapEventTypeHelper.getLabel(type), 'Gig Promo');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFFA855F7));
      expect(MapEventTypeHelper.getIcon(type), Icons.campaign_rounded);
    });

    test('6. Category Sub & Member Search: New Member is Mörkgrön (#047857)', () {
      final gig = SubRequest(
        role: 'Seeking Drummer',
        requestType: 'New Member',
        description: 'Audition for permanent band member',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.newMember);
      expect(MapEventTypeHelper.getCategory(type), MapCategory.subAndMember);
      expect(MapEventTypeHelper.getLabel(type), 'New Member');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFF047857));
      expect(MapEventTypeHelper.getIcon(type), Icons.person_add_alt_1_rounded);
    });

    test('7. Category Sub & Member Search: Subs is Lime grön (#84CC16)', () {
      final gig = SubRequest(
        role: 'Substitute Trombone',
        requestType: 'Subs',
        description: 'Sub needed for weekend gig',
        extraFields: {'eventType': 'subs'},
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.subs);
      expect(MapEventTypeHelper.getCategory(type), MapCategory.subAndMember);
      expect(MapEventTypeHelper.getLabel(type), 'Substitute');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFF84CC16));
      expect(MapEventTypeHelper.getIcon(type), Icons.swap_horiz_rounded);
    });

    test('8. Category Sub & Member Search: Paid is Gul (#EAB308)', () {
      final gig = SubRequest(
        role: 'Paid Lead Guitar',
        requestType: 'Paid',
        isPaid: true,
        payAmount: 4000,
        extraFields: {'eventType': 'paid'},
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.paid);
      expect(MapEventTypeHelper.getCategory(type), MapCategory.subAndMember);
      expect(MapEventTypeHelper.getLabel(type), 'Paid Gigs');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFFEAB308));
      expect(MapEventTypeHelper.getIcon(type), Icons.payments_rounded);
    });
  });
}
