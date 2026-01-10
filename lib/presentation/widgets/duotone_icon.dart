/// Duotone SVG Icon System
/// Replaces Material Icons with custom duotone SVG icons
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// App-wide icon identifiers mapped to SVG file names
class AppIcons {
  AppIcons._();

  // Security
  static const String shield = 'shield';
  static const String shieldCheck = 'shield_check';
  static const String shieldWarning = 'shield_warning';
  static const String shieldCross = 'shield_cross';
  static const String shieldPlus = 'shield_plus';
  static const String shieldMinus = 'shield_minus';
  static const String shieldStar = 'shield_star';
  static const String shieldUser = 'shield_user';
  static const String shieldNetwork = 'shield_network';
  static const String shieldKeyhole = 'shield_keyhole';
  static const String lock = 'lock';
  static const String lockUnlocked = 'lock_unlocked';
  static const String lockKeyhole = 'lock_keyhole';
  static const String key = 'key';
  static const String keySquare = 'key_square';
  static const String eye = 'eye';
  static const String eyeClosed = 'eye_closed';
  static const String eyeScan = 'eye_scan';
  static const String incognito = 'incognito';
  static const String bomb = 'bomb';
  static const String siren = 'siren';
  static const String password = 'password';
  static const String codeScan = 'code_scan';
  static const String objectScan = 'object_scan';
  static const String scanner = 'scanner';
  static const String qrCode = 'qr_code';

  // Users
  static const String user = 'user';
  static const String userRounded = 'user_rounded';
  static const String userCircle = 'user_circle';
  static const String userCheck = 'user_check';
  static const String userCross = 'user_cross';
  static const String userPlus = 'user_plus';
  static const String userMinus = 'user_minus';
  static const String userBlock = 'user_block';
  static const String userHeart = 'user_heart';
  static const String userId = 'user_id';
  static const String userSpeak = 'user_speak';
  static const String usersGroup = 'users_group_rounded';

  // Messages & Communication
  static const String chatDots = 'chat_dots';
  static const String chatLine = 'chat_line';
  static const String chatRound = 'chat_round';
  static const String chatSquare = 'chat__square';
  static const String letter = 'letter';
  static const String letterOpened = 'letter_opened';
  static const String inbox = 'inbox';
  static const String paperclip = 'paperclip';
  static const String pen = 'pen';
  static const String forward = 'forward';

  // Devices & Electronics
  static const String smartphone = 'smartphone';
  static const String laptop = 'laptop';
  static const String monitor = 'monitor';
  static const String tablet = 'tablet';
  static const String devices = 'devices';
  static const String server = 'server';
  static const String serverSquare = 'server_square';
  static const String database = 'database';
  static const String cpu = 'cpu';
  static const String simCard = 'sim_card';
  static const String sdCard = 'sd_card';
  static const String keyboard = 'keyboard';
  static const String mouse = 'mouse';
  static const String printer = 'printer';
  static const String tv = 'tv';
  static const String headphones = 'headphones_round';
  static const String bluetooth = 'bluetooth';
  static const String wifi = 'wi_fi_router';
  static const String wifiRouter = 'wi_fi_router_round';
  static const String cloudStorage = 'cloud_storage';
  static const String flashDrive = 'flash_drive';
  static const String lightbulb = 'lightbulb';

  // Network & IT
  static const String bug = 'bug';
  static const String bugMinimalistic = 'bug_minimalistic';
  static const String code = 'code';
  static const String codeSquare = 'code_square';
  static const String codeCircle = 'code_circle';
  static const String programming = 'programming';
  static const String hashtag = 'hashtag';
  static const String structure = 'structure';
  static const String station = 'station';
  static const String usb = 'usb';
  static const String screencast = 'screencast';
  static const String sidebar = 'siderbar';
  static const String command = 'command';

