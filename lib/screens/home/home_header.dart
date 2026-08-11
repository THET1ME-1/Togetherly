import '../../widgets/mood_image.dart';
import '../../widgets/storage_image.dart';
import 'package:flutter/material.dart';
import '../../utils/safe_text.dart';
import '../../models/pair_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/animations.dart';
import '../miss_you_button.dart';
import 'widgets/relationship_type_dialog.dart';

/// Высота всех блоков шапки.
///
/// Аватары, пилюля типа связи, счёт «скучаю» и круглая кнопка стоят на одной
/// линии и имеют одинаковый рост. До этого их было четыре разных (48, 30, 34 и
/// 28), и строка выглядела собранной из чужих деталей.
///
/// Тридцать четыре, а не сорок: на 360 dp в ряд должны поместиться два
/// аватара, слово «Встречаемся» целиком, оба счёта и сердце. На сорока это не
/// сходится — слово начинает резаться, а резать его нельзя.
const double kHeaderControlHeight = 38;

/// Высота строки. Больше самих блоков: разница уходит в область нажатия,
/// чтобы пилюли ростом 34 всё равно ловили палец по-человечески.
const double kHeaderRowHeight = 50;

/// Насколько соседний аватар наезжает на предыдущий.
const double _avatarStep = 24;

/// Шапка главного экрана: аватары, тип связи, счёт «скучаю».
class HomeHeader extends StatelessWidget {
  final AppTheme theme;
  final bool isPaired;
  final String myAvatarUrl;
  final String myDisplayName;
  final List<GroupMember> partners;
  final MemberMood myMood;
  final MemberMood Function(String uid) moodOf;
  final String statusBadgeText;
  final String statusBadgeEmoji;
  final VoidCallback? onRelationshipTap;
  final String pairId;

  const HomeHeader({
    super.key,
    required this.theme,
    required this.isPaired,
    required this.myAvatarUrl,
    required this.myDisplayName,
    required this.partners,
    required this.myMood,
    required this.moodOf,
    required this.statusBadgeText,
    required this.statusBadgeEmoji,
    this.onRelationshipTap,
    required this.pairId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: SizedBox(
        height: kHeaderRowHeight,
        child: Row(
          children: [
            _avatars(),
            const SizedBox(width: 8),
            // Expanded, а не Flexible: строка обязана доходить до правого
            // края. При Flexible пилюля жалась к содержимому, и справа
            // оставалась дыра шириной с ладонь.
            Expanded(child: _statusPill()),
            if (isPaired) ...[
              const SizedBox(width: 6),
              MissYouButton(
                theme: theme,
                groupId: pairId,
                senderName: myDisplayName,
                enabled: isPaired,
                partnerUid: partners.isEmpty ? '' : partners.first.uid,
                partnerName: partners.isEmpty ? '' : partners.first.name,
                partnerAvatarUrl:
                    partners.isEmpty ? null : partners.first.avatar,
                height: kHeaderControlHeight,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Аватары ────────────────────────────────────────────────────────────────

  Widget _avatars() {
    if (!isPaired) {
      return _avatarWithMood(
        myAvatarUrl,
        name: myDisplayName,
        mood: myMood,
        moodPosition: MoodBadgePosition.bottomRight,
      );
    }
    final shown = partners.take(4).toList();
    return SizedBox(
      width: kHeaderControlHeight + shown.length * _avatarStep,
      height: kHeaderControlHeight,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _avatarWithMood(
              myAvatarUrl,
              name: myDisplayName,
              mood: myMood,
              moodPosition: MoodBadgePosition.topLeft,
            ),
          ),
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: (i + 1) * _avatarStep,
              child: _avatarWithMood(
                shown[i].avatar,
                name: shown[i].name,
                mood: moodOf(shown[i].uid),
                moodPosition: MoodBadgePosition.bottomRight,
              ),
            ),
        ],
      ),
    );
  }

  /// Аватар с кольцом цветом фона.
  ///
  /// Кольцо разделяет наехавшие друг на друга кружки. Раньше эту роль играли
  /// белая обводка и тень — на тёмных темах обводка светилась чужим белым, а
  /// тень нарушала правило «глубину даёт тон, а не размытие».
  Widget _avatarWithMood(
    String url, {
    String? name,
    required MemberMood mood,
    required MoodBadgePosition moodPosition,
  }) {
    const badge = 18.0;
    return SizedBox(
      width: kHeaderControlHeight,
      height: kHeaderControlHeight,
      child: Stack(
        children: [
          Container(
            width: kHeaderControlHeight,
            height: kHeaderControlHeight,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.bgGradient.first,
            ),
            child: ClipOval(
              child: url.isNotEmpty
                  ? StorageImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      memCacheWidth: 120,
                      errorWidget: (context, url, error) =>
                          _avatarPlaceholder(name),
                    )
                  : _avatarPlaceholder(name),
            ),
          ),
          if (mood.isNotEmpty && mood.imagePath.isNotEmpty)
            Positioned(
              top: moodPosition == MoodBadgePosition.topLeft ? 0 : null,
              left: moodPosition == MoodBadgePosition.topLeft ? 0 : null,
              bottom: moodPosition == MoodBadgePosition.bottomRight ? 0 : null,
              right: moodPosition == MoodBadgePosition.bottomRight ? 0 : null,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: theme.bgGradient.first,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: MoodImage(
                    mood.imagePath,
                    width: badge,
                    height: badge,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder(String? name) {
    return Container(
      color: theme.primaryLight,
      child: Center(
        child: Text(
          (name ?? '').firstGraphemeUpper('?'),
          style: TextStyle(
            fontFamily: 'Unbounded',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: theme.primary,
          ),
        ),
      ),
    );
  }

  // ── Тип связи ──────────────────────────────────────────────────────────────

  Widget _statusPill() {
    final active = isPaired;
    // Подложка — поверхность карточки, а не `primaryLight`. У светлых ручных
    // палитр тот почти совпадает с фоном страницы (у вишнёвой `#FBEAEF` на
    // `#FCF0F3`), и пилюля выглядела вовсе без фона.
    final bg = active ? theme.cardSurface : theme.surfaceMuted;
    final fg = active ? theme.primary : theme.textMuted;
    return GestureDetector(
      onTap: active ? onRelationshipTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: kHeaderControlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(kHeaderControlHeight / 2),
        ),
        // Строка во всю ширину пилюли: значок слева, название занимает всё
        // свободное место, стрелка прижата к правому краю. При `min` она
        // липла к слову, и справа оставалась пустая половина пилюли.
        child: Row(
          children: [
            Icon(
              statusBadgeEmoji.isNotEmpty
                  ? relIconForEmoji(statusBadgeEmoji)
                  : Icons.favorite_border_rounded,
              color: fg,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                statusBadgeText,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (active)
              Icon(Icons.expand_more_rounded, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}
