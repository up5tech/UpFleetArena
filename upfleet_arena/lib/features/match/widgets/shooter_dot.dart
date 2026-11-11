import 'package:flutter/material.dart';

/// The dot that carries a player's colour wherever that player is named.
///
/// The shared map paints every shooter in their own colour, so the same dot
/// identifies a player in the roster and in the list of the spectators. A
/// player who is out of the match keeps their colour as a hollow ring.
class ShooterDot extends StatelessWidget {
  const ShooterDot({
    super.key,
    required this.colour,
    this.alive = true,
    this.size = 10,
  });

  final Color colour;
  final bool alive;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: alive ? colour : Colors.transparent,
        border: alive ? null : Border.all(color: colour, width: 1.5),
      ),
    );
  }
}
