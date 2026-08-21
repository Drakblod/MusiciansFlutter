import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../models/band.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';

class BrowseMusiciansScreen extends StatefulWidget {
  final bool favoritesOnly;

  const BrowseMusiciansScreen({super.key, this.favoritesOnly = false});

  @override
  State<BrowseMusiciansScreen> createState() => _BrowseMusiciansScreenState();
}

class _BrowseMusiciansScreenState extends State<BrowseMusiciansScreen> {
  final _searchController = TextEditingController();
  int _activeTab = 0; // 0 = Musicians, 1 = Bands

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

  List<String> _selectedSkills = [];

  List<UserProfile> _allMusicians = [];
  List<UserProfile> _filteredMusicians = [];
  List<Band> _allBands = [];
  List<Band> _filteredBands = [];

  bool _isLoading = true;
  Set<String> _favoriteUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      
      // Load favorites
      final favIds = await appState.firebaseService.getFavoriteUserIdsAsync();
      _favoriteUserIds = favIds.toSet();

      // Load musicians
      List<UserProfile> users = await appState.firebaseService.getAllUsersAsync();
      final selfId = appState.currentUserId;
      _allMusicians = users.where((u) => u.userId != selfId).toList();

      if (widget.favoritesOnly) {
        _allMusicians = _allMusicians.where((u) => u.userId != null && _favoriteUserIds.contains(u.userId)).toList();
      }

      // Seed mock musicians if empty and not favoritesOnly
      if (_allMusicians.isEmpty && !widget.favoritesOnly) {
        _allMusicians = _getMockMusicians();
      }

      // Load bands (only if not favoritesOnly)
      if (!widget.favoritesOnly) {
        _allBands = await appState.firebaseService.getAllBandsAsync();
        if (_allBands.isEmpty) {
          _allBands = _getMockBands();
        }
      }

