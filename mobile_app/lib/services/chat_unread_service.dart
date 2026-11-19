import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unread-chat dot for the Chat tab, worked out on this phone from the
/// conversation itself: the dot shows when the newest message from the
/// other person is newer than the last time this account opened the chat
/// here. It doesn't depend on the backend writing an inbox record, so it
/// works even when the push service is asleep or not deployed.
class ChatUnreadService {
  ChatUnreadService._();

  static final StreamController<void> _seenChanged =
      StreamController<void>.broadcast();

  static String _key(String childProfileId, String uid) =>
      'wellscreen_chat_seen_${childProfileId}_$uid';

  /// Call when the conversation is opened and when it is closed.
  static Future<void> markSeen(String childProfileId, String uid) async {
    if (childProfileId.isEmpty || uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _key(childProfileId, uid),
      DateTime.now().millisecondsSinceEpoch,
    );
    _seenChanged.add(null);
  }

  /// Newest createdAt (ms) among [messages] not sent by [uid]; null if none.
  /// Messages still waiting for their server time are skipped.
  static int? newestFromOther(
    Iterable<Map<String, dynamic>> messages,
    String uid,
  ) {
    int? newest;
    for (final message in messages) {
      if (message['senderId'] == uid) continue;
      final createdAt = message['createdAt'];
      int? ms;
      if (createdAt is Timestamp) ms = createdAt.millisecondsSinceEpoch;
      if (createdAt is DateTime) ms = createdAt.millisecondsSinceEpoch;
      if (ms == null) continue;
      if (newest == null || ms > newest) newest = ms;
    }
    return newest;
  }

  static bool isUnread(int? newestFromOtherMs, int? seenMs) =>
      newestFromOtherMs != null &&
      (seenMs == null || newestFromOtherMs > seenMs);

  /// True while there is a message from the other person this account
  /// hasn't opened the chat to see yet.
  static Stream<bool> hasUnread(String childProfileId, String uid) {
    if (childProfileId.isEmpty || uid.isEmpty) return Stream.value(false);
    late StreamController<bool> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? messages;
    StreamSubscription<void>? seen;
    int? newest;

    Future<void> emit() async {
      final prefs = await SharedPreferences.getInstance();
      final seenMs = prefs.getInt(_key(childProfileId, uid));
      if (!controller.isClosed) controller.add(isUnread(newest, seenMs));
    }

    controller = StreamController<bool>(
      onListen: () {
        messages = FirebaseFirestore.instance
            .collection('child_profiles')
            .doc(childProfileId)
            .collection('chat_messages')
            .orderBy('createdAt', descending: true)
            .limit(20)
            .snapshots()
            .listen(
              (snapshot) {
                newest = newestFromOther(
                  snapshot.docs.map((doc) => doc.data()),
                  uid,
                );
                unawaited(emit());
              },
              onError: (_) {
                if (!controller.isClosed) controller.add(false);
              },
            );
        seen = _seenChanged.stream.listen((_) => unawaited(emit()));
      },
      onCancel: () async {
        await messages?.cancel();
        await seen?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }
}
