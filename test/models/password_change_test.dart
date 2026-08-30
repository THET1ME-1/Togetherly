import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/password_change.dart';

void main() {
  group('смена пароля: что проверяем до сервера', () {
    test('всё заполнено верно', () {
      expect(
        passwordChangeProblem(
            current: 'StaryiParol1', fresh: 'NovyiParol1', repeat: 'NovyiParol1'),
        isNull,
      );
    });

    test('без текущего пароля не отправляем', () {
      expect(
        passwordChangeProblem(current: '', fresh: 'NovyiParol1', repeat: 'NovyiParol1'),
        PasswordChangeProblem.noCurrent,
      );
    });

    test('короче восьми символов', () {
      expect(
        passwordChangeProblem(current: 'StaryiParol1', fresh: 'korot', repeat: 'korot'),
        PasswordChangeProblem.tooShort,
      );
    });

    test('повтор не совпал', () {
      expect(
        passwordChangeProblem(
            current: 'StaryiParol1', fresh: 'NovyiParol1', repeat: 'NovyiParol2'),
        PasswordChangeProblem.mismatch,
      );
    });

    test('новый пароль равен старому — сервер примет молча, мы нет', () {
      expect(
        passwordChangeProblem(
            current: 'StaryiParol1', fresh: 'StaryiParol1', repeat: 'StaryiParol1'),
        PasswordChangeProblem.same,
      );
    });

    test('пустой текущий важнее короткого нового: правим по порядку полей', () {
      expect(
        passwordChangeProblem(current: '', fresh: 'kor', repeat: 'kor'),
        PasswordChangeProblem.noCurrent,
      );
    });
  });
}
