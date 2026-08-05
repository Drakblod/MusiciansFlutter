import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/mock_live_rehearsal.dart';

/// Pre-configured mock live rehearsal broadcast sources for prototype testing.
const List<MockLiveRehearsal> mockLiveRehearsals = [
  MockLiveRehearsal(
    id: 'live_rehearsal_stockholm',
    bandName: 'Neon Harbor',
    city: 'Stockholm',
    position: LatLng(59.3293, 18.0686),
    audioAssetPath: 'audio/bandrep1.mp3',
    genre: 'Indie Rock / Synth',
  ),
  MockLiveRehearsal(
    id: 'live_rehearsal_umea',
    bandName: 'Northern Echo',
    city: 'Umeå',
    position: LatLng(63.8258, 20.2630),
    audioAssetPath: 'audio/bandrep2.mp3',
    genre: 'Alternative / Post-Rock',
  ),
  MockLiveRehearsal(
    id: 'live_rehearsal_la',
    bandName: "Guns N' Roses (1980s Mock Tape)",
    city: 'Los Angeles',
    position: LatLng(34.0522, -118.2437),
    audioAssetPath: 'audio/bandrep3.mp3',
    genre: 'Hard Rock',
  ),
];
