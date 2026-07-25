/// Metadata for a single drawing canvas.
/// The actual strokes are stored in Firebase (paired) or in memory (solo).
class CanvasMeta {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Base64-encoded PNG thumbnail, nullable when no preview has been saved yet.
  final String? previewBase64;

  /// Размер пиксельной сетки. null у обычного холста; у пиксельного задаётся при
  /// создании и дальше не меняется — иначе рисунок партнёра съедет, ведь точки
  /// хранятся в долях 0..1 от листа.
  final int? pixelW;
  final int? pixelH;

  const CanvasMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.previewBase64,
    this.pixelW,
    this.pixelH,
  });

  /// true — холст в режиме пиксель-арта.
  bool get isPixel => (pixelW ?? 0) > 1 && (pixelH ?? 0) > 1;

  /// Пропорция листа: у пиксельного холста её задаёт сетка, у обычного — 4:5.
  double get sheetRatio => isPixel ? pixelW! / pixelH! : 4 / 5;

  CanvasMeta copyWith({
    String? name,
    DateTime? updatedAt,
    String? previewBase64,
    bool clearPreview = false,
  }) =>
      CanvasMeta(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        previewBase64:
            clearPreview ? null : (previewBase64 ?? this.previewBase64),
        pixelW: pixelW,
        pixelH: pixelH,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        if (previewBase64 != null) 'previewBase64': previewBase64,
        if (pixelW != null) 'pixelW': pixelW,
        if (pixelH != null) 'pixelH': pixelH,
      };

  factory CanvasMeta.fromJson(Map<String, dynamic> json) => CanvasMeta(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? 'Canvas',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (json['createdAt'] as num).toInt()),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['updatedAt'] as num).toInt()),
        previewBase64: json['previewBase64'] as String?,
        pixelW: (json['pixelW'] as num?)?.toInt(),
        pixelH: (json['pixelH'] as num?)?.toInt(),
      );
}
