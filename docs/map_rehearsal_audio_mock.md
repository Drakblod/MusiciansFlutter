# Proximity-Based Mock Live Rehearsal Audio Prototype

## Overview
This feature is a safe, isolated proof-of-concept for live band rehearsal audio inside the **Discovery Map** (`lib/views/gig_map_page.dart`).

> [!NOTE]
> This is a mockup. It does NOT use real audio streaming, microphone recording, Firebase audio uploads, or WebRTC backends.

## Mock Bands & Audio Files
1. **Stockholm**
   - **Band**: Neon Harbor
   - **Location**: `59.3293, 18.0686`
   - **Audio File**: `assets/audio/bandrep1.mp3`
2. **Umeå**
   - **Band**: Northern Echo
   - **Location**: `63.8258, 20.2630`
   - **Audio File**: `assets/audio/bandrep2.mp3`

## Audio Behavior & Distance Formula
- **Camera Target Distance**: Distance is calculated in kilometers between the map camera center (`position.target`) and each rehearsal marker using the Haversine formula (`lib/utils/geo_distance.dart`).
- **Audible Radius**: `250.0 km`.
- **Volume Curve**:
  - Distance ≥ 250 km: Volume = `0.0` (Silent).
  - Distance < 250 km: Volume starts at `0.10` (10%) at the 250 km boundary and smoothly increases quadratically (`eased = normalized^2`) up to `1.0` (100%) at the band's exact coordinates.
- **Dominant Rehearsal Rule**: The nearest audible band gets its full calculated volume curve; secondary audible bands are capped at a maximum of `0.20` (20%) to prevent harsh overlapping audio.
- **Smooth Fading**: Volume adjustments use smooth 300ms step interpolation.

## Controls & Web Autoplay
- **Mute / Unmute Overlay**: A compact pill widget on the map allows muting/unmuting live rehearsal audio.
- **Web Autoplay Unlock**: On Flutter Web, if browser autoplay policy blocks audio initialization, an **"Enable rehearsal audio"** button appears on the map overlay for user gesture unlock.

## Disabling or Removing the Feature
- **Feature Flag**: Set `enableMockLiveRehearsals = false` in `lib/config/feature_flags.dart`.
- When set to `false`, no audio players are initialized, no rehearsal markers are rendered, and Discovery Map behaves strictly as normal.
- **Complete Removal**: Delete `lib/models/mock_live_rehearsal.dart`, `lib/data/mock_live_rehearsals.dart`, `lib/services/mock_rehearsal_audio_controller.dart`, `lib/config/feature_flags.dart`, `lib/utils/geo_distance.dart`, `assets/audio/`, and remove the integration lines in `lib/views/gig_map_page.dart`.
