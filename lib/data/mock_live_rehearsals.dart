import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../models/mock_live_rehearsal.dart';

/// Pre-configured mock live rehearsal broadcast sources with structured timestamps.
List<MockLiveRehearsal> getMockLiveRehearsals({DateTime? now}) {
  final current = now ?? DateTime.now();
  final tomorrowStr = DateFormat('EEEE, MMM d, yyyy').format(current.add(const Duration(days: 1)));
  final inTwoDaysStr = DateFormat('EEEE, MMM d, yyyy').format(current.add(const Duration(days: 2)));
  final twoDaysAgoStr = DateFormat('EEEE, MMM d, yyyy').format(current.subtract(const Duration(days: 2)));

  return [
    MockLiveRehearsal(
      id: 'live_rehearsal_stockholm',
      bandName: 'Neon Harbor',
      city: 'Stockholm',
      position: const LatLng(59.3293, 18.0686),
      audioAssetPath: 'audio/bandrep1.mp3',
      genre: 'Indie / Alternative',
      venue: 'Södermalm Rehearsal Studio',
      location: 'Södermalm Rehearsal Studio, Stockholm',
      dateTime: 'Friday, Oct 23, 2026 · 6.00 PM - 9.00 PM',
      description: 'Pre-production band rehearsal broadcasting live. Testing new track arrangements for the winter tour.',
      startDateTime: DateTime(2026, 10, 23, 18, 0),
      endDateTime: DateTime(2026, 10, 23, 21, 0),
      isLiveBroadcast: true,
    ),
    MockLiveRehearsal(
      id: 'live_rehearsal_umea',
      bandName: 'Northern Echo',
      city: 'Umeå',
      position: const LatLng(63.8258, 20.2630),
      audioAssetPath: 'audio/bandrep2.mp3',
      genre: 'Indie / Alternative',
      venue: 'Umeå Musikstudio',
      location: 'Umeå Musikstudio, Västerslätt, Umeå',
      dateTime: '$tomorrowStr · 7.00 PM - 10.00 PM',
      description: 'Weekly full-band rehearsal broadcasting live from Umeå. Preparing songs for upcoming festival gigs.',
      startDateTime: current.add(const Duration(days: 1)),
      endDateTime: current.add(const Duration(days: 1, hours: 3)),
      isLiveBroadcast: false,
    ),
    MockLiveRehearsal(
      id: 'live_rehearsal_gothenburg',
      bandName: 'West Coast Fusion',
      city: 'Göteborg',
      position: const LatLng(57.7089, 11.9746),
      audioAssetPath: 'audio/bandrep3.mp3',
      genre: 'Funk',
      venue: 'Musikens Hus',
      location: 'Musikens Hus, Karl Johansgatan 16, Göteborg',
      dateTime: '$inTwoDaysStr · 6.00 PM - 9.00 PM',
      description: 'Live funk/fusion rehearsal session broadcasting direct from Majorna, Göteborg.',
      startDateTime: current.add(const Duration(days: 2)),
      endDateTime: current.add(const Duration(days: 2, hours: 3)),
      isLiveBroadcast: false,
    ),
    MockLiveRehearsal(
      id: 'live_rehearsal_la',
      bandName: "Guns N' Roses (1980s Mock Tape)",
      city: 'Los Angeles',
      position: const LatLng(34.0522, -118.2437),
      audioAssetPath: 'audio/bandrep3.mp3',
      genre: 'Rock',
      venue: 'Sunset Sound',
      location: 'Sunset Sound, Hollywood, Los Angeles',
      dateTime: '$twoDaysAgoStr · 8.00 PM - 11.00 PM (Ended)',
      description: 'Vintage rock rehearsal archives broadcasting continuous audio stream.',
      startDateTime: current.subtract(const Duration(days: 2, hours: 3)),
      endDateTime: current.subtract(const Duration(days: 2)),
      isLiveBroadcast: false,
    ),
  ];
}

/// Pre-configured mock live rehearsal broadcast sources for prototype testing.
List<MockLiveRehearsal> get mockLiveRehearsals => getMockLiveRehearsals();

/// Explicit QA / test fixture representing an active live rehearsal.
MockLiveRehearsal createActiveMockLiveRehearsalFixture({DateTime? now}) {
  final current = now ?? DateTime.now();
  return MockLiveRehearsal(
    id: 'qa_active_live_rehearsal',
    bandName: 'QA Active Live Band',
    city: 'Stockholm',
    position: const LatLng(59.3293, 18.0686),
    audioAssetPath: 'audio/bandrep1.mp3',
    genre: 'Indie / Alternative',
    venue: 'QA Live Studio',
    location: 'QA Live Studio, Stockholm',
    dateTime: 'Live Now · 6.00 PM - 9.00 PM',
    description: 'Explicit active rehearsal fixture for QA and testing.',
    startDateTime: current.subtract(const Duration(hours: 1)),
    endDateTime: current.add(const Duration(hours: 2)),
    isLiveBroadcast: true,
  );
}
