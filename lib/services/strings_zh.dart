part of 'locale_service.dart';

/// Китайский (упрощённое письмо): то, что словарём не выражается.
///
/// Простые строки берутся из `kStrings` по коду `zh` — колонка лежит в
/// `lib/l10n/zh/` и вливается в словарь при старте. Здесь подстановки, числа
/// и списки дат.
///
/// Норма материковая (简体中文): ей пользуется большинство, а читатели
/// традиционного письма упрощённое понимают. Отдельной колонки `zh-Hant`
/// нет, `LocaleService.detect` отправляет в `zh` любой китайский.
///
/// Множественного числа в китайском нет, поэтому `_n` не нужен: «1 天» и
/// «5 天» пишутся одинаково. Между цифрой или латиницей и иероглифом стоит
/// пробел, как в интерфейсе iOS: «3 天», «Togetherly+ 会员». Дата —
/// «2001年3月8日», месяц — «3月», день недели — «周一».
class _ZhStrings extends _EnStrings {
  const _ZhStrings() : super('zh');

  static const List<String> _monthsNum = [
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月',
  ];

  static const List<String> _weekShort = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  static const List<String> _weekLong = [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];

  // ── Вход и регистрация ──
  @override
  String loginError(String e) => '登录出错：$e';
  @override
  String googleLoginError(String e) => 'Google 登录出错：$e';
  @override
  String registrationError(String e) => '注册出错：$e';
  @override
  String passwordResetSent(String email) =>
      '重置密码的邮件已发送到 $email，请查看收件箱和垃圾邮件。';

  // ── Главная ──
  @override
  String daysLabel(String suffix) => '天 $suffix';
  @override
  String monthsLabel(String suffix) => '月 $suffix';
  @override
  String timeLabel(String suffix) => '时间 $suffix';
  @override
  String partnerIsMood(String name, String mood) => '$name：$mood';
  @override
  String moodPackAuthor(String name) => '画师：$name';
  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name 不太舒服：$label';
  @override
  String moodDateLabel(String dateLabel) => '心情 · $dateLabel';
  @override
  String achProgressOf(int value, int target) => '$value/$target';
  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      '已解锁 $unlocked/$total';
  @override
  String capsuleOpensIn(int days) => days <= 0 ? '今天开启' : '$days 天后';
  @override
  String capsuleOpensOn(String date) => '$date 开启';
  @override
  String capsuleFrom(String name) => '来自 $name';
  @override
  String capsuleNotReady(String date) => '还没到时候 🙈 $date 开启';
  @override
  String capsuleOpenedBodyNamed(String title) => '“$title”正在回忆长廊里等你';

  // ── Виджеты ──
  @override
  String widgetOfPartner(String name) => '$name 的小组件';

  // ── Профиль ──
  @override
  String daysTogetherLabel(String days) => '$days 天';
  @override
  String premiumThemeLocked(int price) => '付费主题：$price 金币，可以在金币商店解锁';
  @override
  String buyThemeDescription(String themeName, int price) =>
      '要用 $price 金币解锁“$themeName”主题吗？';
  @override
  String coinPackTitle(int coins) => '$coins 金币';
  @override
  String coinPurchaseSuccessAmount(int coins) => '已到账 $coins 金币';
  @override
  String coinEarned(int amount) => '获得 $amount 金币！';
  @override
  String uploadError(String e) => '上传出错：$e';

  // ── Календарь настроений ──
  @override
  String partnerMood(String name) => '$name 的心情';

  // ── Рисование ──
  @override
  String drawingSavedTo(String path) => '画作已保存到：$path';
  @override
  String partnerIsDrawing(String name) => '$name 正在画画…';
  @override
  List<String> get reflectionQuestions => const [
    '今天另一半做的哪件小事，让你觉得被珍惜？',
    '今天和另一半的哪个瞬间让你笑了？',
    '此刻你欣赏另一半的哪一点？',
    '今天你对这段感情里的哪件事心怀感激？',
    '你总会想起和另一半的哪段回忆？',
    '另一半最近在哪件事上给了你惊喜？',
    '在你眼里，另一半有什么独一无二的地方？',
    '今天另一半是怎么支持你的？',
    '今天你最想让另一半知道什么？',
    '你最想和另一半一起去经历什么冒险？',
    '哪首歌会让你想起另一半？为什么？',
    '和另一半在一起，最好的是什么？',
    '最近另一半的哪个小小善意对你意义最大？',
    '你最近发现了另一半的什么新的一面？',
    '你们有什么共同的目标？',
    '你最喜欢和另一半一起做的一件事是什么？',
    '你上一次觉得和另一半心意相通是什么时候？',
    '怎样能让明天对你们俩都变得特别？',
    '今天你想夸另一半什么？',
    '另一半有什么小习惯，是你偷偷喜欢的？',
  ];

