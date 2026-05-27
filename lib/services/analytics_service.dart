import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around FirebaseAnalytics so callers don't have to depend on
/// the Firebase package directly and so every event name lives in one place.
///
/// Auto-collected events (first_open, session_start, screen_view, etc.) work
/// without any code on our side — they fire as soon as the SDK is touched.
/// Custom product events go through the typed helpers below.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Use this in `MaterialApp.navigatorObservers` to get automatic
  /// `screen_view` events for every Flutter route push/pop whose
  /// `RouteSettings.name` is set. Anonymous routes (the
  /// `MaterialPageRoute(builder: …)` pattern dominant here) need an
  /// explicit name to be tracked — that's a follow-up if we want
  /// per-screen funnels. Auto events (first_open, session_start) and the
  /// product events below work regardless.
  late final FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: _analytics);

  Future<void> _log(String name, [Map<String, Object?>? params]) async {
    try {
      await _analytics.logEvent(
        name: name,
        parameters: params == null
            ? null
            : {
                for (final entry in params.entries)
                  if (entry.value != null) entry.key: entry.value as Object,
              },
      );
    } catch (e) {
      debugPrint('AnalyticsService.$name failed: $e');
    }
  }

  /// Associate subsequent events with this user. Pass null on sign-out.
  Future<void> setUserId(String? uid) async {
    try {
      await _analytics.setUserId(id: uid);
    } catch (e) {
      debugPrint('AnalyticsService.setUserId failed: $e');
    }
  }

  // ── Product events ─────────────────────────────────────────────────────────
  // Names use snake_case + verb_noun to fit Firebase Analytics conventions.

  Future<void> logPairConnected({required String groupId}) =>
      _log('pair_connected', {'group_id': groupId});

  Future<void> logMemoryAdded({required String type}) =>
      _log('memory_added', {'memory_type': type});

  Future<void> logMoodSet({required String label}) =>
      _log('mood_set', {'mood_label': label});

  Future<void> logCanvasOpened({required bool shared}) =>
      _log('canvas_opened', {'shared': shared});

  Future<void> logVibeSent({required String vibeType}) =>
      _log('vibe_sent', {'vibe_type': vibeType});

  Future<void> logMissYouSent() => _log('miss_you_sent');
}
