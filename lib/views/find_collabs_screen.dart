import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../models/sub_request.dart';
import '../models/band.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';

class FindCollabsScreen extends StatefulWidget {
  final String? role;

  const FindCollabsScreen({super.key, this.role});

  @override
  State<FindCollabsScreen> createState() => _FindCollabsScreenState();
}

class _FindCollabsScreenState extends State<FindCollabsScreen> {
  final _detailsController = TextEditingController();
  final _locationController = TextEditingController();

  // Major Category: 'Songwriters/Producers', 'Studios/Engineers', 'Sessions'
  String _selectedCategory = 'Songwriters/Producers';
  // Sub Role: depends on category
  String _selectedSubRole = 'Songwriters';

  // Selected Collaboration Area / Skills
  List<String> _selectedCollabAreas = [];

  bool _isSubmitting = false;

  // Favorites Selection State
  bool _sendToFavoritesOnly = false;
  bool _showFavoritesList = false;
  List<UserProfile> _favorites = [];
  List<UserProfile> _filteredFavorites = [];
  Map<String, bool> _selectedFavorites = {};
  bool _isLoadingFavorites = false;

  // Master Skills & Talents Category Map
  static final Map<String, List<String>> _allSkillsCategoryMap = {
    '🎧 Roles / Production': [
      'BANDLEADER',
      'SONGWRITER',
      'PRODUCER',
      'COMPOSER',
      'LYRICIST',
      'BEATMAKER',
      'STUDIO/ENGINEER, etc',
    ],
    '🎷 Woodwinds': [
      'Recorder',
      'Flute',
      'Oboe',
      'Clarinet',
      'Bassoon',
      'Soprano Sax',
      'Alto Sax',
      'Tenor Sax',
      'Bari Sax',
    ],
    '🎺 Brass': [
      'Trumpet',
      'Cornet',
      'Trombone',
      'French Horn',
      'Euphonium',
      'Tuba',
    ],
    '🎻 Strings': [
      'Violin',
      'Viola',
      'Cello',
      'Contrabass',
      'Acoustic Guitar',
      'Electric Guitar',
      'Electric Bass',
      'Harp',
    ],
    '🎹 Keyboards': [
      'Piano',
      'Keyboard/Synth',
      'Harpsichord',
      'Organ (Hammond)',
    ],
    '🥁 Percussion': [
      'Drums',
      'Latin Percussion (congas, timbales, etc)',
      'Classical Percussion (timpani, cymbals, etc)',
    ],
    '🗣️ Voices (Choir)': [
      'Soprano',
      'Alto',
      'Tenor',
      'Baritone',
      'Bass',
    ],
    '🎭 Miscellaneous Voices (Classical, Choir)': [
      'Mezzo Soprano',
      'Contralto',
      'Counter Tenor',
    ],
    '🎤 Voices (Popular Music)': [
      'Male Lead Vocals',
      'Female Lead vocals',
      'Male Backing vocals',
      'Female Backing vocals',
    ],
    '🪈 Miscellaneous Instruments': [
      'Soprano Recorder',
      'Alto Recorder',
      'Tenor Recorder',
      'Bass Recorder',
      'Piccolo Flute',
      'Alto Flute',
      'Bass Flute',
      'English Horn',
      'Eb Clarinet',
      'Alto Clarinet',
      'Bass Clarinet',
      'Contra Bassoon',
      'Piccolo Trumpet',
      'Alto Trombone',
      'Viola da Gamba',
      'Steel Guitar',
      'Steel Pan',
    ],
  };

  @override
  void initState() {
    super.initState();
    if (widget.role != null && widget.role!.isNotEmpty) {
      final rLower = widget.role!.toLowerCase();
      if (rLower.contains('studio') || rLower.contains('engineer')) {
        _selectedCategory = 'Studios/Engineers';
        _selectedSubRole = 'Studios';
        _selectedCollabAreas = ['Studio'];
      } else if (rLower.contains('session')) {
        _selectedCategory = 'Sessions';
        _selectedSubRole = 'Create Session';
        _selectedCollabAreas = ['Session Musician'];
      }
    }

    _loadFavorites();
    _initDefaultLocation();
  }

