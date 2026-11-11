import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'UpFleet Arena'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @players.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get players;

  /// No description provided for @board.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get board;

  /// No description provided for @fleet.
  ///
  /// In en, this message translates to:
  /// **'Fleet'**
  String get fleet;

  /// No description provided for @timers.
  ///
  /// In en, this message translates to:
  /// **'Timers'**
  String get timers;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get backToHome;

  /// No description provided for @endRoom.
  ///
  /// In en, this message translates to:
  /// **'End room'**
  String get endRoom;

  /// No description provided for @endTheRoom.
  ///
  /// In en, this message translates to:
  /// **'End the room?'**
  String get endTheRoom;

  /// No description provided for @roomSettings.
  ///
  /// In en, this message translates to:
  /// **'Room settings'**
  String get roomSettings;

  /// No description provided for @invitationCode.
  ///
  /// In en, this message translates to:
  /// **'Invitation code'**
  String get invitationCode;

  /// No description provided for @noNicknameYet.
  ///
  /// In en, this message translates to:
  /// **'No nickname yet'**
  String get noNicknameYet;

  /// No description provided for @prepareYourFleet.
  ///
  /// In en, this message translates to:
  /// **'Prepare your fleet'**
  String get prepareYourFleet;

  /// No description provided for @yourFleet.
  ///
  /// In en, this message translates to:
  /// **'Your fleet'**
  String get yourFleet;

  /// No description provided for @nobodyInRoom.
  ///
  /// In en, this message translates to:
  /// **'Nobody is in the room yet.'**
  String get nobodyInRoom;

  /// No description provided for @battle.
  ///
  /// In en, this message translates to:
  /// **'Battle'**
  String get battle;

  /// No description provided for @lobby.
  ///
  /// In en, this message translates to:
  /// **'Lobby'**
  String get lobby;

  /// No description provided for @aPlayer.
  ///
  /// In en, this message translates to:
  /// **'A player'**
  String get aPlayer;

  /// No description provided for @anotherPlayer.
  ///
  /// In en, this message translates to:
  /// **'another player'**
  String get anotherPlayer;

  /// No description provided for @youWonMatch.
  ///
  /// In en, this message translates to:
  /// **'You won the match.'**
  String get youWonMatch;

  /// No description provided for @roomHasClosed.
  ///
  /// In en, this message translates to:
  /// **'The room has closed.'**
  String get roomHasClosed;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @cellsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cells'**
  String cellsCount(int count);

  /// No description provided for @shipSize.
  ///
  /// In en, this message translates to:
  /// **'{width}×{height}'**
  String shipSize(int width, int height);

  /// No description provided for @squareHint.
  ///
  /// In en, this message translates to:
  /// **'Only a ship whose cells form a square (4, 9, 16…) can be turned into a block: pick it and tap Rotate, or double tap it on the board.'**
  String get squareHint;

  /// No description provided for @shipsLeftCount.
  ///
  /// In en, this message translates to:
  /// **'{count} ships left'**
  String shipsLeftCount(int count);

  /// No description provided for @timeoutsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} timeouts'**
  String timeoutsCount(int count);

  /// No description provided for @playerNameYou.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String playerNameYou(String name);

  /// No description provided for @playerIsShooting.
  ///
  /// In en, this message translates to:
  /// **'{name} is shooting'**
  String playerIsShooting(String name);

  /// No description provided for @turnLabel.
  ///
  /// In en, this message translates to:
  /// **'Turn {turn}'**
  String turnLabel(int turn);

  /// No description provided for @secondsShort.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String secondsShort(int seconds);

  /// No description provided for @turnLabelWithTime.
  ///
  /// In en, this message translates to:
  /// **'Turn {turn} · {seconds}s left'**
  String turnLabelWithTime(int turn, int seconds);

  /// No description provided for @lanOnlyNoBackend.
  ///
  /// In en, this message translates to:
  /// **'LAN only · no backend'**
  String get lanOnlyNoBackend;

  /// No description provided for @heroTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn-based naval combat\nfor the same Wi-Fi'**
  String get heroTitle;

  /// No description provided for @heroBody.
  ///
  /// In en, this message translates to:
  /// **'Every player places a private fleet, then takes turns firing at the others. The room host runs the whole game on their phone — no server, no account, no Internet connection required.'**
  String get heroBody;

  /// No description provided for @lanLab.
  ///
  /// In en, this message translates to:
  /// **'LAN Lab'**
  String get lanLab;

  /// No description provided for @lanLabSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Developer diagnostics — debug builds only'**
  String get lanLabSubtitle;

  /// No description provided for @createRoom.
  ///
  /// In en, this message translates to:
  /// **'Create Room'**
  String get createRoom;

  /// No description provided for @createRoomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Host a room and share the invitation code'**
  String get createRoomSubtitle;

  /// No description provided for @joinRoom.
  ///
  /// In en, this message translates to:
  /// **'Join Room'**
  String get joinRoom;

  /// No description provided for @joinRoomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find a nearby room and join with the code'**
  String get joinRoomSubtitle;

  /// No description provided for @playVsComputer.
  ///
  /// In en, this message translates to:
  /// **'Play vs computer'**
  String get playVsComputer;

  /// No description provided for @playVsComputerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Solo match against the computer, no Wi-Fi needed'**
  String get playVsComputerSubtitle;

  /// No description provided for @chooseDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Choose the difficulty'**
  String get chooseDifficulty;

  /// No description provided for @difficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasy;

  /// No description provided for @difficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get difficultyMedium;

  /// No description provided for @difficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get difficultyHard;

  /// No description provided for @difficultyEasyHint.
  ///
  /// In en, this message translates to:
  /// **'Fires at random cells and never follows up a hit.'**
  String get difficultyEasyHint;

  /// No description provided for @difficultyMediumHint.
  ///
  /// In en, this message translates to:
  /// **'Keeps firing around a hit until the ship is sunk.'**
  String get difficultyMediumHint;

  /// No description provided for @difficultyHardHint.
  ///
  /// In en, this message translates to:
  /// **'Hunts on a checkerboard and finishes damaged ships — a real challenge.'**
  String get difficultyHardHint;

  /// No description provided for @botDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Computer ({difficulty})'**
  String botDisplayName(String difficulty);

  /// No description provided for @startPractice.
  ///
  /// In en, this message translates to:
  /// **'Start playing'**
  String get startPractice;

  /// No description provided for @startingPractice.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get startingPractice;

  /// No description provided for @practiceHint.
  ///
  /// In en, this message translates to:
  /// **'The computer plays on this device. Place your fleet, then take turns firing at each other.'**
  String get practiceHint;

  /// No description provided for @addComputerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a computer opponent'**
  String get addComputerTitle;

  /// No description provided for @addComputer.
  ///
  /// In en, this message translates to:
  /// **'Add computer'**
  String get addComputer;

  /// No description provided for @addComputerHint.
  ///
  /// In en, this message translates to:
  /// **'A computer takes a seat like any player: it places its own fleet and fires on its turns. Only the host can add or remove it.'**
  String get addComputerHint;

  /// No description provided for @computer.
  ///
  /// In en, this message translates to:
  /// **'Computer'**
  String get computer;

  /// No description provided for @computerOpponents.
  ///
  /// In en, this message translates to:
  /// **'Computer opponents'**
  String get computerOpponents;

  /// No description provided for @computerCount.
  ///
  /// In en, this message translates to:
  /// **'Computers'**
  String get computerCount;

  /// No description provided for @computerSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Computers join as soon as you save and place their own fleet. They take a real seat, so the room capacity still applies.'**
  String get computerSettingsHint;

  /// No description provided for @lobbySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Seats, readiness and starting the match'**
  String get lobbySubtitle;

  /// No description provided for @shipPlacement.
  ///
  /// In en, this message translates to:
  /// **'Ship Placement'**
  String get shipPlacement;

  /// No description provided for @shipPlacementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Arrange your private fleet before the match'**
  String get shipPlacementSubtitle;

  /// No description provided for @battleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn-based combat on one shared map'**
  String get battleSubtitle;

  /// No description provided for @profileAndSettings.
  ///
  /// In en, this message translates to:
  /// **'Profile & Settings'**
  String get profileAndSettings;

  /// No description provided for @profileAndSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nickname, avatar, sound, haptics and language'**
  String get profileAndSettingsSubtitle;

  /// No description provided for @inRoomOnly.
  ///
  /// In en, this message translates to:
  /// **'Create or join a room first.'**
  String get inRoomOnly;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @frozenDefaults.
  ///
  /// In en, this message translates to:
  /// **'Frozen defaults'**
  String get frozenDefaults;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @discovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get discovery;

  /// No description provided for @fleetPresetSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fleetPresetSmall;

  /// No description provided for @fleetPresetStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get fleetPresetStandard;

  /// No description provided for @fleetPresetLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fleetPresetLarge;

  /// No description provided for @fleetConstraintValue.
  ///
  /// In en, this message translates to:
  /// **'Standard · {lengths}'**
  String fleetConstraintValue(String lengths);

  /// No description provided for @timersConstraintValue.
  ///
  /// In en, this message translates to:
  /// **'{placement}s placement · {turn}s turn'**
  String timersConstraintValue(int placement, int turn);

  /// No description provided for @hostExitWarning.
  ///
  /// In en, this message translates to:
  /// **'Host exit ends the room for every player. There is no host migration and no Internet fallback.'**
  String get hostExitWarning;

  /// No description provided for @yourProfile.
  ///
  /// In en, this message translates to:
  /// **'Your profile'**
  String get yourProfile;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @nicknameHint.
  ///
  /// In en, this message translates to:
  /// **'How should other players see you?'**
  String get nicknameHint;

  /// No description provided for @nicknamePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your nickname is stored on this device and is shared only with the players in the room you join.'**
  String get nicknamePrivacy;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved on this device.'**
  String get profileSaved;

  /// No description provided for @avatar.
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get avatar;

  /// No description provided for @soundAndEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound & effects'**
  String get soundAndEffects;

  /// No description provided for @soundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound effects'**
  String get soundEffects;

  /// No description provided for @soundEffectsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shots, hits, results and turn warnings'**
  String get soundEffectsSubtitle;

  /// No description provided for @hapticFeedback.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get hapticFeedback;

  /// No description provided for @hapticFeedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibration on shots and results'**
  String get hapticFeedbackSubtitle;

  /// No description provided for @reduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// No description provided for @reduceMotionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shorter animations, following the system setting'**
  String get reduceMotionSubtitle;

  /// No description provided for @saveProfile.
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get saveProfile;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the language for the whole app.'**
  String get languageSubtitle;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystem;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @vietnamese.
  ///
  /// In en, this message translates to:
  /// **'Tiếng Việt'**
  String get vietnamese;

  /// No description provided for @createRoomScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get createRoomScreenTitle;

  /// No description provided for @youWillHost.
  ///
  /// In en, this message translates to:
  /// **'You will host this room'**
  String get youWillHost;

  /// No description provided for @defaultSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'These are the default settings. The host can change them in the lobby before the match starts.'**
  String get defaultSettingsHint;

  /// No description provided for @creating.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get creating;

  /// No description provided for @pickNicknameFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick a nickname before creating a room.'**
  String get pickNicknameFirst;

  /// No description provided for @whileYouHost.
  ///
  /// In en, this message translates to:
  /// **'While you host'**
  String get whileYouHost;

  /// No description provided for @keepAppOpenHost.
  ///
  /// In en, this message translates to:
  /// **'Keep this app open and in the foreground. Closing it ends the room for every player — there is no host migration.'**
  String get keepAppOpenHost;

  /// No description provided for @joinRoomScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get joinRoomScreenTitle;

  /// No description provided for @invitationCodeHint.
  ///
  /// In en, this message translates to:
  /// **'The host shares this code. It is checked by the host device over the direct connection, never over the network announcement.'**
  String get invitationCodeHint;

  /// No description provided for @nearbyRooms.
  ///
  /// In en, this message translates to:
  /// **'Nearby rooms'**
  String get nearbyRooms;

  /// No description provided for @lookingForRooms.
  ///
  /// In en, this message translates to:
  /// **'Looking for rooms on this Wi-Fi…'**
  String get lookingForRooms;

  /// No description provided for @noRoomsFound.
  ///
  /// In en, this message translates to:
  /// **'No rooms found yet. Tap Scan, or use the manual connection below.'**
  String get noRoomsFound;

  /// No description provided for @noAddress.
  ///
  /// In en, this message translates to:
  /// **'no address'**
  String get noAddress;

  /// No description provided for @joinSelectedRoom.
  ///
  /// In en, this message translates to:
  /// **'Join selected room'**
  String get joinSelectedRoom;

  /// No description provided for @manualConnection.
  ///
  /// In en, this message translates to:
  /// **'Manual connection'**
  String get manualConnection;

  /// No description provided for @manualConnectionHint.
  ///
  /// In en, this message translates to:
  /// **'Use this when the router blocks discovery. Enter the IPv4 address and the port shown on the host device.'**
  String get manualConnectionHint;

  /// No description provided for @hostIpv4.
  ///
  /// In en, this message translates to:
  /// **'Host IPv4'**
  String get hostIpv4;

  /// No description provided for @connectManually.
  ///
  /// In en, this message translates to:
  /// **'Connect manually'**
  String get connectManually;

  /// No description provided for @portMustBeNumber.
  ///
  /// In en, this message translates to:
  /// **'The port must be a number.'**
  String get portMustBeNumber;

  /// No description provided for @nothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found?'**
  String get nothingFound;

  /// No description provided for @routerIsolationHint.
  ///
  /// In en, this message translates to:
  /// **'The router may isolate clients from each other. The manual connection above uses a direct TCP link, so it sometimes works when discovery is filtered.'**
  String get routerIsolationHint;

  /// No description provided for @waitingForRoomState.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the room state…'**
  String get waitingForRoomState;

  /// No description provided for @youSuffix.
  ///
  /// In en, this message translates to:
  /// **'  (you)'**
  String get youSuffix;

  /// No description provided for @statusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// No description provided for @statusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected — may rejoin'**
  String get statusDisconnected;

  /// No description provided for @statusLeft.
  ///
  /// In en, this message translates to:
  /// **'Left the room'**
  String get statusLeft;

  /// No description provided for @statusKicked.
  ///
  /// In en, this message translates to:
  /// **'Removed by the host'**
  String get statusKicked;

  /// No description provided for @removePlayer.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String removePlayer(String name);

  /// No description provided for @copyTheCode.
  ///
  /// In en, this message translates to:
  /// **'Copy the code'**
  String get copyTheCode;

  /// No description provided for @invitationCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Invitation code copied.'**
  String get invitationCodeCopied;

  /// No description provided for @shareTheInvitation.
  ///
  /// In en, this message translates to:
  /// **'Share the invitation'**
  String get shareTheInvitation;

  /// No description provided for @manualAddress.
  ///
  /// In en, this message translates to:
  /// **'Manual address'**
  String get manualAddress;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'not available'**
  String get notAvailable;

  /// No description provided for @shareCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Share the code with players on the same Wi-Fi. The code is not part of the network announcement, so only the players you tell can join.'**
  String get shareCodeHint;

  /// No description provided for @shareJoinLine.
  ///
  /// In en, this message translates to:
  /// **'Join my UpFleet Arena room.'**
  String get shareJoinLine;

  /// No description provided for @shareCodeLine.
  ///
  /// In en, this message translates to:
  /// **'Invitation code: {code}'**
  String shareCodeLine(String code);

  /// No description provided for @shareAddressLine.
  ///
  /// In en, this message translates to:
  /// **'Manual address: {address}'**
  String shareAddressLine(String address);

  /// No description provided for @shareWifiLine.
  ///
  /// In en, this message translates to:
  /// **'Every player must be on the same Wi-Fi network.'**
  String get shareWifiLine;

  /// No description provided for @shareSubject.
  ///
  /// In en, this message translates to:
  /// **'UpFleet Arena invitation'**
  String get shareSubject;

  /// No description provided for @sharingNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Sharing is not available here.'**
  String get sharingNotAvailable;

  /// No description provided for @fleetSettingsValue.
  ///
  /// In en, this message translates to:
  /// **'{label} · {count} ships ({summary})'**
  String fleetSettingsValue(String label, int count, String summary);

  /// No description provided for @capacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacity;

  /// No description provided for @capacityValue.
  ///
  /// In en, this message translates to:
  /// **'up to {count} players'**
  String capacityValue(int count);

  /// No description provided for @timersSettingsValue.
  ///
  /// In en, this message translates to:
  /// **'{placement} s preparation · {turn} s per turn'**
  String timersSettingsValue(int placement, int turn);

  /// No description provided for @onlyHostChangesSettings.
  ///
  /// In en, this message translates to:
  /// **'Only the host can change these settings.'**
  String get onlyHostChangesSettings;

  /// No description provided for @startPreparation.
  ///
  /// In en, this message translates to:
  /// **'Start the preparation'**
  String get startPreparation;

  /// No description provided for @preparationTimeoutHint.
  ///
  /// In en, this message translates to:
  /// **'When the preparation time runs out, the host places the missing ships automatically and the match starts.'**
  String get preparationTimeoutHint;

  /// No description provided for @removePlayerQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String removePlayerQuestion(String name);

  /// No description provided for @removePlayerWarning.
  ///
  /// In en, this message translates to:
  /// **'They are removed from the room and cannot rejoin with this invitation code.'**
  String get removePlayerWarning;

  /// No description provided for @endRoomWarning.
  ///
  /// In en, this message translates to:
  /// **'Every player is disconnected and returns to the home screen. The room cannot be reopened.'**
  String get endRoomWarning;

  /// No description provided for @yourFleetReady.
  ///
  /// In en, this message translates to:
  /// **'Your fleet is ready'**
  String get yourFleetReady;

  /// No description provided for @leaveRoom.
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get leaveRoom;

  /// No description provided for @keepAppOpenLobby.
  ///
  /// In en, this message translates to:
  /// **'Keep this app open and in the foreground. Closing it ends the room for every player.'**
  String get keepAppOpenLobby;

  /// No description provided for @hostOnlySettingsNotice.
  ///
  /// In en, this message translates to:
  /// **'Only the host can change the room settings. You see the current values here.'**
  String get hostOnlySettingsNotice;

  /// No description provided for @rows.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get rows;

  /// No description provided for @columns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get columns;

  /// No description provided for @decreaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Decrease {label}'**
  String decreaseLabel(String label);

  /// No description provided for @increaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Increase {label}'**
  String increaseLabel(String label);

  /// No description provided for @seatedPlayers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} player already in the room.} other{{count} players already in the room.}}'**
  String seatedPlayers(int count);

  /// No description provided for @fleetOptionLabel.
  ///
  /// In en, this message translates to:
  /// **'{label} · {count} ships'**
  String fleetOptionLabel(String label, int count);

  /// No description provided for @fleetLengths.
  ///
  /// In en, this message translates to:
  /// **'Lengths {summary}'**
  String fleetLengths(String summary);

  /// No description provided for @preparation.
  ///
  /// In en, this message translates to:
  /// **'Preparation'**
  String get preparation;

  /// No description provided for @eachTurn.
  ///
  /// In en, this message translates to:
  /// **'Each turn'**
  String get eachTurn;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get saveSettings;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to the default settings'**
  String get resetToDefaults;

  /// No description provided for @roomNoLongerOpen.
  ///
  /// In en, this message translates to:
  /// **'The room is no longer open.'**
  String get roomNoLongerOpen;

  /// No description provided for @rotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get rotate;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @youAreReady.
  ///
  /// In en, this message translates to:
  /// **'You are ready'**
  String get youAreReady;

  /// No description provided for @iAmReady.
  ///
  /// In en, this message translates to:
  /// **'I am ready'**
  String get iAmReady;

  /// No description provided for @placeEveryShipFirst.
  ///
  /// In en, this message translates to:
  /// **'Place every ship first'**
  String get placeEveryShipFirst;

  /// No description provided for @preparationEndsIn.
  ///
  /// In en, this message translates to:
  /// **'The preparation ends in {clock}'**
  String preparationEndsIn(String clock);

  /// No description provided for @autoPlaceHint.
  ///
  /// In en, this message translates to:
  /// **'A fleet that is not finished in time is placed automatically.'**
  String get autoPlaceHint;

  /// No description provided for @placing.
  ///
  /// In en, this message translates to:
  /// **'Placing'**
  String get placing;

  /// No description provided for @matchEnded.
  ///
  /// In en, this message translates to:
  /// **'Match ended'**
  String get matchEnded;

  /// No description provided for @theMatch.
  ///
  /// In en, this message translates to:
  /// **'The match'**
  String get theMatch;

  /// No description provided for @matchNotStarted.
  ///
  /// In en, this message translates to:
  /// **'The match has not started yet.'**
  String get matchNotStarted;

  /// No description provided for @spectating.
  ///
  /// In en, this message translates to:
  /// **'Spectating'**
  String get spectating;

  /// No description provided for @yourBoard.
  ///
  /// In en, this message translates to:
  /// **'Your board'**
  String get yourBoard;

  /// No description provided for @leaveTheMatch.
  ///
  /// In en, this message translates to:
  /// **'Leave the match?'**
  String get leaveTheMatch;

  /// No description provided for @endMatchForEveryone.
  ///
  /// In en, this message translates to:
  /// **'This ends the match for every player.'**
  String get endMatchForEveryone;

  /// No description provided for @youWillLeaveMatch.
  ///
  /// In en, this message translates to:
  /// **'You will leave this match.'**
  String get youWillLeaveMatch;

  /// No description provided for @target.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get target;

  /// No description provided for @noTargetsLeft.
  ///
  /// In en, this message translates to:
  /// **'There is nobody left to shoot at.'**
  String get noTargetsLeft;

  /// No description provided for @sharedMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Shared map'**
  String get sharedMapTitle;

  /// No description provided for @legendHit.
  ///
  /// In en, this message translates to:
  /// **'hit'**
  String get legendHit;

  /// No description provided for @legendSunk.
  ///
  /// In en, this message translates to:
  /// **'sunk'**
  String get legendSunk;

  /// No description provided for @legendMiss.
  ///
  /// In en, this message translates to:
  /// **'your miss'**
  String get legendMiss;

  /// No description provided for @closeMatch.
  ///
  /// In en, this message translates to:
  /// **'Leave match'**
  String get closeMatch;

  /// No description provided for @selectedCell.
  ///
  /// In en, this message translates to:
  /// **'Selected: {cell}'**
  String selectedCell(String cell);

  /// No description provided for @selectedCellAlreadyFired.
  ///
  /// In en, this message translates to:
  /// **'Selected: {cell} — already fired here'**
  String selectedCellAlreadyFired(String cell);

  /// No description provided for @waitingForHost.
  ///
  /// In en, this message translates to:
  /// **'Waiting for host…'**
  String get waitingForHost;

  /// No description provided for @doubleTapToFire.
  ///
  /// In en, this message translates to:
  /// **'Double-tap a cell to fire at every opponent.'**
  String get doubleTapToFire;

  /// No description provided for @yourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get yourTurn;

  /// No description provided for @activityMissed.
  ///
  /// In en, this message translates to:
  /// **'{attacker} missed {target}.'**
  String activityMissed(String attacker, String target);

  /// No description provided for @activityHit.
  ///
  /// In en, this message translates to:
  /// **'{attacker} hit {target}.'**
  String activityHit(String attacker, String target);

  /// No description provided for @activitySunk.
  ///
  /// In en, this message translates to:
  /// **'{attacker} sank a ship of {target}.'**
  String activitySunk(String attacker, String target);

  /// No description provided for @battleActivitySunk.
  ///
  /// In en, this message translates to:
  /// **'{attacker} sank a ship belonging to {target}.'**
  String battleActivitySunk(String attacker, String target);

  /// No description provided for @feedbackYouMissed.
  ///
  /// In en, this message translates to:
  /// **'Your shot missed.'**
  String get feedbackYouMissed;

  /// No description provided for @feedbackYouHit.
  ///
  /// In en, this message translates to:
  /// **'Your shot hit a ship.'**
  String get feedbackYouHit;

  /// No description provided for @feedbackYouSunk.
  ///
  /// In en, this message translates to:
  /// **'Your shot sank a ship.'**
  String get feedbackYouSunk;

  /// No description provided for @feedbackTargetMissed.
  ///
  /// In en, this message translates to:
  /// **'A shot missed your board.'**
  String get feedbackTargetMissed;

  /// No description provided for @feedbackTargetHit.
  ///
  /// In en, this message translates to:
  /// **'A shot hit one of your ships.'**
  String get feedbackTargetHit;

  /// No description provided for @feedbackTargetSunk.
  ///
  /// In en, this message translates to:
  /// **'One of your ships was sunk.'**
  String get feedbackTargetSunk;

  /// No description provided for @feedbackOthers.
  ///
  /// In en, this message translates to:
  /// **'The other players are shooting at each other.'**
  String get feedbackOthers;

  /// No description provided for @matchIsOver.
  ///
  /// In en, this message translates to:
  /// **'The match is over.'**
  String get matchIsOver;

  /// No description provided for @yourBoardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your board is not available.'**
  String get yourBoardUnavailable;

  /// No description provided for @ownBoardHint.
  ///
  /// In en, this message translates to:
  /// **'The coloured cells are the hits on your fleet, in the colour of the player who fired them. Only you and the host see this board.'**
  String get ownBoardHint;

  /// No description provided for @turnOrder.
  ///
  /// In en, this message translates to:
  /// **'Turn order'**
  String get turnOrder;

  /// No description provided for @inTheMatch.
  ///
  /// In en, this message translates to:
  /// **'In the match'**
  String get inTheMatch;

  /// No description provided for @eliminated.
  ///
  /// In en, this message translates to:
  /// **'Eliminated'**
  String get eliminated;

  /// No description provided for @matchResult.
  ///
  /// In en, this message translates to:
  /// **'Match result'**
  String get matchResult;

  /// No description provided for @matchNotFinished.
  ///
  /// In en, this message translates to:
  /// **'The match has not finished yet.'**
  String get matchNotFinished;

  /// No description provided for @lastedDuration.
  ///
  /// In en, this message translates to:
  /// **'Lasted {duration}'**
  String lastedDuration(String duration);

  /// No description provided for @lastedDurationWithRank.
  ///
  /// In en, this message translates to:
  /// **'Lasted {duration} · You finished #{rank}'**
  String lastedDurationWithRank(String duration, int rank);

  /// No description provided for @finalRanking.
  ///
  /// In en, this message translates to:
  /// **'Final ranking'**
  String get finalRanking;

  /// No description provided for @rankingHint.
  ///
  /// In en, this message translates to:
  /// **'The ranking and every statistic come from the host. All players see the same result.'**
  String get rankingHint;

  /// No description provided for @endRoomAndReturnHome.
  ///
  /// In en, this message translates to:
  /// **'End room and return home'**
  String get endRoomAndReturnHome;

  /// No description provided for @returnHome.
  ///
  /// In en, this message translates to:
  /// **'Return home'**
  String get returnHome;

  /// No description provided for @matchOverClosesRoom.
  ///
  /// In en, this message translates to:
  /// **'The match is over. This closes the room for everyone.'**
  String get matchOverClosesRoom;

  /// No description provided for @nobodySurvived.
  ///
  /// In en, this message translates to:
  /// **'Nobody survived the match.'**
  String get nobodySurvived;

  /// No description provided for @playerWonMatch.
  ///
  /// In en, this message translates to:
  /// **'{name} won the match.'**
  String playerWonMatch(String name);

  /// No description provided for @rankingStats.
  ///
  /// In en, this message translates to:
  /// **'{shots} shots · {hits} hits · {misses} misses · {sunk} sunk · {timeouts} timeouts'**
  String rankingStats(int shots, int hits, int misses, int sunk, int timeouts);

  /// No description provided for @reviewAllFleets.
  ///
  /// In en, this message translates to:
  /// **'Review all fleets'**
  String get reviewAllFleets;

  /// No description provided for @allFleets.
  ///
  /// In en, this message translates to:
  /// **'All fleets'**
  String get allFleets;

  /// No description provided for @allFleetsHint.
  ///
  /// In en, this message translates to:
  /// **'The match is over, so every fleet is revealed. Each board shows where the ships were and every shot they took.'**
  String get allFleetsHint;

  /// No description provided for @fleetReviewSummary.
  ///
  /// In en, this message translates to:
  /// **'{ships} ships · {sunk} sunk'**
  String fleetReviewSummary(int ships, int sunk);

  /// No description provided for @fleetsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No fleet was recorded.'**
  String get fleetsUnavailable;

  /// No description provided for @shootersLegend.
  ///
  /// In en, this message translates to:
  /// **'Shot colours'**
  String get shootersLegend;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @yourFleetWasSunk.
  ///
  /// In en, this message translates to:
  /// **'Your fleet was sunk.'**
  String get yourFleetWasSunk;

  /// No description provided for @spectatorWatching.
  ///
  /// In en, this message translates to:
  /// **'You are watching the rest of the match. You cannot fire.'**
  String get spectatorWatching;

  /// No description provided for @keepWatching.
  ///
  /// In en, this message translates to:
  /// **'Keep watching'**
  String get keepWatching;

  /// No description provided for @stillInTheMatch.
  ///
  /// In en, this message translates to:
  /// **'Still in the match'**
  String get stillInTheMatch;

  /// No description provided for @nobodyIsLeft.
  ///
  /// In en, this message translates to:
  /// **'Nobody is left.'**
  String get nobodyIsLeft;

  /// No description provided for @publicActivity.
  ///
  /// In en, this message translates to:
  /// **'Public activity'**
  String get publicActivity;

  /// No description provided for @noPublicShots.
  ///
  /// In en, this message translates to:
  /// **'No public shots yet.'**
  String get noPublicShots;

  /// No description provided for @spectatorHint.
  ///
  /// In en, this message translates to:
  /// **'Spectators see no coordinates and no enemy fleet. Your own fleet stays available below.'**
  String get spectatorHint;

  /// No description provided for @battleMapSemantics.
  ///
  /// In en, this message translates to:
  /// **'Battle map with your fleet, {rows} rows by {columns} columns. Tap a cell to select it, double-tap to fire.'**
  String battleMapSemantics(int rows, int columns);

  /// No description provided for @ownBoardSemantics.
  ///
  /// In en, this message translates to:
  /// **'Your board, {rows} rows by {columns} columns.'**
  String ownBoardSemantics(int rows, int columns);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
