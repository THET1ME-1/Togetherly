import 'dart:async';
import '../../utils/safe_launch.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../../models/pair_data.dart';
import '../../services/locale_service.dart';
import '../../widgets/app_sheet.dart';
import '../../services/watch_history_service.dart';
import '../../models/watch_room_load.dart';
import '../../services/watch_room_service.dart';
import '../../services/plus_service.dart';
import '../../services/plus_access.dart';
import '../../services/reels/reels_invite.dart';
import '../../widgets/common/app_dialog.dart';
import '../../services/pb_data_service.dart';
import '../../models/widget_data.dart';
import '../plus_screen.dart';
import '../../services/watch_videos_service.dart';
import '../../widgets/reels/reels_start_sheet.dart';
import 'together_launcher.dart';
import 'watch_player_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/storage_image.dart';
import '../../widgets/together/watch_home_blocks.dart';
import '../../services/pocketbase_service.dart';
import '../../services/pb_auth_service.dart';

/// Вход в совместный просмотр.
///
/// Пара уже связана, поэтому код вводить не нужно: комната открывается сама.
/// Код показан тихой строкой — он нужен лишь тому, кто зовёт партнёра в браузер
/// (приложение и сайт держат одну и ту же комнату).
class WatchHomeScreen extends StatefulWidget {
  final PairData pairData;
  final AppTheme theme;

  const WatchHomeScreen({
    super.key,
    required this.pairData,
    required this.theme,
  });

  @override
  State<WatchHomeScreen> createState() => _WatchHomeScreenState();
}

