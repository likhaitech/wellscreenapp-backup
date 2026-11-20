import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/grant_countdown_notifier.dart';
import '../theme/app_theme.dart';

/// "14:05 left" that ticks every second until [until].
class TimeLeftText extends StatefulWidget {
  const TimeLeftText({super.key, required this.until, this.style});

  final DateTime until;
  final TextStyle? style;

  @override
  State<TimeLeftText> createState() => _TimeLeftTextState();
}

class _TimeLeftTextState extends State<TimeLeftText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!widget.until.isAfter(DateTime.now())) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    return Text(
      left.isNegative ? 'Time is up' : '${formatTimeLeft(left)} left',
      style: widget.style,
    );
  }
}

/// Child Home: one row per app the parent gave extra time, with a live
/// countdown. Hidden when no grant is running.
class ActiveAppGrantsCard extends StatelessWidget {
  const ActiveAppGrantsCard({super.key, required this.childProfileId});

  final String childProfileId;

  @override
  Widget build(BuildContext context) {
    if (childProfileId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('child_profiles')
          .doc(childProfileId)
          .collection('temporary_access_grants')
          .where('state', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final rows = <(String, DateTime)>[];
        for (final doc in snapshot.data?.docs ?? const []) {
          final data = doc.data();
          final until = data['expiresAt'];
          if (until is! Timestamp) continue;
          final end = until.toDate();
          if (!end.isAfter(now)) continue;
          rows.add(((data['appName'] ?? data['packageName'] ?? 'App')
              .toString(), end));
        }
        if (rows.isEmpty) return const SizedBox.shrink();
        rows.sort((a, b) => a.$2.compareTo(b.$2));
        return Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Extra time approved',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          row.$1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      TimeLeftText(
                        until: row.$2,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
