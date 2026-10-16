import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../models/user_profile.dart';
import '../config/feature_flags.dart';
import '../models/mock_live_rehearsal.dart';
import '../data/mock_live_rehearsals.dart';
import '../data/genres_taxonomy.dart';
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

class MapCityPreset {
  final String name;
  final LatLng coordinates;
  final double zoom;

  const MapCityPreset({
    required this.name,
    required this.coordinates,
    this.zoom = 12.0,
  });
}

const List<MapCityPreset> kMapCityPresets = [
  MapCityPreset(name: 'Stockholm', coordinates: LatLng(59.3293, 18.0686), zoom: 12.0),
  MapCityPreset(name: 'Göteborg', coordinates: LatLng(57.7089, 11.9746), zoom: 12.0),
  MapCityPreset(name: 'Malmö', coordinates: LatLng(55.6050, 13.0038), zoom: 12.0),
  MapCityPreset(name: 'Uppsala', coordinates: LatLng(59.8586, 17.6389), zoom: 12.5),
  MapCityPreset(name: 'Örebro', coordinates: LatLng(59.2753, 15.2134), zoom: 12.5),
  MapCityPreset(name: 'Linköping', coordinates: LatLng(58.4108, 15.6214), zoom: 12.5),
  MapCityPreset(name: 'Umeå', coordinates: LatLng(63.8258, 20.2630), zoom: 12.0),
  MapCityPreset(name: 'All Sweden', coordinates: LatLng(59.8, 16.5), zoom: 5.5),
];

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

  static Future<BitmapDescriptor> createWebPinBitmap(Color color) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const double width = 52;
    const double height = 76;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(width / 2, height - 3), width: 14, height: 6),
      shadowPaint,
    );

    final path = Path();
    const double radius = 19.0;
    const center = Offset(width / 2, radius + 3);

    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
    );
    path.lineTo(width / 2, height - 6);
    path.close();

    final bodyPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, bodyPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, borderPaint);

    final innerDiscPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 9, innerDiscPaint);

    final centerDotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5.0, centerDotPaint);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(bytes, width: 26, height: 38);
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
  String _selectedMainCategory = 'All';
  String? _selectedSubCategory;
  String _instrumentQuery = '';
  final TextEditingController _instrumentSearchController = TextEditingController();
  bool _showInstrumentSearch = false;

  String get _selectedFilter => _selectedMainCategory;
  set _selectedFilter(String val) {
    _selectedMainCategory = val;
  }

  String? _selectedCityName;
  SubRequest? _selectedGig;
  bool _showGuideBanner = true;
  bool _showLegend = false;

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

  static final Map<MapEventType, BitmapDescriptor> _webPinCache = {};

  Future<void> _initWebPins() async {
    if (!kIsWeb) return;
    for (final type in MapEventType.values) {
      if (!_webPinCache.containsKey(type)) {
        try {
          final color = MapEventTypeHelper.getColor(type);
          final descriptor = await MapEventTypeHelper.createWebPinBitmap(color);
          _webPinCache[type] = descriptor;
        } catch (e) {
          debugPrint('Error generating web pin for $type: $e');
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
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

  @override
  void initState() {
    super.initState();
    _initWebPins();
    _fetchGigs();
    WidgetsBinding.instance.addObserver(this);
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
              'eventType': 'gigPromo',
              'genre': 'Reggae',
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

  void _jumpToCity(MapCityPreset city) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: city.coordinates,
          zoom: city.zoom,
        ),
      ),
    );
    setState(() {
      _currentCameraPosition = CameraPosition(
        target: city.coordinates,
        zoom: city.zoom,
      );
      _selectedCityName = city.name;
      _manuallyClosedTargetId = null;
    });
    if (FeatureFlags.enableMockLiveRehearsals) {
      _audioController?.updateCameraTarget(city.coordinates, immediate: true);
    }
    final appState = Provider.of<AppState>(context, listen: false);
    _evaluateCrosshairTargeting(_getFilteredGigs(appState.currentUserProfile));
  }

  int _getFilterCount(String label, UserProfile? profile) {
    switch (label) {
      case 'All':
        return _allGigs.length +
            (FeatureFlags.enableMockLiveRehearsals ? mockLiveRehearsals.length : 0);
      case 'Music':
        return _allGigs.where((g) => MapEventTypeHelper.getCategory(MapEventTypeHelper.getEventType(g)) == MapCategory.music).length +
            (FeatureFlags.enableMockLiveRehearsals ? mockLiveRehearsals.length : 0);
      case 'Gig Promo':
        return _allGigs.where((g) => MapEventTypeHelper.getCategory(MapEventTypeHelper.getEventType(g)) == MapCategory.gigPromo).length;
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
                    _selectedSubCategory == 'Rehearsal')));

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
    );

    if (bestTarget == null) {
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
    if (kIsWeb && _webPinCache.containsKey(eventType)) {
      return _webPinCache[eventType]!;
    }
    return MapEventTypeHelper.getMarkerIcon(eventType);
  }

  List<SubRequest> _getFilteredGigs(UserProfile? profile) {
    List<SubRequest> list = _allGigs;

    // 1. Primary Category Filter
    if (_selectedMainCategory == 'Music') {
      list = list.where((g) {
        final cat = MapEventTypeHelper.getCategory(MapEventTypeHelper.getEventType(g));
        return cat == MapCategory.music;
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
        final shortLabel = MapEventTypeHelper.getShortLabel(type);
        final fullLabel = MapEventTypeHelper.getLabel(type);
        return shortLabel == _selectedSubCategory ||
            fullLabel == _selectedSubCategory ||
            type.name == _selectedSubCategory ||
            (_selectedSubCategory == 'Substitute' && (shortLabel == 'Subs' || type == MapEventType.subs)) ||
            (_selectedSubCategory == 'Subs' && (shortLabel == 'Substitute' || type == MapEventType.subs)) ||
            (_selectedSubCategory == 'Paid Gigs' && (shortLabel == 'Paid' || type == MapEventType.paid)) ||
            (_selectedSubCategory == 'Paid' && (shortLabel == 'Paid Gigs' || type == MapEventType.paid));
      }).toList();
    }

    // 3. Instrument Search Query Filter (under Sub & Member Search)
    if (_instrumentQuery.trim().isNotEmpty) {
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
                    _selectedSubCategory == 'Rehearsal')));

    final Set<Marker> realLiveMarkers = {};
    if (FeatureFlags.enableRealLiveBroadcasts && _activeRealBroadcasts.isNotEmpty) {
      for (final broadcast in _activeRealBroadcasts) {
        realLiveMarkers.add(
          Marker(
            markerId: MarkerId('real_live_${broadcast.id}'),
            position: LatLng(broadcast.latitude, broadcast.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
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
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta),
        infoWindow: InfoWindow(
          title: rehearsal.bandName,
          snippet: 'LIVE rehearsal · ${rehearsal.city}',
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
    final bandNameController = TextEditingController();
    final roleController = TextEditingController();
    final locationController = TextEditingController(text: 'Stockholm, Sweden');
    final descriptionController = TextEditingController();
    final audioTrackController = TextEditingController();

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
                            'Upload Map Event / Audio',
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
                    'Post a pin to Map View and attach an audio snippet for other musicians and audiences to discover.',
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

                  // Event Type Selector
                  Text('Event Type', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
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
                      labelText: 'Pin Location (Street, City, Country)',
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
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
                  const SizedBox(height: 10),

                  // Audio Snippet / Audio Track (Fritext)
                  Text('Audio Snippet', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: audioTrackController,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Audio Snippet / Audio Track',
                      hintText: 'e.g. audio/bandrep1.mp3 or https://...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1633),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Publish Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () {
                        final band = bandNameController.text.trim().isEmpty ? 'My Band' : bandNameController.text.trim();
                        final title = roleController.text.trim().isEmpty ? selectedType : roleController.text.trim();
                        final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                        
                        final lat = _currentCameraPosition.target.latitude;
                        final lng = _currentCameraPosition.target.longitude;

                        String mappedType = 'gigConcert';
                        if (selectedType == 'Rehearsal') mappedType = 'rehearsal';
                        if (selectedType == 'Jam Session') mappedType = 'jamSession';
                        if (selectedType == 'Recorded Music') mappedType = 'recordedMusic';
                        if (selectedType == 'Gig Promo') mappedType = 'gigPromo';
                        if (selectedType == 'New Member') mappedType = 'newMember';
                        if (selectedType == 'Substitute') mappedType = 'subs';
                        if (selectedType == 'Paid Gigs') mappedType = 'paid';

                        final audioUrl = audioTrackController.text.trim();

                        final newGig = SubRequest(
                          id: newId,
                          subRequestId: newId,
                          bandName: band,
                          role: title,
                          voicePart: title,
                          requestType: selectedType,
                          location: locationController.text.trim().isEmpty ? 'Stockholm, Sweden' : locationController.text.trim(),
                          date: DateTime.now().add(const Duration(days: 3)).toIso8601String(),
                          startTime: '19:00:00',
                          endTime: '22:00:00',
                          description: descriptionController.text.trim().isEmpty ? 'Uploaded via Map View.' : descriptionController.text.trim(),
                          latitude: lat,
                          longitude: lng,
                          isPaid: selectedType == 'Paid Gigs',
                          payAmount: 2000,
                          responses: {},
                          extraFields: {
                            if (audioUrl.isNotEmpty) ...{
                              'audioSnippetUrl': audioUrl,
                              'audioSnippetTitle': '$band Audio Track',
                            },
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

                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Event & audio pin published to Map View!'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Publish to Map',
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
                      _mapController?.setMapStyle(_darkMapStyle);
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
                  // Row 1: Actions Header (Upload Event on left, Refresh and Guide on right)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isVeryCompact = constraints.maxWidth < 360;
                        final bool isCompact = constraints.maxWidth < 430;

                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: constraints.maxWidth),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Upload Event & optional Go Live Button
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: _showUploadEventSheet,
                                      child: Container(
                                        height: 34,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          gradient: AppTheme.primaryGradient,
                                          borderRadius: BorderRadius.circular(17),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.primaryAccent.withOpacity(0.35),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 14),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Upload Event',
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
                                    if (FeatureFlags.enableRealLiveBroadcasts && _currentPublishingBroadcast == null) ...[
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: _openStartLiveBroadcastDialog,
                                        child: Container(
                                          height: 34,
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          decoration: BoxDecoration(
                                            color: AppTheme.dangerRed,
                                            borderRadius: BorderRadius.circular(17),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppTheme.dangerRed.withOpacity(0.35),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.podcasts_rounded, color: Colors.white, size: 14),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Go Live',
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
                                  ],
                                ),

                                // Action Buttons: Refresh & Guide Toggle
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Refresh Button
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
                                      if (isVeryCompact)
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F0C20).withOpacity(0.92),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.5), width: 1.2),
                                          ),
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(Icons.help_outline_rounded, color: AppTheme.primaryAccent, size: 16),
                                            tooltip: 'What is Map View?',
                                            onPressed: () => setState(() => _showGuideBanner = true),
                                          ),
                                        )
                                      else
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
                                                  isCompact ? 'Guide' : 'What is Map View?',
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
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Row 2: Full-width Primary Category Filter Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildMainFilterChip('All', _getFilterCount('All', appState.currentUserProfile)),
                        _buildMainFilterChip('Music', _getFilterCount('Music', appState.currentUserProfile)),
                        _buildMainFilterChip('Gig Promo', _getFilterCount('Gig Promo', appState.currentUserProfile)),
                        _buildMainFilterChip('Sub & Member Search', _getFilterCount('Sub & Member Search', appState.currentUserProfile)),
                        _buildMainFilterChip('This Week', _getFilterCount('This Week', appState.currentUserProfile)),
                      ],
                    ),
                  ),

                  // Row 2: Sub-filter Row (conditional when Music or Sub & Member Search is active)
                  if (_selectedMainCategory == 'Music') ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildSubFilterChip('Gig / Concert', MapEventType.gigConcert),
                          _buildSubFilterChip('Rehearsal', MapEventType.rehearsal),
                          _buildSubFilterChip('Jam Session', MapEventType.jamSession),
                          _buildSubFilterChip('Recorded Music', MapEventType.recordedMusic),
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
                          _buildSubFilterChip('New Member', MapEventType.newMember),
                          _buildSubFilterChip('Substitute', MapEventType.subs),
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

                  // Row 3: Clickable "What is Map View?" Box
                  if (_showGuideBanner) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildWhatIsMapViewBanner(),
                    ),
                  ],
                ],
              ),
            ),

            // Bottom drawer details card for Gigs (with Live Audio bar docked directly above it)
            if (_selectedGig != null)
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
                    _buildBottomCardContent(_selectedGig!, appState),
                  ],
                ),
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

            // When no event card is selected: Pin Legend at bottom-left & Live Audio at bottom-right
            if (_selectedGig == null && _selectedRehearsal == null) ...[
              _buildLegendOverlay(bottomOffset: 76),
              Positioned(
                bottom: 16,
                right: 16,
                child: _buildLiveAudioBar(isDocked: false),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C20).withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryAccent.withOpacity(0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: AppTheme.primaryAccent.withOpacity(0.08),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      color: AppTheme.primaryAccent,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'What is Map View?',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppTheme.primaryAccent,
                    size: 12,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
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
              const SizedBox(height: 6),
              Text(
                'Explore Map View to discover audio snippets from gigs, rehearsals, recordings and gig promos, as well as requests for band members, subs and paid gigs.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFFD4CEEB),
                  height: 1.35,
                ),
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

    return Container(
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
    );
  }

  Widget _buildBottomCardContent(SubRequest gig, AppState appState) {
    final currentUserId = appState.currentUserId;
    final gigReqId = gig.subRequestId ?? gig.id;
    final isCreator = currentUserId != null && (gig.creatorUserId == currentUserId || gig.userId == currentUserId);
    final hasApplied = currentUserId != null && !isCreator && (gig.responses.containsKey(currentUserId) || (gigReqId != null && _appliedGigIds.contains(gigReqId)));
    final eventType = MapEventTypeHelper.getEventType(gig);
    final badgeColor = MapEventTypeHelper.getColor(eventType);
    final badgeLabel = MapEventTypeHelper.getShortLabel(eventType);
    final badgeIcon = MapEventTypeHelper.getIcon(eventType);
    final genre = gig.extraFields['genre']?.toString() ??
        gig.extraFields['Genre']?.toString() ??
        gig.style ??
        '';

    return Container(
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
          // e.g. "Mats Holmquist Stora Stygga - Big Band Contemporary"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  genre.isNotEmpty ? '${gig.bandName ?? "Unknown Band"} - $genre' : (gig.bandName ?? 'Unknown Band'),
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

          // 3. Location (Line 3: e.g. "Fasching, Kungsgatan 44")
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

          // 4. Date & Time (Line 4: either gig/rehearsal time or "Posted Nov 12")
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

          // 5. Fritext-ruta / Description (Line 5: e.g. "Äntligen är de tillbaka...")
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

          // 6. Inline Audio snippet player
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
                          gig.audioSnippetTitle ?? 'Audio Preview Snippet',
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
                          'SNIPPET',
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
                  const SizedBox(height: 6),
                  AudioSnippetPlayer(audioUrl: gig.audioSnippetUrl!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // 7. Buttons Row: "Details" (instead of "View Details") + "Apply"
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/gig-details', arguments: gig);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Details',
                    style: GoogleFonts.inter(
                      color: AppTheme.primaryAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: isCreator
                    ? Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.4)),
                        ),
                        child: Center(
                          child: Text(
                            'Your Request',
                            style: GoogleFonts.inter(
                              color: AppTheme.primaryAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : hasApplied
                    ? Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Center(
                          child: Text(
                            'Applied',
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            if (currentUserId == null) return;
                            try {
                              if ((gig.id ?? '').startsWith('mock_')) {
                                await Future.delayed(const Duration(milliseconds: 300));
                              } else {
                                await appState.firebaseService.addResponseToSubRequestAsync(
                                  gig.subRequestId ?? gig.id!,
                                  currentUserId,
                                );
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Successfully applied for gig!'),
                                    backgroundColor: AppTheme.success,
                                  ),
                                );
                                setState(() {
                                  if (gigReqId != null) _appliedGigIds.add(gigReqId);
                                  gig.responses[currentUserId] = true;
                                });
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to apply: $e'),
                                    backgroundColor: AppTheme.danger,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Apply',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRehearsalBottomCardContent(MockLiveRehearsal rehearsal) {
    final dist = _audioController?.distancesKm[rehearsal.id];
    final distStr = dist != null && dist.isFinite ? '${dist.toStringAsFixed(0)} km away' : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purpleAccent.withOpacity(0.55), width: 1.5),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  rehearsal.bandName,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 20),
                onPressed: () {
                  final closedId = _selectedRehearsal?.id;
                  setState(() {
                    _selectedRehearsal = null;
                    _isAutoSelected = false;
                    _manuallyClosedTargetId = closedId;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.purpleAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sensors_rounded, color: Colors.purpleAccent, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'LIVE REHEARSAL',
                      style: GoogleFonts.inter(
                        color: Colors.purpleAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                rehearsal.genre,
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primaryAccent, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
              const SizedBox(width: 4),
              Text(
                '${rehearsal.city}${distStr.isNotEmpty ? " · $distStr" : ""}',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Broadcasting live rehearsal audio continuously. Move reticle closer to adjust volume.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white70,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainFilterChip(String label, int count) {
    final isSelected = _selectedMainCategory == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedMainCategory = label;
            _selectedSubCategory = null;
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
                label,
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

  Widget _buildInstrumentFilterToggle() {
    final isFiltering = _instrumentQuery.isNotEmpty;
    return GestureDetector(
      onTap: () {
        setState(() {
          _showInstrumentSearch = !_showInstrumentSearch;
          if (!_showInstrumentSearch && _instrumentQuery.isNotEmpty) {
            _instrumentQuery = '';
            _instrumentSearchController.clear();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isFiltering || _showInstrumentSearch
              ? const Color(0xFF84CC16).withOpacity(0.25)
              : const Color(0xFF0F0C20).withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFiltering || _showInstrumentSearch
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
              color: isFiltering || _showInstrumentSearch
                  ? const Color(0xFF84CC16)
                  : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              isFiltering ? 'Instrument: $_instrumentQuery' : 'Search Instrument',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isFiltering || _showInstrumentSearch
                    ? Colors.white
                    : Colors.white70,
              ),
            ),
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



  Widget _buildLegendOverlay({double bottomOffset = 24}) {
    return Positioned(
      bottom: bottomOffset,
      left: 16,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: !_showLegend
            ? GestureDetector(
                key: const ValueKey('legend_button'),
                onTap: () => setState(() => _showLegend = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0C20).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.palette_outlined, color: AppTheme.primaryAccent, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Pin Colors',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                key: const ValueKey('legend_expanded'),
                width: 240,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0C20).withOpacity(0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.4), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
                              const Icon(Icons.palette_outlined, color: AppTheme.primaryAccent, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'PIN EVENT TYPES',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showLegend = false),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Category: Music
                      Text(
                        'MUSIC',
                        style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 4),
                      _buildLegendItem(MapEventType.gigConcert),
                      const SizedBox(height: 5),
                      _buildLegendItem(MapEventType.rehearsal),
                      const SizedBox(height: 5),
                      _buildLegendItem(MapEventType.jamSession),
                      const SizedBox(height: 5),
                      _buildLegendItem(MapEventType.recordedMusic),
                      const SizedBox(height: 10),

                      // Category: Gig Promo
                      Text(
                        'GIG PROMO',
                        style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFA855F7), letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 4),
                      _buildLegendItem(MapEventType.gigPromo),
                      const SizedBox(height: 10),

                      // Category: Sub & Member Search
                      Text(
                        'SUB & MEMBER SEARCH',
                        style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF84CC16), letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 4),
                      _buildLegendItem(MapEventType.newMember),
                      const SizedBox(height: 5),
                      _buildLegendItem(MapEventType.subs),
                      const SizedBox(height: 5),
                      _buildLegendItem(MapEventType.paid),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLegendItem(MapEventType type) {
    final color = MapEventTypeHelper.getColor(type);
    final label = MapEventTypeHelper.getLabel(type);
    final icon = MapEventTypeHelper.getIcon(type);

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Icon(icon, color: Colors.black.withOpacity(0.65), size: 9),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

