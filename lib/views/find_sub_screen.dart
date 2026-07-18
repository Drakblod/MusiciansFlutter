import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../models/user_profile.dart';
import '../models/band.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class FindSubScreen extends StatefulWidget {
  final String? eventId;
  final String? bandId;

  const FindSubScreen({super.key, this.eventId, this.bandId});

  @override
  State<FindSubScreen> createState() => _FindSubScreenState();
}

class _FindSubScreenState extends State<FindSubScreen> {
  final _messageController = TextEditingController();
  final _locationController = TextEditingController();

  String _selectedInstrument = 'Electric Guitar';
  String _selectedRole = 'Substitute';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 4));
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  bool _isPaid = true;
  bool _isSubmitting = false;

  bool _sendToFavoritesOnly = false;
  bool _showFavoritesList = false;
  List<UserProfile> _favorites = [];
  List<UserProfile> _filteredFavorites = [];
  Map<String, bool> _selectedFavorites = {};
  bool _isLoadingFavorites = false;

  void _updateFilteredFavorites() {
    final selectedInstrumentLower = _selectedInstrument.toLowerCase();
    _filteredFavorites = _favorites.where((m) {
      final matchesInstrument = (m.userType?.toLowerCase() == selectedInstrumentLower) ||
          m.instruments.any((i) => i.toLowerCase() == selectedInstrumentLower);
      return matchesInstrument;
    }).toList();
    
    _selectedFavorites.clear();
    for (final f in _filteredFavorites) {
      if (f.userId != null) {
        _selectedFavorites[f.userId!] = true;
      }
    }
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _isLoadingFavorites = true;
    });
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final favIds = await appState.firebaseService.getFavoriteUserIdsAsync();
      
      final List<UserProfile> loaded = [];
      for (final id in favIds) {
        final profile = await appState.firebaseService.getUserProfileAsync(id);
        if (profile != null) {
          loaded.add(profile);
        }
      }
      
      setState(() {
        _favorites = loaded;
        _updateFilteredFavorites();
      });
    } catch (e) {
      debugPrint("Error loading favorites: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFavorites = false;
        });
      }
    }
  }

  TimeOfDay _parseTime(String? timeStr, TimeOfDay defaultTime) {
    if (timeStr == null || timeStr.isEmpty) return defaultTime;
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      debugPrint("Error parsing time string $timeStr: $e");
    }
    return defaultTime;
  }

  Future<void> _loadBandInfo() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = appState.activeBandId;
    if (bandId != null) {
      try {
        final Band? band = await appState.firebaseService.getBandInfoAsync(bandId);
        if (band != null && mounted) {
          setState(() {
            if (band.rehearsalLocation != null && band.rehearsalLocation!.isNotEmpty) {
              _locationController.text = band.rehearsalLocation!;
            } else if (band.location != null && band.location!.isNotEmpty) {
              _locationController.text = band.location!;
            }

            if (band.rehearsalStartTime != null && band.rehearsalStartTime!.isNotEmpty) {
              _startTime = _parseTime(band.rehearsalStartTime, _startTime);
            }
            if (band.rehearsalEndTime != null && band.rehearsalEndTime!.isNotEmpty) {
              _endTime = _parseTime(band.rehearsalEndTime, _endTime);
            }
          });
        }
      } catch (e) {
        debugPrint("Error loading band info: $e");
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.currentUserProfile?.location != null) {
        _locationController.text = appState.currentUserProfile!.location!;
      } else {
        _locationController.text = 'Stockholm, Sweden';
      }
      _loadBandInfo();
      _loadFavorites().then((_) {
        _loadEventDetails();
      });
    });
  }

  void _loadEventDetails() async {
    if (widget.eventId == null || widget.bandId == null) return;
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final event = await appState.firebaseService.getBandEventOnceAsync(widget.bandId!, widget.eventId!);
      if (event != null && mounted) {
        setState(() {
          _locationController.text = event.location;
          final start = DateTime.tryParse(event.startDateTime) ?? DateTime.now();
          _selectedDate = start;
          _startTime = TimeOfDay.fromDateTime(start);
          final end = DateTime.tryParse(event.endDateTime) ?? start.add(const Duration(hours: 2));
          _endTime = TimeOfDay.fromDateTime(end);
          _messageController.text = "Need substitute for event: ${event.title}\nDescription: ${event.description}";
          
          final lowerTitle = event.title.toLowerCase();
          for (final inst in _instruments) {
            if (lowerTitle.contains(inst.toLowerCase())) {
              _selectedInstrument = inst;
              break;
            }
          }
          
          _updateFilteredFavorites();
        });
      }
    } catch (e) {
      debugPrint("Error loading event context: $e");
    }
  }

  Map<String, double>? _resolveCoordinates(String location) {
    final loc = location.toLowerCase();
    if (loc.contains('stockholm')) {
      return {'latitude': 59.3293, 'longitude': 18.0686};
    } else if (loc.contains('gothenburg') || loc.contains('göteborg')) {
      return {'latitude': 57.7089, 'longitude': 11.9746};
    } else if (loc.contains('malmö') || loc.contains('malmo')) {
      return {'latitude': 55.6050, 'longitude': 13.0038};
    } else if (loc.contains('uppsala')) {
      return {'latitude': 59.8586, 'longitude': 17.6389};
    }
    return null;
  }

  final List<String> _instruments = [
    "BANDLEADER",
    "PRODUCER",
    "Vocalist",
    "Recorder",
    "Flute",
    "Oboe",
    "Clarinet",
    "Bassoon",
    "Soprano Sax",
    "Alto Sax",
    "Tenor Sax",
    "Bari Sax",
    "Trumpet",
    "Cornet",
    "Trombone",
    "French Horn",
    "Euphonium",
    "Tuba",
    "Violin",
    "Viola",
    "Cello",
    "Contrabass",
    "Acoustic Guitar",
    "Electric Guitar",
    "Electric Bass",
    "Harp",
    "Piano",
    "Keyboard/Synth",
    "Harpsichord",
    "Organ (Hammond)",
    "Drums",
    "Latin Percussion",
    "Classical Percussion",
    "Soprano Recorder",
    "Alto Recorder",
    "Tenor Recorder",
    "Bass Recorder",
    "Piccolo Flute",
    "Alto Flute",
    "Bass Flute",
    "English Horn",
    "Eb Clarinet",
    "Alto Clarinet",
    "Bass Clarinet",
    "Contra Bassoon",
    "Piccolo Trumpet",
    "Alto Trombone",
    "Viola da Gamba",
    "Steel Guitar",
    "Steel Pan"
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: AppTheme.cardBackground,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              surface: AppTheme.cardBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _submitRequest({required bool sendToAll}) async {
    setState(() => _isSubmitting = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final profile = appState.currentUserProfile;

      List<String>? targetUserIds;

      if (!sendToAll) {
        if (_favorites.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have no favorited musicians. Go to the Browse tab to add favorites.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          setState(() => _isSubmitting = false);
          return;
        }
        if (_filteredFavorites.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('None of your favorites play $_selectedInstrument. Add matching favorites or use Send to All.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          setState(() => _isSubmitting = false);
          return;
        }
        final checkedUserIds = _selectedFavorites.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList();
        if (checkedUserIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please check at least one favorite musician to send the request to.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          setState(() => _isSubmitting = false);
          return;
        }
        targetUserIds = checkedUserIds;
      }

      final resolvedLoc = _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : (profile?.location ?? 'Stockholm, Sweden');
      
      final coords = _resolveCoordinates(resolvedLoc);

      // Create model
      final request = SubRequest(
        voicePart: _selectedInstrument,
        location: resolvedLoc,
        startTime: '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00',
        endTime: '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00',
        description: _messageController.text,
        date: _selectedDate.toIso8601String(),
        role: _selectedRole,
        isPaid: _isPaid,
        bandName: appState.activeBandName ?? 'Freelance Gig',
        rehearsalDayOfWeek: DateFormat('EEEE').format(_selectedDate),
        latitude: coords?['latitude'],
        longitude: coords?['longitude'],
        targetUserIds: targetUserIds,
        eventId: widget.eventId,
        bandId: widget.bandId,
      );

      final subRequestId = await appState.firebaseService.saveSubRequestAsync(request);

      if (widget.eventId != null && widget.bandId != null && subRequestId != null) {
        final targets = request.targetUserIds;
        if (targets != null && targets.isNotEmpty) {
          await appState.firebaseService.addExternalInviteesToEventAsync(
            widget.bandId!,
            widget.eventId!,
            targets,
            subRequestId: subRequestId,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request posted successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post request: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showBandSelectorBottomSheet(
    BuildContext context,
    AppState appState,
    Map<String, String> bands,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C22).withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'SELECT A BAND',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose which band you are posting this request for.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: bands.length,
                  itemBuilder: (context, index) {
                    final bandId = bands.keys.elementAt(index);
                    final bandName = bands[bandId]!;
                    final isSelected = appState.activeBandId == bandId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedTapDetector(
                        onTap: () {
                          appState.selectBand(bandId, bandName);
                          Navigator.pop(context); // Close bottom sheet
                          setState(() {}); // Refresh current screen state to show selected band
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryAccent.withOpacity(0.12)
                                : AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryAccent
                                  : const Color(0xFF2E2A4E),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryAccent.withOpacity(0.2)
                                      : Colors.white.withOpacity(0.05),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.groups_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  bandName,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.primaryAccent,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final formatTime = (TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Find a Musician',
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FIND A MUSICIAN/VOCALIST',
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final userId = appState.currentUserId;
                if (userId == null) return;

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                  ),
                );

                try {
                  final bands = await appState.firebaseService.getUserBandsAsync(userId);
                  if (context.mounted) {
                    Navigator.pop(context); // Dismiss loader
                  }

                  if (bands.isNotEmpty) {
                    if (context.mounted) {
                      _showBandSelectorBottomSheet(context, appState, bands);
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You are not a member of any bands yet.'),
                          backgroundColor: AppTheme.danger,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // Dismiss loader
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.groups_rounded, color: AppTheme.primaryAccent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      appState.activeBandName ?? "Freelance Gig",
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit_rounded, color: AppTheme.primaryAccent, size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Instrument Picker Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.inputBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedInstrument,
                  isExpanded: true,
                  dropdownColor: AppTheme.cardBackground,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                  items: _instruments.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedInstrument = newValue;
                        if (_showFavoritesList) {
                          _updateFilteredFavorites();
                        }
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Gig/Rehearsal Details card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF231F45), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryAccent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Gig/Rehearsal Details',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Location / Address',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      hintText: 'Location (e.g. Stockholm, Gothenburg, Malmö)',
                      prefixIcon: Icon(Icons.location_on_rounded, color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Date',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),

                  // Date Button Selector
                  AnimatedTapDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.inputBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('dd MMMM yyyy').format(_selectedDate),
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Time fields row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Time',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            AnimatedTapDetector(
                              onTap: () => _pickTime(true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppTheme.inputBackground,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                                ),
                                child: Center(
                                  child: Text(
                                    formatTime(_startTime),
                                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Time',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            AnimatedTapDetector(
                              onTap: () => _pickTime(false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppTheme.inputBackground,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                                ),
                                child: Center(
                                  child: Text(
                                    formatTime(_endTime),
                                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Optional Message Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF231F45), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primaryAccent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'More details..',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(optional)',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    maxLength: 200,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'More details..',
                      counterStyle: TextStyle(color: AppTheme.textSecondary),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Paid switch row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Is this a paid gig?',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                Switch(
                  value: _isPaid,
                  onChanged: (val) {
                    setState(() {
                      _isPaid = val;
                    });
                  },
                  activeColor: AppTheme.primaryAccent,
                  activeTrackColor: AppTheme.primaryAccent.withOpacity(0.3),
                  inactiveThumbColor: AppTheme.textSecondary,
                  inactiveTrackColor: Colors.grey.withOpacity(0.2),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF2E2A4E), height: 32),

            // Side-by-side Action Buttons: FAVORITES LIST & SEND TO ALL
            Row(
              children: [
                Expanded(
                  child: AnimatedTapDetector(
                    onTap: () {
                      setState(() {
                        _showFavoritesList = !_showFavoritesList;
                      });
                      if (_showFavoritesList && _favorites.isEmpty) {
                        _loadFavorites();
                      }
                    },
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _showFavoritesList
                            ? AppTheme.primaryAccent.withOpacity(0.15)
                            : AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _showFavoritesList
                              ? AppTheme.primaryAccent
                              : const Color(0xFF2E2A4E),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'FAVORITES LIST',
                          style: GoogleFonts.inter(
                            color: _showFavoritesList ? Colors.white : AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _isSubmitting
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                      : AnimatedTapDetector(
                          onTap: () => _submitRequest(sendToAll: true),
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryAccent.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                )
                              ],
                            ),
                            child: Center(
                              child: Text(
                                'SEND TO ALL',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),

            if (_showFavoritesList) ...[
              const SizedBox(height: 24),
              if (_isLoadingFavorites)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                  ),
                )
              else if (_favorites.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You have no favorited musicians. Go to the Browse tab to add favorites.',
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_filteredFavorites.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppTheme.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'None of your favorites play $_selectedInstrument. Add matching favorites or use Send to All.',
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Text(
                  'SELECT RECIPIENTS',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filteredFavorites.length,
                  itemBuilder: (context, index) {
                    final musician = _filteredFavorites[index];
                    final userId = musician.userId ?? '';
                    final isChecked = _selectedFavorites[userId] ?? false;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isChecked ? AppTheme.primaryAccent.withOpacity(0.5) : const Color(0xFF231F45),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isChecked,
                            onChanged: (val) {
                              setState(() {
                                _selectedFavorites[userId] = val ?? false;
                              });
                            },
                            activeColor: AppTheme.primaryAccent,
                            checkColor: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                            backgroundImage: musician.profilePictureUrl != null &&
                                    musician.profilePictureUrl!.isNotEmpty
                                ? NetworkImage(musician.profilePictureUrl!)
                                : null,
                            child: musician.profilePictureUrl == null ||
                                    musician.profilePictureUrl!.isEmpty
                                ? Text(
                                    (musician.displayName ?? 'U').substring(0, 1).toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  musician.displayName ?? 'Unknown',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                if (musician.location != null)
                                  Text(
                                    musician.location!,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _isSubmitting
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                    : AnimatedTapDetector(
                        onTap: () => _submitRequest(sendToAll: false),
                        child: Container(
                          height: 52,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryAccent.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Send to Favorites Only',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
              ],
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