class _WatchHomeScreenState extends State<WatchHomeScreen>
    with WidgetsBindingObserver {
  String _room = '';
  bool _loading = true;
  List<WatchEntry> _recent = const [];

  /// Свои залитые ролики — живым потоком канала пары.
  List<WatchVideo> _uploaded = const [];

  /// Видео из ленты воспоминаний — отдельным чтением: они лежат в `memories`,
  /// ссылка внутри json, и фильтра по вложенному полю у PocketBase нет.
  List<WatchVideo> _lane = const [];
  bool _uploading = false;
  StreamSubscription<List<WatchVideo>>? _videosSub;

  List<WatchVideo> get _videos => [..._uploaded, ..._lane];

  /// Плюс партнёра: с ним ленту запускает он, а я вхожу по его зову.
  bool _partnerPlus = false;

  /// Партнёр сейчас зовёт в ленту (`/api/reels/active`).
  ReelsInvite? _invite;

  ReelsEntry get _reelsEntry => PlusAccess.reelsEntry(
        mine: PlusService.instance.gate,
        partnerPlus: _partnerPlus,
        invited: _invite != null,
      );

  Future<void> _loadInvite() async {
    final invite = await ReelsInvite.active(widget.pairData.pairId);
    if (!mounted) return;
    if (invite?.source != _invite?.source || (invite == null) != (_invite == null)) setState(() => _invite = invite);
  }

  /// Флаг лежит в карточке виджета партнёра — его ставит сервер.
  Future<void> _loadPartnerPlus() async {
    final uid = widget.pairData.partnerUid;
    if (widget.pairData.pairId.isEmpty || uid.isEmpty) return;
    final rec = await PbDataService().loadWidget(widget.pairData.pairId, uid);
    if (!mounted || rec == null) return;
    final has = WidgetData.fromPb(rec).plus;
    if (has != _partnerPlus) setState(() => _partnerPlus = has);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPartnerPlus());
    unawaited(_loadInvite());
    _loadRoom();
    _loadRecent();
    _listenVideos();
    _loadLane();
    // Ролики нужны на вечер, а лежали вечно. Убираем просроченные при заходе:
    // отдельный планировщик ради этого не нужен.
    unawaited(WatchVideosService.purgeExpired(widget.pairData.pairId));
  }

  @override
  void dispose() {
    _videosSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Ролик партнёра приезжает живым событием: коллекция `watch_videos` ходит в
  /// канале `pair:<groupId>` с 17.08.2026. До этого список читался ровно один
  /// раз, на входе в раздел, и пара, сидящая в «Смотрим» вдвоём, не видела
  /// только что залитый ролик — жалоба «поставил видео, а партнёр не видит»
  /// (16.08.2026).
  void _listenVideos() {
    _videosSub?.cancel();
    _videosSub = WatchVideosService.streamUploaded(widget.pairData.pairId)
        .listen(
          (items) {
            if (!mounted) return;
            setState(() => _uploaded = items);
          },
          // Поток сам переподнимается с бэкоффом; на всякий случай оставляем
          // прежний список, а не чистим экран.
          onError: (_) {},
        );
  }

  /// Запасной путь на случай мёртвой подписки: возврат из фона и жест вниз.
  /// Сокет рвётся у всех разом на каждом перезапуске PocketBase, и первым это
  /// замечает как раз тот, кто ждёт ролик партнёра.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAll());
      unawaited(_loadInvite());
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadUploadedOnce(), _loadLane(), _loadRecent()]);
    if (_room.isEmpty) await _loadRoom();
  }

  Future<void> _loadUploadedOnce() async {
    final items = await WatchVideosService.uploaded(widget.pairData.pairId);
    if (!mounted) return;
    setState(() => _uploaded = items);
  }

  Future<void> _loadLane() async {
    final items = await WatchVideosService.fromMemoryLane(
      widget.pairData.pairId,
    );
    if (!mounted) return;
    setState(() => _lane = items);
  }

  Future<void> _loadVideos() async {
    await Future.wait([_loadUploadedOnce(), _loadLane()]);
  }

  /// Загрузка своего ролика: он ложится к нам, поэтому играет у обоих по
  /// обычной ссылке и синхронизируется секунда в секунду.
  Future<void> _uploadVideo() async {
    final s = LocaleService.current;
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = picked?.files.single.path;
    if (path == null) return;

    final name = picked!.files.single.name;
    if (!WatchVideosService.isPlayable(name)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.watchVideoFormatUnsupported),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final file = File(path);
    final plus = PlusService.instance.active;
    final limit = WatchVideosService.limitFor(plus: plus);
    if (await file.length() > limit) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.watchVideoTooBig(limit ~/ (1024 * 1024))),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _uploading = true);
    final saved = await WatchVideosService.upload(
      groupId: widget.pairData.pairId,
      file: file,
      title: name,
      plus: plus,
    );
    if (!mounted) return;
    setState(() => _uploading = false);

    if (saved == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.error), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    await _loadVideos();
  }

  /// Убрать свой ролик. До этого удаления не было вовсе: тестеру отвечали
  /// «сделаем вручную, пока только через 30 дней», хотя сервис умел это с
  /// самого начала — не хватало кнопки.
  /// Нажатие по ролику: смотреть вместе или убрать.
  ///
  /// Кнопка-корзина на самой обложке не работала: ролики лежат в
  /// `CarouselView`, а он ловит нажатие на весь элемент и до кнопки оно не
  /// доходит. Человек жал корзину, попадал в комнату просмотра и встречал там
  /// рекламу — «не работает кнопка удаления видео, просит посмотреть рекламу и
  /// перекидывает на кинотеатр» (13 августа 2026). Стережёт
  /// `test/widgets/carousel_delete_button_test.dart`.
  Future<void> _tapVideo(WatchVideo video) async {
    if (!video.uploaded) {
      await _openVideo(video);
      return;
    }
    final s = LocaleService.current;
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => SheetScaffold(
        title: video.title,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop('play'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(s.watchTogether),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(ctx).pop('remove'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(s.delete),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'play') {
      await _openVideo(video);
    } else if (action == 'remove') {
      await _removeVideo(video);
    }
  }

  Future<void> _removeVideo(WatchVideo video) async {
    final s = LocaleService.current;
    final messenger = ScaffoldMessenger.of(context);
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.watchVideoRemoveTitle),
        content: Text(s.watchVideoRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (agreed != true) return;

    final ok = await WatchVideosService.remove(video.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? s.watchVideoRemoved : s.error),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) await _loadVideos();
  }

  Future<void> _loadRecent() async {
    final items = await WatchHistoryService.recent(widget.pairData.pairId);
    if (!mounted) return;
    setState(() => _recent = items);
  }

  /// Спрашивает код комнаты и, если не вышло, пробует ещё.
  ///
  /// Один заход при открытии экрана оставлял человека с многоточием: сессия к
  /// первому кадру бывает не поднята, id пары приезжает позже, а вечером
  /// сервер отвечает дольше клиентского таймаута. Жалоба со снимком
  /// 16.08.2026 звучала просто — «нет кода». Правило повторов и пауз живёт в
  /// `models/watch_room_load.dart` под тестами.
  Future<void> _loadRoom({int attempt = 0}) async {
    if (attempt == 0 && mounted) setState(() => _loading = true);
    final room = await WatchRoomService.roomCode(widget.pairData.pairId);
    if (!mounted) return;

    if (watchRoomShouldRetry(code: room, attempt: attempt)) {
      await Future<void>.delayed(watchRoomRetryDelay(attempt));
      if (!mounted) return;
      return _loadRoom(attempt: attempt + 1);
    }

    setState(() {
      _room = room;
      _loading = false;
    });
  }

  @override
  void didUpdateWidget(covariant WatchHomeScreen old) {
    super.didUpdateWidget(old);
    // Пара приехала (или сменилась) уже после первого кадра — код у прежней
    // чужой, а у пустой его не было вовсе.
    if (old.pairData.pairId != widget.pairData.pairId) {
      _room = '';
      _loadRoom();
    }
  }

  Future<void> _openOnSite() async {
    if (_room.isEmpty) return;
    await safeLaunchUrl(
      Uri.parse(WatchRoomService.siteUrl(_room)),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openGames() async {
    await safeLaunchUrl(
      Uri.parse(WatchRoomService.gamesUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _copyCode() async {
    if (_room.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: WatchRoomService.siteUrl(_room)),
    );
    if (!mounted) return;
    final s = LocaleService.current;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.linkCopied),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Плитки под главной карточкой: слева высокая совместная лента, справа
  /// игры и вход с компьютера. Ленты нет (Плюса тут не продают и никто не
  /// зовёт) — игры и компьютер встают рядом.
  Widget _bento(AppStrings s) {
    return WatchBento(
      // Совместная лента — по Togetherly+: запускает купивший, партнёр
      // входит по его зову.
      reels: _reelsEntry == ReelsEntry.hidden
          ? null
          : (w) => WatchReelsTile(
                title: s.reelsTogether,
                text: _invite != null && _reelsEntry == ReelsEntry.join
                    ? s.reelsInvitedBy(_invite!.name.isEmpty ? s.partner : _invite!.name, _invite!.source.title)
                    : s.watchReelsTileHint,
                plusLocked: _reelsEntry == ReelsEntry.buy || _reelsEntry == ReelsEntry.askPartner,
                onTap: _room.isEmpty ? null : _openReels,
                titleWidth: w,
              ),
      games: (w) => WatchGamesTile(title: s.gamesForTwo, text: s.watchGamesTileHint, onTap: _openGames, titleWidth: w),
      computer: WatchComputerTile(
        code: _room,
        loading: _loading,
        onCopy: _copyCode,
        onOpenSite: _openOnSite,
        onRetry: _loading ? null : () => _loadRoom(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    final partner = widget.pairData.partnerName;
    final me = PocketBaseService().userId ?? '';
    final profile = PbAuthService().currentProfile() ?? const <String, dynamic>{};

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        // Тянуть вниз можно и на коротком списке: без этого жест не родится на
        // экране, который помещается целиком.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // Вариант А макета «Афиша и плитки» (выбран 05.10.2026): кино —
          // главная карточка, ниже плитки, а не ряд одинаковых строк.
          WatchLead(title: s.watchHeroTitle),
          const SizedBox(height: 12),
          WatchKinoCard(
            theme: widget.theme,
            title: partner.isEmpty ? s.watchTogether : s.watchWithPartner(partner),
            subtitle: s.watchRoomOpensForBoth,
            hint: s.watchKinoSources,
            myUid: me,
            myAvatar: (profile['avatarUrl'] as String?) ?? '',
            myName: (profile['displayName'] as String?) ?? '',
            partnerUid: widget.pairData.partnerUid,
            partnerAvatar: widget.pairData.partnerAvatarUrl,
            partnerName: partner,
            // У купившего Togetherly+ рекламы перед комнатой нет вовсе
            // (`TogetherLauncher` пропускает её по `PlusService.active`), и
            // обещать её в подписи — врать человеку, который как раз заплатил,
            // чтобы её не видеть.
            note: PlusService.instance.active ? null : s.watchAfterShortAd,
            enabled: !_loading && _room.isNotEmpty,
            onTap: _openInApp,
          ),
          const SizedBox(height: 10),
          _bento(s),
          const SizedBox(height: 10),
          WatchSectionHeader(title: s.watchOurVideos, count: _videos.length),
          // M3 multi-browse карусель: контейнер каждого кадра сужается маской,
          // а содержимое остаётся в полном размере (parallax). Первый слот —
          // плитка загрузки, дальше свои ролики.
          SizedBox(
            height: 180,
            child: CarouselView.weighted(
              flexWeights: const [3, 2, 1],
              itemSnapping: true,
              shrinkExtent: 40,
              padding: const EdgeInsets.only(right: 8),
              backgroundColor: cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              onTap: (i) {
                if (i == 0) {
                  if (!_uploading) _uploadVideo();
                } else {
                  _tapVideo(_videos[i - 1]);
                }
              },
              children: [
                _UploadTile(
                  busy: _uploading,
                  limitMb:
                      WatchVideosService.limitFor(
                        plus: PlusService.instance.active,
                      ) ~/
                      (1024 * 1024),
                ),
                for (final v in _videos) _VideoTile(video: v),
              ],
            ),
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 10),
            WatchSectionHeader(title: s.watchRecent),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _RecentCard(
                  entry: _recent[i],
                  onTap: () => _openAgain(_recent[i]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openInApp() async {
    if (_room.isEmpty) return;
    await TogetherLauncher.open(context, pairId: widget.pairData.pairId);
    await _loadRecent();
  }

  /// Ленты вдвоём: та же комната пары в режиме коротких роликов. Сперва лист
  /// выбора площадки.
  Future<void> _openReels() async {
    if (_room.isEmpty) return;
    // Зов мог кончиться, пока экран стоял открытым: спрашиваем свежий.
    await _loadInvite();
    if (!mounted) return;
    switch (_reelsEntry) {
      case ReelsEntry.hidden:
        return;
      case ReelsEntry.buy:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PlusScreen(scheme: Theme.of(context).colorScheme)),
        );
        // Вернулся с покупкой — плитка откроется сама.
        if (mounted) setState(() {});
        return;
      case ReelsEntry.askPartner:
        await AppDialog.info(
          context,
          title: LocaleService.current.reelsAskPartnerTitle,
          message: LocaleService.current.reelsAskPartnerBody,
        );
        return;
      case ReelsEntry.join:
        // Вхожу по зову — площадку выбрал тот, кто позвал.
        await TogetherLauncher.open(context, pairId: widget.pairData.pairId, reels: true, reelsSource: _invite!.source);
        return;
      case ReelsEntry.start:
        final source = await showReelsStartSheet(context);
        if (source == null || !mounted) return;
        await TogetherLauncher.open(context, pairId: widget.pairData.pairId, reels: true, reelsSource: source);
    }
  }

  /// Свой ролик открываем в комнате пары: файл лежит у нас и отдаётся прямой
  /// ссылкой, поэтому партнёр видит тот же кадр — и в приложении, и во вкладке
  /// браузера, секунда в секунду.
  ///
  /// Ролик из ленты воспоминаний туда не отдать: его ссылка живёт полторы
  /// минуты и только с нашей сессией. Такой играем нативно, у себя.
  Future<void> _openVideo(WatchVideo video) async {
    if (_room.isEmpty) return;

    if (video.appOnly) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WatchPlayerScreen(
            room: _room,
            pairId: widget.pairData.pairId,
            url: video.url,
            title: video.title,
          ),
        ),
      );
      await _loadRecent();
      return;
    }

    // Название и обложку знаем только мы: комната пришлёт в историю одну
    // ссылку, и «Недавнее» показало бы голый адрес сервера вместо ролика.
    unawaited(
      WatchHistoryService.remember(
        groupId: widget.pairData.pairId,
        url: video.url,
        kind: 'video',
        title: video.title,
        thumb: video.thumbUrl,
      ),
    );

    await TogetherLauncher.open(
      context,
      pairId: widget.pairData.pairId,
      videoUrl: video.url,
    );
    await _loadRecent();
  }

  /// Повторный просмотр: включаем ролик сразу, без поиска ссылки.
  Future<void> _openAgain(WatchEntry entry) async {
    if (_room.isEmpty) return;
    if (entry.url.startsWith('file://')) {
      // Свой файл лежит на устройстве, ссылкой его не открыть.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleService.current.watchPickFileAgain),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await TogetherLauncher.open(
      context,
      pairId: widget.pairData.pairId,
      videoUrl: entry.url,
    );
    await _loadRecent();
  }
}

/// Карточка недавнего просмотра: обложка, если площадка её отдала, и название.
class _RecentCard extends StatelessWidget {
  final WatchEntry entry;
  final VoidCallback onTap;

  const _RecentCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: 150,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 86,
                  width: 150,
                  child: entry.thumb.isEmpty
                      ? Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: cs.onSurfaceVariant,
                            size: 30,
                          ),
                        )
                      : Image.network(
                          entry.thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: cs.surfaceContainerHighest),
                        ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                entry.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плитка своего ролика внутри M3-карусели. Заполняет весь слот, который
/// карусель клипует и сужает маской; play и подписи лежат поверх кадра.
class _VideoTile extends StatelessWidget {
  final WatchVideo video;

  /// Убрать свой ролик. У видео из ленты воспоминаний кнопки нет: оно живёт
  /// своей записью, и удалять его надо там же.
  const _VideoTile({required this.video});

  String _duration(int s) {
    if (s <= 0) return '';
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dur = _duration(video.seconds);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Обложка ролика; нет или не загрузилась — тональный кадр под play.
        if (video.thumbUrl.isNotEmpty)
          StorageImage(
            imageUrl: video.thumbUrl,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) =>
                ColoredBox(color: cs.surfaceContainerHighest),
          )
        else
          ColoredBox(color: cs.surfaceContainerHighest),
        // Затемнение снизу, чтобы белая подпись читалась на любом кадре.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xB3120C1A)],
            ),
          ),
        ),
        Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0x3DFFFFFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 12,
          child: Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (dur.isNotEmpty)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x6B000000),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                dur,
                style: text.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Плитка «добавить своё видео» — первый слот карусели. Filled tonal, без
/// рамок: тональный контейнер задаёт форму, а не обводка.
class _UploadTile extends StatelessWidget {
  final bool busy;

  /// Потолок размера — свой у бесплатной версии и у Togetherly+.
  final int limitMb;

  const _UploadTile({required this.busy, required this.limitMb});

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;

    return ColoredBox(
      color: cs.secondaryContainer,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.onSecondaryContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: busy
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                    )
                  : Icon(
                      Icons.add_rounded,
                      color: cs.onSecondaryContainer,
                      size: 30,
                    ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                busy ? s.watchVideoUploading : s.watchVideoAdd(limitMb),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  height: 1.3,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
