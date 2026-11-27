import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';

/// One user account as shown on the admin "Manage Users" screen.
class AdminManagedUser {
  const AdminManagedUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.disabled,
    this.createdAt,
    this.lastSignInAt,
    this.emailVerified = false,
    this.paired,
  });

  final String uid;
  final String email;
  final String displayName;

  /// 'admin', 'parent', 'child' or 'user' (unknown).
  final String role;
  final bool disabled;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final bool emailVerified;

  /// Guardian or child account linked to the other side. Null for admins
  /// or when the pairing could not be read.
  final bool? paired;

  AdminManagedUser copyWith({
    String? email,
    String? displayName,
    bool? disabled,
  }) {
    return AdminManagedUser(
      uid: uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role,
      disabled: disabled ?? this.disabled,
      createdAt: createdAt,
      lastSignInAt: lastSignInAt,
      emailVerified: emailVerified,
      paired: paired,
    );
  }
}

/// Account-level pairing from the users documents: a child account is
/// paired when it is connected to a guardian; a guardian is paired when
/// any child account points to them. Only these fields are read.
Map<String, bool> adminPairingFromUserDocs(
  Map<String, Map<String, dynamic>> docs,
) {
  bool hasText(Object? v) => v is String && v.trim().isNotEmpty;
  final guardiansWithChild = <String>{};
  final result = <String, bool>{};
  docs.forEach((uid, data) {
    final role = (data['role'] ?? '').toString().toLowerCase();
    if (role == 'child' || role == 'student') {
      final parent = data['pairedParentId'];
      final paired =
          data['pairingStatus'] == 'connected' || hasText(parent);
      result[uid] = paired;
      if (hasText(parent)) guardiansWithChild.add((parent as String).trim());
    }
  });
  docs.forEach((uid, data) {
    final role = (data['role'] ?? '').toString().toLowerCase();
    if (role == 'parent') {
      result[uid] = guardiansWithChild.contains(uid) ||
          data['pairingStatus'] == 'connected';
    }
  });
  return result;
}

/// Talks to the backend's /admin/users routes (Retrieve, Update, Deactivate,
/// Delete user records - manuscript "Manage Users" use case). The Firestore
/// `users/{uid}.role` value (parent / child) is merged in only for display,
/// because the backend's own role claim only knows "user" and "admin".
class AdminUsersApiService {
  AdminUsersApiService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.backendBaseUrl,
              // Render's free tier can take up to a minute to wake up.
              connectTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );

  final Dio _dio;

  Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated user.');
    }
    final result = await user.getIdTokenResult(true);
    final token = result.token;
    if (token == null || token.isEmpty) {
      throw Exception('Unable to get Firebase ID token.');
    }
    return token;
  }

  Future<Options> _options() async {
    final token = await _token();
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// Turns a Dio error into a readable message (uses the backend's "detail").
  String errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'The server is taking too long. It may be waking up - try again in a moment.';
      }
      if (error.response != null) {
        return 'Request failed (${error.response?.statusCode}).';
      }
      return 'Could not reach the server.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  DateTime? _fromMillis(dynamic value) {
    if (value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  /// Firestore users documents (role and pairing fields), for display only.
  Future<Map<String, Map<String, dynamic>>> _firestoreUsers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      return {for (final doc in snapshot.docs) doc.id: doc.data()};
    } catch (_) {
      // Display only - fall back to the backend role if this read fails.
      return <String, Map<String, dynamic>>{};
    }
  }

  Future<List<AdminManagedUser>> listUsers() async {
    final options = await _options();
    final response = await _dio.get('/admin/users/', options: options);
    final data = response.data;
    final rawUsers = (data is Map && data['users'] is List)
        ? data['users'] as List
        : <dynamic>[];
    final firestoreUsers = await _firestoreUsers();
    final pairing = adminPairingFromUserDocs(firestoreUsers);

    final users = <AdminManagedUser>[];
    for (final item in rawUsers) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final uid = (map['uid'] ?? '').toString();
      final backendRole = (map['role'] ?? 'user').toString().toLowerCase();
      var role = backendRole;
      if (backendRole != 'admin') {
        final stored =
            (firestoreUsers[uid]?['role'] ?? '').toString().toLowerCase();
        role = stored.isNotEmpty ? stored : backendRole;
        if (role == 'student') role = 'child';
      }
      users.add(
        AdminManagedUser(
          uid: uid,
          email: (map['email'] ?? '').toString(),
          displayName: (map['display_name'] ?? '').toString(),
          role: role,
          disabled: map['disabled'] == true,
          createdAt: _fromMillis(map['created_at']),
          lastSignInAt: _fromMillis(map['last_sign_in_at']),
          emailVerified: map['email_verified'] == true,
          paired: role == 'admin' ? null : pairing[uid],
        ),
      );
    }

    users.sort(
      (a, b) => a.email.toLowerCase().compareTo(b.email.toLowerCase()),
    );
    return users;
  }

  Future<void> updateUser(
    String uid, {
    String? displayName,
    String? email,
    String? password,
    bool? disabled,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (email != null) body['email'] = email;
    if (password != null) body['password'] = password;
    if (disabled != null) body['disabled'] = disabled;

    final options = await _options();
    await _dio.patch('/admin/users/$uid', data: body, options: options);
  }

  Future<void> deleteUser(String uid) async {
    final options = await _options();
    await _dio.delete('/admin/users/$uid', options: options);
  }
}
