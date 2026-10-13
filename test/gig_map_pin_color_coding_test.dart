import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/models/sub_request.dart';

void main() {
  group('Map Pin Color Coding & Event Type Classification Tests', () {
    test('1. Classifies live concert/gig to MapEventType.gig and hueRed', () {
      final gig = SubRequest(
        role: 'Rock Guitarist Needed',
        requestType: 'Gig',
        description: 'Live concert show this Friday evening',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.gig);
      expect(MapEventTypeHelper.getLabel(type), 'Gig / Live Show');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFFEF4444));
      expect(MapEventTypeHelper.getIcon(type), Icons.stadium_rounded);
    });

    test('2. Classifies band rehearsal to MapEventType.rehearsal and hueMagenta', () {
      final gig = SubRequest(
        role: 'Bassist Needed',
        requestType: 'Rehearsal',
        description: 'Weekly band rehearsal in studio',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.rehearsal);
      expect(MapEventTypeHelper.getLabel(type), 'Rehearsal');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFFD946EF));
      expect(MapEventTypeHelper.getIcon(type), Icons.music_note_rounded);
    });

    test('3. Classifies new member / audition to MapEventType.newMember and hueGreen', () {
      final gig = SubRequest(
        role: 'Seeking Drummer',
        requestType: 'New Member',
        description: 'Audition for permanent band member',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.newMember);
      expect(MapEventTypeHelper.getLabel(type), 'New Member');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFF10B981));
      expect(MapEventTypeHelper.getIcon(type), Icons.person_add_alt_1_rounded);
    });

    test('4. Classifies jam session / workshop to MapEventType.jamSession and hueAzure', () {
      final gig = SubRequest(
        role: 'Open Jam',
        requestType: 'Jam Session',
        description: 'Open stage jazz jam session',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.jamSession);
      expect(MapEventTypeHelper.getLabel(type), 'Jam Session');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFF38BDF8));
      expect(MapEventTypeHelper.getIcon(type), Icons.groups_rounded);
    });

    test('5. Classifies studio / recording to MapEventType.studio and hueOrange', () {
      final gig = SubRequest(
        role: 'Studio Recording',
        requestType: 'Recording Session',
        description: 'Pro studio session for EP recording',
      );
      final type = MapEventTypeHelper.getEventType(gig);
      expect(type, MapEventType.studio);
      expect(MapEventTypeHelper.getLabel(type), 'Studio / Recording');
      expect(MapEventTypeHelper.getColor(type), const Color(0xFFF59E0B));
      expect(MapEventTypeHelper.getIcon(type), Icons.mic_rounded);
    });
  });
}
