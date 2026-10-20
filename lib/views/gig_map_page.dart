import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'edit_band_info_screen.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../models/user_profile.dart';
import '../config/feature_flags.dart';
import '../models/mock_live_rehearsal.dart';
import '../data/mock_live_rehearsals.dart';
import '../data/genres_taxonomy.dart';
import '../data/skills_taxonomy.dart';
import '../services/mock_rehearsal_audio_controller.dart';
import '../widgets/map_crosshair.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/audio_snippet_player.dart';
import '../widgets/what_is_map_view_dialog.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';
import '../utils/map_crosshair_targeting.dart';
import '../models/live_broadcast.dart';
import '../services/live_broadcast_service.dart';
import '../services/livekit_audio_controller.dart';
import '../widgets/start_live_broadcast_dialog.dart';
import '../widgets/live_broadcaster_bar.dart';
import '../widgets/live_listener_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapCategory {
  music,
  gigPromo,
  subAndMember,
}

enum MapEventType {
  // Category: Music
  gigConcert, // Orange (#F97316)
  rehearsal,  // Röd (#EF4444)
  jamSession, // Turkos (#06B6D4)
  recordedMusic, // Mörkblå (#2563EB)

  // Category: Gig Promo
  gigPromo,   // Lila (#A855F7)

  // Category: Sub & Member Search
  newMember,  // Mörkgrön (#047857)
  subs,       // Lime grön (#84CC16)
  paid,       // Gul (#EAB308)
}

class MapEventTypeHelper {
  // Aliases for compatibility
  static const MapEventType gig = MapEventType.gigConcert;
  static const MapEventType studio = MapEventType.recordedMusic;

  static MapCategory getCategory(MapEventType type) {
    switch (type) {
      case MapEventType.gigConcert:
      case MapEventType.rehearsal:
      case MapEventType.jamSession:
      case MapEventType.recordedMusic:
        return MapCategory.music;
      case MapEventType.gigPromo:
        return MapCategory.gigPromo;
      case MapEventType.newMember:
      case MapEventType.subs:
      case MapEventType.paid:
        return MapCategory.subAndMember;
    }
  }

  static MapEventType getEventType(SubRequest gig) {
    final explicitType = gig.extraFields["eventType"]?.toString().toLowerCase();
    if (explicitType == 'gigconcert' || explicitType == 'gig_concert') return MapEventType.gigConcert;
    if (explicitType == 'rehearsal') return MapEventType.rehearsal;
    if (explicitType == 'jamsession' || explicitType == 'jam_session') return MapEventType.jamSession;
    if (explicitType == 'recordedmusic' || explicitType == 'recorded_music' || explicitType == 'studio') return MapEventType.recordedMusic;
    if (explicitType == 'gigpromo' || explicitType == 'gig_promo') return MapEventType.gigPromo;
    if (explicitType == 'newmember' || explicitType == 'new_member') return MapEventType.newMember;
    if (explicitType == 'subs' || explicitType == 'sub') return MapEventType.subs;
    if (explicitType == 'paid') return MapEventType.paid;

    final text = '${gig.requestType ?? ""} ${gig.role ?? ""} ${gig.eventTitle ?? ""} ${gig.description ?? ""}'.toLowerCase();

    // 1. Gig Promo (Lila)
    if (text.contains('gig promo') || text.contains('promo')) {
      return MapEventType.gigPromo;
    }

    // 2. Sub & Member Search
    // 2a. New Member (Mörkgrön)
    if (text.contains('new member') ||
        text.contains('ny medlem') ||
        text.contains('audition') ||
        text.contains('permanent') ||
        text.contains('join the band') ||
        text.contains('söker musiker')) {
      return MapEventType.newMember;
    }

    // 2b. Paid (Gul)
    if (gig.isPaid && (text.contains('paid') || text.contains('betalt') || (gig.payAmount != null && gig.payAmount! > 0 && text.contains('gig')))) {
      if (!text.contains('concert') && !text.contains('rehearsal')) {
        return MapEventType.paid;
      }
    }

    // 2c. Subs (Lime grön)
    if (text.contains('sub') || text.contains('vikarie') || (gig.requestType?.toLowerCase() == 'sub')) {
      if (!text.contains('rehearsal') && !text.contains('concert')) {
        return MapEventType.subs;
      }
    }

    // 3. Music
    // 3a. Rehearsal (Röd)
    if ((gig.rehearsalDayOfWeek != null && gig.rehearsalDayOfWeek!.isNotEmpty) ||
        gig.requestType?.toLowerCase() == 'rehearsal' ||
        text.contains('rehearsal') ||
        text.contains('repetition') ||
        text.contains('bandrep')) {
      if (!text.contains('live gig') && !text.contains('concert')) {
        return MapEventType.rehearsal;
      }
    }

    // 3b. Recorded Music (Mörkblå)
    if (text.contains('recorded music') ||
        text.contains('inspelad musik') ||
        text.contains('studio recording') ||
        text.contains('recording session') ||
        text.contains('studio session') ||
        text.contains('recording') ||
        text.contains('inspelning') ||
        text.contains('album') ||
        text.contains('single') ||
        text.contains('studio')) {
      return MapEventType.recordedMusic;
    }

    // 3c. Jam Session (Turkos)
    if (text.contains('jam') ||
        text.contains('workshop') ||
        text.contains('open stage') ||
        text.contains('öppen scen') ||
        text.contains('session')) {
      return MapEventType.jamSession;
    }

    // 3d. Default: Gig / Concert / Live Performance (Orange)
    return MapEventType.gigConcert;
  }

  static Future<BitmapDescriptor> createNoteBitmap({
    required Color color,
    required bool isHalfNote,
    double opacity = 1.0,
    bool hasGlow = false,
  }) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);

    // Canvas size (2x resolution for retina / crisp display)
    const double canvasWidth = 68.0;
    const double canvasHeight = 92.0;

    // Egg-shaped notehead center in canvas
    const double headCenterX = 24.0;
    const double headCenterY = 66.0;
    const double headRadiusX = 14.5; // Egg width radius
    const double headRadiusY = 10.0; // Egg height radius
    const double tiltAngle = -22.0 * (math.pi / 180.0); // Tilted ~ -22°

    // Stem: vertical shaft rising from right edge of notehead
    const double stemX = headCenterX + 11.2;
    const double stemTopY = 14.0;
    const double stemBottomY = headCenterY + 2.0;
    const double stemWidth = 3.6;

    final noteColor = color.withValues(alpha: opacity);

    // 1. Shadow / Glow for high contrast on both white and dark maps
    final shadowPaint = Paint()
      ..color = hasGlow
          ? color.withValues(alpha: 0.65 * opacity)
          : Colors.black.withValues(alpha: 0.35 * opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, hasGlow ? 4.5 : 2.5);

    // Draw shadow under notehead
    canvas.save();
    canvas.translate(headCenterX, headCenterY);
    canvas.rotate(tiltAngle);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(1.0, 1.5),
        width: headRadiusX * 2 + (hasGlow ? 4.0 : 2.0),
        height: headRadiusY * 2 + (hasGlow ? 4.0 : 2.0),
      ),
      shadowPaint,
    );
    canvas.restore();

    // Draw shadow under stem
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          stemX - stemWidth / 2 + 1.0,
          stemTopY + 1.0,
          stemWidth + (hasGlow ? 2.0 : 0.0),
          (stemBottomY - stemTopY) + (hasGlow ? 2.0 : 0.0),
        ),
        const Radius.circular(2.0),
      ),
      shadowPaint,
    );

    // 2. Outlines & Note Paints
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.40 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final notePaint = Paint()
      ..color = noteColor
      ..style = PaintingStyle.fill;

    // 3. Draw Stem
    final stemRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(stemX - stemWidth / 2, stemTopY, stemWidth, stemBottomY - stemTopY),
      const Radius.circular(1.8),
    );
    canvas.drawRRect(stemRRect, outlinePaint);
    canvas.drawRRect(stemRRect, notePaint);

    // 4. Draw Egg-Shaped Notehead
    canvas.save();
    canvas.translate(headCenterX, headCenterY);
    canvas.rotate(tiltAngle);

    final outerHeadRect = Rect.fromCenter(
      center: Offset.zero,
      width: headRadiusX * 2,
      height: headRadiusY * 2,
    );

    if (isHalfNote) {
      // Halvnot: Open / hollow egg-shaped notehead
      canvas.drawOval(outerHeadRect, outlinePaint);
      canvas.drawOval(outerHeadRect, notePaint);

      // Inner cutout: tilted steeper (-18 deg relative to note angle)
      canvas.rotate(-18.0 * (math.pi / 180.0));
      final innerHeadRect = Rect.fromCenter(
        center: Offset.zero,
        width: headRadiusX * 1.08,
        height: headRadiusY * 0.70,
      );

      final clearPaint = Paint()..blendMode = BlendMode.clear;
      canvas.drawOval(innerHeadRect, clearPaint);
      canvas.drawOval(innerHeadRect, outlinePaint);
    } else {
      // Fjärdedelsnot: Solid filled egg-shaped notehead
      canvas.drawOval(outerHeadRect, outlinePaint);
      canvas.drawOval(outerHeadRect, notePaint);
    }

    canvas.restore();

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(canvasWidth.toInt(), canvasHeight.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    // Rendered on map at 34x46 points
    return BitmapDescriptor.bytes(bytes, width: 34, height: 46);
  }

  static Future<BitmapDescriptor> createWebPinBitmap(Color color) async {
    return createNoteBitmap(color: color, isHalfNote: false);
  }

  static BitmapDescriptor getMarkerIcon(MapEventType type) {
    switch (type) {
      case MapEventType.gigConcert:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case MapEventType.rehearsal:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      case MapEventType.jamSession:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
      case MapEventType.recordedMusic:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      case MapEventType.gigPromo:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      case MapEventType.newMember:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      case MapEventType.subs:
        return BitmapDescriptor.defaultMarkerWithHue(85.0);
      case MapEventType.paid:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
  }

  static Color getColor(MapEventType type) {
    switch (type) {
      case MapEventType.gigConcert:
        return const Color(0xFFF97316); // Orange
      case MapEventType.rehearsal:
        return const Color(0xFFEF4444); // Röd
      case MapEventType.jamSession:
        return const Color(0xFF06B6D4); // Turkos
      case MapEventType.recordedMusic:
        return const Color(0xFF2563EB); // Mörkblå
      case MapEventType.gigPromo:
        return const Color(0xFFA855F7); // Lila
      case MapEventType.newMember:
        return const Color(0xFF047857); // Mörkgrön
      case MapEventType.subs:
        return const Color(0xFF84CC16); // Lime grön
      case MapEventType.paid:
        return const Color(0xFFEAB308); // Gul
    }
  }

  static String getLabel(MapEventType type) {
    switch (type) {
      case MapEventType.gigConcert:
        return 'Gig / Concert';
      case MapEventType.rehearsal:
        return 'Rehearsal';
      case MapEventType.jamSession:
        return 'Jam Session';
      case MapEventType.recordedMusic:
        return 'Recorded Music';
      case MapEventType.gigPromo:
        return 'Gig Promo';
      case MapEventType.newMember:
        return 'New Member';
      case MapEventType.subs:
        return 'Substitute';
      case MapEventType.paid:
        return 'Paid Gigs';
    }
  }

  static String getShortLabel(MapEventType type) {
    switch (type) {
      case MapEventType.gigConcert:
        return 'Gig / Concert';
      case MapEventType.rehearsal:
        return 'Rehearsal';
      case MapEventType.jamSession:
        return 'Jam Session';
      case MapEventType.recordedMusic:
        return 'Recorded Music';
      case MapEventType.gigPromo:
        return 'Gig Promo';
      case MapEventType.newMember:
        return 'New Member';
      case MapEventType.subs:
        return 'Substitute';
      case MapEventType.paid:
        return 'Paid Gigs';
    }
  }

  static IconData getIcon(MapEventType type) {
    switch (type) {
      case MapEventType.gigConcert:
        return Icons.stadium_rounded;
      case MapEventType.rehearsal:
        return Icons.music_note_rounded;
      case MapEventType.jamSession:
        return Icons.groups_rounded;
      case MapEventType.recordedMusic:
        return Icons.album_rounded;
      case MapEventType.gigPromo:
        return Icons.campaign_rounded;
      case MapEventType.newMember:
        return Icons.person_add_alt_1_rounded;
      case MapEventType.subs:
        return Icons.swap_horiz_rounded;
      case MapEventType.paid:
        return Icons.payments_rounded;
    }
  }
}


