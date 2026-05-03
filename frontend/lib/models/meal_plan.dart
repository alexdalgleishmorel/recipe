import 'chat_message.dart';

enum PlanStatus { draft, finalized }

class MealPlan {
  MealPlan({
    required this.id,
    required this.name,
    required this.status,
    required this.start,
    required this.end,
    required this.days,
    required this.dates,
    required this.meals,
    required this.candidates,
    required this.grid,
    required this.chat,
  });

  final String id;
  final String? name;
  final PlanStatus status;
  final String start;
  final String end;
  final List<String> days;
  final List<String> dates;
  final List<String> meals;
  final List<String> candidates;
  // grid[dayIdx][mealIdx] = recipeId | null
  final List<List<String?>> grid;
  final List<ChatMessage> chat;

  String get displayName => (name == null || name!.isEmpty)
      ? 'Week of $start–$end'
      : name!;

  bool get isDefaultName => name == null || name!.isEmpty;

  MealPlan copyWith({
    String? id,
    String? name,
    bool nameExplicit = false,
    PlanStatus? status,
    String? start,
    String? end,
    List<String>? days,
    List<String>? dates,
    List<String>? meals,
    List<String>? candidates,
    List<List<String?>>? grid,
    List<ChatMessage>? chat,
  }) {
    final nextName = nameExplicit ? name : (name ?? this.name);
    return MealPlan(
        id: id ?? this.id,
        name: nextName,
        status: status ?? this.status,
        start: start ?? this.start,
        end: end ?? this.end,
        days: days ?? this.days,
        dates: dates ?? this.dates,
        meals: meals ?? this.meals,
        candidates: candidates ?? this.candidates,
        grid: grid ?? this.grid,
        chat: chat ?? this.chat,
      );
  }

  factory MealPlan.fromJson(Map<String, dynamic> j) => MealPlan(
        id: j['id'] as String,
        name: j['name'] as String?,
        status: (j['status'] == 'finalized') ? PlanStatus.finalized : PlanStatus.draft,
        start: (j['start'] ?? '') as String,
        end: (j['end'] ?? '') as String,
        days: ((j['days'] as List?) ?? const []).map((e) => e.toString()).toList(),
        dates: ((j['dates'] as List?) ?? const []).map((e) => e.toString()).toList(),
        meals: ((j['meals'] as List?) ?? const []).map((e) => e.toString()).toList(),
        candidates: ((j['candidates'] as List?) ?? const []).map((e) => e.toString()).toList(),
        grid: ((j['grid'] as List?) ?? const [])
            .map<List<String?>>((row) => (row as List).map<String?>((c) => c?.toString()).toList())
            .toList(),
        chat: ((j['chat'] as List?) ?? const [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status == PlanStatus.finalized ? 'finalized' : 'draft',
        'start': start,
        'end': end,
        'days': days,
        'dates': dates,
        'meals': meals,
        'candidates': candidates,
        'grid': grid,
        'chat': chat.map((c) => c.toJson()).toList(),
      };
}
