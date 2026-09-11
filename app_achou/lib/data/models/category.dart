/// Categoria do catálogo.
///
/// `slug` vazio representa a aba "Tudo", que não filtra nada.
class Category {
  const Category({required this.name, required this.slug});

  final String name;
  final String slug;

  static const Category todas = Category(name: 'Tudo', slug: '');

  bool get isTodas => slug.isEmpty;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
    );
  }
}
