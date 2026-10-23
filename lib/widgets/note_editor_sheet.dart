import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../services/home_widget_service.dart';
import '../services/locale_service.dart';
import 'app_sheet.dart';

/// Правка заметки на двоих из приложения.
///
/// На Android листик правится прямо с рабочего стола: тап открывает прозрачную
/// `NoteEditorActivity`, потому что `EditText` в RemoteViews не существует. На
/// iPhone печатать внутри виджета нельзя вовсе, и тап уводит сюда по
/// `loveapp://note` — иначе виджет-заметка на iOS остался бы доской, которую
/// нечем писать.
Future<void> showNoteEditorSheet(
  BuildContext context, {
  required String groupId,
}) async {
  final g = groupId.isEmpty ? 'solo' : groupId;
  final current =
      await HomeWidget.getWidgetData<String>('note_${g}_text') ?? '';
  if (!context.mounted) return;

  final controller = TextEditingController(text: current);
  final s = LocaleService.current;

  // На телефоне может лежать прежний текст: заметку партнёра хранилище
  // виджетов получало только с полной синхронизацией на входе (TOG-13). Лист
  // открывается сразу, а свежий текст подставляется, пока человек ещё ничего
  // не начал печатать.
  var closed = false;
  unawaited(() async {
    await HomeWidgetService.instance.refreshNote(g);
    final fresh = await HomeWidget.getWidgetData<String>('note_${g}_text');
    if (closed || fresh == null || fresh == current) return;
    if (controller.text == current) controller.text = fresh;
  }().catchError((Object _) {}));

  await showAppSheet<void>(
    context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SheetScaffold(
        title: s.tgNoteTitle,
        bottom: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              // Пишем локально до похода на сервер: листик на рабочем столе
              // должен обновиться сразу, а не после ответа сети.
              await HomeWidgetService.instance
                  .saveNoteFromWidget(groupId: g, text: text);
            },
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            child: Text(s.save),
          ),
        ),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          maxLength: 200,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 16,
            color: cs.onSurface,
          ),
          decoration: InputDecoration(
            hintText: s.tgNoteSubtitle,
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );
    },
  );

  closed = true;
  controller.dispose();
}
