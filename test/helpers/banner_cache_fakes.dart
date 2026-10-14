// Кэш баннеров на подделках: сервер считает скачивания, файлы и записи
// лежат во временной папке. Общий для тестов кэша и шапки профиля.
import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:love_app/services/banner_cache.dart';

/// Сервер-подделка: считает скачивания и отдаёт [body] по адресу.
class FakeBannerServer extends FileService {
  FakeBannerServer(this.body);

  final List<int> Function(String url) body;
  final downloads = <String>[];
  bool offline = false;

  /// Держит ответ, пока тест не отпустит.
  Completer<void>? gate;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    downloads.add(url);
    await gate?.future;
    if (offline) throw const io.SocketException('нет сети');
    return _Response(Uint8List.fromList(body(url)));
  }
}

class _Response implements FileServiceResponse {
  _Response(this._bytes);
  final Uint8List _bytes;

  @override
  Stream<List<int>> get content => Stream.value(_bytes);
  @override
  int? get contentLength => _bytes.length;
  @override
  int get statusCode => 200;

  /// Срок свежести уже вышел: общий кэш на таком файле качал бы заново.
  @override
  DateTime get validTill => DateTime.now().subtract(const Duration(days: 1));
  @override
  String? get eTag => null;
  @override
  String get fileExtension => '.gif';
}

class _Dir implements FileSystem {
  _Dir(this.root);
  final io.Directory root;

  @override
  Future<File> createFile(String name) async =>
      const LocalFileSystem().directory(root.path).childFile(name);
}

/// Менеджер кэша во временной папке [dir] поверх [server].
CacheManager fakeBannerManager(io.Directory dir, FakeBannerServer server) =>
    CacheManager(Config(
      'banner_test',
      repo: JsonCacheInfoRepository.withFile(io.File('${dir.path}/db.json')),
      fileSystem: _Dir(dir),
      fileService: server,
    ));

/// Кэш баннеров поверх [manager]. Токен в адресе каждый раз новый, как у
/// настоящего сервера.
BannerCache fakeBannerCache(CacheManager manager) {
  var tokens = 0;
  return BannerCache(
    manager: manager,
    resolve: (ref) async =>
        'https://togetherly.day/api/files/${ref.substring(5)}?token=${++tokens}',
  );
}
