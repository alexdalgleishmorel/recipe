class CustomTag {
  const CustomTag({required this.key, required this.value});

  final String key;
  final String value;

  CustomTag copyWith({String? key, String? value}) =>
      CustomTag(key: key ?? this.key, value: value ?? this.value);

  factory CustomTag.fromJson(Map<String, dynamic> j) => CustomTag(
        key: (j['key'] ?? '').toString(),
        value: (j['value'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}