      _applyFilters();
    } catch (e) {
      debugPrint("Error loading data: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<UserProfile> _getMockMusicians() {
    return [
      UserProfile(
        userId: 'mock_1',
        displayName: 'Lina Rockwell',
        nickname: 'linarock',
        userType: 'Vocalist',
        location: 'Stockholm, Sweden',
        instruments: ['Vocalist', 'Popular Music'],
        genres: ['Rock', 'Pop', 'Indie'],
        about: 'Passionate vocalist with experience in live performances and studio recordings. Love rock, pop and indie vibes!',
        profilePictureUrl: '',
      ),
      UserProfile(
        userId: 'mock_2',
        displayName: 'Marcus K.',
        nickname: 'marcusg',
        userType: 'Electric Guitar',
        location: 'Gothenburg, Sweden',
        instruments: ['Electric Guitar', 'Strings'],
        genres: ['Rock', 'Blues', 'Metal'],
        about: 'Lead guitarist playing for over 10 years. Looking for heavy rock bands or acoustic side gigs.',
        profilePictureUrl: '',
      ),
      UserProfile(
        userId: 'mock_3',
        displayName: 'Sofia Lind',
        nickname: 'sofia_bass',
        userType: 'Electric Bass',
        location: 'Malmö, Sweden',
        instruments: ['Electric Bass', 'Strings'],
        genres: ['Pop', 'Funk', 'Soul'],
        about: 'Bass player with a strong focus on groove and pocket. Experienced in musical theater and pop cover groups.',
        profilePictureUrl: '',
      ),
      UserProfile(
        userId: 'mock_4',
        displayName: 'Jonas Pettersson',
        nickname: 'jonasdrums',
        userType: 'Drums',
        location: 'Uppsala, Sweden',
        instruments: ['Drums', 'Percussion'],
        genres: ['Rock', 'Alternative', 'Indie'],
        about: 'Energetic drummer who plays both acoustic and electronic setups. Available for rehearsal substitutes and studio sessions.',
        profilePictureUrl: '',
      ),
    ];
  }

  List<Band> _getMockBands() {
    return [
      Band(
        id: 'mock_band_1',
        name: 'The Sonic Wave',
        ensembleType: 'Band',
        genres: ['Rock', 'Indie', 'Alternative'],
        location: 'Stockholm, Sweden',
        rehearsalLocation: 'Studio 4, Stockholm',
        rehearsalDayOfWeek: 'Wednesday',
        rehearsalStartTime: '18:00',
        rehearsalEndTime: '21:00',
        about: 'We are a 4-piece indie rock band looking for active gigs and occasional synth player substitutes.',
        description: 'Indie rock band from Stockholm.',
      ),
      Band(
        id: 'mock_band_2',
        name: 'Groove Collective',
        ensembleType: 'Ensemble',
        genres: ['Funk', 'Soul', 'Jazz'],
        location: 'Gothenburg, Sweden',
        rehearsalLocation: 'Gothenburg Community Center',
        rehearsalDayOfWeek: 'Monday',
        rehearsalStartTime: '19:00',
        rehearsalEndTime: '21:30',
        about: 'A loose collective of soul and jazz lovers. We play cover events and corporate gigs.',
        description: 'Funk and Soul collective in Gothenburg.',
      ),
    ];
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  Future<void> _openSkillsPicker() async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Filter Skills & Instruments',
      categoryMap: _allSkillsCategoryMap,
      initialSelected: _selectedSkills,
    );
    if (result != null) {
      setState(() {
        _selectedSkills = result;
        _applyFilters();
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    
    if (_activeTab == 0) {
      // Musicians filtering
      setState(() {
        _filteredMusicians = _allMusicians.where((m) {
          final matchesSearch = query.isEmpty ||
              (m.displayName?.toLowerCase().contains(query) ?? false) ||
              (m.location?.toLowerCase().contains(query) ?? false) ||
              (m.about?.toLowerCase().contains(query) ?? false) ||
              (m.userType?.toLowerCase().contains(query) ?? false) ||
              m.instruments.any((i) => i.toLowerCase().contains(query));
          
          if (!matchesSearch) return false;
          
          if (_selectedSkills.isEmpty) return true;

          final userInstruments = m.instruments.map((i) => i.toLowerCase()).toList();
          final userType = m.userType?.toLowerCase() ?? '';
          final about = m.about?.toLowerCase() ?? '';

          return _selectedSkills.any((skill) {
            final s = skill.toLowerCase();
            return userType.contains(s) ||
                userInstruments.any((i) => i.contains(s)) ||
                about.contains(s);
          });
        }).toList();
      });
    } else {
      // Bands filtering
      setState(() {
        _filteredBands = _allBands.where((b) {
          final matchesSearch = query.isEmpty ||
              (b.name?.toLowerCase().contains(query) ?? false) ||
              (b.location?.toLowerCase().contains(query) ?? false) ||
              (b.description?.toLowerCase().contains(query) ?? false) ||
              b.genres.any((g) => g.toLowerCase().contains(query));

          if (!matchesSearch) return false;

          if (_selectedSkills.isEmpty) return true;

          final genres = b.genres.map((g) => g.toLowerCase()).toList();
          final about = b.about?.toLowerCase() ?? '';

          return _selectedSkills.any((skill) {
            final s = skill.toLowerCase();
            return genres.any((g) => g.contains(s)) || about.contains(s);
          });
        }).toList();
      });
    }
  }

  void _showBandDetails(Band band) {
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      band.name ?? 'Unknown Band',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      band.ensembleType ?? 'Band',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.primaryAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (band.location != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      band.location!,
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF2E2A4E)),
              const SizedBox(height: 16),
              Text(
                'ABOUT',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                band.about ?? band.description ?? 'No description provided.',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'REHEARSAL DETAILS',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: AppTheme.primaryAccent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    band.rehearsalDayOfWeek != null 
                        ? 'Every ${band.rehearsalDayOfWeek}'
                        : 'No set schedule',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  ),
                  if (band.rehearsalStartTime != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.access_time_rounded, color: AppTheme.primaryAccent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${band.rehearsalStartTime} - ${band.rehearsalEndTime ?? ""}',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ],
              ),
              if (band.rehearsalLocation != null && band.rehearsalLocation!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.room_rounded, color: AppTheme.primaryAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        band.rehearsalLocation!,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: AnimatedTapDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppTheme.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            'Close',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: CustomTopBar(
        title: widget.favoritesOnly ? 'My Favorites' : 'Profiles',
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.favoritesOnly ? 'MY FAVORITES' : 'PROFILES',
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Selector (Only shown if NOT favoritesOnly mode)
            if (!widget.favoritesOnly) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF231F45), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _activeTab = 0;
                              _applyFilters();
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: _activeTab == 0
                                  ? AppTheme.primaryAccent.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                'Musicians',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _activeTab == 0
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _activeTab = 1;
                              _applyFilters();
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: _activeTab == 1
                                  ? AppTheme.primaryAccent.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                'Bands',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _activeTab == 1
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
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Interactive Search & Selection Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedTapDetector(
                enableFocus: true,
                semanticLabel: 'Filter Skills and Instruments',
                onTap: _openSkillsPicker,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedSkills.isNotEmpty
                          ? AppTheme.primaryAccent.withOpacity(0.5)
                          : const Color(0xFF2E2A4E),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _selectedSkills.isEmpty
                            ? Text(
                                _activeTab == 0
                                    ? 'Search musicians, vocalists, songwriters, producers...'
                                    : 'Search bands, ensembles...',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              )
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _selectedSkills.map((skill) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryAccent.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppTheme.primaryAccent.withOpacity(0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          skill,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedSkills.remove(skill);
                                              _applyFilters();
                                            });
                                          },
                                          child: const Icon(
                                            Icons.close_rounded,
                                            size: 14,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.tune_rounded,
                        color: _selectedSkills.isNotEmpty ? AppTheme.primaryAccent : AppTheme.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Content List (Musicians or Bands)
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                  : _activeTab == 0
                      ? _buildMusiciansList()
                      : _buildBandsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusiciansList() {
    if (_filteredMusicians.isEmpty) {
      return Center(
        child: Text(
          'No musicians found.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredMusicians.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final musician = _filteredMusicians[index];
        return _buildMusicianCard(musician);
      },
    );
  }

  Widget _buildBandsList() {
    if (_filteredBands.isEmpty) {
      return Center(
        child: Text(
          'No bands found.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredBands.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final band = _filteredBands[index];
        return _buildBandCard(band);
      },
    );
  }

  Widget _buildMusicianCard(UserProfile user) {
    final appState = Provider.of<AppState>(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF231F45), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pushNamed(context, '/profile-detail', arguments: user);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                      backgroundImage: user.profilePictureUrl != null &&
                              user.profilePictureUrl!.isNotEmpty
                          ? NetworkImage(user.profilePictureUrl!)
                          : null,
                      child: user.profilePictureUrl == null ||
                              user.profilePictureUrl!.isEmpty
                          ? Text(
                              (user.displayName != null && user.displayName!.isNotEmpty)
                                  ? user.displayName!.substring(0, 1).toUpperCase()
                                  : 'U',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 4,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.cardBackground, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              user.displayName ?? 'Unknown',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final isFav = _favoriteUserIds.contains(user.userId ?? '');
                              return GestureDetector(
                                onTap: () async {
                                  final targetId = user.userId ?? '';
                                  final nextFav = !isFav;
                                  await appState.firebaseService
                                      .toggleFavoriteAsync(targetId, nextFav);
                                  setState(() {
                                    if (nextFav) {
                                      _favoriteUserIds.add(targetId);
                                    } else {
                                      _favoriteUserIds.remove(targetId);
                                      if (widget.favoritesOnly) {
                                        _allMusicians.removeWhere((u) => u.userId == targetId);
                                        _applyFilters();
                                      }
                                    }
                                  });
                                },
                                child: Icon(
                                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                                  color: isFav ? AppTheme.primaryAccent : AppTheme.textSecondary,
                                  size: 24,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.mainSkillsSubtitle,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.primaryAccent,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            user.location ?? 'Unknown',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: user.genres.map((genre) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1A3A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              genre,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: AppTheme.secondaryAccent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBandCard(Band band) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF231F45), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showBandDetails(band),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        band.name ?? 'Unknown Band',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        band.ensembleType ?? 'Band',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.primaryAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (band.location != null)
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        band.location!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (band.description != null && band.description!.isNotEmpty) ...[
                  Text(
                    band.description!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Member count badge
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded, color: AppTheme.textSecondary, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${band.membersBand.length} member${band.membersBand.length == 1 ? "" : "s"}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    // Genre tags (up to 2)
                    Row(
                      children: band.genres.take(2).map((genre) {
                        return Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1A3A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            genre,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppTheme.secondaryAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
