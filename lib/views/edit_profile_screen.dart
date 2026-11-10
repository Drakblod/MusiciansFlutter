import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../models/city_location.dart';
import '../widgets/city_location_picker_field.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';
import '../widgets/audio_snippet_player.dart';
import '../data/skills_taxonomy.dart';
import '../data/genres_taxonomy.dart';
import '../utils/secondary_skills_utils.dart';
import '../widgets/secondary_skills_editor.dart';
import '../widgets/skill_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  CityLocation? _cityLocation;
  String? _legacyLocation;
  final _aboutController = TextEditingController();
  final _collabBioController = TextEditingController();
  final _spotifyController = TextEditingController();
  final _youtubeController = TextEditingController();
  
  List<String> _primarySkills = [];
  List<String> _secondarySkills = [];
  List<String> _selectedGenres = [];
  late String _level;
  bool _isSaving = false;
  String? _editingUserId;

  final List<String> _levels = [
    'A = PRO',
    'B = SEMI PRO',
    'C = INTERMEDIATE',
    'D = AMATEUR',
    'E = BEGINNER'
  ];

  String? _profilePictureUrl;
  bool _isUploadingProfilePic = false;

  String? _audioSnippetUrl;
  String? _pickedAudioFileName;
  bool _isUploadingAudio = false;

  // PDF Specified Genre & Band Types Categories
  static final Map<String, List<String>> _genreCategoryMap = GenresTaxonomy.categoryMap;

  Future<void> _openPrimarySkillPicker() async {
    final result = await SkillPicker.show(
      context,
      title: 'Primary Skill/Talent (Select 1)',
      taxonomyContext: SkillTaxonomyContext.editProfile,
      selected: _primarySkills,
      singleSelect: true,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _primarySkills = result;
        _secondarySkills = SecondarySkillsUtils.reconcileWithPrimary(
          _secondarySkills, _primarySkills.firstOrNull,
        );
      });
    }
  }

  Future<void> _openGenrePicker() async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Genres/Band Types',
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
    _editingUserId = user?.userId;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _emailController.text = appState.firebaseService.currentUser?.email ?? user.email ?? '';
      _cityLocation = user.publicLocation;
      if (_cityLocation == null) _legacyLocation = user.location;
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
      
      _primarySkills = user.mainSkills;
      _secondarySkills = user.secondarySkills;

      _selectedGenres = List<String>.from(user.genres);
      _level = _levels.contains(user.level) ? user.level! : 'C = INTERMEDIATE';
    } else {
      _emailController.text = appState.firebaseService.currentUser?.email ?? '';
      _level = 'C = INTERMEDIATE';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
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
            color: const Color(0xFF16132D).withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Profile Picture',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primaryAccent),
                  title: Text('Choose from Gallery', style: GoogleFonts.inter(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadProfilePicture(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primaryAccent),
                  title: Text('Take a Photo', style: GoogleFonts.inter(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadProfilePicture(ImageSource.camera);
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
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        final name = file.name;

        if (bytes != null) {
          setState(() {
            _isUploadingAudio = true;
          });

          final appState = Provider.of<AppState>(context, listen: false);
          final userId = appState.currentUserProfile?.userId;
          if (userId == null) throw Exception("User is not logged in");

          final url = await appState.firebaseService.uploadAudioSnippetAsync(
            userId,
            bytes,
            name,
          );

          setState(() {
            _audioSnippetUrl = url;
            _pickedAudioFileName = name;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Track uploaded! Remember to save your profile to keep changes.'),
                backgroundColor: AppTheme.success,
              ),
            );
          }
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

  void _toggleGenre(String genre) {
    setState(() {
      if (_selectedGenres.contains(genre)) {
        _selectedGenres.remove(genre);
      } else {
        _selectedGenres.add(genre);
      }
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_primarySkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 1 Primary Skill/Talent'),
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
        if (user.userId != _editingUserId || appState.currentUserId != _editingUserId) {
          throw StateError('Your account changed. Reopen Edit Profile.');
        }
        final allSelectedSkills = SecondarySkillsUtils.buildInstrumentsList(
          _primarySkills.first, _secondarySkills,
        );
        final mainInstrumentStr = _primarySkills.first;

        final updatedProfile = UserProfile(
          userId: user.userId,
          nickname: user.nickname,
          displayName: _nameController.text.trim(),
          userType: _primarySkills.first,
          location: _cityLocation?.label,
          publicLocation: _cityLocation,
          clearPublicLocation: _cityLocation == null &&
              (user.publicLocation != null || user.location != null),
          level: _level,
          about: _aboutController.text.trim(),
          profilePictureUrl: _profilePictureUrl,
          genres: _selectedGenres,
          instruments: allSelectedSkills,
          styles: user.styles,
          contact: user.contact,
          history: user.history,
          projects: user.projects,
          collabRoles: user.collabRoles,
          collabRemote: user.collabRemote,
          spotifyUrl: _spotifyController.text.trim().isEmpty ? null : _spotifyController.text.trim(),
          youtubeUrl: _youtubeController.text.trim().isEmpty ? null : _youtubeController.text.trim(),
          audioSnippetUrl: _audioSnippetUrl,
          collabBio: _collabBioController.text.trim().isEmpty ? null : _collabBioController.text.trim(),
          mainInstrument: mainInstrumentStr,
        );

        await appState.firebaseService.saveUserProfileAsync(user.userId ?? '', updatedProfile);
        await appState.refreshProfile();

        if (mounted && appState.currentUserId == _editingUserId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save profile: Please try again.'),
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
    final appState = Provider.of<AppState>(context);
    if (_editingUserId != null && appState.currentUserId != _editingUserId) {
      return const GradientScaffold(
        body: Center(child: Text('Your account changed. Reopen Edit Profile.')),
      );
    }
    return GradientScaffold(
      appBar: const CustomTopBar(
        showBack: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
                readOnly: true,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'alex.hill@example.com',
                ),
              ),
              const SizedBox(height: 20),

              CityLocationPickerField(
                purpose:'profile',
                targetId:()=>_editingUserId??'',
                initialLocation: _cityLocation,
                onChanged: (city) => setState(() => _cityLocation = city),
              ),
              if (_legacyLocation?.trim().isNotEmpty == true)
                Text('Previous location (unverified): $_legacyLocation',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 24),

              // ================= SKILLS & TALENTS CARD =================
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: AppTheme.primaryAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'SKILLS/TALENTS',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Primary Skill (Select 1)
                    AnimatedTapDetector(
                      enableFocus: true,
                      semanticLabel: 'Primary Skill/Talent',
                      onTap: _openPrimarySkillPicker,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Primary Skill/Talent',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
                                    ),
                                    TextSpan(
                                      text: ' (Select 1)',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.normal, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              )),
                              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_primarySkills.isEmpty)
                            Text(
                              'Tap to select your Primary Skill/Talent...',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                            )
                          else
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _primarySkills.map((skill) {
                                return InputChip(
                                  label: Text(skill),
                                  selected: false,
                                  onPressed: _openPrimarySkillPicker,
                                  backgroundColor: AppTheme.primaryAccent.withOpacity(0.25),
                                  labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  side: const BorderSide(color: AppTheme.primaryAccent, width: 1),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF231F45), height: 1),
                    const SizedBox(height: 16),

                    SecondarySkillsEditor(
                      primarySkill: _primarySkills.firstOrNull,
                      selected: _secondarySkills,
                      taxonomyContext: SkillTaxonomyContext.editProfile,
                      onChanged: (skills) => setState(() => _secondarySkills = skills),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ================= GENRES CARD =================
              AnimatedTapDetector(
                enableFocus: true,
                semanticLabel: 'GENRES/BAND TYPES',
                onTap: _openGenrePicker,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Row(
                            children: [
                              const Icon(Icons.music_note_rounded, color: AppTheme.primaryAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                'GENRES/BAND TYPES',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              )),
                            ],
                          )),
                          Row(
                            children: [
                              if (_selectedGenres.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_selectedGenres.length}',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                                  ),
                                ),
                              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_selectedGenres.isEmpty)
                        Text(
                          'Tap to select Genres/Band Types',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _selectedGenres.map((genre) {
                            return InputChip(
                              label: Text(genre),
                              selected: false,
                              onDeleted: () => _toggleGenre(genre),
                              deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                              backgroundColor: const Color(0xFF1B1735),
                              labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              side: const BorderSide(color: AppTheme.primaryAccent, width: 1),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 4. Level
              Text(
                'Level',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.inputBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: _level,
                    isExpanded: true,
                    dropdownColor: AppTheme.cardBackground,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    items: _levels.map((String val) {
                      return DropdownMenuItem<String>(
                        value: val,
                        child: Text(val),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setState(() {
                          _level = newValue;
                        });
                      }
                    },
                  ),
                ),
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
                'Specify what types of collaborations you are open to (if any)',
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
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
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
                              ),
                              const SizedBox(height: 12),
                              AudioSnippetPlayer(audioUrl: _audioSnippetUrl!),
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
              const SizedBox(height: 32),

              // Danger Zone: Delete Account
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFEF4444),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'DANGER ZONE',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFEF4444),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Permanently remove your account, profile, feeds, and all related data.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedTapDetector(
                      onTap: () => _showDeleteAccountConfirmation(context),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withOpacity(0.6),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.delete_forever_rounded,
                                color: Color(0xFFEF4444),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Delete Account',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _showDeleteAccountConfirmation(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0C20).withOpacity(0.98),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5), width: 1.5),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Delete Account',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Are you sure you want to permanently delete your account? This action cannot be undone and will delete all your profile data, notification feeds, and band memberships.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (isDeleting)
                      const Center(
                        child: CircularProgressIndicator(color: Color(0xFFEF4444)),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF2E2A4E)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => Navigator.pop(dialogCtx),
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
                                backgroundColor: const Color(0xFFEF4444),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () async {
                                setDialogState(() {
                                  isDeleting = true;
                                });
                                try {
                                  await appState.deleteCurrentAccount();
                                  if (dialogCtx.mounted) {
                                    Navigator.pop(dialogCtx); // Close dialog
                                    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Account deleted successfully.'),
                                        backgroundColor: AppTheme.warning,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (dialogCtx.mounted) {
                                    setDialogState(() {
                                      isDeleting = false;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error deleting account: $e'),
                                        backgroundColor: AppTheme.danger,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                'Delete',
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
}
