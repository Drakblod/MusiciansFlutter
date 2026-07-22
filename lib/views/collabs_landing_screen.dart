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

class CollabsLandingScreen extends StatefulWidget {
  const CollabsLandingScreen({super.key});

  @override
  State<CollabsLandingScreen> createState() => _CollabsLandingScreenState();
}

class _CollabsLandingScreenState extends State<CollabsLandingScreen> {
  final _messageController = TextEditingController();
  final _locationController = TextEditingController();

  String _selectedMainCategory = 'Songwriters/Producers';
  String _selectedSubcategory = 'Songwriter';

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 4));
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  bool _isPaid = true;
  bool _isSubmitting = false;

  bool _showFavoritesList = false;
  List<UserProfile> _favorites = [];
  List<UserProfile> _filteredFavorites = [];
  Map<String, bool> _selectedFavorites = {};
  bool _isLoadingFavorites = false;

  List<String> _getSubcategories() {
    if (_selectedMainCategory == 'Songwriters/Producers') {
      return ['Songwriter', 'Producer', 'Other'];
    } else if (_selectedMainCategory == 'Studios/Engineers') {
      return ['Studio', 'Engineer', 'Other'];
    } else {
      return ['Create Session', 'Find Session'];
    }
  }

  void _updateFilteredFavorites() {
    final subLower = _selectedSubcategory.toLowerCase();
    _filteredFavorites = _favorites.where((m) {
      if (subLower == 'songwriter') {
        return m.collabRoles.contains('songwriter') ||
            (m.userType?.toLowerCase().contains('songwriter') ?? false);
      } else if (subLower == 'producer') {
        return m.collabRoles.contains('producer') ||
            (m.userType?.toLowerCase().contains('producer') ?? false) ||
            m.instruments.any((i) => i.toLowerCase().contains('producer'));
      } else if (subLower == 'engineer') {
        return m.collabRoles.contains('engineer') ||
            (m.userType?.toLowerCase().contains('engineer') ?? false) ||
            (m.userType?.toLowerCase().contains('mix') ?? false) ||
            (m.userType?.toLowerCase().contains('mastering') ?? false);
      } else if (subLower == 'studio') {
        return m.userType?.toLowerCase().contains('studio') ?? false;
      }
      // 'Other' or 'Sessions' matches any favorites
      return true;
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
      debugPrint("Error parsing time: $e");
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
        debugPrint("Error loading band details: $e");
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
      _loadFavorites();
    });
  }

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
              content: Text('You have no favorited collaborators. Go to the Browse tab to add favorites.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          setState(() => _isSubmitting = false);
          return;
        }
        if (_filteredFavorites.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('None of your favorites match $_selectedSubcategory. Add matching favorites or use Send to All.'),
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
              content: Text('Please check at least one favorite collaborator to send the request to.'),
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

      // Create model (Marked as collab request)
      final request = SubRequest(
        voicePart: _selectedSubcategory,
        location: resolvedLoc,
        startTime: '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00',
        endTime: '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00',
        description: _messageController.text,
        date: _selectedDate.toIso8601String(),
        role: 'Collab', // Mark as Collab
        isPaid: _isPaid,
        bandName: appState.activeBandName ?? 'Collab Project',
        rehearsalDayOfWeek: DateFormat('EEEE').format(_selectedDate),
        targetUserIds: targetUserIds,
      );

      await appState.firebaseService.saveSubRequestAsync(request);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Collaboration request posted successfully!'),
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
                'Choose which band/project you are posting this request for.',
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
                          Navigator.pop(context);
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryAccent.withOpacity(0.12)
                                : AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryAccent
                                  : const Color(0xFF231F45),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                bandName,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, color: AppTheme.primaryAccent, size: 20),
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
        title: 'Collabs',
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COLLABS',
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
                    Navigator.pop(context);
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
                    Navigator.pop(context);
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
                      appState.activeBandName ?? "Collab Project",
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

            // Collab Main Category selector
            Text(
              'COLLABORATION AREA',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  ChoiceChip(
                    label: const Text('Songwriters/Producers'),
                    selected: _selectedMainCategory == 'Songwriters/Producers',
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedMainCategory = 'Songwriters/Producers';
                          _selectedSubcategory = 'Songwriter';
                          _updateFilteredFavorites();
                        });
                      }
                    },
                    selectedColor: AppTheme.primaryAccent,
                    backgroundColor: AppTheme.inputBackground,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: _selectedMainCategory == 'Songwriters/Producers' ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Studios/Engineers'),
                    selected: _selectedMainCategory == 'Studios/Engineers',
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedMainCategory = 'Studios/Engineers';
                          _selectedSubcategory = 'Studio';
                          _updateFilteredFavorites();
                        });
                      }
                    },
                    selectedColor: AppTheme.primaryAccent,
                    backgroundColor: AppTheme.inputBackground,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: _selectedMainCategory == 'Studios/Engineers' ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Sessions'),
                    selected: _selectedMainCategory == 'Sessions',
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedMainCategory = 'Sessions';
                          _selectedSubcategory = 'Create Session';
                          _updateFilteredFavorites();
                        });
                      }
                    },
                    selectedColor: AppTheme.primaryAccent,
                    backgroundColor: AppTheme.inputBackground,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: _selectedMainCategory == 'Sessions' ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Collab Role / Subcategory selector
            Text(
              'SKILLS/TALENTS',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: _getSubcategories().map((sub) {
                  final isSelected = _selectedSubcategory == sub;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(sub),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedSubcategory = sub;
                            _updateFilteredFavorites();
                          });
                        }
                      },
                      selectedColor: AppTheme.primaryAccent.withOpacity(0.4),
                      backgroundColor: AppTheme.cardBackground,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: Colors.white,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Collaboration Details Card (Free Text Only)
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
                        'Collaboration Details',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
                      hintText: "I'm looking for a co-writer to compose on the weekends...",
                      counterStyle: TextStyle(color: AppTheme.textSecondary),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF2E2A4E), height: 32),

            // Action Buttons Row: FAVORITES LIST & SEND TO ALL
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
                          'You have no favorited collaborators. Go to the Browse tab to add favorites.',
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
                          'None of your favorites match $_selectedSubcategory. Add matching favorites or use Send to All.',
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