  // Navigation & Arrows
  static const String arrowUp = 'arrow_up';
  static const String arrowDown = 'arrow_down';
  static const String arrowLeft = 'arrow_left';
  static const String arrowRight = 'arrow_right';
  static const String chevronUp = 'alt_arrow_up';
  static const String chevronDown = 'alt_arrow_down';
  static const String chevronLeft = 'alt_arrow_left';
  static const String chevronRight = 'alt_arrow_right';
  static const String refresh = 'refresh';
  static const String restart = 'restart';
  static const String transferHorizontal = 'transfer_horizontal';
  static const String transferVertical = 'transfer_vertical';
  static const String sortHorizontal = 'sort_horizontal';
  static const String sortVertical = 'sort_vertical';

  // Essential UI
  static const String home = 'home';
  static const String homeAngle = 'home_angle';
  static const String homeSmile = 'home_smile';
  static const String settings = 'settings';
  static const String settingsMinimalistic = 'settings_minimalistic';
  static const String tuning = 'tuning';
  static const String tuningSquare = 'tuning_square';
  static const String widget = 'widget';
  static const String widgetAdd = 'widget_add';
  static const String filter = 'filter';
  static const String sort = 'sort';
  static const String menu = 'hamburger_menu';
  static const String menuDots = 'menu_dots';
  static const String menuDotsCircle = 'menu_dots_circle';
  static const String addCircle = 'add_circle';
  static const String addSquare = 'add_square';
  static const String minusCircle = 'minus_circle';
  static const String minusSquare = 'minus_square';
  static const String closeCircle = 'close_circle';
  static const String closeSquare = 'close_square';
  static const String checkCircle = 'check_circle';
  static const String checkSquare = 'check_square';
  static const String infoCircle = 'info_circle';
  static const String infoSquare = 'info_square';
  static const String questionCircle = 'question_circle';
  static const String questionSquare = 'question_square';
  static const String dangerCircle = 'danger_circle';
  static const String dangerTriangle = 'danger_triangle';
  static const String dangerSquare = 'danger_square';
  static const String warning = dangerTriangle;
  static const String forbidden = 'forbidden';
  static const String forbiddenCircle = 'forbidden_circle';
  static const String copy = 'copy';
  static const String trash = 'trash_bin_minimalistic';
  static const String trashBin = 'trash_bin_2';
  static const String pin = 'pin';
  static const String pinCircle = 'pin_circle';
  static const String flag = 'flag';
  static const String target = 'target';
  static const String power = 'power';
  static const String bolt = 'bolt';
  static const String boltCircle = 'bolt_circle';
  static const String flashlight = 'flashlight_on';
  static const String gift = 'gift';
  static const String glasses = 'glasses';
  static const String magic = 'magic_stick';
  static const String magnet = 'magnet';
  static const String mirror = 'mirror';
  static const String box = 'box';
  static const String share = 'share';
  static const String shareCircle = 'share_circle';
  static const String sliderHorizontal = 'slider_horizontal';
  static const String sliderVertical = 'slider_vertical';
  static const String reorder = 'reorder';
  static const String help = 'help';

  // Search
  static const String search = 'magnifer';
  static const String searchZoomIn = 'magnifer_zoom_in';
  static const String searchZoomOut = 'magnifer_zoom_out';
  static const String searchBug = 'magnifer_bug';

  // Notifications
  static const String bell = 'bell';
  static const String bellBing = 'bell_bing';
  static const String bellOff = 'bell_off';
  static const String notification = 'notification_unread';
  static const String notificationRemove = 'notification_remove';

  // Likes & Ratings
  static const String heart = 'heart';
  static const String heartShine = 'heart_shine';
  static const String heartBroken = 'heart_broken';
  static const String like = 'like';
  static const String dislike = 'dislike';
  static const String star = 'star';
  static const String starShine = 'star_shine';
  static const String medal = 'medal_star';
  static const String medalRibbon = 'medal_ribbon';
  static const String crown = 'crown';
  static const String cup = 'cup_star';