  void _initDefaultLocation() {
    final appState = Provider.of<AppState>(context, listen: false);
    final userLoc = appState.currentUserProfile?.location;
    if (userLoc != null && userLoc.isNotEmpty) {
      _locationController.text = userLoc;
    } else {
      _locationController.text = 'Stockholm, Sweden';
    }
  }

  @override
  void dispose() {
    _detailsController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoadingFavorites = true);
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
        setState(() => _isLoadingFavorites = false);
      }
    }
  }

  void _updateFilteredFavorites() {
    _filteredFavorites = List.from(_favorites);
    _selectedFavorites.clear();
    for (final f in _filteredFavorites) {
      if (f.userId != null) {
        _selectedFavorites[f.userId!] = true;
      }
    }
  }

  List<String> get _currentSubRoles {
    switch (_selectedCategory) {
      case 'Songwriters/Producers':
        return ['Songwriters', 'Producers', 'Other'];
      case 'Studios/Engineers':
        return ['Studios', 'Engineers', 'Other'];
      case 'Sessions':
        return ['Create Session', 'Create Jam', 'Find Session'];
      default:
        return ['Songwriters', 'Producers', 'Other'];
    }
  }

  void _onCategoryChanged(String newCat) {
    setState(() {
      _selectedCategory = newCat;
      final subs = _currentSubRoles;
      _selectedSubRole = subs.first;
      if (newCat == 'Songwriters/Producers') {
        _selectedCollabAreas = ['Songwriter'];
      } else if (newCat == 'Studios/Engineers') {
        _selectedCollabAreas = ['Studio'];
      } else {
        _selectedCollabAreas = ['Session Musician'];
      }
    });
  }

  Future<void> _openCollabAreaPicker() async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Collaboration Area',
      categoryMap: _allSkillsCategoryMap,
      initialSelected: _selectedCollabAreas,
    );
    if (result != null) {
      setState(() {
        _selectedCollabAreas = result;
      });
    }
  }

  Future<void> _submitCollabRequest() async {
    if (_detailsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe what your collaboration is about'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;

    try {
      List<String>? targetIds;
      if (_sendToFavoritesOnly) {
        targetIds = _selectedFavorites.entries.where((e) => e.value).map((e) => e.key).toList();
        if (targetIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select at least 1 favorite recipient.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          setState(() => _isSubmitting = false);
          return;
        }
      }

      final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final collabReq = SubRequest(
        creatorUserId: userId,
        userId: userId,
        role: _selectedCategory,
        voicePart: _selectedSubRole,
        level: _selectedCollabAreas.isEmpty ? 'Collaboration' : _selectedCollabAreas.join(', '),
        location: _locationController.text.trim().isEmpty ? 'Stockholm, Sweden' : _locationController.text.trim(),
        description: _detailsController.text.trim(),
        date: nowStr,
        bandName: appState.activeBandName ?? "Freelance Collab",
        bandId: appState.activeBandId,
        targetUserIds: targetIds,
      );

      final reqId = await appState.firebaseService.saveSubRequestAsync(collabReq);

      if (mounted) {
        if (reqId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Collaboration Request sent successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
          Navigator.pop(context);
        } else {
          throw Exception("Failed to save collaboration request.");
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send collaboration request: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showBandSelectorBottomSheet(BuildContext context, AppState appState, Map<String, String> bands) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16132D).withOpacity(0.95),
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
                'Choose which band you are posting this collaboration request for.',
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

  Widget _buildCategoryButton(String categoryKey, String label) {
    final isSelected = _selectedCategory == categoryKey;
    return Expanded(
      child: AnimatedTapDetector(
        onTap: () => _onCategoryChanged(categoryKey),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryAccent.withOpacity(0.12)
                : AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Find Collab',
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FIND COLLAB',
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),

            // Active Band Chip Selector
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
                  if (context.mounted) Navigator.pop(context);

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
                  if (context.mounted) Navigator.pop(context);
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
                      appState.activeBandName ?? "Freelance Collab",
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

            // 1. Major Category Selector (Songwriters/Producers, Studios/Engineers, Sessions)
            Row(
              children: [
                _buildCategoryButton('Songwriters/Producers', 'Songwriters/\nProducers'),
                const SizedBox(width: 6),
                _buildCategoryButton('Studios/Engineers', 'Studios/\nEngineers'),
                const SizedBox(width: 6),
                _buildCategoryButton('Sessions', 'Sessions'),
              ],
            ),
            const SizedBox(height: 14),

            // Sub-Role Pill Chips
            Wrap(
              spacing: 8,
              children: _currentSubRoles.map((subRole) {
                final isSel = _selectedSubRole == subRole;
                return ChoiceChip(
                  label: Text(subRole),
                  selected: isSel,
                  selectedColor: AppTheme.primaryAccent,
                  backgroundColor: AppTheme.cardBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSel ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                    ),
                  ),
                  labelStyle: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12,
                  ),
                  onSelected: (_) {
                    if (subRole == 'Create Session') {
                      Navigator.pushNamed(context, '/create-session');
                    } else if (subRole == 'Create Jam') {
                      Navigator.pushNamed(context, '/create-session', arguments: 'Jam');
                    } else if (subRole == 'Find Session') {
                      Navigator.pushNamed(context, '/find-sessions');
                    } else {
                      setState(() {
                        _selectedSubRole = subRole;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // 2. COLLABORATION AREA Card Container (Matching Edit Profile / Genres style)
            AnimatedTapDetector(
              onTap: _openCollabAreaPicker,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedCollabAreas.isNotEmpty
                        ? AppTheme.primaryAccent
                        : const Color(0xFF2E2A4E),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.hub_rounded, color: AppTheme.primaryAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'COLLABORATION AREA',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        if (_selectedCollabAreas.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_selectedCollabAreas.length} selected',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 22),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_selectedCollabAreas.isEmpty)
                      Text(
                        'Tap to add area of collaboration...',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _selectedCollabAreas.map((area) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAccent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.4)),
                            ),
                            child: Text(
                              area,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. COLLABORATION DETAILS Card Container
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2A4E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COLLABORATION DETAILS',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location (City, Country)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Location',
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        TextSpan(
                          text: ' (City, Country)',
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _locationController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Stockholm, Sweden',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Details Multiline Text Field
                  Text(
                    'Collaboration Description',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _detailsController,
                    maxLines: 4,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: "Describe what the collaboration is about (e.g. 'I am looking for a co-writer to compose acoustic tracks on weekends')",
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. SELECT FAVORITE(S) Container
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2A4E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELECT FAVORITE(S)',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedTapDetector(
                          onTap: () {
                            setState(() {
                              _sendToFavoritesOnly = true;
                              _showFavoritesList = true;
                            });
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: _sendToFavoritesOnly
                                  ? AppTheme.primaryAccent.withOpacity(0.15)
                                  : AppTheme.inputBackground,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _sendToFavoritesOnly
                                    ? AppTheme.primaryAccent
                                    : const Color(0xFF2E2A4E),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'FAVORITES LIST',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _sendToFavoritesOnly
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AnimatedTapDetector(
                          onTap: () {
                            setState(() {
                              _sendToFavoritesOnly = false;
                              _showFavoritesList = false;
                            });
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: !_sendToFavoritesOnly
                                  ? AppTheme.primaryAccent.withOpacity(0.15)
                                  : AppTheme.inputBackground,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: !_sendToFavoritesOnly
                                    ? AppTheme.primaryAccent
                                    : const Color(0xFF2E2A4E),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'SEND TO ALL',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: !_sendToFavoritesOnly
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_showFavoritesList) ...[
                    const SizedBox(height: 16),
                    _isLoadingFavorites
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                            ),
                          )
                        : _filteredFavorites.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Center(
                                  child: Text(
                                    'No favorite collaborators found.',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            : Column(
                                children: _filteredFavorites.map((fav) {
                                  final isChecked = _selectedFavorites[fav.userId] ?? false;
                                  return CheckboxListTile(
                                    controlAffinity: ListTileControlAffinity.leading,
                                    value: isChecked,
                                    activeColor: AppTheme.primaryAccent,
                                    checkColor: Colors.white,
                                    title: Text(
                                      fav.displayName ?? 'Artist',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      fav.mainSkillsSubtitle,
                                      style: GoogleFonts.inter(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onChanged: (val) {
                                      if (fav.userId != null) {
                                        setState(() {
                                          _selectedFavorites[fav.userId!] = val ?? false;
                                        });
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Submit Collaboration Request Button
            _isSubmitting
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : AnimatedTapDetector(
                    onTap: _submitCollabRequest,
                    child: Container(
                      height: 55,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryAccent.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Send Collaboration Request',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
