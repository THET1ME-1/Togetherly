import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Нативная проводка кнопки Togetherly Wallet. На Linux её не собрать и не
/// запустить, поэтому стережём исходники: без любой из этих строк кнопка
/// молча ведёт в магазин вместо уже установленного Wallet, а касание по пушу о
/// выходе просто открывает Togetherly.
void main() {
  test('Android видит пакет Wallet и умеет его запускать', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('<package android:name="com.togetherly.money" />'),
        reason: 'без <queries> Android 11+ прячет установленный Wallet');
    final activity = File(
            'android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt')
        .readAsStringSync();
    expect(activity, contains('"launchPackage" ->'));
    expect(activity, contains('openWalletFromPush(intent)'));
  });

  test('iPhone ведёт пуш о выходе в App Store и не глотает остальные', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('(info["kind"] as? String) == "wallet"'));
    expect(
        delegate,
        contains('super.userNotificationCenter(\n      center,\n'
            '      didReceive: response,'),
        reason: 'без вызова super перестанут работать касания по другим пушам');
  });

  test('Скрипт выхода шлёт те поля, которые читают обе платформы', () {
    final script = File('pocketbase/wallet_release.py').readAsStringSync();
    expect(script, contains('"kind": "wallet"'));
    expect(script, contains('"url": links[kind]'));
    expect(script, contains('"package": package'));
  });
}
