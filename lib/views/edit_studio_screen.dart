import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/collab_studio.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class EditStudioScreen extends StatefulWidget {
  const EditStudioScreen({super.key});

  @override
  State<EditStudioScreen> createState() => _EditStudioScreenState();
}

class _EditStudioScreenState extends State<EditStudioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _facilitiesController = TextEditingController();
  final _contactInfoController = TextEditingController();

  List<String> _selectedGenres = [];
  bool _isSaving = false;
  CollabStudio? _existingStudio;
  bool _initialized = false;

  final List<String> _genresList = [
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
    "Reggae",
    "Alternative",
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is CollabStudio) {
        _existingStudio = args;
        _nameController.text = args.name;
        _descriptionController.text = args.description;
        _locationController.text = args.location;
        _facilitiesController.text = args.facilities ?? '';
        _contactInfoController.text = args.contactInfo ?? '';
        _selectedGenres = List<String>.from(args.genres);
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _facilitiesController.dispose();
    _contactInfoController.dispose();
    super.dispose();
  }

  void _toggleGenre(String genre) {
    setState(() {
      if (_selectedGenres.contains(genre)) {
        _selectedGenres.remove(genre);
      } else {
        _selectedGenres.add(genre);
      }
    });
  }

  Future<void> _saveStudio() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;

    if (userId == null) {
      setState(() => _isSaving = false);
      return;
    }

    // Ownership check for edits
    if (_existingStudio != null && _existingStudio!.creatorId != userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unauthorized: You do not own this studio listing'),
          backgroundColor: AppTheme.danger,
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    try {
      final studio = CollabStudio(
        id: _existingStudio?.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        genres: _selectedGenres,
        facilities: _facilitiesController.text.trim().isEmpty
            ? null
            : _facilitiesController.text.trim(),
        contactInfo: _contactInfoController.text.trim().isEmpty
            ? null
            : _contactInfoController.text.trim(),
        creatorId: _existingStudio?.creatorId ?? userId,
        createdAt: _existingStudio?.createdAt ?? 0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await appState.firebaseService.saveCollabStudioAsync(studio);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Studio listing saved successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save studio: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = _existingStudio != null;

    return GradientScaffold(
      appBar: const CustomTopBar(showBack: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          physics: const BouncingScrollPhysics(),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditMode ? 'EDIT STUDIO' : 'ADD STUDIO LISTING',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Studio Name
                Text(
                  'Studio Name *',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Abbey Road Stockholm',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter the studio name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Location
                Text(
                  'Location *',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _locationController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Stockholm, Sweden',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter location';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Description
                Text(
                  'Studio Description *',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText:
                        'Describe your studio facility, acoustics, vibe, and specialties...',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Genres Specialties selector
                Text(
                  'Specialty Genres',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _genresList.map((genre) {
                    final isSelected = _selectedGenres.contains(genre);
                    return ChoiceChip(
                      label: Text(genre),
                      selected: isSelected,
                      onSelected: (_) => _toggleGenre(genre),
                      selectedColor: AppTheme.primaryAccent,
                      backgroundColor: AppTheme.cardBackground,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: Colors.white,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.primaryAccent
                            : const Color(0xFF2E2A4E),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Facilities & Gear Description
                Text(
                  'Facilities & Gear list',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _facilitiesController,
                  maxLines: 4,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText:
                        'List your console, DAW, monitors, mics, instruments, preamps...',
                  ),
                ),
                const SizedBox(height: 20),

                // Booking / Contact Info
                Text(
                  'Contact / Booking Instructions',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _contactInfoController,
                  maxLines: 2,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. Email at studio@example.com or visit www.studio.com',
                  ),
                ),
                const SizedBox(height: 32),

                // Save Button
                _isSaving
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryAccent,
                        ),
                      )
                    : AnimatedTapDetector(
                        onTap: _saveStudio,
                        child: Container(
                          height: 55,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              isEditMode ? 'Save Changes' : 'Publish Listing',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
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
