import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/chat_notifications_service.dart';
import '../services/chat_unread_service.dart';
import '../services/emergency_access_service.dart';
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
  bool _sendingEmergency = false;
  bool _showRequestComposer = false;
  String? _selectedPackage;
  int _requestedMinutes = 60;
  final Set<String> _locallyRequestedPackages = <String>{};
  String? _decidingRequest;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _inboxReadSubscription;

  static const Color _chatBlue = AppColors.messenger;
  static const Color _chatDarkBlue = AppColors.primaryDark;
  static const Color _softBlue = AppColors.surfaceMuted;
  static const Color _chatLine = AppColors.border;

  DocumentReference<Map<String, dynamic>> get _profile => FirebaseFirestore
      .instance
      .collection('child_profiles')
      .doc(widget.childProfileId);

  @override
  void initState() {
    super.initState();
    // A conversation view acknowledges its own unread notification history.
    // Firestore queues this change while offline and synchronizes on return.
    unawaited(
      ChatNotificationsService.instance.markProfileRead(widget.childProfileId),
    );
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Clears the Chat tab's unread dot (see ChatUnreadService).
    if (uid != null) {
      unawaited(ChatUnreadService.markSeen(widget.childProfileId, uid));
    }
    if (uid != null) {
      _inboxReadSubscription = ChatNotificationsService.instance
          .inboxFor(uid)
          .where('childProfileId', isEqualTo: widget.childProfileId)
          .snapshots()
          .listen((snapshot) {
            if (!snapshot.metadata.hasPendingWrites &&
                snapshot.docs.any((doc) => doc.data()['readAt'] == null)) {
              unawaited(
                ChatNotificationsService.instance.markProfileRead(
                  widget.childProfileId,
                ),
              );
            }
          });
    }
  }

  @override
  void dispose() {
    unawaited(_inboxReadSubscription?.cancel());
    // Messages that arrived while the chat was open count as seen.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      unawaited(ChatUnreadService.markSeen(widget.childProfileId, uid));
    }
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
        debugPrint(
          'WellScreen $kind notification dispatch failed: '
          'HTTP=$status attempt=$attempt '
          'detail=${error.response?.data ?? error.message}',
        );
        // Only retry transient failures. Auth/pairing/data errors need a fix.
        if (status == 400 || status == 401 || status == 403 || status == 404) {
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
    unawaited(
      doc
          .set({
            'senderId': uid,
            'body': text,
            'createdAt': FieldValue.serverTimestamp(),
            'notificationState': 'pending',
          })
          .then((_) => _dispatchCommittedEvent('message', doc.id))
          .catchError((Object error) {
            _showError(error);
          }),
    );
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

    try {
      // Authenticate the child using Firebase.
      final user = FirebaseAuth.instance.currentUser;

      if (user == null || user.uid != uid) {
        throw StateError('Your session expired. Please sign in again.');
      }

      final token = await user.getIdToken();

      if (token == null || token.isEmpty) {
        throw StateError('Unable to authenticate. Please sign in again.');
      }

      // Generate a Firestore document ID without directly writing to Firestore.
      // The trusted backend will create the actual request document.
      final requestId = _profile.collection('access_requests').doc().id;

      // Submit the request through FastAPI.
      await Dio().post<Object?>(
        '${AppConfig.backendBaseUrl}/chat/requests/${widget.childProfileId}/$requestId',
        data: {
          'packageName': packageName,
          'requestedMinutes': _requestedMinutes,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      // Notify the parent after the backend successfully creates the request.
      await _dispatchCommittedEvent('request', requestId);

      if (!mounted) return;

      setState(() {
        _showRequestComposer = false;
        _selectedPackage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'App access request sent. Your guardian will be notified.',
          ),
        ),
      );
    } on DioException catch (error) {
      _locallyRequestedPackages.remove(packageName);

      final responseData = error.response?.data;

      final detail = responseData is Map
          ? responseData['detail']?.toString()
          : responseData?.toString();

      if (error.response?.statusCode == 404) {
        _showError(
          'App access request API not found. '
          'Please deploy the latest FastAPI backend.',
        );
      } else if (error.response?.statusCode == 429) {
        _showError(
          detail ?? 'Request limit reached. Please wait before trying again.',
        );
      } else {
        _showError(
          detail ?? error.message ?? 'Unable to submit app access request.',
        );
      }
    } catch (error) {
      _locallyRequestedPackages.remove(packageName);
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _sendingRequest = false);
      }
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
        data: {'approve': approve, 'approvedMinutes': approve ? minutes : null},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
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

      _showError('Request failed (HTTP ${status ?? 'network error'}): $detail');
    } catch (error) {
      debugPrint('App access decision error: $error');
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _decidingRequest = null);
      }
    }
  }

  /// Guardian "Approve Access" sheet: duration pills, then Approve / Deny.
  Future<void> _openApprovalDialog(String id, int requested) async {
    final options = <int>{5, 15, 30, if (requested > 0) requested}.toList()
      ..sort();
    var minutes = requested > 0 ? requested : 15;

    // Returns the approved minutes, 0 for "Deny", or null when dismissed.
    final decided = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Approve Access',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  requested > 0
                      ? 'Child requested $requested minutes.'
                      : 'Choose how long to allow.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: AppPillButton(
                          label: '${options[i]}m',
                          compact: true,
                          style: options[i] == minutes
                              ? AppPillStyle.brand
                              : AppPillStyle.soft,
                          onPressed: () =>
                              setModalState(() => minutes = options[i]),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  decoration: const InputDecoration(
                    labelText: 'Or type minutes (1-120)',
                    suffixText: 'min',
                    isDense: true,
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (text) {
                    final typed = int.tryParse(text.trim());
                    if (typed != null && typed >= 1 && typed <= 120) {
                      setModalState(() => minutes = typed);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppPillButton(
                        label: 'Approve $minutes min',
                        onPressed: () => Navigator.pop(sheetContext, minutes),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppPillButton(
                        label: 'Deny',
                        style: AppPillStyle.soft,
                        onPressed: () => Navigator.pop(sheetContext, 0),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (decided == null) return;
    if (decided == 0) {
      await _decide(id, approve: false, minutes: 0);
    } else {
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
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
          decoration: BoxDecoration(
            color: own ? _chatBlue : AppColors.surface,
            border: own ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(own ? 20 : 6),
              bottomRight: Radius.circular(own ? 6 : 20),
            ),
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
                    fontSize: 15,
                    height: 1.3,
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
    final app = (request['appName'] ?? request['packageName'] ?? 'App')
        .toString();
    final pkg = (request['packageName'] ?? '').toString();
    final requested = request['requestedMinutes'] is num
        ? (request['requestedMinutes'] as num).toInt()
        : 0;
    final rawStatus = (request['status'] ?? 'pending').toString();
    final endTime = request['expiresAt'];
    final status =
        rawStatus == 'active' &&
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
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.access_time_filled_rounded,
                    size: 17,
                    color: _chatBlue,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Access Request',
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
                    label: app,
                    packageName: pkg,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
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
                          label: const Text(
                            'Approve',
                            style: TextStyle(fontSize: 12),
                          ),
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
                          label: const Text(
                            'Decline',
                            style: TextStyle(fontSize: 12),
                          ),
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

  /// Focus mode, bedtime, breaks and used-up limits block every app, not
  /// one restricted app, so they need Emergency Access (all restrictions
  /// lifted for a while), the same request as the Home card.
  Future<void> _sendEmergencyRequest(String parentId, String reason) async {
    if (_sendingEmergency) return;
    setState(() => _sendingEmergency = true);
    try {
      await EmergencyAccessService().requestAccess(
        childProfileId: widget.childProfileId,
        parentId: parentId,
        reason: reason,
      );
      if (!mounted) return;
      setState(() => _showRequestComposer = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency Access request sent to your guardian.'),
        ),
      );
    } on StateError catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sendingEmergency = false);
    }
  }

  Widget _emergencySection(String parentId) {
    const reasons = <String>['Schoolwork', 'Call Guardian', 'Urgent'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 22),
        const Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.danger),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Focus mode, bedtime or a time limit?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Ask for Emergency Access to lift all restrictions for a while. '
          'Pick a reason:',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final reason in reasons)
              ActionChip(
                label: Text(reason, style: const TextStyle(fontSize: 12)),
                onPressed: _sendingEmergency
                    ? null
                    : () => _sendEmergencyRequest(parentId, reason),
              ),
          ],
        ),
      ],
    );
  }

  Widget _requestComposer(
    String uid,
    String parentId,
    List<Map<String, String>> apps,
    Set<String> pending,
  ) {
    final allowedSelection = apps.any(
      (a) => a['packageName'] == _selectedPackage,
    );
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
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 9)],
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
              'No single app is restricted right now.',
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
              key: ValueKey('minutes-$_requestedMinutes'),
              initialValue: _requestedMinutes,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.schedule_rounded, color: _chatBlue),
                labelText: 'Requested duration',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: (<int>{5, 10, 15, 30, 45, 60, 90, 120, _requestedMinutes}
                      .toList()
                    ..sort())
                  .map(
                    (minutes) => DropdownMenuItem<int>(
                      value: minutes,
                      child: Text('$minutes minutes'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _requestedMinutes = value);
              },
            ),
            const SizedBox(height: 9),
            TextField(
              keyboardType: TextInputType.number,
              maxLength: 3,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.edit_rounded, color: _chatBlue),
                labelText: 'Or type minutes (1-120)',
                suffixText: 'min',
                isDense: true,
                counterText: '',
                border: OutlineInputBorder(),
              ),
              onChanged: (text) {
                final typed = int.tryParse(text.trim());
                if (typed != null && typed >= 1 && typed <= 120) {
                  setState(() => _requestedMinutes = typed);
                }
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
                  onPressed:
                      _sendingRequest || apps.isEmpty || selectedIsPending
                      ? null
                      : () {
                          _selectedPackage = selected;
                          _submitAccessRequest(uid, apps, pending);
                        },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text(
                    'Send Request',
                    style: TextStyle(fontSize: 12),
                  ),
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
          _emergencySection(parentId),
        ],
      ),
    );
  }

  Widget _messageBar(String uid) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: const BoxDecoration(color: Colors.white),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!widget.isParent)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 2),
                child: Material(
                  color: AppColors.teal,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Request app access',
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(
                      () => _showRequestComposer = !_showRequestComposer,
                    ),
                    icon: const Icon(
                      Icons.add_rounded,
                      color: AppColors.onTeal,
                      size: 24,
                    ),
                  ),
                ),
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
                  hintText: 'Message...',
                  hintStyle: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendText(uid),
              ),
            ),
            const SizedBox(width: 7),
            SizedBox(
              width: 41,
              height: 41,
              child: IconButton(
                onPressed: _sendingMessage ? null : () => _sendText(uid),
                icon: const Icon(Icons.send_rounded, size: 24),
                color: _chatBlue,
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
                        'Your paired guardian/child Firestore chat rules must be '
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
      return const Center(
        child: Text('Pair a child device to start chatting.'),
      );
    }
    if ((widget.isParent && uid != parentId) ||
        (!widget.isParent && uid != childId)) {
      return const Center(
        child: Text('Only paired family members can use this chat.'),
      );
    }

    final messages = _profile
        .collection('chat_messages')
        .orderBy('createdAt')
        .limit(200)
        .snapshots();
    final requests = _profile
        .collection('access_requests')
        .orderBy('createdAt')
        .limit(100)
        .snapshots();

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
              return _chatError(
                'Unable to load requests',
                requestSnapshot.error!,
              );
            }
            final reqDocs = requestSnapshot.data?.docs ?? [];
            final serverPending = reqDocs
                .where((doc) {
                  final data = doc.data();
                  final status = data['status'];
                  if (status == 'active' &&
                      data['expiresAt'] is Timestamp &&
                      !(data['expiresAt'] as Timestamp).toDate().isAfter(
                        DateTime.now(),
                      )) {
                    return false;
                  }
                  return [
                    'pending',
                    'approved_pending_activation',
                    'active',
                  ].contains(status);
                })
                .map((doc) => (doc.data()['packageName'] ?? '').toString())
                .toSet();

            // A resolved server request permits a later, new request.
            _locallyRequestedPackages.removeWhere(
              (packageName) =>
                  !serverPending.contains(packageName) &&
                  reqDocs.any(
                    (doc) => doc.data()['packageName'] == packageName,
                  ),
            );
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

            // The request form takes only the height it needs (at most half
            // the space) and the message list takes the rest, so the message
            // bar always sits at the bottom. A Flexible here used to reserve
            // half the screen even when the form was hidden.
            return LayoutBuilder(
              builder: (context, constraints) => Column(
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
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.5,
                    ),
                    child: SingleChildScrollView(
                      child:
                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('app_rules')
                                .doc(parentId)
                                .snapshots(),
                            builder: (context, rulesSnapshot) {
                              final raw = rulesSnapshot.data?.data()?['rules'];
                              final apps = <Map<String, String>>[];
                              if (raw is List) {
                                for (final item in raw) {
                                  if (item is Map &&
                                      item['restrictEnabled'] == true &&
                                      item['packageName'] is String) {
                                    apps.add({
                                      'packageName':
                                          item['packageName'] as String,
                                      'appName':
                                          (item['appName'] ??
                                                  item['packageName'])
                                              .toString(),
                                    });
                                  }
                                }
                              }
                              // The + button in the message bar opens the
                              // request form; no separate row above the bar,
                              // which pushed the bar up the screen.
                              return _showRequestComposer
                                  ? _requestComposer(uid, parentId, apps, pending)
                                  : const SizedBox.shrink();
                            },
                          ),
                    ),
                  ),
                _messageBar(uid),
              ],
              ),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleSpacing: 0,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _profile.snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? <String, dynamic>{};
            String name;
            if (widget.isParent) {
              name =
                  (data['childDisplayName'] ??
                          data['name'] ??
                          data['childEmail'] ??
                          'Child')
                      .toString()
                      .trim();
            } else {
              name =
                  (data['parentDisplayName'] ??
                          data['parentName'] ??
                          data['parentEmail'] ??
                          'Guardian')
                      .toString()
                      .trim();
            }
            if (name.isEmpty) name = widget.isParent ? 'Child' : 'Guardian';
            return Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    name
                        .split(RegExp(r'\s+'))
                        .where((part) => part.isNotEmpty)
                        .take(2)
                        .map((part) => part.characters.first.toUpperCase())
                        .join(),
                    style: const TextStyle(
                      fontFamily: AppFonts.heading,
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      const Text('Private family conversation',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
            return const Center(
              child: Text('Pair your devices to start chatting.'),
            );
          }
          return _chatBody(profile, uid);
        },
      ),
    );
  }
}