  // Business & Stats
  static const String chart = 'chart';
  static const String chartSquare = 'chart_square';
  static const String chartActivity = 'chart_2';
  static const String graph = 'graph';
  static const String graphUp = 'graph_up';
  static const String graphDown = 'graph_down';
  static const String pieChart = 'pie_chart';
  static const String presentation = 'presentation_graph';
  static const String diagram = 'diagram_up';
  static const String courseUp = 'course_up';
  static const String courseDown = 'course_down';

  // Money
  static const String wallet = 'wallet';
  static const String walletMoney = 'wallet_money';
  static const String card = 'card';
  static const String cardTransfer = 'card_transfer';
  static const String banknote = 'banknote';
  static const String dollar = 'dollar';
  static const String dollarCircle = 'dollar_minimalistic';
  static const String moneyBag = 'money_bag';
  static const String safe = 'safe';
  static const String tag = 'tag';
  static const String tagPrice = 'tag_price';
  static const String ticket = 'ticket';
  static const String verifiedCheck = 'verified_check';

  // Quotes & Text
  static const String quoteDown = 'quote_down';
  static const String quoteUp = 'quote_up';
  static const String hook = 'link_round';

  // Files & Folders
  static const String file = 'file';
  static const String fileText = 'file_text';
  static const String fileCheck = 'file_check';
  static const String fileDownload = 'file_download';
  static const String fileRemove = 'file_remove';
  static const String fileCorrupted = 'file_corrupted';
  static const String codeFile = 'code_file';
  static const String zipFile = 'zip_file';
  static const String folder = 'folder';
  static const String folderOpen = 'folder_open';
  static const String folderAdd = 'add_folder';
  static const String folderCheck = 'folder_check';

  // Map & Location
  static const String map = 'map';
  static const String mapPoint = 'map_point';
  static const String mapPointAdd = 'map_point_add';
  static const String mapPointSearch = 'map_point_search';
  static const String mapPointWave = 'map_point_wave';
  static const String compass = 'compass';
  static const String gps = 'gps';
  static const String global = 'global';
  static const String globus = 'globus';
  static const String route = 'route';
  static const String routing = 'routing';
  static const String radar = 'radar';
  static const String peopleNearby = 'people_nearby';
  static const String branchingPaths = 'branching_paths_up';

  // Time
  static const String clock = 'clock_circle';
  static const String clockSquare = 'clock_square';
  static const String alarm = 'alarm';
  static const String stopwatch = 'stopwatch';
  static const String timer = 'history';
  static const String calendar = 'calendar';
  static const String calendarAdd = 'calendar_add';
  static const String calendarCheck = 'calendar_mark';

  // Video & Audio
  static const String play = 'play';
  static const String playCircle = 'play_circle';
  static const String pause = 'pause';
  static const String stop = 'stop';
  static const String volumeHigh = 'volume_loud';
  static const String volumeLow = 'volume';
  static const String volumeMute = 'muted';
  static const String microphone = 'microphone';
  static const String microphoneOff = 'microphone_slash';
  static const String camera = 'camera';
  static const String cameraMinimalistic = 'camera_minimalistic';
  static const String video = 'videocamera';
  static const String videoOff = 'video_frame_cut';
  static const String gallery = 'gallery';
  static const String image = 'gallery_wide';

  // Notes
  static const String document = 'document';
  static const String documentAdd = 'document_add';
  static const String documentText = 'document_text';
  static const String clipboard = 'clipboard';
  static const String clipboardCheck = 'clipboard_check';
  static const String clipboardText = 'clipboard_text';
  static const String notes = 'notes';
  static const String notesMinimalistic = 'notes_minimalistic';

