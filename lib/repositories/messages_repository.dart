import '../models/models.dart';

abstract class MessagesRepository {
  List<ChatMessage> messagesForFamily(String familyId);

  Stream<List<ChatMessage>> watchMessagesForFamily(String familyId);

  Future<void> upsert(ChatMessage item);

  Future<void> delete(String id);
}
