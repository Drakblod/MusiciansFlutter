import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/listing.dart';
import '../models/marketplace_taxonomy.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/marketplace_filter_selector.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedIntent;
  String? _selectedCategoryId;
  List<Listing> _allListings = [];
  List<Listing> _filteredListings = [];
  bool _isLoading = true;

  final Map<String, String> _sellerNamesCache = {};

  @override
  void initState() {
    super.initState();
    _loadListings();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadListings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final listings = await appState.firebaseService.getActiveListingsAsync();
      if (mounted) {
        setState(() {
          _allListings = listings;
          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint("Error loading marketplace listings: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      _filteredListings = _allListings.where((listing) {
        final matchesSearch = query.isEmpty ||
            (listing.title?.toLowerCase().contains(query) ?? false) ||
            (listing.description?.toLowerCase().contains(query) ?? false) ||
            (listing.city?.toLowerCase().contains(query) ?? false);

        final matchesCategoryFilter = MarketplaceTaxonomy.matchesBrowsingFilter(
          listing: listing,
          browsingIntent: _selectedIntent,
          browsingCategoryId: _selectedCategoryId,
        );

        return matchesSearch && matchesCategoryFilter;
      }).toList();
    });
  }

  Future<String> _getSellerName(String userId) async {
    if (_sellerNamesCache.containsKey(userId)) {
      return _sellerNamesCache[userId]!;
    }
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final profile = await appState.firebaseService.getUserProfileAsync(userId);
      final name = profile?.displayName ?? profile?.nickname ?? 'Unknown Seller';
      _sellerNamesCache[userId] = name;
      return name;
    } catch (e) {
      return 'Seller';
    }
  }

  String _getBadgeLabel(Listing listing) {
    final intent = listing.effectiveIntent;
    final categoryLabel = MarketplaceTaxonomy.getCategoryLabel(intent, listing.effectiveCategory);
    if (intent == MarketplaceTaxonomy.intentLookingFor) {
      return 'WANTED • $categoryLabel';
    } else {
      final typeDisplay = listing.listingType == 'rent'
          ? 'RENT'
          : (listing.listingType == 'service' ? 'SERVICE' : 'OFFER');
      return '$typeDisplay • $categoryLabel';
    }
  }

  Color _getBadgeColor(Listing listing) {
    if (listing.effectiveIntent == MarketplaceTaxonomy.intentLookingFor) {
      return AppTheme.success;
    }
    if (listing.listingType == 'rent') return Colors.orangeAccent;
    if (listing.listingType == 'service') return Colors.cyanAccent;
    return AppTheme.primaryAccent;
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Marketplace',
        showBack: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryAccent,
          backgroundColor: AppTheme.cardBackground,
          onRefresh: _loadListings,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MARKETPLACE',
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    AnimatedTapDetector(
                      onTap: () {
                        Navigator.pushNamed(context, '/my-listings');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 16, color: AppTheme.primaryAccent),
                            const SizedBox(width: 6),
                            Text(
                              'My Listings',
                              style: GoogleFonts.inter(
                                color: AppTheme.primaryAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search instrument, equipment, studio, mixing...',
                    prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                          )
                        : null,
                  ),
                ),
              ),

              // Dual-Entry Marketplace Selector Cards
              MarketplaceFilterSelector(
                selectedIntent: _selectedIntent,
                selectedCategoryId: _selectedCategoryId,
                onFilterChanged: (filter) {
                  setState(() {
                    _selectedIntent = filter.intent;
                    _selectedCategoryId = filter.categoryId;
                    _applyFilters();
                  });
                },
              ),

              const SizedBox(height: 8),

              // Listings List/Grid
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                      )
                    : _filteredListings.isEmpty
                        ? _buildEmptyState()
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _filteredListings.length,
                            itemBuilder: (context, index) {
                              final listing = _filteredListings[index];
                              return _buildListingCard(listing);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(
            context,
            '/create-listing',
            arguments: {
              'initialIntent': _selectedIntent,
              'initialCategory': _selectedCategoryId,
            },
          ).then((value) {
            _loadListings();
          });
        },
        backgroundColor: AppTheme.primaryAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    String ctaLabel = 'Post a Listing';
    String? targetIntent = _selectedIntent;
    String? targetCategory = _selectedCategoryId;

    if (_selectedIntent == MarketplaceTaxonomy.intentLookingFor) {
      ctaLabel = 'Create a request';
    } else if (_selectedIntent == MarketplaceTaxonomy.intentOffering) {
      ctaLabel = 'Create an offer';
    }

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2E2A4E)),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  size: 64,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No Listings Found',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters or search query, or create a brand new listing below!',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/create-listing',
                    arguments: {
                      'initialIntent': targetIntent,
                      'initialCategory': targetCategory,
                    },
                  ).then((value) {
                    _loadListings();
                  });
                },
                icon: const Icon(Icons.add, color: Colors.white),
                label: Text(
                  ctaLabel,
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListingCard(Listing listing) {
    final hasImages = listing.imageUrls.isNotEmpty;
    final priceStr = listing.price == 0 ? 'Free' : '${listing.price.toInt()} kr';
    final badgeLabel = _getBadgeLabel(listing);
    final badgeColor = _getBadgeColor(listing);

    return AnimatedTapDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/listing-details',
          arguments: listing,
        ).then((_) => _loadListings());
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF231F45),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image / Placeholder Section
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: hasImages
                        ? Image.network(
                            listing.imageUrls.first,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
                          )
                        : _buildPlaceholderImage(),
                  ),
                  // Listing Badge
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: badgeColor.withOpacity(0.6),
                          ),
                        ),
                        child: Text(
                          badgeLabel.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content Section
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title ?? 'Untitled Item',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        priceStr,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondaryAccent,
                        ),
                      ),
                      if (listing.city != null && listing.city!.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 12, color: AppTheme.textSecondary),
                            const SizedBox(width: 2),
                            Text(
                              listing.city!,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Divider(color: Color(0xFF2E2A4E), height: 1),
                  const SizedBox(height: 6),
                  // Seller Card Info
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FutureBuilder<String>(
                          future: _getSellerName(listing.userId ?? ''),
                          builder: (context, snapshot) {
                            return Text(
                              snapshot.data ?? 'Loading...',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F1235), Color(0xFF120822)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_note_rounded,
              color: AppTheme.primaryAccent,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              'No Images',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
