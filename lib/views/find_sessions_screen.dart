import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/collab_session.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';

class FindSessionsScreen extends StatefulWidget {
  const FindSessionsScreen({super.key});

  @override
  State<FindSessionsScreen> createState() => _FindSessionsScreenState();
}

class _FindSessionsScreenState extends State<FindSessionsScreen> {
  final _searchController = TextEditingController();
  List<CollabSession> _allSessions = [];
  List<CollabSession> _filteredSessions = [];
  bool _isLoading = true;

  // Filters
  String _selectedCategory = 'All';
  String _selectedType = 'All';
  String _selectedRole = 'All';

  final List<String> _categories = [
    "All",
    "Songwriting",
    "Recording",
    "Production",
    "Jam",
    "Other",
  ];
  final List<String> _types = ["All", "In person", "Remote", "Hybrid"];
  final List<String> _roles = [
    "All",
    "Songwriter",
    "Producer",
    "Engineer",
    "Vocalist",
    "Musician",
  ];

  @override
  void initState() {
    _loadSessions();
    _searchController.addListener(_onSearchChanged);
    super.initState();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      _allSessions = await appState.firebaseService.getCollabSessionsAsync();
      _applyFilters();
    } catch (e) {
      debugPrint("Error loading sessions: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredSessions = _allSessions.where((session) {
        // Text search
        final matchesSearch =
            session.title.toLowerCase().contains(query) ||
            session.description.toLowerCase().contains(query) ||
            (session.location?.toLowerCase().contains(query) ?? false);

        // Category filter
        final matchesCategory =
            _selectedCategory == 'All' ||
            session.sessionCategory.toLowerCase() ==
                _selectedCategory.toLowerCase();

        // Session type filter
        final matchesType =
            _selectedType == 'All' ||
            session.sessionType.toLowerCase() == _selectedType.toLowerCase();

        // Role needed filter
        final matchesRole =
            _selectedRole == 'All' ||
            session.lookingForRoles.any(
              (r) => r.toLowerCase() == _selectedRole.toLowerCase(),
            );

        return matchesSearch &&
            matchesCategory &&
            matchesType &&
            matchesRole &&
            session.status == 'active';
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(title: 'Find Sessions', showBack: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'COLLAB SESSIONS',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.pushNamed(context, '/create-session');
                      _loadSessions();
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      'New Session',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search Text Field
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by title, location or keywords...',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Filters Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    // Category Filter
                    _buildFilterDropdown(
                      label: 'Category',
                      value: _selectedCategory,
                      items: _categories,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedCategory = val);
                          _applyFilters();
                        }
                      },
                    ),
                    const SizedBox(width: 8),

                    // Type Filter
                    _buildFilterDropdown(
                      label: 'Type',
                      value: _selectedType,
                      items: _types,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedType = val);
                          _applyFilters();
                        }
                      },
                    ),
                    const SizedBox(width: 8),

                    // Role Filter
                    _buildFilterDropdown(
                      label: 'Role Needed',
                      value: _selectedRole,
                      items: _roles,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedRole = val);
                          _applyFilters();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Sessions List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryAccent,
                        ),
                      )
                    : _filteredSessions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.forum_outlined,
                              color: AppTheme.textMuted,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No sessions found matching filters.',
                              style: GoogleFonts.inter(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () async {
                                await Navigator.pushNamed(
                                  context,
                                  '/create-session',
                                );
                                _loadSessions();
                              },
                              child: const Text(
                                'Create a Collaboration Session!',
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredSessions.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          final session = _filteredSessions[index];
                          return _buildSessionCard(session);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.inputBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E2A4E)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: AppTheme.cardBackground,
          icon: const Icon(
            Icons.arrow_drop_down,
            color: Colors.white,
            size: 18,
          ),
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          onChanged: onChanged,
          items: items.map((String item) {
            return DropdownMenuItem<String>(value: item, child: Text(item));
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSessionCard(CollabSession session) {
    final dateStr = session.isDateFlexible
        ? 'Flexible Date'
        : (session.startDateTime != null
              ? session.startDateTime!.substring(0, 10)
              : 'Date not set');

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
          onTap: () async {
            await Navigator.pushNamed(
              context,
              '/session-details',
              arguments: session,
            );
            _loadSessions();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        session.sessionCategory.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ),
                    Text(
                      session.sessionType,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),

                // Description
                Text(
                  session.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Date & Location Info
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: AppTheme.textSecondary,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dateStr,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.location_on_outlined,
                      color: AppTheme.textSecondary,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        session.location ?? 'Remote',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Looking For Tags
                if (session.lookingForRoles.isNotEmpty) ...[
                  Text(
                    'Looking for:',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: session.lookingForRoles.map((role) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1A3A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          role[0].toUpperCase() + role.substring(1),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
