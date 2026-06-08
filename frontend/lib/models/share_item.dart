/// The kind of entity being shared. Sharing always produces an editable COPY
/// (fork) of the item on claim.
enum ShareItemType { recipe, collection }

ShareItemType shareItemTypeFromString(String s) =>
    s == 'collection' ? ShareItemType.collection : ShareItemType.recipe;

String shareItemTypeToString(ShareItemType t) =>
    t == ShareItemType.collection ? 'collection' : 'recipe';

/// A lightweight pointer to the thing being shared: a type + the source id in
/// the sharer's library. `title` is carried along so "Shared with me" can show
/// something meaningful without resolving the source library.
class ShareItem {
  ShareItem({
    required this.type,
    required this.id,
    required this.title,
  });

  final ShareItemType type;
  final String id;
  final String title;

  ShareItem copyWith({ShareItemType? type, String? id, String? title}) =>
      ShareItem(
        type: type ?? this.type,
        id: id ?? this.id,
        title: title ?? this.title,
      );

  factory ShareItem.fromJson(Map<String, dynamic> j) => ShareItem(
        type: shareItemTypeFromString((j['type'] ?? 'recipe') as String),
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'type': shareItemTypeToString(type),
        'id': id,
        'title': title,
      };
}
