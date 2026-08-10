import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pair_data.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/share_origin.dart';
import '../widgets/app_sheet.dart';
import '../widgets/waiting/waiting_setup_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    _pair.addListener(_onPairChanged);
    // Код мог не сгенериться при регистрации без сети — пробуем ещё раз.
    if (_pair.inviteCode.isEmpty && !_pair.isPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pair.regenerateCode();
      });
    }
  }

  @override
  void dispose() {
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
  }

  Future<void> _share() async {
    final code = _pair.inviteCode;
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
    final code = _pair.inviteCode;
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
    final code = _pair.inviteCode;
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
                child: QrImageView(
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
    final code = _pair.inviteCode;

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
                      _codeCard(cs, code),
                      const SizedBox(height: 20),
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
                            child: _tonalButton(
                              cs,
                              icon: Icons.keyboard_rounded,
                              label: _s.haveCode,
                              onTap: _joining ? null : _enterCode,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _keepSeatCard(cs),
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

  /// Пара заранее — для тех, кому позвать пока некого.
  ///
  /// Из 3 200 приходящих за неделю 1 220 не находят партнёра, и месяц из них
  /// переживают 5%: приложение до пары показывает половину интерфейса.
  /// Механика «второго места» это решает — пара заводится на одного, записи с
  /// первого дня ложатся в неё, а пришедший по коду получает готовую историю.
  Future<void> _keepSeat() async {
    await WaitingSetupSheet.show(context, pair: _pair, theme: widget.theme);
    if (!mounted) return;
    // Закрываем экран сами, а не надеемся на слушателя: он мог отработать,
    // пока лист был открыт, и закрыть только лист.
    if (_pair.isPaired) Navigator.of(context).maybePop();
  }

  Widget _keepSeatCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 21,
                  color: cs.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s.waitingSoloTitle,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _s.waitingSoloBody,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 12.5,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: _keepSeat,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: const StadiumBorder(),
                backgroundColor: cs.secondaryContainer,
                foregroundColor: cs.onSecondaryContainer,
              ),
              child: Text(
                _s.waitingSoloAction,
                style: const TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Код приглашения крупно: его диктуют вслух и переписывают в мессенджер.
  Widget _codeCard(ColorScheme cs, String code) {
    final ready = code.isNotEmpty;
    return Material(
      color: cs.primaryContainer,
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
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 10),
              if (ready)
                Text(
                  code,
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: 5,
                    color: cs.onPrimaryContainer,
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
                        color: cs.onPrimaryContainer,
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
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
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
