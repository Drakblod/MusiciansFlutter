import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/collab_studio.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';

class FindStudiosScreen extends StatefulWidget {
  const FindStudiosScreen({super.key});

  @override
  State<FindStudiosScreen> createState() => _FindStudiosScreenState();
}

class _FindStudiosScreenState extends State<FindStudiosScreen> {
  final _searchController = TextEditingController();
  List<CollabStudio> _allStudios = [];
  List<CollabStudio> _filteredStudios = [];
  bool _isLoading = true;

  @override
  void initState() {
    _loadStudios();
    _searchController.addListener(_onSearchChanged);
    super.initState();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudios() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      _allStudios = await appState.firebaseService.getCollabStudiosAsync();
      _applyFilters();
    } catch (e) {
      debugPrint("Error loading studios: $e");
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
      _filteredStudios = _allStudios.where((studio) {
        return studio.name.toLowerCase().contains(query) ||
            studio.location.toLowerCase().contains(query) ||
            studio.description.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Find Studios',
        showBack: true,
      ),
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
                    'FIND STUDIOS',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.pushNamed(context, '/edit-studio');
                      _loadStudios();
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      'Add Studio',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search Text Field
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by studio name or location...',
                  prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 16),

              // Studios List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                    : _filteredStudios.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.music_video_rounded, color: AppTheme.textMuted, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'No studios found matching filters.',
                                  style: GoogleFonts.inter(color: AppTheme.textSecondary),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: () async {
                                    await Navigator.pushNamed(context, '/edit-studio');
                                    _loadStudios();
                                  },
                                  child: const Text('Add the first Studio!'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredStudios.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final studio = _filteredStudios[index];
                              return _buildStudioCard(studio);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudioCard(CollabStudio studio) {
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
            await Navigator.pushNamed(context, '/studio-details', arguments: studio);
            _loadStudios();
          },
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
                        studio.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 14),
                  ],
                ),
                const SizedBox(height: 4),

                // Location
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        studio.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  studio.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Genres tags
                if (studio.genres.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: studio.genres.take(3).map((genre) {
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
        ),
      ),
    );
  }
}
