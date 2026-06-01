import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../models/sub_request.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class ProducerSearchScreen extends StatefulWidget {
  const ProducerSearchScreen({super.key});

  @override
  State<ProducerSearchScreen> createState() => _ProducerSearchScreenState();
}

class _ProducerSearchScreenState extends State<ProducerSearchScreen> {
  final _messageController = TextEditingController();
  
  List<UserProfile> _allMusicians = [];
  List<UserProfile> _filteredMusicians = [];
  bool _isLoading = true;

  // Filter States
  String _selectedLevel = 'All Levels';
  String _selectedInstrument = 'Vocalist'; // Default to Vocalist to find singers
  String _selectedGenre = 'All Styles';
  bool _canMixMasterOnly = false;

  // Send Request Form State
  String _targetInstrument = 'Vocalist';

  final List<String> _levels = [
    'All Levels',
    'A = PRO',
    'B = SEMI PRO',
    'C = INTERMEDIATE',
    'D = AMATEUR',
    'E = BEGINNER'
  ];

  final List<String> _instruments = [
    'All Instruments',
    'Vocalist',
    'Guitar',
    'Bass',
    'Drums',
    'Piano',
    'Keyboard',
    'Saxophone',
    'Trumpet',
    'Violin',
    'Cello',
    'Other'
  ];

  final List<String> _targetInstruments = [
    'Vocalist',
    'Guitar',
    'Bass',
    'Drums',
    'Piano',
    'Keyboard',
    'Saxophone',
    'Trumpet',
    'Violin',
    'Cello',
    'Other'
  ];

  final List<String> _genres = [
    'All Styles',
    'Pop',
    'Rock',
    'Jazz',
    'Classical',
    'Metal'
  ];

  @override
  void initState() {
    super.initState();
    _loadMusicians();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMusicians() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final users = await appState.firebaseService.getAllUsersAsync();
      
      setState(() {
        _allMusicians = users;
        _applyFilters();
      });
    } catch (e) {
      debugPrint("Error loading musicians: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load musicians: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredMusicians = _allMusicians.where((musician) {
        // 1. Filter by Level
        if (_selectedLevel != 'All Levels') {
          if (musician.level == null ||
              !musician.level!.toLowerCase().contains(_selectedLevel.split(' = ').last.toLowerCase())) {
            return false;
          }
        }

        // 2. Filter by Instrument
        if (_selectedInstrument != 'All Instruments') {
          final instLower = _selectedInstrument.toLowerCase();
          final matchesInst = musician.instruments.any((i) => i.toLowerCase().contains(instLower));
          if (!matchesInst) return false;
        }

        // 3. Filter by Genre
        if (_selectedGenre != 'All Styles') {
          final genreLower = _selectedGenre.toLowerCase();
          final matchesGenre = musician.styles.any((s) => s.toLowerCase().contains(genreLower));
          if (!matchesGenre) return false;
        }

        // 4. Filter by Mix/Master
        if (_canMixMasterOnly) {
          if (!musician.canMixMaster) return false;
        }

        return true;
      }).toList();
    });
  }

  Future<void> _sendRequest() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a message for the request.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final currentUserId = appState.currentUserId;
      final profile = appState.currentUserProfile;
      final creatorName = profile?.displayName ?? profile?.nickname ?? "Producer";

      if (currentUserId == null) {
        throw Exception("User not logged in");
      }

      final request = SubRequest(
        creatorUserId: currentUserId,
        userId: currentUserId,
        voicePart: _targetInstrument,
        role: 'Producer Request',
        isPaid: true,
        location: 'Studio',
        description: message,
        date: DateTime.now().toIso8601String().split('T').first,
        startTime: '12:00:00',
        endTime: '14:00:00',
        bandName: creatorName,
      );

      await appState.firebaseService.saveSubRequestAsync(request);

      if (mounted) {
        _messageController.clear();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF2E2A4E), width: 1),
            ),
            title: Text(
              'Success',
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Your request for a $_targetInstrument has been sent successfully!',
              style: GoogleFonts.inter(color: AppTheme.textSecondary),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('OK', style: GoogleFonts.inter(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint("Error sending request: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send request: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Producer Mode',
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'FIND COLLABORATORS',
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Filter Form Container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: Column(
                  children: [
                    // Instrument selector
                    _buildDropdownFilter(
                      label: 'Target Instrument',
                      value: _selectedInstrument,
                      items: _instruments,
                      onChanged: (val) {
                        if (val != null) {
                          _selectedInstrument = val;
                          _applyFilters();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // Level selector
                    _buildDropdownFilter(
                      label: 'Musician Level',
                      value: _selectedLevel,
                      items: _levels,
                      onChanged: (val) {
                        if (val != null) {
                          _selectedLevel = val;
                          _applyFilters();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // Genre selector
                    _buildDropdownFilter(
                      label: 'Genre / Style',
                      value: _selectedGenre,
                      items: _genres,
                      onChanged: (val) {
                        if (val != null) {
                          _selectedGenre = val;
                          _applyFilters();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    // Mix/Master capability check
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Can Mix / Master?',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Switch(
                          value: _canMixMasterOnly,
                          activeColor: AppTheme.primaryAccent,
                          activeTrackColor: AppTheme.primaryAccent.withOpacity(0.3),
                          onChanged: (val) {
                            _canMixMasterOnly = val;
                            _applyFilters();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Musicians Found (${_filteredMusicians.length})',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              // Musicians List Container
              _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                      ),
                    )
                  : _filteredMusicians.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'No musicians match your filters.',
                              style: GoogleFonts.inter(color: AppTheme.textSecondary),
                            ),
                          ),
                        )
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ListView.builder(
                            itemCount: _filteredMusicians.length,
                            shrinkWrap: true,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final musician = _filteredMusicians[index];

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.05),
                                    width: 1,
                                  ),
                                ),
                                child: ListTile(
                                  title: Text(
                                    musician.displayName ?? musician.nickname ?? 'Musician',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Text(
                                    musician.instrumentsStr,
                                    style: GoogleFonts.inter(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (musician.level != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            musician.level!.split(' = ').last,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      if (musician.canMixMaster) ...[
                                        const SizedBox(width: 6),
                                        const Tooltip(
                                          message: 'Mix/Master Specialist',
                                          child: Icon(
                                            Icons.adjust_rounded,
                                            color: AppTheme.primaryAccent,
                                            size: 16,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/profile-detail',
                                      arguments: musician,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
              const SizedBox(height: 32),

              // Request Creation Form
              Text(
                'Send Studio Collaboration Request',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: Column(
                  children: [
                    _buildDropdownFilter(
                      label: 'Instrument Needed',
                      value: _targetInstrument,
                      items: _targetInstruments,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _targetInstrument = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _messageController,
                      maxLines: 3,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Describe your project (e.g. Need a vocalist for a pop/rock track. Standard studio session.)',
                        hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.inputBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedTapDetector(
                      onTap: _sendRequest,
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Send Request',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.inputBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              dropdownColor: AppTheme.cardBackground,
              icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryAccent),
              isExpanded: true,
            ),
          ),
        ),
      ],
    );
  }
}
