import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pair_data.dart';
import '../services/locale_service.dart';
import '../services/ui_prefs.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/share_origin.dart';
import '../widgets/app_sheet.dart';
import '../widgets/common/guide_hint.dart';
import '../widgets/common/m3_loading.dart';

/// Первый экран после регистрации: позвать свою половину.
///
/// Показывается один раз, сразу после setup, и только пока пары нет. Ничего не
/// блокирует — «Пока побуду один» уводит на главную.
///
/// Зачем экран: до пары доходят 57% зарегистрировавшихся, а из тех, кто не
/// дошёл, 79% уходят в день установки. Приглашение спрятано во вкладку, и
/// человек, открывший приложение для двоих, видит пустую половину интерфейса
/// раньше, чем повод позвать второго.
class InvitePartnerScreen extends StatefulWidget {
  const InvitePartnerScreen({
    super.key,
    required this.pairData,
    required this.theme,
  });

  final PairData pairData;
  final AppTheme theme;

  @override
  State<InvitePartnerScreen> createState() => _InvitePartnerScreenState();
}

class _InvitePartnerScreenState extends State<InvitePartnerScreen> {
  ColorScheme get _cs => ProfileTheme.themeFor(widget.theme).colorScheme;
  AppStrings get _s => LocaleService.current;
  PairData get _pair => widget.pairData;

  bool _joining = false;

  /// Новый код выпускается: кнопка крутится и не жмётся второй раз.
  bool _regenerating = false;

  /// Куда показывает Ту: на свой код и на ввод чужого.
  final GlobalKey _codeKey = GlobalKey();
  final GlobalKey _enterKey = GlobalKey();

  /// Подсказки Ту уже пошли в этом заходе.
  bool _guideStarted = false;

  /// Пауза перед первой подсказкой: человек сперва видит экран целиком.
  static const Duration _guideDelay = Duration(milliseconds: 1200);

