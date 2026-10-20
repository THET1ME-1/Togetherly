import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/timer_item.dart';
import 'package:love_app/models/timer_sync.dart';

/// Обращение 358 (20.10.2026): дату на главном круге ставят, а через десять
/// минут там снова «1 день». Правка уходила на сервер одной попыткой, ошибку
/// никто не видел, и следующее обновление пары возвращало старую дату. Теперь
/// правка ждёт подтверждения сервера, а обновление пары её не откатывает.
void main() {
  TimerItem timer(String id, String date, {bool system = false, bool main = false}) => TimerItem(
        id: id,
        title: 'Влюблённые',
        startDate: DateTime.parse(date),
        isSystem: system,
        isDefault: main,
      );

  group('запись на сервер одного таймера', () {
    test('заменяет таймер с тем же id, остальные не трогает', () {
      final list = [
        timer('system', '2026-10-19T16:56:25.200Z', system: true, main: true).toJson(),
        timer('a', '2025-01-01T00:00:00.000').toJson(),
      ];
      final out = upsertTimerJson(list, timer('system', '2026-08-05T08:40:00.000', system: true, main: true).toJson());
      expect(out, hasLength(2));
      expect(out[0]['startDate'], '2026-08-05T08:40:00.000');
      expect(out[1]['startDate'], '2025-01-01T00:00:00.000');
    });

    test('нового таймера в списке нет — добавляет', () {
      final out = upsertTimerJson([], timer('a', '2025-01-01T00:00:00.000').toJson());
      expect(out.single['id'], 'a');
    });

    test('новый основной снимает флаг с остальных', () {
      final list = [timer('system', '2026-10-19T16:56:25.200Z', system: true, main: true).toJson()];
      final out = upsertTimerJson(list, timer('a', '2025-01-01T00:00:00.000', main: true).toJson());
      expect(out.firstWhere((e) => e['id'] == 'system')['isDefault'], isFalse);
      expect(out.firstWhere((e) => e['id'] == 'a')['isDefault'], isTrue);
    });
  });

  group('неотправленная правка', () {
    test('обновление пары с прежней датой её не откатывает', () {
      final remote = [timer('system', '2026-10-19T16:56:25.200Z', system: true, main: true)];
      final pending = {'system': timer('system', '2026-08-05T08:40:00.000', system: true, main: true)};
      final out = mergeWithPending(remote, pending);
      expect(out.single.startDate, DateTime.parse('2026-08-05T08:40:00.000'));
    });

    test('таймеры без правок берутся с сервера', () {
      final remote = [
        timer('system', '2026-10-19T16:56:25.200Z', system: true, main: true),
        timer('a', '2024-02-02T00:00:00.000'),
      ];
      final out = mergeWithPending(remote, {'system': timer('system', '2026-08-05T08:40:00.000', system: true, main: true)});
      expect(out.firstWhere((t) => t.id == 'a').startDate, DateTime.parse('2024-02-02T00:00:00.000'));
    });

    test('добавленный и ещё не отправленный таймер остаётся в списке', () {
      final out = mergeWithPending([], {'a': timer('a', '2025-01-01T00:00:00.000')});
      expect(out.single.id, 'a');
    });

    test('сервер вернул ту же правку — она больше не ждёт', () {
      final edit = timer('system', '2026-08-05T08:40:00.000', system: true, main: true);
      final remote = [timer('system', '2026-08-05T08:40:00.000', system: true, main: true)];
      expect(stillPending(remote, {'system': edit}), isEmpty);
    });

    test('на сервере ещё старая дата — правка ждёт дальше', () {
      final edit = timer('system', '2026-08-05T08:40:00.000', system: true, main: true);
      final remote = [timer('system', '2026-10-19T16:56:25.200Z', system: true, main: true)];
      expect(stillPending(remote, {'system': edit}).keys, ['system']);
    });
  });
}
