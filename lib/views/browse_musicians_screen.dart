import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';

class BrowseMusiciansScreen extends StatefulWidget {
  const BrowseMusiciansScreen({super.key});

  @override
  State<BrowseMusiciansScreen> createState() => _BrowseMusiciansScreenState();
}

class _BrowseMusiciansScreenState extends State<BrowseMusiciansScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'All';
  List<UserProfile> _allMusicians = [];
  List<UserProfile> _filteredMusicians = [];
  bool _isLoading = true;

  final List<String> _categories = ['All', 'Electric Guitar', 'Electric Bass', 'Drums', 'Keyboard/Synth', 'Vocalist'];

  @override
  void initState() {
    _loadMusicians();
    _searchController.addListener(_onSearchChanged);
    super.initState();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMusicians() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final users = await appState.firebaseService.getAllUsersAsync();
      
      // Filter out the current user themselves
      final selfId = appState.currentUserId;
      _allMusicians = users.where((u) => u.userId != selfId).toList();

      // Seed mock musicians if the database is empty
      if (_allMusicians.isEmpty) {
        _allMusicians = _getMockMusicians();
      }
      
      _applyFilters();
    } catch (e) {
      debugPrint("Error loading musicians: $e");
    } finally {
      setState(() => _isLoading = false);
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
        instruments: ['Vocalist'],
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
        instruments: ['Electric Guitar'],
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
        instruments: ['Electric Bass'],
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
        instruments: ['Drums'],
        genres: ['Rock', 'Alternative', 'Indie'],
        about: 'Energetic drummer who plays both acoustic and electronic setups. Available for rehearsal substitutes and studio sessions.',
        profilePictureUrl: '',
      ),
    ];
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredMusicians = _allMusicians.where((m) {
        final matchesSearch = (m.displayName?.toLowerCase().contains(query) ?? false) ||
            (m.location?.toLowerCase().contains(query) ?? false);
        
        final matchesCategory = _selectedCategory == 'All' ||
            m.instruments.any((i) => i.toLowerCase() == _selectedCategory.toLowerCase()) ||
            (m.userType?.toLowerCase() == _selectedCategory.toLowerCase());

        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Browse Musicians',
        showBack: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const SizedBox(height: 10),
          Text(
            'BROWSE MUSICIANS',
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Search Input
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search musicians',
              prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 16),

          // Categories chips row
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedCategory = category;
                        });
                        _applyFilters();
                      }
                    },
                    selectedColor: AppTheme.primaryAccent,
                    backgroundColor: AppTheme.inputBackground,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Musicians List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : _filteredMusicians.isEmpty
                    ? Center(
                        child: Text(
                          'No musicians found.',
                          style: GoogleFonts.inter(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredMusicians.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          final musician = _filteredMusicians[index];
                          return _buildMusicianCard(musician);
                        },
                      ),
          ),
        ],
      ),
    ),
  ),
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
                // Avatar with green status dot
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
                              (user.displayName ?? 'U').substring(0, 1).toUpperCase(),
                              style: const TextStyle(
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

                // Musician Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            user.displayName ?? 'Unknown',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          // Favorite Icon
                          FutureBuilder<bool>(
                            future: appState.firebaseService.isFavoriteAsync(user.userId ?? ''),
                            builder: (context, snapshot) {
                              final isFav = snapshot.data ?? false;
                              return GestureDetector(
                                onTap: () async {
                                  await appState.firebaseService
                                      .toggleFavoriteAsync(user.userId ?? '', !isFav);
                                  setState(() {}); // trigger rebuild of this star icon
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
                        user.userType ?? 'Musician',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.primaryAccent,
                          fontWeight: FontWeight.w500,
                        ),
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

                      // Genre tags
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
}
