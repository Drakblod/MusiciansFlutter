import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/collab_studio.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';


class StudioDetailsScreen extends StatefulWidget {
  final CollabStudio studio;

  const StudioDetailsScreen({super.key, required this.studio});

  @override
  State<StudioDetailsScreen> createState() => _StudioDetailsScreenState();
}

class _StudioDetailsScreenState extends State<StudioDetailsScreen> {
  bool _isDeleting = false;

  Future<void> _deleteStudio() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: Text('Delete Studio', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text('Are you sure you want to delete this studio listing permanently?',
            style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isDeleting = true);
      try {
        final appState = Provider.of<AppState>(context, listen: false);
        await appState.firebaseService.deleteCollabStudioAsync(widget.studio.id ?? '');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Studio listing deleted successfully'), backgroundColor: AppTheme.success),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete studio: $e'), backgroundColor: AppTheme.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isOwner = widget.studio.creatorId == appState.currentUserId;

    return GradientScaffold(
      appBar: const CustomTopBar(
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Category Label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'RECORDING STUDIO',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Title and Owner Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.studio.name,
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (isOwner) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryAccent),
                      onPressed: () async {
                        await Navigator.pushNamed(context, '/edit-studio', arguments: widget.studio);
                        if (mounted) Navigator.pop(context); // reload listing detail parent list
                      },
                    ),
                    _isDeleting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.danger),
                          )
                        : IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                            onPressed: _deleteStudio,
                          ),
                  ],
                ],
              ),
              const SizedBox(height: 6),

              // Location
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    widget.studio.location,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Specialties / Genres
              if (widget.studio.genres.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.studio.genres.map((genre) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1A3A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E2A4E)),
                      ),
                      child: Text(
                        genre,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.secondaryAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Description
              Text(
                'About the Studio',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF231F45), width: 1),
                ),
                child: Text(
                  widget.studio.description,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Facilities / Equipment list
              if (widget.studio.facilities != null && widget.studio.facilities!.isNotEmpty) ...[
                Text(
                  'Facilities & Equipment',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF231F45), width: 1),
                  ),
                  child: Text(
                    widget.studio.facilities!,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Contact Info / Booking Info
              if (widget.studio.contactInfo != null && widget.studio.contactInfo!.isNotEmpty) ...[
                Text(
                  'Booking & Contact',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF231F45), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppTheme.primaryAccent, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.studio.contactInfo!,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
