import 'dart:io' show File;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../data/genres_taxonomy.dart';
import '../models/public_calendar_event.dart';
import '../providers/app_state.dart';
import '../repositories/public_event_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';

class CreatePublicEventScreen extends StatefulWidget {
  final PublicEventRepository? repository;

  const CreatePublicEventScreen({
    super.key,
    this.repository,
  });

  @override
  State<CreatePublicEventScreen> createState() => _CreatePublicEventScreenState();
}

class _CreatePublicEventScreenState extends State<CreatePublicEventScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _organizerController = TextEditingController();
  final TextEditingController _venueController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _shortDescController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();

  PublicEventType _selectedType = PublicEventType.liveGig;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 2));
  TimeOfDay _startTime = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);

  bool _isFree = false;
  List<String> _selectedGenres = [];
  bool _isSaving = false;

  final ImagePicker _picker = ImagePicker();
  XFile? _selectedCoverImage;
  Uint8List? _coverImageBytes;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    final userProfile = appState.currentUserProfile;
    final name = userProfile?.displayName?.trim();
    if (name != null && name.isNotEmpty) {
      _organizerController.text = name;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizerController.dispose();
    _venueController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _priceController.dispose();
    _shortDescController.dispose();
    _descController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: AppTheme.cardBackground,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: AppTheme.cardBackground,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: AppTheme.cardBackground,
              onSurface: Colors.white,
            ),
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: AppTheme.cardBackground,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _startTime = picked;
        // Auto adjust end time if before start time
        if (_endTime.hour < _startTime.hour ||
            (_endTime.hour == _startTime.hour && _endTime.minute <= _startTime.minute)) {
          _endTime = TimeOfDay(
            hour: (_startTime.hour + 2) % 24,
            minute: _startTime.minute,
          );
        }
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: AppTheme.cardBackground,
              onSurface: Colors.white,
            ),
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: AppTheme.cardBackground,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _endTime = picked;
      });
    }
  }

  Future<void> _openGenrePicker() async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Select Genres',
      categoryMap: GenresTaxonomy.categoryMap,
      initialSelected: _selectedGenres,
    );

    if (result != null && mounted) {
      setState(() {
        _selectedGenres = result;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1440,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedCoverImage = image;
          _coverImageBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint("Error picking cover image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access camera or gallery: $e'),
            backgroundColor: Colors.redAccent,
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
            color: const Color(0xFF0F0C22).withValues(alpha: 0.95),
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
                  'CHOOSE COVER PHOTO',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
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
                  leading: const Icon(Icons.photo_library_outlined, color: AppTheme.secondaryAccent),
                  title: Text('Choose from Gallery', style: GoogleFonts.inter(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removeCoverImage() {
    setState(() {
      _selectedCoverImage = null;
      _coverImageBytes = null;
      _imageUrlController.clear();
    });
  }

  Future<void> _saveEvent() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please fill in all required fields.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final currentUid = appState.currentUserProfile?.userId;

      final startDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _startTime.hour,
        _startTime.minute,
      );

      final endDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _endTime.hour,
        _endTime.minute,
      );

      double? price;
      if (!_isFree && _priceController.text.trim().isNotEmpty) {
        price = double.tryParse(_priceController.text.trim().replaceAll(',', '.'));
      }

      final shortDesc = _shortDescController.text.trim().isNotEmpty
          ? _shortDescController.text.trim()
          : (_descController.text.trim().length > 100
              ? '${_descController.text.trim().substring(0, 97)}...'
              : _descController.text.trim());

      String? resolvedImageUrl;
      if (_selectedCoverImage != null) {
        try {
          resolvedImageUrl = await appState.firebaseService.uploadPublicEventCoverImageAsync(_selectedCoverImage!);
        } catch (e) {
          debugPrint("Failed to upload cover image, proceeding without uploaded file: $e");
        }
      } else if (_imageUrlController.text.trim().isNotEmpty) {
        resolvedImageUrl = _imageUrlController.text.trim();
      }

      final newEvent = PublicCalendarEvent(
        id: '',
        title: _titleController.text.trim(),
        shortDescription: shortDesc,
        description: _descController.text.trim(),
        eventType: _selectedType,
        organizerName: _organizerController.text.trim(),
        venueName: _venueController.text.trim(),
        city: _cityController.text.trim(),
        address: _addressController.text.trim(),
        startDateTime: startDateTime,
        endDateTime: endDateTime,
        genres: _selectedGenres,
        priceAmount: price,
        currency: 'SEK',
        isFree: _isFree,
        status: PublicEventStatus.published,
        isMock: false,
        imageUrl: resolvedImageUrl,
        createdBy: currentUid,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final repo = widget.repository ??
          FirebasePublicEventRepository(
            firebaseService: appState.firebaseService,
          );

      await repo.createEvent(newEvent);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Event "${newEvent.title}" published successfully!',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppTheme.primaryAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save event: $e',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Add Event',
        showBack: true,
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ADD TO EVENT CALENDAR',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Publish a gig, jam session, workshop or public music event.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Event Title
                    _buildSectionHeader('EVENT DETAILS'),
                    const SizedBox(height: 10),
                    _buildInputField(
                      controller: _titleController,
                      label: 'Event Title *',
                      hint: 'e.g. Stockholm Live Showcase, Jazz Jam',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a title for the event';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Event Type Selector
                    _buildFieldLabel('Event Type *'),
                    const SizedBox(height: 8),
                    _buildEventTypeSelector(),
                    const SizedBox(height: 20),

                    // Organizer / Host
                    _buildInputField(
                      controller: _organizerController,
                      label: 'Organizer / Band / Host *',
                      hint: 'e.g. The Midnight Band, West Coast Studio',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter organizer name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Location Section
                    _buildSectionHeader('LOCATION & VENUE'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildInputField(
                            controller: _venueController,
                            label: 'Venue Name *',
                            hint: 'e.g. Jazzbaren, Fasching',
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildInputField(
                            controller: _cityController,
                            label: 'City *',
                            hint: 'e.g. Stockholm',
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: _addressController,
                      label: 'Street Address (Optional)',
                      hint: 'e.g. Storgatan 14',
                    ),
                    const SizedBox(height: 24),

                    // Date & Time Section
                    _buildSectionHeader('DATE & TIME'),
                    const SizedBox(height: 10),
                    _buildDateTimePickers(),
                    const SizedBox(height: 24),

                    // Pricing Section
                    _buildSectionHeader('ADMISSION & TICKETS'),
                    const SizedBox(height: 10),
                    _buildPricingSection(),
                    const SizedBox(height: 24),

                    // Genres & Taxonomy Section
                    _buildSectionHeader('GENRES & TAGS'),
                    const SizedBox(height: 10),
                    _buildGenreSelector(),
                    const SizedBox(height: 24),

                    // Cover Image Section (Upload from Camera/Gallery or URL)
                    _buildCoverImageSection(),
                    const SizedBox(height: 24),

                    // Description Section
                    _buildSectionHeader('EVENT INFORMATION'),
                    const SizedBox(height: 10),
                    _buildInputField(
                      controller: _shortDescController,
                      label: 'Short Summary / Headline',
                      hint: 'Brief 1-2 sentence teaser shown on calendar cards...',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: _descController,
                      label: 'Full Description *',
                      hint: 'Detailed program, schedule, line-up, participant details...',
                      maxLines: 5,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please provide a description for the event';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Publish Button
                    Semantics(
                      button: true,
                      label: 'Publish Event',
                      child: AnimatedTapDetector(
                        onTap: _isSaving ? () {} : _saveEvent,
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.primaryAccent, AppTheme.secondaryAccent],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryAccent.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _isSaving
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Publish Event',
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppTheme.secondaryAccent,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white70,
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E2452)),
          ),
          child: TextFormField(
            controller: controller,
            maxLines: maxLines,
            validator: validator,
            inputFormatters: inputFormatters,
            keyboardType: keyboardType,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: InputBorder.none,
              errorStyle: GoogleFonts.inter(color: Colors.redAccent, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverImageSection() {
    final hasImage = _coverImageBytes != null ||
        _selectedCoverImage != null ||
        _imageUrlController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('COVER IMAGE & POSTER'),
        const SizedBox(height: 10),
        if (hasImage) ...[
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.5), width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_coverImageBytes != null)
                  Image.memory(
                    _coverImageBytes!,
                    fit: BoxFit.cover,
                  )
                else if (_selectedCoverImage != null && !kIsWeb)
                  Image.file(
                    File(_selectedCoverImage!.path),
                    fit: BoxFit.cover,
                  )
                else if (_imageUrlController.text.trim().isNotEmpty)
                  Image.network(
                    _imageUrlController.text.trim(),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.broken_image_rounded, color: Colors.amber, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'Could not load image URL',
                            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Overlay controls
                Positioned(
                  top: 10,
                  right: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                          tooltip: 'Change Cover Photo',
                          onPressed: _showImagePickerOptions,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                          tooltip: 'Remove Cover Photo',
                          onPressed: _removeCoverImage,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          AnimatedTapDetector(
            onTap: _showImagePickerOptions,
            child: Container(
              height: 130,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF2E2452),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_rounded,
                        color: AppTheme.primaryAccent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload Cover Photo or Poster',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to choose from Gallery or Camera',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildInputField(
          controller: _imageUrlController,
          label: 'Or paste image link (Optional)',
          hint: 'https://example.com/poster.jpg',
        ),
      ],
    );
  }

  Widget _buildEventTypeSelector() {
    final types = [
      {'type': PublicEventType.liveGig, 'label': 'Live/Gig', 'icon': Icons.music_note_rounded},
      {'type': PublicEventType.openSession, 'label': 'Session', 'icon': Icons.groups_rounded},
      {'type': PublicEventType.workshopCourse, 'label': 'Workshop', 'icon': Icons.school_rounded},
      {'type': PublicEventType.other, 'label': 'Other', 'icon': Icons.event_rounded},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((item) {
        final type = item['type'] as PublicEventType;
        final isSelected = _selectedType == type;
        final label = item['label'] as String;
        final icon = item['icon'] as IconData;

        return AnimatedTapDetector(
          onTap: () {
            setState(() {
              _selectedType = type;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryAccent.withValues(alpha: 0.25)
                  : AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2452),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? AppTheme.primaryAccent : AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateTimePickers() {
    final dateFormat = DateFormat('EEE, d MMM yyyy');
    final formattedDate = dateFormat.format(_selectedDate);

    return Column(
      children: [
        // Date tile
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E2452)),
          ),
          child: ListTile(
            onTap: _pickDate,
            leading: const Icon(Icons.calendar_today_rounded, color: AppTheme.secondaryAccent, size: 20),
            title: Text(
              'Date',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
            ),
            subtitle: Text(
              formattedDate,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 14),
          ),
        ),
        const SizedBox(height: 12),

        // Start & End Time row
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2452)),
                ),
                child: ListTile(
                  onTap: _pickStartTime,
                  leading: const Icon(Icons.access_time_rounded, color: AppTheme.primaryAccent, size: 20),
                  title: Text(
                    'Start Time',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  subtitle: Text(
                    _startTime.format(context),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2452)),
                ),
                child: ListTile(
                  onTap: _pickEndTime,
                  leading: const Icon(Icons.timer_outlined, color: AppTheme.secondaryAccent, size: 20),
                  title: Text(
                    'End Time',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  subtitle: Text(
                    _endTime.format(context),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPricingSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2452)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isFree ? Icons.money_off_rounded : Icons.confirmation_number_rounded,
                    color: _isFree ? Colors.greenAccent : AppTheme.secondaryAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Free Admission',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _isFree,
                onChanged: (val) {
                  setState(() {
                    _isFree = val;
                  });
                },
                activeColor: Colors.greenAccent,
                inactiveThumbColor: Colors.white70,
              ),
            ],
          ),
          if (!_isFree) ...[
            const Divider(color: Color(0xFF2E2452), height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+[\.,]?\d{0,2}')),
                    ],
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Ticket / Admission Price',
                      labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
                      hintText: 'e.g. 150',
                      hintStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2E2452)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2E2452)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.primaryAccent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1A3A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2E2452)),
                  ),
                  child: Text(
                    'SEK',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGenreSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedTapDetector(
          onTap: _openGenrePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E2452)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.style_rounded, color: AppTheme.primaryAccent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _selectedGenres.isEmpty ? 'Select Genres & Tags' : 'Edit Genres (${_selectedGenres.length})',
                      style: GoogleFonts.inter(
                        color: _selectedGenres.isEmpty ? AppTheme.textMuted : Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 14),
              ],
            ),
          ),
        ),
        if (_selectedGenres.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _selectedGenres.map((genre) {
              return Chip(
                label: Text(
                  genre,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                ),
                backgroundColor: AppTheme.primaryAccent.withValues(alpha: 0.2),
                side: const BorderSide(color: AppTheme.primaryAccent),
                deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                onDeleted: () {
                  setState(() {
                    _selectedGenres.remove(genre);
                  });
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
