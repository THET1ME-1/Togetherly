/// Согласие на обработку данных цикла.
///
/// Отметки цикла и самочувствия — особая категория персональных данных: и
/// закон Республики Молдова № 133/2011, и GDPR требуют на них отдельного
/// явного согласия, а не общего «принимаю политику» при регистрации. Отзыв
/// должен быть таким же простым, как согласие, поэтому он живёт здесь же.
///
/// Версия нужна на случай, когда меняется сам текст: согласие на прошлую
/// редакцию не считается согласием на новую.
const int kCycleConsentVersion = 1;

class CycleConsent {
  const CycleConsent({
    this.grantedAt,
    this.withdrawnAt,
    this.version = 0,
  });

  /// Согласия не спрашивали ни разу.
  const CycleConsent.absent() : this();

  factory CycleConsent.granted({required DateTime at, required int version}) =>
      CycleConsent(grantedAt: at, version: version);

  final DateTime? grantedAt;
  final DateTime? withdrawnAt;
  final int version;

  /// Согласие действует: дано, не отозвано и на текущую редакцию текста.
  bool get granted =>
      grantedAt != null &&
      withdrawnAt == null &&
      version >= kCycleConsentVersion;

  bool get needsAsking => !granted;

  CycleConsent withdrawn({required DateTime at}) =>
      CycleConsent(grantedAt: grantedAt, withdrawnAt: at, version: version);

  static DateTime? _date(Object? raw) {
    final text = (raw ?? '').toString();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  factory CycleConsent.fromMap(Map<String, dynamic> map) => CycleConsent(
        grantedAt: _date(map['granted_at']),
        withdrawnAt: _date(map['withdrawn_at']),
        version: (map['version'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        if (grantedAt != null) 'granted_at': grantedAt!.toIso8601String(),
        if (withdrawnAt != null) 'withdrawn_at': withdrawnAt!.toIso8601String(),
        'version': version,
      };
}
