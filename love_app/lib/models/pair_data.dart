import 'dart:math';
import 'package:flutter/foundation.dart';

class PairData extends ChangeNotifier {
  bool _isPaired = false;
  DateTime? _startDate;
  String _myName = 'You';
  String _partnerName = '';
  String _inviteCode = '';

  PairData() {
    _inviteCode = _generateCode();
  }

  // ── Getters ──
  bool get isPaired => _isPaired;
  DateTime? get startDate => _startDate;
  String get myName => _myName;
  String get partnerName => _partnerName;
  String get inviteCode => _inviteCode;

  String get inviteLink => 'https://loveapp.link/invite/$_inviteCode';

  // ── Counter values ──
  int get daysInLove {
    if (!_isPaired || _startDate == null) return 0;
    return DateTime.now().difference(_startDate!).inDays;
  }

  int get monthsInLove {
    if (!_isPaired || _startDate == null) return 0;
    final now = DateTime.now();
    int months =
        (now.year - _startDate!.year) * 12 + now.month - _startDate!.month;
    if (now.day < _startDate!.day) months--;
    return months;
  }

  Duration get timeInLove {
    if (!_isPaired || _startDate == null) return Duration.zero;
    return DateTime.now().difference(_startDate!);
  }

  // ── Actions ──
  void setMyName(String name) {
    _myName = name;
    notifyListeners();
  }

  /// Pair with a partner (simulate accepting/entering code)
  void pairWith({required String partnerName}) {
    _isPaired = true;
    _startDate = DateTime.now();
    _partnerName = partnerName;
    notifyListeners();
  }

  /// Accept a code and simulate pairing
  bool acceptCode(String code) {
    // In a real app, this would validate against a server.
    // For demo: any 6-character code works.
    if (code.length == 6) {
      pairWith(partnerName: 'Alex');
      return true;
    }
    return false;
  }

  void unpair() {
    _isPaired = false;
    _startDate = null;
    _partnerName = '';
    _inviteCode = _generateCode();
    notifyListeners();
  }

  void regenerateCode() {
    _inviteCode = _generateCode();
    notifyListeners();
  }

  // ── Helpers ──
  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
