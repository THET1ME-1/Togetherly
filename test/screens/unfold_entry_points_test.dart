import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Где экран вырастает из нажатого элемента (переход UnfoldRoute, макет
/// https://claude.ai/artifact/Ssgdjfc37xm7TigCWy6NGC).
///
/// Подключение состоит из двух половин — источник вокруг плитки и маршрут
/// `unfoldFrom` в месте открытия. Потеряется одна — экран молча откроется
/// прежним сдвигом сбоку, и по тестам поведения этого не видно: он ведь
/// открылся. Поэтому сверяем по исходникам.
void main() {
  String read(String path) => File(path).readAsStringSync();
  String part(String source, String from, String to) {
    final start = source.indexOf(from);
    expect(start, isNot(-1), reason: 'нет «$from»');
    final end = source.indexOf(to, start + from.length);
    expect(end, isNot(-1), reason: 'нет «$to» после «$from»');
    return source.substring(start, end);
  }

  Set<String> tags(String source) => RegExp(r"UnfoldShared\(\s*tag: '(\w+)'")
      .allMatches(source)
      .map((match) => match.group(1)!)
      .toSet();

  test('плитка «Чат» на экране связи', () {
    final screen = read('lib/screens/connect_partner_screen.dart');
    final tile = part(screen, 'Widget _chatTile(', 'Widget _chatTileBody(');
    expect(tile, contains('UnfoldSource('));
    expect(tile, contains('_openChat(from: tile)'));
    final open = part(screen, 'void _openChat(', 'Widget _buildChatButton(');
    expect(open, contains('unfoldFrom<void>('));
  });

  test('круглая кнопка чата на главной', () {
    final nav = read('lib/screens/home/home_bottom_nav.dart');
    expect(nav, contains('key: chatSourceKey'));
    final home = read('lib/screens/home_screen.dart');
    expect(home, contains('chatSourceKey: _chatSourceKey'));
    final open = part(home, 'void _openChat()', 'void _onSideAction()');
    expect(open, contains('unfoldFrom<void>('));
    expect(open, contains('_chatSourceKey.currentState'));
  });

  test('плитки профиля: магазин, достижения, подарки, лента', () {
    final profile = read('lib/screens/profile_screen.dart');
    final tile = part(profile, 'Widget _quickTile({', 'Widget _quickTileBody({');
    expect(tile, contains('UnfoldSource('));
    for (final open in [
      'void _openMemoryLane(',
      'void _openShop(',
      'void _openSelfProfile(',
      'void _openPartnerProfile(',
    ]) {
      final body = part(profile, open, '\n  }\n');
      expect(body, contains('UnfoldSourceState? from'), reason: open);
      expect(body, contains('unfoldFrom<void>('), reason: open);
    }
    final achievements =
        part(profile, 'Widget _achievementsTile(', 'AchievementsScreen(');
    expect(achievements, contains('unfoldFrom<void>('));
  });

  test('карточки главной: желания, карта, сундук', () {
    for (final path in [
      'lib/widgets/home/wishes_card.dart',
      'lib/screens/home/widgets/live_map_card.dart',
      'lib/widgets/chest/chest_home_card.dart',
    ]) {
      final source = read(path);
      expect(source, contains('UnfoldSource('), reason: path);
      expect(source, contains('unfoldFrom<void>('), reason: path);
    }
  });

  test('сезонный сундук открывается прежним переходом', () {
    // У него свой занавес и прыжок на сезонную страницу: второе движение
    // поверх было бы лишним.
    final chest = read('lib/widgets/chest/chest_home_card.dart');
    final open = part(chest, 'Future<void> _openScreen()', '_load();');
    expect(open, contains('_season == null ? _source.currentState : null'));
  });

  test('профиль партнёра из шапки чата: аватар и имя общие', () {
    final chat = read('lib/screens/chat_screen.dart');
    final bar = part(chat, 'Widget _buildTopBar(', 'Widget _headerAvatarPill(');
    expect(bar, contains('UnfoldSource('));
    expect(bar, contains('_openPartnerProfile(who)'));
    final open =
        part(chat, 'void _openPartnerProfile(', 'Widget build(BuildContext');
    expect(open, contains('unfoldFrom<void>('));
    expect(open, contains('coupleDaysTogether('),
        reason: '«дней вместе» считает общая формула, а не своя');

    final hero = read('lib/screens/profile/profile_hero.dart');
    expect(tags(chat), containsAll(<String>['avatar', 'name']));
    expect(tags(hero), containsAll(<String>['avatar', 'name']));
  });
}
