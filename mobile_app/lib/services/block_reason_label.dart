/// Turns a blocked-website entry's reason (saved by the child's phone,
/// RestrictionLogger.kt) into words for the parent's report, for example
/// "adult (keyword match)", "gambling (AI-detected)" or
/// "gambling (page words)".
/// Returns null for app blocks and older entries that have no reason.
String? blockReasonLabel(Map<String, dynamic> entry) {
  final how = switch (entry['blockSource']) {
    'parent_rule' => 'your block list',
    'keyword' => 'keyword match',
    'list' => 'exact match',
    'ai' => 'AI-detected',
    'schedule' => 'schedule',
    'page' => 'page words',
    'hint' => 'possible risk, age 6 and below',
    _ => null,
  };
  if (how == null) return null;

  final category = entry['category'];
  if (category is! String || category.trim().isEmpty) return how;
  return '${category.replaceAll('_', ' ')} ($how)';
}