  // App-specific icons
  static const String dashboard = 'widget_5';
  static const String threatHunting = 'magnifer_bug';
  static const String intelligence = 'structure';
  static const String enterprise = 'server_square';
  static const String policy = 'clipboard_text';
  static const String compliance = 'document_add';
  static const String siem = 'server_square';
  static const String stixTaxii = 'transfer_horizontal';
  static const String supplyChain = 'box';
  static const String identity = 'user_id';
  static const String executive = 'crown';
  static const String socialMedia = 'share';
  static const String rogueAp = 'wi_fi_router_round';
  static const String firewall = 'shield_network';
  static const String darkWeb = 'incognito';
  static const String network = 'wi_fi_router';
  static const String appSecurity = 'smartphone';
  static const String smsProtection = 'chat_dots';
  static const String urlProtection = 'link';
  static const String qrScanner = 'qr_code';
  static const String mitre = 'structure';
  static const String mlAnalysis = 'cpu';
  static const String correlation = 'branching_paths_up';
  static const String threatGraph = 'diagram_up';
  static const String campaign = 'flag';
  static const String threatActor = 'user_block';
  static const String malware = 'bug';
  static const String ioc = 'danger_triangle';
  static const String yara = 'code';
  static const String playbooks = 'clipboard_text';
  static const String integrations = 'usb';
  static const String webhooks = 'link';
  static const String desktop = 'monitor';
  static const String vpn = 'shield_keyhole';
  static const String forensics = 'magnifer_bug';
  static const String privacy = 'eye_closed';
  static const String scam = 'danger_circle';
  static const String footprint = 'map_point_wave';
  static const String deviceSecurity = 'smartphone';
}

/// Duotone SVG Icon Widget
class DuotoneIcon extends StatelessWidget {
  final String icon;
  final double size;
  final Color? color;
  final Color? secondaryColor;
  final BlendMode? blendMode;

  const DuotoneIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.secondaryColor,
    this.blendMode,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).iconTheme.color ?? Colors.white;

    return SvgPicture.asset(
      'assets/icons/$icon.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(iconColor, blendMode ?? BlendMode.srcIn),
    );
  }
}

/// Glass-styled icon box with duotone SVG
class GlassDuotoneIconBox extends StatelessWidget {
  final String icon;
  final Color color;
  final double size;
  final double iconSize;
  final double borderRadius;

  const GlassDuotoneIconBox({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize = 20,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: DuotoneIcon(
          icon,
          size: iconSize,
          color: color,
        ),
      ),
    );
  }
}

