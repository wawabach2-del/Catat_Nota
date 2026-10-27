/// Kategori transaksi. [keywords] dipakai parser untuk menebak kategori otomatis.
class Category {
  final String id;
  final String name;
  final int colorValue;
  final List<String> keywords;

  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    this.keywords = const [],
  });

  Category copyWith({String? name, int? colorValue, List<String>? keywords}) => Category(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        keywords: keywords ?? this.keywords,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'color': colorValue,
        'keywords': keywords.join(','),
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as String,
        name: m['name'] as String,
        colorValue: m['color'] as int,
        keywords: ((m['keywords'] as String?) ?? '')
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList(),
      );
}
