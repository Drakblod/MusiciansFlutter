import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/band.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';

class CreateBandScreen extends StatefulWidget {
  const CreateBandScreen({super.key});

  @override
  State<CreateBandScreen> createState() => _CreateBandScreenState();
}

class _CreateBandScreenState extends State<CreateBandScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _rehearsalLocationController = TextEditingController();
  final _aboutController = TextEditingController();

  String _ensembleType = 'Pop/Rock band';
  String _level = 'C = INTERMEDIATE';
  String _rehearsalDay = 'Monday';
  
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  
  List<String> _selectedStyles = [];
  bool _isSaving = false;

  final List<String> _ensembleTypes = ['Choir', 'Big band', 'Pop/Rock band'];
  final List<String> _levels = [
    'A = PRO',
    'B = SEMI PRO',
    'C = INTERMEDIATE',
    'D = AMATEUR',
    'E = BEGINNER'
  ];
  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  final DictionaryStyles = const {
    'Choir': ['A Capella', 'Classical', 'Gospel', 'Pop', 'Gregorian'],
    'Big band': ['Swing', 'Jazz', 'Fusion', 'Salsa'],
    'Pop/Rock band': ['Pop', 'Rock', 'Metal', 'Blues', 'Reggae'],
  };

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _rehearsalLocationController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  void _onBandTypeChanged(String newType) {
    setState(() {
      _ensembleType = newType;
      _selectedStyles.clear();
    });
  }

  void _toggleStyle(String style) {
    setState(() {
      if (_selectedStyles.contains(style)) {
        _selectedStyles.remove(style);
      } else {
        _selectedStyles.add(style);
      }
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              surface: AppTheme.cardBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _saveBand() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No user logged in.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final formatTime = (TimeOfDay t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

      final band = Band(
        name: _nameController.text.trim(),
        ensembleType: _ensembleType,
        genres: _selectedStyles,
        styleBand: _selectedStyles,
        level: _level,
        location: _locationController.text.trim(),
        rehearsalLocation: _rehearsalLocationController.text.trim(),
        rehearsalDayOfWeek: _rehearsalDay,
        rehearsalStartTime: formatTime(_startTime),
        rehearsalEndTime: formatTime(_endTime),
        about: _aboutController.text.trim(),
        description: _aboutController.text.trim(),
      );

      await appState.firebaseService.createBandAsync(userId, band);
      await appState.refreshProfile(); // refresh local active bands

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Band created successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create band: $e'),
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
    final formatTime = (TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final availableStyles = DictionaryStyles[_ensembleType] ?? [];

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
                'Create New Band',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Band Name
              Text(
                'Band Name',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Enter band name',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a band name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Ensemble Type
              Text(
                'Band Type',
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
                    value: _ensembleType,
                    dropdownColor: AppTheme.cardBackground,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    items: _ensembleTypes.map((String val) {
                      return DropdownMenuItem<String>(
                        value: val,
                        child: Text(val),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        _onBandTypeChanged(newValue);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Dynamic Styles/Genres
              if (availableStyles.isNotEmpty) ...[
                Text(
                  'Styles',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableStyles.map((style) {
                    final isSelected = _selectedStyles.contains(style);
                    return FilterChip(
                      label: Text(
                        style,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isSelected ? Colors.white : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryAccent,
                      checkmarkColor: Colors.white,
                      backgroundColor: const Color(0xFF1E1A3C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                        ),
                      ),
                      onSelected: (_) => _toggleStyle(style),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],

              // Band Level
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
              const SizedBox(height: 20),

              // Location
              Text(
                'Location (Country, City)',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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

              // Rehearsal Location
              Text(
                'Rehearsal Location',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _rehearsalLocationController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'e.g. Studio 3, Stockholm',
                ),
              ),
              const SizedBox(height: 20),

              // Rehearsal Day
              Text(
                'Rehearsal Day',
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
                    value: _rehearsalDay,
                    dropdownColor: AppTheme.cardBackground,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    items: _daysOfWeek.map((String val) {
                      return DropdownMenuItem<String>(
                        value: val,
                        child: Text(val),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setState(() {
                          _rehearsalDay = newValue;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Times Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start Time',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        AnimatedTapDetector(
                          onTap: () => _pickTime(true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.inputBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                            ),
                            child: Center(
                              child: Text(
                                formatTime(_startTime),
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                              ),
                            ),
                          ),
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
                          'End Time',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        AnimatedTapDetector(
                          onTap: () => _pickTime(false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.inputBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                            ),
                            child: Center(
                              child: Text(
                                formatTime(_endTime),
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // About/Description
              Text(
                'About the Band',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _aboutController,
                maxLines: 4,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Provide details about rehearsals, gigs, level, style, etc.',
                ),
              ),
              const SizedBox(height: 30),

              // Save Button
              _isSaving
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                  : AnimatedTapDetector(
                      onTap: _saveBand,
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Save Band',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
