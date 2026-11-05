import 'package:pocketbase/pocketbase.dart' show ClientException;

/// Провайдер уже привязан к другому аккаунту — привязать его сюда нельзя.
class LinkedElsewhere implements Exception {
  const LinkedElsewhere();
}

/// Отказ сервера на привязку: провайдер у другого аккаунта
/// (`login_methods.pb.js` бросает `linked_elsewhere`, PocketBase отдаёт его
/// сообщением с заглавной буквы и точкой).
bool isLinkedElsewhere(Object e) =>
    e is LinkedElsewhere ||
    (e is ClientException &&
        '${e.response['message']}'.toLowerCase().contains('linked_elsewhere'));

/// Отказ отвязать последний способ входа (409 `last`).
bool isLastMethod(Object e) =>
    e is ClientException && e.statusCode == 409 && e.response['code'] == 'last';

/// Способы входа аккаунта (экран «Способы входа», 05.11.2026).
///
/// Ответ сервера `GET /api/auth/methods` (`pb_hooks/login_methods.pb.js`):
/// знает ли человек пароль и какие провайдеры привязаны. Аккаунт один, войти
/// в него можно любым привязанным способом.
class LoginMethods {
  const LoginMethods({
    required this.password,
    required this.providers,
    this.email = '',
  });

  factory LoginMethods.fromJson(Map<String, dynamic> json) {
    final raw = json['providers'];
    return LoginMethods(
      password: json['password'] == true,
      providers: {
        if (raw is List)
          for (final p in raw)
            if (p is String && p.isNotEmpty) p,
      },
      email: json['email'] is String ? json['email'] as String : '',
    );
  }

  /// Человек знает пароль от почты аккаунта.
  final bool password;

  /// Привязанные провайдеры: `google`, `yandex`, `apple`.
  final Set<String> providers;

  final String email;

  /// Сколько способов входа сейчас работает.
  int get count => (password ? 1 : 0) + providers.length;

  /// Один способ: забыл пароль или потерял доступ к Google — аккаунт закрыт.
  bool get atRisk => count <= 1;

  /// Провайдеры-плитки на экране. Apple привязывают только на iPhone, но
  /// привязанный там виден и на Android: иначе счёт «из скольких» врал бы.
  List<String> tiles({required bool ios}) => [
    'google',
    'yandex',
    if (ios || providers.contains('apple')) 'apple',
  ];

  /// Всего способов на экране: пароль плюс плитки.
  int total({required bool ios}) => 1 + tiles(ios: ios).length;

  /// Последний способ входа не отвязывается.
  bool canUnlink(String provider) => providers.contains(provider) && count > 1;
}
