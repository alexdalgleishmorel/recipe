import '../models/grocery_item.dart';
import '../models/recipe.dart';

/// Parse a numeric prefix from amounts like "1.5", "1/2", "2", or "1-2".
/// Returns null when the amount has no leading number.
double? parseAmt(String? a) {
  if (a == null) return null;
  final s = a.trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d+/\d+$').hasMatch(s)) {
    final parts = s.split('/').map(double.parse).toList();
    return parts[0] / parts[1];
  }
  final m = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(s);
  if (m == null) return null;
  return double.parse(m.group(1)!);
}

/// Format a parsed amount for display, restoring common fractions where they
/// look more natural than decimals.
String formatAmt(double? n) {
  if (n == null) return '';
  if (n == n.truncateToDouble()) return n.toInt().toString();
  // Keyed by `(value * 1000).round()` to avoid float-key issues.
  const fractions = {
    250: '1/4',
    333: '1/3',
    500: '1/2',
    667: '2/3',
    750: '3/4',
    1500: '1.5',
  };
  final f = fractions[(n * 1000).round()];
  if (f != null) return f;
  final s = n.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Normalize a unit string so "tbsp" + "tbsp" can sum.
String normUnit(String? u) {
  if (u == null) return '';
  return u.toLowerCase().replaceFirst(RegExp(r'\.$'), '').trim();
}

/// Map an ingredient name to one of the five grocery categories.
GroceryCategory categorize(String name) {
  final n = name.toLowerCase();
  if (RegExp(
    r'(\bchicken\b|\bpork\b|\bbeef\b|\blamb\b|\bsalmon\b|\bfish\b(?! sauce)|\btofu\b|\bpaneer\b|\blardons?\b|\bbacon\b|\bsausage\b|\bshrimp\b|\bprawn\b|\beggs?\b|ground\s+\w+|chorizo|anchov|turkey|duck|tempeh|seitan)',
  ).hasMatch(n)) {
    return GroceryCategory.protein;
  }
  if (RegExp(
    r'(\bmilk\b|\bcream\b|\bbutter\b|\byogurt\b|\bcheese\b|ricotta|parmes|parmigiano|pecorino|\bfeta\b|buttermilk|mozzarella|gruyere|cheddar|crème|creme fra)',
  ).hasMatch(n)) {
    return GroceryCategory.dairy;
  }
  // Pantry checked before produce so "canned tomatoes" doesn't read as produce.
  if (RegExp(
    r'(\bcan\b|\bcanned\b|cans of|\bjar\b|\bbottle\b|pasta|\bspaghetti\b|bucatini|noodle|\brice\b(?! noodle)|tortilla|\bbread\b|pita|baguette|\bflour\b|cornmeal|\bsugar\b|\boil\b|vinegar|soy sauce|fish sauce|\bmiso\b|mirin|\bsake\b|\bwine\b|stock|broth|\bbeans?\b|chickpea|lentil|cocoa|baking (?:powder|soda)|sesame seed|\bnori\b|achiote|vanilla|salt|peppercorn|spice|paste|honey|maple|chocolate|coffee|tea|crushed tomatoes|whole tomatoes \(|tomato sauce|tomato paste|adobo|guajillo|chipotle in|stock cube|breadcrumb|panko|coconut milk|coconut cream)',
  ).hasMatch(n)) {
    return GroceryCategory.pantry;
  }
  if (RegExp(
    r'(onion|garlic|lemon|\blime\b|tomato|potato|spinach|broccoli|\bpepper\b|parsley|cilantro|mushroom|carrot|cucumber|zucchini|eggplant|\bherb\b|scallion|ginger|chile|chili|\bleek\b|cabbage|kale|lettuce|apple|\borange\b|pineapple|avocado|basil|thyme|rosemary|sage|mint|chive|fennel|celery|bell|sprig|cloves|leaves|berr|\bpear\b|peach|cherry|grape|fig\b|pomegranate|radish|squash|pumpkin|asparagus|\bcorn\b|pea\b|cauliflower|sprout|shallot|galangal|lemongrass|lime leaf|kaffir)',
  ).hasMatch(n)) {
    return GroceryCategory.produce;
  }
  return GroceryCategory.other;
}

/// Aggregate ingredients across the given recipes, summing matching units and
/// grouping by category. Each category's items are sorted alphabetically.
Map<GroceryCategory, List<GroceryItem>> aggregateIngredients(
  Iterable<Recipe> recipes,
) {
  final bucket = <String, _Bucket>{};
  for (final r in recipes) {
    for (final ing in r.ingredients) {
      final u = normUnit(ing.unit);
      final key = '${ing.name.toLowerCase().trim()}|$u';
      final n = parseAmt(ing.amount);
      final existing = bucket[key];
      if (existing == null) {
        bucket[key] = _Bucket(amount: n, unit: u, name: ing.name);
      } else {
        if (n != null && existing.amount != null) {
          existing.amount = existing.amount! + n;
        } else {
          existing.amount = null;
        }
      }
    }
  }
  final out = <GroceryCategory, List<GroceryItem>>{
    GroceryCategory.produce: [],
    GroceryCategory.protein: [],
    GroceryCategory.dairy: [],
    GroceryCategory.pantry: [],
    GroceryCategory.other: [],
  };
  for (final b in bucket.values) {
    final cat = categorize(b.name);
    out[cat]!.add(GroceryItem(amount: b.amount, unit: b.unit, name: b.name, category: cat));
  }
  for (final list in out.values) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  return out;
}

class _Bucket {
  _Bucket({required this.amount, required this.unit, required this.name});
  double? amount;
  final String unit;
  final String name;
}

/// Render an aggregated grocery map as plain text suitable for the clipboard.
/// Categories with no items are skipped. Each line reads like "- 2 tbsp olive
/// oil"; the leading quantity is omitted when there's none.
String formatGroceryList(Map<GroceryCategory, List<GroceryItem>> cats) {
  final buf = StringBuffer();
  for (final cat in GroceryCategory.values) {
    final items = cats[cat];
    if (items == null || items.isEmpty) continue;
    if (buf.isNotEmpty) buf.writeln();
    buf.writeln('${cat.label.toUpperCase()}:');
    for (final it in items) {
      final qty = [formatAmt(it.amount), it.unit].where((s) => s.isNotEmpty).join(' ');
      buf.writeln(qty.isEmpty ? '- ${it.name}' : '- $qty ${it.name}');
    }
  }
  return buf.toString().trimRight();
}
