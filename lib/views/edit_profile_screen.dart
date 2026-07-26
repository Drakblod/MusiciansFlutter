import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _locationController = TextEditingController();
  final _aboutController = TextEditingController();
  final _collabBioController = TextEditingController();
  final _spotifyController = TextEditingController();
  final _youtubeController = TextEditingController();
  
  List<String> _selectedInstruments = [];
  List<String> _mainSkills = [];
  List<String> _selectedGenres = [];
  bool _isSaving = false;

  String? _profilePictureUrl;
  bool _isUploadingProfilePic = false;

  String? _audioSnippetUrl;
  String? _pickedAudioFileName;
  bool _isUploadingAudio = false;

  // 1. Instruments
  static final Map<String, List<String>> _instrumentsCategoryMap = {
    '🎷 Woodwinds': [
      'Flute', 'Piccolo Flute', 'Alto Flute', 'Bass Flute',
      'Oboe', 'English Horn', 'Clarinet', 'Eb Clarinet', 'Alto Clarinet', 'Bass Clarinet',
      'Bassoon', 'Contra Bassoon', 'Soprano Sax', 'Alto Sax', 'Tenor Sax', 'Bari Sax',
      'Recorder', 'Soprano Recorder', 'Alto Recorder', 'Tenor Recorder', 'Bass Recorder'
    ],
    '🎺 Brass': [
      'Trumpet', 'Cornet', 'Piccolo Trumpet', 'Trombone', 'Alto Trombone',
      'French Horn', 'Euphonium', 'Tuba'
    ],
    '🎻 Strings': [
      'Acoustic Guitar', 'Electric Guitar', 'Electric Bass', 'Violin', 'Viola', 'Cello',
      'Contrabass', 'Harp', 'Viola da Gamba', 'Steel Guitar', 'Steel Pan'
    ],
    '🎹 Keyboards': [
      'Piano', 'Keyboard/Synth', 'Harpsichord', 'Organ (Hammond)'
    ],
    '🥁 Percussion': [
      'Drums', 'Latin Percussion (congas, timbales, etc)', 'Classical Percussion (timpani, cymbals, etc)'
    ],
  };

  // 2. Voices
  static final Map<String, List<String>> _voicesCategoryMap = {
    '🗣️ Voices (Choir)': [
      'Soprano', 'Alto', 'Tenor', 'Baritone', 'Bass'
    ],
    '🎼 Misc Voices (Classical & Choir)': [
      'Mezzo Soprano', 'Contralto', 'Counter Tenor'
    ],
    '🎙️ Voices (Popular Music)': [
      'Male Lead Vocals', 'Female Lead vocals', 'Male Backing vocals', 'Female Backing vocals'
    ],
  };

  // 3. Songwriters/Producers, etc
  static final Map<String, List<String>> _songwritersCategoryMap = {
    '🎧 Songwriters & Producers': [
      'Songwriter', 'Producer', 'Composer', 'Lyricist', 'Beatmaker', 'DJ', 'Other'
    ],
  };

  // 4. Studios/Engineers
  static final Map<String, List<String>> _studiosCategoryMap = {
    '🎛️ Studios & Engineers': [
      'Studio', 'Home Studio', 'Recording Engineer', 'Mix engineer', 'Live Engineer', 'Other'
    ],
  };

  // 5. PR & Management
  static final Map<String, List<String>> _prManagementCategoryMap = {
    '💼 PR & Management': [
      'Manager', 'Promotor', 'Agency', 'Other'
    ],
  };

  // PDF Specified Genre & Band Types Categories
  static final Map<String, List<String>> _genreCategoryMap = {
    '🎸 Rock, Pop, R&B, Hip Hop, etc': [
      'Rock',
      'Pop',
      'R&B',
      'Hip Hop',
      'Electronic Dance Music (EDM)',
      'Soul',
      'Funk',
      'Country',
      'Reggae',
      'Latin',
      'Indie / Alternative',
    ],
    '🗣️ Choir': [
      'Choir',
      'Medieval',
      'Renaissance',
      'Baroque',
      'Classical',
      'Romanticism',
      'Impressionism',
      'Modernism',
      'Contemporary',
      'Barbershop',
      'Gospel',
      'Pop',
    ],
    '🎼 Classical': [
      'Classical',
      'Medieval',
      'Renaissance',
      'Baroque',
      'Romanticism',
      'Impressionism',
      'Modernism',
      'Contemporary',
    ],
    '🎺 Wind, Concert & Brass Band': [
      'Wind Band',
      'Concert Band',
      'Brass Band',
      'Classical',
      'March & Ceremonial',
      'Contemporary',
      'Film & Popular',
      'Crossover',
    ],
    '🎷 Jazz': [
      'Jazz',
      'New Orleans/Dixieland',
      'Swing',
      'Bebop',
      'Cool',
      'Hardbop',
      'Free Jazz/Avantgarde',
      'Fusion',
      'Latin',
      'Modern/Contemporary',
    ],
    '🥁 Big Band': [
      'Big Band',
      'Mainstream (Basie, Miller, Sinatra, etc)',
      'New Orleans/Dixieland',
      'Swing',
      'Bebop',
      'Latin',
      'Fusion',
      'Modern/Contemporary',
      'Free Jazz/Avantgarde',
    ],
    '🌍 World Music': [
      'African',
      'Latin',
      'Caribbean',
      'Middle Eastern & Arabic',
      'South Asian',
      'East Asian',
      'Celtic & European',
      'Indigenous',
      'Global Fusion',
    ],
  };

  int _countSelectedForMap(Map<String, List<String>> categoryMap) {
    int count = 0;
    for (final list in categoryMap.values) {
      for (final item in list) {
        if (_selectedInstruments.contains(item)) {
          count++;
        }
      }
    }
    return count;
  }

  Future<void> _openCategoryPicker(String title, Map<String, List<String>> categoryMap) async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: title,
      categoryMap: categoryMap,
      initialSelected: _selectedInstruments,
    );
    if (result != null) {
      setState(() {
        _selectedInstruments = result;
        _mainSkills.removeWhere((skill) => !_selectedInstruments.contains(skill));
        if (_mainSkills.isEmpty && _selectedInstruments.isNotEmpty) {
          _mainSkills = [_selectedInstruments.first];
        }
      });
    }
  }

  Future<void> _openGenrePicker() async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Select Genres/Band Types',
      categoryMap: _genreCategoryMap,
      initialSelected: _selectedGenres,
    );
    if (result != null) {
      setState(() {
        _selectedGenres = result;
      });
    }
  }

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
      _emailController.text = user.email ?? appState.firebaseService.currentUser?.email ?? '';
      _locationController.text = user.location ?? '';
      _aboutController.text = user.about ?? '';
      _collabBioController.text = user.collabBio ?? '';
      _spotifyController.text = user.spotifyUrl ?? '';
      _youtubeController.text = user.youtubeUrl ?? '';
      _profilePictureUrl = user.profilePictureUrl;
      _audioSnippetUrl = user.audioSnippetUrl;
      if (user.audioSnippetUrl != null) {
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

      if (user.mainInstrument != null && user.mainInstrument!.isNotEmpty) {
        final parsed = user.mainInstrument!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        _mainSkills = parsed.where((item) => _selectedInstruments.contains(item)).take(3).toList();
      }
      if (_mainSkills.isEmpty && _selectedInstruments.isNotEmpty) {
        _mainSkills = [_selectedInstruments.first];
      }

      _selectedGenres = List<String>.from(user.genres);
    } else {
      _emailController.text = appState.firebaseService.currentUser?.email ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _locationController.dispose();
    _aboutController.dispose();
    _collabBioController.dispose();
    _spotifyController.dispose();
    _youtubeController.dispose();
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

  Future<void> _showImagePickerOptions() async {
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
                  'PROFILE PICTURE',
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
                    _pickAndUploadProfilePicture(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: AppTheme.primaryAccent),
                  title: Text('Choose from Gallery', style: GoogleFonts.inter(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadProfilePicture(ImageSource.gallery);
                  },
                ),
                if (_profilePictureUrl != null && _profilePictureUrl!.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                    title: Text('Remove Photo', style: GoogleFonts.inter(color: AppTheme.danger)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _profilePictureUrl = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile picture removed (save to apply changes)'),
                          backgroundColor: AppTheme.warning,
                        ),
                      );
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

  Future<void> _pickAndUploadProfilePicture([ImageSource source = ImageSource.gallery]) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
      );

      if (image != null) {
        setState(() {
          _isUploadingProfilePic = true;
        });

        final bytes = await image.readAsBytes();
        final appState = Provider.of<AppState>(context, listen: false);
        final userId = appState.currentUserProfile?.userId;
        if (userId == null) {
          throw Exception("User is not logged in");
        }

        final url = await appState.firebaseService.uploadProfilePictureAsync(
          userId,
          bytes,
          kIsWeb ? null : image.path,
        );

        setState(() {
          _profilePictureUrl = url;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture updated!'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload profile picture: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingProfilePic = false;
        });
      }
    }
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
              content: Text('Track uploaded successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload track: $e'),
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

  void _toggleMainSkill(String skill) {
    setState(() {
      if (_mainSkills.contains(skill)) {
        _mainSkills.remove(skill);
      } else {
        if (_mainSkills.length >= 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can select a maximum of 3 Primary Skills'),
              backgroundColor: AppTheme.warning,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          _mainSkills.add(skill);
        }
      }
    });
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
        _mainSkills.remove(instrument);
        if (_mainSkills.isEmpty && _selectedInstruments.isNotEmpty) {
          _mainSkills = [_selectedInstruments.first];
        }
      } else {
        _selectedInstruments.add(instrument);
        if (_mainSkills.length < 3) {
          _mainSkills.add(instrument);
        }
      }
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInstruments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one skill or talent'),
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
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          userType: _mainSkills.isNotEmpty ? _mainSkills.first : (_selectedInstruments.isNotEmpty ? _selectedInstruments.first : 'Electric Guitar'),
          location: _locationController.text.trim(),
          about: _aboutController.text.trim(),
          profilePictureUrl: _profilePictureUrl,
          genres: _selectedGenres,
          instruments: _selectedInstruments,
          spotifyUrl: _spotifyController.text.trim().isEmpty ? null : _spotifyController.text.trim(),
          youtubeUrl: _youtubeController.text.trim().isEmpty ? null : _youtubeController.text.trim(),
          audioSnippetUrl: _audioSnippetUrl,
          collabBio: _collabBioController.text.trim().isEmpty ? null : _collabBioController.text.trim(),
          mainInstrument: _mainSkills.isNotEmpty ? _mainSkills.join(', ') : (_selectedInstruments.isNotEmpty ? _selectedInstruments.first : null),
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

  Widget _buildCategoryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required int selectedCount,
    required VoidCallback onTap,
  }) {
    final hasSelection = selectedCount > 0;
    return AnimatedTapDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasSelection ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
            width: hasSelection ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasSelection
                    ? AppTheme.primaryAccent.withOpacity(0.2)
                    : const Color(0xFF1E1A3A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: hasSelection ? AppTheme.primaryAccent : Colors.white70,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (hasSelection) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$selectedCount selected',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final instrumentsCount = _countSelectedForMap(_instrumentsCategoryMap);
    final voicesCount = _countSelectedForMap(_voicesCategoryMap);
    final songwritersCount = _countSelectedForMap(_songwritersCategoryMap);
    final studiosCount = _countSelectedForMap(_studiosCategoryMap);
    final prCount = _countSelectedForMap(_prManagementCategoryMap);

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
              const SizedBox(height: 20),

              // Profile Picture Avatar Header
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        GestureDetector(
                          onTap: _showImagePickerOptions,
                          child: Container(
                            width: 105,
                            height: 105,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.primaryAccent, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryAccent.withOpacity(0.3),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _isUploadingProfilePic
                                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                                  : _profilePictureUrl != null && _profilePictureUrl!.isNotEmpty
                                      ? Image.network(
                                          _profilePictureUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, stack) => const Icon(
                                            Icons.person_rounded,
                                            size: 60,
                                            color: Colors.white70,
                                          ),
                                        )
                                      : Container(
                                          color: AppTheme.cardBackground,
                                          child: const Icon(
                                            Icons.person_rounded,
                                            size: 60,
                                            color: Colors.white70,
                                          ),
                                        ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _showImagePickerOptions,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryAccent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _showImagePickerOptions,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _profilePictureUrl != null ? 'Change Profile Picture' : 'Upload Profile Picture',
                        style: GoogleFonts.inter(
                          color: AppTheme.primaryAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 1. Profile Name
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

              // 2. Email Address
              Text(
                'Email Address',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'alex.hill@example.com',
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Please enter a valid email address';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 3. Location (incl. country)
              Text(
                'Location (incl. country)',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Stockholm, Sweden',
                ),
              ),
              const SizedBox(height: 24),

              // 4. Skills/Talents (5 Main Category Cards)
              Text(
                'Skills/Talents',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a category below to select your instruments, voices, or roles.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              _buildCategoryCard(
                title: 'Instruments',
                subtitle: 'Woodwinds, Brass, Strings, Keyboards, Percussion',
                icon: Icons.music_note_rounded,
                selectedCount: instrumentsCount,
                onTap: () => _openCategoryPicker('Select Instruments', _instrumentsCategoryMap),
              ),
              const SizedBox(height: 10),
              _buildCategoryCard(
                title: 'Voices',
                subtitle: 'Choir, Classical & Popular Music Vocals',
                icon: Icons.mic_rounded,
                selectedCount: voicesCount,
                onTap: () => _openCategoryPicker('Select Voices', _voicesCategoryMap),
              ),
              const SizedBox(height: 10),
              _buildCategoryCard(
                title: 'Songwriters/Producers, etc',
                subtitle: 'Songwriter, Producer, Composer, Lyricist, Beatmaker, DJ',
                icon: Icons.headphones_rounded,
                selectedCount: songwritersCount,
                onTap: () => _openCategoryPicker('Select Songwriters/Producers', _songwritersCategoryMap),
              ),
              const SizedBox(height: 10),
              _buildCategoryCard(
                title: 'Studios/Engineers',
                subtitle: 'Studio, Home Studio, Recording, Mix & Live Engineers',
                icon: Icons.tune_rounded,
                selectedCount: studiosCount,
                onTap: () => _openCategoryPicker('Select Studios/Engineers', _studiosCategoryMap),
              ),
              const SizedBox(height: 10),
              _buildCategoryCard(
                title: 'PR & Management',
                subtitle: 'Manager, Promotor, Agency',
                icon: Icons.work_outline_rounded,
                selectedCount: prCount,
                onTap: () => _openCategoryPicker('Select PR & Management', _prManagementCategoryMap),
              ),
              const SizedBox(height: 24),

              // 5. Primary Skill/Talents
              if (_selectedInstruments.isNotEmpty) ...[
                Text(
                  'Primary Skill/Talents',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to input max. 3 Primary Skills/Talents. Put your No. 1 Skill/Instrument, etc first...',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedInstruments.map((skill) {
                    final isMain = _mainSkills.contains(skill);
                    return FilterChip(
                      label: Text(skill),
                      selected: isMain,
                      onSelected: (_) => _toggleMainSkill(skill),
                      selectedColor: AppTheme.primaryAccent,
                      backgroundColor: AppTheme.cardBackground,
                      checkmarkColor: Colors.white,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
                        color: Colors.white,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(
                        color: isMain ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // 6. Secondary Skills/Talents
                Text(
                  'Secondary Skills/Talents',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to input your secondary Skills/Talents...',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final secondarySkills = _selectedInstruments
                        .where((skill) => !_mainSkills.contains(skill))
                        .toList();
                    if (secondarySkills.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF231F45)),
                        ),
                        child: Text(
                          'All selected skills are assigned as Primary Skills.',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: secondarySkills.map((skill) {
                        return Chip(
                          label: Text(skill),
                          onDeleted: () => _toggleInstrument(skill),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                          backgroundColor: const Color(0xFF1E1A3A),
                          labelStyle: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: const BorderSide(color: Color(0xFF2E2A4E)),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],

              // 7. Genres/Band Types
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Genres/Band Types',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  AnimatedTapDetector(
                    onTap: _openGenrePicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune_rounded, color: AppTheme.primaryAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _selectedGenres.isEmpty ? 'Select Genres' : 'Edit (${_selectedGenres.length})',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_selectedGenres.isEmpty)
                AnimatedTapDetector(
                  onTap: _openGenrePicker,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF231F45)),
                    ),
                    child: Text(
                      'No genres selected yet. Tap to add your musical styles...',
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedGenres.map((genre) {
                    return InputChip(
                      label: Text(genre),
                      selected: false,
                      onDeleted: () => _toggleGenre(genre),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                      backgroundColor: AppTheme.cardBackground,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: const BorderSide(color: AppTheme.primaryAccent),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 24),

              // 8. About
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
                  hintText: 'Tell other musicians about your musical journey, experience, and gear...',
                ),
              ),
              const SizedBox(height: 24),

              // 9. Collaborations
              Text(
                'Collaborations',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Specify what types of collaborations you are open to.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _collabBioController,
                maxLines: 3,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: "I'm looking for the following collaboration(s)...",
                ),
              ),
              const SizedBox(height: 24),

              // 10. Social Links
              Text(
                'Social Links',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              
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
              const SizedBox(height: 16),

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
              const SizedBox(height: 24),

              // 11. Track
              Text(
                'Track',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Upload an MP3 track of your own music to play on your profile.',
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
                            'Uploading ${_pickedAudioFileName ?? "track"}...',
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
                                      _pickedAudioFileName ?? 'track.mp3',
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
                                      'Track loaded',
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
                                tooltip: 'Change track',
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
                                      content: Text('Track removed from profile (save to apply changes)'),
                                      backgroundColor: AppTheme.warning,
                                    ),
                                  );
                                },
                                tooltip: 'Remove track',
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
                                    'Upload MP3 Track',
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
              const SizedBox(height: 30),

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
