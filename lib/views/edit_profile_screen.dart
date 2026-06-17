import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../widgets/gradient_scaffold.dart';
import '../services/location_service.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _aboutController = TextEditingController();
  
  List<String> _selectedInstruments = [];
  List<String> _selectedGenres = [];
  bool _isSaving = false;
  bool _showAllInstruments = false;
  bool _showAllGenres = false;
  bool _isFetchingLocation = false;

  Future<void> _testLocation() async {
    setState(() {
      _isFetchingLocation = true;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUserId;
      if (userId == null) {
        throw Exception("User not logged in");
      }

      final locationService = LocationService();
      final result = await locationService.getCurrentLocationAsync();

      await appState.firebaseService.updateCurrentUserLocationAsync(
        userId,
        result.latitude,
        result.longitude,
        result.displayName,
        result.city,
        result.country,
      );

      await appState.refreshProfile();

      if (mounted) {
        setState(() {
          _locationController.text = result.displayName;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.displayName),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errMsg = e.toString();
        if (errMsg.startsWith("Exception: ")) {
          errMsg = errMsg.substring(11);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Location Error: $errMsg"),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
        });
      }
    }
  }

  final List<String> _roles = [
    "BANDLEADER",
    "PRODUCER",
    "Vocalist",
    "Recorder",
    "Flute",
    "Oboe",
    "Clarinet",
    "Bassoon",
    "Soprano Sax",
    "Alto Sax",
    "Tenor Sax",
    "Bari Sax",
    "Trumpet",
    "Cornet",
    "Trombone",
    "French Horn",
    "Euphonium",
    "Tuba",
    "Violin",
    "Viola",
    "Cello",
    "Contrabass",
    "Acoustic Guitar",
    "Electric Guitar",
    "Electric Bass",
    "Harp",
    "Piano",
    "Keyboard/Synth",
    "Harpsichord",
    "Organ (Hammond)",
    "Drums",
    "Latin Percussion",
    "Classical Percussion",
    "Soprano Recorder",
    "Alto Recorder",
    "Tenor Recorder",
    "Bass Recorder",
    "Piccolo Flute",
    "Alto Flute",
    "Bass Flute",
    "English Horn",
    "Eb Clarinet",
    "Alto Clarinet",
    "Bass Clarinet",
    "Contra Bassoon",
    "Piccolo Trumpet",
    "Alto Trombone",
    "Viola da Gamba",
    "Steel Guitar",
    "Steel Pan"
  ];

  final List<String> _genresList = [
    "All styles",
    "Salsa",
    "Fusion",
    "20's-40's",
    "Classical",
    "Pop",
    "K-pop",
    "Mainstream Rock",
    "Hard Rock",
    "Metal",
    "Death Metal",
    "Psychedelic",
    "Rock and Roll",
    "Rockabilly",
    "Punk",
    "Grunge",
    "Soul",
    "Reggae",
    "Glam Rock",
    "Blues-Rock",
    "Country",
    "Hip-Hop",
    "Trip-hop",
    "Balkan",
    "Klezmer",
    "A Capella",
    "Chamber",
    "Men's choir",
    "Women's choir",
    "Children's choir",
    "Gospel",
    "Barbershop",
    "Madrigals",
    "Gregorian",
    "Mixing",
    "Mastering"
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  void _loadCurrentProfile() {
    final appState = Provider.of<AppState>(context, listen: false);
    final user = appState.currentUserProfile;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _locationController.text = user.location ?? '';
      _aboutController.text = user.about ?? '';
      
      _selectedInstruments = List<String>.from(user.instruments);
      final role = user.userType ?? '';
      if (role.isNotEmpty && !_selectedInstruments.contains(role)) {
        _selectedInstruments.add(role);
      }
      _selectedGenres = List<String>.from(user.genres);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _aboutController.dispose();
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

  void _toggleInstrument(String instrument) {
    setState(() {
      if (_selectedInstruments.contains(instrument)) {
        _selectedInstruments.remove(instrument);
      } else {
        _selectedInstruments.add(instrument);
      }
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInstruments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one instrument/role'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final appState = Provider.of<AppState>(context, listen: false);

    try {
      final user = appState.currentUserProfile;
      if (user != null) {
        final updatedProfile = UserProfile(
          userId: user.userId,
          nickname: user.nickname,
          displayName: _nameController.text.trim(),
          userType: _selectedInstruments.isNotEmpty ? _selectedInstruments.first : 'Electric Guitar',
          location: _locationController.text.trim(),
          about: _aboutController.text.trim(),
          profilePictureUrl: user.profilePictureUrl,
          genres: _selectedGenres,
          instruments: _selectedInstruments,
        );

        await appState.firebaseService.saveUserProfileAsync(user.userId ?? '', updatedProfile);
        await appState.refreshProfile();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        physics: const BouncingScrollPhysics(),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EDIT PROFILE',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              // Display Name
              Text(
                'Display Name',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Alex Hill',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your display name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Instruments Selection
              Text(
                'Instruments/Roles',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (_showAllInstruments
                        ? _roles
                        : _roles.where((i) => _selectedInstruments.contains(i) || _roles.indexOf(i) < 8).toList())
                    .map((instrument) {
                  final isSelected = _selectedInstruments.contains(instrument);
                  return ChoiceChip(
                    label: Text(instrument),
                    selected: isSelected,
                    onSelected: (_) => _toggleInstrument(instrument),
                    selectedColor: AppTheme.primaryAccent,
                    backgroundColor: AppTheme.cardBackground,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAllInstruments = !_showAllInstruments;
                  });
                },
                icon: Icon(
                  _showAllInstruments ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.primaryAccent,
                  size: 20,
                ),
                label: Text(
                  _showAllInstruments ? 'Show Less' : 'Show More',
                  style: GoogleFonts.inter(
                    color: AppTheme.primaryAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(height: 20),

              // Location
              Text(
                'Location',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Stockholm, Sweden',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your location';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              // Test Location Button
              _isFetchingLocation
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppTheme.primaryAccent,
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _testLocation,
                      icon: const Icon(Icons.my_location, color: AppTheme.primaryAccent, size: 18),
                      label: Text(
                        'Test Location',
                        style: GoogleFonts.inter(
                          color: AppTheme.primaryAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
              const SizedBox(height: 20),

              // About Me
              Text(
                'About Me',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _aboutController,
                maxLines: 4,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Tell other musicians about your musical journey, experience, or what bands you are looking for...',
                ),
              ),
              const SizedBox(height: 24),

              // Genres selection list
              Text(
                'Genres',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (_showAllGenres
                        ? _genresList
                        : _genresList.where((g) => _selectedGenres.contains(g) || _genresList.indexOf(g) < 8).toList())
                    .map((genre) {
                  final isSelected = _selectedGenres.contains(genre);
                  return ChoiceChip(
                    label: Text(genre),
                    selected: isSelected,
                    onSelected: (_) => _toggleGenre(genre),
                    selectedColor: AppTheme.primaryAccent,
                    backgroundColor: AppTheme.cardBackground,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAllGenres = !_showAllGenres;
                  });
                },
                icon: Icon(
                  _showAllGenres ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.primaryAccent,
                  size: 20,
                ),
                label: Text(
                  _showAllGenres ? 'Show Less' : 'Show More',
                  style: GoogleFonts.inter(
                    color: AppTheme.primaryAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(height: 40),

              // Save Button
              _isSaving
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                  : AnimatedTapDetector(
                      onTap: _saveProfile,
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryAccent.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Save Profile',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
