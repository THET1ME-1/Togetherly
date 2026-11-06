import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pair_quiz.dart';
import '../services/locale_service.dart';
import '../theme/profile_theme.dart';
import '../utils/share_origin.dart';
import '../widgets/common/app_dialog.dart';

/// «Поделиться» итогом теста для пары: картинка 1080×1920 для сторис, как у
/// сосуда настроений (`vessel_story_screen.dart`). Предпросмотр, кнопки
/// «Поделиться» и «Сохранить».
class PairQuizStoryScreen extends StatefulWidget {
  const PairQuizStoryScreen({
    super.key,
    required this.scheme,
    required this.mine,
    required this.theirs,
    required this.partnerName,
  });

  final ColorScheme scheme;
  final QuizResult mine;
  final QuizResult? theirs;
  final String partnerName;

  @override
  State<PairQuizStoryScreen> createState() => _PairQuizStoryScreenState();
}

class _PairQuizStoryScreenState extends State<PairQuizStoryScreen> {
  final GlobalKey _shot = GlobalKey();
  bool _busy = false;

  String get _lang => LocaleService.instance.language.code;

  /// Снимок карточки в натуральном размере: масштаб предпросмотра не влияет.
  Future<File> _render() async {
    final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/togetherly_quiz_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data!.buffer.asUint8List());
    return file;
  }

  Future<void> _share() async {
    // Якорь для поповера iPad снимаем ДО первого await: дальше контекст уедет.
    final origin = shareOriginFromContext(context);
    setState(() => _busy = true);
    try {
      final file = await _render();
      await Share.shareXFiles([XFile(file.path)], sharePositionOrigin: origin);
    } catch (e) {
      debugPrint('тест пары: поделиться не вышло: $e');
      if (mounted) AppSnack.error(context, LocaleService.current.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final file = await _render();
      await Gal.putImage(file.path, album: 'Togetherly');
      if (mounted) AppSnack.success(context, LocaleService.current.savedToGallery);
    } catch (e) {
      debugPrint('тест пары: сохранить не вышло: $e');
      if (mounted) AppSnack.error(context, LocaleService.current.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(backgroundColor: cs.surface, surfaceTintColor: Colors.transparent),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _shot,
                      child: PairQuizStoryCard(
                        scheme: cs,
                        mine: widget.mine,
                        theirs: widget.theirs,
                        partnerName: widget.partnerName,
                        lang: _lang,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 54), shape: const StadiumBorder()),
                        child: FittedBox(fit: BoxFit.scaleDown, child: Text(quizUi('save', _lang))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _share,
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 54), shape: const StadiumBorder()),
                        child: FittedBox(fit: BoxFit.scaleDown, child: Text(quizUi('share', _lang))),
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

/// Сама картинка: 360×640, снимается с `pixelRatio: 3`. Шрифт телефона на
/// неё не влияет (картинка одна на всех), углы прямые: сторис во весь экран.
/// В `Material`, а не в голом контейнере: вне дерева экрана текст без
/// унаследованного стиля Flutter метит жёлтым подчёркиванием прямо в картинку.
class PairQuizStoryCard extends StatelessWidget {
  const PairQuizStoryCard({
    super.key,
    required this.scheme,
    required this.mine,
    required this.theirs,
    required this.partnerName,
    required this.lang,
  });

  final ColorScheme scheme;
  final QuizResult mine;
  final QuizResult? theirs;
  final String partnerName;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final kind = mine.kind;
    String emoji(QuizResult r) => kind == QuizKind.animal ? '${kAnimalEmoji[r.type]} ' : '';
    final partner = partnerName.trim().isEmpty ? quizUi('theirs', lang) : partnerName.trim();
    // «Насколько вы похожи»: своего типа нет, на картинке процент совпадения.
    final match = kind == QuizKind.alike && theirs != null ? quizMatch(mine, theirs!, lang) : null;
    final percent = match != null && match.total > 0;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(
        width: 360,
        height: 640,
        child: Material(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 44, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quizTitle(kind, lang).toUpperCase(),
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 13,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  percent ? '${match.percent}%' : '${emoji(mine)}${quizTypeTitle(kind, mine.type, lang)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: percent ? 72 : 34,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  percent ? quizPairSummary(mine, theirs!, lang) : quizTypeText(kind, mine.type, lang),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 15, height: 1.4, color: cs.onPrimaryContainer),
                ),
                const Spacer(),
                if (theirs != null && !percent) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                        ),
                        Text(
                          '${emoji(theirs!)}${quizTypeTitle(kind, theirs!.type, lang)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          quizUi('together', lang).toUpperCase(),
                          style: TextStyle(
                            fontFamily: ProfileTheme.bodyFont,
                            fontSize: 12,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          quizPairSummary(mine, theirs!, lang),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 14, height: 1.35, color: cs.onSurface),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Togetherly',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: ProfileTheme.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        'togetherly.day',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 13, color: cs.onPrimaryContainer.withValues(alpha: 0.75)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
