import 'package:flutter/material.dart';

import '../../models/watch_voice_ui.dart';
import '../../services/locale_service.dart';
import '../../services/watch_voice_service.dart';

/// Полоса голосовой связи под плеером комнаты.
///
/// Живёт ОТДЕЛЬНО от слоя управления видео и не прячется вместе с ним: чтобы
/// поговорить, включать ролик не нужно, поэтому кнопка вызова должна быть на
/// экране всегда. Раньше голос жил внутри всплывающего слоя плеера, и в пустой
/// комнате до него было не добраться вовсе.
class WatchVoiceBar extends StatelessWidget {
  const WatchVoiceBar({
    super.key,
    required this.state,
    required this.micOn,
    required this.speakerOn,
    required this.onCallToggle,
    required this.onMicToggle,
    required this.onSpeakerToggle,
  });

  final VoiceCallState state;
  final bool micOn;
  final bool speakerOn;
  final VoidCallback onCallToggle;
  final VoidCallback onMicToggle;
  final VoidCallback onSpeakerToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    final bar = WatchVoiceBarModel(state);

    final label = switch (state) {
      VoiceCallState.off => s.watchVoiceHint,
      VoiceCallState.connecting => s.watchVoiceConnecting,
      VoiceCallState.live => s.watchVoiceLive,
      VoiceCallState.failed => s.watchVoiceFailed,
    };

    return Material(
      color: cs.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              _Round(
                icon: bar.callEndsTalk
                    ? Icons.call_end_rounded
                    : Icons.call_rounded,
                tooltip:
                    bar.callEndsTalk ? s.watchVoiceHangUp : s.watchVoiceCall,
                busy: bar.busy,
                danger: bar.callEndsTalk,
                active: !bar.callEndsTalk,
                onTap: onCallToggle,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13.5,
                    color: bar.failed ? cs.error : cs.onSurfaceVariant,
                  ),
                ),
              ),
              // Глушилки появляются, только когда друг друга уже слышно: до
              // этого глушить нечего, а две мёртвые кнопки читаются поломкой.
              if (bar.showsMicAndSpeaker) ...[
                _Round(
                  icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                  tooltip: s.watchVoiceMic,
                  active: micOn,
                  onTap: onMicToggle,
                ),
                const SizedBox(width: 8),
                _Round(
                  icon: speakerOn
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  tooltip: s.watchVoiceSpeaker,
                  active: speakerOn,
                  onTap: onSpeakerToggle,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Круглая кнопка полосы: заливка из контейнерных ролей, как у остальных
/// круглых действий приложения.
class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.busy = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = danger
        ? cs.errorContainer
        : active
            ? cs.primaryContainer
            : cs.surfaceContainerHighest;
    final fg = danger
        ? cs.onErrorContainer
        : active
            ? cs.onPrimaryContainer
            : cs.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child:
                        CircularProgressIndicator(strokeWidth: 2.4, color: fg),
                  )
                : Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}
