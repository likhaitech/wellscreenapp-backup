import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';

class GeneratedPairingCode {
  final String code;
  final String childProfileId;
  final DateTime expiresAt;

  const GeneratedPairingCode({
    required this.code,
    required this.childProfileId,
    required this.expiresAt,
  });

  factory GeneratedPairingCode.fromJson(Map<String, dynamic> json) {
    return GeneratedPairingCode(
      code: json['code'] as String,
      childProfileId: json['childProfileId'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
    );
  }
}

class PairingConnection {
  final String parentId;
  final String childProfileId;

  const PairingConnection({
    required this.parentId,
    required this.childProfileId,
  });

  factory PairingConnection.fromJson(Map<String, dynamic> json) {
    return PairingConnection(
      parentId: json['parentId'] as String,
      childProfileId: json['childProfileId'] as String,
    );
  }
}

class PairingApiService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.backendBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 90),
      contentType: Headers.jsonContentType,
    ),
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('Please log in again.');
    }

    final token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw Exception('Unable to verify your account.');
    }

    try {
      final response = await _dio.post(
        path,
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final body = response.data;

      if (body is! Map) {
        throw Exception('Invalid pairing server response.');
      }

      return Map<String, dynamic>.from(body);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final data = error.response?.data;

      if (status == 404) {
        throw Exception(
          'Pairing API not available. '
          'Please contact the administrator.',
        );
      }

      if (status == 401) {
        throw Exception('Please log in again.');
      }

      if (status != null &&
          status >= 400 &&
          status < 500 &&
          data is Map &&
          data['detail'] is String) {
        throw Exception(data['detail']);
      }

      if (status == 429) {
        throw Exception('Too many pairing attempts. Please try again later.');
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw Exception(
          'The server is taking too long to respond. '
          'Please try again.',
        );
      }

      throw Exception(
        'Unable to connect to the pairing server. '
        'Please try again.',
      );
    }
  }

  Future<GeneratedPairingCode> generateCode({required String childName}) async {
    final result = await _post('/pairing/code', {
      'childName': childName.trim(),
    });

    return GeneratedPairingCode.fromJson(result);
  }

  Future<PairingConnection> redeemCode({required String code}) async {
    final result = await _post('/pairing/redeem', {'code': code.trim()});

    return PairingConnection.fromJson(result);
  }

  Future<void> unpairDevice({required String childProfileId}) async {
    final result = await _post('/pairing/unpair', {
      'childProfileId': childProfileId,
    });

    if (result['status'] != 'unpaired') {
      throw Exception('Unable to remove the child device.');
    }
  }
}
