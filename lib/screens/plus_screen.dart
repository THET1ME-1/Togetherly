import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/coin_store.dart';
import '../services/locale_service.dart';
import '../services/pb_coins_service.dart';
import '../services/plus_service.dart';
import '../theme/profile_theme.dart';
import '../widgets/app_sheet.dart';

/// Экран Togetherly+.
///
/// Разовая покупка, не подписка: заплатил один раз — доступ остаётся и
/// переезжает вместе с аккаунтом. Оплата идёт на lava.top, оттуда вебхук
/// приходит в PocketBase и ставит флаг; если почта покупки совпала с почтой
/// аккаунта, всё открывается само, иначе бот выдаёт код.
///
/// Кнопка покупки показывается только в сборках мимо Google Play: там нельзя
/// проводить оплату цифровых товаров чужим биллингом. Уже купленный доступ
/// работает везде — флаг живёт на аккаунте, а не в сборке.
class PlusScreen extends StatefulWidget {
  const PlusScreen({super.key, required this.scheme});

  final ColorScheme scheme;

  @override
  State<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends State<PlusScreen> {
  final PlusService _plus = PlusService.instance;
  bool _busy = false;

  /// Магазин заводится только в Play-сборке — там покупка идёт через биллинг.
  /// В остальных сборках оплата уходит на lava.top, и магазин не нужен.
  CoinStore? _store;

  ColorScheme get _cs => widget.scheme;
  AppStrings get _s => LocaleService.current;

  @override
  void initState() {
    super.initState();
    _plus.addListener(_onChanged);
    unawaitedRefresh();
    if (PlusService.buysInStore) _initStore();
  }

  Future<void> _initStore() async {
    // Общий магазин на всё приложение: свой экземпляр отписывался бы от потока
    // покупок в `dispose`, и оплата, случившаяся при закрытом экране, до
    // сервера не доезжала (инцидент 30 июля).
    final store = sharedCoinStore;
    _store = store;
    store.addListener(_onChanged);
    await store.init(
      onGrantCoins: ({
        required String productId,
        required String purchaseToken,
      }) async {
        // Тот же роут, что начисляет монеты: для togetherly_plus он ставит флаг
        // доступа. Возвращаем баланс — по non-null сервис понимает, что сервер
        // покупку принял.
        final res = await PbCoinsService()
            .iapPurchase(productId: productId, purchaseToken: purchaseToken);
        if (res == null || res['ok'] != true) return null;
        return (res['coins'] as num?)?.toInt() ?? 0;
      },
    );
    if (mounted) setState(() {});
  }

  void unawaitedRefresh() {
    _plus.refresh();
  }

  @override
  void dispose() {
    _plus.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    // dispose у общего магазина не зовём: он живёт со всем приложением и
    // должен продолжать слушать поток покупок после закрытия экрана.
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = _plus.active;

    return Theme(
      data: ProfileTheme.data(_cs),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: _cs.surface,
          appBar: AppBar(
            backgroundColor: _cs.surface,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            title: Text(
              _s.plusTitle,
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                color: _cs.onSurface,
              ),
            ),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).padding.bottom + 32,
            ),
            children: [
              _hero(active),
              const SizedBox(height: 20),
              _features(),
              const SizedBox(height: 20),
              if (!active) _actions(),
              if (active) _ownedNote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(bool active) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: active ? _cs.primaryContainer : _cs.primary,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            active ? Icons.verified_rounded : Icons.workspace_premium_rounded,
            size: 32,
            color: active ? _cs.onPrimaryContainer : _cs.onPrimary,
          ),
          const SizedBox(height: 14),
          Text(
            active ? _s.plusActiveTitle : _s.plusHeroTitle,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              letterSpacing: -0.5,
              color: active ? _cs.onPrimaryContainer : _cs.onPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            active ? _s.plusActiveBody : _s.plusHeroBody,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 14,
              height: 1.4,
              color: (active ? _cs.onPrimaryContainer : _cs.onPrimary)
                  .withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _features() {
    final items = <(IconData, String, String)>[
      (Icons.block_rounded, _s.plusNoAdsTitle, _s.plusNoAdsBody),
      (Icons.palette_rounded, _s.plusThemesTitle, _s.plusThemesBody),
      (Icons.water_drop_rounded, _s.plusCycleTitle, _s.plusCycleBody),
      (Icons.widgets_rounded, _s.plusWidgetsTitle, _s.plusWidgetsBody),
      (Icons.lightbulb_rounded, _s.plusTipsTitle, _s.plusTipsBody),
      (Icons.videocam_rounded, _s.plusVideoTitle, _s.plusVideoBody),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 72,
                endIndent: 16,
                color: _cs.outlineVariant.withValues(alpha: 0.4),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(items[i].$1,
                        size: 22, color: _cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontVariations: const [FontVariation('wght', 600)],
                            color: _cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$3,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 13,
                            height: 1.3,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions() {
    if (!PlusService.canPurchase) {
      // В сборке из Google Play покупка не предлагается: их правила запрещают
      // проводить оплату цифровых товаров мимо своего биллинга.
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          _s.plusUnavailableHere,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 13,
            height: 1.35,
            color: _cs.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _openPurchase,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(
              _s.plusBuy,
              style: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        // Ввод кода в Play-сборке не показываем: код выдают за оплату мимо
        // биллинга Google, и кнопка «у меня есть код» рядом с их же покупкой
        // читается как обход. Купившие на lava.top с другой почтой открывают
        // доступ в сборке с GitHub — флаг всё равно ложится на аккаунт.
        if (!PlusService.buysInStore) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : _openRedeem,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              _s.plusHaveCode,
              style: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        ],
        const SizedBox(height: 12),
        Text(
          _s.plusHowItWorks,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 12,
            height: 1.4,
            color: _cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _ownedNote() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(Icons.devices_rounded, size: 20, color: _cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _s.plusPortableNote,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                height: 1.35,
                color: _cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPurchase() async {
    if (PlusService.buysInStore) {
      await _buyInStore();
      return;
    }
    setState(() => _busy = true);
    // Ссылку выдаёт сервер: он заводит счёт в lava.top на почту аккаунта, и
    // только по счетам оттуда приходят уведомления об оплате. Не ответил —
    // идём на витрину, как раньше, но тогда доступ придётся выдавать руками.
    final fromServer = await PlusService.instance.checkoutUrl();
    final url = Uri.tryParse(fromServer ?? PlusService.purchaseUrl);
    if (url == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Браузера нет или ссылка не открылась — молча возвращаем кнопку.
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Покупка через биллинг Google Play. Флаг доступа ставит сервер, экран лишь
  /// показывает исход: успех, отмену или ошибку.
  Future<void> _buyInStore() async {
    final store = _store;
    if (store == null || !store.isAvailable) {
      _toast(_s.plusStoreUnavailable);
      return;
    }
    setState(() => _busy = true);
    final res = await store.buy(kPlusProductId);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res.status) {
      case IapStatus.success:
        await _plus.refresh();
        if (mounted) _toast(_s.plusPurchased);
      case IapStatus.pending:
        _toast(_s.plusPurchasePending);
      case IapStatus.cancelled:
        break; // человек сам отказался — молчим
      case IapStatus.error:
        _toast(_s.plusPurchaseFailed);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  /// Ввод кода, выданного ботом: платили с другой почты или аккаунта ещё не
  /// было в момент покупки.
  void _openRedeem() {
    final controller = TextEditingController();

    showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SheetScaffold(
          title: _s.plusHaveCode,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.plusCodeHint,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    height: 1.35,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'TG••••••',
                    filled: true,
                    fillColor: _cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottom: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final code = controller.text.trim();
                if (code.isEmpty) return;
                final ok = await _plus.redeem(code);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? _s.plusCodeOk : _s.plusCodeFailed),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                _s.plusCodeApply,
                style: const TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
