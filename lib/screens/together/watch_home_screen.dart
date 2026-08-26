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
import '../../services/watch_videos_service.dart';
import 'together_launcher.dart';
import 'watch_player_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/storage_image.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (state == AppLifecycleState.resumed) unawaited(_refreshAll());
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

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final partner = widget.pairData.partnerName;

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        // Тянуть вниз можно и на коротком списке: без этого жест не родится на
        // экране, который помещается целиком.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _Hero(cs: cs, text: text),
          const SizedBox(height: 14),
          _PrimaryCard(
            title: partner.isEmpty
                ? s.watchTogether
                : s.watchWithPartner(partner),
            subtitle: s.watchRoomOpensForBoth,
            // У купившего Togetherly+ рекламы перед комнатой нет вовсе
            // (`TogetherLauncher` пропускает её по `PlusService.active`), и
            // обещать её в подписи — врать человеку, который как раз заплатил,
            // чтобы её не видеть.
            note: PlusService.instance.active ? null : s.watchAfterShortAd,
            enabled: !_loading && _room.isNotEmpty,
            onTap: _openInApp,
          ),
          const SizedBox(height: 12),
          _TonalCard(
            icon: Icons.open_in_new_rounded,
            title: s.watchOpenOnSite,
            subtitle: s.watchOnSiteHint,
            onTap: _room.isEmpty ? null : _openOnSite,
          ),
          const SizedBox(height: 12),
          _CodeRow(
            code: _room,
            loading: _loading,
            onCopy: _copyCode,
            onRetry: _loading ? null : () => _loadRoom(),
          ),
          const SizedBox(height: 20),
          // Игры к комнате не привязаны: они на одном телефоне, кода не просят.
          // Поэтому стоят ПОСЛЕ строки кода, за отступом — иначе читались бы
          // продолжением связки «комната — сайт — код».
          _TonalCard(
            icon: Icons.sports_esports_rounded,
            title: s.gamesForTwo,
            subtitle: s.gamesForTwoHint,
            onTap: _openGames,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              s.watchOurVideos,
              style: text.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // M3 multi-browse карусель: контейнер каждого кадра сужается маской,
          // а содержимое остаётся в полном размере (parallax). Первый слот —
          // плитка загрузки, дальше свои ролики.
          SizedBox(
            height: 200,
            child: CarouselView.weighted(
              flexWeights: const [3, 2, 1],
              itemSnapping: true,
              shrinkExtent: 48,
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
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                s.watchRecent,
                style: text.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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

class _Hero extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme text;

  const _Hero({required this.cs, required this.text});

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -18,
            bottom: -34,
            child: Text(
              '♥',
              style: TextStyle(
                fontSize: 116,
                height: 1,
                color: cs.onPrimaryContainer.withValues(alpha: 0.14),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.watchHeroTitle,
                style: text.headlineSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 240,
                child: Text(
                  s.watchHeroText,
                  style: text.bodyMedium?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.86),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? note;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryCard({
    required this.title,
    required this.subtitle,
    this.note,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.onPrimary.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: cs.onPrimary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: text.titleMedium?.copyWith(color: cs.onPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(
                          color: cs.onPrimary.withValues(alpha: 0.86),
                        ),
                      ),
                      if (note != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: cs.onPrimary.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            note!,
                            style:
                                text.labelSmall?.copyWith(color: cs.onPrimary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TonalCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _TonalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  final String code;
  final bool loading;

  /// Спросить код заново. Нужен, когда его так и не дали: без этого человек
  /// смотрит на прочерк и не знает, что делать.
  final VoidCallback? onRetry;
  final VoidCallback onCopy;

  const _CodeRow({
    required this.code,
    required this.loading,
    required this.onCopy,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.watchPartnerInBrowser,
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                if (loading)
                  Text(
                    '…',
                    style: text.titleLarge?.copyWith(letterSpacing: 1.2),
                  )
                else if (code.isEmpty)
                  // Код не дали — говорим об этом словами и даём повторить.
                  // Прежде тут стоял молчаливый прочерк, и человек писал в
                  // поддержку «нет кода» (16.08.2026).
                  InkWell(
                    onTap: onRetry,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            s.watchCodeRetry,
                            style: text.titleSmall?.copyWith(color: cs.primary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    code,
                    style: text.titleLarge?.copyWith(letterSpacing: 1.2),
                  ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: code.isEmpty ? null : onCopy,
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: s.copyLink,
          ),
        ],
      ),
    );
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
    final text = Theme.of(context).textTheme;

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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                busy ? s.watchVideoUploading : s.watchVideoAdd(limitMb),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.labelLarge?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
