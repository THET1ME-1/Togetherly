/// Что экран приглашения вправе показать на месте кода.
///
/// Код в памяти телефона ещё не значит, что он есть на сервере. 23 сентября
/// 2026 у человека висел код TPNQGP, которого в `invite_codes` не было:
/// партнёр ввёл его 27 раз за 8 минут и 27 раз услышал «Код не найден». Сессия
/// у человека к тому времени умерла, и ни проверить код, ни выпустить новый
/// приложение уже не могло, но экран рисовал его как рабочий.
enum InviteCodeState {
  /// Сервер выдал или подтвердил код в этом запуске: можно показывать и
  /// раздавать.
  ready,

  /// Кода нет, либо сервер ещё не подтвердил его: сверка идёт или сервер
  /// промолчал. Экран показывает ожидание.
  pending,

  /// Сессии нет: сервер нас не узнаёт. Ни свой код проверить, ни чужой
  /// принять нельзя, поэтому человеку надо войти заново.
  sessionLost,
}

InviteCodeState inviteCodeStateOf({
  required String code,
  required bool signedIn,
  required bool confirmed,
}) {
  if (!signedIn) return InviteCodeState.sessionLost;
  if (code.trim().isEmpty || !confirmed) return InviteCodeState.pending;
  return InviteCodeState.ready;
}

/// Коды приглашения, которые сервер выдал или подтвердил в этом запуске
/// приложения, с владельцем.
///
/// Живёт только в памяти, намеренно: после перезапуска каждый код из prefs
/// заново сверяется с сервером, прежде чем экран его покажет. Владелец нужен,
/// чтобы после смены аккаунта код прежнего человека не считался рабочим.
class ConfirmedInviteCodes {
  ConfirmedInviteCodes._();

  static final Map<String, String> _ownerByCode = {};

  static String _key(String code) => code.trim().toUpperCase();

  static void confirm(String code, {required String ownerUid}) {
    final k = _key(code);
    if (k.isEmpty || ownerUid.isEmpty) return;
    _ownerByCode[k] = ownerUid;
  }

  static void forget(String code) => _ownerByCode.remove(_key(code));

  static bool contains(String code, {required String ownerUid}) {
    final k = _key(code);
    if (k.isEmpty || ownerUid.isEmpty) return false;
    return _ownerByCode[k] == ownerUid;
  }

  static void clear() => _ownerByCode.clear();
}
