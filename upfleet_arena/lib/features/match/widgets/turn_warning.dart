/// Warning shared by the match UI when a turn is about to run out.
library;

/// From this many seconds left a turn is about to run out.
const int urgentTurnSeconds = 5;

/// Whether [remaining] seconds left counts as an urgent turn.
bool isUrgentTurn(int? remaining) =>
    remaining != null && remaining <= urgentTurnSeconds;
