import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/listing.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class ListingDetailsPage extends StatefulWidget {
  final Listing listing;

  const ListingDetailsPage({super.key, required this.listing});

  @override
  State<ListingDetailsPage> createState() => _ListingDetailsPageState();
}

class _ListingDetailsPageState extends State<ListingDetailsPage> {
  int _currentImageIndex = 0;
  String _sellerName = 'Loading...';
  String _sellerLocation = '';
  String? _sellerPhotoUrl;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSellerProfile();
  }

  Future<void> _loadSellerProfile() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final profile = await appState.firebaseService.getUserProfileAsync(widget.listing.userId);
      if (profile != null && mounted) {
        setState(() {
          _sellerName = profile.displayName ?? profile.nickname ?? 'Unknown Seller';
          _sellerLocation = profile.location ?? '';
          _sellerPhotoUrl = profile.profilePictureUrl;
        });
      }
    } catch (e) {
      debugPrint("Error loading seller profile: $e");
      if (mounted) {
        setState(() {
          _sellerName = 'Seller';
        });
      }
    }
  }

  String _getTypeDisplay(String? type) {
    switch (type) {
      case 'sell':
        return 'For Sale';
      case 'buy':
        return 'Wanted';
      case 'rent':
        return 'Rent';
      case 'service':
        return 'Service';
      default:
        return 'Listing';
    }
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'sell':
        return AppTheme.primaryAccent;
      case 'buy':
        return AppTheme.success;
      case 'rent':
        return Colors.orangeAccent;
      case 'service':
        return Colors.cyanAccent;
      default:
        return AppTheme.textSecondary;
    }
  }

  Future<void> _contactSeller() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;
    final sellerId = widget.listing.userId;

    if (currentUserId == null || sellerId == null) return;

    setState(() => _isActionLoading = true);

    try {
      // 1. Get or create conversation between currentUser and seller
      final conversationId = await appState.firebaseService.getOrCreateDirectConversationAsync(
        currentUserId,
        sellerId,
      );

      // 2. Prepare dynamic initial text
      final initialText = 'Hi! I am interested in your marketplace listing: "${widget.listing.title}".';
      
      // 3. Send initial message automatically
      final senderName = appState.currentUserProfile?.displayName ??
          appState.currentUserProfile?.nickname ??
          'Musician';

      await appState.firebaseService.sendConversationMessageAsync(
        conversationId,
        initialText,
        sellerId,
        senderName,
      );

      // 4. Route to existing chat detail screen using exact arguments
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/chat-detail',
          arguments: {
            'conversationId': conversationId,
            'receiverId': sellerId,
            'receiverName': _sellerName,
          },
        );
      }
    } catch (e) {
      debugPrint("Error contacting seller: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start conversation: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  void _showReportDialog() {
    final reasons = ['Spam', 'Fraud / Scam', 'Duplicate Listing', 'Offensive Content', 'Other'];
    String selectedReason = reasons.first;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0C20).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REPORT LISTING',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Why are you reporting this listing?',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...reasons.map((reason) {
                      return RadioListTile<String>(
                        value: reason,
                        groupValue: selectedReason,
                        title: Text(reason, style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
                        activeColor: AppTheme.primaryAccent,
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedReason = val);
                          }
                        },
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF2E2A4E)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.danger,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () async {
                              final appState = Provider.of<AppState>(context, listen: false);
                              final currentUserId = appState.currentUserId;
                              if (currentUserId != null && widget.listing.id != null) {
                                await appState.firebaseService.reportListingAsync(
                                  widget.listing.id!,
                                  currentUserId,
                                  selectedReason,
                                );
                              }
                              if (context.mounted) {
                                Navigator.pop(context); // Close dialog
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Listing reported. Thank you for keeping our platform safe.'),
                                    backgroundColor: AppTheme.success,
                                  ),
                                );
                              }
                            },
                            child: Text(
                              'Report',
                              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isOwner = widget.listing.userId == appState.currentUserId;
    final hasImages = widget.listing.imageUrls.isNotEmpty;
    final priceStr = widget.listing.price == 0 ? 'Free' : '${widget.listing.price.toInt()} kr';
    final dateStr = DateFormat('yMMMd').format(DateTime.fromMillisecondsSinceEpoch(widget.listing.createdAt));

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Listing Details',
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Slider / Carousel Section
              SizedBox(
                height: 280,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: hasImages
                          ? PageView.builder(
                              itemCount: widget.listing.imageUrls.length,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentImageIndex = index;
                                });
                              },
                              itemBuilder: (context, index) {
                                return Image.network(
                                  widget.listing.imageUrls[index],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
                                );
                              },
                            )
                          : _buildPlaceholderImage(),
                    ),
                    // Back button overlay
                    Positioned(
                      top: 12,
                      left: 12,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    // Image Index Dots
                    if (hasImages && widget.listing.imageUrls.length > 1)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            widget.listing.imageUrls.length,
                            (index) => Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentImageIndex == index
                                    ? AppTheme.primaryAccent
                                    : Colors.white30,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Status Badge overlay
                    if (widget.listing.status != 'active')
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.listing.status == 'sold' ? AppTheme.success : AppTheme.danger,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.listing.status.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Title and Price Section
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getTypeColor(widget.listing.listingType).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _getTypeColor(widget.listing.listingType).withOpacity(0.5)),
                          ),
                          child: Text(
                            _getTypeDisplay(widget.listing.listingType).toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _getTypeColor(widget.listing.listingType),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2E2A4E)),
                          ),
                          child: Text(
                            widget.listing.category ?? 'Other',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.listing.title ?? 'Untitled Listing',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          priceStr,
                          style: GoogleFonts.outfit(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryAccent,
                          ),
                        ),
                        Text(
                          'Posted: $dateStr',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF2E2A4E), height: 1),
                    const SizedBox(height: 20),

                    // Description Section
                    Text(
                      'DESCRIPTION',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.listing.description ?? 'No description provided.',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.white70,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Color(0xFF2E2A4E), height: 1),
                    const SizedBox(height: 20),

                    // Location Info
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: AppTheme.primaryAccent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          widget.listing.city ?? 'Unknown Location',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Color(0xFF2E2A4E), height: 1),
                    const SizedBox(height: 20),

                    // Seller Card
                    Text(
                      'SELLER INFORMATION',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF231F45), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                            backgroundImage: _sellerPhotoUrl != null && _sellerPhotoUrl!.isNotEmpty
                                ? NetworkImage(_sellerPhotoUrl!)
                                : null,
                            child: _sellerPhotoUrl == null || _sellerPhotoUrl!.isEmpty
                                ? Text(
                                    _sellerName.isNotEmpty ? _sellerName.substring(0, 1).toUpperCase() : 'S',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _sellerName,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_sellerLocation.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _sellerLocation,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Action buttons
                    if (isOwner) ...[
                      // If owner, let them manage their listing by opening the management page
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.05),
                          side: const BorderSide(color: Color(0xFF2E2A4E)),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/my-listings');
                        },
                        icon: const Icon(Icons.inventory_2_outlined, color: Colors.white),
                        label: Text(
                          'Manage My Listings',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ] else ...[
                      // Action Row for Buyer
                      Row(
                        children: [
                          // Report button
                          GestureDetector(
                            onTap: _showReportDialog,
                            child: Container(
                              height: 52,
                              width: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF2E2A4E)),
                              ),
                              child: const Icon(Icons.outlined_flag_rounded, color: Colors.redAccent),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Contact Seller button
                          Expanded(
                            child: AnimatedTapDetector(
                              onTap: _isActionLoading ? () {} : () => _contactSeller(),
                              child: Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryAccent.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isActionLoading
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Contact Seller',
                                              style: GoogleFonts.inter(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
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
              size: 56,
            ),
            const SizedBox(height: 8),
            Text(
              'No Images Available',
              style: GoogleFonts.inter(
                fontSize: 13,
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
