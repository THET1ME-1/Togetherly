import 'dart:async';

import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../services/offline/connectivity_service.dart';
import '../services/offline/outbox_service.dart';

/// Глобальная тонкая плашка состояния синхронизации поверх любого экрана
/// (через `MaterialApp.builder`). Показывается, только когда есть что показать:
/// • офлайн / есть несинхронизированные изменения — некликабельная подсказка;
/// • есть «ядопытые» операции (сервер упорно отверг) — КЛИКАБЕЛЬНАЯ плашка
///   «повторить» (вызывает [OutboxService.retryPoison]).
/// Пустые зоны вокруг плашек прозрачны для касаний — экран под ними кликается.
class OfflineSyncBanner extends StatelessWidget {
  const OfflineSyncBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: _SyncChips(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncChips extends StatefulWidget {
  @override
  State<_SyncChips> createState() => _SyncChipsState();
}

class _SyncChipsState extends State<_SyncChips> {
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    OutboxService.instance.pendingCount.addListener(_onChange);
    OutboxService.instance.poisonCount.addListener(_onChange);
    _connSub =
        ConnectivityService.instance.onOnlineChanged.listen((_) => _onChange());
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    OutboxService.instance.pendingCount.removeListener(_onChange);
    OutboxService.instance.poisonCount.removeListener(_onChange);
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = OutboxService.instance.pendingCount.value;
    final poison = OutboxService.instance.poisonCount.value;
    final online = ConnectivityService.instance.isOnline;
    final ru = LocaleService.instance.isRussian;

    final chips = <Widget>[];

    // Подсказка офлайн / ожидает синхронизации (некликабельная).
    if (!online || pending > 0) {
      final IconData icon;
      final String text;
      if (!online) {
        icon = Icons.cloud_off_rounded;
        text = pending > 0
            ? (ru
                ? 'Офлайн · $pending ожидает отправки'
                : 'Offline · $pending pending')
            : (ru ? 'Офлайн' : 'Offline');
      } else {
        icon = Icons.sync_rounded;
        text = ru ? 'Синхронизация… ($pending)' : 'Syncing… ($pending)';
      }
      chips.add(IgnorePointer(
        child: _chip(icon, text, const Color(0xFF2E2A2C)),
      ));
    }

    // Плашка «ядовитых» операций — кликабельная: повторить отправку.
    if (poison > 0) {
      chips.add(GestureDetector(
        onTap: () => OutboxService.instance.retryPoison(),
        child: _chip(
          Icons.error_outline_rounded,
          ru
              ? '$poison не отправлено · повторить'
              : "$poison didn't sync · retry",
          const Color(0xFFB3261E),
        ),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in chips)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: c),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}
