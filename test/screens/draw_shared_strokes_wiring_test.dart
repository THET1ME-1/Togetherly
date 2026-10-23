import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Экран холста сводит свои штрихи с серверными через книгу `SharedStrokes`
/// (TOG-12, 22.10.2026). Правила книги под тестами в
/// `test/models/shared_strokes_test.dart`; здесь — что экран ими пользуется
/// во всех путях. Разъедется — вернутся жалобы «нарисовал, а оно удалилось»
/// и «появилось то, что стёр давно».
String _body(String src, String signature, [int span = 3000]) {
  final at = src.indexOf(signature);
  expect(at, greaterThan(0), reason: 'не нашёл $signature');
  return src.substring(at, (at + span).clamp(0, src.length));
}

void main() {
  final src = File('lib/screens/draw_screen.dart').readAsStringSync();

  test('прежних отметок «отменён» мимо книги не осталось', () {
    expect(src, isNot(contains('_cancelledPendingStrokeIds')));
  });

  test('снимок сервера идёт через книгу', () {
    expect(_body(src, 'void _onRemoteStrokes('),
        contains('_shared.applySnapshot('));
  });

  test('отмена, ластик и удаление картинки удаляют запись по плану книги', () {
    expect(_body(src, 'Future<void> _undoOne('), contains('_shared.remove(undoKey)'));
    expect(_body(src, 'Future<void> _undoOne('), contains('_sendRemoval('));
    expect(_body(src, 'void _removeStrokeById('), contains('_shared.remove(id)'));
    expect(_body(src, 'Future<void> _deleteSelectedImage('),
        contains('_shared.remove(id)'));
  });

  test('штрих пишется под своим id записи, исход сверяется с книгой', () {
    final send = _body(src, 'void _sendStroke(');
    expect(send, contains('id: stroke.id'));
    expect(send, contains('_shared.createSucceeded('));
    expect(send, contains('_shared.createFailed('));
  });

  test('каждый новый штрих получает id записи из номера мазка', () {
    for (final site in [
      'void _commitCurrentStroke(',
      'void _submitMirrors(',
      'Future<void> _redoOne(',
      'void _restoreWholeErase(',
      'Future<void> _pickAndAddImage(',
      'Future<void> _applyFill(',
    ]) {
      expect(_body(src, site, 4000), contains('_recordId('), reason: site);
    }
  });

  test('сбой загрузки заливки отдаёт её очереди, а не стирает', () {
    final upload = _body(src, 'Future<void> _uploadImageAsync(');
    expect(upload, contains("'strokeImageAdd'"));
    expect(upload, isNot(contains('_pendingLocalStrokes.remove(')));
  });

  test('мазок партнёра без записи гаснет, номер порядка его учитывает', () {
    final live = _body(src, 'void _onLivePacket(');
    expect(live, contains('_shared.addPartnerCommitted('));
    expect(live, contains('finished.orderIndex + 1'));
    expect(_body(src, 'void _removeStalePartners('),
        contains('_shared.expirePartner('));
  });
}
