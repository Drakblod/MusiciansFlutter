import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Owns only its progress route. Session changes dismiss it and discard UI results;
/// a server-authorized operation already sent is not optimistically rolled back.
class MembershipMutationFeedback {
  static final _busy = Expando<Map<String, Object>>();
  static Future<bool> run(
    BuildContext context,
    String bandId,
    Future<void> Function() operation,
  ) async {
    final state = context.read<AppState>();
    final uid = state.currentUserId;
    final activeBand = state.activeBandId;
    if (uid == null || activeBand != bandId) return false;
    final scope = '$uid/$bandId';
    final busy = _busy[state] ??= <String, Object>{};
    if (busy.containsKey(scope)) return false;
    final token = Object();
    busy[scope] = token;
    var cancelled = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
    bool current() =>
        !cancelled &&
        context.mounted &&
        state.currentUserId == uid &&
        state.activeBandId == activeBand;
    void close() {
      if (progress.isActive && navigator.mounted) {
        navigator.removeRoute(progress);
      }
    }

    void sessionChanged() {
      if (!current()) {
        cancelled = true;
        if (identical(busy[scope], token)) busy.remove(scope);
        close();
      }
    }

    state.addListener(sessionChanged);
    navigator.push(progress);
    try {
      await operation();
      return current();
    } catch (_) {
      if (context.mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update band membership. Please try again.',
            ),
          ),
        );
      }
      return false;
    } finally {
      close();
      state.removeListener(sessionChanged);
      if (identical(busy[scope], token)) busy.remove(scope);
    }
  }
}
