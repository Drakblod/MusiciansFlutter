import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../widgets/gradient_scaffold.dart';
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
  final _spotifyController = TextEditingController();
  final _youtubeController = TextEditingController();
  
  List<String> _selectedInstruments = [];
  List<String> _selectedGenres = [];
  bool _isSaving = false;
  bool _showAllInstruments = false;
  bool _showAllGenres = false;

  String? _audioSnippetUrl;
  String? _pickedAudioFileName;
  bool _isUploadingAudio = false;

  List<String> _selectedCollabRoles = [];
  bool _collabRemote = false;
  final _collabBioController = TextEditingController();

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
      _spotifyController.text = user.spotifyUrl ?? '';
      _youtubeController.text = user.youtubeUrl ?? '';
      _audioSnippetUrl = user.audioSnippetUrl;
      if (user.audioSnippetUrl != null) {
        // extract file name or use a default label
        try {
          final uri = Uri.parse(user.audioSnippetUrl!);
          final name = uri.pathSegments.last;
          _pickedAudioFileName = name.contains('/') ? name.split('/').last : name;
        } catch (_) {
          _pickedAudioFileName = 'audio_snippet.mp3';
        }
      }
      
      _selectedInstruments = List<String>.from(user.instruments);
      final role = user.userType ?? '';
      if (role.isNotEmpty && !_selectedInstruments.contains(role)) {
        _selectedInstruments.add(role);
      }
      _selectedGenres = List<String>.from(user.genres);
      _selectedCollabRoles = List<String>.from(user.collabRoles);
      _collabRemote = user.collabRemote;
      _collabBioController.text = user.collabBio ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _aboutController.dispose();
    _spotifyController.dispose();
    _youtubeController.dispose();
    _collabBioController.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value, String platform) {
    if (value == null || value.trim().isEmpty) return null;
    final url = value.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAbsolutePath || !(uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'spotify' || uri.scheme == 'youtube')) {
      return 'Please enter a valid URL (starting with http:// or https://)';
    }
    if (platform == 'Spotify' && !url.toLowerCase().contains('spotify.com') && !url.toLowerCase().contains('spotify:')) {
      return 'Please enter a valid Spotify link';
    }
    if (platform == 'YouTube' && !url.toLowerCase().contains('youtube.com') && !url.toLowerCase().contains('youtu.be') && !url.toLowerCase().contains('youtube:')) {
      return 'Please enter a valid YouTube link';
    }
    return null;
  }

  Future<void> _pickAndUploadAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3'],
        withData: true,
      );

      if (result != null) {
        final file = result.files.single;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        setState(() {
          _isUploadingAudio = true;
          _pickedAudioFileName = file.name;
        });

        final appState = Provider.of<AppState>(context, listen: false);
        final userId = appState.currentUserProfile?.userId;
        if (userId == null) {
          throw Exception("User is not logged in");
        }

        // Upload to storage
        final url = await appState.firebaseService.uploadAudioSnippetAsync(
          userId,
          bytes,
          file.path,
        );

        setState(() {
          _audioSnippetUrl = url;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio snippet uploaded successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload audio: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAudio = false;
        });
      }
    }
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
          spotifyUrl: _spotifyController.text.trim().isEmpty ? null : _spotifyController.text.trim(),
          youtubeUrl: _youtubeController.text.trim().isEmpty ? null : _youtubeController.text.trim(),
          audioSnippetUrl: _audioSnippetUrl,
          collabRoles: _selectedCollabRoles,
          collabRemote: _collabRemote,
          collabBio: _collabBioController.text.trim().isEmpty ? null : _collabBioController.text.trim(),
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
              // Profile Name
              Text(
                'Profile Name',
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
                    return 'Please enter your profile name';
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
              const SizedBox(height: 20),

              // About
              Text(
                'About',
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

              // Social Links Section
              Text(
                'SOCIAL LINKS',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              
              // Spotify URL
              Text(
                'Spotify Profile or Track Link',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _spotifyController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'https://open.spotify.com/artist/...',
                  prefixIcon: Icon(Icons.music_note, color: Colors.green),
                ),
                validator: (value) => _validateUrl(value, 'Spotify'),
              ),
              const SizedBox(height: 20),

              // YouTube URL
              Text(
                'YouTube Channel or Video Link',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _youtubeController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'https://www.youtube.com/...',
                  prefixIcon: Icon(Icons.play_circle_fill, color: Colors.red),
                ),
                validator: (value) => _validateUrl(value, 'YouTube'),
              ),
              const SizedBox(height: 32),

              // Audio Snippet Section
              Text(
                'AUDIO SNIPPET',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Upload a short MP3 snippet of your own music to play on your profile.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: _isUploadingAudio
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: AppTheme.primaryAccent),
                          const SizedBox(height: 12),
                          Text(
                            'Uploading ${_pickedAudioFileName ?? "audio snippet"}...',
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      )
                    : _audioSnippetUrl != null
                        ? Row(
                            children: [
                              const Icon(Icons.audiotrack_rounded, color: AppTheme.primaryAccent, size: 36),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _pickedAudioFileName ?? 'audio_snippet.mp3',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Audio snippet loaded',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.success,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, color: AppTheme.primaryAccent),
                                onPressed: _pickAndUploadAudio,
                                tooltip: 'Change snippet',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.danger),
                                onPressed: () {
                                  setState(() {
                                    _audioSnippetUrl = null;
                                    _pickedAudioFileName = null;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Audio snippet removed from profile (save to apply changes)'),
                                      backgroundColor: AppTheme.warning,
                                    ),
                                  );
                                },
                                tooltip: 'Remove snippet',
                              ),
                            ],
                          )
                        : InkWell(
                            onTap: _pickAndUploadAudio,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.cloud_upload_outlined,
                                    color: AppTheme.textSecondary,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Upload MP3 Snippet',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Only MP3 files supported',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
              // Collabs Section
              const SizedBox(height: 30),
              Text(
                'COLLABORATION SETTINGS',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),

              // Collab Roles Checkboxes
              Text(
                'Collaboration Roles',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Songwriter', 'Producer', 'Engineer'].map((role) {
                  final key = role.toLowerCase();
                  final isSelected = _selectedCollabRoles.contains(key);
                  return ChoiceChip(
                    label: Text(role),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedCollabRoles.add(key);
                        } else {
                          _selectedCollabRoles.remove(key);
                        }
                      });
                    },
                    selectedColor: AppTheme.primaryAccent,
                    backgroundColor: AppTheme.cardBackground,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Remote Switch
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remote Collaboration',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Are you available for remote work?',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  Switch(
                    value: _collabRemote,
                    onChanged: (val) {
                      setState(() {
                        _collabRemote = val;
                      });
                    },
                    activeColor: AppTheme.primaryAccent,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Collab Bio Description
              Text(
                'Collaboration Bio / Details',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _collabBioController,
                maxLines: 3,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Share what gear you use, your songwriting process, or what you are looking for in collabs...',
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
