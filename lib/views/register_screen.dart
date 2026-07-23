import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  
  String _selectedUserType = 'Electric Guitar';
  bool _obscurePassword = true;

  final List<String> _userTypes = [
    "BANDLEADER",
    "SONGWRITER",
    "PRODUCER",
    "COMPOSER",
    "LYRICIST",
    "BEATMAKER",
    "STUDIO/ENGINEER, etc",
    "INSTRUMENTS/VOICES",
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
    "Latin Percussion (congas, timbales, etc)",
    "Classical Percussion (timpani, cymbals, etc)",
    "Soprano",
    "Alto",
    "Tenor",
    "Baritone",
    "Bass",
    "Mezzo Soprano",
    "Contralto",
    "Counter Tenor",
    "Male Lead Vocals",
    "Female Lead vocals",
    "Male Backing vocals",
    "Female Backing vocals",
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = Provider.of<AppState>(context, listen: false);
    try {
      await appState.register(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _selectedUserType,
        _nicknameController.text.trim(),
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main-nav');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return GradientScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          physics: const BouncingScrollPhysics(),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryAccent.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'm',
                      style: GoogleFonts.outfit(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAccent,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Center(
                  child: Text(
                    'Create Account',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Join the community of local musicians.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Nickname field
                TextFormField(
                  controller: _nicknameController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Nickname',
                    hintText: 'Enter your stage name/nickname',
                    prefixIcon: Icon(Icons.person_outline_rounded, color: AppTheme.textSecondary),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a nickname';
                    }
                    if (value.length < 3) {
                      return 'Nickname must be at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // User Type Selection Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      value: _selectedUserType,
                      decoration: const InputDecoration(
                        labelText: 'Primary Role',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        prefixIcon: Icon(Icons.music_note_outlined, color: AppTheme.textSecondary),
                      ),
                      dropdownColor: AppTheme.cardBackground,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                      items: _userTypes.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedUserType = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textSecondary),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Choose a strong password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.textSecondary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please choose a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),

                // Submit button
                appState.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                      )
                    : AnimatedTapDetector(
                        onTap: _handleRegister,
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
                              'Sign Up',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 24),

                // Link to Login screen
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account? ",
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: Text(
                        'Login here',
                        style: GoogleFonts.inter(
                          color: AppTheme.primaryAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
