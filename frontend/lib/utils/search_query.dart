import '../models/recipe.dart';

/// Datadog-style query parser. Supported syntax (per the help popup in
/// `recipes-wireframe/project/Recipes.html`):
///
///   * Free text             →  `lasagna`
///   * Attribute match       →  `cuisine:italian`
///   * Quoted value          →  `author:"Julia Child"`
///   * OR within attribute   →  `cuisine:(thai OR vietnamese)`
///   * Boolean AND / OR      →  `tags:weeknight AND vegetarian`  (AND default)
///   * Negation              →  `-dairy`, `-cuisine:french`
///   * Numeric comparison    →  `prepTime:<30`, `servings:>=4`
///   * Custom key:value tag  →  `cookware:cast-iron`
///
/// Returns a predicate that resolves to true if the recipe matches the query.
/// Empty / whitespace queries match everything.
typedef RecipePredicate = bool Function(Recipe recipe);

RecipePredicate parseSearchQuery(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return (_) => true;
  final tokens = _tokenize(trimmed);
  if (tokens.isEmpty) return (_) => true;
  final terms = <_Term>[];
  final ops = <_BoolOp>[]; // ops[i] joins terms[i] with terms[i+1]

  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == 'AND' || t == 'OR') {
      // Coalesce: if no preceding term yet, ignore.
      if (terms.isEmpty) continue;
      ops.add(t == 'OR' ? _BoolOp.or : _BoolOp.and);
      continue;
    }
    // Implicit AND between adjacent terms when no operator was specified.
    if (terms.isNotEmpty && ops.length == terms.length - 1) {
      ops.add(_BoolOp.and);
    }
    terms.add(_parseTerm(t));
  }

  return (recipe) {
    if (terms.isEmpty) return true;
    var acc = terms[0].matches(recipe);
    for (var i = 0; i < ops.length && i + 1 < terms.length; i++) {
      final next = terms[i + 1].matches(recipe);
      acc = ops[i] == _BoolOp.and ? (acc && next) : (acc || next);
    }
    return acc;
  };
}

// ──────────────────────────────────────────────────────────────────────────
// Tokenizer — splits on whitespace, respecting "..." quotes and (...) groups.
// ──────────────────────────────────────────────────────────────────────────

List<String> _tokenize(String input) {
  final tokens = <String>[];
  final buf = StringBuffer();
  int i = 0;
  bool inQuote = false;
  int parenDepth = 0;
  while (i < input.length) {
    final ch = input[i];
    if (ch == '"') {
      buf.write(ch);
      inQuote = !inQuote;
      i++;
      continue;
    }
    if (!inQuote && ch == '(') {
      buf.write(ch);
      parenDepth++;
      i++;
      continue;
    }
    if (!inQuote && ch == ')') {
      buf.write(ch);
      if (parenDepth > 0) parenDepth--;
      i++;
      continue;
    }
    if (!inQuote && parenDepth == 0 && _isWhitespace(ch)) {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
      i++;
      continue;
    }
    buf.write(ch);
    i++;
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  return tokens;
}

bool _isWhitespace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

enum _BoolOp { and, or }

// ──────────────────────────────────────────────────────────────────────────
// Term parsing — converts a single token into a predicate fragment.
// ──────────────────────────────────────────────────────────────────────────

_Term _parseTerm(String raw) {
  var s = raw;
  var negated = false;
  if (s.startsWith('-') && s.length > 1) {
    negated = true;
    s = s.substring(1);
  }
  final colon = s.indexOf(':');
  if (colon <= 0) {
    return _FreeTerm(_unwrap(s), negated: negated);
  }
  final field = s.substring(0, colon);
  final raw2 = s.substring(colon + 1);
  // Numeric comparison: starts with <, >, <=, >=
  if (raw2.startsWith('<=') || raw2.startsWith('>=')) {
    final op = raw2.substring(0, 2);
    final val = double.tryParse(raw2.substring(2));
    if (val != null) return _NumTerm(field, op, val, negated: negated);
  }
  if (raw2.startsWith('<') || raw2.startsWith('>')) {
    final op = raw2.substring(0, 1);
    final val = double.tryParse(raw2.substring(1));
    if (val != null) return _NumTerm(field, op, val, negated: negated);
  }
  // OR-within-attribute: field:(a OR b)
  if (raw2.startsWith('(') && raw2.endsWith(')')) {
    final inner = raw2.substring(1, raw2.length - 1);
    final parts = inner
        .split(RegExp(r'\s+OR\s+', caseSensitive: true))
        .map((p) => _unwrap(p.trim()))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) return _FieldOrTerm(field, parts, negated: negated);
  }
  // Plain field:value (or field:"quoted value")
  return _FieldTerm(field, _unwrap(raw2), negated: negated);
}

