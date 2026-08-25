import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/listing.dart';
import '../models/marketplace_taxonomy.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class CreateListingPage extends StatefulWidget {
  final String? initialIntent;
  final String? initialCategory;

  const CreateListingPage({
    super.key,
    this.initialIntent,
    this.initialCategory,
  });

  @override
  State<CreateListingPage> createState() => _CreateListingPageState();
}

class _CreateListingPageState extends State<CreateListingPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _cityController = TextEditingController();

  late String _selectedIntent;
  String? _selectedCategory;
  String _selectedType = 'sell';
  final List<XFile> _selectedImages = [];
  bool _isSubmitting = false;
  bool _initializedArgs = false;

  final Map<String, String> _offeringTypes = {
    'sell': 'For Sale',
    'rent': 'For Rent',
    'service': 'Service',
  };

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedIntent = widget.initialIntent ?? MarketplaceTaxonomy.intentOffering;
    _selectedCategory = widget.initialCategory;
    _ensureValidCategory();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedArgs) {
      _initializedArgs = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        if (args['initialIntent'] != null && args['initialIntent'] is String) {
          _selectedIntent = args['initialIntent'] as String;
        }
        if (args['initialCategory'] != null && args['initialCategory'] is String) {
          _selectedCategory = args['initialCategory'] as String;
        }
        _ensureValidCategory();
      }
    }
  }

  void _ensureValidCategory() {
    final available = MarketplaceTaxonomy.getCategoriesForIntent(_selectedIntent);
    if (_selectedCategory == null || !available.any((c) => c.id == _selectedCategory)) {
      if (available.isNotEmpty) {
        _selectedCategory = available.first.id;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (image != null) {
        setState(() {
          _selectedImages.add(image);
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access camera/photo library: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C22).withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Text(
                  'ADD PHOTO',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primaryAccent),
                  title: Text('Take Photo', style: GoogleFonts.inter(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: AppTheme.primaryAccent),
                  title: Text('Choose from Gallery', style: GoogleFonts.inter(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUserId;
      if (userId == null) throw Exception("User not logged in");

      // Generate local unique key to link images and listing records
      final listingId = appState.firebaseService.generateListingId();

      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        imageUrls = await appState.firebaseService.uploadListingImagesAsync(listingId, _selectedImages);
      }

      final legacyListingType = _selectedIntent == MarketplaceTaxonomy.intentLookingFor
          ? 'buy'
          : _selectedType;
      final categoryLabel = MarketplaceTaxonomy.getCategoryLabel(_selectedIntent, _selectedCategory);

      final listing = Listing(
        id: listingId,
        userId: userId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: categoryLabel,
        listingType: legacyListingType,
        marketplaceIntent: _selectedIntent,
        marketplaceCategory: _selectedCategory,
        price: double.tryParse(_priceController.text) ?? 0.0,
        city: _cityController.text.trim(),
        imageUrls: imageUrls,
        status: 'active',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await appState.firebaseService.saveListingAsync(listing);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing created successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Error creating listing: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create listing: $e'),
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

  @override
  Widget build(BuildContext context) {
    final categories = MarketplaceTaxonomy.getCategoriesForIntent(_selectedIntent);

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Post Listing',
        showBack: true,
      ),
      body: SafeArea(
        child: _isSubmitting
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppTheme.primaryAccent),
                    const SizedBox(height: 16),
                    Text(
                      'Creating listing and uploading images...',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CREATE A NEW LISTING',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Listing Intent Selector (Looking For vs Offering)
                      Text(
                        'LISTING INTENT',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildIntentChip(
                              intent: MarketplaceTaxonomy.intentLookingFor,
                              label: MarketplaceTaxonomy.labelLookingFor,
                              icon: Icons.search_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildIntentChip(
                              intent: MarketplaceTaxonomy.intentOffering,
                              label: MarketplaceTaxonomy.labelOffering,
                              icon: Icons.storefront_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Category Dropdown (displays only the 8 categories for chosen intent)
                      Text(
                        'CATEGORY',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedCategory,
                        dropdownColor: AppTheme.cardBackground,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        items: categories.map((cat) {
                          return DropdownMenuItem<String>(
                            value: cat.id,
                            child: Text(cat.label),
                          );
                        }).toList(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a category';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedCategory = value);
                          }
                        },
                      ),
                      const SizedBox(height: 20),

                      // Offering Transaction Type (if offering)
                      if (_selectedIntent == MarketplaceTaxonomy.intentOffering) ...[
                        Text(
                          'OFFERING TYPE',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedType,
                          dropdownColor: AppTheme.cardBackground,
                          style: GoogleFonts.inter(color: Colors.white),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          items: _offeringTypes.entries.map((entry) {
                            return DropdownMenuItem(value: entry.key, child: Text(entry.value));
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedType = value);
                            }
                          },
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Image Selector Section
                      Text(
                        'PHOTOS (OPTIONAL, UP TO 5)',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildImageSelector(),
                      const SizedBox(height: 24),

                      // Listing Title
                      Text(
                        'TITLE',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'e.g., Fender Stratocaster 2021',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a title';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Price & City Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PRICE (KR) (0 FOR FREE)',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textSecondary,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _priceController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.inter(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'e.g., 4500',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Please enter a price';
                                    }
                                    final parsed = double.tryParse(value);
                                    if (parsed == null || parsed < 0) {
                                      return 'Must be >= 0';
                                    }
                                    return null;
                                  },
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
                                  'CITY / LOCATION',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textSecondary,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _cityController,
                                  style: GoogleFonts.inter(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'e.g., Stockholm',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Please enter location';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Description
                      Text(
                        'DESCRIPTION',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 5,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Provide all necessary details (condition, accessories, features, availability)...',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a description';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Submit Button
                      AnimatedTapDetector(
                        onTap: _submitForm,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
                            child: Text(
                              'Publish Listing',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildIntentChip({
    required String intent,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedIntent == intent;
    return InkWell(
      onTap: () {
        if (_selectedIntent != intent) {
          setState(() {
            _selectedIntent = intent;
            _ensureValidCategory();
          });
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryAccent.withOpacity(0.15)
              : AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppTheme.primaryAccent : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSelector() {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length < 5 ? _selectedImages.length + 1 : 5,
        itemBuilder: (context, index) {
          if (index == _selectedImages.length && _selectedImages.length < 5) {
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AnimatedTapDetector(
                onTap: _showImagePickerOptions,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppTheme.primaryAccent,
                      size: 28,
                    ),
                  ),
                ),
              ),
            );
          }

          final imageFile = _selectedImages[index];

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: kIsWeb
                      ? Image.network(
                          imageFile.path,
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          File(imageFile.path),
                          fit: BoxFit.cover,
                        ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: AnimatedTapDetector(
                    onTap: () => _removeImage(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