  /// Следующая сверка, пока сервер не выдал рабочий код.
  Timer? _retry;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _pair.addListener(_onPairChanged);
    // Экран раздаёт только код, который сервер подтвердил в этом запуске. Код
    // из памяти телефона после перезапуска надо сверить заново: без этого
    // карточка «Позвать» на главной открывала вечное «Готовим код» (обращение
    // 376). Пустой код выпускаем: он мог не сгенериться при регистрации без
    // сети. Подтверждённый код не трогаем: сверка — это запрос к серверу и
    // полный проход главной по оповещению модели пары.
    if (!_pair.isPaired && _pair.inviteCodeState != InviteCodeState.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkCode());
    }
    _startGuideWhenReady();
  }

  /// Ту объясняет экран, когда код уже на месте: показывать на крутилку
  /// бессмысленно. Пока кода нет, ждём оповещения модели пары.
  void _startGuideWhenReady() {
    if (_guideStarted || _pair.isPaired || _pair.shareableInviteCode.isEmpty) return;
    _guideStarted = true;
    _guideTimer = Timer(_guideDelay, _runGuide);
  }

  /// Отложенный старт подсказок: экран закрыли раньше — подсказки не будет.
  Timer? _guideTimer;

  /// Подсказки Ту по одной (владелец 12.11.2026: «люди не знают, как и куда
  /// вписывать код»). Первая — на свой код, вторая — на «Ввести код». Каждая
  /// одноразовая: отметка пишется перед показом, как в очереди подсказок.
  Future<void> _runGuide() async {
    final steps = [
      (key: 'invite_code', target: _codeKey, text: _s.inviteCodeHint),
      (key: 'invite_enter', target: _enterKey, text: _s.inviteEnterHint),
    ];
    for (final step in steps) {
      if (!_guideMayShow()) return;
      if (await UiPrefs.hintSeen(step.key)) continue;
      await UiPrefs.markHintSeen(step.key);
      if (!_guideMayShow()) return;
      await showGuideHint(
        context,
        targetKey: step.target,
        text: step.text,
        gotIt: _s.gotIt,
        theme: widget.theme,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  /// Экран на месте и поверх него ничего не открыто (лист ввода кода, QR).
  bool _guideMayShow() =>
      mounted && !_pair.isPaired && (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _newCode() async {
    if (_regenerating) return;
    setState(() => _regenerating = true);
    await _pair.regenerateCode();
    if (!mounted) return;
    setState(() => _regenerating = false);
    // Сервер не выдал код — хвалиться нечем (так же на экране связи).
    if (_pair.shareableInviteCode.isNotEmpty) _toast(_s.newCodeGenerated);
  }

  /// Дольше одной попытки не ждём. У клиента сервера сроков нет, и на
  /// повисшем соединении (VPN, плохая сеть) выпуск кода не кончается вовсе.
  static const _checkLimit = Duration(seconds: 20);

  /// Пауза перед следующей попыткой: 5, 10, 20, дальше каждые 30 секунд.
  static Duration _retryAfter(int attempt) =>
      Duration(seconds: math.min(30, 5 << math.min(attempt, 3)));

  /// Код крутится, пока его не выдаст сервер (решение владельца 20.10.2026):
  /// своего кода без подтверждения экран не показывает, таблички вместо
  /// ожидания тоже нет. Сервер промолчал — спрашиваем ещё раз сами.
  Future<void> _checkCode() async {
    if (!mounted || _pair.isPaired) return;
    try {
      await (_pair.inviteCode.isEmpty
              ? _pair.regenerateCode()
              : _pair.ensureInviteCodeIsReal())
          .timeout(_checkLimit);
    } on TimeoutException {
      // Поздний ответ не пропадёт: модель пары сама перерисует экран.
    }
    if (!mounted || _pair.isPaired || _pair.shareableInviteCode.isNotEmpty) {
      return;
    }
    _retry = Timer(_retryAfter(_attempt++), _checkCode);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _guideTimer?.cancel();
    _pair.removeListener(_onPairChanged);
    super.dispose();
  }

  /// Партнёр принял приглашение, пока экран открыт, — уходим сами.
  void _onPairChanged() {
    if (!mounted) return;
    if (_pair.isPaired) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
    _startGuideWhenReady();
  }

  Future<void> _share() async {
    final code = _pair.shareableInviteCode;
    if (code.isEmpty) return;
    // Origin считаем синхронно, до await: на iPad лист без него молча не
    // открывается (та самая причина реджекта 2.1(a)).
    final origin = shareOriginFromContext(context);
    await Share.share(
      _s.shareInviteText(code, _pair.inviteLink),
      subject: _s.loveAppInvitation,
      sharePositionOrigin: origin,
    );
  }

  void _copyCode() {
    final code = _pair.shareableInviteCode;
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
        content: Text(_s.codeCopied),
      ),
    );
  }

  void _showQr() {
    final code = _pair.shareableInviteCode;
    if (code.isEmpty) return;
    final cs = _cs;
    showAppSheet<void>(
      context,
      builder: (ctx) => SheetScaffold(
        title: _s.inviteQrTitle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _s.inviteQrHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 14,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                // Пустой код рисовать нечем: QrImageView на пустой строке
                // падает, а ссылка без кода ведёт партнёра в 404. Пока сервер
                // не ответил, на месте кода крутится ожидание.
                child: _pair.inviteLink.isEmpty
                    ? const SizedBox(
                        width: 208,
                        height: 208,
                        child: Center(child: M3Loading(color: Colors.black45)),
                      )
                    : QrImageView(
                        data: _pair.inviteLink,
                        size: 208,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.circle,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: Colors.black,
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              Text(
                code,
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ввод кода партнёра: пришли первым не мы, а нас.
  void _enterCode() {
    final controller = TextEditingController();
    final cs = _cs;
    showAppSheet<void>(
      context,
      builder: (ctx) => SheetScaffold(
        title: _s.enterPartnerCode,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: cs.onSurface,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  hintText: 'XXXX-XX',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final code = controller.text.trim().toUpperCase();
                    if (code.isEmpty) return;
                    Navigator.of(ctx).pop();
                    await _submitCode(code);
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    _s.connect,
                    style: const TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitCode(String code) async {
    // Второй запрос тем же кодом, пока идёт первый, не отправляем: он
    // натыкался на уже использованный код, и его ошибка ложилась поверх
    // успешного подключения (тот же guard в connect_partner_screen).
    if (_joining) return;
    if (_pair.isSelfCode(code)) {
      _toast(_s.cantInviteSelf);
      return;
    }
    setState(() => _joining = true);
    final ok = await _pair.acceptCode(code);
    if (!mounted) return;
    setState(() => _joining = false);
    if (ok) {
      // Пара появилась — слушатель уведёт экран сам, но на всякий случай.
      Navigator.of(context).maybePop();
    } else {
      // Показываем настоящую причину (истёкшая сессия, группа занята, свой
      // код), а не всегда «код не найден»: этот экран отвечал одной строкой на
      // все отказы, и человек искал проблему в коде, когда дело было в сессии.
      // Так же устроен _submitCode в connect_partner_screen.
      final msg = _pair.lastAcceptMessage;
      _toast((msg != null && msg.isNotEmpty) ? msg : _s.inviteCodeNotFound);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final code = _pair.shareableInviteCode;

    return Theme(
      data: ProfileTheme.data(cs),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(
                        _s.later,
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    children: [
                      Text(
                        _s.inviteHeroTitle,
                        style: TextStyle(
                          fontFamily: ProfileTheme.displayFont,
                          fontSize: 28,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          letterSpacing: -0.5,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _s.inviteHeroBody,
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 15,
                          height: 1.45,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      KeyedSubtree(key: _codeKey, child: _codeCard(cs, code)),
                      // Код можно сменить: старый перестаёт работать, если
                      // его отправили не тому человеку.
                      Center(
                        child: TextButton.icon(
                          onPressed: code.isEmpty || _regenerating || _joining ? null : _newCode,
                          icon: _regenerating
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurfaceVariant),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            _s.newInviteCode,
                            style: const TextStyle(
                              fontFamily: ProfileTheme.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: code.isEmpty || _joining ? null : _share,
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: Text(
                            _s.sendInvitation,
                            style: const TextStyle(
                              fontFamily: ProfileTheme.bodyFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _tonalButton(
                              cs,
                              icon: Icons.qr_code_rounded,
                              label: _s.showQr,
                              onTap: code.isEmpty ? null : _showQr,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            key: _enterKey,
                            child: _tonalButton(
                              cs,
                              icon: Icons.keyboard_rounded,
                              label: _s.haveCode,
                              onTap: _joining ? null : _enterCode,
                            ),
                          ),
                        ],
                      ),
                      // Карточка «пара заранее» убрана 19.08.2026: экран
                      // показывается один раз, сразу после регистрации, и
                      // новичок читал в её листе «Завести пару» — решал, что
                      // это создание пары, а не ожидание того, кого ждать.
                      // Вход остался на экране связи.
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: Text(
                            _s.staySolo,
                            style: TextStyle(
                              fontFamily: ProfileTheme.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Цвет кода: оттенок акцента темы, но тоном для надписи. У тем,
  /// нарисованных руками, `primary` светлый, и розовый код на светлой
  /// карточке читался с контрастом 1,9:1.
  static Color _ink(ColorScheme cs) {
    final accent = Hct.fromInt(cs.primary.toARGB32());
    final tone = cs.brightness == Brightness.light ? 38.0 : 84.0;
    return Color(Hct.from(accent.hue, accent.chroma, tone).toInt());
  }

  /// Код приглашения крупно: его диктуют вслух и переписывают в мессенджер.
  Widget _codeCard(ColorScheme cs, String code) {
    final ready = code.isNotEmpty;
    final ink = _ink(cs);
    return Material(
      // Не `primaryContainer`: у тем, нарисованных руками, он почти равен фону
      // страницы, а надпись на нём читалась с контрастом 2:1. Так же сделана
      // карточка кода на «Связи».
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: ready ? _copyCode : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            children: [
              Text(
                _s.yourInviteCode,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (ready)
                // Одной строкой всегда: на 320 точках при шрифте 1,3 код
                // рвался на «AB12C» и «D».
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: ProfileTheme.displayFont,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      fontVariations: const [FontVariation('wght', 700)],
                      letterSpacing: 5,
                      color: ink,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: ink,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                ready ? _s.tapToCopy : _s.inviteCodeLoading,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tonalButton(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: ProfileTheme.bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: const StadiumBorder(),
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
      ),
    );
  }
}
