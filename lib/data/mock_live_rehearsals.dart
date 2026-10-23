import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/mock_live_rehearsal.dart';

/// Pre-configured mock live rehearsal broadcast sources with structured timestamps.
List<MockLiveRehearsal> getMockLiveRehearsals({DateTime? now}) {
  final current = now ?? DateTime.now();
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
      dateTime: 'Thursday, Oct 23, 2026 - 6.00 PM 9.00 PM',
      description: 'Pre-production band rehearsal broadcasting live. Testing new track arrangements for the winter tour.',
      startDateTime: current.subtract(const Duration(hours: 1)),
      endDateTime: current.add(const Duration(hours: 2)),
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
      dateTime: 'Wednesday, Oct 22, 2026 - 7.00 PM 10.00 PM',
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
      dateTime: 'Friday, Oct 24, 2026 - 6.00 PM 9.00 PM',
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
      dateTime: 'Saturday, Oct 25, 2026 - 8.00 PM 11.00 PM',
      description: 'Vintage rock rehearsal archives broadcasting continuous audio stream.',
      startDateTime: current.subtract(const Duration(days: 2, hours: 3)),
      endDateTime: current.subtract(const Duration(days: 2)),
      isLiveBroadcast: false,
    ),
  ];
}

/// Pre-configured mock live rehearsal broadcast sources for prototype testing.
List<MockLiveRehearsal> get mockLiveRehearsals => getMockLiveRehearsals();
