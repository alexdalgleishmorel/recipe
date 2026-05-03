enum ChatWho { user, ai }

class ChatMessage {
  ChatMessage({required this.who, required this.text});

  final ChatWho who;
  final String text;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        who: (j['who'] == 'ai') ? ChatWho.ai : ChatWho.user,
        text: (j['text'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'who': who == ChatWho.ai ? 'ai' : 'user',
        'text': text,
      };
}
