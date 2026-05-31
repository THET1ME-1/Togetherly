import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../services/firebase_service.dart';
import '../../services/rewarded_ad_service.dart';
import 'watch_together_screen.dart';

/// Точки входа в совместный просмотр: запуск хостом и баннер-приглашение гостю.
class TogetherLauncher {
  // Rewarded на старте показываем ТОЛЬКО хосту и один раз за запуск сеанса.
  // Гость заходит без рекламы (иначе старт рассинхронится). Если реклама не
  // загружена — не блокируем фичу, просто пускаем и грузим на следующий раз.
  static final RewardedAdService _ads = RewardedAdService();

  /// Предзагрузка rewarded — звать заранее (напр. при открытии карточки видео),
  /// чтобы к тапу «Смотреть вместе» ролик уже был готов. Идемпотентно.
  static void preloadStartAd() => _ads.load();

  /// Opt-in перед стартом: предлагаем хосту посмотреть rewarded ради коинов.
  /// Политика AdMob требует явного согласия и упоминания награды — авто-показ
  /// rewarded недопустим. Отказ НЕ блокирует совместный просмотр.
  static Future<void> _offerStartAd(BuildContext context) async {
    if (!_ads.isReady) {
      _ads.load(); // не готово — не навязываем, грузим на следующий раз
      return;
    }
    final watch = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Смотреть вместе'),
        content: const Text(
          'Посмотри короткую рекламу — поддержишь приложение '
          'и получишь коины 🪙',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Позже'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('Смотреть'),
          ),
        ],
      ),
    );
    if (watch == true) {
      final uid = FirebaseService().uid ?? '';
      await _ads.show(uid: uid);
      unawaited(_ads.load()); // грузим следующий
    }
  }

  /// Показать диалог вставки YouTube-ссылки и запустить совместный просмотр
  /// как хост.
  static Future<void> startWatchTogether(
    BuildContext context, {
    required String pairId,
    required String partnerUid,
  }) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Смотреть вместе'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ссылка на YouTube',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Начать'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;

    final videoId = YoutubePlayer.convertUrlToId(url);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось распознать ссылку YouTube')),
      );
      return;
    }

    // Rewarded на старте (только хост). Фичу не блокируем, если не готово.
    await _offerStartAd(context);
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchTogetherScreen(
          pairId: pairId,
          partnerUid: partnerUid,
          videoId: videoId,
          isHost: true,
        ),
      ),
    );
  }

  /// Запустить совместный просмотр конкретного видео как хост (URL уже известен,
  /// диалог не нужен) — напр. из карточки видео-воспоминания.
  static Future<void> hostVideo(
    BuildContext context, {
    required String pairId,
    required String partnerUid,
    required String videoUrl,
  }) async {
    final videoId = YoutubePlayer.convertUrlToId(videoUrl);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось распознать ссылку YouTube')),
      );
      return;
    }

    // Rewarded на старте (только хост). Фичу не блокируем, если не готово.
    await _offerStartAd(context);
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchTogetherScreen(
          pairId: pairId,
          partnerUid: partnerUid,
          videoId: videoId,
          isHost: true,
        ),
      ),
    );
  }

  /// Присоединиться к сеансу, который начал партнёр.
  static void joinSession(
    BuildContext context, {
    required String pairId,
    required String partnerUid,
    required String videoId,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchTogetherScreen(
          pairId: pairId,
          partnerUid: partnerUid,
          videoId: videoId,
          isHost: false,
        ),
      ),
    );
  }
}

/// Баннер-приглашение. Слушает activeSessionStream (реюзает hub-листенер
/// group-doc → 0 новых Firestore-чтений) и показывает кнопку «Присоединиться»,
/// когда партнёр начал совместный сеанс.
class TogetherInviteBanner extends StatelessWidget {
  final String pairId;
  final String partnerUid;

  const TogetherInviteBanner({
    super.key,
    required this.pairId,
    required this.partnerUid,
  });

  @override
  Widget build(BuildContext context) {
    if (pairId.isEmpty) return const SizedBox.shrink();
    final myUid = FirebaseService().uid;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: FirebaseService().activeSessionStream(pairId),
      builder: (context, snap) {
        final session = snap.data;
        if (session == null) return const SizedBox.shrink();

        final hostUid = session['hostUid'] as String?;
        // Не показываем баннер хосту — он уже в сеансе.
        if (hostUid == null || hostUid == myUid) return const SizedBox.shrink();

        final mediaId = (session['mediaId'] as String?) ?? '';
        if (mediaId.isEmpty) return const SizedBox.shrink();
        final hostName = (session['hostName'] as String?) ?? 'Партнёр';

        return Material(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => TogetherLauncher.joinSession(
              context,
              pairId: pairId,
              partnerUid: partnerUid,
              videoId: mediaId,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.smart_display, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$hostName зовёт смотреть вместе',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Text('Присоединиться'),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
