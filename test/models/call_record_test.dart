import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/call_record.dart';

void main() {
  test('запись делает один из двоих, и оба согласны кто', () {
    expect(writesCallRecord(me: 'aaa', peer: 'bbb'), isTrue);
    expect(writesCallRecord(me: 'bbb', peer: 'aaa'), isFalse);
  });

  test('собеседник неизвестен — пишем сами', () {
    expect(writesCallRecord(me: 'bbb', peer: ''), isTrue);
  });

  test('длительность как на часах', () {
    expect(callDuration(0), '0:00');
    expect(callDuration(4 * 60000 + 12000), '4:12');
    expect(callDuration(3600000 + 2 * 60000 + 3000), '1:02:03');
  });

  test('текст для сборок без карточки', () {
    expect(callRecordText('Звонок', 65000), 'Звонок · 1:05');
  });
}
