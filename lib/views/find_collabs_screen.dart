import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';

class FindCollabsScreen extends StatefulWidget {
  final String role; // 'songwriter', 'producer', 'engineer'

  const FindCollabsScreen({super.key, required this.role});

  @override
  State<FindCollabsScreen> createState() => _FindCollabsScreenState();
}

class _FindCollabsScreenState extends State<FindCollabsScreen> {
  final _searchController = TextEditingController();
  List<UserProfile> _allCollabUsers = [];
  List<UserProfile> _filteredUsers = [];
  bool _isLoading = true;
  Set<String> _favoriteUserIds = {};

  // Filtering states
  String _selectedGenre = 'All';
  bool _remoteOnly = false;

  final List<String> _genresList = [
    "All",
    "Pop",
    "Rock",
    "Metal",
    "Hip-Hop",
    "Jazz",
    "Blues",
    "Electronic",
    "Country",
    "Classical",
    "Soul",
    "Reggae"
  ];

  @override
  void initState() {
    _loadCollabUsers();
    _searchController.addListener(_onSearchOrFilterChanged);
    super.initState();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchOrFilterChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCollabUsers() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);

      // Load favorites
      final favIds = await appState.firebaseService.getFavoriteUserIdsAsync();
      _favoriteUserIds = favIds.toSet();

      // Load all users
      final users = await appState.firebaseService.getAllUsersAsync();

      // Filter out self and keep only users with matching collab role
      final selfId = appState.currentUserId;
      _allCollabUsers = users.where((u) {
        if (u.userId == selfId) return false;
        return u.collabRoles.contains(widget.role.toLowerCase());
      }).toList();

      _applyFilters();
    } catch (e) {
      debugPrint("Error loading collab users: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onSearchOrFilterChanged() {
    _applyFilters();
  }

  /// Clean helper logic for client-side filtering that can be replaced with server-side discovery queries later.
  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _allCollabUsers.where((user) {
        // Text Search
        final matchesSearch = (user.displayName?.toLowerCase().contains(query) ?? false) ||
            (user.location?.toLowerCase().contains(query) ?? false);

        // Genre Filter
        final matchesGenre = _selectedGenre == 'All' ||
            user.genres.any((g) => g.toLowerCase() == _selectedGenre.toLowerCase());

        // Remote Switch
        final matchesRemote = !_remoteOnly || user.collabRemote;

        return matchesSearch && matchesGenre && matchesRemote;
      }).toList();
    });
  }

  String _getRoleTitle() {
    switch (widget.role.toLowerCase()) {
      case 'songwriter':
        return 'Songwriters';
      case 'producer':
        return 'Producers';
      case 'engineer':
        return 'Engineers';
      default:
        return 'Collaborators';
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _getRoleTitle();

    return GradientScaffold(
      appBar: CustomTopBar(
        title: 'Find $titleText',
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
                'FIND ${titleText.toUpperCase()}',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              // Search Text Field
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name or location...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 16),

              // Genre Dropdown & Remote Toggle Row
              Row(
                children: [
                  // Genre Selector Dropdown
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.inputBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E2A4E)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedGenre,
                          dropdownColor: AppTheme.cardBackground,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                          onChanged: (String? val) {
                            if (val != null) {
                              setState(() => _selectedGenre = val);
                              _applyFilters();
                            }
                          },
                          items: _genresList.map((String genre) {
                            return DropdownMenuItem<String>(
                              value: genre,
                              child: Text(genre),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Remote Toggle Switch
                  Row(
                    children: [
                      Text(
                        'Remote Only',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      Switch(
                        value: _remoteOnly,
                        onChanged: (val) {
                          setState(() => _remoteOnly = val);
                          _applyFilters();
                        },
                        activeColor: AppTheme.primaryAccent,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Users List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                    : _filteredUsers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_search_rounded, color: AppTheme.textMuted, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'No $titleText found matching filters.',
                                  style: GoogleFonts.inter(color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredUsers.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              return _buildCollabUserCard(user);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollabUserCard(UserProfile user) {
    final appState = Provider.of<AppState>(context);
    final isFav = _favoriteUserIds.contains(user.userId ?? '');

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
                // Circle Avatar
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                  backgroundImage: user.profilePictureUrl != null && user.profilePictureUrl!.isNotEmpty
                      ? NetworkImage(user.profilePictureUrl!)
                      : null,
                  child: user.profilePictureUrl == null || user.profilePictureUrl!.isEmpty
                      ? Text(
                          (user.displayName != null && user.displayName!.isNotEmpty)
                              ? user.displayName!.substring(0, 1).toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),

                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              user.displayName ?? 'Unknown Artist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final targetId = user.userId ?? '';
                              final nextFav = !isFav;
                              await appState.firebaseService.toggleFavoriteAsync(targetId, nextFav);
                              setState(() {
                                if (nextFav) {
                                  _favoriteUserIds.add(targetId);
                                } else {
                                  _favoriteUserIds.remove(targetId);
                                }
                              });
                            },
                            child: Icon(
                              isFav ? Icons.star_rounded : Icons.star_border_rounded,
                              color: isFav ? AppTheme.primaryAccent : AppTheme.textSecondary,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),

                      // Location & Remote Status Row
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              user.location ?? 'Remote',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          if (user.collabRemote) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Remote',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Collab Bio snippet
                      if (user.collabBio != null && user.collabBio!.isNotEmpty) ...[
                        Text(
                          user.collabBio!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Genres Tag list
                      if (user.genres.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: user.genres.take(3).map((genre) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
