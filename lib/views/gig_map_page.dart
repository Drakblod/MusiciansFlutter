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
import '../services/mock_rehearsal_audio_controller.dart';

class GigMapPage extends StatefulWidget {
  const GigMapPage({super.key});

  @override
  State<GigMapPage> createState() => _GigMapPageState();
}

class _GigMapPageState extends State<GigMapPage> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  List<SubRequest> _allGigs = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  SubRequest? _selectedGig;

  // Prototype Mock Live Rehearsal Audio State
  MockRehearsalAudioController? _audioController;
  MockLiveRehearsal? _selectedRehearsal;

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

  @override
  void initState() {
    super.initState();
    _fetchGigs();
    if (FeatureFlags.enableMockLiveRehearsals) {
      WidgetsBinding.instance.addObserver(this);
      _audioController = MockRehearsalAudioController();
      _audioController!.initialize();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!FeatureFlags.enableMockLiveRehearsals || _audioController == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _audioController!.pauseAudio();
    } else if (state == AppLifecycleState.resumed) {
      _audioController!.resumeAudio();
    }
  }

  @override
  void dispose() {
    if (FeatureFlags.enableMockLiveRehearsals) {
      WidgetsBinding.instance.removeObserver(this);
      _audioController?.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchGigs() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final rawGigs = await appState.firebaseService.getAllSubRequestsAsync();
      
      // Filter out gigs that have coordinates
      final dbGigsWithCoords = rawGigs.where((g) => g.latitude != null && g.longitude != null).toList();

      if (dbGigsWithCoords.isEmpty) {
        // Fallback mock markers inside Sweden
        _allGigs = [
          SubRequest(
            id: 'mock_1',
            subRequestId: 'mock_1',
            voicePart: 'Electric Guitar',
            role: 'Rock Guitarist Needed',
            bandName: 'The Midnight Storm',
            location: 'Stockholm, Sweden',
            date: DateTime.now().add(const Duration(days: 3)).toIso8601String(),
            startTime: '19:00:00',
            endTime: '22:00:00',
            description: 'Looking for a solid rock guitarist to fill in for a rehearsal and possibly a weekend gig.',
            isPaid: true,
            latitude: 59.3293,
            longitude: 18.0686,
            responses: {},
          ),
          SubRequest(
            id: 'mock_2',
            subRequestId: 'mock_2',
            voicePart: 'Vocalist',
            role: 'Jazz Vocalist',
            bandName: 'Cool Autumn Quartet',
            location: 'Gothenburg, Sweden',
            date: DateTime.now().add(const Duration(days: 5)).toIso8601String(),
            startTime: '20:00:00',
            endTime: '23:00:00',
            description: 'Need a guest vocalist for standard jazz tunes at a local club show.',
            isPaid: true,
            latitude: 57.7089,
            longitude: 11.9746,
            responses: {},
          ),
          SubRequest(
            id: 'mock_3',
            subRequestId: 'mock_3',
            voicePart: 'Cello',
            role: 'Classical Cello Substitute',
            bandName: 'Uppsala Sinfonietta',
            location: 'Uppsala, Sweden',
            date: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
            startTime: '18:00:00',
            endTime: '21:00:00',
            description: 'Substitute required for our weekly orchestra rehearsal. Sheet music provided.',
            isPaid: false,
            latitude: 59.8586,
            longitude: 17.6389,
            responses: {},
          ),
          SubRequest(
            id: 'mock_4',
            subRequestId: 'mock_4',
            voicePart: 'Drums',
            role: 'Drummer for Pop Band',
            bandName: 'Vibe Check',
            location: 'Malmö, Sweden',
            date: DateTime.now().add(const Duration(days: 6)).toIso8601String(),
            startTime: '17:30:00',
            endTime: '20:30:00',
            description: 'Our regular drummer has a family emergency. Energetic pop drumming style required.',
            isPaid: true,
            latitude: 55.6050,
            longitude: 13.0038,
            responses: {},
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
      }
    }
  }

  BitmapDescriptor _getMarkerColor(String? instrument) {
    if (instrument == null) return BitmapDescriptor.defaultMarker;
    final inst = instrument.toLowerCase();
    if (inst.contains('vocal') || inst.contains('singer') || inst.contains('choir') || inst.contains('voice') || inst.contains('soprano') && !inst.contains('recorder') && !inst.contains('sax')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    } else if (inst.contains('drum') || inst.contains('percussion') || inst.contains('steel pan')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    } else if (inst.contains('guitar') || inst.contains('bass') || inst.contains('harp') || inst.contains('violin') || inst.contains('cello') || inst.contains('viola') || inst.contains('contrabass')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    } else if (inst.contains('piano') || inst.contains('keyboard') || inst.contains('organ') || inst.contains('harpsichord') || inst.contains('synth')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    } else if (inst.contains('trumpet') || inst.contains('trombone') || inst.contains('horn') || inst.contains('tuba') || inst.contains('sax') || inst.contains('flute') || inst.contains('clarinet') || inst.contains('oboe') || inst.contains('bassoon') || inst.contains('recorder') || inst.contains('piccolo') || inst.contains('euphonium')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
  }

  List<SubRequest> _getFilteredGigs(UserProfile? profile) {
    if (_selectedFilter == 'All') {
      return _allGigs;
    } else if (_selectedFilter == 'My Instruments') {
      final userInstruments = profile?.instruments ?? [];
      if (userInstruments.isEmpty) return [];
      return _allGigs.where((gig) {
        if (gig.voicePart == null) return false;
        final vpLower = gig.voicePart!.toLowerCase();
        return userInstruments.any((inst) {
          final instLower = inst.toLowerCase();
          return instLower == vpLower || vpLower.contains(instLower) || instLower.contains(vpLower);
        });
      }).toList();
    } else if (_selectedFilter == 'Paid Gigs') {
      return _allGigs.where((gig) => gig.isPaid).toList();
    } else if (_selectedFilter == 'This Week') {
      final now = DateTime.now();
      final oneWeekLater = now.add(const Duration(days: 7));
      return _allGigs.where((gig) {
        if (gig.date == null) return false;
        final d = DateTime.tryParse(gig.date!);
        if (d == null) return false;
        return d.isAfter(now.subtract(const Duration(days: 1))) && d.isBefore(oneWeekLater);
      }).toList();
    }
    return _allGigs;
  }

  Set<Marker> _buildMarkers(List<SubRequest> filteredGigs) {
    final gigMarkers = filteredGigs.map((gig) {
      return Marker(
        markerId: MarkerId(gig.id ?? gig.subRequestId ?? UniqueKey().toString()),
        position: LatLng(gig.latitude!, gig.longitude!),
        icon: _getMarkerColor(gig.voicePart),
        onTap: () {
          setState(() {
            _selectedGig = gig;
            _selectedRehearsal = null;
          });
        },
      );
    }).toSet();

    if (!FeatureFlags.enableMockLiveRehearsals) {
      return gigMarkers;
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
          });
        },
      );
    }).toSet();

    return {...gigMarkers, ...rehearsalMarkers};
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final filteredGigs = _getFilteredGigs(appState.currentUserProfile);
    final markers = _buildMarkers(filteredGigs);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Discovery Map',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.backgroundStart,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _fetchGigs,
          ),
        ],
      ),
      body: Container(
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
                      if (FeatureFlags.enableMockLiveRehearsals) {
                        _audioController?.updateCameraTarget(position.target);
                      }
                    },
                    onCameraIdle: () {
                      if (FeatureFlags.enableMockLiveRehearsals && _mapController != null) {
                        _mapController?.getVisibleRegion();
                      }
                    },
                    markers: markers,
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    onTap: (_) {
                      // Deselect gig and rehearsal on tapping map empty space
                      setState(() {
                        _selectedGig = null;
                        _selectedRehearsal = null;
                      });
                    },
                  ),

            // Center Map Crosshair Overlay
            Center(
              child: IgnorePointer(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryAccent.withOpacity(0.65),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryAccent.withOpacity(0.25),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Center dot
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      // Horizontal reticle line
                      Container(
                        width: 18,
                        height: 1.5,
                        color: AppTheme.primaryAccent.withOpacity(0.75),
                      ),
                      // Vertical reticle line
                      Container(
                        width: 1.5,
                        height: 18,
                        color: AppTheme.primaryAccent.withOpacity(0.75),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Top Filter Row
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterChip('All'),
                    _buildFilterChip('My Instruments'),
                    _buildFilterChip('Paid Gigs'),
                    _buildFilterChip('This Week'),
                  ],
                ),
              ),
            ),

            // Audio Controls Overlay
            _buildAudioControlsOverlay(),

            // Bottom drawer details card for Gigs
            if (_selectedGig != null) _buildBottomCard(_selectedGig!, appState),

            // Bottom drawer details card for Mock Live Rehearsals
            if (_selectedRehearsal != null) _buildRehearsalBottomCard(_selectedRehearsal!),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioControlsOverlay() {
    if (!FeatureFlags.enableMockLiveRehearsals || _audioController == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 68,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _audioController!.webAutoplayBlockedNotifier,
            builder: (context, isBlocked, _) {
              if (!isBlocked) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.warning,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.volume_up_rounded, color: Colors.black, size: 16),
                  label: Text(
                    'Enable rehearsal audio',
                    style: GoogleFonts.inter(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    _audioController?.enableWebAudio();
                  },
                ),
              );
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _audioController!.isMutedNotifier,
            builder: (context, isMuted, _) {
              return Tooltip(
                message: isMuted ? 'Unmute Live Rehearsals' : 'Mute Live Rehearsals',
                child: GestureDetector(
                  onTap: () {
                    _audioController?.toggleMute();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isMuted ? AppTheme.danger : AppTheme.primaryAccent,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: isMuted ? AppTheme.danger : AppTheme.primaryAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isMuted ? 'Muted' : 'Live Audio',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRehearsalBottomCard(MockLiveRehearsal rehearsal) {
    final dist = _audioController?.distancesKm[rehearsal.id];
    final distStr = dist != null && dist.isFinite ? '${dist.toStringAsFixed(0)} km away' : '';

    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.purpleAccent.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sensors_rounded, color: Colors.purpleAccent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE REHEARSAL',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 20),
                  onPressed: () {
                    setState(() {
                      _selectedRehearsal = null;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              rehearsal.bandName,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${rehearsal.city}${distStr.isNotEmpty ? " · $distStr" : ""}',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.music_note_rounded, color: AppTheme.primaryAccent, size: 14),
                const SizedBox(width: 4),
                Text(
                  rehearsal.genre,
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primaryAccent),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Broadcasting live rehearsal audio continuously for prototype testing.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white70,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedFilter = label;
            _selectedGig = null;
            _selectedRehearsal = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: isSelected ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCard(SubRequest gig, AppState appState) {
    final date = gig.date != null ? DateTime.tryParse(gig.date!) ?? DateTime.now() : DateTime.now();
    final formattedDate = DateFormat('MMM dd, yyyy').format(date);
    final currentUserId = appState.currentUserId;
    final hasApplied = currentUserId != null && gig.responses.containsKey(currentUserId);
    
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Role + Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    gig.role ?? gig.voicePart ?? 'Substitute Request',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedGig = null;
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
            const SizedBox(height: 4),
            Text(
              gig.bandName ?? 'Unknown Band',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.primaryAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            
            // Info Row (Date/Time, Location)
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '$formattedDate | ${gig.startTime ?? "18:00"} - ${gig.endTime ?? "21:00"}',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    gig.location ?? 'Stockholm, Sweden',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Paid indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: gig.isPaid ? AppTheme.primaryAccent.withOpacity(0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    gig.isPaid ? 'Paid' : 'Unpaid',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: gig.isPaid ? AppTheme.primaryAccent : AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Buttons Row
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
                      'View Details',
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
                  child: hasApplied
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
                                  // Simulated apply for fallback mock gig
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
            )
          ],
        ),
      ),
    );
  }
}
