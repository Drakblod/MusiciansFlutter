import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/band.dart';
import '../providers/app_state.dart';
import 'gradient_scaffold.dart';

class NoBandState extends StatelessWidget {
  final bool staffing;
  final bool managerRequired;
  const NoBandState({super.key, this.staffing = false, this.managerRequired = false});

  static const staffingTitle = 'Create a band first';
  static const staffingBody = 'You need to create or join a band before you can search for musicians or vocalists.';

  static Future<void> showStaffingDialog(BuildContext context) async {
    final create = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text(staffingTitle), content: const Text(staffingBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create a Band')),
      ],
    ));
    if (create == true && context.mounted) await Navigator.pushNamed(context, '/create-band');
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(managerRequired ? 'Band leader or admin required' :
        staffing ? staffingTitle : 'You’re not in a band yet', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(managerRequired ? 'Ask a band leader or admin to manage staffing requests.' :
        staffing ? staffingBody : 'Create a band to start using Band Room, invite members and manage your band.',
        textAlign: TextAlign.center),
      const SizedBox(height: 20),
      if (!managerRequired) FilledButton(
        onPressed: () => Navigator.pushNamed(context, '/create-band'),
        child: const Text('Create a Band')),
      if (staffing) TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Cancel')),
    ]),
  )));
}

/// Validate before constructing a band-owned screen or any of its draft state.
class AuthorizedBandGate extends StatefulWidget {
  final String? requestedBandId;
  final bool staffing;
  final Widget Function(Band band) builder;
  const AuthorizedBandGate({super.key, this.requestedBandId,
    this.staffing = false, required this.builder});
  @override
  State<AuthorizedBandGate> createState() => _AuthorizedBandGateState();
}

class _AuthorizedBandGateState extends State<AuthorizedBandGate> {
  String? _requestKey;
  int _generation = 0;
  Band? _band;
  bool _loading = true;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureResolved(Provider.of<AppState>(context));
  }

  @override
  void didUpdateWidget(covariant AuthorizedBandGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedBandId != widget.requestedBandId || oldWidget.staffing != widget.staffing) {
      _requestKey = null;
      _ensureResolved(Provider.of<AppState>(context, listen: false));
    }
  }

  void _ensureResolved(AppState state) {
    final key = '${state.currentUserId}/${widget.requestedBandId ?? state.activeBandId}/${widget.staffing}';
    if (key == _requestKey) return;
    _requestKey = key;
    _band = null;
    _loading = true;
    _failed = false;
    _resolve(state);
  }

  Future<void> _resolve(AppState state) async {
    final generation = ++_generation;
    final uid = state.currentUserId;
    try {
      final band = await state.resolveAuthorizedBand(widget.requestedBandId,
        requireManager: widget.staffing);
      if (!mounted || generation != _generation || uid != state.currentUserId) return;
      setState(() { _band = band; _loading = false; });
    } catch (_) {
      if (!mounted || generation != _generation || uid != state.currentUserId) return;
      setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    if (_loading) {
      return const GradientScaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_failed) {
      return GradientScaffold(body: Center(child: TextButton(
      onPressed: () { setState(() { _loading = true; _failed = false; }); _resolve(state); },
      child: const Text('Could not verify band membership. Retry'),
    )));
    }
    if (_band == null) {
      return GradientScaffold(body: NoBandState(
      staffing: widget.staffing, managerRequired: widget.staffing && state.hasAuthorizedBand));
    }
    return KeyedSubtree(key: ValueKey('${state.currentUserId}/${_band!.id}'),
      child: widget.builder(_band!));
  }
}
