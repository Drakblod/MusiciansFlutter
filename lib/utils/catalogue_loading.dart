import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/user_profile.dart';

/// Cancellation is permanent across A→B→A switches; server reads stay read-only.
class CatalogueScope {
  final AppState state;
  late final String? uid;
  late final String? band;
  bool _cancelled = false;
  CatalogueScope(this.state) {
    uid = state.currentUserId;
    band = state.activeBandId;
    state.addListener(_changed);
  }
  void _changed() {
    if (state.currentUserId != uid || state.activeBandId != band) {
      _cancelled = true;
    }
  }

  bool get current =>
      !_cancelled && state.currentUserId == uid && state.activeBandId == band;
  void dispose() {
    state.removeListener(_changed);
  }
}

class CatalogueLoading {
  static Future<List<UserProfile>?> usersForPicker(BuildContext context) async {
    final state = context.read<AppState>();
    final scope = CatalogueScope(state);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    void close() {
      if (navigator.mounted && progress.isActive) {
        navigator.removeRoute(progress);
      }
    }

    void changed() {
      if (!scope.current) close();
    }

    state.addListener(changed);
    navigator.push(progress);
    try {
      final users = await state.firebaseService.getAllUsersAsync();
      return context.mounted && scope.current ? users : null;
    } catch (_) {
      if (context.mounted && scope.current) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load profiles. Please try again.'),
          ),
        );
      }
      return null;
    } finally {
      state.removeListener(changed);
      scope.dispose();
      close();
    }
  }
}
