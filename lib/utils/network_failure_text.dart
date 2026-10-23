import '../dict_strings.dart';
import '../services/network/server_reach.dart';

/// Что сказать человеку, когда запрос не дошёл до нашего сервера (TOG-16).
///
/// Раньше в любом таком случае приложение писало «Сервер не отвечает.
/// Проверьте интернет.», а регистрация после повтора — «Некорректный email»,
/// хотя у людей из Украины и США интернет работал, а сервер закрывал
/// провайдер. Ответ берётся из [ServerReach.check]: закрыт — совет про VPN,
/// нет интернета — так и говорим, сервер на месте — просим повторить.
String networkFailureText(ServerReachState verdict) => switch (verdict) {
      ServerReachState.blocked => trKey('serverBlockedVpn'),
      ServerReachState.offline => trKey('noInternet'),
      ServerReachState.ok || ServerReachState.unknown => trKey('serverSlowRetry'),
    };