String _unwrap(String s) {
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

// ──────────────────────────────────────────────────────────────────────────
// Term implementations
// ──────────────────────────────────────────────────────────────────────────

abstract class _Term {
  _Term({this.negated = false});
  final bool negated;
  bool matches(Recipe r) {
    final m = _match(r);
    return negated ? !m : m;
  }
  bool _match(Recipe r);
}

class _FreeTerm extends _Term {
  _FreeTerm(this.value, {super.negated});
  final String value;
  @override
  bool _match(Recipe r) {
    final v = value.toLowerCase();
    if (v.isEmpty) return true;
    if (r.title.toLowerCase().contains(v)) return true;
    if (r.description.toLowerCase().contains(v)) return true;
    if (r.cuisine.toLowerCase().contains(v)) return true;
    for (final t in r.tags) {
      if (t.toLowerCase().contains(v)) return true;
    }
    for (final d in r.dietary) {
      if (d.toLowerCase().contains(v)) return true;
    }
    if (r.author.toLowerCase().contains(v)) return true;
    for (final ing in r.ingredients) {
      if (ing.name.toLowerCase().contains(v)) return true;
    }
    return false;
  }
}

class _FieldTerm extends _Term {
  _FieldTerm(this.field, this.value, {super.negated});
  final String field;
  final String value;
  @override
  bool _match(Recipe r) => _matchField(r, field, value);
}

class _FieldOrTerm extends _Term {
  _FieldOrTerm(this.field, this.values, {super.negated});
  final String field;
  final List<String> values;
  @override
  bool _match(Recipe r) => values.any((v) => _matchField(r, field, v));
}

class _NumTerm extends _Term {
  _NumTerm(this.field, this.op, this.value, {super.negated});
  final String field;
  final String op;
  final double value;
  @override
  bool _match(Recipe r) {
    final n = _numField(r, field);
    if (n == null) return false;
    switch (op) {
      case '<':  return n < value;
      case '>':  return n > value;
      case '<=': return n <= value;
      case '>=': return n >= value;
    }
    return false;
  }
}

bool _matchField(Recipe r, String field, String value) {
  final v = value.toLowerCase();
  switch (field) {
    case 'title':
      return r.title.toLowerCase().contains(v);
    case 'description':
      return r.description.toLowerCase().contains(v);
    case 'cuisine':
      return r.cuisine.toLowerCase().contains(v);
    case 'author':
      return r.author.toLowerCase().contains(v);
    case 'tags':
      return r.tags.any((t) => t.toLowerCase().contains(v));
    case 'dietary':
      return r.dietary.any((d) => d.toLowerCase().contains(v));
    case 'ingredients.name':
    case 'ingredients':
      return r.ingredients.any((i) => i.name.toLowerCase().contains(v));
    case 'prepTime':
      return r.prepTime.toString() == value;
    case 'cookTime':
      return r.cookTime.toString() == value;
    case 'servings':
      return r.servings.toString() == value;
  }
  // Treat unknown fields as custom-tag keys.
  return r.customTags.any(
    (c) => c.key.toLowerCase() == field.toLowerCase() &&
        c.value.toLowerCase().contains(v),
  );
}

double? _numField(Recipe r, String field) {
  switch (field) {
    case 'prepTime':
      return r.prepTime.toDouble();
    case 'cookTime':
      return r.cookTime.toDouble();
    case 'servings':
      return r.servings.toDouble();
  }
  return null;
}
