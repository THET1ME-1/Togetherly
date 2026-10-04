import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/reels_source.dart';
import '../pocketbase_service.dart';

/// Зов в совместную ленту (решение 05.10.2026): ленту запускает тот, у кого
/// Togetherly+, партнёру приходит пуш «Аня зовёт смотреть TikTok», и он
/// входит без своего Плюса. Сервер — `pb_hooks/reels_invite.pb.js`.
class ReelsInvite {
  const ReelsInvite({required this.groupId, required this.source, this.name = ''});

  final String groupId;
  final ReelsSource source;

  /// Кто зовёт — имя как есть, без склонения.
  final String name;

  /// Ответ `GET /api/reels/active` или данные пуша (`kind: reels`).
  /// null — зова нет или пришло что-то чужое.
  static ReelsInvite? parse(Object? raw, {String groupId = ''}) {
    if (raw is! Map) return null;
    if (raw.containsKey('active') && raw['active'] != true) return null;
    if (raw.containsKey('kind') && raw['kind'] != 'reels') return null;
    final feed = '${raw['feed'] ?? ''}';
    final group = '${raw['group'] ?? groupId}';
    if (group.isEmpty || !ReelsSource.values.any((s) => s.key == feed)) return null;
    return ReelsInvite(groupId: group, source: ReelsSource.byKey(feed), name: '${raw['name'] ?? ''}'.trim());
  }

  /// Запустил ленту — позвать партнёра. Сервер сам решает, не рано ли
  /// звать снова, и отказывает без Плюса. Сбой сети смотреть не мешает.
  static Future<void> send(String groupId, ReelsSource source) async {
    if (groupId.isEmpty) return;
    try {
      await PocketBaseService()
          .pb
          .send('/api/reels/invite', method: 'POST', body: {'group_id': groupId, 'feed': source.key})
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('ReelsInvite: зов не ушёл: $e');
    }
  }

  /// Вышел из ленты — зов больше не действует.
  static Future<void> stop(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      await PocketBaseService()
          .pb
          .send('/api/reels/invite', method: 'POST', body: {'group_id': groupId, 'stop': true})
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Зовёт ли партнёр сейчас. null — не зовёт или сервер не ответил.
  static Future<ReelsInvite?> active(String groupId) async {
    if (groupId.isEmpty) return null;
    try {
      final res = await PocketBaseService()
          .pb
          .send('/api/reels/active', query: {'group_id': groupId})
          .timeout(const Duration(seconds: 8));
      return parse(res, groupId: groupId);
    } catch (_) {
      return null;
    }
  }
}

/// Пуш зова — из системы в приложение. Касание по пушу (`opened`) и пуш,
/// пришедший, пока приложение открыто (`arrived`), едут каналом
/// `love_app/reels_invite`; касание, которым приложение запустили с нуля,
/// забирается вопросом `pending`. Главный экран слушает [invites].
class ReelsInviteBus {
  ReelsInviteBus._();
  static final ReelsInviteBus instance = ReelsInviteBus._();

  static const _channel = MethodChannel('love_app/reels_invite');

  final _ctrl = StreamController<({ReelsInvite invite, bool opened})>.broadcast();
  Stream<({ReelsInvite invite, bool opened})> get invites => _ctrl.stream;
  bool _wired = false;

  /// Подключить канал и забрать касание, которым запустили приложение.
  Future<void> init() async {
    if (!_wired) {
      _wired = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'opened' && call.method != 'arrived') return null;
        final invite = ReelsInvite.parse(call.arguments);
        if (invite != null) _ctrl.add((invite: invite, opened: call.method == 'opened'));
        return null;
      });
    }
    try {
      final raw = await _channel.invokeMethod<Object?>('pending');
      final invite = ReelsInvite.parse(raw);
      if (invite != null) _ctrl.add((invite: invite, opened: true));
    } on MissingPluginException {
      // Платформа без моста (тесты, старая нативная часть) — пушей зова нет.
    } catch (_) {}
  }
}
