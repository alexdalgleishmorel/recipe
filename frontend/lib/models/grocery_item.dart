enum GroceryCategory { produce, protein, dairy, pantry, other }

extension GroceryCategoryLabel on GroceryCategory {
  String get label {
    switch (this) {
      case GroceryCategory.produce:
        return 'Produce';
      case GroceryCategory.protein:
        return 'Protein';
      case GroceryCategory.dairy:
        return 'Dairy';
      case GroceryCategory.pantry:
        return 'Pantry';
      case GroceryCategory.other:
        return 'Other';
    }
  }
}

class GroceryItem {
  GroceryItem({
    required this.amount,
    required this.unit,
    required this.name,
    required this.category,
  });

  /// Null when amounts couldn't be summed cleanly across recipes.
  final double? amount;
  final String unit;
  final String name;
  final GroceryCategory category;
}
