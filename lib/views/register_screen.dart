import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';
import '../data/skills_taxonomy.dart';
import '../data/genres_taxonomy.dart';

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
  String _selectedLevel = 'C = INTERMEDIATE';
  List<String> _selectedGenres = [];
  bool _obscurePassword = true;

  final List<String> _levels = [
    'A = PRO',
    'B = SEMI PRO',
    'C = INTERMEDIATE',
    'D = AMATEUR',
    'E = BEGINNER',
  ];

  List<String> get _userTypes =>
      SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.register);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _openGenrePicker() async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Genres/Band Types',
      categoryMap: GenresTaxonomy.categoryMap,
      initialSelected: _selectedGenres,
    );
    if (result != null) {
      setState(() {
        _selectedGenres = result;
      });
    }
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
        _selectedLevel,
        _selectedGenres,
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

                // 1. Profile Name field
                TextFormField(
                  controller: _nicknameController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Profile Name',
                    hintText: 'Enter your name or stage name',
                    helperText:
                        'Preferably use your real name to make it easier for users to find you',
                    helperMaxLines: 3,
                    prefixIcon: Icon(
                      Icons.person_outline_rounded,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a profile name';
                    }
                    if (value.trim().length < 2) {
                      return 'Profile name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 2. Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    ).hasMatch(value.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 3. Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Choose a strong password',
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
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
                const SizedBox(height: 16),

                // 4. Primary Skill/Talent Selection (Exactly 1 choice)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2E2A4E),
                      width: 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUserType,
                      decoration: const InputDecoration(
                        labelText: 'Primary Skill/Talent (Select 1)',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        prefixIcon: Icon(
                          Icons.music_note_outlined,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      dropdownColor: AppTheme.cardBackground,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textSecondary,
                      ),
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

                // 5. Genres/Band Types Selection
                AnimatedTapDetector(
                  enableFocus: true,
                  semanticLabel: 'Genres/Band Types',
                  onTap: _openGenrePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.inputBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF2E2A4E),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.category_outlined,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Genres/Band Types',
                                style: GoogleFonts.inter(
                                  color: _selectedGenres.isNotEmpty
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (_selectedGenres.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_selectedGenres.length}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryAccent,
                                  ),
                                ),
                              ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppTheme.textSecondary,
                            ),
                          ],
                        ),
                        if (_selectedGenres.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _selectedGenres.map((genre) {
                              return InputChip(
                                label: Text(genre),
                                selected: false,
                                onDeleted: () {
                                  setState(() {
                                    _selectedGenres.remove(genre);
                                  });
                                },
                                deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                                backgroundColor: const Color(0xFF1B1735),
                                labelStyle: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                side: const BorderSide(
                                  color: AppTheme.primaryAccent,
                                  width: 1,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 0,
                                ),
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Level Selection
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2E2A4E),
                      width: 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      value: _selectedLevel,
                      decoration: const InputDecoration(
                        labelText: 'Level',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        prefixIcon: Icon(
                          Icons.star_outline_rounded,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      dropdownColor: AppTheme.cardBackground,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textSecondary,
                      ),
                      items: _levels.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedLevel = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Submit button
                appState.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryAccent,
                        ),
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
                              ),
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
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
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
