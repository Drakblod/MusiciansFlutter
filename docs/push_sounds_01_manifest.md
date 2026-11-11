# Push Sounds 01

The owner masters are external to the repository. Each source is a stereo 48 kHz, 24-bit PCM WAV. Trim the exact windows below, preserve internal pauses, downmix with equal left and right gains, then apply 5 ms and 40 ms edge fades and the listed static gain. Resample to 44.1 kHz and use triangular dither for signed 16-bit little-endian mono PCM WAV. Target −18 LUFS integrated within 1 LU, with a −2 dBTP ceiling. Measurements use FFmpeg EBU R128 loudness and true peak.

| Source filename | Source SHA-256 | Trim, s | Gain, dB |
| --- | --- | --- | ---: |
| `session_Ringsignaler Stevie 1 Vib NY_Wav (Tagged+Normalized).wav` | `badabd853188b700106415ca0b4d7eddbd6df9067fc813e17e1d7ce412aafb4a` | 0.04–5.61 | −0.4 |
| `session_Ringsignaler One. Vib. A (Sept 27)_Wav (Tagged+Normalized).wav` | `94c7ac223ff18d9cf34e6e697ed49b352b0a6564ddefd70829fd858840d4ef90` | 0.21–3.18 | −3.1 |
| `session_Ringsignaler Summer Mar. D (Sept 27)_Wav (Tagged+Normalized).wav` | `89af50cd1b3e909dabaa2a8ca8972ac5510544423c311cc0c9d832f5c0919666` | 0.04–4.07 | +0.5 |
| `session_Ringsignaler Always Vib. Eb (Sept 27)_Wav (Tagged+Normalized).wav` | `ac0fc98f6b0b3b433acccdf073b53cc7eabeffbd5c918c3c1145c96805442b6f` | 0.38–4.65 | −2.1 |

Each output filename is the APNs sound name. Android uses the stem. The Android raw resource, iOS Runner resource and Flutter tester copy are byte-identical.

| Output filename | Duration, s | LUFS | dBTP | Output SHA-256 | Notification types | Android channel |
| --- | ---: | ---: | ---: | --- | --- | --- |
| `notification_gig_request_v2.wav` | 5.57 | −17.75 | −2.77 | `fa847191acb4c6b3ce73f0a985d87ac76734a0031039365195abd37eb093680d` | `sub_request_invite`, `grouped_sub_request` | `gig_request_channel_v2` |
| `notification_gig_response_v2.wav` | 2.97 | −18.06 | −5.77 | `5df676f51c9707dc92734de2f95e22134e1fbc1af39a957aab108cf9c7ebed4f` | `sub_request_response`, `session_application`, `session_application_status` | `gig_response_channel_v2` |
| `notification_event_rsvp_v2.wav` | 4.03 | −18.30 | −2.13 | `a08a50704999a843bbbdd40c374889e8c8b66f2852979bd1ffecdaa688a5d4b5` | `event_invite`, `event_reminder`, `event_threshold` | `rsvp_reminder_channel_v2` |
| `notification_gig_confirmed_v2.wav` | 4.27 | −18.54 | −4.42 | `8ff200758efcabfbc7ef3084b648fc60829c6d251216de6d4897c548708c0f45` | `gig_finalized` | `finalized_gig_channel_v2` |
| System sound | — | — | — | — | `band_section_chat` | `chat_notifications_v2` |

Direct messages, session messages, Band Room messages and band file uploads remain Notification Center only. The admin tester uses the same four files for media previews. OS notification volume requires a device push test.

Native setup checks its resources before the installation advertises `android-v2` or `ios-v2`. The server accepts only these profile values and resolves every sound through a fixed allowlist. Older installations that already use the V2 registry retain the existing four custom mappings. Band Section remains Notification Center only on bindings without a supported sound profile because those bindings do not identify the platform and legacy Android has no registered chat channel. APNs uses `default` for Band Section. Android uses its registered system-sound chat channel.

Android 8 and later store notification settings per channel. The new channels are registered with high importance and use the new sounds by default. Android cannot copy every user preference to a new channel. Previous channel IDs and resources stay available, and users can adjust the new channels in Android settings. The new client leaves missing-channel fallback to Firebase's system channel. Previously installed builds retain their own manifest and guitar default. Compatible native builds and real-device tests are required before release. The separate V2 notification rollout and paused reminder scheduler are outside this implementation.
