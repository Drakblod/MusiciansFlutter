import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

/// The same default AlertDialog styling used by the original staffing prompt.
class BandRequiredDialog extends StatelessWidget {
  static const title = 'Create a band first';
  static const bandRoomBody =
      'You need to create or join a band before you can access Band Room.';
  static const staffingBody =
      'You need to create or join a band before you can search for musicians or vocalists.';

  final bool staffing;
  final String? body;
  const BandRequiredDialog({super.key, required this.staffing, this.body});

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text(title),
    content: Text(body ?? (staffing ? staffingBody : bandRoomBody)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Create a Band'),
      ),
    ],
  );
}

class BandRequiredPrompt {
  BandRequiredPrompt._();
  static final _dialogs = Expando<DialogRoute<bool>>();
  static final _navigationBusy = Expando<Object>();

  static void _dismiss(NavigatorState navigator, Route<dynamic> route) {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  }

  static Future<bool> _decision(
    BuildContext context,
    AppState state,
    WidgetBuilder builder,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (_dialogs[navigator] != null) return false;
    final uid = state.currentUserId;
    var cancelled = false;
    final route = DialogRoute<bool>(context: context, builder: builder);
    _dialogs[navigator] = route;
    void sessionChanged() {
      if (state.currentUserId != uid || state.isLoading) {
        cancelled = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _dismiss(navigator, route),
        );
      }
    }

    state.addListener(sessionChanged);
    try {
      final accepted = await navigator.push(route);
      return accepted == true &&
          !cancelled &&
          state.currentUserId == uid &&
          !state.isLoading;
    } finally {
      state.removeListener(sessionChanged);
      if (identical(_dialogs[navigator], route)) _dialogs[navigator] = null;
    }
  }

  /// Returns a choice; callers retain their current route until it is dismissed.
  static Future<bool> show(
    BuildContext context,
    AppState state, {
    required bool staffing,
  }) =>
      _decision(context, state, (_) => BandRequiredDialog(staffing: staffing));

  static Future<bool> _retry(BuildContext context, AppState state) => _decision(
    context,
    state,
    (context) => AlertDialog(
      scrollable: true,
      title: const Text('Could not verify band membership'),
      content: const Text('Please try again.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  /// Close only this operation's sheet if its user/session changes.
  static Future<T?> showSessionSheet<T>(
    BuildContext context,
    AppState state, {
    required bool Function() isCurrent,
    required WidgetBuilder builder,
  }) async {
    if (!isCurrent()) return null;
    final navigator = Navigator.of(context);
    ModalRoute<dynamic>? ownedRoute;
    void sessionChanged() {
      final route = ownedRoute;
      if (!isCurrent() && route != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _dismiss(navigator, route),
        );
      }
    }

    state.addListener(sessionChanged);
    try {
      return await showModalBottomSheet<T>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) {
          ownedRoute = ModalRoute.of(sheetContext);
          return ListenableBuilder(
            listenable: state,
            builder: (_, _) {
              if (!isCurrent()) {
                sessionChanged();
                return const SizedBox.shrink();
              }
              return builder(sheetContext);
            },
          );
        },
      );
    } finally {
      state.removeListener(sessionChanged);
    }
  }

  /// Single-flight Home lookup, keeping loading, failure and empty results distinct.
  /// No protected route, draft or write is started until membership succeeds.
  static Future<bool> checkMemberships(
    BuildContext context,
    AppState state, {
    required bool staffing,
    required Future<bool> Function(
      Map<String, String> bands,
      bool Function() isCurrent,
    )
    onVerified,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final uid = state.currentUserId;
    if (uid == null || state.isLoading || _navigationBusy[navigator] != null) {
      return false;
    }
    final operation = Object();
    _navigationBusy[navigator] = operation;
    var cancelled = false;
    DialogRoute<void>? loading;
    void sessionChanged() {
      if (state.currentUserId != uid || state.isLoading) {
        cancelled = true;
        if (identical(_navigationBusy[navigator], operation)) {
          _navigationBusy[navigator] = null;
        }
        final route = loading;
        if (route != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _dismiss(navigator, route),
          );
        }
      }
    }

    state.addListener(sessionChanged);
    bool current() =>
        context.mounted &&
        !cancelled &&
        state.currentUserId == uid &&
        !state.isLoading;
    try {
      while (current()) {
        if (!context.mounted) return false;
        final route = DialogRoute<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PopScope(
            canPop: false,
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryAccent),
            ),
          ),
        );
        loading = route;
        navigator.push(route);
        final Map<String, String> bands;
        try {
          bands = await state.refreshBandMemberships();
        } catch (_) {
          _dismiss(navigator, route);
          loading = null;
          if (!context.mounted || !current()) return false;
          final retry = await _retry(context, state);
          if (!retry || !current()) return false;
          continue;
        }
        _dismiss(navigator, route);
        loading = null;
        if (!context.mounted || !current()) return false;
        if (bands.isEmpty) {
          if (state.hasAuthorizedBand) {
            return false; // A superseded lookup is not confirmed empty.
          }
          final create = await show(context, state, staffing: staffing);
          if (create && context.mounted && current()) {
            await Navigator.pushNamed(context, '/create-band');
          }
          return false;
        }
        return await onVerified(bands, current);
      }
      return false;
    } finally {
      final route = loading;
      if (route != null) _dismiss(navigator, route);
      state.removeListener(sessionChanged);
      if (identical(_navigationBusy[navigator], operation)) {
        _navigationBusy[navigator] = null;
      }
    }
  }
}