class GigMapPage extends StatefulWidget {
  const GigMapPage({super.key});

  @override
  State<GigMapPage> createState() => _GigMapPageState();
}

class _GigMapPageState extends State<GigMapPage> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  List<SubRequest> _allGigs = [];
  final Set<String> _appliedGigIds = {};
  bool _isLoading = true;
  String _selectedMainCategory = 'Music';
  String? _selectedSubCategory;
  String _instrumentQuery = '';
  final TextEditingController _instrumentSearchController = TextEditingController();
  bool _showInstrumentSearch = false;

  SubRequest? _selectedGig;
  bool _showGuideBanner = true;

  // Prototype Mock Live Rehearsal Audio State
  MockRehearsalAudioController? _audioController;
  MockLiveRehearsal? _selectedRehearsal;

  // Real Live Broadcast (LiveKit Cloud) State
  LiveBroadcastService? _liveBroadcastService;
  LiveKitAudioController? _liveKitAudioController;
  StreamSubscription<List<LiveBroadcast>>? _liveBroadcastsSubscription;
  List<LiveBroadcast> _activeRealBroadcasts = [];
  LiveBroadcast? _currentPublishingBroadcast;
  LiveBroadcast? _currentlyListeningBroadcast;

  // MAP-02 Automatic Crosshair Targeting State
  CameraPosition _currentCameraPosition = const CameraPosition(
    target: LatLng(59.3293, 18.0686),
    zoom: 5.5,
  );
  bool _isAutoSelected = false;
  String? _manuallyClosedTargetId;
  bool _isWhiteMap = true;

  static const String _darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#18142c"
      }
    ]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#8e8c9a"
      }
    ]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#18142c"
      }
    ]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#9e8bff"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#7b61ff"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#16132d"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#2c2654"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#16132d"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#8e8c9a"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#3b3370"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#18142c"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#090714"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#5e5c6a"
      }
    ]
  }
]
''';

  static const String _whiteMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#f8fafc"
      }
    ]
  },
  {
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#475569"
      }
    ]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#ffffff"
      }
    ]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#1e293b"
      }
    ]
  },
  {
    "featureType": "poi",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#ffffff"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#e2e8f0"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#64748b"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#f1f5f9"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#cbd5e1"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "transit",
    "stylers": [
      {
        "visibility": "on"
      }
    ]
  },
  {
    "featureType": "transit.line",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#cbd5e1"
      },
      {
        "visibility": "on"
      }
    ]
  },
  {
    "featureType": "transit.station",
    "stylers": [
      {
        "visibility": "on"
      }
    ]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "on"
      }
    ]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#1e293b"
      },
      {
        "visibility": "on"
      }
    ]
  },
  {
    "featureType": "transit.station.subway",
    "stylers": [
      {
        "visibility": "on"
      }
    ]
  },
  {
    "featureType": "transit.station.subway",
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "on"
      }
    ]
  },
  {
    "featureType": "transit.station.subway",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#0284c7"
      },
      {
        "visibility": "on"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#dbeafe"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#94a3b8"
      }
    ]
  }
]
''';

  Future<void> _loadMapStylePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('map_view_is_white_theme');
      if (saved != null && mounted) {
        setState(() {
          _isWhiteMap = saved;
        });
        _mapController?.setMapStyle(_isWhiteMap ? _whiteMapStyle : _darkMapStyle);
      }
    } catch (_) {}
  }

  Future<void> _toggleMapTheme(bool isWhite) async {
    if (_isWhiteMap == isWhite) return;
    setState(() {
      _isWhiteMap = isWhite;
    });
    await _mapController?.setMapStyle(_isWhiteMap ? _whiteMapStyle : _darkMapStyle);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('map_view_is_white_theme', isWhite);
    } catch (_) {}
  }

  static final Map<String, BitmapDescriptor> _notePinCache = {};
  bool _liveNoteBlinkOn = true;
  Timer? _liveBlinkTimer;

  Future<void> _initNotePins() async {
    for (final type in MapEventType.values) {
      final color = MapEventTypeHelper.getColor(type);
      final isLive = type == MapEventType.gigConcert || type == MapEventType.rehearsal;
      if (isLive) {
        final keyOn = '${type.name}_on';
        if (!_notePinCache.containsKey(keyOn)) {
          try {
            _notePinCache[keyOn] = await MapEventTypeHelper.createNoteBitmap(
              color: color,
              isHalfNote: true,
              opacity: 1.0,
              hasGlow: true,
            );
          } catch (e) {
            debugPrint('Error generating note pin $keyOn: $e');
          }
        }
        final keyDim = '${type.name}_dim';
        if (!_notePinCache.containsKey(keyDim)) {
          try {
            _notePinCache[keyDim] = await MapEventTypeHelper.createNoteBitmap(
              color: color,
              isHalfNote: true,
              opacity: 0.28,
              hasGlow: false,
            );
          } catch (e) {
            debugPrint('Error generating note pin $keyDim: $e');
          }
        }
      } else {
        final key = type.name;
        if (!_notePinCache.containsKey(key)) {
          try {
            _notePinCache[key] = await MapEventTypeHelper.createNoteBitmap(
              color: color,
              isHalfNote: false,
              opacity: 1.0,
              hasGlow: false,
            );
          } catch (e) {
            debugPrint('Error generating note pin $key: $e');
          }
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  BitmapDescriptor _getNoteDescriptor(MapEventType eventType) {
    if (eventType == MapEventType.gigConcert || eventType == MapEventType.rehearsal) {
      final key = '${eventType.name}_${_liveNoteBlinkOn ? 'on' : 'dim'}';
      if (_notePinCache.containsKey(key)) {
        return _notePinCache[key]!;
      }
    } else {
      if (_notePinCache.containsKey(eventType.name)) {
        return _notePinCache[eventType.name]!;
      }
    }
    return MapEventTypeHelper.getMarkerIcon(eventType);
  }

  String _monthShort(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }

  String _weekdayName(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    if (weekday >= 1 && weekday <= 7) return days[weekday - 1];
    return '';
  }

  String _formatTimeNice(String raw) {
    if (raw.toLowerCase().contains('am') || raw.toLowerCase().contains('pm')) return raw;
    final parts = raw.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        final period = h >= 12 ? 'PM' : 'AM';
        final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        final minuteStr = m == 0 ? '00' : (m < 10 ? '0$m' : '$m');
        return '$hour12.$minuteStr $period';
      }
    }
    return raw;
  }

  String _formatEventDateTime(SubRequest gig, MapEventType eventType) {
    final isRequest = eventType == MapEventType.newMember ||
        eventType == MapEventType.subs ||
        eventType == MapEventType.paid;

    if (isRequest) {
      DateTime? postDate;
      if (gig.createdAt != null) {
        postDate = DateTime.fromMillisecondsSinceEpoch(gig.createdAt!);
      } else if (gig.date != null) {
        postDate = DateTime.tryParse(gig.date!);
      }
      postDate ??= DateTime.now();
      final month = _monthShort(postDate.month);
      return 'Posted: $month ${postDate.day}, ${postDate.year}';
    }

    DateTime? eventDate;
    if (gig.date != null) {
      eventDate = DateTime.tryParse(gig.date!);
    }
    eventDate ??= DateTime.now();
    final weekday = (gig.rehearsalDayOfWeek != null && gig.rehearsalDayOfWeek!.trim().isNotEmpty)
        ? gig.rehearsalDayOfWeek!.trim()
        : _weekdayName(eventDate.weekday);
    final month = _monthShort(eventDate.month);
    final year = eventDate.year;

    final start = _formatTimeNice(gig.startTime ?? '18:00');
    final end = _formatTimeNice(gig.endTime ?? '21:00');

    return '$weekday, $month ${eventDate.day}, $year - $start $end';
  }

  Future<LatLng> _geocodeAddress(String address, LatLng fallback) async {
    final clean = address.trim();
    if (clean.isEmpty) return fallback;

    try {
      final encoded = Uri.encodeComponent(clean);
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$encoded&format=json&limit=1');
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'MusiciansFlutterApp/2.75.7 (info@musiciansapp.com)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat']?.toString() ?? '');
          final lon = double.tryParse(data[0]['lon']?.toString() ?? '');
          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }
    } catch (_) {}

    // Fallback dictionary for common Swedish cities/places
    final lower = clean.toLowerCase();
    if (lower.contains('solna') || lower.contains('ankdammsgatan')) return const LatLng(59.3600, 17.9980);
    if (lower.contains('lidingö') || lower.contains('agavägen')) return const LatLng(59.3620, 18.1520);
    if (lower.contains('fasching') || lower.contains('kungsgatan')) return const LatLng(59.3360, 18.0560);
    if (lower.contains('södermalm')) return const LatLng(59.3150, 18.0700);
    if (lower.contains('stockholm')) return const LatLng(59.3293, 18.0686);
    if (lower.contains('gothenburg') || lower.contains('göteborg')) return const LatLng(57.7089, 11.9746);
    if (lower.contains('malmö')) return const LatLng(55.6050, 13.0038);
    if (lower.contains('uppsala')) return const LatLng(59.8586, 17.6389);
    if (lower.contains('umeå')) return const LatLng(63.8258, 20.2630);
    if (lower.contains('linköping')) return const LatLng(58.4108, 15.6214);
    if (lower.contains('örebro')) return const LatLng(59.2753, 15.2134);
    if (lower.contains('ljusdal')) return const LatLng(61.8286, 16.0963);
    if (lower.contains('bollnäs')) return const LatLng(61.3482, 16.3946);

    return fallback;
  }

  void _openBandProfile({
    required BuildContext context,
    required String bandName,
    required String genre,
    String? aboutText,
    String? location,
    String? audioUrl,
    String? audioTitle,
  }) async {
    final appState = Provider.of<AppState>(context, listen: false);

    // If user has an active band matching this name, open their full EditBandInfoScreen
    if (appState.activeBandId != null) {
      try {
        final activeBand = await appState.firebaseService.getBandInfoAsync(appState.activeBandId!);
        if (activeBand != null && activeBand.name?.toLowerCase() == bandName.toLowerCase()) {
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditBandInfoScreen(band: activeBand)),
            );
            return;
          }
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0C20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF2E2A4E)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bandName,
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (genre.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF60A5FA).withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF60A5FA).withOpacity(0.5)),
                                ),
                                child: Text(
                                  genre,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF60A5FA),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (location != null && location.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          location,
                          style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Tab / Section: ABOUT (Prominent Band Profile About Section)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16122E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AppTheme.primaryAccent, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'ABOUT',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryAccent,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          (aboutText != null && aboutText.trim().isNotEmpty)
                              ? aboutText
                              : '$bandName is an active ensemble playing $genre, connecting with musicians and fans on the Map View.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.9),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (audioUrl != null && audioUrl.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'AUDIO TRACK',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16122E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.music_note_rounded, color: Color(0xFF60A5FA), size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  audioTitle ?? '$bandName Audio Track',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          AudioSnippetPlayer(audioUrl: audioUrl),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.mail_outline_rounded, size: 16),
                      label: Text('Contact $bandName', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Contact request sent to $bandName!')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  @override
  void initState() {
    super.initState();
    _loadMapStylePref();
    _initNotePins();
    _fetchGigs();
    WidgetsBinding.instance.addObserver(this);
    _liveBlinkTimer = Timer.periodic(const Duration(milliseconds: 750), (timer) {
      if (mounted) {
        setState(() {
          _liveNoteBlinkOn = !_liveNoteBlinkOn;
        });
      }
    });
    if (FeatureFlags.enableMockLiveRehearsals) {
      _audioController = MockRehearsalAudioController();
      _audioController!.initialize();
    }
    if (FeatureFlags.enableRealLiveBroadcasts) {
      _liveBroadcastService = LiveBroadcastService();
      _liveKitAudioController = LiveKitAudioController();
      _liveBroadcastsSubscription = _liveBroadcastService!.streamActiveBroadcasts().listen((broadcasts) {
        if (mounted) {
          final appState = Provider.of<AppState>(context, listen: false);
          final myUserId = appState.currentUserId;
          LiveBroadcast? myActiveBroadcast;
          if (myUserId != null) {
            myActiveBroadcast = broadcasts.cast<LiveBroadcast?>().firstWhere(
              (b) => b != null && b.creatorUserId == myUserId && b.status == LiveBroadcastStatus.active,
              orElse: () => null,
            );
          }

          setState(() {
            _activeRealBroadcasts = broadcasts;
            if (myActiveBroadcast != null) {
              _currentPublishingBroadcast = myActiveBroadcast;
            } else if (_currentPublishingBroadcast != null) {
              _currentPublishingBroadcast = null;
            }
          });
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _liveBlinkTimer?.cancel();
      _liveBlinkTimer = null;
    } else if (state == AppLifecycleState.resumed && _liveBlinkTimer == null) {
      _liveBlinkTimer = Timer.periodic(const Duration(milliseconds: 750), (timer) {
        if (mounted) {
          setState(() {
            _liveNoteBlinkOn = !_liveNoteBlinkOn;
          });
        }
      });
    }
    if (FeatureFlags.enableMockLiveRehearsals && _audioController != null) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
        _audioController!.pauseAudio();
      } else if (state == AppLifecycleState.resumed) {
        _audioController!.resumeAudio();
      }
    }
  }

  @override
  void dispose() {
    _liveBlinkTimer?.cancel();
    _instrumentSearchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (FeatureFlags.enableMockLiveRehearsals) {
      _audioController?.dispose();
    }
    if (FeatureFlags.enableRealLiveBroadcasts) {
      _liveBroadcastsSubscription?.cancel();
      _liveKitAudioController?.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchGigs() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final currentUserId = appState.currentUserId;
      if (currentUserId != null) {
        final applied = await appState.firebaseService.getUserAppliedSubRequestIdsAsync(currentUserId);
        _appliedGigIds.addAll(applied);
      }
      final rawGigs = await appState.firebaseService.getAllSubRequestsAsync();
      
      // Filter out gigs that have coordinates
      final dbGigsWithCoords = rawGigs.where((g) => g.latitude != null && g.longitude != null).toList();

      if (dbGigsWithCoords.isEmpty) {
        // Fallback mock markers inside Sweden covering all 8 event types
        _allGigs = [
          SubRequest(
            id: 'mock_1',
            subRequestId: 'mock_1',
            voicePart: 'Big Band',
            role: 'Gig / Concert',
            requestType: 'Gig / Concert',
            rehearsalDayOfWeek: 'Friday',
            bandName: 'Mats Holmquist Stora Stygga',
            location: 'Fasching, Kungsgatan 44',
            date: '2026-10-24T18:00:00',
            startTime: '18:00:00',
            endTime: '21:00:00',
            description: 'Äntligen är de tillbaka...',
            isPaid: false,
            latitude: 59.3340,
            longitude: 18.0560,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep1.mp3',
              'audioSnippetTitle': 'Stora Stygga Live at Fasching Demo',
              'venue': 'Fasching',
              'eventType': 'gigConcert',
              'genre': 'Big Band Contemporary',
            },
          ),
          SubRequest(
            id: 'mock_2',
            subRequestId: 'mock_2',
            voicePart: 'Bass',
            role: 'New Member',
            requestType: 'New Member',
            bandName: 'Alex Bästa',
            location: 'Ljusdal',
            date: '2026-10-12T00:00:00',
            createdAt: DateTime.parse('2026-10-12T10:00:00').millisecondsSinceEpoch,
            startTime: '18:00:00',
            endTime: '21:00:00',
            description: 'Vi söker basist med minst 10 års erfarenhet',
            isPaid: false,
            latitude: 61.8286,
            longitude: 16.0957,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep2.mp3',
              'audioSnippetTitle': 'Alex Bästa - Soul Audition Track',
              'venue': 'Ljusdals Folkpark',
              'eventType': 'newMember',
              'genre': 'Soul',
            },
          ),
          SubRequest(
            id: 'mock_3',
            subRequestId: 'mock_3',
            voicePart: 'Band Promo',
            role: 'Gig Promo',
            requestType: 'Gig Promo',
            rehearsalDayOfWeek: 'Tuesday',
            bandName: 'Matsans Home Cookin’',
            location: 'Bollnäs Folkets Hus',
            date: '2026-10-24T18:00:00',
            startTime: '18:00:00',
            endTime: '21:00:00',
            description: 'På turné i norrland oktober 2026',
            isPaid: false,
            latitude: 61.3482,
            longitude: 16.3946,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep3.mp3',
              'audioSnippetTitle': 'Matsans Home Cookin’ - Live Reggae Tour',
              'venue': 'Bollnäs Folkets Hus',
              'eventType': 'gigPromo',
              'genre': 'Reggae',
            },
          ),
          SubRequest(
            id: 'mock_3b',
            subRequestId: 'mock_3b',
            voicePart: 'Sommarkonsert',
            role: 'Sommarkonsert',
            requestType: 'Gig Promo',
            rehearsalDayOfWeek: 'Friday',
            bandName: 'Alex Bästa',
            location: 'Ankdammsgatan 33, Solna',
            date: '2026-10-24T18:00:00',
            startTime: '18:00:00',
            endTime: '21:00:00',
            description: 'Promo för gig på Fasching Tis 26/10',
            isPaid: false,
            latitude: 59.3592,
            longitude: 17.9940,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep2.mp3',
              'audioSnippetTitle': 'Sommarkonsert Live Demo',
              'venue': 'Fasching',
              'eventType': 'gigPromo',
              'genre': 'Soul',
            },
          ),
          SubRequest(
            id: 'mock_3c',
            subRequestId: 'mock_3c',
            voicePart: 'Guitar',
            role: 'Looking for Guitar Sub',
            requestType: 'Paid Gigs',
            bandName: 'Stora Stygga',
            location: 'Agavägen 29, Lidingö',
            date: '2026-10-16T00:00:00',
            createdAt: DateTime.parse('2026-10-16T10:00:00').millisecondsSinceEpoch,
            startTime: '19:00:00',
            endTime: '22:00:00',
            description: 'Gig att Fasching ”Tribute to Stevie W.”',
            isPaid: true,
            payAmount: 2500,
            currency: 'SEK',
            latitude: 59.3620,
            longitude: 18.1520,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep1.mp3',
              'audioSnippetTitle': 'Stora Stygga Stevie W Tribute Demo',
              'venue': 'Fasching',
              'eventType': 'paid',
              'genre': 'Big Band Contemporary',
            },
          ),
          SubRequest(
            id: 'mock_4',
            subRequestId: 'mock_4',
            voicePart: 'Brass / Strings',
            role: 'Studio Overdubs for EP',
            requestType: 'Recorded Music',
            bandName: 'Monochrome Sound Lab',
            location: 'Södermalm, Stockholm',
            date: DateTime.now().add(const Duration(days: 7)).toIso8601String(),
            startTime: '11:00:00',
            endTime: '17:00:00',
            description: 'Seeking brass horn players for studio overdubs on upcoming indie rock EP.',
            isPaid: true,
            payAmount: 3000,
            currency: 'SEK',
            latitude: 59.3175,
            longitude: 18.0720,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep3.mp3',
              'audioSnippetTitle': 'Studio Rough Mix - Horns',
              'venue': 'Monochrome Studio',
              'eventType': 'recordedMusic',
              'genre': 'Indie / Alternative',
            },
          ),
          SubRequest(
            id: 'mock_5',
            subRequestId: 'mock_5',
            voicePart: 'Band Promo',
            role: 'Summer Festival Tour Promo',
            requestType: 'Gig Promo',
            bandName: 'Nordic Echoes',
            location: 'Gothenburg, Sweden',
            date: DateTime.now().add(const Duration(days: 9)).toIso8601String(),
            startTime: '20:00:00',
            endTime: '23:00:00',
            description: 'New single release and preview of upcoming summer headline tour across Scandinavia.',
            isPaid: false,
            latitude: 57.7089,
            longitude: 11.9746,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep1.mp3',
              'audioSnippetTitle': 'Summer Tour Single - Nordic Echoes',
              'venue': 'Nefertiti',
              'eventType': 'gigPromo',
              'genre': 'Electronic Dance Music (EDM)',
            },
          ),
          SubRequest(
            id: 'mock_6',
            subRequestId: 'mock_6',
            voicePart: 'Drums',
            role: 'New Member',
            requestType: 'New Member',
            bandName: 'Vibe Check',
            location: 'Malmö, Sweden',
            date: DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
            startTime: '17:30:00',
            endTime: '20:30:00',
            description: 'Audition / seeking permanent drummer for touring Scandinavian pop-rock band.',
            isPaid: true,
            payAmount: 1800,
            currency: 'SEK',
            latitude: 55.6050,
            longitude: 13.0038,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep1.mp3',
              'audioSnippetTitle': 'Audition Track: Nightglow (Tempo 128)',
              'venue': 'Kulturbolaget',
              'eventType': 'newMember',
              'genre': 'Pop',
            },
          ),
          SubRequest(
            id: 'mock_7',
            subRequestId: 'mock_7',
            voicePart: 'Cello',
            role: 'Substitute',
            requestType: 'Subs',
            rehearsalDayOfWeek: 'Wednesday',
            bandName: 'Uppsala Sinfonietta',
            location: 'Uppsala Konsert & Kongress',
            date: DateTime.now().subtract(const Duration(days: 4)).toIso8601String(),
            startTime: '18:00:00',
            endTime: '21:00:00',
            description: 'Substitute cellist required for our weekly orchestra rehearsal. Sheet music provided in advance.',
            isPaid: false,
            latitude: 59.8586,
            longitude: 17.6389,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep2.mp3',
              'audioSnippetTitle': 'Movement 3 Chamber Preview',
              'venue': 'Uppsala Konsert & Kongress',
              'eventType': 'subs',
              'genre': 'Classical',
            },
          ),
          SubRequest(
            id: 'mock_8',
            subRequestId: 'mock_8',
            voicePart: 'Lead Guitar',
            role: 'Paid Gigs',
            requestType: 'Paid',
            bandName: 'Arctic Lights Collective',
            location: 'Umeå Open, Umeå',
            date: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
            startTime: '19:30:00',
            endTime: '22:30:00',
            description: 'Paid sub guitarist needed for high-energy opening slot at Arctic Lights Festival.',
            isPaid: true,
            payAmount: 4000,
            currency: 'SEK',
            latitude: 63.8258,
            longitude: 20.2630,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep1.mp3',
              'audioSnippetTitle': 'Festival Opening Anthem',
              'venue': 'Umeå Folkets Hus',
              'eventType': 'paid',
              'genre': 'Rock',
            },
          ),
          SubRequest(
            id: 'mock_9',
            subRequestId: 'mock_9',
            voicePart: 'Bass',
            role: 'Studio Session Bassist',
            requestType: 'Recorded Music',
            bandName: 'SoundWave Studios',
            location: 'Linköping, Sweden',
            date: DateTime.now().add(const Duration(days: 7)).toIso8601String(),
            startTime: '10:00:00',
            endTime: '16:00:00',
            description: 'Studio recording session for an upcoming album. Pro level groove required.',
            isPaid: true,
            payAmount: 3500,
            currency: 'SEK',
            latitude: 58.4108,
            longitude: 15.6214,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep2.mp3',
              'audioSnippetTitle': 'Album Pre-production Bass Stem',
              'venue': 'SoundWave Studios',
              'eventType': 'recordedMusic',
              'genre': 'Indie / Alternative',
            },
          ),
          SubRequest(
            id: 'mock_10',
            subRequestId: 'mock_10',
            voicePart: 'Guitar & Bass',
            role: 'Funk & Soul Open Stage',
            requestType: 'Jam Session',
            bandName: 'Öresund Jam Society',
            location: 'Möllevången, Malmö',
            date: DateTime.now().add(const Duration(days: 3)).toIso8601String(),
            startTime: '20:00:00',
            endTime: '23:30:00',
            description: 'Weekly soul & funk jam session on Thursdays. Full backline available.',
            isPaid: false,
            latitude: 55.5910,
            longitude: 13.0070,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep2.mp3',
              'audioSnippetTitle': 'Möllevången Soul Session Excerpt',
              'venue': 'Möllevången Scen',
              'eventType': 'jamSession',
              'genre': 'Soul',
            },
          ),
          SubRequest(
            id: 'mock_11',
            subRequestId: 'mock_11',
            voicePart: 'Vocalist',
            role: 'Gig / Concert',
            requestType: 'Club Gig',
            bandName: 'Cool Autumn Quartet',
            location: 'Nefertiti, Gothenburg',
            date: DateTime.now().add(const Duration(days: 5)).toIso8601String(),
            startTime: '20:00:00',
            endTime: '23:00:00',
            description: 'Guest vocalist featured for standard jazz tunes at Nefertiti jazz club show.',
            isPaid: true,
            payAmount: 2200,
            currency: 'SEK',
            latitude: 57.6970,
            longitude: 11.9510,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep2.mp3',
              'audioSnippetTitle': 'Autumn in Gothenburg (Vocal Demo)',
              'venue': 'Nefertiti',
              'eventType': 'gigConcert',
              'genre': 'Jazz',
            },
          ),
          SubRequest(
            id: 'mock_12',
            subRequestId: 'mock_12',
            voicePart: 'Trombone',
            role: 'Substitute',
            requestType: 'Subs',
            bandName: 'West Coast Horn Band',
            location: 'Gothenburg, Sweden',
            date: DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
            startTime: '18:00:00',
            endTime: '21:00:00',
            description: 'Substitute trombone player needed for concert series.',
            isPaid: true,
            payAmount: 2500,
            currency: 'SEK',
            latitude: 57.7020,
            longitude: 11.9680,
            responses: {},
            extraFields: {
              'audioSnippetUrl': 'audio/bandrep2.mp3',
              'audioSnippetTitle': 'Brass Repertoire Snippet',
              'venue': 'Göteborgs Konserthus',
              'eventType': 'subs',
              'genre': 'Big Band',
            },
          ),
        ];
      } else {
        _allGigs = dbGigsWithCoords;
      }
    } catch (e) {
      debugPrint("Error fetching subrequests for map: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        final appState = Provider.of<AppState>(context, listen: false);
        _evaluateCrosshairTargeting(_getFilteredGigs(appState.currentUserProfile));
      }
    }
  }

  int _getFilterCount(String label, UserProfile? profile) {
    switch (label) {
      case 'All':
        return _allGigs.length +
            (FeatureFlags.enableMockLiveRehearsals ? mockLiveRehearsals.length : 0);
      case 'Music':
        return _allGigs.where((g) {
          final cat = MapEventTypeHelper.getCategory(MapEventTypeHelper.getEventType(g));
          return cat == MapCategory.music || cat == MapCategory.gigPromo;
        }).length +
            (FeatureFlags.enableMockLiveRehearsals ? mockLiveRehearsals.length : 0);
      case 'Gig Promo':
        return _allGigs.where((g) => MapEventTypeHelper.getEventType(g) == MapEventType.gigPromo).length;
      case 'Sub & Member Search':
        return _allGigs.where((g) => MapEventTypeHelper.getCategory(MapEventTypeHelper.getEventType(g)) == MapCategory.subAndMember).length;
      case 'This Week':
        final now = DateTime.now();
        final oneWeekLater = now.add(const Duration(days: 7));
        return _allGigs.where((gig) {
          if (gig.date == null) return false;
          final d = DateTime.tryParse(gig.date!);
          if (d == null) return false;
          return d.isAfter(now.subtract(const Duration(days: 1))) &&
              d.isBefore(oneWeekLater);
        }).length;

      // Sub-filters under Music
      case 'All Music':
        return _getFilterCount('Music', profile);
      case 'Live Gigs / Rehearsals':
        return _allGigs.where((g) {
          final t = MapEventTypeHelper.getEventType(g);
          return t == MapEventType.gigConcert || t == MapEventType.rehearsal;
        }).length +
            (FeatureFlags.enableMockLiveRehearsals ? mockLiveRehearsals.length : 0);
      case 'Gig / Concert':
      case 'Gigs':
        return _allGigs.where((g) => MapEventTypeHelper.getEventType(g) == MapEventType.gigConcert).length;
      case 'Rehearsal':
      case 'Rehearsals':
        return _allGigs.where((g) => MapEventTypeHelper.getEventType(g) == MapEventType.rehearsal).length +
            (FeatureFlags.enableMockLiveRehearsals ? mockLiveRehearsals.length : 0);
      case 'Jam Session':
      case 'Jam Sessions':
        return _allGigs.where((g) => MapEventTypeHelper.getEventType(g) == MapEventType.jamSession).length;
      case 'Recorded Music':
      case 'Demos / Recordings':
      case 'Studio':
        return _allGigs.where((g) => MapEventTypeHelper.getEventType(g) == MapEventType.recordedMusic).length;

      // Sub-filters under Sub & Member Search
      case 'All Sub/Member':
        return _getFilterCount('Sub & Member Search', profile);
      case 'New Member':
      case 'New Members':
        return _allGigs.where((g) => MapEventTypeHelper.getEventType(g) == MapEventType.newMember).length;
      case 'Subs':
      case 'Substitute':
      case 'Substitutes':
        return _allGigs.where((g) => MapEventTypeHelper.getEventType(g) == MapEventType.subs).length;
      case 'Paid':
      case 'Paid Gigs':
        return _allGigs.where((g) => MapEventTypeHelper.getEventType(g) == MapEventType.paid || g.isPaid).length;

      case 'With Audio':
        return _allGigs.where((g) => g.hasAudioSnippet).length +
            (FeatureFlags.enableMockLiveRehearsals ? mockLiveRehearsals.length : 0);

      case 'My Instruments':
        final userInstruments = profile?.instruments ?? [];
        if (userInstruments.isEmpty) return 0;
        return _allGigs.where((gig) {
          if (gig.voicePart == null) return false;
          final vpLower = gig.voicePart!.toLowerCase();
          return userInstruments.any((inst) {
            final instLower = inst.toLowerCase();
            return instLower == vpLower ||
                vpLower.contains(instLower) ||
                instLower.contains(vpLower);
          });
        }).length;

      default:
        return 0;
    }
  }

  void _evaluateCrosshairTargeting(List<SubRequest> filteredGigs) {
    final candidates = <MapTargetCandidate>[];

    for (final gig in filteredGigs) {
      if (gig.latitude != null && gig.longitude != null) {
        candidates.add(MapTargetCandidate.fromSubRequest(gig));
      }
    }

    final showRehearsals = FeatureFlags.enableMockLiveRehearsals &&
        (_selectedMainCategory == 'All' ||
            (_selectedMainCategory == 'Music' &&
                (_selectedSubCategory == null ||
                    _selectedSubCategory == 'All Music' ||
                    _selectedSubCategory == 'Rehearsal' ||
                    _selectedSubCategory == 'Live Gigs / Rehearsals')));

    if (showRehearsals) {
      for (final reh in mockLiveRehearsals) {
        candidates.add(MapTargetCandidate.fromRehearsal(reh));
      }
    }

    final bestTarget = MapCrosshairTargeting.findNearestTarget(
      cameraLat: _currentCameraPosition.target.latitude,
      cameraLng: _currentCameraPosition.target.longitude,
      zoom: _currentCameraPosition.zoom,
      candidates: candidates,
      hitRadiusPixels: 48.0,
    );

    if (bestTarget == null) {
      // Camera has moved away from target; clear any manual close restriction
      _manuallyClosedTargetId = null;
      if (_isAutoSelected && (_selectedGig != null || _selectedRehearsal != null)) {
        setState(() {
          _selectedGig = null;
          _selectedRehearsal = null;
          _isAutoSelected = false;
        });
      }
      return;
    }

    if (bestTarget.id == _manuallyClosedTargetId) {
      return;
    }

    // Acquired a new target, clear previous manual close block
    _manuallyClosedTargetId = null;

    final currentSelectedId = _selectedGig?.id ?? _selectedGig?.subRequestId ?? _selectedRehearsal?.id;

    if (bestTarget.id != currentSelectedId) {
      setState(() {
        if (bestTarget.kind == MapTargetKind.subRequest) {
          _selectedGig = bestTarget.subRequest;
          _selectedRehearsal = null;
        } else {
          _selectedRehearsal = bestTarget.rehearsal;
          _selectedGig = null;
        }
        _isAutoSelected = true;
        _manuallyClosedTargetId = null;
      });
    }
  }

  BitmapDescriptor _getMarkerColor(SubRequest gig) {
    final eventType = MapEventTypeHelper.getEventType(gig);
    return _getNoteDescriptor(eventType);
  }

  List<SubRequest> _getFilteredGigs(UserProfile? profile) {
    List<SubRequest> list = _allGigs;

    // 1. Primary Category Filter
    if (_selectedMainCategory == 'Music') {
      list = list.where((g) {
        final cat = MapEventTypeHelper.getCategory(MapEventTypeHelper.getEventType(g));
        return cat == MapCategory.music || cat == MapCategory.gigPromo;
      }).toList();
    } else if (_selectedMainCategory == 'Gig Promo') {
      list = list.where((g) {
        final cat = MapEventTypeHelper.getCategory(MapEventTypeHelper.getEventType(g));
        return cat == MapCategory.gigPromo;
      }).toList();
    } else if (_selectedMainCategory == 'Sub & Member Search') {
      list = list.where((g) {
        final cat = MapEventTypeHelper.getCategory(MapEventTypeHelper.getEventType(g));
        return cat == MapCategory.subAndMember;
      }).toList();
    } else if (_selectedMainCategory == 'This Week') {
      final now = DateTime.now();
      final oneWeekLater = now.add(const Duration(days: 7));
      list = list.where((gig) {
        if (gig.date == null) return false;
        final d = DateTime.tryParse(gig.date!);
        if (d == null) return false;
        return d.isAfter(now.subtract(const Duration(days: 1))) && d.isBefore(oneWeekLater);
      }).toList();
    }

    // 2. Secondary Sub-Filter
    if (_selectedSubCategory != null &&
        _selectedSubCategory != 'All Music' &&
        _selectedSubCategory != 'All Sub/Member' &&
        _selectedSubCategory != 'All Sub & Member') {
      list = list.where((g) {
        final type = MapEventTypeHelper.getEventType(g);
        if (_selectedSubCategory == 'Gig Promo') {
          return type == MapEventType.gigPromo;
        }
        if (_selectedSubCategory == 'Live Gigs / Rehearsals') {
          return type == MapEventType.gigConcert || type == MapEventType.rehearsal;
        }
        if (_selectedSubCategory == 'Jam Sessions' || _selectedSubCategory == 'Jam Session') {
          return type == MapEventType.jamSession;
        }
        if (_selectedSubCategory == 'Demos / Recordings' || _selectedSubCategory == 'Recorded Music') {
          return type == MapEventType.recordedMusic;
        }
        if (_selectedSubCategory == 'Substitutes' || _selectedSubCategory == 'Substitute' || _selectedSubCategory == 'Subs') {
          return type == MapEventType.subs;
        }
        if (_selectedSubCategory == 'New Members' || _selectedSubCategory == 'New Member') {
          return type == MapEventType.newMember;
        }
        if (_selectedSubCategory == 'Paid Gigs' || _selectedSubCategory == 'Paid') {
          return type == MapEventType.paid || g.isPaid;
        }

        final shortLabel = MapEventTypeHelper.getShortLabel(type);
        final fullLabel = MapEventTypeHelper.getLabel(type);
        return shortLabel == _selectedSubCategory ||
            fullLabel == _selectedSubCategory ||
            type.name == _selectedSubCategory;
      }).toList();
    }

    // 3. Instrument Search Query Filter (strictly under Sub & Member Search)
    if (_selectedMainCategory == 'Sub & Member Search' && _instrumentQuery.trim().isNotEmpty) {
      final q = _instrumentQuery.trim().toLowerCase();
      list = list.where((gig) {
        final vp = (gig.voicePart ?? '').toLowerCase();
        final r = (gig.role ?? '').toLowerCase();
        final d = (gig.description ?? '').toLowerCase();
        return vp.contains(q) || r.contains(q) || d.contains(q);
      }).toList();
    }

    return list;
  }

  Set<Marker> _buildMarkers(List<SubRequest> filteredGigs) {
    final gigMarkers = filteredGigs.map((gig) {
      final eventType = MapEventTypeHelper.getEventType(gig);
      final standardizedType = MapEventTypeHelper.getShortLabel(eventType);
      final genre = gig.extraFields['genre']?.toString() ??
          gig.extraFields['Genre']?.toString() ??
          gig.style ??
          '';
      final title = genre.isNotEmpty
          ? '${gig.bandName ?? "Band"} - $genre'
          : (gig.bandName ?? 'Band');
      return Marker(
        markerId: MarkerId(gig.id ?? gig.subRequestId ?? UniqueKey().toString()),
        position: LatLng(gig.latitude!, gig.longitude!),
        icon: _getMarkerColor(gig),
        anchor: const Offset(0.353, 0.717),
        infoWindow: InfoWindow(
          title: title,
          snippet: '$standardizedType · ${gig.location ?? ""}',
        ),
        onTap: () {
          setState(() {
            _selectedGig = gig;
            _selectedRehearsal = null;
            _isAutoSelected = false;
            _manuallyClosedTargetId = null;
          });
        },
      );
    }).toSet();

    final showRehearsals = FeatureFlags.enableMockLiveRehearsals &&
        (_selectedMainCategory == 'All' ||
            (_selectedMainCategory == 'Music' &&
                (_selectedSubCategory == null ||
                    _selectedSubCategory == 'All Music' ||
                    _selectedSubCategory == 'Rehearsal' ||
                    _selectedSubCategory == 'Live Gigs / Rehearsals')));

    final Set<Marker> realLiveMarkers = {};
    if (FeatureFlags.enableRealLiveBroadcasts && _activeRealBroadcasts.isNotEmpty) {
      for (final broadcast in _activeRealBroadcasts) {
        realLiveMarkers.add(
          Marker(
            markerId: MarkerId('real_live_${broadcast.id}'),
            position: LatLng(broadcast.latitude, broadcast.longitude),
            icon: _getNoteDescriptor(MapEventType.gigConcert),
            anchor: const Offset(0.353, 0.717),
            infoWindow: InfoWindow(
              title: '🔴 LIVE: ${broadcast.bandName}',
              snippet: '${broadcast.title} · ${broadcast.listenerCount} listeners',
            ),
            onTap: () {
              _showLiveBroadcastDetails(broadcast);
            },
          ),
        );
      }
    }

    if (!showRehearsals) {
      return {...gigMarkers, ...realLiveMarkers};
    }

    final rehearsalMarkers = mockLiveRehearsals.map((rehearsal) {
      return Marker(
        markerId: MarkerId(rehearsal.id),
        position: rehearsal.position,
        icon: _getNoteDescriptor(MapEventType.rehearsal),
        anchor: const Offset(0.353, 0.717),
        infoWindow: InfoWindow(
          title: rehearsal.genre.isNotEmpty ? '${rehearsal.bandName} - ${rehearsal.genre}' : rehearsal.bandName,
          snippet: 'Rehearsal · ${rehearsal.city}',
        ),
        onTap: () {
          setState(() {
            _selectedRehearsal = rehearsal;
            _selectedGig = null;
            _isAutoSelected = false;
            _manuallyClosedTargetId = null;
          });
        },
      );
    }).toSet();

    return {...gigMarkers, ...rehearsalMarkers, ...realLiveMarkers};
  }

  void _showMapInfoDialog() {
    showWhatIsMapViewDialog(context);
  }

  void _openStartLiveBroadcastDialog() {
    if (_currentPublishingBroadcast != null) {
      _confirmStopBroadcast(_currentPublishingBroadcast!.id);
      return;
    }
    StartLiveBroadcastDialog.show(
      context,
      onStartBroadcast: ({
        required String bandId,
        required String bandName,
        required String title,
        String? genre,
        String? description,
      }) async {
        final location = _currentCameraPosition.target;
        if (_liveBroadcastService == null || _liveKitAudioController == null) {
          throw Exception('Live broadcast service is not initialized.');
        }

        final session = await _liveBroadcastService!.startLiveBroadcast(
          bandId: bandId,
          title: title,
          location: location,
          genre: genre,
          description: description,
        );

        await _liveKitAudioController!.connectPublisher(session);

        if (mounted) {
          setState(() {
            _currentPublishingBroadcast = LiveBroadcast(
              id: session.broadcastId,
              bandId: bandId,
              bandName: bandName,
              creatorUserId: Provider.of<AppState>(context, listen: false).currentUserId ?? '',
              title: title,
              genre: genre,
              description: description,
              latitude: location.latitude,
              longitude: location.longitude,
              status: LiveBroadcastStatus.active,
              startedAt: DateTime.now(),
              livekitRoomName: session.roomName,
              listenerCount: 0,
            );
          });
        }
      },
    );
  }

  Future<void> _stopPublishingBroadcast([String? broadcastId]) async {
    final bId = broadcastId ?? _currentPublishingBroadcast?.id;
    if (bId == null) return;
    try {
      await _liveBroadcastService?.stopLiveBroadcast(broadcastId: bId);
    } catch (e) {
      debugPrint('[GigMapPage] Error stopping live broadcast: $e');
    }
    await _liveKitAudioController?.disconnect();
    if (mounted) {
      setState(() {
        _currentPublishingBroadcast = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live broadcast ended.')),
      );
    }
  }

  Future<void> _confirmStopBroadcast([String? broadcastId]) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: Text(
          'End Live Broadcast?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to stop this live broadcast? All active listeners will be disconnected.',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('End Broadcast', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _stopPublishingBroadcast(broadcastId);
    }
  }

  void _showBroadcasterManageSheet(LiveBroadcast broadcast) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppTheme.dangerRed, width: 2),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.dangerRed,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.circle, color: Colors.white, size: 8),
                            const SizedBox(width: 4),
                            Text(
                              'YOUR LIVE STREAM',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    broadcast.title,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    broadcast.bandName,
                    style: GoogleFonts.inter(fontSize: 14, color: AppTheme.primaryAccent, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.headset_rounded, size: 16, color: Colors.white54),
                      const SizedBox(width: 6),
                      Text(
                        '${broadcast.listenerCount} listeners right now',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _confirmStopBroadcast(broadcast.id);
                      },
                      icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
                      label: Text(
                        'End Live Stream',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.dangerRed,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLiveBroadcastDetails(LiveBroadcast broadcast) {
    if (_liveBroadcastService == null || _liveKitAudioController == null) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final isMyBroadcast = appState.currentUserId != null &&
        (broadcast.creatorUserId == appState.currentUserId ||
            _currentPublishingBroadcast?.id == broadcast.id);

    if (isMyBroadcast) {
      _showBroadcasterManageSheet(broadcast);
      return;
    }

    final isListening = _currentlyListeningBroadcast?.id == broadcast.id;

    LiveListenerSheet.show(
      context,
      broadcast: broadcast,
      audioController: _liveKitAudioController!,
      isCurrentlyListening: isListening,
      onStartListening: () async {
        try {
          final session = await _liveBroadcastService!.joinLiveBroadcast(
            broadcastId: broadcast.id,
          );
          await _liveKitAudioController!.connectListener(session);
          if (mounted) {
            setState(() {
              _currentlyListeningBroadcast = broadcast;
            });
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not join live stream: $e')),
            );
          }
        }
      },
      onStopListening: () async {
        await _liveKitAudioController?.disconnect();
        if (mounted) {
          setState(() {
            _currentlyListeningBroadcast = null;
          });
        }
      },
    );
  }

  void _showUploadEventSheet() {
    String selectedCategory = 'Music';
    String selectedType = 'Gig / Concert';
    List<String> selectedGenres = ['Big Band Contemporary'];
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay selectedStartTime = const TimeOfDay(hour: 18, minute: 0);
    TimeOfDay selectedEndTime = const TimeOfDay(hour: 21, minute: 0);
    final bandNameController = TextEditingController();
    final roleController = TextEditingController();
    final venueController = TextEditingController();
    final locationController = TextEditingController(text: 'Stockholm, Sweden');
    final descriptionController = TextEditingController();
    final audioTrackController = TextEditingController();
    final infoAudioTrackController = TextEditingController();
    PlatformFile? pickedAudioFile;
    bool isPublishing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0C20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF2E2A4E)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final typesForCategory = selectedCategory == 'Music'
              ? ['Gig / Concert', 'Rehearsal', 'Jam Session', 'Recorded Music']
              : selectedCategory == 'Gig Promo'
                  ? ['Gig Promo']
                  : ['Substitute', 'New Member', 'Paid Gigs'];

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.add_location_alt_rounded, color: AppTheme.primaryAccent, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Upload Map View Pin / Audio',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white60),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Post a pin to Map View and attach an audio track for other musicians and audiences to discover.',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  
                  // Category Selector
                  Text('Category', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  Row(
                    children: ['Music', 'Gig Promo', 'Sub & Member Search'].map((cat) {
                      final isSelected = selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            cat,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.white70,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryAccent,
                          backgroundColor: const Color(0xFF1E1A38),
                          onSelected: (val) {
                            if (val) {
                              setSheetState(() {
                                selectedCategory = cat;
                                if (cat == 'Music') selectedType = 'Gig / Concert';
                                if (cat == 'Gig Promo') selectedType = 'Gig Promo';
                                if (cat == 'Sub & Member Search') selectedType = 'Substitute';
                              });
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Type Selector
                  Text('Type', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: typesForCategory.map((type) {
                      final isSelected = selectedType == type;
                      return ChoiceChip(
                        label: Text(type, style: GoogleFonts.inter(fontSize: 11, color: isSelected ? Colors.white : Colors.white70)),
                        selected: isSelected,
                        selectedColor: const Color(0xFF6366F1),
                        backgroundColor: const Color(0xFF1E1A38),
                        onSelected: (val) {
                          if (val) setSheetState(() => selectedType = type);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Band Name
                  TextField(
                    controller: bandNameController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Band Name / Artist',
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Genre / Band Type (Strictly from GenresTaxonomy)
                  Text('Genre / Band Type', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final result = await SearchableCategoryMultiSelectSheet.show(
                        context: context,
                        title: 'Select Genre / Band Type',
                        categoryMap: GenresTaxonomy.categoryMap,
                        initialSelected: selectedGenres,
                      );
                      if (result != null && result.isNotEmpty) {
                        setSheetState(() {
                          selectedGenres = result;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1633),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E2A4E)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.music_note_rounded, color: AppTheme.primaryAccent, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedGenres.isNotEmpty ? selectedGenres.join(', ') : 'Select Genre / Band Type (from list)',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: selectedGenres.isNotEmpty ? Colors.white : Colors.white54,
                                fontWeight: selectedGenres.isNotEmpty ? FontWeight.w500 : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Venue / Spelställe
                  TextField(
                    controller: venueController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Venue / Spelställe (e.g. Fasching, Stampen)',
                      hintText: 'e.g. Fasching, Stampen, Nefertiti',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Role / Title
                  TextField(
                    controller: roleController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Event Title / Role (e.g. Lead Guitarist Needed)',
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Location
                  TextField(
                    controller: locationController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Pin Location (Street, City without postal code)',
                      hintText: 'e.g. Ankdammsgatan 33, Solna or Kungsgatan 44, Stockholm',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Date & Time
                  Text('Date & Time', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  
                  // Date Picker
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setSheetState(() => selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1633),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E2A4E)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.primaryAccent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              DateFormat('EEEE, MMM d, yyyy').format(selectedDate),
                              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Separate Time Pickers: Start Time (Från) and End Time (Till)
                  Row(
                    children: [
                      // Start Time (Från)
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final startPicked = await showTimePicker(
                              context: context,
                              initialTime: selectedStartTime,
                            );
                            if (startPicked != null) {
                              setSheetState(() => selectedStartTime = startPicked);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1633),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF2E2A4E)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time_rounded, size: 15, color: AppTheme.primaryAccent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Start (Från tid)',
                                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white54),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedStartTime.format(context),
                                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // End Time (Till)
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final endPicked = await showTimePicker(
                              context: context,
                              initialTime: selectedEndTime,
                            );
                            if (endPicked != null) {
                              setSheetState(() => selectedEndTime = endPicked);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1633),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF2E2A4E)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.update_rounded, size: 15, color: Color(0xFF60A5FA)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'End (Till tid)',
                                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white54),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedEndTime.format(context),
                                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Description
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Description / Details',
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Audio Track (Fritext)
                  Text('Audio Track', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: audioTrackController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Audio Track',
                      hintText: 'Track name or audio URL (e.g. Sommarkonsert Demo)',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Info Audio Track (Fritext)
                  TextField(
                    controller: infoAudioTrackController,
                    maxLines: 2,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Info Audio Track',
                      hintText: 'e.g. Recorded live at Fasching with rough horn mix',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Upload Track Button (File Picker)
                  InkWell(
                    onTap: () async {
                      try {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
                          withData: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          final file = result.files.first;
                          setSheetState(() {
                            pickedAudioFile = file;
                            if (audioTrackController.text.trim().isEmpty) {
                              audioTrackController.text = file.name;
                            }
                          });
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('File picker notice: $e')),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1A38),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: pickedAudioFile != null ? AppTheme.success : const Color(0xFF2E2A4E),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            pickedAudioFile != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                            color: pickedAudioFile != null ? AppTheme.success : AppTheme.primaryAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pickedAudioFile != null ? 'Selected: ${pickedAudioFile!.name}' : 'Upload Track (Choose Audio File)',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: pickedAudioFile != null ? Colors.white : Colors.white70,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  pickedAudioFile != null
                                      ? '${(pickedAudioFile!.size / 1024).toStringAsFixed(1)} KB · Ready to attach'
                                      : 'Tap to choose .mp3, .m4a or .wav from device',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (pickedAudioFile != null)
                            GestureDetector(
                              onTap: () {
                                setSheetState(() {
                                  pickedAudioFile = null;
                                });
                              },
                              child: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Publish Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: isPublishing
                          ? null
                          : () async {
                              setSheetState(() => isPublishing = true);
                              final band = bandNameController.text.trim().isEmpty ? 'My Band' : bandNameController.text.trim();
                              final title = roleController.text.trim().isEmpty ? selectedType : roleController.text.trim();
                              final venueText = venueController.text.trim();
                              final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                              final addressText = locationController.text.trim().isEmpty ? 'Stockholm, Sweden' : locationController.text.trim();

                              // Geocode entered address to get real geographic coordinates (without postal code)
                              final targetLatLng = await _geocodeAddress(addressText, _currentCameraPosition.target);

                              String mappedType = 'gigConcert';
                              if (selectedType == 'Rehearsal') mappedType = 'rehearsal';
                              if (selectedType == 'Jam Session') mappedType = 'jamSession';
                              if (selectedType == 'Recorded Music') mappedType = 'recordedMusic';
                              if (selectedType == 'Gig Promo') mappedType = 'gigPromo';
                              if (selectedType == 'New Member') mappedType = 'newMember';
                              if (selectedType == 'Substitute') mappedType = 'subs';
                              if (selectedType == 'Paid Gigs') mappedType = 'paid';

                              final audioText = audioTrackController.text.trim();
                              final audioInfo = infoAudioTrackController.text.trim();

                              String? audioUrl;
                              if (pickedAudioFile != null) {
                                try {
                                  final appState = Provider.of<AppState>(context, listen: false);
                                  final userId = appState.currentUserId ?? 'map_user';
                                  audioUrl = await appState.firebaseService.uploadAudioSnippetAsync(
                                    userId,
                                    pickedAudioFile!.bytes,
                                    pickedAudioFile!.path,
                                  );
                                } catch (e) {
                                  debugPrint('[UploadPin] Storage upload fallback: $e');
                                  audioUrl = pickedAudioFile!.path ?? 'audio/bandrep1.mp3';
                                }
                              } else if (audioText.isNotEmpty) {
                                audioUrl = audioText;
                              }

                              final newGig = SubRequest(
                                id: newId,
                                subRequestId: newId,
                                bandName: band,
                                role: title,
                                voicePart: title,
                                requestType: selectedType,
                                location: addressText,
                                date: selectedDate.toIso8601String(),
                                startTime: '${selectedStartTime.hour.toString().padLeft(2, '0')}:${selectedStartTime.minute.toString().padLeft(2, '0')}:00',
                                endTime: '${selectedEndTime.hour.toString().padLeft(2, '0')}:${selectedEndTime.minute.toString().padLeft(2, '0')}:00',
                                description: descriptionController.text.trim().isEmpty ? 'Uploaded via Map View.' : descriptionController.text.trim(),
                                latitude: targetLatLng.latitude,
                                longitude: targetLatLng.longitude,
                                isPaid: selectedType == 'Paid Gigs',
                                payAmount: 2000,
                                responses: {},
                                extraFields: {
                                  if (audioUrl != null && audioUrl.isNotEmpty) ...{
                                    'audioSnippetUrl': audioUrl,
                                    'audioSnippetTitle': audioText.isNotEmpty ? audioText : '$band Audio Track',
                                    if (audioInfo.isNotEmpty) 'infoAudioTrack': audioInfo,
                                  },
                                  if (venueText.isNotEmpty) 'venue': venueText,
                                  'eventType': mappedType,
                                  'genre': selectedGenres.isNotEmpty ? selectedGenres.first : 'Big Band Contemporary',
                                  'subCategory': selectedCategory,
                                },
                              );

                              setState(() {
                                _allGigs.insert(0, newGig);
                                _selectedGig = newGig;
                                _selectedRehearsal = null;
                              });

                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(targetLatLng, 14.5),
                              );

                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Pin published at $addressText!'),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isPublishing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Publish Map View Pin / Audio',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final filteredGigs = _getFilteredGigs(appState.currentUserProfile);
    final markers = _buildMarkers(filteredGigs);

    return Scaffold(
      appBar: const CustomTopBar(showBack: true),
      body: SafeArea(
        top: false,
        child: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Stack(
          children: [
            // Map
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(59.3293, 18.0686),
                      zoom: 5.5,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _mapController?.setMapStyle(_isWhiteMap ? _whiteMapStyle : _darkMapStyle);
                      if (FeatureFlags.enableMockLiveRehearsals) {
                        _audioController?.updateCameraTarget(const LatLng(59.3293, 18.0686), immediate: true);
                      }
                    },
                    onCameraMove: (position) {
                      _currentCameraPosition = position;
                      if (FeatureFlags.enableMockLiveRehearsals) {
                        _audioController?.updateCameraTarget(position.target);
                      }
                    },
                    onCameraIdle: () {
                      if (FeatureFlags.enableMockLiveRehearsals && _mapController != null) {
                        _mapController?.getVisibleRegion();
                      }
                      _evaluateCrosshairTargeting(filteredGigs);
                    },
                    markers: markers,
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    onTap: (_) {
                      // Deselect gig and rehearsal on tapping map empty space
                      final closedId = _selectedGig?.id ?? _selectedGig?.subRequestId ?? _selectedRehearsal?.id;
                      setState(() {
                        _selectedGig = null;
                        _selectedRehearsal = null;
                        _isAutoSelected = false;
                        _manuallyClosedTargetId = closedId;
                      });
                    },
                  ),

            // Center Map Crosshair Overlay
            Center(
              child: MapCrosshair(
                isTargetAcquired: _selectedGig != null || _selectedRehearsal != null,
              ),
            ),

            // Top Structured Controls (Broadcaster Bar, Filters, Sub-filters, City Jumpers, "What is Map View?" Box)
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Broadcaster sticky bar (when local user is broadcasting live)
                  if (_currentPublishingBroadcast != null && _liveKitAudioController != null)
                    LiveBroadcasterBar(
                      broadcast: _currentPublishingBroadcast!,
                      audioController: _liveKitAudioController!,
                      onStopBroadcast: _stopPublishingBroadcast,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    ),

                  // Row 1 (TOP): Clickable "What is Map View?" Box
                  if (_showGuideBanner) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _buildWhatIsMapViewBanner(),
                    ),
                  ],

                  // Row 2: Actions Header (Map Style Toggle on left, Refresh and Guide on right)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Map Style Toggle Pill (White vs Default Dark)
                        _buildMapThemeToggle(),

                        // Action Buttons: Refresh & Guide Toggle
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F0C20).withOpacity(0.92),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                                tooltip: 'Refresh Map',
                                onPressed: _fetchGigs,
                              ),
                            ),
                            if (!_showGuideBanner) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _showGuideBanner = true),
                                child: Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F0C20).withOpacity(0.92),
                                    borderRadius: BorderRadius.circular(17),
                                    border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.5), width: 1.2),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.help_outline_rounded, color: AppTheme.primaryAccent, size: 14),
                                      const SizedBox(width: 5),
                                      Text(
                                        'What is Map View?',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Row 3: Full-width Primary Category Filter Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildMainFilterChip('Music', _getFilterCount('Music', appState.currentUserProfile), displayLabel: 'MUSIC'),
                        _buildMainFilterChip('Sub & Member Search', _getFilterCount('Sub & Member Search', appState.currentUserProfile), displayLabel: 'SUB & MEMBER SEARCH'),
                        _buildMainFilterChip('This Week', _getFilterCount('This Week', appState.currentUserProfile), displayLabel: 'THIS WEEK'),
                      ],
                    ),
                  ),

                  // Row 4: Sub-filter Row (conditional when Music or Sub & Member Search is active)
                  if (_selectedMainCategory == 'Music') ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildSubFilterChip('Gig Promo', MapEventType.gigPromo),
                          _buildSubFilterChip('Live Gigs / Rehearsals', MapEventType.gigConcert),
                          _buildSubFilterChip('Jam Sessions', MapEventType.jamSession),
                          _buildSubFilterChip('Demos / Recordings', MapEventType.recordedMusic),
                        ],
                      ),
                    ),
                  ] else if (_selectedMainCategory == 'Sub & Member Search') ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildSubFilterChip('Substitutes', MapEventType.subs),
                          _buildSubFilterChip('New Members', MapEventType.newMember),
                          _buildSubFilterChip('Paid Gigs', MapEventType.paid),
                          const SizedBox(width: 8),
                          _buildInstrumentFilterToggle(),
                        ],
                      ),
                    ),
                    if (_showInstrumentSearch || _instrumentQuery.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildInstrumentSearchBar(),
                    ],
                  ],
                ],
              ),
            ),

            // Bottom drawer details card for Gigs
            if (_selectedGig != null)
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: _buildBottomCardContent(_selectedGig!, appState),
              ),

            // Bottom drawer details card for Mock Live Rehearsals (with Live Audio bar docked directly above it)
            if (_selectedRehearsal != null)
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLiveAudioBar(isDocked: true),
                    const SizedBox(height: 8),
                    _buildRehearsalBottomCardContent(_selectedRehearsal!),
                  ],
                ),
              ),

            // When no event card is selected: Action buttons at bottom-left
            if (_selectedGig == null && _selectedRehearsal == null) ...[
              Positioned(
                bottom: 16,
                left: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _showUploadEventSheet,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(19),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryAccent.withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Upload Map View Pin / Audio',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (FeatureFlags.enableRealLiveBroadcasts && _currentPublishingBroadcast == null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openStartLiveBroadcastDialog,
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerRed,
                            borderRadius: BorderRadius.circular(19),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.dangerRed.withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.podcasts_rounded, color: Colors.white, size: 15),
                              const SizedBox(width: 5),
                              Text(
                                'Go Live',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildWhatIsMapViewBanner() {
    return Semantics(
      button: true,
      label: 'What is Map View? Click to read full guide.',
      child: AnimatedTapDetector(
        onTap: _showMapInfoDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C20).withOpacity(0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primaryAccent.withOpacity(0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: AppTheme.primaryAccent.withOpacity(0.08),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: AppTheme.primaryAccent,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'What is Map View: ',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(
                        text:
                            'Move pins towards the centre of the screen (telescopic sight) to hear different bands and their recordings, band info, gig promo, etc',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFFD4CEEB),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.primaryAccent,
                size: 11,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Dismiss',
                onPressed: () {
                  setState(() {
                    _showGuideBanner = false;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveAudioBar({bool isDocked = false}) {
    if (!FeatureFlags.enableMockLiveRehearsals || _audioController == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0C20).withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.purpleAccent.withOpacity(0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ValueListenableBuilder<bool>(
          valueListenable: _audioController!.isAudioStoppedNotifier,
          builder: (context, isStopped, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _audioController!.isMutedNotifier,
              builder: (context, isMuted, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isStopped
                            ? AppTheme.danger.withOpacity(0.2)
                            : isMuted
                                ? AppTheme.warning.withOpacity(0.2)
                                : Colors.purpleAccent.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isStopped
                            ? Icons.power_settings_new_rounded
                            : isMuted
                                ? Icons.volume_off_rounded
                                : Icons.sensors_rounded,
                        color: isStopped
                            ? AppTheme.danger
                            : isMuted
                                ? AppTheme.warning
                                : Colors.purpleAccent,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'LIVE AUDIO',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          isStopped
                              ? 'Turned OFF'
                              : isMuted
                                  ? 'Muted'
                                  : 'Active (Proximity)',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: isStopped
                                ? AppTheme.danger
                                : isMuted
                                    ? AppTheme.warning
                                    : Colors.purpleAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Power Switch (Turn OFF / Turn ON)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _audioController?.toggleAudioPower();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isStopped
                              ? AppTheme.success.withOpacity(0.2)
                              : AppTheme.danger.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isStopped
                                ? AppTheme.success.withOpacity(0.6)
                                : AppTheme.danger.withOpacity(0.6),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isStopped ? Icons.play_arrow_rounded : Icons.power_settings_new_rounded,
                              size: 13,
                              color: isStopped ? AppTheme.success : AppTheme.danger,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isStopped ? 'Turn ON' : 'Turn OFF',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isStopped ? AppTheme.success : AppTheme.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Mute Button (disabled if turned off)
                    if (!isStopped)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _audioController?.toggleMute();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isMuted
                                ? AppTheme.primaryAccent.withOpacity(0.2)
                                : const Color(0xFF2E2A4E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isMuted
                                  ? AppTheme.primaryAccent.withOpacity(0.6)
                                  : const Color(0xFF433D72),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                size: 13,
                                color: isMuted ? AppTheme.primaryAccent : Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isMuted ? 'Unmute' : 'Mute',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isMuted ? AppTheme.primaryAccent : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomCardContent(SubRequest gig, AppState appState) {
    final eventType = MapEventTypeHelper.getEventType(gig);
    final badgeColor = MapEventTypeHelper.getColor(eventType);
    final badgeLabel = MapEventTypeHelper.getShortLabel(eventType);
    final badgeIcon = MapEventTypeHelper.getIcon(eventType);
    final genre = gig.extraFields['genre']?.toString() ??
        gig.extraFields['Genre']?.toString() ??
        gig.style ??
        '';
    final venue = gig.venue ?? gig.extraFields['venue']?.toString() ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground.withOpacity(0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: badgeColor.withOpacity(0.55), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Band name (clickable -> Band Profile "About") + Genre / Band Type (Line 1) & Close button
          // e.g. "Mats Holmquist Stora Stygga - Big Band Contemporary"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    _openBandProfile(
                      context: context,
                      bandName: gig.bandName ?? "Unknown Band",
                      genre: genre,
                      aboutText: gig.description,
                      location: gig.location,
                      audioUrl: gig.audioSnippetUrl,
                      audioTitle: gig.audioSnippetTitle,
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: gig.bandName ?? "Unknown Band",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white38,
                            height: 1.25,
                          ),
                        ),
                        if (genre.isNotEmpty) ...[
                          TextSpan(
                            text: ' - ',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white54,
                            ),
                          ),
                          TextSpan(
                            text: genre,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF60A5FA), // Mindre, blåfärgad font
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final closedId = _selectedGig?.id ?? _selectedGig?.subRequestId;
                  setState(() {
                    _selectedGig = null;
                    _isAutoSelected = false;
                    _manuallyClosedTargetId = closedId;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 2. Standardized Event Category (Line 2: e.g. "Gig / Concert", "Substitute", "Rehearsal")
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: badgeColor.withOpacity(0.6), width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, color: badgeColor, size: 13),
                const SizedBox(width: 5),
                Text(
                  badgeLabel,
                  style: GoogleFonts.inter(
                    color: badgeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Venue (Line 3: e.g. "Fasching", "Stampen", "Nefertiti")
          if (venue.trim().isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.nightlife_rounded, size: 14, color: AppTheme.primaryAccent),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    venue,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],

          // 4. Location (Line 4: e.g. "Kungsgatan 44, Stockholm")
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  gig.location ?? 'Sweden',
                  style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 5. Date & Time (Line 5: either gig/rehearsal time or "Posted Nov 12")
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 13, color: AppTheme.textSecondary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _formatEventDateTime(gig, eventType),
                  style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // 6. Fritext-ruta / Description (Line 6: e.g. "Äntligen är de tillbaka...")
          if (gig.description != null && gig.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              gig.description!,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.white.withOpacity(0.85),
                height: 1.35,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // 7. Inline Audio Track player (Auto-plays when pin enters crosshairs)
          if (gig.hasAudioSnippet) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF131028),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: badgeColor.withOpacity(0.35), width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.graphic_eq_rounded, color: badgeColor, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          gig.audioSnippetTitle ?? 'Audio Track',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'AUDIO TRACK',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (gig.extraFields['infoAudioTrack'] != null &&
                      gig.extraFields['infoAudioTrack'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      gig.extraFields['infoAudioTrack'].toString().trim(),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  AudioSnippetPlayer(audioUrl: gig.audioSnippetUrl!, autoPlay: true),
                ],
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildRehearsalBottomCardContent(MockLiveRehearsal rehearsal) {
    final dist = _audioController?.distancesKm[rehearsal.id];
    final distStr = dist != null && dist.isFinite ? '${dist.toStringAsFixed(0)} km away' : '';
    final badgeColor = MapEventTypeHelper.getColor(MapEventType.rehearsal);
    final badgeLabel = MapEventTypeHelper.getShortLabel(MapEventType.rehearsal);
    final badgeIcon = MapEventTypeHelper.getIcon(MapEventType.rehearsal);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground.withOpacity(0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: badgeColor.withOpacity(0.55), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Band name + Genre / Band Type (Line 1) & Close button
            // e.g. "Northern Echo - Alternative / Post-Rock"
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                  onTap: () {
                    _openBandProfile(
                      context: context,
                      bandName: rehearsal.bandName,
                      genre: rehearsal.genre,
                      aboutText: rehearsal.description,
                      location: rehearsal.location ?? rehearsal.city,
                      audioUrl: rehearsal.audioAssetPath,
                      audioTitle: '${rehearsal.bandName} Live Rehearsal Track',
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: rehearsal.bandName,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white38,
                            height: 1.25,
                          ),
                        ),
                        if (rehearsal.genre.isNotEmpty) ...[
                          TextSpan(
                            text: ' - ',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white54,
                            ),
                          ),
                          TextSpan(
                            text: rehearsal.genre,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF60A5FA), // Mindre, blåfärgad font
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final closedId = _selectedRehearsal?.id;
                    setState(() {
                      _selectedRehearsal = null;
                      _isAutoSelected = false;
                      _manuallyClosedTargetId = closedId;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 2. Standardized Event Category (Line 2: "Rehearsal")
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeColor.withOpacity(0.6), width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badgeIcon, color: badgeColor, size: 13),
                  const SizedBox(width: 5),
                  Text(
                    badgeLabel,
                    style: GoogleFonts.inter(
                      color: badgeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 3. Venue (Line 3: e.g. "Umeå Musikstudio", "Musikens Hus")
            if ((rehearsal.venue ?? '').trim().isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.nightlife_rounded, size: 14, color: AppTheme.primaryAccent),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      rehearsal.venue!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],

            // 4. Location (Line 4: e.g. "Umeå Musikstudio, Västerslätt, Umeå")
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    rehearsal.location ?? '${rehearsal.city}${distStr.isNotEmpty ? " · $distStr" : ""}',
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 5. Date & Time (Line 5: e.g. "Wednesday, Oct 22, 2026 - 7.00 PM 10.00 PM")
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    rehearsal.dateTime ?? 'Wednesday, Oct 22, 2026 - 7.00 PM 10.00 PM',
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // 6. Fritext-ruta / Description
            if (rehearsal.description != null && rehearsal.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rehearsal.description!,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: Colors.white.withOpacity(0.85),
                  height: 1.35,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMapThemeToggle() {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0C20).withOpacity(0.92),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // White Map Button
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleMapTheme(true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isWhiteMap ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: _isWhiteMap
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wb_sunny_rounded,
                    size: 13,
                    color: _isWhiteMap ? const Color(0xFF0F0C20) : Colors.white60,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'White',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _isWhiteMap ? const Color(0xFF0F0C20) : Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Default Map Button
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleMapTheme(false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: !_isWhiteMap ? AppTheme.primaryAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: !_isWhiteMap
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryAccent.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.nightlight_round,
                    size: 13,
                    color: !_isWhiteMap ? Colors.white : Colors.white60,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Default',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: !_isWhiteMap ? Colors.white : Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainFilterChip(String label, int count, {String? displayLabel}) {
    final isSelected = _selectedMainCategory == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedMainCategory = label;
            _selectedSubCategory = null;
            if (label != 'Sub & Member Search') {
              _instrumentQuery = '';
              _instrumentSearchController.clear();
              _showInstrumentSearch = false;
            }
            _selectedGig = null;
            _selectedRehearsal = null;
            _isAutoSelected = false;
            _manuallyClosedTargetId = null;
          });
          final appState = Provider.of<AppState>(context, listen: false);
          _evaluateCrosshairTargeting(_getFilteredGigs(appState.currentUserProfile));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryAccent.withOpacity(0.9)
                : AppTheme.cardBackground.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayLabel ?? label,
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.25)
                        : const Color(0xFF2E2A4E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.inter(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubFilterChip(String label, MapEventType sampleType) {
    final isSelected = _selectedSubCategory == label;
    final color = MapEventTypeHelper.getColor(sampleType);
    final count = _getFilterCount(label, null);

    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedSubCategory = isSelected ? null : label;
            _selectedGig = null;
            _selectedRehearsal = null;
            _isAutoSelected = false;
            _manuallyClosedTargetId = null;
          });
          final appState = Provider.of<AppState>(context, listen: false);
          _evaluateCrosshairTargeting(_getFilteredGigs(appState.currentUserProfile));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.25)
                : const Color(0xFF0F0C20).withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : const Color(0xFF2E2A4E),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '($count)',
                  style: GoogleFonts.inter(
                    color: isSelected ? Colors.white70 : Colors.white38,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInstrumentTaxonomyPicker() async {
    final categoryMap = SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.findSub);
    final selectedList = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Select Role / Instrument',
      categoryMap: categoryMap,
      initialSelected: _instrumentQuery.isNotEmpty ? [_instrumentQuery] : [],
      isSingleSelect: true,
      presentation: CategoryPickerPresentation.skillsHierarchy,
    );
    if (selectedList != null) {
      setState(() {
        if (selectedList.isNotEmpty) {
          _instrumentQuery = selectedList.first;
          _instrumentSearchController.text = _instrumentQuery;
          _showInstrumentSearch = true;
        } else {
          _instrumentQuery = '';
          _instrumentSearchController.clear();
          _showInstrumentSearch = false;
        }
      });
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
      _evaluateCrosshairTargeting(_getFilteredGigs(appState.currentUserProfile));
    }
  }

  Widget _buildInstrumentFilterToggle() {
    final isFiltering = _instrumentQuery.isNotEmpty;
    return GestureDetector(
      onTap: _openInstrumentTaxonomyPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isFiltering
              ? const Color(0xFF84CC16).withOpacity(0.25)
              : const Color(0xFF0F0C20).withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFiltering
                ? const Color(0xFF84CC16)
                : const Color(0xFF2E2A4E),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_rounded,
              size: 13,
              color: isFiltering
                  ? const Color(0xFF84CC16)
                  : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              isFiltering ? 'Instrument: $_instrumentQuery' : 'Search Instruments',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isFiltering
                    ? Colors.white
                    : Colors.white70,
              ),
            ),
            if (isFiltering) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _instrumentQuery = '';
                    _instrumentSearchController.clear();
                    _showInstrumentSearch = false;
                  });
                  final appState = Provider.of<AppState>(context, listen: false);
                  _evaluateCrosshairTargeting(_getFilteredGigs(appState.currentUserProfile));
                },
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInstrumentSearchBar() {
    const commonInstruments = ['Guitar', 'Bass', 'Drums', 'Vocals', 'Keys', 'Horns', 'Cello'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0C20).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF84CC16).withOpacity(0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _instrumentSearchController,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Filter by instrument or role (e.g. Bass, Drums)...',
                      hintStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF84CC16)),
                      suffixIcon: _instrumentQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 14, color: Colors.white70),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                setState(() {
                                  _instrumentQuery = '';
                                  _instrumentSearchController.clear();
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                      filled: true,
                      fillColor: const Color(0xFF1E1A38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _instrumentQuery = val;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: commonInstruments.map((inst) {
                final isSelected = _instrumentQuery.toLowerCase() == inst.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _instrumentQuery = '';
                          _instrumentSearchController.clear();
                        } else {
                          _instrumentQuery = inst;
                          _instrumentSearchController.text = inst;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF84CC16).withOpacity(0.35)
                            : const Color(0xFF1A1633),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF84CC16) : const Color(0xFF2E2A4E),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        inst,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}


