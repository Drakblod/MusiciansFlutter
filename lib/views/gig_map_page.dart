import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
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
import '../data/stockholm_demo_pins.dart';
import '../data/genres_taxonomy.dart';
import '../data/skills_taxonomy.dart';
import '../services/mock_rehearsal_audio_controller.dart';
import '../services/route_observer.dart';
import '../widgets/map_crosshair.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/what_is_map_view_dialog.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';
import '../utils/map_crosshair_targeting.dart';
import '../utils/map_event_activity_helper.dart';
import '../widgets/map_pin_details_card.dart';
import '../models/live_broadcast.dart';
import '../services/live_broadcast_service.dart';
import '../services/livekit_audio_controller.dart';
import '../widgets/start_live_broadcast_dialog.dart';
import '../widgets/live_broadcaster_bar.dart';
import '../widgets/live_listener_sheet.dart';
import '../widgets/live_listener_bar.dart';
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
    const double canvasWidth = 60.0;
    const double canvasHeight = 74.0;

    // Outer badge: Rectangle with crisp black border and subtle rounded corners
    const double badgeLeft = 4.0;
    const double badgeTop = 4.0;
    const double badgeWidth = 52.0;
    const double badgeHeight = 66.0;
    final badgeRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(badgeLeft, badgeTop, badgeWidth, badgeHeight),
      const Radius.circular(9.0),
    );

    // 1. Drop Shadow for badge
    final shadowPaint = Paint()
      ..color = hasGlow
          ? color.withValues(alpha: 0.70 * opacity)
          : Colors.black.withValues(alpha: 0.40 * opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, hasGlow ? 5.0 : 3.0);
    canvas.drawRRect(badgeRRect.shift(const Offset(1.0, 2.0)), shadowPaint);

    // 2. Badge Fill (clean high-contrast white / subtle warm ivory backing)
    final badgeFillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * opacity)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(badgeRRect, badgeFillPaint);

    // 3. Crisp Black Outer Frame (2.2px black border per owner requirement)
    final badgeBorderPaint = Paint()
      ..color = Colors.black.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(badgeRRect, badgeBorderPaint);

    // Eighth Note (Åttondelsnot ♪) Geometry inside badge
    // Head center
    const double headCenterX = 23.0;
    const double headCenterY = 50.0;
    const double headRadiusX = 9.5;
    const double headRadiusY = 6.5;
    const double tiltAngle = -26.0 * (math.pi / 180.0);

    // Stem: vertical shaft rising from right edge of notehead
    const double stemX = headCenterX + 7.6; // ~30.6
    const double stemTopY = 14.0;
    const double stemBottomY = headCenterY + 1.0;
    const double stemWidth = 2.4;

    final noteColor = color.withValues(alpha: opacity);

    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final notePaint = Paint()
      ..color = noteColor
      ..style = PaintingStyle.fill;

    // 4. Draw Stem
    final stemRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(stemX - stemWidth / 2, stemTopY, stemWidth, stemBottomY - stemTopY),
      const Radius.circular(1.2),
    );
    canvas.drawRRect(stemRRect, outlinePaint);
    canvas.drawRRect(stemRRect, notePaint);

    // 5. Draw Eighth Note Flag (Åttondels-fana/flagga sweeping out and downward)
    final flagPath = Path();
    flagPath.moveTo(stemX, stemTopY);
    // Outer wave curving to the right and down
    flagPath.cubicTo(
      stemX + 8.0, stemTopY + 1.5,
      stemX + 13.5, stemTopY + 6.0,
      stemX + 13.0, stemTopY + 16.5,
    );
    // Tapering hook point returning inwards to stem
    flagPath.cubicTo(
      stemX + 12.0, stemTopY + 23.0,
      stemX + 7.5, stemTopY + 21.0,
      stemX, stemTopY + 17.5,
    );
    flagPath.close();

    canvas.drawPath(flagPath, outlinePaint);
    canvas.drawPath(flagPath, notePaint);

    // 6. Draw Egg-Shaped Notehead
    canvas.save();
    canvas.translate(headCenterX, headCenterY);
    canvas.rotate(tiltAngle);

    final outerHeadRect = Rect.fromCenter(
      center: Offset.zero,
      width: headRadiusX * 2,
      height: headRadiusY * 2,
    );

    if (isHalfNote) {
      // Halvnot: Open egg-shaped notehead
      canvas.drawOval(outerHeadRect, outlinePaint);
      canvas.drawOval(outerHeadRect, notePaint);

      canvas.rotate(-16.0 * (math.pi / 180.0));
      final innerHeadRect = Rect.fromCenter(
        center: Offset.zero,
        width: headRadiusX * 1.35,
        height: headRadiusY * 0.65,
      );

      final clearPaint = Paint()..blendMode = BlendMode.clear;
      canvas.drawOval(innerHeadRect, clearPaint);
      canvas.drawOval(innerHeadRect, outlinePaint);
    } else {
      // Åttondelsnot: Solid filled egg-shaped notehead
      canvas.drawOval(outerHeadRect, outlinePaint);
      canvas.drawOval(outerHeadRect, notePaint);
    }

    canvas.restore();

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(canvasWidth.toInt(), canvasHeight.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    // Rendered on map at 30x37 points
    return BitmapDescriptor.bytes(bytes, width: 30, height: 37);
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
        return 'Demos / Recordings';
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

  @visibleForTesting
  static const String darkMapStyle = _GigMapPageState._darkMapStyle;
  @visibleForTesting
  static const String whiteMapStyle = _GigMapPageState._whiteMapStyle;

  @override
  State<GigMapPage> createState() => _GigMapPageState();
}

