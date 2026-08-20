import 'dart:async';
import 'package:flutter/foundation.dart';
import 'connections_manager.dart';
import 'connection.dart';
import '../services/nickname_service.dart';

// Re-export for convenience
export 'connection.dart'
    show RelationshipType, GroupMember, MemberMood, MemberAilment;

/// Wrapper around ConnectionsManager for backward compatibility
/// Delegates to the active connection
class PairData extends ChangeNotifier {
  final ConnectionsManager _manager = ConnectionsManager();

  ConnectionsManager get manager => _manager;

  Connection? get _active => _manager.activeConnection;

  // ── Getters ──
  bool get isPaired => _active?.isPaired ?? false;
  bool get isSolo => _active?.isSolo ?? false;
  DateTime? get startDate => _active?.startDate;
  String get myName => 'You';
  String get partnerName => _active?.partnerName ?? '';
  String get partnerAvatarUrl => _active?.partnerAvatarUrl ?? '';
  String get inviteCode => _active?.inviteCode ?? '';

  /// UID первого партнёра (для хранения псевдонима)
  String get partnerUid => _active?.partners.firstOrNull?.uid ?? '';

  /// Отображаемое имя партнёра: псевдоним (если задан) или реальное имя
  String get partnerDisplayName =>
      NicknameService.instance.resolve(partnerUid, partnerName);

  /// Отображаемое имя участника группы: псевдоним или реальное
  String displayNameOf(GroupMember member) =>
      NicknameService.instance.resolve(member.uid, member.name);

  /// Сохранить локальный псевдоним для участника
  Future<void> setNickname(String uid, String nickname) async {
    await NicknameService.instance.set(uid, nickname);
    notifyListeners();
  }

  /// Удалить псевдоним (вернуть настоящее имя)
  Future<void> clearNickname(String uid) async {
    await NicknameService.instance.clear(uid);
    notifyListeners();
  }

  String get pairId => _active?.pairId ?? '';
  bool get loading => _manager.loading;
  RelationshipType get relationshipType =>
      _active?.relationshipType ?? RelationshipType.couple;

  // Лендинг приглашения отдаёт `pb_hooks/invite_web.pb.js` (страница,
  // assetlinks, AASA), и на своём домене он уже живёт. Ссылку человек
  // отправляет партнёру — в ней должно стоять наше имя, а не служебный
  // поддомен duckdns.
  /// Пустой код ссылкой НЕ становится.
  ///
  /// Сервер выдаёт код не мгновенно, и до ответа поле пустое. Склейка
  /// отдавала `https://togetherly.day/invite/`, партнёр получал 404, а
  /// отправитель поломки не видел: у него ссылка выглядела как обычно. За
  /// 18–19 августа 2026 на такую ссылку зашли 30 раз с настоящих устройств —
  /// жалоба звучала как «партнёр не может перейти по пригласительной ссылке».
  String get inviteLink =>
      inviteCode.trim().isEmpty ? '' : 'https://togetherly.day/invite/$inviteCode';

  /// Прямой deep link без веб-хоста: партнёр сканирует QR камерой → сразу в
  /// приложение (App Links-верификация не нужна, работает офлайн от Firebase).
  /// Прямой deep link без веб-хоста (для QR). Пустой код — пустая строка.
  String get inviteDeepLink =>
      inviteCode.trim().isEmpty ? '' : 'loveapp://invite/$inviteCode';

  // ── Multi-member getters ──
  List<GroupMember> get members => _active?.members ?? [];
  List<GroupMember> get partners => _active?.partners ?? [];
  int get partnerCount => _active?.partnerCount ?? 0;
  int get maxMembers => _active?.maxMembers ?? 2;
  bool get canInviteMore => _active?.canInviteMore ?? false;

  // ── Counter values ──
  int get daysInLove => _active?.daysInLove ?? 0;
  DateTime? get anniversaryDate => _active?.anniversaryDate;
  int get monthsInLove => _active?.monthsInLove ?? 0;
  Duration get timeInLove => _active?.timeInLove ?? Duration.zero;

  // ── Relationship Type Helpers ──
  String get relationshipLabel => _active?.relationshipLabel ?? 'In Love';
  String get relationshipEmoji => _active?.relationshipEmoji ?? '❤️';
  String get relationshipStatusId => _active?.currentStatus?.id ?? '';

  // ── Mood ──
  MemberMood get myMood => _active?.myMood ?? const MemberMood();
  MemberMood get partnerMood => _active?.partnerMood ?? const MemberMood();
  MemberMood moodOf(String uid) => _active?.moodOf(uid) ?? const MemberMood();

  Future<void> setMood(String imagePath, String label) async {
    if (_active == null) return;
    await _active!.setMood(imagePath, label);
    notifyListeners();
  }

  Future<void> clearMood() async {
    if (_active == null) return;
    await _active!.clearMood();
    notifyListeners();
  }

  // ── Самочувствие («болячки») ──
  MemberAilment get myAilment => _active?.myAilment ?? const MemberAilment();
  MemberAilment get partnerAilment =>
      _active?.partnerAilment ?? const MemberAilment();
  MemberAilment ailmentOf(String uid) =>
      _active?.ailmentOf(uid) ?? const MemberAilment();

  Future<void> setAilment(String id, String label, String emoji) async {
    if (_active == null) return;
    await _active!.setAilment(id, label, emoji);
    notifyListeners();
  }

  Future<void> clearAilment() async {
    if (_active == null) return;
    await _active!.clearAilment();
    notifyListeners();
  }

