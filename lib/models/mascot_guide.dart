/// Кому показывать облачко-гида: на приветствии, в регистрации и в
/// подсказках главной.
///
/// Сначала гид включается одному человеку — владельцу, чтобы проверить его на
/// себе: остальные не увидят ничего, даже обновившись. После проверки сервер
/// ставит дату, и гид получают все, кто зарегистрировался с этого дня.
/// Задаётся полем `app_config.mascot_guide`:
/// `{"uids": ["<id>", …], "new_since": "<ISO-дата>"}`.
library;

class MascotGuideConfig {
  const MascotGuideConfig({this.uids = const {}, this.newSince});

  /// Кому гид включён руками, независимо от даты регистрации.
  final Set<String> uids;

  /// С какого дня регистрации гид включён всем. Нет даты — новым он не
  /// показывается.
  final DateTime? newSince;

  static const MascotGuideConfig off = MascotGuideConfig();

  /// До первого ответа сервера на свежей установке: гид включён новым, как
  /// на сервере с 31.10.2026. Сервер ответит — его слово главнее.
  static final MascotGuideConfig firstLaunch = MascotGuideConfig(newSince: DateTime.utc(2026, 10, 31));

  /// Разбирает поле с сервера. Всё непонятное — гид выключен.
  static MascotGuideConfig parse(Object? raw) {
    if (raw is! Map) return off;
    final uids = <String>{};
    final list = raw['uids'];
    if (list is List) {
      for (final v in list) {
        if (v is String && v.trim().isNotEmpty) uids.add(v.trim());
      }
    }
    final since = raw['new_since'];
    return MascotGuideConfig(
      uids: uids,
      newSince: since is String ? DateTime.tryParse(since)?.toUtc() : null,
    );
  }
}

/// Показывать ли гида. До входа в аккаунт (`uid == null`) решает дата для
/// новых или то, что на этом телефоне гид уже был включён.
bool mascotGuideOn(
  MascotGuideConfig config, {
  required String? uid,
  required DateTime? createdAt,
  bool rememberedOnDevice = false,
}) {
  if (rememberedOnDevice) return true;
  if (uid != null && config.uids.contains(uid)) return true;
  final since = config.newSince;
  if (since == null) return false;
  if (uid == null) return true;
  return createdAt != null && !createdAt.toUtc().isBefore(since);
}
