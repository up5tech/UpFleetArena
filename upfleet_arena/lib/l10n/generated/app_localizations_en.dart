// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'UpFleet Arena';

  @override
  String get cancel => 'Cancel';

  @override
  String get edit => 'Edit';

  @override
  String get players => 'Players';

  @override
  String get board => 'Board';

  @override
  String get fleet => 'Fleet';

  @override
  String get timers => 'Timers';

  @override
  String get port => 'Port';

  @override
  String get ready => 'Ready';

  @override
  String get host => 'Host';

  @override
  String get backToHome => 'Back to home';

  @override
  String get endRoom => 'End room';

  @override
  String get endTheRoom => 'End the room?';

  @override
  String get roomSettings => 'Room settings';

  @override
  String get invitationCode => 'Invitation code';

  @override
  String get noNicknameYet => 'No nickname yet';

  @override
  String get prepareYourFleet => 'Prepare your fleet';

  @override
  String get yourFleet => 'Your fleet';

  @override
  String get nobodyInRoom => 'Nobody is in the room yet.';

  @override
  String get battle => 'Battle';

  @override
  String get lobby => 'Lobby';

  @override
  String get aPlayer => 'A player';

  @override
  String get anotherPlayer => 'another player';

  @override
  String get youWonMatch => 'You won the match.';

  @override
  String get roomHasClosed => 'The room has closed.';

  @override
  String get remove => 'Remove';

  @override
  String get leave => 'Leave';

  @override
  String get stop => 'Stop';

  @override
  String get scan => 'Scan';

  @override
  String get hide => 'Hide';

  @override
  String get show => 'Show';

  @override
  String cellsCount(int count) {
    return '$count cells';
  }

  @override
  String shipSize(int width, int height) {
    return '$width×$height';
  }

  @override
  String shipsLeftCount(int count) {
    return '$count ships left';
  }

  @override
  String timeoutsCount(int count) {
    return '$count timeouts';
  }

  @override
  String playerNameYou(String name) {
    return '$name (you)';
  }

  @override
  String playerIsShooting(String name) {
    return '$name is shooting';
  }

  @override
  String turnLabel(int turn) {
    return 'Turn $turn';
  }

  @override
  String secondsShort(int seconds) {
    return '${seconds}s';
  }

  @override
  String turnLabelWithTime(int turn, int seconds) {
    return 'Turn $turn · ${seconds}s left';
  }

  @override
  String get lanOnlyNoBackend => 'LAN only · no backend';

  @override
  String get heroTitle => 'Turn-based naval combat\nfor the same Wi-Fi';

  @override
  String get heroBody =>
      'Every player places a private fleet, then takes turns firing at the others. The room host runs the whole game on their phone — no server, no account, no Internet connection required.';

  @override
  String get lanLab => 'LAN Lab';

  @override
  String get lanLabSubtitle => 'Developer diagnostics — debug builds only';

  @override
  String get createRoom => 'Create Room';

  @override
  String get createRoomSubtitle => 'Host a room and share the invitation code';

  @override
  String get joinRoom => 'Join Room';

  @override
  String get joinRoomSubtitle => 'Find a nearby room and join with the code';

  @override
  String get playVsComputer => 'Play vs computer';

  @override
  String get playVsComputerSubtitle =>
      'Solo match against the computer, no Wi-Fi needed';

  @override
  String get chooseDifficulty => 'Choose the difficulty';

  @override
  String get difficultyEasy => 'Easy';

  @override
  String get difficultyMedium => 'Medium';

  @override
  String get difficultyHard => 'Hard';

  @override
  String get difficultyEasyHint =>
      'Fires at random cells and never follows up a hit.';

  @override
  String get difficultyMediumHint =>
      'Keeps firing around a hit until the ship is sunk.';

  @override
  String get difficultyHardHint =>
      'Hunts on a checkerboard and finishes damaged ships — a real challenge.';

  @override
  String botDisplayName(String difficulty) {
    return 'Computer ($difficulty)';
  }

  @override
  String get startPractice => 'Start playing';

  @override
  String get startingPractice => 'Preparing…';

  @override
  String get practiceHint =>
      'The computer plays on this device. Place your fleet, then take turns firing at each other.';

  @override
  String get addComputerTitle => 'Add a computer opponent';

  @override
  String get addComputer => 'Add computer';

  @override
  String get addComputerHint =>
      'A computer takes a seat like any player: it places its own fleet and fires on its turns. Only the host can add or remove it.';

  @override
  String get computer => 'Computer';

  @override
  String get computerOpponents => 'Computer opponents';

  @override
  String get computerCount => 'Computers';

  @override
  String get computerSettingsHint =>
      'Computers join as soon as you save and place their own fleet. They take a real seat, so the room capacity still applies.';

  @override
  String get lobbySubtitle => 'Seats, readiness and starting the match';

  @override
  String get shipPlacement => 'Ship Placement';

  @override
  String get shipPlacementSubtitle =>
      'Arrange your private fleet before the match';

  @override
  String get battleSubtitle => 'Turn-based combat on one shared map';

  @override
  String get profileAndSettings => 'Profile & Settings';

  @override
  String get profileAndSettingsSubtitle =>
      'Nickname, avatar, sound, haptics and language';

  @override
  String get inRoomOnly => 'Create or join a room first.';

  @override
  String get later => 'Later';

  @override
  String get frozenDefaults => 'Frozen defaults';

  @override
  String get network => 'Network';

  @override
  String get discovery => 'Discovery';

  @override
  String get fleetPresetSmall => 'Small';

  @override
  String get fleetPresetStandard => 'Standard';

  @override
  String get fleetPresetLarge => 'Large';

  @override
  String fleetConstraintValue(String lengths) {
    return 'Standard · $lengths';
  }

  @override
  String timersConstraintValue(int placement, int turn) {
    return '${placement}s placement · ${turn}s turn';
  }

  @override
  String get hostExitWarning =>
      'Host exit ends the room for every player. There is no host migration and no Internet fallback.';

  @override
  String get yourProfile => 'Your profile';

  @override
  String get nickname => 'Nickname';

  @override
  String get nicknameHint => 'How should other players see you?';

  @override
  String get nicknamePrivacy =>
      'Your nickname is stored on this device and is shared only with the players in the room you join.';

  @override
  String get profileSaved => 'Profile saved on this device.';

  @override
  String get avatar => 'Avatar';

  @override
  String get soundAndEffects => 'Sound & effects';

  @override
  String get soundEffects => 'Sound effects';

  @override
  String get soundEffectsSubtitle => 'Shots, hits, results and turn warnings';

  @override
  String get hapticFeedback => 'Haptic feedback';

  @override
  String get hapticFeedbackSubtitle => 'Vibration on shots and results';

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get reduceMotionSubtitle =>
      'Shorter animations, following the system setting';

  @override
  String get saveProfile => 'Save profile';

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle => 'Choose the language for the whole app.';

  @override
  String get followSystem => 'Follow system';

  @override
  String get english => 'English';

  @override
  String get vietnamese => 'Tiếng Việt';

  @override
  String get createRoomScreenTitle => 'Create room';

  @override
  String get youWillHost => 'You will host this room';

  @override
  String get defaultSettingsHint =>
      'These are the default settings. The host can change them in the lobby before the match starts.';

  @override
  String get creating => 'Creating…';

  @override
  String get pickNicknameFirst => 'Pick a nickname before creating a room.';

  @override
  String get whileYouHost => 'While you host';

  @override
  String get keepAppOpenHost =>
      'Keep this app open and in the foreground. Closing it ends the room for every player — there is no host migration.';

  @override
  String get joinRoomScreenTitle => 'Join room';

  @override
  String get invitationCodeHint =>
      'The host shares this code. It is checked by the host device over the direct connection, never over the network announcement.';

  @override
  String get nearbyRooms => 'Nearby rooms';

  @override
  String get lookingForRooms => 'Looking for rooms on this Wi-Fi…';

  @override
  String get noRoomsFound =>
      'No rooms found yet. Tap Scan, or use the manual connection below.';

  @override
  String get noAddress => 'no address';

  @override
  String get joinSelectedRoom => 'Join selected room';

  @override
  String get manualConnection => 'Manual connection';

  @override
  String get manualConnectionHint =>
      'Use this when the router blocks discovery. Enter the IPv4 address and the port shown on the host device.';

  @override
  String get hostIpv4 => 'Host IPv4';

  @override
  String get connectManually => 'Connect manually';

  @override
  String get portMustBeNumber => 'The port must be a number.';

  @override
  String get nothingFound => 'Nothing found?';

  @override
  String get routerIsolationHint =>
      'The router may isolate clients from each other. The manual connection above uses a direct TCP link, so it sometimes works when discovery is filtered.';

  @override
  String get waitingForRoomState => 'Waiting for the room state…';

  @override
  String get youSuffix => '  (you)';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusDisconnected => 'Disconnected — may rejoin';

  @override
  String get statusLeft => 'Left the room';

  @override
  String get statusKicked => 'Removed by the host';

  @override
  String removePlayer(String name) {
    return 'Remove $name';
  }

  @override
  String get copyTheCode => 'Copy the code';

  @override
  String get invitationCodeCopied => 'Invitation code copied.';

  @override
  String get shareTheInvitation => 'Share the invitation';

  @override
  String get manualAddress => 'Manual address';

  @override
  String get notAvailable => 'not available';

  @override
  String get shareCodeHint =>
      'Share the code with players on the same Wi-Fi. The code is not part of the network announcement, so only the players you tell can join.';

  @override
  String get shareJoinLine => 'Join my UpFleet Arena room.';

  @override
  String shareCodeLine(String code) {
    return 'Invitation code: $code';
  }

  @override
  String shareAddressLine(String address) {
    return 'Manual address: $address';
  }

  @override
  String get shareWifiLine => 'Every player must be on the same Wi-Fi network.';

  @override
  String get shareSubject => 'UpFleet Arena invitation';

  @override
  String get sharingNotAvailable => 'Sharing is not available here.';

  @override
  String fleetSettingsValue(String label, int count, String summary) {
    return '$label · $count ships ($summary)';
  }

  @override
  String get capacity => 'Capacity';

  @override
  String capacityValue(int count) {
    return 'up to $count players';
  }

  @override
  String timersSettingsValue(int placement, int turn) {
    return '$placement s preparation · $turn s per turn';
  }

  @override
  String get onlyHostChangesSettings =>
      'Only the host can change these settings.';

  @override
  String get startPreparation => 'Start the preparation';

  @override
  String get preparationTimeoutHint =>
      'When the preparation time runs out, the host places the missing ships automatically and the match starts.';

  @override
  String removePlayerQuestion(String name) {
    return 'Remove $name?';
  }

  @override
  String get removePlayerWarning =>
      'They are removed from the room and cannot rejoin with this invitation code.';

  @override
  String get endRoomWarning =>
      'Every player is disconnected and returns to the home screen. The room cannot be reopened.';

  @override
  String get yourFleetReady => 'Your fleet is ready';

  @override
  String get leaveRoom => 'Leave room';

  @override
  String get keepAppOpenLobby =>
      'Keep this app open and in the foreground. Closing it ends the room for every player.';

  @override
  String get hostOnlySettingsNotice =>
      'Only the host can change the room settings. You see the current values here.';

  @override
  String get rows => 'Rows';

  @override
  String get columns => 'Columns';

  @override
  String decreaseLabel(String label) {
    return 'Decrease $label';
  }

  @override
  String increaseLabel(String label) {
    return 'Increase $label';
  }

  @override
  String seatedPlayers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count players already in the room.',
      one: '$count player already in the room.',
    );
    return '$_temp0';
  }

  @override
  String fleetOptionLabel(String label, int count) {
    return '$label · $count ships';
  }

  @override
  String fleetLengths(String summary) {
    return 'Lengths $summary';
  }

  @override
  String get preparation => 'Preparation';

  @override
  String get eachTurn => 'Each turn';

  @override
  String get saving => 'Saving…';

  @override
  String get saveSettings => 'Save settings';

  @override
  String get resetToDefaults => 'Reset to the default settings';

  @override
  String get roomNoLongerOpen => 'The room is no longer open.';

  @override
  String get rotate => 'Rotate';

  @override
  String get undo => 'Undo';

  @override
  String get auto => 'Auto';

  @override
  String get youAreReady => 'You are ready';

  @override
  String get iAmReady => 'I am ready';

  @override
  String get placeEveryShipFirst => 'Place every ship first';

  @override
  String preparationEndsIn(String clock) {
    return 'The preparation ends in $clock';
  }

  @override
  String get autoPlaceHint =>
      'A fleet that is not finished in time is placed automatically.';

  @override
  String get placing => 'Placing';

  @override
  String get matchEnded => 'Match ended';

  @override
  String get theMatch => 'The match';

  @override
  String get matchNotStarted => 'The match has not started yet.';

  @override
  String get spectating => 'Spectating';

  @override
  String get yourBoard => 'Your board';

  @override
  String get leaveTheMatch => 'Leave the match?';

  @override
  String get endMatchForEveryone => 'This ends the match for every player.';

  @override
  String get youWillLeaveMatch => 'You will leave this match.';

  @override
  String get target => 'Target';

  @override
  String get noTargetsLeft => 'There is nobody left to shoot at.';

  @override
  String get sharedMapTitle => 'Shared map';

  @override
  String get legendHit => 'hit';

  @override
  String get legendSunk => 'sunk';

  @override
  String get legendMiss => 'your miss';

  @override
  String get closeMatch => 'Leave match';

  @override
  String selectedCell(String cell) {
    return 'Selected: $cell';
  }

  @override
  String selectedCellAlreadyFired(String cell) {
    return 'Selected: $cell — already fired here';
  }

  @override
  String get waitingForHost => 'Waiting for host…';

  @override
  String get doubleTapToFire => 'Double-tap a cell to fire at every opponent.';

  @override
  String get yourTurn => 'Your turn';

  @override
  String activityMissed(String attacker, String target) {
    return '$attacker missed $target.';
  }

  @override
  String activityHit(String attacker, String target) {
    return '$attacker hit $target.';
  }

  @override
  String activitySunk(String attacker, String target) {
    return '$attacker sank a ship of $target.';
  }

  @override
  String battleActivitySunk(String attacker, String target) {
    return '$attacker sank a ship belonging to $target.';
  }

  @override
  String get feedbackYouMissed => 'Your shot missed.';

  @override
  String get feedbackYouHit => 'Your shot hit a ship.';

  @override
  String get feedbackYouSunk => 'Your shot sank a ship.';

  @override
  String get feedbackTargetMissed => 'A shot missed your board.';

  @override
  String get feedbackTargetHit => 'A shot hit one of your ships.';

  @override
  String get feedbackTargetSunk => 'One of your ships was sunk.';

  @override
  String get feedbackOthers => 'The other players are shooting at each other.';

  @override
  String get matchIsOver => 'The match is over.';

  @override
  String get yourBoardUnavailable => 'Your board is not available.';

  @override
  String get ownBoardHint =>
      'The coloured cells are the hits on your fleet, in the colour of the player who fired them. Only you and the host see this board.';

  @override
  String get turnOrder => 'Turn order';

  @override
  String get inTheMatch => 'In the match';

  @override
  String get eliminated => 'Eliminated';

  @override
  String get matchResult => 'Match result';

  @override
  String get matchNotFinished => 'The match has not finished yet.';

  @override
  String lastedDuration(String duration) {
    return 'Lasted $duration';
  }

  @override
  String lastedDurationWithRank(String duration, int rank) {
    return 'Lasted $duration · You finished #$rank';
  }

  @override
  String get finalRanking => 'Final ranking';

  @override
  String get rankingHint =>
      'The ranking and every statistic come from the host. All players see the same result.';

  @override
  String get endRoomAndReturnHome => 'End room and return home';

  @override
  String get returnHome => 'Return home';

  @override
  String get matchOverClosesRoom =>
      'The match is over. This closes the room for everyone.';

  @override
  String get nobodySurvived => 'Nobody survived the match.';

  @override
  String playerWonMatch(String name) {
    return '$name won the match.';
  }

  @override
  String rankingStats(int shots, int hits, int misses, int sunk, int timeouts) {
    return '$shots shots · $hits hits · $misses misses · $sunk sunk · $timeouts timeouts';
  }

  @override
  String get reviewAllFleets => 'Review all fleets';

  @override
  String get allFleets => 'All fleets';

  @override
  String get allFleetsHint =>
      'The match is over, so every fleet is revealed. Each board shows where the ships were and every shot they took.';

  @override
  String fleetReviewSummary(int ships, int sunk) {
    return '$ships ships · $sunk sunk';
  }

  @override
  String get fleetsUnavailable => 'No fleet was recorded.';

  @override
  String get shootersLegend => 'Shot colours';

  @override
  String get ok => 'OK';

  @override
  String get yourFleetWasSunk => 'Your fleet was sunk.';

  @override
  String get spectatorWatching =>
      'You are watching the rest of the match. You cannot fire.';

  @override
  String get keepWatching => 'Keep watching';

  @override
  String get stillInTheMatch => 'Still in the match';

  @override
  String get nobodyIsLeft => 'Nobody is left.';

  @override
  String get publicActivity => 'Public activity';

  @override
  String get noPublicShots => 'No public shots yet.';

  @override
  String get spectatorHint =>
      'Spectators see no coordinates and no enemy fleet. Your own fleet stays available below.';

  @override
  String battleMapSemantics(int rows, int columns) {
    return 'Battle map with your fleet, $rows rows by $columns columns. Tap a cell to select it, double-tap to fire.';
  }

  @override
  String ownBoardSemantics(int rows, int columns) {
    return 'Your board, $rows rows by $columns columns.';
  }
}