class _GigMapPageState extends State<GigMapPage> with WidgetsBindingObserver, RouteAware {

  // --- New Pin Ripple Wave Spotter ---
  LatLng? _newPinRippleLocation;
  DateTime? _newPinRippleStartTime;
  Timer? _newPinRippleTimer;
  double _rippleWavePhase = 0.0;

  void _triggerNewPinRipple(LatLng position) {
    _newPinRippleLocation = position;
    _newPinRippleStartTime = DateTime.now();
    _newPinRippleTimer?.cancel();
    _newPinRippleTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _newPinRippleLocation == null || _newPinRippleStartTime == null) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_newPinRippleStartTime!).inSeconds;
      if (elapsed >= 30) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _newPinRippleLocation = null;
            _newPinRippleStartTime = null;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _rippleWavePhase = (DateTime.now().millisecondsSinceEpoch % 2000) / 2000.0;
        });
      }
    });
  }

  Set<Circle> _buildPinRipples() {
    if (_newPinRippleLocation == null) return {};
    final wave1 = _rippleWavePhase;
    final wave2 = (_rippleWavePhase + 0.5) % 1.0;

    return {
      Circle(
        circleId: const CircleId('new_pin_ripple_1'),
        center: _newPinRippleLocation!,
        radius: 30.0 + (wave1 * 180.0),
        strokeWidth: 2,
        strokeColor: AppTheme.primaryAccent.withValues(alpha: (1.0 - wave1) * 0.75),
        fillColor: AppTheme.primaryAccent.withValues(alpha: (1.0 - wave1) * 0.20),
      ),
      Circle(
        circleId: const CircleId('new_pin_ripple_2'),
        center: _newPinRippleLocation!,
        radius: 30.0 + (wave2 * 180.0),
        strokeWidth: 2,
        strokeColor: AppTheme.primaryAccent.withValues(alpha: (1.0 - wave2) * 0.75),
        fillColor: AppTheme.primaryAccent.withValues(alpha: (1.0 - wave2) * 0.20),
      ),
    };
  }

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
  String? _focusedTargetId;
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
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
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
    "featureType": "road.highway",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
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
    "featureType": "road.arterial",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.arterial",
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.local",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.local",
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
        "visibility": "off"
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
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
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
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
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
    "featureType": "road.arterial",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.arterial",
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.local",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.local",
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
        "visibility": "off"
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
      final isLiveEligible = type == MapEventType.gigConcert || type == MapEventType.rehearsal;

      // Always generate and cache a base static pin for every type
      final keyStatic = type.name;
      if (!_notePinCache.containsKey(keyStatic)) {
        try {
          _notePinCache[keyStatic] = await MapEventTypeHelper.createNoteBitmap(
            color: color,
            isHalfNote: isLiveEligible,
            opacity: 1.0,
            hasGlow: false,
          );
        } catch (e) {
          debugPrint('Error generating static note pin $keyStatic: $e');
        }
      }

      // For Gig/Concert and Rehearsal, generate animated blinking variations
      if (isLiveEligible) {
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
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  BitmapDescriptor _getNoteDescriptor(MapEventType eventType, {bool isLive = false}) {
    if (isLive && (eventType == MapEventType.gigConcert || eventType == MapEventType.rehearsal)) {
      final key = '${eventType.name}_${_liveNoteBlinkOn ? 'on' : 'dim'}';
      if (_notePinCache.containsKey(key)) {
        return _notePinCache[key]!;
      }
    }
    if (_notePinCache.containsKey(eventType.name)) {
      return _notePinCache[eventType.name]!;
    }
    return MapEventTypeHelper.getMarkerIcon(eventType);
  }

  static bool _isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90.0 || lat > 90.0) return false;
    if (lng < -180.0 || lng > 180.0) return false;
    return true;
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    final clean = address.trim();
    if (clean.isEmpty) return null;

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
          if (lat != null && lon != null && _isValidCoordinate(lat, lon)) {
            return LatLng(lat, lon);
          }
        }
      }
    } catch (_) {}

    return null;
  }

  void _openBandProfile({
    required BuildContext context,
    required String bandId,
  }) async {
    final appState = Provider.of<AppState>(context, listen: false);
    try {
      final band = await appState.firebaseService.getBandInfoAsync(bandId);
      if (band != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EditBandInfoScreen(band: band)),
        );
      }
    } catch (e) {
      debugPrint('[MapPin] Error loading band info: $e');
    }
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute is PageRoute) {
      appRouteObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void didPushNext() {
    // Another screen was pushed on top of GigMapPage (e.g. Edit Band, Inbox, Profile, Settings)
    if (FeatureFlags.enableMockLiveRehearsals) {
      _audioController?.pauseAudio();
    }
    if (FeatureFlags.enableRealLiveBroadcasts && _liveKitAudioController != null) {
      if (_currentlyListeningBroadcast != null) {
        _liveBroadcastService?.leaveLiveBroadcast(broadcastId: _currentlyListeningBroadcast!.id);
        _liveKitAudioController!.disconnect();
        _currentlyListeningBroadcast = null;
      }
    }
  }

  @override
  void didPopNext() {
    // User popped the screen that was covering GigMapPage and returned back
    if (FeatureFlags.enableMockLiveRehearsals && _audioController != null) {
      if (!_audioController!.isAudioStopped && !_audioController!.isMuted) {
        _audioController!.resumeAudio();
        _audioController!.updateCameraTarget(
          _currentCameraPosition.target,
          immediate: true,
          zoom: _currentCameraPosition.zoom,
        );
      }
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
    appRouteObserver.unsubscribe(this);
    _liveBlinkTimer?.cancel();
    _instrumentSearchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (FeatureFlags.enableMockLiveRehearsals) {
      _audioController?.dispose();
    }
    if (FeatureFlags.enableRealLiveBroadcasts) {
      _liveBroadcastsSubscription?.cancel();
      if (_liveKitAudioController != null) {
        if (_liveKitAudioController!.isListener || _currentlyListeningBroadcast != null) {
          if (_currentlyListeningBroadcast != null) {
            _liveBroadcastService?.leaveLiveBroadcast(broadcastId: _currentlyListeningBroadcast!.id);
          }
          _liveKitAudioController!.disconnect();
          _currentlyListeningBroadcast = null;
        }
        if (!_liveKitAudioController!.isPublisher) {
          _liveKitAudioController!.dispose();
        }
      }
    }
    _newPinRippleTimer?.cancel();
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
      case 'Gigs / Rehearsals':
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
      if (gig.latitude != null && gig.longitude != null && gig.canonicalTargetId != null) {
        candidates.add(MapTargetCandidate.fromSubRequest(gig));
      }
    }

    final showRehearsals = FeatureFlags.enableMockLiveRehearsals &&
        (_selectedMainCategory == 'All' ||
            (_selectedMainCategory == 'Music' &&
                (_selectedSubCategory == null ||
                    _selectedSubCategory == 'All Music' ||
                    _selectedSubCategory == 'Rehearsal' ||
                    (_selectedSubCategory == 'Gigs / Rehearsals' || _selectedSubCategory == 'Live Gigs / Rehearsals'))));

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
      _focusedTargetId = null;
      if (FeatureFlags.enableMockLiveRehearsals) {
        _audioController?.setFocusedTargetId(null);
      }
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
    _focusedTargetId = bestTarget.id;
    if (FeatureFlags.enableMockLiveRehearsals) {
      _audioController?.setFocusedTargetId(bestTarget.id);
    }

    final currentSelectedId = _selectedGig?.canonicalTargetId ?? _selectedRehearsal?.id;

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
    final isLive = isSubRequestActive(gig);
    return _getNoteDescriptor(eventType, isLive: isLive);
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
        if ((_selectedSubCategory == 'Gigs / Rehearsals' || _selectedSubCategory == 'Live Gigs / Rehearsals')) {
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
        markerId: MarkerId(gig.canonicalTargetId ?? UniqueKey().toString()),
        position: LatLng(gig.latitude!, gig.longitude!),
        icon: _getMarkerColor(gig),
        anchor: const Offset(0.321, 0.716),
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
                    (_selectedSubCategory == 'Gigs / Rehearsals' || _selectedSubCategory == 'Live Gigs / Rehearsals'))));

    final Set<Marker> realLiveMarkers = {};
    if (FeatureFlags.enableRealLiveBroadcasts && _activeRealBroadcasts.isNotEmpty) {
      for (final broadcast in _activeRealBroadcasts) {
        realLiveMarkers.add(
          Marker(
            markerId: MarkerId('real_live_${broadcast.id}'),
            position: LatLng(broadcast.latitude, broadcast.longitude),
            icon: _getNoteDescriptor(MapEventType.gigConcert),
            anchor: const Offset(0.321, 0.716),
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
      final isLive = isMockLiveRehearsalActive(rehearsal);
      return Marker(
        markerId: MarkerId(rehearsal.id),
        position: rehearsal.position,
        icon: _getNoteDescriptor(MapEventType.rehearsal, isLive: isLive),
        anchor: const Offset(0.321, 0.716),
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
        final bId = broadcast.id;
        await _liveKitAudioController?.disconnect();
        await _liveBroadcastService?.leaveLiveBroadcast(broadcastId: bId);
        if (mounted) {
          setState(() {
            _currentlyListeningBroadcast = null;
          });
        }
      },
    );
  }

  bool get _hasStockholmDemoPins => _allGigs.any((g) => g.extraFields['isDemoStockholm'] == true);

  void _loadStockholmDemoPins() {
    final appState = Provider.of<AppState>(context, listen: false);
    final myUid = appState.currentUserId ?? 'demo_user';
    final demoPins = getStockholmDemoPins(myUid);

    setState(() {
      _allGigs.removeWhere((g) => g.extraFields['isDemoStockholm'] == true);
      _allGigs.insertAll(0, demoPins);
      if (demoPins.isNotEmpty) {
        _selectedGig = demoPins.first;
        _focusedTargetId = demoPins.first.canonicalTargetId;
      }
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(const LatLng(59.3293, 18.0686), 13.0),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('20 Stockholm demo pins loaded! Tap "Clear Sthlm Pins" anytime to remove.'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  void _clearStockholmDemoPins() {
    setState(() {
      _allGigs.removeWhere((g) => g.extraFields['isDemoStockholm'] == true);
      if (_selectedGig?.extraFields['isDemoStockholm'] == true) {
        _selectedGig = null;
        _focusedTargetId = null;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All Stockholm demo pins removed cleanly.'),
        backgroundColor: Colors.blueGrey,
      ),
    );
  }

  void _confirmDeletePin(SubRequest pin) {
    final appState = Provider.of<AppState>(context, listen: false);
    final pinId = pin.canonicalTargetId ?? pin.id;
    if (pinId == null || pinId.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0C20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2A4E)),
        ),
        title: Text(
          'Delete Map Pin',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete this map pin? This action cannot be undone.',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                final myUid = appState.currentUserId ?? '';
                final ok = await appState.firebaseService.deleteSubRequestAsync(myUid, pinId);
                if (ok && mounted) {
                  setState(() {
                    _allGigs.removeWhere((g) => g.canonicalTargetId == pinId || g.id == pinId);
                    if (_selectedGig?.canonicalTargetId == pinId || _selectedGig?.id == pinId) {
                      _selectedGig = null;
                      _focusedTargetId = null;
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Map pin deleted successfully.'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete pin: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showUploadEventSheet({SubRequest? editingPin}) {
    final isEditing = editingPin != null;
    String selectedCategory = editingPin?.extraFields['subCategory']?.toString() ?? 'Music';
    String selectedType = editingPin?.requestType ?? (selectedCategory == 'Music' ? 'Gig / Concert' : 'Substitute');
    List<String> selectedGenres = [
      editingPin?.extraFields['genre']?.toString() ?? editingPin?.style ?? 'Big Band Contemporary'
    ];
    DateTime selectedDate = editingPin?.date != null
        ? (DateTime.tryParse(editingPin!.date!) ?? DateTime.now().add(const Duration(days: 7)))
        : DateTime.now().add(const Duration(days: 7));
    TimeOfDay selectedStartTime = const TimeOfDay(hour: 18, minute: 0);
    TimeOfDay selectedEndTime = const TimeOfDay(hour: 21, minute: 0);
    if (editingPin?.startTime != null) {
      final parts = editingPin!.startTime!.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) selectedStartTime = TimeOfDay(hour: h, minute: m);
      }
    }
    if (editingPin?.endTime != null) {
      final parts = editingPin!.endTime!.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) selectedEndTime = TimeOfDay(hour: h, minute: m);
      }
    }

    final bandNameController = TextEditingController(text: editingPin?.bandName ?? '');
    final venueController = TextEditingController(text: editingPin?.extraFields['venue']?.toString() ?? '');
    final locationController = TextEditingController(text: editingPin?.location ?? '');
    final descriptionController = TextEditingController(text: editingPin?.description ?? '');
    final audioTrackController = TextEditingController(
      text: editingPin?.extraFields['audioSnippetTitle']?.toString() ??
          editingPin?.extraFields['infoAudioTrack']?.toString() ??
          '',
    );
    PlatformFile? pickedAudioFile;
    bool isPublishing = false;
    String? uploadErrorMessage;

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
              ? [
                  'Gig',
                  'Concert',
                  'Festival',
                  'Rehearsal',
                  'Demo',
                  'Recording',
                  'Jam Session',
                  'Songwriting Session',
                  'Workshop',
                  'Lecture',
                  'Other'
                ]
              : [
                  'New Member',
                  'Substitute'
                ];

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
                    isEditing ? 'Update pin details, venue or audio track info.' : 'Post a pin to Map View and attach an audio track for other musicians and audiences to discover.',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  
                  // Category Selector
                  Text('Category', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  Row(
                    children: ['Music', 'Sub & Member Search'].map((cat) {
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
                                                                if (cat == 'Sub & Member Search') selectedType = 'Substitute';
                              });
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Standardized Event / Search Type Selector (Clean Dropdown, no 'Type' prefix)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1A38),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF38325A)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: typesForCategory.contains(selectedType) ? selectedType : typesForCategory.first,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1A1633),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                        items: typesForCategory.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(
                              type,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (newVal) {
                          if (newVal != null) {
                            setSheetState(() => selectedType = newVal);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Band Name
                  TextField(
                    controller: bandNameController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Band Name / Artist',
                      helperText: 'Leave blank to place the pin at the current map centre.',
                      helperStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
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
                      labelText: 'Venue (e.g. Ronnie Scott\'s, Blue Note)',
                      hintText: 'e.g. Ronnie Scott\'s, Blue Note, Village Vanguard',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Description / Details
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
                  const SizedBox(height: 10),

                  // Location
                  TextField(
                    controller: locationController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Street Address (Optional)',
                      hintText: 'e.g. 123 Main Street, Stockholm (or leave blank)',
                      helperText: 'Optional. Leave blank to place the pin at crosshair map centre.',
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
                                        'Start Time',
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
                                        'End Time',
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

                  // Audio Track info (title + info)
                  Text('Audio Track info (title + info)', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: audioTrackController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Audio Track info (title + info)',
                      hintText: 'e.g. Live at Montreux, rough horn mix',
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

                  // In-modal error banner (visible inside sheet)
                  if (uploadErrorMessage != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerRed.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.dangerRed.withOpacity(0.55)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRed, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              uploadErrorMessage!,
                              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Publish Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: isPublishing
                          ? null
                          : () async {
                              if (isPublishing) return;
                              final appState = Provider.of<AppState>(context, listen: false);
                              setSheetState(() => isPublishing = true);
                              final band = bandNameController.text.trim().isEmpty ? 'My Band' : bandNameController.text.trim();
                              final descText = descriptionController.text.trim();
                              final title = descText.isEmpty ? selectedType : descText;
                              final venueText = venueController.text.trim();
                              final addressText = locationController.text.trim();

                              LatLng targetLatLng;
                              String effectiveLocation;

                              if (addressText.isEmpty) {
                                if (ctx.mounted) {
                                  setSheetState(() {
                                    isPublishing = false;
                                    uploadErrorMessage = 'Please enter a street address and city (e.g. "Kungsgatan 12, Stockholm") so musicians can locate your pin.';
                                  });
                                }
                                return;
                              }

                              final geocoded = await _geocodeAddress(addressText);
                              if (geocoded == null || !_isValidCoordinate(geocoded.latitude, geocoded.longitude)) {
                                if (ctx.mounted) {
                                  setSheetState(() {
                                    isPublishing = false;
                                    uploadErrorMessage = 'Could not locate address "$addressText". Please specify street, house number and city.';
                                  });
                                }
                                return;
                              }
                              targetLatLng = geocoded;
                              effectiveLocation = addressText;

                              String mappedType = 'gigConcert';
                              if (selectedType == 'Rehearsal') mappedType = 'rehearsal';
                              if (selectedType == 'Jam Session') mappedType = 'jamSession';
                              if (selectedType == 'Recorded Music' || selectedType == 'Demos / Recordings') mappedType = 'recordedMusic';
                              if (selectedType == 'Gig Promo') mappedType = 'gigPromo';
                              if (selectedType == 'New Member') mappedType = 'newMember';
                              if (selectedType == 'Substitute') mappedType = 'subs';
                              if (selectedType == 'Paid Gigs') mappedType = 'paid';

                              final audioText = audioTrackController.text.trim();
                              final audioInfo = audioText;

                              String? audioUrl;
                              if (pickedAudioFile != null) {
                                try {
                                  final userId = appState.currentUserId ?? 'map_user';
                                  audioUrl = await appState.firebaseService.uploadAudioSnippetAsync(
                                    userId,
                                    pickedAudioFile!.bytes,
                                    pickedAudioFile!.path,
                                  );
                                  if (audioUrl.isEmpty) {
                                    throw Exception('Audio upload returned an empty URL.');
                                  }
                                } catch (e) {
                                  debugPrint('[UploadPin] Storage upload failed: $e');
                                  if (ctx.mounted) {
                                    setSheetState(() {
                                      isPublishing = false;
                                      uploadErrorMessage = 'Failed to upload audio file: $e';
                                    });
                                  }
                                  return;
                                }
                              } else if (audioText.isNotEmpty) {
                                audioUrl = audioText;
                              }

                              final isStaffingSearch = selectedCategory == 'Sub & Member Search';

                              final draftGig = SubRequest(
                                bandName: band,
                                bandId: appState.activeBandId,
                                role: isStaffingSearch ? title : null,
                                voicePart: isStaffingSearch ? title : null,
                                requestType: selectedType,
                                location: effectiveLocation,
                                date: selectedDate.toIso8601String(),
                                startTime: '${selectedStartTime.hour.toString().padLeft(2, '0')}:${selectedStartTime.minute.toString().padLeft(2, '0')}:00',
                                endTime: '${selectedEndTime.hour.toString().padLeft(2, '0')}:${selectedEndTime.minute.toString().padLeft(2, '0')}:00',
                                description: descText.isNotEmpty ? descText : null,
                                latitude: targetLatLng.latitude,
                                longitude: targetLatLng.longitude,
                                isPaid: selectedType == 'Paid Gigs',
                                payAmount: 2000,
                                responses: const {},
                                style: selectedGenres.isNotEmpty ? selectedGenres.first : 'Big Band Contemporary',
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
                                  if (!isStaffingSearch) 'NotificationMode': 'map_pin',
                                },
                              );

                              SubRequest publishedGig;
                              try {
                                if (isEditing) {
                                  final pinId = editingPin.canonicalTargetId ?? editingPin.id;
                                  final updateDraft = draftGig.copyWith(
                                    id: pinId,
                                    subRequestId: pinId,
                                  );
                                  publishedGig = await appState.firebaseService.updateMapPinAsync(updateDraft);
                                } else if (isStaffingSearch) {
                                  final savedKey = await appState.firebaseService.saveSubRequestAsync(draftGig);
                                  if (savedKey == null || savedKey.isEmpty) {
                                    throw Exception('Database write did not return a valid key.');
                                  }
                                  publishedGig = draftGig.copyWith(
                                    id: savedKey,
                                    subRequestId: savedKey,
                                  );
                                } else {
                                  publishedGig = await appState.firebaseService.saveMapPinAsync(draftGig);
                                }
                              } catch (e) {
                                debugPrint('[UploadPin] Database write failed: $e');
                                if (ctx.mounted) {
                                  setSheetState(() {
                                    isPublishing = false;
                                    uploadErrorMessage = 'Failed to save pin: $e';
                                  });
                                }
                                return;
                              }

                              final effectiveTargetId = publishedGig.canonicalTargetId;

                              setState(() {
                                if (effectiveTargetId != null) {
                                  _allGigs.removeWhere((g) => g.canonicalTargetId == effectiveTargetId);
                                }
                                _allGigs.insert(0, publishedGig);
                                _selectedGig = publishedGig;
                                _focusedTargetId = effectiveTargetId;
                                _selectedRehearsal = null;
                                _isAutoSelected = false;
                                _manuallyClosedTargetId = null;
                              });

                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(targetLatLng, 15.0),
                              );
                              _triggerNewPinRipple(targetLatLng);

                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Pin published at $effectiveLocation!'),
                                    backgroundColor: AppTheme.success,
                                  ),
                                );
                              }
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
                              isEditing ? 'Save Changes' : 'Publish Map View Pin / Audio',
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
                        _audioController?.updateCameraTarget(
                          _currentCameraPosition.target,
                          immediate: true,
                          zoom: _currentCameraPosition.zoom,
                        );
                      }
                    },
                    onCameraMove: (position) {
                      _currentCameraPosition = position;
                      if (FeatureFlags.enableMockLiveRehearsals) {
                        _audioController?.updateCameraTarget(
                          position.target,
                          zoom: position.zoom,
                        );
                      }
                    },
                    onCameraIdle: () {
                      if (FeatureFlags.enableMockLiveRehearsals && _mapController != null) {
                        _mapController?.getVisibleRegion();
                        _audioController?.updateCameraTarget(
                          _currentCameraPosition.target,
                          immediate: true,
                          zoom: _currentCameraPosition.zoom,
                        );
                      }
                      _evaluateCrosshairTargeting(filteredGigs);
                    },
                    markers: markers,
                    circles: _buildPinRipples(),
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    onTap: (_) {
                      // Deselect gig and rehearsal on tapping map empty space
                      final closedId = _selectedGig?.canonicalTargetId ?? _selectedRehearsal?.id;
                      if (FeatureFlags.enableMockLiveRehearsals) {
                        _audioController?.setFocusedTargetId(null);
                      }
                      setState(() {
                        _selectedGig = null;
                        _selectedRehearsal = null;
                        _focusedTargetId = null;
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

                  // Listener sticky bar (when local user is tuned into a live stream)
                  if (_currentlyListeningBroadcast != null && _liveKitAudioController != null)
                    LiveListenerBar(
                      broadcast: _currentlyListeningBroadcast!,
                      audioController: _liveKitAudioController!,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      onLeave: () async {
                        final bId = _currentlyListeningBroadcast!.id;
                        await _liveKitAudioController?.disconnect();
                        await _liveBroadcastService?.leaveLiveBroadcast(broadcastId: bId);
                        if (mounted) {
                          setState(() {
                            _currentlyListeningBroadcast = null;
                          });
                        }
                      },
                      onTap: () {
                        if (_currentlyListeningBroadcast != null) {
                          _showLiveBroadcastDetails(_currentlyListeningBroadcast!);
                        }
                      },
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
                          _buildSubFilterChip('Gigs / Rehearsals', MapEventType.gigConcert),
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

            // Unified Persistent Bottom Area: Live Audio Bar ("Turn ON/OFF & Mute") is ALWAYS visible!
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Live Audio Bar ("Turn ON/OFF & Mute") - ALWAYS VISIBLE
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _buildLiveAudioBar(isDocked: true),
                    ),
                    const SizedBox(height: 8),

                    // Active content card or default action buttons
                    if (_selectedGig != null)
                      _buildBottomCardContent(_selectedGig!, appState)
                    else if (_selectedRehearsal != null)
                      _buildRehearsalBottomCardContent(_selectedRehearsal!)
                    else
                      // Default Action buttons (Upload, Go Live, 20 Sthlm Pins)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
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
                            const SizedBox(width: 8),
                            // 20 Stockholm Demo Pins Quick Loader / Clearer
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _hasStockholmDemoPins ? _clearStockholmDemoPins : _loadStockholmDemoPins,
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: _hasStockholmDemoPins
                                      ? AppTheme.dangerRed.withOpacity(0.25)
                                      : const Color(0xFF1A1633),
                                  borderRadius: BorderRadius.circular(19),
                                  border: Border.all(
                                    color: _hasStockholmDemoPins
                                        ? AppTheme.dangerRed.withOpacity(0.7)
                                        : const Color(0xFF38BDF8),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_hasStockholmDemoPins ? AppTheme.dangerRed : const Color(0xFF38BDF8)).withOpacity(0.2),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _hasStockholmDemoPins ? Icons.delete_sweep_rounded : Icons.location_city_rounded,
                                      size: 15,
                                      color: _hasStockholmDemoPins ? AppTheme.dangerRed : const Color(0xFF38BDF8),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _hasStockholmDemoPins ? 'Clear Sthlm Pins' : '20 Sthlm Pins',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
            if (isStopped) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _isAutoSelected = false);
                  _audioController?.toggleAudioPower();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_off_rounded, size: 14, color: AppTheme.danger),
                    const SizedBox(width: 6),
                    Text(
                      'Turn ON Audio',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.play_arrow_rounded, size: 15, color: AppTheme.success),
                  ],
                ),
              );
            }

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
                        setState(() {
                          _isAutoSelected = false;
                        });
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
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isStopped
                          ? null
                          : () {
                              setState(() {
                                _isAutoSelected = false;
                              });
                              _audioController?.toggleMute();
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isStopped
                              ? const Color(0xFF2E2A4E).withOpacity(0.4)
                              : (isMuted
                                  ? AppTheme.primaryAccent.withOpacity(0.2)
                                  : const Color(0xFF2E2A4E)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isStopped
                                ? const Color(0xFF433D72).withOpacity(0.4)
                                : (isMuted
                                    ? AppTheme.primaryAccent.withOpacity(0.6)
                                    : const Color(0xFF433D72)),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                              size: 13,
                              color: isStopped
                                  ? Colors.white38
                                  : (isMuted ? AppTheme.primaryAccent : Colors.white70),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isMuted ? 'Unmute' : 'Mute',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isStopped
                                    ? Colors.white38
                                    : (isMuted ? AppTheme.primaryAccent : Colors.white70),
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
    return MapPinDetailsCard(
      gig: gig,
      appState: appState,
      focusedTargetId: _focusedTargetId,
      onClose: () {
        final closedId = _selectedGig?.canonicalTargetId;
        if (FeatureFlags.enableMockLiveRehearsals) {
          _audioController?.setFocusedTargetId(null);
        }
        setState(() {
          _selectedGig = null;
          _focusedTargetId = null;
          _isAutoSelected = false;
          _manuallyClosedTargetId = closedId;
        });
      },
      onOpenBandProfile: (ctx, bandId) {
        _openBandProfile(
          context: ctx,
          bandId: bandId,
        );
      },
      onEditPin: (pin) {
        _showUploadEventSheet(editingPin: pin);
      },
      onDeletePin: (pin) {
        _confirmDeletePin(pin);
      },
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
                              color: const Color(0xFF60A5FA),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final closedId = _selectedRehearsal?.id;
                    if (FeatureFlags.enableMockLiveRehearsals) {
                      _audioController?.setFocusedTargetId(null);
                    }
                    setState(() {
                      _selectedRehearsal = null;
                      _focusedTargetId = null;
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
          if (FeatureFlags.enableMockLiveRehearsals) {
            _audioController?.setFocusedTargetId(null);
          }
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
            _focusedTargetId = null;
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
          if (FeatureFlags.enableMockLiveRehearsals) {
            _audioController?.setFocusedTargetId(null);
          }
          setState(() {
            _selectedSubCategory = isSelected ? null : label;
            _selectedGig = null;
            _selectedRehearsal = null;
            _focusedTargetId = null;
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


