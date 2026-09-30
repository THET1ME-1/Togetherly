import 'package:flutter/material.dart';

import '../dict_strings.dart';

/// Справка «Как сделать»: ответы на то, о чём чаще всего пишут в приёмную.
///
/// Каждое десятое обращение спрашивает то, что в приложении уже есть: как
/// оплатить Плюс, удалить пару, сменить пол или пароль, где канал. Ответ —
/// путь, три шага и кнопка, которая открывает нужное место. Тексты взяты из
/// ответов приёмной, а подписи в шагах совпадают с подписями на экранах.

enum HelpTopic { pair, together, widgets, account, plus }

/// Куда ведёт кнопка «Открыть» под ответом.
enum HelpAction {
  tabHome,
  tabWidgets,
  tabConnect,
  tabWatch,
  tabProfile,
  settings,
  plusSheet,
  plusSite,
  telegram,
}

class HelpItem {
  const HelpItem(this.id, this.topic, this.icon, [this.action]);

  /// Ключ строк: `help.<id>.q`, `.path`, `.s1`–`.s3`.
  final String id;
  final HelpTopic topic;
  final IconData icon;

  /// null — открывать нечего, под ответом только «Написать нам».
  final HelpAction? action;

  String get question => trKey('help.$id.q');
  String get path => fillHelpLabels(trKey('help.$id.path'));
  List<String> get steps => [
        for (final n in [1, 2, 3]) fillHelpLabels(trKey('help.$id.s$n')),
      ];
}

/// `{connect}` → подпись с экрана на текущем языке. Так шаг зовёт кнопку тем
/// же словом, что на ней написано.
String fillHelpLabels(String text) =>
    text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => trKey(m.group(1)!));

String helpTopicLabel(HelpTopic t) => trKey('help.topic.${t.name}');

/// Вопросы для этой сборки.
///
/// [plusInStore] — Плюс покупается через магазин (Google Play и iPhone):
/// тогда ответ ведёт в настройки, и ни слова о внешней оплате, иначе магазин
/// снимет приложение. В сборках с сайта и RuStore — ссылка на lava.top.
List<HelpItem> helpItems({required bool plusInStore}) => [
      const HelpItem('unpair', HelpTopic.pair, Icons.link_off_rounded,
          HelpAction.tabConnect),
      const HelpItem('startDate', HelpTopic.pair, Icons.event_rounded,
          HelpAction.tabHome),
      const HelpItem('draw', HelpTopic.together, Icons.brush_rounded,
          HelpAction.tabHome),
      const HelpItem('watch', HelpTopic.together, Icons.live_tv_rounded,
          HelpAction.tabWatch),
      const HelpItem('tasks', HelpTopic.together, Icons.task_alt_rounded,
          HelpAction.tabHome),
      const HelpItem('widgetPhoto', HelpTopic.widgets,
          Icons.hide_image_rounded, HelpAction.tabWidgets),
      const HelpItem('widgetStale', HelpTopic.widgets, Icons.widgets_rounded,
          HelpAction.tabWidgets),
      const HelpItem('password', HelpTopic.account, Icons.lock_rounded,
          HelpAction.settings),
      const HelpItem(
          'resetMail', HelpTopic.account, Icons.mark_email_unread_rounded),
      const HelpItem('email', HelpTopic.account, Icons.mark_email_read_rounded,
          HelpAction.settings),
      const HelpItem('gender', HelpTopic.account, Icons.transgender_rounded,
          HelpAction.tabProfile),
      const HelpItem('telegram', HelpTopic.account, Icons.send_rounded,
          HelpAction.telegram),
      plusInStore
          ? const HelpItem('plusStore', HelpTopic.plus,
              Icons.workspace_premium_rounded, HelpAction.plusSheet)
          : const HelpItem('plusSite', HelpTopic.plus,
              Icons.workspace_premium_rounded, HelpAction.plusSite),
    ];

/// Два вопроса крупными плитками наверху: о них спрашивают чаще всего.
List<HelpItem> helpPopular(List<HelpItem> items) => [
      for (final id in ['plusStore', 'plusSite', 'unpair', 'startDate'])
        ...items.where((i) => i.id == id),
    ].take(2).toList();

/// Поиск по вопросу, пути и шагам, без учёта регистра и «ё».
///
/// У длинного слова окончание отбрасывается: «пароля» находит «пароль»,
/// «виджета» — «виджет». Для справки из дюжины ответов этого хватает.
bool helpMatches(HelpItem item, String query) {
  final q = _norm(query);
  if (q.isEmpty) return true;
  final hay = _norm([item.question, item.path, ...item.steps].join(' '));
  return q
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w.length > 5 ? w.substring(0, w.length - 2) : w)
      .every(hay.contains);
}

String _norm(String s) =>
    s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();
