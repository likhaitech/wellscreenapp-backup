import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/pairing_api_service.dart';

import '../theme/app_theme.dart';
import 'login_screen.dart';

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  static const Color purple = AppColors.primary;
  static const Color deepPurple = AppColors.primaryDark;
  static const Color teal = AppColors.accent;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;
  static const Color softPurple = AppColors.primaryLight;
  static const Color softGreen = AppColors.successBg;
  static const Color softOrange = AppColors.warningBg;

  final childNameController = TextEditingController();

  // Detect new successful pairings while the parent is on this screen.
  // The initial server snapshot establishes a baseline, so existing
  // connected devices do not trigger a confirmation on every visit.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _connectionSubscription;
  Map<String, bool> _previousConnectionStates = {};
  bool _hasInitialConnectionSnapshot = false;
  bool _isSyncingParentDetails = false;

  @override
  void initState() {
    super.initState();
    final parentUser = FirebaseAuth.instance.currentUser;
    if (parentUser == null) return;

    // Backfill parent details for devices paired before this feature existed.
    // Only the owning parent writes these identity fields.
    unawaited(_syncPublicParentDetailsToChildren(parentUser));

    _connectionSubscription = FirebaseFirestore.instance
        .collection('child_profiles')
        .where('parentId', isEqualTo: parentUser.uid)
        .snapshots(includeMetadataChanges: true)
        .listen(_onChildProfilesUpdated, onError: (Object _) {});
  }

  /// Details deliberately copied only into the parent's own child profiles.
  /// The child does not need read permission for the parent's users document.
  Future<Map<String, String>> _parentIdentityFields(User parentUser) async {
    var name = (parentUser.displayName ?? '').trim();
    var email = (parentUser.email ?? '').trim();

    try {
      final parentDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentUser.uid)
          .get();
      final profile = parentDoc.data() ?? <String, dynamic>{};
      final profileName =
          (profile['fullName'] ??
                  profile['displayName'] ??
                  profile['name'] ??
                  '')
              .toString()
              .trim();
      final profileEmail = (profile['email'] ?? '').toString().trim();
      if (profileName.isNotEmpty) name = profileName;
      if (email.isEmpty && profileEmail.isNotEmpty) email = profileEmail;
    } catch (error) {
      debugPrint('Could not read parent display details: $error');
    }

    return {
      if (name.isNotEmpty) 'parentDisplayName': name,
      if (email.isNotEmpty) 'parentEmail': email,
    };
  }

  /// Backfills existing child profiles without generating new pairing codes.
  /// Manual retries give visible feedback instead of swallowing failures.
  Future<void> _syncPublicParentDetailsToChildren(
    User parentUser, {
    bool showFeedback = false,
  }) async {
    if (_isSyncingParentDetails) return;
    _isSyncingParentDetails = true;
    if (mounted) setState(() {});
    try {
      final details = await _parentIdentityFields(parentUser);
      if ((details['parentDisplayName'] ?? '').trim().isEmpty ||
          (details['parentEmail'] ?? '').trim().isEmpty) {
        throw StateError(
          'Set your full name and email in the parent account profile first.',
        );
      }
      final profiles = await FirebaseFirestore.instance
          .collection('child_profiles')
          .where('parentId', isEqualTo: parentUser.uid)
          .get(const GetOptions(source: Source.server));
      var updated = 0;
      for (final profile in profiles.docs) {
        final oldData = profile.data();
        if (details.entries.any((field) => oldData[field.key] != field.value)) {
          await profile.reference
              .set(details, SetOptions(merge: true))
              .timeout(const Duration(seconds: 12));
          updated++;
        }
      }
      if (showFeedback && mounted) {
        showMessage(
          'Parent details synced. $updated child profile(s) updated.',
        );
      }
    } catch (error) {
      debugPrint('Could not sync linked parent identity: $error');
      if (showFeedback && mounted) {
        showMessage('Parent details sync failed: $error');
      }
    } finally {
      _isSyncingParentDetails = false;
      if (mounted) setState(() {});
    }
  }

  void _onChildProfilesUpdated(QuerySnapshot<Map<String, dynamic>> snapshot) {
    // Cached snapshots may be stale; only use server-confirmed states to
    // decide that a device has actually completed pairing.
    if (!mounted || snapshot.metadata.isFromCache) return;

    final currentStates = <String, bool>{
      for (final doc in snapshot.docs)
        doc.id: doc.data()['pairingStatus'] == 'connected',
    };

    if (!_hasInitialConnectionSnapshot) {
      _previousConnectionStates = currentStates;
      _hasInitialConnectionSnapshot = true;
      return;
    }

    final newlyConnected = snapshot.docs.where(
      (doc) =>
          _previousConnectionStates[doc.id] == false &&
          currentStates[doc.id] == true,
    );

    final childNames = newlyConnected
        .map((doc) => (doc.data()['name'] ?? 'Child').toString())
        .toList();

    // Update before showing dialogs to prevent duplicate confirmations on
    // Firestore metadata changes or widget rebuilds.
    _previousConnectionStates = currentStates;

    for (final childName in childNames) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        _showPairingSuccessDialog(childName);
      });
    }
  }

  void _showPairingSuccessDialog(String childName) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: const Text(
          'Device Connected Successfully!',
          textAlign: TextAlign.center,
          style: TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 42,
              backgroundColor: softGreen,
              child: Icon(Icons.verified_rounded, color: teal, size: 55),
            ),
            const SizedBox(height: 16),
            Text(
              '$childName\'s device has been successfully connected to your account.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: grayText,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(
              backgroundColor: purple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  bool isGenerating = false;
  String generatedCode = '';
  String generatedChildName = '';
  String generatedChildProfileId = '';
  DateTime? generatedExpiry;
  final Set<String> _removingProfileIds = {};

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    childNameController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> childProfilesStream(String uid) {
    return FirebaseFirestore.instance
        .collection('child_profiles')
        .where('parentId', isEqualTo: uid)
        .snapshots();
  }

  Future<void> generatePairingCode() async {
    if (isGenerating) return;

    final parentUser = FirebaseAuth.instance.currentUser;

    if (parentUser == null) {
      showMessage('Please log in again.');
      return;
    }

    final childName = childNameController.text.trim();

    if (childName.isEmpty) {
      showMessage('Enter the child name first.');
      return;
    }

    setState(() => isGenerating = true);

    try {
      final result = await PairingApiService().generateCode(
        childName: childName,
      );

      if (!mounted) return;

      setState(() {
        generatedCode = result.code;
        generatedChildName = childName;
        generatedChildProfileId = result.childProfileId;
        generatedExpiry = result.expiresAt;
      });

      childNameController.clear();
      showMessage('Pairing code generated.');
    } catch (e) {
      if (!mounted) return;
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isGenerating = false);
      }
    }
  }

  Future<void> removeChildDevice({
    required String childProfileId,
    required String childName,
  }) async {
    if (_removingProfileIds.contains(childProfileId)) return;

    setState(() {
      _removingProfileIds.add(childProfileId);
    });

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Remove Child Device?',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Are you sure you want to remove $childName?\n\n'
            'You will no longer be able to monitor or control '
            'this device until it is paired again.\n\n'
            'The child account will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove Device'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      await PairingApiService().unpairDevice(childProfileId: childProfileId);

      if (!mounted) return;

      setState(() {
        if (generatedChildProfileId == childProfileId) {
          generatedCode = '';
          generatedChildName = '';
          generatedChildProfileId = '';
          generatedExpiry = null;
        }
      });

      showMessage('$childName has been successfully removed.');
    } catch (error) {
      if (!mounted) return;

      showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _removingProfileIds.remove(childProfileId);
        });
      }
    }
  }

  bool isConnected(Map<String, dynamic> data) {
    final pairingStatus = (data['pairingStatus'] ?? '').toString();
    final childEmail = (data['childEmail'] ?? '').toString();
    final childAccountId = (data['childAccountId'] ?? '').toString();

    return pairingStatus == 'connected' ||
        childEmail.isNotEmpty ||
        childAccountId.isNotEmpty;
  }

  String formatDate(DateTime? date) {
    if (date == null) return 'Not available';

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$month/$day/$year $hour:$minute';
  }

  String formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      return formatDate(value.toDate());
    }

    return 'Not available';
  }

  void copyCode() {
    if (generatedCode.isEmpty) return;

    Clipboard.setData(ClipboardData(text: generatedCode));
    showMessage('Pairing code copied.');
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final parentUser = FirebaseAuth.instance.currentUser;

    if (parentUser == null) {
      return Scaffold(
        backgroundColor: pageBg,
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Return to Login'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'Device Pairing',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: pageBg,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: childProfilesStream(parentUser.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppErrorState(
                  title: 'Could Not Load Devices',
                  message:
                      'Something went wrong loading paired '
                      'devices.\n\n${snapshot.error}',
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final childDocs = (snapshot.data?.docs ?? [])
              .where((doc) => doc.data()['pairingStatus'] != 'unpaired')
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              _headerCard(),
              const SizedBox(height: 18),
              _generateCodeCard(),
              if (generatedCode.isNotEmpty) const SizedBox(height: 18),
              if (generatedCode.isNotEmpty) _generatedCodeCard(),
              const SizedBox(height: 22),
              _childrenSection(childDocs),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [purple, deepPurple],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          _logoBox(),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Pair Child Device',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Icon(Icons.link_rounded, color: Colors.white, size: 34),
        ],
      ),
    );
  }

  Widget _logoBox() {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(31),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31),
        child: Image.asset(
          'assets/icons/wellscreen_icon.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _generateCodeCard() {
    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Pairing Code',
            style: TextStyle(
              color: darkText,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the child name and generate a 6-digit code. The child will enter this code on their device.',
            style: TextStyle(
              color: grayText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: childNameController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Child Name',
              prefixIcon: const Icon(Icons.child_care_rounded, color: purple),
              filled: true,
              fillColor: pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: purple, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isGenerating ? null : generatePairingCode,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: Text(
                isGenerating ? 'Generating...' : 'Generate Pairing Code',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _generatedCodeCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: softPurple,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x222557A7)),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white,
            child: Icon(Icons.verified_rounded, color: teal, size: 46),
          ),
          const SizedBox(height: 14),
          const Text(
            'Pairing Code Ready',
            style: TextStyle(
              color: darkText,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            generatedChildName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: grayText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              generatedCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: purple,
                fontSize: 38,
                letterSpacing: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Same code as above, just scannable - the child can either
          // type the 6 digits or point their camera at this on the child
          // app's pairing screen (see qr_scan_screen.dart). Encodes the
          // plain code only, nothing else, so it carries no more trust
          // than the digits do: whoever holds pairing_codes/{code} in
          // Firestore is still what actually grants the pairing, not
          // possession of the image.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                QrImageView(
                  data: generatedCode,
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: purple,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: purple,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Or let the child scan this QR code',
                  style: TextStyle(
                    color: grayText,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Expires: ${formatDate(generatedExpiry)}',
            style: const TextStyle(
              color: grayText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: copyCode,
              style: OutlinedButton.styleFrom(
                foregroundColor: purple,
                side: const BorderSide(color: purple, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.copy_rounded),
              label: const Text(
                'Copy Code',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _childrenSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> childDocs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Child Devices',
          style: TextStyle(
            color: darkText,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        if (childDocs.isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSyncingParentDetails
                  ? null
                  : () {
                      final parentUser = FirebaseAuth.instance.currentUser;
                      if (parentUser != null) {
                        unawaited(
                          _syncPublicParentDetailsToChildren(
                            parentUser,
                            showFeedback: true,
                          ),
                        );
                      }
                    },
              icon: _isSyncingParentDetails
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(
                _isSyncingParentDetails
                    ? 'Syncing Parent Details...'
                    : 'Sync Parent Details',
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (childDocs.isEmpty)
          _emptyChildrenCard()
        else
          ...childDocs.map((doc) => _childDeviceCard(doc.id, doc.data())),
      ],
    );
  }

  Widget _emptyChildrenCard() {
    return _whiteCard(
      child: const Column(
        children: [
          Icon(Icons.phone_android_rounded, color: purple, size: 58),
          SizedBox(height: 12),
          Text(
            'No child device yet',
            style: TextStyle(
              color: darkText,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Generate a pairing code to connect a child account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: grayText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _childDeviceCard(String childProfileId, Map<String, dynamic> data) {
    final name = (data['name'] ?? 'Child Device').toString();
    final email = (data['childEmail'] ?? 'Not connected yet').toString();
    final connected = isConnected(data);
    final connectedAt = formatTimestamp(data['connectedAt']);
    final isRemoving = _removingProfileIds.contains(childProfileId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 29,
                backgroundColor: connected ? softGreen : softOrange,
                child: Icon(
                  connected
                      ? Icons.phone_android_rounded
                      : Icons.link_off_rounded,
                  color: connected ? teal : Colors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: darkText,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      connected ? email : 'Waiting for child pairing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: grayText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      connected ? 'Connected: $connectedAt' : 'Status: Waiting',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: grayText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: connected ? softGreen : softOrange,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  connected ? 'Online' : 'Waiting',
                  style: TextStyle(
                    color: connected ? teal : Colors.orange,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: isRemoving
                  ? null
                  : () => removeChildDevice(
                      childProfileId: childProfileId,
                      childName: name,
                    ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: isRemoving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_off_rounded),
              label: Text(isRemoving ? 'Removing Device...' : 'Remove Device'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _whiteCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}
