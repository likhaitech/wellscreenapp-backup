import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_release_service.dart';
import '../theme/app_theme.dart';

/// Wraps the whole app (MaterialApp.builder). While a guardian or child is
/// signed in it follows the admin's system patch live:
///
/// - app older than the minimum version -> a full-screen "Update
///   WellScreen" page (the phone's blocking keeps running underneath, so a
///   child can't use the old version to get around it);
/// - maintenance notice set -> a slim notice above every screen.
///
/// Admins are never locked out, so they can always undo a patch.
class AppReleaseGate extends StatefulWidget {
  const AppReleaseGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppReleaseGate> createState() => _AppReleaseGateState();
}

class _AppReleaseGateState extends State<AppReleaseGate> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppReleaseStatus>? _releaseSub;

  String? _installed;
  bool _isAdmin = false;
  AppReleaseStatus _status = AppReleaseStatus.none;
  String? _dismissedMessage;

  @override
  void initState() {
    super.initState();
    AppReleaseService.installedVersion().then((v) {
      if (mounted) setState(() => _installed = v);
    }).catchError((Object _) {});
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  Future<void> _onUser(User? user) async {
    await _releaseSub?.cancel();
    _releaseSub = null;
    if (user == null) {
      if (mounted) {
        setState(() {
          _status = AppReleaseStatus.none;
          _isAdmin = false;
        });
      }
      return;
    }
    try {
      final claims = (await user.getIdTokenResult()).claims ?? const {};
      _isAdmin = claims['admin'] == true || claims['role'] == 'admin';
    } catch (_) {
      _isAdmin = false;
    }
    _releaseSub = AppReleaseService.watch().listen(
      (status) {
        if (mounted) setState(() => _status = status);
      },
      onError: (Object error) {
        // Unreadable settings never lock anyone out.
        debugPrint('Could not read system settings: $error');
      },
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _releaseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installed = _installed;
    if (!_isAdmin &&
        installed != null &&
        AppReleaseService.needsUpdate(installed, _status.minimumVersion)) {
      // On top of the app (not instead of it), so screens keep their
      // state and come back as they were once the patch is lifted.
      return Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: _UpdateRequiredPage(
              installed: installed,
              minimum: _status.minimumVersion,
            ),
          ),
        ],
      );
    }

    final message = _status.maintenanceMessage;
    if (message.isEmpty || message == _dismissedMessage) return widget.child;

    return Column(
      children: [
        MaintenanceNoticeBar(
          message: message,
          onHide: () => setState(() => _dismissedMessage = message),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// The slim maintenance notice above every screen.
///
/// It sits in MaterialApp.builder, above the Navigator, so there is no
/// Overlay here: no tooltips or other overlay widgets may be used.
class MaintenanceNoticeBar extends StatelessWidget {
  const MaintenanceNoticeBar({
    super.key,
    required this.message,
    required this.onHide,
  });

  final String message;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              const Icon(
                Icons.campaign_outlined,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Hide notice',
                excludeSemantics: true,
                child: InkResponse(
                  key: const Key('hideMaintenanceNotice'),
                  onTap: onHide,
                  radius: 22,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateRequiredPage extends StatelessWidget {
  const _UpdateRequiredPage({required this.installed, required this.minimum});

  final String installed;
  final String minimum;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icons/wellscreen_icon.png',
                width: 72,
                height: 72,
                semanticLabel: 'WellScreen',
              ),
              const SizedBox(height: 20),
              const Text(
                'Update WellScreen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.heading,
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This version ($installed) has a problem that is fixed in '
                'version $minimum. Install the latest WellScreen to keep '
                'using the app.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Website and app protection keeps working until then.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