  // ── Подключение ──
  @override
  String groupOf(int count) => '$count 人群组';
  @override
  String membersCount(int count) => '成员 · $count';
  @override
  String shareInviteText(String code, String link) =>
      '来 Togetherly 找我吧！邀请码：$code\n\n或者点这里：$link';
  @override
  String onboardingLeft(int left) => left == 1 ? '还差一步' : '还差 $left 步';
  @override
  String onboardingNext(String step) => '还差一步：$step';

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => '照片',
    'video' => '视频',
    'location' => '地点',
    'music' => '音乐',
    'text' => '笔记',
    'videoLink' => '视频链接',
    'book' => '书',
    _ => '电影',
  };
  @override
  String timerDaysCount(int days) => '$days 天';
  @override
  String symbolSearchFound(int count) => '找到 $count 个';

  @override
  String quietPartnerTitle(String name, int days) =>
      days == 1 ? '$name 已经一天没来了' : '$name 已经 $days 天没来了';

  @override
  String membersOfMax(int current, int max) => '成员 $current/$max';
  @override
  String shareGroupInviteText(String code, String link) =>
      '来 Togetherly 加入我们的群组吧！邀请码：$code\n\n或者点这里：$link';
  @override
  String connectedWithCouple(String name) => '你和 $name 连接成功了！';
  @override
  String marriedTo(String name) => '你和 $name 是夫妻啦！💍';
  @override
  String friendsWith(String name) => '你和 $name 成为朋友了！';
  @override
  String buddiesWith(String name) => '你和 $name 成了死党！';
  @override
  String customRelWith(String label, String name) => '你和 $name 现在是“$label”！';
  @override
  String joinMeLinkText(String link) => '来 Togetherly 找我吧！$link';
  @override
  String membersCountBracket(int count) => '成员（$count）';

  // ── Даты ──
  @override
  List<String> get shortMonths => _monthsNum;
  @override
  List<String> get shortWeekdays => _weekShort;

  // ── Скучаю ──
  @override
  String missYouNotifTitle(String name) => '$name 在想你';
  @override
  String missYouStreak(int count) => '🔥 $count';
  @override
  String thinkingOfYouNotifTitle(String name) => '$name 正在想你 💭';
  @override
  String wantHugNotifTitle(String name) => '$name 想抱抱你 🤗';
  @override
  String customVibeNotifTitle(String name) => name;

  // ── Карточка фото ──
  @override
  String kmFromYou(String km) => '离你 $km';
  @override
  String minutesAgo(int m) => '$m 分钟前';
  @override
  String hoursAgo(int h) => '$h 小时前';
  @override
  String daysAgo(int d) => '$d 天前';

  // ── Лента воспоминаний ──
  @override
  String newMemory(String type) => '新的$type';
  @override
  String failedAddMemory(String e) => '回忆添加失败：$e';
  @override
  String savedToPath(String path) => '已保存到 $path';
  @override
  String downloadFailed(String e) => '下载失败：$e';
  @override
  String failedSelectPhotos(String e) => '选择照片失败：$e';
  @override
  String failedSelectVideo(String e) => '选择视频失败：$e';
  @override
  String nPhotos(int count) => '$count 张照片';
  @override
  String openIn(String name) => '在 $name 中打开';
  @override
  List<String> get fullMonths => const [
    '',
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月',
  ];
  @override
  String formatDateAt(String month, int day, int year, String time) =>
      '$year年$month$day日 $time';

  // ── Статус отношений ──
  @override
  String statusSetTo(String status) => '状态已设为：$status';
  @override
  String failedSetStatus(String e) => '状态设置失败：$e';
  @override
  String failedClearStatus(String e) => '状态清除失败：$e';
  @override
  String failedAddStatus(String e) => '状态添加失败：$e';
  @override
  String failedUpdateStatus(String e) => '状态更新失败：$e';
  @override
  String deleteStatusConfirm(String label) => '确定要删除“$label”吗？';
  @override
  String failedDeleteStatus(String e) => '状态删除失败：$e';

  // ── Календарь настроений ──
  @override
  String moodRecorded(String label) => '已记录：$label！';
  @override
  List<String> get shortWeekdaysSingleChar => const [
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];
  @override
  List<String> get longWeekdays => _weekLong;

  // ── Таймеры ──
  @override
  String timerDeleteConfirm(String name) => '“$name”会被永久删除。';

  // ── Виджеты (продолжение) ──
  @override
  String failedAddWidget(String e) => '小组件添加失败：$e';
  @override
  String yearsAlready(int years) => '已经 $years 年了 ❤️';
  @override
  String monthsAlready(int months) => '已经 $months 个月了 ❤️';
  @override
  String widgetSlotTitle(int index) => '小组件 ${index + 1}';

  // ── Профиль (продолжение) ──
  @override
  String get cycleConsentBody =>
      '经期日期和身体状况属于健康数据，所以我们单独征求你的同意。它们保存在我们的服务器上，'
      '只有你打开后另一半才能看到，一键就能删除。你可以在设置里撤回同意，记录也会随之删除。';
  @override
  String get cycleConsentAgree => '同意并开始记录';
  @override
  String get cycleConsentLater => '以后再说';
  @override
  String get cycleConsentWithdraw => '撤回生理期记录的同意';
  @override
  String get cycleConsentWithdrawHint => '这个功能会关闭，记录会被清除';
  @override
  String get exportMyData => '我的数据';
  @override
  String get exportMyDataHint => '下载我们保存的你的全部数据';
  @override
  String get exportMyDataReady => '压缩包已准备好';
  @override
  String get exportMyDataFailed => '压缩包没能生成';
  @override
  String get exportMemories => '导出回忆';
  @override
  String exportError(String e) => '导出出错：$e';

  // ── Мини-календарь ──
  @override
  List<String> get shortWeekdaysUpper => _weekShort;

  // ── Уведомления ──
  @override
  String daysTogetherNotifBody(int days) => '你们已经在一起 $days 天了 ❤️';

  // ── Чат ──
  @override
  String waitingDaysLeft(int days) => '${days.abs()} 天';
  @override
  String chatReplyingTo(String name) => '回复 $name';
  @override
  String chatTyping(String name) => '$name 正在输入…';
  @override
  String chatNotifTitle(String name) => '$name 给你发了消息 💬';
  @override
  String moodNotifTitle(String name) => '$name 更新了心情';
  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    final base = '${day.month}月${day.day}日';
    return day.year == now.year ? base : '${day.year}年$base';
  }

  @override
  String chatDeleteConfirm(String text) => '删除这条消息？';
  @override
  String pixelCanvasSummary(int cells, int px) => '$cells 格 · 导出时每格 $px 像素';
  @override
  String canvasesSubtitle(int count, String lastDate) =>
      '$count 幅画 · 最近一次 $lastDate';
  @override
  String tgDaysTogetherCaption(int days) => '天在一起';
  @override
  String tgMonthsCaption(int months) => '个月';
  @override
  String tgDaysMilestone(int days) => '$days 天';
  @override
  String tgYearsMilestone(int years) => '$years 年';
  @override
  String tgInDays(int days) => '$days 天后';
  @override
  String tgUntilMilestone(int target, int left) =>
      '距离 ${tgDaysMilestone(target)}：${tgInDays(left)}';
  @override
  String tgMissAddressee(String name) => '给 $name';
  @override
  String tgMoodMatched(int days) => '7 天里有 $days 天心情一致';
  @override
  String tgCountdownDaysLeft(int days) => '天后见面';
  @override
  String tgYearDaysWord(int days) => '天';
  @override
  String tgYearDaysUnit(int days) => '天';
  @override
  String tgYearDaysTogether(int days) => '天在一起';
  @override
  String tgYearDaysLeft(int days) => '还剩 $days 天';
  @override
  String tgYearToAnniversary(int year) => '距离第 $year 年';
  @override
  String tgYearToAnniversaryShort(int year, int days) => '距离第 $year 年 · $days';
  @override
  String tgYearCurrentYearShort(int year, int days) => '第 $year 年 · 还剩 $days';
  @override
  String tgYearOrdinalLabel(int year) => '在一起的第 $year 年';
  @override
  String tgYearsAndDays(int years, int days) => '$years 年 $days 天';
  @override
  String tgYearSince(String date) => '自 $date 起';
  @override
  String mascotSleepRange(String from, String to) => '$from 到 $to 睡觉';
  @override
  String mascotNightRange(String from, String to) => '$from 到 $to 发光';

  @override
  String cycleOf(String name) => '$name 的生理期';
  @override
  String cycleDaysLeft(int days) => '$days 天后';
  @override
  String cycleDayOfCycle(int day) => '周期第 $day 天';
  @override
  String cycleOverdue(int days) => '推迟 $days 天';
  @override
  String cycleAnalyticsHint(int cycles) => '最近 $cycles 个周期';
  @override
  String cycleDaysValue(int days) => '$days 天';
  @override
  List<String> get cycleWeekdayShorts => const [
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];
  @override
  List<String> get cycleMonthNames => _monthsNum;
  @override
  List<String> get cycleMonthsGenitive => _monthsNum;
  @override
  String dayLogDate(DateTime day) => '${day.month}月${day.day}日';
  @override
  String dayLogWeekday(DateTime day) => _weekLong[day.weekday - 1];
  @override
  String cyclePeriodDayLabel(int day) => '经期第 $day 天';
  @override
  String drawLayerName(int index) => '图层 $index';
  @override
  String drawLayerStrokes(int count) => count == 0 ? '空' : '$count 笔';
  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => '纯色',
    'grid' => '方格',
    'dots' => '点阵',
    'notebook' => '横线本',
    'millimeter' => '坐标纸',
    'kraft' => '牛皮纸',
    'chalkboard' => '黑板',
    'music' => '五线谱',
    'stars' => '星星',
    'hearts' => '爱心',
    'watercolor' => '水彩',
    'film' => '胶片',
    _ => id,
  };
  @override
  String memoryFileTooBig(int limitMb) => '文件超过 $limitMb MB，无法上传';
  @override
  String pcReceiptShift(int days) => '第 $days 班';
  @override
  String pcReceiptItems(PostcardStats stats) {
    final lines = <String>[];
    if (stats.memories > 0) lines.add('回忆 — ${stats.memories}');
    if (stats.drawings > 0) lines.add('画作 — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('想你 — ${stats.missYou}');
    if (stats.streak > 0) lines.add('连续天数 — ${stats.streak}');
    if (lines.isEmpty) lines.add('才刚刚开始 — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      '寄件人：${from.isEmpty ? '我' : from}\n'
      '内件：$days 天，完好无损';
  @override
  String statsMoodMarks(int n) => '30 天内的记录：$n';
  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      '文件超过 $limitMb MB。Togetherly+ 会把上限翻倍';
  @override
  String selectedCount(int n) => '已选 $n';
  @override
  String deleteCanvasesTitle(int n) => n == 1 ? '删除画布？' : '删除 $n 块画布？';
  @override
  String deleteCanvasesConfirm(int n) => '你们两边都会看不到这些画，删除后无法恢复。';
  @override
  String chatBgConfirmBody(int price) =>
      '要花 $price 🪙 把你的照片设为聊天背景吗？\n\n以后每次更换也要 $price 🪙。';
  @override
  String captionDestPairWidgetSub(String partner) =>
      '照片放在“我的小组件”里，你和 $partner 都能看到';
  @override
  String captionDestPartnerWidgetSub(String partner) =>
      '一个单独的小组件，放给 $partner 看的照片';
  @override
  String streakLabel(int days) => '连续 $days 天';

  // ── Виджеты (фото) ──
  @override
  String unlockForCoins(int price) => '解锁 · $price 🪙';
  @override
  String notEnoughCoinsNeed(int price) => '金币不够，需要 $price 🪙';
  @override
  String personalPhotosHelp(String partner) =>
      '个人照片：每个小组件 1 到 10 张。有两张以上就会开启轮播，解锁时或按时间切换。\n\n'
      '这些照片只有你能看到。想给 $partner 看，请打开“另一半的照片”→“选择给另一半的照片”。';
  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      '这个小组件显示 $partner 分享的照片（$count 张），只有 $partner 能更改。';
  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner 还没分享照片。要让照片出现在这里，$partner 需要打开“另一半的照片”，'
      '点“选择给另一半的照片”。普通的“照片小组件”只有自己能看到。';
  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner 能看到你的 $count 张照片';
  @override
  String photosUnit(int n) => '张照片';
  @override
  String photoCountOnUnlock(int count) => '$count 张照片 · 解锁时切换';
  @override
  String photoCountInterval(int count, String interval) =>
      '$count 张照片 · $interval';
  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return '每 15 分钟';
      case 30:
        return '每 30 分钟';
      case 60:
        return '每小时';
      case 180:
        return '每 3 小时';
      default:
        return '每 $minutes 分钟';
    }
  }

  @override
  String partnerSharedCountHelp(int count) =>
      '另一半分享了 $count 张照片，选一下它们在这个小组件上怎么切换。';

  // ── Галерея маскотов ──
  @override
  String mascotDeactivated(String name) => '$name 已停用';
  @override
  String mascotActivated(String name) => '$name 现在是当前萌宠';
  @override
  String deleteMascotBody(String name) => '“$name”会被永久删除。';
  @override
  String recordStreakDays(int days) => '纪录：$days 天';
  @override
  String mascotsCount(int count, int max) => '萌宠 $count/$max';
  @override
  String recordStreakBadge(int days) => '$days 天';

  // ── Рисование маскота, раскраска ──
  @override
  String genericError(String e) => '出错了：$e';
  @override
  String coloringPartnerColoring(String name) => '$name 正在涂色';
  @override
  String coloringWaitingHint(String name) => '$name 点“完成”后就会打开';

  // ── Карусель фото ──
  @override
  String photoCountCarousel(int count) => '$count 张照片 · 轮播';
  @override
  String photoNumber(int n) => '照片 $n';
  @override
  String positionNumber(int n) => '第 $n 个';

  // ── Профиль, «Смотрим», ленты ──
  @override
  String yearRange(int first, int last) => '$first 到 $last 年';
  @override
  String kpRating(String rating) => 'KP $rating';
  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} 米'
      : '${(meters / 1000).toStringAsFixed(1)} 公里';
  @override
  String watchWithPartner(String name) => '和 $name 一起看';
  @override
  String watchVideoAdd(int mb) => '添加视频\n最大 $mb MB';
  @override
  String watchVideoTooBig(int mb) => '视频超过 $mb MB：请压缩一下，或者选一段短一点的';
  @override
  String invitesToWatchTogether(String hostName) => '$hostName 邀请你一起看';
  @override
  String selectUpToPhotos(int n) => '最多选 $n 张照片';
  @override
  String addWithCount(int n) => '添加（$n）';
  @override
  String failedToSave(Object e) => '保存失败：$e';
  @override
  String itemsShort(int n) => '$n 项';
  @override
  String coinsPlus(int n) => '+$n 金币';
  @override
  String moodScoreLabel(int score, int max) => '$moodScorePrefix $score/$max';
  @override
  List<String> get monthAbbrev => _monthsNum;
  @override
  String memoriesUnit(int n) => '条回忆';

  // ── Карта ──
  @override
  String liveLocationAgo(String value) => '$value前';

  // ── Получение подарка ──
  @override
  String giftFromPartner(String name) => '来自 $name 的礼物';
  @override
  String giftBunnyMisses(int misses) => misses == 1 ? '它溜走了！' : '又溜走了，快抓住它！';
  @override
  String giftIncomingCount(int n) => n == 1 ? '正在等你' : '$n 份正在等你';
  @override
  String giftMutualBonus(int coins) => '回应得正是时候：各得 $coins 金币';
  @override
  String giftSunriseGreeting(String name) => '早上好！$name 给你送来了日出';
  @override
  String supportCopied(String email) => '地址已复制：$email';
  @override
  String redeemCodeDone(int coins) => '已到账 $coins 金币';

  // ── Профиль партнёра ──
  @override
  String partnerGiftsChip(int count) => '$count';
  @override
  String partnerMissChip(int count) => '$count';
  @override
  String partnerDaysTogether(int days) => '在一起 $days 天';
  @override
  String partnerMissPeak(String weekday) => '最常在$weekday';
  @override
  String weekdayShort(int weekday) => _weekShort[weekday - 1];
  @override
  String weekdayLong(int weekday) => _weekLong[weekday - 1];

  // ── Подарки ──
  @override
  String giftPushBody(String giftName) => '送了你一份礼物：$giftName';
}