  void setRelationshipType(
    RelationshipType type, {
    String label = '',
    String emoji = '',
  }) {
    _active?.setRelationshipType(type, label: label, emoji: emoji);
    notifyListeners();
  }

  // ── Custom Relationship Types ──
  List<Map<String, String>> get customRelationshipTypes =>
      _active?.customRelationshipTypes ?? [];

  Future<void> addCustomRelationshipType(String label, String emoji) async {
    if (_active == null) return;
    await _active!.addCustomRelationshipType(label, emoji);
    notifyListeners();
  }

  Future<void> updateCustomRelationshipType(
    String id,
    String label,
    String emoji,
  ) async {
    if (_active == null) return;
    await _active!.updateCustomRelationshipType(id, label, emoji);
    notifyListeners();
  }

  Future<void> deleteCustomRelationshipType(String id) async {
    if (_active == null) return;
    await _active!.deleteCustomRelationshipType(id);
    notifyListeners();
  }

  // ── Инициализация ──
  Future<void> init({required String myName}) async {
    await NicknameService.instance.init();
    _manager.addListener(_onManagerChanged);
    await _manager.init(myName: myName);
    notifyListeners();
  }

  void _onManagerChanged() {
    notifyListeners();
  }

  // ── Actions ──
  void setMyName(String name) {
    // Not used anymore, kept for compatibility
    notifyListeners();
  }

  /// Принять код партнёра — создаёт/вступает в группу через Firestore.
  /// Работает независимо от того, есть ли уже активная группа.
  Future<bool> acceptCode(String code) async {
    final result = await _manager.acceptCodeAndCreateGroup(code);
    if (result) notifyListeners();
    return result;
  }

  /// Реальная причина последнего неуспешного приёма кода (истёкшая сессия, свой
  /// код, группа полна) — для честного сообщения вместо generic «код не найден».
  String? get lastAcceptMessage => _manager.lastAcceptMessage;

  /// Свой ли код? Проверяет по ВСЕМ connections.
  bool isSelfCode(String code) {
    return _manager.isSelfCodeAny(code);
  }

  // ── Пара с пустым местом («он в армии») ──
  bool get waitingMode => _active?.waitingMode ?? false;
  String get placeholderName => _active?.placeholderName ?? '';
  String get placeholderAvatar => _active?.placeholderAvatar ?? '';
  DateTime? get returnDate => _active?.returnDate;
  String get claimToken => _active?.claimToken ?? '';
  bool get hasClaimRequest => _active?.hasClaimRequest ?? false;
  String get claimName => _active?.claimName ?? '';
  int? get daysUntilReturn => _active?.daysUntilReturn;

  /// Кого показывать вторым: настоящего партнёра или заглушку.
  String get counterpartName =>
      waitingMode ? placeholderName : partnerDisplayName;

  /// Заявка на второе место ушла и ждёт подтверждения хозяйкой пары.
  bool get awaitingApproval => _manager.lastAcceptWaiting;
  String get awaitingOwnerName => _manager.lastAcceptOwnerName;

  /// Почему сервер отказался заводить пару с пустым местом (пусто — не знаем).
  String? get lastWaitingCreateError => _manager.lastWaitingCreateError;

  Future<String> createWaitingPair({
    required String name,
    String? avatar,
    DateTime? returnDate,
  }) async {
    final code = await _manager.createWaitingPair(
      name: name,
      avatar: avatar,
      returnDate: returnDate,
    );
    notifyListeners();
    return code;
  }

  Future<bool> updateWaitingPlaceholder({
    String? name,
    String? avatar,
    DateTime? returnDate,
    bool clearReturnDate = false,
  }) async {
    if (pairId.isEmpty) return false;
    final ok = await _manager.updatePlaceholder(
      pairId: pairId,
      name: name,
      avatar: avatar,
      returnDate: returnDate,
      clearReturnDate: clearReturnDate,
    );
    notifyListeners();
    return ok;
  }

  Future<bool> answerClaim({required bool approve}) async {
    if (pairId.isEmpty) return false;
    final ok = await _manager.answerClaim(pairId, approve: approve);
    notifyListeners();
    return ok;
  }

  Future<String> resetClaimToken() async {
    if (pairId.isEmpty) return '';
    final code = await _manager.resetClaimToken(pairId);
    notifyListeners();
    return code;
  }

  /// Передумали ждать: пара с пустым местом закрывается, код гаснет.
  Future<bool> cancelWaiting() async {
    if (pairId.isEmpty) return false;
    final ok = await _manager.cancelWaitingPair(pairId);
    notifyListeners();
    return ok;
  }

  /// Проверить, подтвердили ли нашу заявку («ждём» → «мы в паре»).
  Future<String> checkWaitingClaim() => _manager.checkWaitingClaim();

  /// Разорвать пару
  Future<void> unpair() async {
    if (_active == null) return;
    await _active!.unpair();
    notifyListeners();
  }

  /// Перегенерация кода
  Future<void> regenerateCode() async {
    if (_active == null) return;
    await _active!.regenerateCode();
    notifyListeners();
  }

  /// Сверить показанный код с сервером и перевыпустить, если его там нет.
  /// Зовётся при открытии экрана приглашения — см. `Connection`.
  Future<void> ensureInviteCodeIsReal() async {
    if (_active == null) return;
    final before = _active!.inviteCode;
    await _active!.ensureInviteCodeIsReal();
    if (_active!.inviteCode != before) notifyListeners();
  }

  /// Generate group invite code (for adding more members)
  Future<String> generateGroupInvite() async {
    if (_active == null) return '';
    return await _active!.generateInviteForGroup();
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _manager.dispose();
    super.dispose();
  }
}