/// Map Material Icons to SVG icon names for migration
class IconMapper {
  static String fromMaterial(IconData icon) {
    // This maps common Material Icons to our SVG icons
    final mapping = <int, String>{
      Icons.shield.codePoint: AppIcons.shield,
      Icons.shield_outlined.codePoint: AppIcons.shield,
      Icons.security.codePoint: AppIcons.shieldCheck,
      Icons.verified_user.codePoint: AppIcons.shieldUser,
      Icons.gpp_good.codePoint: AppIcons.shieldCheck,
      Icons.gpp_bad.codePoint: AppIcons.shieldCross,
      Icons.gpp_maybe.codePoint: AppIcons.shieldWarning,
      Icons.lock.codePoint: AppIcons.lock,
      Icons.lock_open.codePoint: AppIcons.lockUnlocked,
      Icons.lock_outline.codePoint: AppIcons.lockKeyhole,
      Icons.key.codePoint: AppIcons.key,
      Icons.vpn_key.codePoint: AppIcons.keySquare,
      Icons.visibility.codePoint: AppIcons.eye,
      Icons.visibility_off.codePoint: AppIcons.eyeClosed,
      Icons.remove_red_eye.codePoint: AppIcons.eyeScan,
      Icons.fingerprint.codePoint: AppIcons.objectScan,
      Icons.qr_code.codePoint: AppIcons.qrCode,
      Icons.qr_code_scanner.codePoint: AppIcons.scanner,
      Icons.person.codePoint: AppIcons.user,
      Icons.person_outline.codePoint: AppIcons.userRounded,
      Icons.account_circle.codePoint: AppIcons.userCircle,
      Icons.person_add.codePoint: AppIcons.userPlus,
      Icons.person_remove.codePoint: AppIcons.userMinus,
      Icons.group.codePoint: AppIcons.usersGroup,
      Icons.people.codePoint: AppIcons.usersGroup,
      Icons.badge.codePoint: AppIcons.userId,
      Icons.admin_panel_settings.codePoint: AppIcons.crown,
      Icons.chat.codePoint: AppIcons.chatDots,
      Icons.chat_bubble.codePoint: AppIcons.chatRound,
      Icons.message.codePoint: AppIcons.chatLine,
      Icons.sms.codePoint: AppIcons.chatDots,
      Icons.email.codePoint: AppIcons.letter,
      Icons.mail.codePoint: AppIcons.letter,
      Icons.inbox.codePoint: AppIcons.inbox,
      Icons.attach_file.codePoint: AppIcons.paperclip,
      Icons.edit.codePoint: AppIcons.pen,
      Icons.phone_android.codePoint: AppIcons.smartphone,
      Icons.smartphone.codePoint: AppIcons.smartphone,
      Icons.laptop.codePoint: AppIcons.laptop,
      Icons.computer.codePoint: AppIcons.monitor,
      Icons.desktop_windows.codePoint: AppIcons.monitor,
      Icons.tablet.codePoint: AppIcons.tablet,
      Icons.devices.codePoint: AppIcons.devices,
      Icons.dns.codePoint: AppIcons.server,
      Icons.storage.codePoint: AppIcons.database,
      Icons.memory.codePoint: AppIcons.cpu,
      Icons.sim_card.codePoint: AppIcons.simCard,
      Icons.sd_card.codePoint: AppIcons.sdCard,
      Icons.keyboard.codePoint: AppIcons.keyboard,
      Icons.mouse.codePoint: AppIcons.mouse,
      Icons.print.codePoint: AppIcons.printer,
      Icons.tv.codePoint: AppIcons.tv,
      Icons.headphones.codePoint: AppIcons.headphones,
      Icons.bluetooth.codePoint: AppIcons.bluetooth,
      Icons.wifi.codePoint: AppIcons.wifi,
      Icons.wifi_tethering.codePoint: AppIcons.wifiRouter,
      Icons.router.codePoint: AppIcons.wifiRouter,
      Icons.cloud.codePoint: AppIcons.cloudStorage,
      Icons.usb.codePoint: AppIcons.flashDrive,
      Icons.lightbulb.codePoint: AppIcons.lightbulb,
      Icons.bug_report.codePoint: AppIcons.bug,
      Icons.code.codePoint: AppIcons.code,
      Icons.terminal.codePoint: AppIcons.codeSquare,
      Icons.developer_mode.codePoint: AppIcons.programming,
      Icons.tag.codePoint: AppIcons.hashtag,
      Icons.hub.codePoint: AppIcons.structure,
      Icons.arrow_upward.codePoint: AppIcons.arrowUp,
      Icons.arrow_downward.codePoint: AppIcons.arrowDown,
      Icons.arrow_back.codePoint: AppIcons.arrowLeft,
      Icons.arrow_forward.codePoint: AppIcons.arrowRight,
      Icons.expand_more.codePoint: AppIcons.chevronDown,
      Icons.expand_less.codePoint: AppIcons.chevronUp,
      Icons.chevron_left.codePoint: AppIcons.chevronLeft,
      Icons.chevron_right.codePoint: AppIcons.chevronRight,
      Icons.refresh.codePoint: AppIcons.refresh,
      Icons.sync.codePoint: AppIcons.refresh,
      Icons.swap_horiz.codePoint: AppIcons.transferHorizontal,
      Icons.swap_vert.codePoint: AppIcons.transferVertical,
      Icons.home.codePoint: AppIcons.home,
      Icons.settings.codePoint: AppIcons.settings,
      Icons.tune.codePoint: AppIcons.tuning,
      Icons.widgets.codePoint: AppIcons.widget,
      Icons.filter_list.codePoint: AppIcons.filter,
      Icons.sort.codePoint: AppIcons.sort,
      Icons.menu.codePoint: AppIcons.menu,
      Icons.more_vert.codePoint: AppIcons.menuDots,
      Icons.more_horiz.codePoint: AppIcons.menuDots,
      Icons.add.codePoint: AppIcons.addCircle,
      Icons.add_circle.codePoint: AppIcons.addCircle,
      Icons.add_box.codePoint: AppIcons.addSquare,
      Icons.remove.codePoint: AppIcons.minusCircle,
      Icons.remove_circle.codePoint: AppIcons.minusCircle,
      Icons.close.codePoint: AppIcons.closeCircle,
      Icons.cancel.codePoint: AppIcons.closeCircle,
      Icons.check.codePoint: AppIcons.checkCircle,
      Icons.check_circle.codePoint: AppIcons.checkCircle,
      Icons.check_box.codePoint: AppIcons.checkSquare,
      Icons.info.codePoint: AppIcons.infoCircle,
      Icons.info_outline.codePoint: AppIcons.infoCircle,
      Icons.help.codePoint: AppIcons.questionCircle,
      Icons.help_outline.codePoint: AppIcons.questionCircle,
      Icons.warning.codePoint: AppIcons.dangerTriangle,
      Icons.warning_amber.codePoint: AppIcons.dangerTriangle,
      Icons.error.codePoint: AppIcons.dangerCircle,
      Icons.error_outline.codePoint: AppIcons.dangerCircle,
      Icons.block.codePoint: AppIcons.forbidden,
      Icons.do_not_disturb.codePoint: AppIcons.forbiddenCircle,
      Icons.content_copy.codePoint: AppIcons.copy,
      Icons.delete.codePoint: AppIcons.trash,
      Icons.delete_outline.codePoint: AppIcons.trash,
      Icons.push_pin.codePoint: AppIcons.pin,
      Icons.flag.codePoint: AppIcons.flag,
      Icons.gps_fixed.codePoint: AppIcons.target,
      Icons.power_settings_new.codePoint: AppIcons.power,
      Icons.flash_on.codePoint: AppIcons.bolt,
      Icons.flashlight_on.codePoint: AppIcons.flashlight,
      Icons.card_giftcard.codePoint: AppIcons.gift,
      Icons.share.codePoint: AppIcons.share,
      Icons.search.codePoint: AppIcons.search,
      Icons.zoom_in.codePoint: AppIcons.searchZoomIn,
      Icons.zoom_out.codePoint: AppIcons.searchZoomOut,
      Icons.notifications.codePoint: AppIcons.bell,
      Icons.notifications_active.codePoint: AppIcons.bellBing,
      Icons.notifications_off.codePoint: AppIcons.bellOff,
      Icons.favorite.codePoint: AppIcons.heart,
      Icons.favorite_border.codePoint: AppIcons.heart,
      Icons.thumb_up.codePoint: AppIcons.like,
      Icons.thumb_down.codePoint: AppIcons.dislike,
      Icons.star.codePoint: AppIcons.star,
      Icons.star_border.codePoint: AppIcons.star,
      Icons.emoji_events.codePoint: AppIcons.cup,
      Icons.bar_chart.codePoint: AppIcons.chart,
      Icons.analytics.codePoint: AppIcons.chartSquare,
      Icons.show_chart.codePoint: AppIcons.graph,
      Icons.trending_up.codePoint: AppIcons.graphUp,
      Icons.trending_down.codePoint: AppIcons.graphDown,
      Icons.pie_chart.codePoint: AppIcons.pieChart,
      Icons.account_balance_wallet.codePoint: AppIcons.wallet,
      Icons.credit_card.codePoint: AppIcons.card,
      Icons.payments.codePoint: AppIcons.banknote,
      Icons.attach_money.codePoint: AppIcons.dollar,
      Icons.local_offer.codePoint: AppIcons.tag,
      Icons.confirmation_number.codePoint: AppIcons.ticket,
      Icons.verified.codePoint: AppIcons.verifiedCheck,
      Icons.description.codePoint: AppIcons.file,
      Icons.insert_drive_file.codePoint: AppIcons.file,
      Icons.article.codePoint: AppIcons.fileText,
      Icons.file_download.codePoint: AppIcons.fileDownload,
      Icons.folder.codePoint: AppIcons.folder,
      Icons.folder_open.codePoint: AppIcons.folderOpen,
      Icons.create_new_folder.codePoint: AppIcons.folderAdd,
      Icons.map.codePoint: AppIcons.map,
      Icons.location_on.codePoint: AppIcons.mapPoint,
      Icons.add_location.codePoint: AppIcons.mapPointAdd,
      Icons.explore.codePoint: AppIcons.compass,
      Icons.my_location.codePoint: AppIcons.gps,
      Icons.public.codePoint: AppIcons.global,
      Icons.language.codePoint: AppIcons.globus,
      Icons.directions.codePoint: AppIcons.route,
      Icons.radar.codePoint: AppIcons.radar,
      Icons.access_time.codePoint: AppIcons.clock,
      Icons.schedule.codePoint: AppIcons.clock,
      Icons.alarm.codePoint: AppIcons.alarm,
      Icons.timer.codePoint: AppIcons.stopwatch,
      Icons.history.codePoint: AppIcons.timer,
      Icons.calendar_today.codePoint: AppIcons.calendar,
      Icons.event.codePoint: AppIcons.calendar,
      Icons.play_arrow.codePoint: AppIcons.play,
      Icons.play_circle.codePoint: AppIcons.playCircle,
      Icons.pause.codePoint: AppIcons.pause,
      Icons.stop.codePoint: AppIcons.stop,
      Icons.volume_up.codePoint: AppIcons.volumeHigh,
      Icons.volume_down.codePoint: AppIcons.volumeLow,
      Icons.volume_off.codePoint: AppIcons.volumeMute,
      Icons.mic.codePoint: AppIcons.microphone,
      Icons.mic_off.codePoint: AppIcons.microphoneOff,
      Icons.camera_alt.codePoint: AppIcons.camera,
      Icons.photo_camera.codePoint: AppIcons.cameraMinimalistic,
      Icons.videocam.codePoint: AppIcons.video,
      Icons.videocam_off.codePoint: AppIcons.videoOff,
      Icons.photo_library.codePoint: AppIcons.gallery,
      Icons.image.codePoint: AppIcons.image,
      Icons.note.codePoint: AppIcons.document,
      Icons.note_add.codePoint: AppIcons.documentAdd,
      Icons.assignment.codePoint: AppIcons.clipboard,
      Icons.assignment_turned_in.codePoint: AppIcons.clipboardCheck,
      Icons.dashboard.codePoint: AppIcons.dashboard,
      Icons.grid_view.codePoint: AppIcons.mitre,
      Icons.inventory_2.codePoint: AppIcons.supplyChain,
      Icons.person_pin.codePoint: AppIcons.identity,
      Icons.policy.codePoint: AppIcons.policy,
      Icons.dark_mode.codePoint: AppIcons.darkWeb,
      Icons.apps.codePoint: AppIcons.appSecurity,
      Icons.link.codePoint: AppIcons.urlProtection,
      Icons.psychology.codePoint: AppIcons.mlAnalysis,
      Icons.account_tree.codePoint: AppIcons.correlation,
      Icons.integration_instructions.codePoint: AppIcons.integrations,
      Icons.gavel.codePoint: AppIcons.compliance,
      Icons.dashboard_customize.codePoint: AppIcons.dashboard,
      Icons.fullscreen.codePoint: AppIcons.target,
      Icons.pattern.codePoint: AppIcons.structure,
      Icons.business.codePoint: AppIcons.enterprise,
    };

    return mapping[icon.codePoint] ?? AppIcons.help;
  }
}
