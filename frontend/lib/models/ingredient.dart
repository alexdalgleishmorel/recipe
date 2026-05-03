class Ingredient {
  const Ingredient({
    required this.amount,
    required this.unit,
    required this.name,
  });

  final String amount;
  final String unit;
  final String name;

  Ingredient copyWith({String? amount, String? unit, String? name}) =>
      Ingredient(
        amount: amount ?? this.amount,
        unit: unit ?? this.unit,
        name: name ?? this.name,
      );

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
        amount: (j['amount'] ?? '').toString(),
        unit: (j['unit'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'unit': unit,
        'name': name,
      };
}
