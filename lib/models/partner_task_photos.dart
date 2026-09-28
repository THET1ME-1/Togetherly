import 'memory.dart';

/// Фото из заданий дня в виджете «Фото партнёра» (обращение 197, 28.09.2026).
///
/// Виджет показывает снимки, которые партнёр отправил прямо в него. Задание
/// дня кладёт фото в ленту, и до виджета оно не доходило. Теперь по
/// настройке «Фото из заданий дня» ([kPartnerTaskPhotosKey]) карусель виджета
/// дополняется последними такими снимками партнёра.

/// Ключ настройки в HomeWidgetPreferences: фон её тоже читает.
const String kPartnerTaskPhotosKey = 'widget_partner_task_photos';

/// Сколько снимков из заданий берём в карусель.
const int kPartnerTaskPhotosLimit = 10;

/// Потолок всей карусели: каждый снимок скачивается на телефон.
const int kPartnerCarouselLimit = 20;

/// Снимки из заданий дня, которые выложил [partnerUid], новые первыми.
///
/// Секретные и ещё запечатанные капсулы не берём: на рабочем столе их увидит
/// любой, кто взял телефон. Видео тоже: виджет показывает картинку.
List<String> partnerTaskPhotos(
  Iterable<Memory> memories, {
  required String partnerUid,
  DateTime? now,
  int limit = kPartnerTaskPhotosLimit,
}) {
  if (partnerUid.isEmpty) return const [];
  final sorted = memories.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final out = <String>[];
  for (final m in sorted) {
    if (m.authorUid != partnerUid) continue;
    if ((m.dailyTaskId ?? '').isEmpty) continue;
    if (m.type != MemoryType.photo) continue;
    if (m.isSecret || m.sealedNow(now)) continue;
    final urls = (m.imageUrls != null && m.imageUrls!.isNotEmpty)
        ? m.imageUrls!
        : [if ((m.imageUrl ?? '').isNotEmpty) m.imageUrl!];
    for (final u in urls) {
      if (u.isEmpty || out.contains(u)) continue;
      out.add(u);
      if (out.length >= limit) return out;
    }
  }
  return out;
}

/// Карусель виджета: сперва то, что партнёр отправил сам, следом задания.
List<String> mergePartnerCarousel(
  List<String> sent,
  List<String> tasks, {
  int limit = kPartnerCarouselLimit,
}) {
  final out = <String>[];
  for (final u in [...sent, ...tasks]) {
    if (u.isEmpty || out.contains(u)) continue;
    out.add(u);
    if (out.length >= limit) break;
  }
  return out;
}
