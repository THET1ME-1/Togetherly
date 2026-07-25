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

  /// Пропорция листа (ширина/высота), с которой холст создан.
  ///
  /// null — холст из времён, когда лист занимал всю свободную область экрана.
  /// Точки штрихов хранятся в долях 0..1 от холста, поэтому такие рисунки
  /// нельзя перекладывать на лист 4:5 — их сплющило бы. Им оставляем прежнее
  /// поведение, лист получают только новые холсты.
  final double? sheetRatio;

  const CanvasMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.previewBase64,
    this.pixelW,
    this.pixelH,
    this.sheetRatio,
  });

  /// true — холст в режиме пиксель-арта.
  bool get isPixel => (pixelW ?? 0) > 1 && (pixelH ?? 0) > 1;

  /// Пропорция листа для отрисовки: у пиксельного её задаёт сетка, у нового
  /// обычного — сохранённая, у старого — null (рисуем во всю область).
  double? get effectiveRatio =>
      isPixel ? pixelW! / pixelH! : sheetRatio;

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
        sheetRatio: sheetRatio,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        if (previewBase64 != null) 'previewBase64': previewBase64,
        if (pixelW != null) 'pixelW': pixelW,
        if (pixelH != null) 'pixelH': pixelH,
        if (sheetRatio != null) 'sheetRatio': sheetRatio,
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
        sheetRatio: (json['sheetRatio'] as num?)?.toDouble(),
      );
}
