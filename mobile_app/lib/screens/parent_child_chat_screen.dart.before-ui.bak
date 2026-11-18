import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/chat_notifications_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_usage_icon.dart';



/// Parent-child chat and app-access request screen.
///
/// This changes presentation only; requests still require the trusted backend
/// before an individual package is temporarily allowed by Android.
/// Firestore snapshots provide live updates and queued offline writes.
class ParentChildChatScreen extends StatefulWidget {
  const ParentChildChatScreen({
    super.key,
    required this.childProfileId,
    required this.isParent,
  });

  final String childProfileId;
  final bool isParent;

  @override
  State<ParentChildChatScreen> createState() => _ParentChildChatScreenState();
}

class _ParentChildChatScreenState extends State<ParentChildChatScreen> {
  final TextEditingController _message = TextEditingController();
  bool _sendingMessage = false;
  bool _sendingRequest = false;
  bool _showRequestComposer = false;
  String? _selectedPackage;
  int _requestedMinutes = 60;
  final Set<String> _locallyRequestedPackages = <String>{};
  String? _decidingRequest;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _inboxReadSubscription;

  static const Color _chatBlue = AppColors.primary;
  static const Color _chatDarkBlue = AppColors.primaryDark;
  static const Color _softBlue = Color(0xFFEDF3FF);
  static const Color _chatLine = Color(0xFFDCE5F5);

  DocumentReference<Map<String, dynamic>> get _profile => FirebaseFirestore
      .instance
      .collection('child_profiles')
      .doc(widget.childProfileId);

  @override
  void initState() {
    super.initState();
    // A conversation view acknowledges its own unread notification history.
    // Firestore queues this change while offline and synchronizes on return.
    unawaited(ChatNotificationsService.instance.markProfileRead(widget.childProfileId));
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _inboxReadSubscription = ChatNotificationsService.instance
          .inboxFor(uid)
          .where('childProfileId', isEqualTo: widget.childProfileId)
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.metadata.hasPendingWrites &&
            snapshot.docs.any((doc) => doc.data()['readAt'] == null)) {
          unawaited(ChatNotificationsService.instance
              .markProfileRead(widget.childProfileId));
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(_inboxReadSubscription?.cancel());
    _message.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _dispatchCommittedEvent(String kind, String eventId) async {
    // A successful Firestore chat write does not itself send FCM. This
    // request dispatches the event, with retries for Render cold starts.
    for (var attempt = 1; attempt <= 3; attempt++) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      try {
        final response = await Dio().post<Object?>(
          '${AppConfig.backendBaseUrl}/chat/events/${widget.childProfileId}/$kind/$eventId/dispatch',
          options: Options(
            headers: {'Authorization': 'Bearer ${await user.getIdToken()}'},
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 70),
          ),
        );
        // HTTP 2xx only means that Render handled the request. Inspect the
        // backend result separately to see whether FCM was actually sent.
        debugPrint(
          'WellScreen $kind notification dispatch: '
          'HTTP=${response.statusCode} '
          'attempt=$attempt result=${response.data}',
        );
        return;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        debugPrint('WellScreen $kind notification dispatch failed: '
            'HTTP=$status attempt=$attempt '
            'detail=${error.response?.data ?? error.message}');
        // Only retry transient failures. Auth/pairing/data errors need a fix.
        if (status == 400 || status == 401 ||
            status == 403 || status == 404) {
          return;
        }
      } catch (error) {
        debugPrint('WellScreen $kind dispatch error: $error');
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(seconds: 3 * attempt));
      }
    }
    debugPrint('WellScreen $kind notification pending for backend sweep.');
  }

  void _sendText(String uid) {
    final text = _message.text.trim();
    if (_sendingMessage || text.isEmpty || text.length > 2000) return;
    setState(() => _sendingMessage = true);
    _message.clear();
    final doc = _profile.collection('chat_messages').doc();
    // Returning immediately is intentional: Firestore queues writes offline.
    unawaited(doc.set({
      'senderId': uid,
      'body': text,
      'createdAt': FieldValue.serverTimestamp(),
      'notificationState': 'pending',
    }).then((_) => _dispatchCommittedEvent('message', doc.id))
        .catchError((Object error) {
      _showError(error);
    }));
    if (mounted) setState(() => _sendingMessage = false);
  }

  Future<void> _submitAccessRequest(
    String uid,
    List<Map<String, String>> apps,
    Set<String> pendingPackages,
  ) async {
    if (_sendingRequest) return;
    final packageName = _selectedPackage;
    if (packageName == null || packageName.isEmpty) {
      _showError('Select an application first.');
      return;
    }
    final matching = apps.where((app) => app['packageName'] == packageName);
    if (matching.isEmpty) {
      _showError('The selected app is no longer restricted.');
      return;
    }
    if (pendingPackages.contains(packageName) ||
        !_locallyRequestedPackages.add(packageName)) {
      _showError('You already have an unresolved request for this app.');
      return;
    }
    setState(() => _sendingRequest = true);
    final doc = _profile.collection('access_requests').doc();
    // A fixed Firestore document ID prevents retries of the same write from
    // creating duplicate request records; approval is always backend-only.
    unawaited(doc.set({
      'childUid': uid,
      'packageName': packageName,
      'appName': matching.first['appName'],
      'requestedMinutes': _requestedMinutes,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'notificationState': 'pending',
    }).then((_) => _dispatchCommittedEvent('request', doc.id))
        .catchError((Object error) {
      _locallyRequestedPackages.remove(packageName);
      _showError(error);
    }));
    if (mounted) {
      setState(() {
        _sendingRequest = false;
        _showRequestComposer = false;
        _selectedPackage = null;
      });
    }
  }

