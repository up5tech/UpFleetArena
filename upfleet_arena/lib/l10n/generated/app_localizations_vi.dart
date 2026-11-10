// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'UpFleet Arena';

  @override
  String get cancel => 'Hủy';

  @override
  String get edit => 'Sửa';

  @override
  String get players => 'Người chơi';

  @override
  String get board => 'Bàn chơi';

  @override
  String get fleet => 'Hạm đội';

  @override
  String get timers => 'Thời gian';

  @override
  String get port => 'Cổng';

  @override
  String get ready => 'Sẵn sàng';

  @override
  String get host => 'Chủ phòng';

  @override
  String get backToHome => 'Về trang chủ';

  @override
  String get endRoom => 'Kết thúc phòng';

  @override
  String get endTheRoom => 'Kết thúc phòng?';

  @override
  String get roomSettings => 'Cài đặt phòng';

  @override
  String get invitationCode => 'Mã mời';

  @override
  String get noNicknameYet => 'Chưa có biệt danh';

  @override
  String get prepareYourFleet => 'Chuẩn bị hạm đội';

  @override
  String get yourFleet => 'Hạm đội của bạn';

  @override
  String get nobodyInRoom => 'Chưa có ai trong phòng.';

  @override
  String get battle => 'Chiến đấu';

  @override
  String get lobby => 'Sảnh chờ';

  @override
  String get aPlayer => 'Một người chơi';

  @override
  String get anotherPlayer => 'người chơi khác';

  @override
  String get youWonMatch => 'Bạn đã thắng trận.';

  @override
  String get roomHasClosed => 'Phòng đã đóng.';

  @override
  String get remove => 'Loại';

  @override
  String get leave => 'Rời';

  @override
  String get stop => 'Dừng';

  @override
  String get scan => 'Quét';

  @override
  String get hide => 'Ẩn';

  @override
  String get show => 'Hiện';

  @override
  String cellsCount(int count) {
    return '$count ô';
  }

  @override
  String shipsLeftCount(int count) {
    return 'còn $count tàu';
  }

  @override
  String timeoutsCount(int count) {
    return '$count lần hết giờ';
  }

  @override
  String playerNameYou(String name) {
    return '$name (bạn)';
  }

  @override
  String playerIsShooting(String name) {
    return '$name đang bắn';
  }

  @override
  String turnLabel(int turn) {
    return 'Lượt $turn';
  }

  @override
  String secondsShort(int seconds) {
    return '${seconds}s';
  }

  @override
  String turnLabelWithTime(int turn, int seconds) {
    return 'Lượt $turn · còn ${seconds}s';
  }

  @override
  String get lanOnlyNoBackend => 'Chỉ LAN · không máy chủ';

  @override
  String get heroTitle => 'Hải chiến theo lượt\ncho cùng mạng Wi-Fi';

  @override
  String get heroBody =>
      'Mỗi người chơi đặt một hạm đội riêng, rồi lần lượt bắn vào đối phương. Chủ phòng chạy toàn bộ trò chơi trên điện thoại của họ — không máy chủ, không tài khoản, không cần kết nối Internet.';

  @override
  String get lanLab => 'LAN Lab';

  @override
  String get lanLabSubtitle => 'Chẩn đoán cho nhà phát triển — chỉ bản debug';

  @override
  String get createRoom => 'Tạo phòng';

  @override
  String get createRoomSubtitle => 'Làm chủ phòng và chia sẻ mã mời';

  @override
  String get joinRoom => 'Vào phòng';

  @override
  String get joinRoomSubtitle => 'Tìm phòng lân cận và vào bằng mã';

  @override
  String get playVsComputer => 'Chơi với máy';

  @override
  String get playVsComputerSubtitle => 'Đấu một mình với máy, không cần Wi-Fi';

  @override
  String get chooseDifficulty => 'Chọn độ khó';

  @override
  String get difficultyEasy => 'Dễ';

  @override
  String get difficultyMedium => 'Trung bình';

  @override
  String get difficultyHard => 'Khó';

  @override
  String get difficultyEasyHint =>
      'Bắn ngẫu nhiên và không dò theo phát trúng.';

  @override
  String get difficultyMediumHint =>
      'Bắn tiếp quanh phát trúng cho đến khi chìm tàu.';

  @override
  String get difficultyHardHint =>
      'Dò theo ô so le và kết liễu tàu bị thương — đối thủ khó.';

  @override
  String botDisplayName(String difficulty) {
    return 'Máy ($difficulty)';
  }

  @override
  String get startPractice => 'Bắt đầu chơi';

  @override
  String get startingPractice => 'Đang chuẩn bị…';

  @override
  String get practiceHint =>
      'Máy chơi ngay trên thiết bị này. Xếp hạm đội rồi lần lượt bắn vào nhau.';

  @override
  String get addComputerTitle => 'Thêm đối thủ máy';

  @override
  String get addComputer => 'Thêm máy';

  @override
  String get addComputerHint =>
      'Máy chiếm một chỗ như người chơi: tự xếp hạm đội và bắn vào lượt của nó. Chỉ chủ phòng thêm hoặc loại được.';

  @override
  String get computer => 'Máy';

  @override
  String get computerOpponents => 'Đối thủ máy';

  @override
  String get computerCount => 'Số máy';

  @override
  String get computerSettingsHint =>
      'Máy vào phòng ngay khi bạn lưu và tự xếp hạm đội. Máy chiếm một chỗ của người chơi nên vẫn tính vào sức chứa phòng.';

  @override
  String get lobbySubtitle => 'Người chơi, trạng thái sẵn sàng và bắt đầu trận';

  @override
  String get shipPlacement => 'Xếp tàu';

  @override
  String get shipPlacementSubtitle =>
      'Sắp xếp hạm đội riêng trước khi trận bắt đầu';

  @override
  String get battleSubtitle => 'Chiến đấu theo lượt trên bàn mục tiêu';

  @override
  String get profileAndSettings => 'Hồ sơ & Cài đặt';

  @override
  String get profileAndSettingsSubtitle =>
      'Biệt danh, ảnh đại diện, âm thanh, rung và ngôn ngữ';

  @override
  String get inRoomOnly => 'Hãy tạo hoặc tham gia một phòng trước.';

  @override
  String get later => 'Để sau';

  @override
  String get frozenDefaults => 'Mặc định cố định';

  @override
  String get network => 'Mạng';

  @override
  String get discovery => 'Dò tìm';

  @override
  String get fleetPresetSmall => 'Nhỏ';

  @override
  String get fleetPresetStandard => 'Chuẩn';

  @override
  String get fleetPresetLarge => 'Lớn';

  @override
  String fleetConstraintValue(String lengths) {
    return 'Chuẩn · $lengths';
  }

  @override
  String timersConstraintValue(int placement, int turn) {
    return '${placement}s xếp tàu · ${turn}s mỗi lượt';
  }

  @override
  String get hostExitWarning =>
      'Chủ phòng thoát sẽ kết thúc phòng với mọi người chơi. Không có chuyển chủ phòng và không dự phòng Internet.';

  @override
  String get yourProfile => 'Hồ sơ của bạn';

  @override
  String get nickname => 'Biệt danh';

  @override
  String get nicknameHint => 'Người chơi khác sẽ thấy bạn như thế nào?';

  @override
  String get nicknamePrivacy =>
      'Biệt danh được lưu trên thiết bị này và chỉ chia sẻ với người chơi trong phòng bạn vào.';

  @override
  String get profileSaved => 'Đã lưu hồ sơ trên thiết bị này.';

  @override
  String get avatar => 'Ảnh đại diện';

  @override
  String get soundAndEffects => 'Âm thanh & hiệu ứng';

  @override
  String get soundEffects => 'Hiệu ứng âm thanh';

  @override
  String get soundEffectsSubtitle => 'Âm thanh bắn, trúng và kết quả';

  @override
  String get hapticFeedback => 'Phản hồi rung';

  @override
  String get hapticFeedbackSubtitle => 'Rung khi bắn và khi có kết quả';

  @override
  String get reduceMotion => 'Giảm chuyển động';

  @override
  String get reduceMotionSubtitle =>
      'Rút ngắn hiệu ứng; cũng tôn trọng cài đặt hệ thống';

  @override
  String get saveProfile => 'Lưu hồ sơ';

  @override
  String get language => 'Ngôn ngữ';

  @override
  String get languageSubtitle => 'Chọn ngôn ngữ cho toàn bộ ứng dụng.';

  @override
  String get followSystem => 'Theo hệ thống';

  @override
  String get english => 'English';

  @override
  String get vietnamese => 'Tiếng Việt';

  @override
  String get createRoomScreenTitle => 'Tạo phòng';

  @override
  String get youWillHost => 'Bạn sẽ làm chủ phòng này';

  @override
  String get defaultSettingsHint =>
      'Đây là cài đặt mặc định. Chủ phòng có thể thay đổi trong sảnh trước khi trận bắt đầu.';

  @override
  String get creating => 'Đang tạo…';

  @override
  String get pickNicknameFirst => 'Hãy chọn biệt danh trước khi tạo phòng.';

  @override
  String get whileYouHost => 'Trong khi làm chủ phòng';

  @override
  String get keepAppOpenHost =>
      'Giữ ứng dụng mở và hiển thị. Đóng ứng dụng sẽ kết thúc phòng với mọi người chơi — không có chuyển chủ phòng.';

  @override
  String get joinRoomScreenTitle => 'Vào phòng';

  @override
  String get invitationCodeHint =>
      'Chủ phòng chia sẻ mã này. Mã được kiểm tra bởi thiết bị chủ phòng qua kết nối trực tiếp, không qua thông báo mạng.';

  @override
  String get nearbyRooms => 'Phòng lân cận';

  @override
  String get lookingForRooms => 'Đang tìm phòng trên Wi-Fi này…';

  @override
  String get noRoomsFound =>
      'Chưa tìm thấy phòng. Nhấn Quét, hoặc dùng kết nối thủ công bên dưới.';

  @override
  String get noAddress => 'không có địa chỉ';

  @override
  String get joinSelectedRoom => 'Vào phòng đã chọn';

  @override
  String get manualConnection => 'Kết nối thủ công';

  @override
  String get manualConnectionHint =>
      'Dùng khi bộ định tuyến chặn dò tìm. Nhập địa chỉ IPv4 và cổng hiển thị trên thiết bị chủ phòng.';

  @override
  String get hostIpv4 => 'IPv4 chủ phòng';

  @override
  String get connectManually => 'Kết nối thủ công';

  @override
  String get portMustBeNumber => 'Cổng phải là một số.';

  @override
  String get nothingFound => 'Không tìm thấy gì?';

  @override
  String get routerIsolationHint =>
      'Bộ định tuyến có thể cô lập các thiết bị với nhau. Kết nối thủ công ở trên dùng liên kết TCP trực tiếp, nên đôi khi hoạt động khi dò tìm bị lọc.';

  @override
  String get waitingForRoomState => 'Đang chờ trạng thái phòng…';

  @override
  String get youSuffix => '  (bạn)';

  @override
  String get statusConnected => 'Đã kết nối';

  @override
  String get statusDisconnected => 'Mất kết nối — có thể vào lại';

  @override
  String get statusLeft => 'Đã rời phòng';

  @override
  String get statusKicked => 'Bị chủ phòng loại';

  @override
  String removePlayer(String name) {
    return 'Loại $name';
  }

  @override
  String get copyTheCode => 'Sao chép mã';

  @override
  String get invitationCodeCopied => 'Đã sao chép mã mời.';

  @override
  String get shareTheInvitation => 'Chia sẻ lời mời';

  @override
  String get manualAddress => 'Địa chỉ thủ công';

  @override
  String get notAvailable => 'không khả dụng';

  @override
  String get shareCodeHint =>
      'Chia sẻ mã với người chơi cùng mạng Wi-Fi. Mã không nằm trong thông báo mạng, nên chỉ người bạn báo mới có thể vào.';

  @override
  String get shareJoinLine => 'Hãy vào phòng UpFleet Arena của tôi.';

  @override
  String shareCodeLine(String code) {
    return 'Mã mời: $code';
  }

  @override
  String shareAddressLine(String address) {
    return 'Địa chỉ thủ công: $address';
  }

  @override
  String get shareWifiLine => 'Mọi người chơi phải ở cùng mạng Wi-Fi.';

  @override
  String get shareSubject => 'Lời mời UpFleet Arena';

  @override
  String get sharingNotAvailable => 'Chia sẻ không khả dụng ở đây.';

  @override
  String fleetSettingsValue(String label, int count, String summary) {
    return '$label · $count tàu ($summary)';
  }

  @override
  String get capacity => 'Sức chứa';

  @override
  String capacityValue(int count) {
    return 'tối đa $count người chơi';
  }

  @override
  String timersSettingsValue(int placement, int turn) {
    return '$placement s chuẩn bị · $turn s mỗi lượt';
  }

  @override
  String get onlyHostChangesSettings =>
      'Chỉ chủ phòng mới có thể thay đổi cài đặt này.';

  @override
  String get startPreparation => 'Bắt đầu chuẩn bị';

  @override
  String get preparationTimeoutHint =>
      'Khi hết thời gian chuẩn bị, chủ phòng tự động xếp các tàu còn thiếu và trận bắt đầu.';

  @override
  String removePlayerQuestion(String name) {
    return 'Loại $name?';
  }

  @override
  String get removePlayerWarning =>
      'Người này bị loại khỏi phòng và không thể vào lại bằng mã mời này.';

  @override
  String get endRoomWarning =>
      'Mọi người chơi bị ngắt kết nối và trở về trang chủ. Phòng không thể mở lại.';

  @override
  String get yourFleetReady => 'Hạm đội của bạn đã sẵn sàng';

  @override
  String get leaveRoom => 'Rời phòng';

  @override
  String get keepAppOpenLobby =>
      'Giữ ứng dụng mở và hiển thị. Đóng ứng dụng sẽ kết thúc phòng với mọi người chơi.';

  @override
  String get hostOnlySettingsNotice =>
      'Chỉ chủ phòng mới có thể thay đổi cài đặt phòng. Bạn xem các giá trị hiện tại ở đây.';

  @override
  String get rows => 'Hàng';

  @override
  String get columns => 'Cột';

  @override
  String decreaseLabel(String label) {
    return 'Giảm $label';
  }

  @override
  String increaseLabel(String label) {
    return 'Tăng $label';
  }

  @override
  String seatedPlayers(int count) {
    return '$count người chơi đã ở trong phòng.';
  }

  @override
  String fleetOptionLabel(String label, int count) {
    return '$label · $count tàu';
  }

  @override
  String fleetLengths(String summary) {
    return 'Chiều dài $summary';
  }

  @override
  String get preparation => 'Chuẩn bị';

  @override
  String get eachTurn => 'Mỗi lượt';

  @override
  String get saving => 'Đang lưu…';

  @override
  String get saveSettings => 'Lưu cài đặt';

  @override
  String get resetToDefaults => 'Đặt lại về cài đặt mặc định';

  @override
  String get roomNoLongerOpen => 'Phòng không còn mở.';

  @override
  String get rotate => 'Xoay';

  @override
  String get undo => 'Hoàn tác';

  @override
  String get auto => 'Tự động';

  @override
  String get youAreReady => 'Bạn đã sẵn sàng';

  @override
  String get iAmReady => 'Tôi đã sẵn sàng';

  @override
  String get placeEveryShipFirst => 'Hãy xếp hết tàu trước';

  @override
  String preparationEndsIn(String clock) {
    return 'Chuẩn bị kết thúc sau $clock';
  }

  @override
  String get autoPlaceHint =>
      'Hạm đội chưa hoàn thành kịp sẽ được xếp tự động.';

  @override
  String get placing => 'Đang xếp';

  @override
  String get matchEnded => 'Trận đã kết thúc';

  @override
  String get theMatch => 'Trận đấu';

  @override
  String get matchNotStarted => 'Trận đấu chưa bắt đầu.';

  @override
  String get spectating => 'Đang xem';

  @override
  String get yourBoard => 'Bàn của bạn';

  @override
  String get leaveTheMatch => 'Rời trận đấu?';

  @override
  String get endMatchForEveryone =>
      'Việc này kết thúc trận đấu với mọi người chơi.';

  @override
  String get youWillLeaveMatch => 'Bạn sẽ rời trận đấu này.';

  @override
  String get target => 'Mục tiêu';

  @override
  String get noTargetsLeft => 'Không còn ai để bắn.';

  @override
  String get boardLegend => 'Chấm: trượt · Chấm đầy: trúng · Vòng: chìm';

  @override
  String selectedCell(String cell) {
    return 'Đã chọn: $cell';
  }

  @override
  String selectedCellAlreadyFired(String cell) {
    return 'Đã chọn: $cell — đã bắn vào đây';
  }

  @override
  String get waitingForHost => 'Đang chờ chủ phòng…';

  @override
  String get fireAtThisCell => 'Bắn vào ô này';

  @override
  String get waitForYourTurn => 'Chờ đến lượt bạn';

  @override
  String get yourTurn => 'Lượt của bạn';

  @override
  String activityMissed(String attacker, String target) {
    return '$attacker bắn trượt $target.';
  }

  @override
  String activityHit(String attacker, String target) {
    return '$attacker bắn trúng $target.';
  }

  @override
  String activitySunk(String attacker, String target) {
    return '$attacker bắn chìm một tàu của $target.';
  }

  @override
  String battleActivitySunk(String attacker, String target) {
    return '$attacker bắn chìm một tàu của $target.';
  }

  @override
  String get feedbackYouMissed => 'Phát bắn của bạn trượt.';

  @override
  String get feedbackYouHit => 'Phát bắn của bạn trúng một tàu.';

  @override
  String get feedbackYouSunk => 'Phát bắn của bạn đánh chìm một tàu.';

  @override
  String get feedbackTargetMissed => 'Một phát bắn trượt bàn của bạn.';

  @override
  String get feedbackTargetHit => 'Một phát bắn trúng một tàu của bạn.';

  @override
  String get feedbackTargetSunk => 'Một tàu của bạn bị đánh chìm.';

  @override
  String get feedbackOthers => 'Những người chơi khác đang bắn lẫn nhau.';

  @override
  String get matchIsOver => 'Trận đấu đã kết thúc.';

  @override
  String get yourBoardUnavailable => 'Bàn của bạn không khả dụng.';

  @override
  String get ownBoardHint =>
      'Các ô đỏ là những phát trúng hạm đội của bạn. Chỉ bạn và chủ phòng thấy bàn này.';

  @override
  String get turnOrder => 'Thứ tự lượt';

  @override
  String get inTheMatch => 'Còn trong trận';

  @override
  String get eliminated => 'Bị loại';

  @override
  String get matchResult => 'Kết quả trận';

  @override
  String get matchNotFinished => 'Trận đấu chưa kết thúc.';

  @override
  String lastedDuration(String duration) {
    return 'Kéo dài $duration';
  }

  @override
  String lastedDurationWithRank(String duration, int rank) {
    return 'Kéo dài $duration · Bạn về đích #$rank';
  }

  @override
  String get finalRanking => 'Xếp hạng chung cuộc';

  @override
  String get rankingHint =>
      'Xếp hạng và mọi thống kê đến từ chủ phòng. Mọi người chơi thấy cùng kết quả.';

  @override
  String get endRoomAndReturnHome => 'Kết thúc phòng và về trang chủ';

  @override
  String get returnHome => 'Về trang chủ';

  @override
  String get matchOverClosesRoom =>
      'Trận đấu đã kết thúc. Việc này đóng phòng với mọi người.';

  @override
  String get nobodySurvived => 'Không ai sống sót sau trận.';

  @override
  String playerWonMatch(String name) {
    return '$name đã thắng trận.';
  }

  @override
  String rankingStats(int shots, int hits, int misses, int sunk, int timeouts) {
    return '$shots phát bắn · $hits trúng · $misses trượt · $sunk chìm · $timeouts lần hết giờ';
  }

  @override
  String get yourFleetWasSunk => 'Hạm đội của bạn đã bị chìm.';

  @override
  String get spectatorWatching =>
      'Bạn đang xem phần còn lại của trận. Bạn không thể bắn.';

  @override
  String get stillInTheMatch => 'Còn trong trận';

  @override
  String get nobodyIsLeft => 'Không còn ai.';

  @override
  String get publicActivity => 'Hoạt động công khai';

  @override
  String get noPublicShots => 'Chưa có phát bắn công khai nào.';

  @override
  String get spectatorHint =>
      'Người xem không thấy tọa độ và không thấy hạm đội đối phương. Bàn của bạn vẫn khả dụng ở tab kế tiếp.';

  @override
  String targetBoardSemantics(int rows, int columns) {
    return 'Bàn mục tiêu, $rows hàng và $columns cột. Chạm một ô để chọn.';
  }

  @override
  String ownBoardSemantics(int rows, int columns) {
    return 'Bàn của bạn, $rows hàng và $columns cột.';
  }
}
