import 'package:flutter/material.dart';

class AnimatedLibrarySliverGrid extends StatefulWidget {
  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final SliverChildDelegate delegate;

  const AnimatedLibrarySliverGrid({
    super.key,
    required this.maxCrossAxisExtent,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.childAspectRatio,
    required this.delegate,
  });

  @override
  State<AnimatedLibrarySliverGrid> createState() =>
      _AnimatedLibrarySliverGridState();
}

class _AnimatedLibrarySliverGridState extends State<AnimatedLibrarySliverGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late double _beginExtent;
  late double _endExtent;

  @override
  void initState() {
    super.initState();
    _beginExtent = widget.maxCrossAxisExtent;
    _endExtent = widget.maxCrossAxisExtent;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    )..value = 1;
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant AnimatedLibrarySliverGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.maxCrossAxisExtent - _endExtent).abs() < 0.1) return;
    _beginExtent = _currentExtent;
    _endExtent = widget.maxCrossAxisExtent;
    _controller.forward(from: 0);
  }

  double get _currentExtent =>
      _beginExtent + ((_endExtent - _beginExtent) * _curve.value);

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _currentExtent,
            mainAxisSpacing: widget.mainAxisSpacing,
            crossAxisSpacing: widget.crossAxisSpacing,
            childAspectRatio: widget.childAspectRatio,
          ),
          delegate: widget.delegate,
        );
      },
    );
  }
}
