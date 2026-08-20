import 'package:flutter/material.dart';

class AnimatedTapDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool enableFocus;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final String? semanticHint;

  const AnimatedTapDetector({
    super.key,
    required this.child,
    required this.onTap,
    this.enableFocus = false,
    this.focusNode,
    this.semanticLabel,
    this.semanticHint,
  });

  @override
  State<AnimatedTapDetector> createState() => _AnimatedTapDetectorState();
}

class _AnimatedTapDetectorState extends State<AnimatedTapDetector>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  void _handleActivate() {
    _controller.forward().then((_) => _controller.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final gestureDetector = GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );

    if (!widget.enableFocus) {
      return gestureDetector;
    }

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      mouseCursor: SystemMouseCursors.click,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            _handleActivate();
            return null;
          },
        ),
      },
      onFocusChange: (bool focused) {
        if (_isFocused != focused) {
          setState(() {
            _isFocused = focused;
          });
        }
      },
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        hint: widget.semanticHint,
        enabled: true,
        child: Container(
          decoration: _isFocused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).primaryColor, width: 2),
                )
              : null,
          child: gestureDetector,
        ),
      ),
    );
  }
}
