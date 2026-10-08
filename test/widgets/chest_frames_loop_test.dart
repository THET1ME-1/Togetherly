import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';

/// Покой сундука крутится по кругу: кадры идут, а не стоят на первом.
void main() {
  final file = File(
    Platform.environment['IDLE_WEBP'] ?? '${Platform.environment['HOME']}/Projects/togetherly-badges-hand/out_season/hw/idle.webp',
  );

  testWidgets('покой сундука играет кадры по кругу', (tester) async {
    if (!file.existsSync()) return;
    ChestFrames.debugPut('t://idle', file.readAsBytesSync());
    final frames = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ChestFrames(url: 't://idle', still: null, side: 200, onFrame: frames.add),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 70));
    }
    expect(frames.length, greaterThan(5), reason: 'кадры: $frames');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('частые перерисовки родителя не останавливают покой', (tester) async {
    if (!file.existsSync()) return;
    ChestFrames.debugPut('t://idle2', file.readAsBytesSync());
    final frames = <int>[];
    late StateSetter rebuild;
    var n = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            rebuild = set;
            n++;
            // новая строка с тем же адресом — как адрес, собранный заново в build
            return Center(child: ChestFrames(url: 't://${'idle2'}', still: null, side: 200 + (n % 2), onFrame: frames.add));
          },
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      rebuild(() {});
      await tester.pump(const Duration(milliseconds: 70));
    }
    expect(frames.length, greaterThan(5), reason: 'кадры: $frames');
    await tester.pumpWidget(const SizedBox());
  });
}
