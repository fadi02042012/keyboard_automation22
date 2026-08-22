class Shortcut {
  final String key;
  final List<String> modifiers;
  final String description;
  final String category;

  const Shortcut({
    required this.key,
    required this.modifiers,
    required this.description,
    this.category = 'عام',
  });
}
