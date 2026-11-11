import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// A framed block of the match view.
///
/// The map, the roster, the activity feed and the own fleet share the same
/// frame, so every part of the match reads as one screen instead of loose
/// content on the background.
class MatchPanel extends StatelessWidget {
  const MatchPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: child,
    );
  }
}
