import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/user_data.dart';
import '../../utils/email_typo.dart';
import 'app_dialog.dart';
import 'email_change_sheet.dart';

const _kAskedAt = 'email_typo_asked_at';

/// Аккаунт заведён на почту с опечаткой — предлагаем исправить (04.10.2026).
///
/// На проде около 1270 таких аккаунтов: gmail.con, gmai.com, icloud.con.
/// Пока человек помнит пароль, всё работает, а забыл — письмо для сброса
/// уходит в никуда, и он теряет аккаунт с парой (обращения 208, 223, 232).
/// Спрашиваем на главной не чаще раза в три дня: «Позже» не должно
/// превращаться в окно на каждом запуске. Исправление — та же смена почты
/// кодом, что в настройках, с уже подставленным адресом.
Future<void> maybeAskToFixEmailTypo(BuildContext context, UserData userData) async {
  final fix = emailTypoFix(userData.email);
  if (fix == null) return;
  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    return;
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = prefs.getInt(_kAskedAt) ?? 0;
  if (now - last < const Duration(days: 3).inMilliseconds) return;
  await prefs.setInt(_kAskedAt, now);
  if (!context.mounted) return;
  final ok = await AppDialog.confirm(
    context,
    title: trKey('emailTypoTitle'),
    message: trKey('emailTypoAccountBody')
        .replaceAll('{typed}', userData.email)
        .replaceAll('{fixed}', fix),
    confirmLabel: trKey('emailTypoFix'),
    cancelLabel: trKey('emailTypoLater'),
    icon: Icons.alternate_email_rounded,
  );
  if (!ok || !context.mounted) return;
  final email = await showEmailChangeSheet(
    context,
    scheme: Theme.of(context).colorScheme,
    initialEmail: fix,
  );
  if (email == null) return;
  await userData.setEmail(email);
}