Future<void> _decide(
  String requestId, {
  required bool approve,
  required int minutes,
}) async {
  if (_decidingRequest != null) return;

  setState(() => _decidingRequest = requestId);

  try {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('Please sign in again.');
    }

    final token = await user.getIdToken();

    await Dio().post<Object?>(
      '${AppConfig.backendBaseUrl}/chat/requests/'
      '${widget.childProfileId}/$requestId/decision',
      data: {
        'approve': approve,
        'approvedMinutes': approve ? minutes : null,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
        },
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 35),
      ),
    );

    debugPrint('App access decision saved successfully.');
  } on DioException catch (error) {
    final responseData = error.response?.data;

    String detail = 'Unable to process the request.';

    if (responseData is Map) {
      detail = (responseData['detail'] ?? detail).toString();
    } else if (responseData != null) {
      detail = responseData.toString();
    } else if (error.message != null) {
      detail = error.message!;
    }

    final status = error.response?.statusCode;

    debugPrint(
      'App access decision failed: '
      'HTTP=$status, '
      'PATH=${error.requestOptions.uri.path}, '
      'DETAIL=$detail',
    );

    _showError(
      'Request failed (HTTP ${status ?? 'network error'}): $detail',
    );
  } catch (error) {
    debugPrint('App access decision error: $error');
    _showError(error);
  } finally {
    if (mounted) {
      setState(() => _decidingRequest = null);
    }
  }
}

  Future<void> _openApprovalDialog(String id, int requested) async {
    var minutes = requested;
    final decided = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          title: const Text('Modify Approved Time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Child requested $requested minutes.'),
              const SizedBox(height: 12),
              const Text('Approve for:'),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: minutes,
                isExpanded: true,
                items: (<int>{5, 10, 15, 20, 30, 45, 60, 90, 120, 180, requested}
                      .toList()..sort())
                    .map((value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value minutes'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setModalState(() => minutes = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, minutes),
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
    if (decided != null) {
      await _decide(id, approve: true, minutes: decided);
    }
  }

  static String _time(dynamic raw) {
    if (raw is! Timestamp) return 'Pending sync';
    final date = raw.toDate();
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
  }

  static IconData _fallback(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('youtube')) return Icons.play_circle_fill_rounded;
    if (lower.contains('facebook') || lower.contains('chrome')) {
      return Icons.public_rounded;
    }
    if (lower.contains('game') || lower.contains('legend')) {
      return Icons.sports_esports_rounded;
    }
    return Icons.apps_rounded;
  }

  String? _iconFor(Map<String, dynamic> profile, String pkg) {
    final report = profile['latestUsageReport'];
    if (report is! Map) return null;
    final allApps = report['allApps'];
    if (allApps is! List) return null;
    for (final entry in allApps) {
      if (entry is Map &&
          entry['packageName'] == pkg &&
          entry['iconBase64'] is String) {
        return entry['iconBase64'] as String;
      }
    }
    return null;
  }

  Widget _messageBubble(Map<String, dynamic> item, String uid) {
    final own = item['senderId'] == uid;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.79,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: own ? _chatBlue : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(17),
              topRight: const Radius.circular(17),
              bottomLeft: Radius.circular(own ? 17 : 5),
              bottomRight: Radius.circular(own ? 5 : 17),
            ),
            border: own ? null : Border.all(color: _chatLine),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 7,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  (item['body'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.32,
                    color: own ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _time(item['createdAt']),
                style: TextStyle(
                  fontSize: 10,
                  color: own ? Colors.white70 : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestCard(
    Map<String, dynamic> request,
    String id,
    Map<String, dynamic> profile,
  ) {
    final app = (request['appName'] ?? request['packageName'] ?? 'App').toString();
    final pkg = (request['packageName'] ?? '').toString();
    final requested = request['requestedMinutes'] is num
        ? (request['requestedMinutes'] as num).toInt()
        : 0;
    final rawStatus = (request['status'] ?? 'pending').toString();
    final endTime = request['expiresAt'];
    final status = rawStatus == 'active' &&
            endTime is Timestamp &&
            !endTime.toDate().isAfter(DateTime.now())
        ? 'expired'
        : rawStatus;
    final approved = request['approvedMinutes'];
    final pending = status == 'pending';
    final isBusy = _decidingRequest != null;
    final label = switch (status) {
      'pending' => 'Pending approval',
      'approved_pending_activation' => 'Approved • awaiting activation',
      'active' => 'Access active',
      'expired' => 'Access expired',
      'declined' => 'Declined',
      _ => status.replaceAll('_', ' '),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 9),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCFDDFC)),
            boxShadow: const [
              BoxShadow(color: Color(0x0A24488E), blurRadius: 10),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.access_time_filled_rounded, size: 17, color: _chatBlue),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'App Access Request',
                      style: TextStyle(
                        color: _chatDarkBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: _chatLine, height: 19),
              Row(
                children: [
                  AppUsageIcon(
                    encoded: _iconFor(profile, pkg),
                    fallback: _fallback(app),
                    fallbackColor: _chatBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Requested: $requested minutes',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (approved is num)
                          Text(
                            'Approved: ${approved.toInt()} minutes',
                            style: const TextStyle(
                              color: _chatBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: status == 'declined'
                          ? AppColors.dangerBg
                          : status == 'active'
                              ? AppColors.successBg
                              : _softBlue,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        color: _chatDarkBlue,
                      ),
                    ),
                  ),
                  Text(
                    _time(request['createdAt']),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (widget.isParent && pending) ...[
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 39,
                        child: FilledButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => _decide(
                                    id,
                                    approve: true,
                                    minutes: requested,
                                  ),
                          icon: const Icon(Icons.check_rounded, size: 17),
                          label: const Text('Approve', style: TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            backgroundColor: _chatBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 39,
                        child: OutlinedButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => _decide(id, approve: false, minutes: 0),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('Decline', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => _openApprovalDialog(id, requested),
                    icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                    label: const Text('Modify time before approval'),
                    style: TextButton.styleFrom(foregroundColor: _chatBlue),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestComposer(
    String uid,
    List<Map<String, String>> apps,
    Set<String> pending,
  ) {
    final allowedSelection = apps.any((a) => a['packageName'] == _selectedPackage);
    final selected = allowedSelection
        ? _selectedPackage
        : (apps.isEmpty ? null : apps.first['packageName']);
    final selectedIsPending = selected != null && pending.contains(selected);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 7),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFCEDDFB)),
        boxShadow: const [BoxShadow(color: Color(0x0D214989), blurRadius: 9)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_clock_rounded, size: 18, color: _chatBlue),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Request Access',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (apps.isEmpty)
            const Text(
              'No restricted applications are available to request.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else ...[
            DropdownButtonFormField<String>(
              key: ValueKey(selected),
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.apps_rounded, color: _chatBlue),
                labelText: 'Application or game',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: apps.map((app) {
                return DropdownMenuItem<String>(
                  value: app['packageName'],
                  child: Text(
                    app['appName'] ?? app['packageName'] ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedPackage = value);
              },
            ),
            const SizedBox(height: 9),
            DropdownButtonFormField<int>(
              initialValue: _requestedMinutes,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.schedule_rounded, color: _chatBlue),
                labelText: 'Requested duration',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [5, 10, 15, 30, 45, 60, 90, 120]
                  .map((minutes) => DropdownMenuItem<int>(
                        value: minutes,
                        child: Text('$minutes minutes'),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _requestedMinutes = value);
              },
            ),
            if (selectedIsPending) ...[
              const SizedBox(height: 8),
              const Text(
                'A request for this app is already pending or active.',
                style: TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sendingRequest || apps.isEmpty || selectedIsPending
                      ? null
                      : () {
                          _selectedPackage = selected;
                          _submitAccessRequest(uid, apps, pending);
                        },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Send Request', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _chatBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sendingRequest
                      ? null
                      : () => setState(() => _showRequestComposer = false),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _chatBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messageBar(String uid) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _chatLine)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!widget.isParent)
              IconButton(
                tooltip: 'Request app access',
                onPressed: () => setState(
                  () => _showRequestComposer = !_showRequestComposer,
                ),
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: _chatBlue,
              ),
            Expanded(
              child: TextField(
                controller: _message,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Type a message...',
                  hintStyle: const TextStyle(fontSize: 13),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF6F8FC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _chatLine),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _chatBlue),
                  ),
                ),
                onSubmitted: (_) => _sendText(uid),
              ),
            ),
            const SizedBox(width: 7),
            SizedBox(
              width: 41,
              height: 41,
              child: IconButton.filled(
                onPressed: _sendingMessage ? null : () => _sendText(uid),
                icon: const Icon(Icons.send_rounded, size: 19),
                style: IconButton.styleFrom(backgroundColor: _chatBlue),
                tooltip: 'Send message',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatError(String heading, Object error) {
    final details = error.toString();
    final denied = details.contains('permission-denied');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 39, color: _chatBlue),
            const SizedBox(height: 10),
            Text(
              heading,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'Firebase denied access to the chat collection. '
                    'Your paired parent/child Firestore chat rules must be '
                    'published before messages and requests can load.'
                  : details,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatBody(Map<String, dynamic> profile, String uid) {
    final parentId = (profile['parentId'] ?? '').toString();
    final childId = (profile['childAccountId'] ?? '').toString();
    if (parentId.isEmpty || childId.isEmpty) {
      return const Center(child: Text('Pair a child device to start chatting.'));
    }
    if ((widget.isParent && uid != parentId) ||
        (!widget.isParent && uid != childId)) {
      return const Center(child: Text('Only paired family members can use this chat.'));
    }

    final messages = _profile.collection('chat_messages')
        .orderBy('createdAt').limit(200).snapshots();
    final requests = _profile.collection('access_requests')
        .orderBy('createdAt').limit(100).snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: messages,
      builder: (context, messageSnapshot) {
        if (messageSnapshot.hasError) {
          return _chatError('Unable to load chat', messageSnapshot.error!);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: requests,
          builder: (context, requestSnapshot) {
            if (requestSnapshot.hasError) {
              return _chatError('Unable to load requests', requestSnapshot.error!);
            }
            final reqDocs = requestSnapshot.data?.docs ?? [];
            final serverPending = reqDocs.where((doc) {
              final data = doc.data();
              final status = data['status'];
              if (status == 'active' && data['expiresAt'] is Timestamp &&
                  !(data['expiresAt'] as Timestamp)
                      .toDate().isAfter(DateTime.now())) {
                return false;
              }
              return ['pending', 'approved_pending_activation', 'active']
                  .contains(status);
            }).map((doc) => (doc.data()['packageName'] ?? '').toString()).toSet();

            // A resolved server request permits a later, new request.
            _locallyRequestedPackages.removeWhere((packageName) =>
                !serverPending.contains(packageName) &&
                reqDocs.any((doc) => doc.data()['packageName'] == packageName));
            final pending = <String>{
              ...serverPending,
              ..._locallyRequestedPackages,
            };

            final timeline = <Map<String, dynamic>>[];
            for (final doc in messageSnapshot.data?.docs ?? []) {
              timeline.add({'kind': 'message', 'id': doc.id, ...doc.data()});
            }
            for (final doc in reqDocs) {
              timeline.add({'kind': 'request', 'id': doc.id, ...doc.data()});
            }
            DateTime when(Map<String, dynamic> item) {
              final raw = item['createdAt'];
              return raw is Timestamp ? raw.toDate() : DateTime.now();
            }
            timeline.sort((a, b) => when(a).compareTo(when(b)));

            return Column(
              children: [
                Expanded(
                  child: timeline.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 40,
                                color: _chatBlue,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Start a conversation with your '
                                '${widget.isParent ? 'child' : 'parent'}.',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          // Latest messages stay next to the message composer.
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 12,
                          ),
                          itemCount: timeline.length,
                          itemBuilder: (context, index) {
                            final item = timeline[timeline.length - index - 1];
                            return item['kind'] == 'request'
                                ? _requestCard(
                                    item,
                                    item['id'] as String,
                                    profile,
                                  )
                                : _messageBubble(item, uid);
                          },
                        ),
                ),
                if (!widget.isParent)
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('app_rules').doc(parentId).snapshots(),
                    builder: (context, rulesSnapshot) {
                      final raw = rulesSnapshot.data?.data()?['rules'];
                      final apps = <Map<String, String>>[];
                      if (raw is List) {
                        for (final item in raw) {
                          if (item is Map &&
                              item['restrictEnabled'] == true &&
                              item['packageName'] is String) {
                            apps.add({
                              'packageName': item['packageName'] as String,
                              'appName': (item['appName'] ??
                                  item['packageName']).toString(),
                            });
                          }
                        }
                      }
                      return _showRequestComposer
                          ? _requestComposer(uid, apps, pending)
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 13),
                                child: TextButton.icon(
                                  onPressed: _sendingRequest
                                      ? null
                                      : () => setState(
                                          () => _showRequestComposer = true),
                                  icon: const Icon(
                                    Icons.lock_open_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Request app access'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _chatBlue,
                                  ),
                                ),
                              ),
                            );
                    },
                  ),
                    ),
                  ),
                _messageBar(uid),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.childProfileId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Sign in and pair a device first.')),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: AppBar(
        toolbarHeight: 74,
        backgroundColor: _chatBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleSpacing: 0,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_chatBlue, _chatDarkBlue],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _profile.snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? <String, dynamic>{};
            String name;
            if (widget.isParent) {
              name = (data['childDisplayName'] ?? data['name'] ??
                  data['childEmail'] ?? 'Child').toString().trim();
            } else {
              name = (data['parentDisplayName'] ?? data['parentName'] ??
                  data['parentEmail'] ?? 'Parent').toString().trim();
            }
            if (name.isEmpty) name = widget.isParent ? 'Child' : 'Parent';
            return Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFFD7E9FF),
                  child: Icon(Icons.person_rounded,
                    color: _chatDarkBlue, size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white,
                          fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      const Text('Private family conversation',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _chatError('Chat unavailable', snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data?.data();
          if (profile == null) {
            return const Center(child: Text('Pair your devices to start chatting.'));
          }
          return _chatBody(profile, uid);
        },
      ),
    );
  }
}
