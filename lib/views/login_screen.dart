import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = Provider.of<AppState>(context, listen: false);
    try {
      await appState.login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main-nav');
      }
    } catch (e) {
      if (mounted) {
        String errMsg = e.toString();
        if (errMsg.contains('user-not-found') || errMsg.contains('wrong-password') || errMsg.contains('invalid-credential')) {
          errMsg = 'Invalid email or password. Please try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
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
                // Premium visual logo element
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
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAccent,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: Text(
                    'Musicians',
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
                    'Connect with bands, subs, and gigs.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email address',
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
                const SizedBox(height: 20),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
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
                      return 'Please enter your password';
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
                        onTap: _handleLogin,
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
                              'Login',
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

                // Switch to Register Screen link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacementNamed(context, '/register');
                      },
                      child: Text(
                        'Register here',
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
