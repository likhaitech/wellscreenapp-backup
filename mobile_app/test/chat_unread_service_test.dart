import 'package:app/services/chat_unread_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Timestamp at(int ms) => Timestamp.fromMillisecondsSinceEpoch(ms);

  test('newest message from the other person, ignoring my own', () {
    final messages = [
      {'senderId': 'me', 'createdAt': at(5000)},
      {'senderId': 'child', 'createdAt': at(3000)},
      {'senderId': 'child', 'createdAt': at(4000)},
      // Not yet stamped by the server.
      {'senderId': 'child', 'createdAt': null},
    ];
    expect(ChatUnreadService.newestFromOther(messages, 'me'), 4000);
    expect(
      ChatUnreadService.newestFromOther([
        {'senderId': 'me', 'createdAt': at(1)},
      ], 'me'),
      isNull,
    );
  });

  test('unread only when the other person wrote after I last looked', () {
    expect(ChatUnreadService.isUnread(4000, null), isTrue);
    expect(ChatUnreadService.isUnread(4000, 3000), isTrue);
    expect(ChatUnreadService.isUnread(4000, 4000), isFalse);
    expect(ChatUnreadService.isUnread(4000, 9000), isFalse);
    expect(ChatUnreadService.isUnread(null, null), isFalse);
  });
}
