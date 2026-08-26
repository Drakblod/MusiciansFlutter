import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/collab_session.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import '../data/skills_taxonomy.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  String _sessionType = 'Remote';
  String _sessionCategory = 'Songwriting';
  bool _isDateFlexible = true;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  List<String> _selectedGenres = [];
  List<String> _selectedRoles = [];
  List<String> _selectedInstruments = [];

  bool _isSaving = false;
  CollabSession? _existingSession;
  bool _initialized = false;

  final List<String> _categories = ["Songwriting", "Recording", "Production", "Jam", "Other"];
  final List<String> _types = ["In person", "Remote", "Hybrid"];

  final List<String> _genresList = [
    "Pop", "Rock", "Metal", "Hip-Hop", "Jazz", "Blues",
    "Electronic", "Country", "Classical", "Soul", "Reggae", "Alternative"
  ];

  List<String> get _rolesList => SkillsTaxonomy.sessionRoles;

  List<String> get _instrumentsList =>
      SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.createSession);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is CollabSession) {
        _existingSession = args;
        _titleController.text = args.title;
        _descriptionController.text = args.description;
        _locationController.text = args.location ?? '';
        _sessionType = args.sessionType;
        _sessionCategory = args.sessionCategory;
        _isDateFlexible = args.isDateFlexible;
        _selectedGenres = List<String>.from(args.genres);
        _selectedRoles = List<String>.from(args.lookingForRoles);
        _selectedInstruments = List<String>.from(args.lookingForInstruments);

        if (args.startDateTime != null) {
          final dt = DateTime.tryParse(args.startDateTime!);
          if (dt != null) {
            _selectedDate = dt;
            _selectedTime = TimeOfDay.fromDateTime(dt);
          }
        }
      } else if (args is String && args == 'Jam') {
        _sessionCategory = 'Jam';
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
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

  void _toggleRole(String role) {
    setState(() {
      if (_selectedRoles.contains(role)) {
        _selectedRoles.remove(role);
      } else {
        _selectedRoles.add(role);
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

  Future<void> _saveSession() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one role you are looking for'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    setState(() => _isSaving = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;

    if (userId == null) {
      setState(() => _isSaving = false);
      return;
    }

    if (_existingSession != null && _existingSession!.creatorId != userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unauthorized: You do not own this session'), backgroundColor: AppTheme.danger),
      );
      setState(() => _isSaving = false);
      return;
    }

    String? startIso;
    if (!_isDateFlexible && _selectedDate != null && _selectedTime != null) {
      final fullDt = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      startIso = fullDt.toUtc().toIso8601String();
    }

    try {
      final session = CollabSession(
        id: _existingSession?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        sessionType: _sessionType,
        sessionCategory: _sessionCategory,
        isDateFlexible: _isDateFlexible,
        startDateTime: startIso,
        location: _sessionType == 'Remote' ? null : _locationController.text.trim(),
        genres: _selectedGenres,
        lookingForRoles: _selectedRoles,
        lookingForInstruments: _selectedRoles.contains('musician') ? _selectedInstruments : [],
        creatorId: _existingSession?.creatorId ?? userId,
        createdAt: _existingSession?.createdAt ?? 0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        status: _existingSession?.status ?? 'active',
      );

      await appState.firebaseService.saveCollabSessionAsync(session);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session saved successfully!'), backgroundColor: AppTheme.success),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save session: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = _existingSession != null;

    return GradientScaffold(
      appBar: const CustomTopBar(
        showBack: true,
      ),
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
                  isEditMode ? 'EDIT SESSION' : 'CREATE COLLAB SESSION',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Session Title *',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Pop Songwriting Session in Stockholm',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Description
                Text(
                  'Session Description *',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Explain the goal of the session, what you plan to create, and any requirements...',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Session Category Selector
                Text(
                  'Session Category *',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sessionCategory,
                      dropdownColor: AppTheme.cardBackground,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                      isExpanded: true,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      onChanged: (String? val) {
                        if (val != null) {
                          setState(() => _sessionCategory = val);
                        }
                      },
                      items: _categories.map((String category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Session Type Selector
                Text(
                  'Session Type *',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Row(
                  children: _types.map((type) {
                    final isSel = _sessionType == type;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          label: Text(type),
                          selected: isSel,
                          onSelected: (val) {
                            if (val) setState(() => _sessionType = type);
                          },
                          selectedColor: AppTheme.primaryAccent,
                          backgroundColor: AppTheme.cardBackground,
                          labelStyle: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            color: Colors.white,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: BorderSide(color: isSel ? AppTheme.primaryAccent : const Color(0xFF2E2A4E)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Location (Hidden if Remote)
                if (_sessionType != 'Remote') ...[
                  Text(
                    'Location *',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _locationController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Sound Studio 3, Stockholm',
                    ),
                    validator: (value) {
                      if (_sessionType != 'Remote' && (value == null || value.trim().isEmpty)) {
                        return 'Please enter location';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                ],

                // Date Time / Flexible Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Flexible Date',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Decide date/time later',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    Switch(
                      value: _isDateFlexible,
                      onChanged: (val) {
                        setState(() => _isDateFlexible = val);
                      },
                      activeColor: AppTheme.primaryAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (!_isDateFlexible) ...[
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedTapDetector(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.inputBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2E2A4E)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _selectedDate == null ? 'Select Date' : _selectedDate!.toString().substring(0, 10),
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                ),
                                const Icon(Icons.calendar_today, color: Colors.white70, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: AnimatedTapDetector(
                          onTap: _pickTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.inputBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2E2A4E)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _selectedTime == null ? 'Select Time' : _selectedTime!.format(context),
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                ),
                                const Icon(Icons.access_time_rounded, color: Colors.white70, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                // Genres Selector
                Text(
                  'Genres/Band Types',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: Colors.white,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Looking For Roles Selector
                Text(
                  'Looking For Roles *',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _rolesList.map((role) {
                    final isSelected = _selectedRoles.contains(role);
                    return ChoiceChip(
                      label: Text(role[0].toUpperCase() + role.substring(1)),
                      selected: isSelected,
                      onSelected: (_) => _toggleRole(role),
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

                // Instruments Selector (Only shows if Musician role is selected)
                if (_selectedRoles.contains('musician')) ...[
                  Text(
                    'Instruments Needed',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _instrumentsList.map((inst) {
                      final isSelected = _selectedInstruments.contains(inst);
                      return ChoiceChip(
                        label: Text(inst),
                        selected: isSelected,
                        onSelected: (_) => _toggleInstrument(inst),
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
                ],
                const SizedBox(height: 20),

                // Save Button
                _isSaving
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                    : AnimatedTapDetector(
                        onTap: _saveSession,
                        child: Container(
                          height: 55,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              isEditMode ? 'Save Changes' : 'Create Session',
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
