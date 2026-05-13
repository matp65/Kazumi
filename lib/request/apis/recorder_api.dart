import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/utils/logger.dart';
import 'package:kazumi/utils/storage.dart';
import 'package:hive_ce/hive.dart';

class RecorderApi {
  static final Dio _dio = DioFactory.apiDio;

  static Box get _setting => GStorage.setting;

  static String get _baseUrl {
    final url = _setting
        .get(SettingBoxKey.recorderApiUrl,
            defaultValue: 'http://127.0.0.1:8080')
        .toString()
        .trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static String get _token {
    return _setting
        .get(SettingBoxKey.recorderApiToken, defaultValue: '')
        .toString()
        .trim();
  }

  static bool get _enabled {
    return _setting
        .get(SettingBoxKey.recorderSyncEnable, defaultValue: false);
  }

  static bool get isConfigured => _enabled && _token.isNotEmpty && _baseUrl.isNotEmpty;

  static Future<RecorderGetResponse?> getRecording(int bangumiId) async {
    if (!isConfigured) return null;
    try {
      final response = await _dio.post(
        '$_baseUrl/api/v1/open/get',
        queryParameters: {
          'token': _token,
          'bangumi_id': bangumiId,
        },
      );
      final data = response.data as Map<String, dynamic>;
      if (data['status'] == 0) {
        return RecorderGetResponse.fromJson(data);
      }
    } on DioException catch (e) {
      KazumiLogger().w('RecorderApi: get recording failed', error: e);
    }
    return null;
  }

  static Future<bool> addRecording(int bangumiId, int userStatus) async {
    if (!isConfigured) return false;
    try {
      final response = await _dio.post(
        '$_baseUrl/api/v1/open/new',
        queryParameters: {
          'token': _token,
          'bangumi_id': bangumiId,
          'user_status': userStatus,
        },
      );
      final data = response.data as Map<String, dynamic>;
      if (data['status'] == 0) {
        return true;
      }
      if (data['status'] == -3) {
        // Already exists, try update instead
        return await updateRecording(bangumiId, userStatus);
      }
    } on DioException catch (e) {
      KazumiLogger().w('RecorderApi: add recording failed', error: e);
    }
    return false;
  }

  static Future<bool> updateRecording(int bangumiId, int userStatus) async {
    if (!isConfigured) return false;
    try {
      // Update status via new endpoint with user_status
      final response = await _dio.post(
        '$_baseUrl/api/v1/open/new',
        queryParameters: {
          'token': _token,
          'bangumi_id': bangumiId,
          'user_status': userStatus,
        },
      );
      final data = response.data as Map<String, dynamic>;
      if (data['status'] == 0) {
        return true;
      }
      // status -3 means already exists, which is fine for an "update"
      if (data['status'] == -3) {
        return true;
      }
    } on DioException catch (e) {
      KazumiLogger().w('RecorderApi: update recording failed', error: e);
    }
    return false;
  }

  static Future<bool> updateProgress(int bangumiId, String recorder) async {
    if (!isConfigured) return false;
    try {
      final response = await _dio.post(
        '$_baseUrl/api/v1/open/update',
        queryParameters: {
          'token': _token,
          'bangumi_id': bangumiId,
          'recorder': recorder,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return data['status'] == 0;
    } on DioException catch (e) {
      KazumiLogger().w('RecorderApi: update progress failed', error: e);
    }
    return false;
  }

  static Future<List<RecorderItem>> listRecordings() async {
    if (!isConfigured) return [];
    try {
      final response = await _dio.get(
        '$_baseUrl/api/v1/open/list',
        queryParameters: {
          'token': _token,
        },
      );
      final data = response.data as Map<String, dynamic>;
      if (data['status'] == 0 && data['data'] != null) {
        final list = data['data'] as List<dynamic>;
        return list
            .map((e) => RecorderItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } on DioException catch (e) {
      KazumiLogger().w('RecorderApi: list recordings failed', error: e);
    }
    return [];
  }

  static Future<bool> ping() async {
    if (!isConfigured) return false;
    try {
      final response = await _dio.get(
        '$_baseUrl/api/v1/open/list',
        queryParameters: {
          'token': _token,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return data['status'] == 0;
    } on DioException catch (e) {
      KazumiLogger().w('RecorderApi: ping failed', error: e);
      return false;
    }
  }

  static int collectTypeToUserStatus(int collectType) {
    // CollectType.watching(1) → user_status 1 (recording)
    // CollectType.planToWatch(2) → user_status 0 (pending)
    // CollectType.onHold(3) → user_status 0 (pending)
    // CollectType.watched(4) → user_status 2 (completed)
    // CollectType.abandoned(5) → user_status 3 (failed)
    switch (collectType) {
      case 1:
        return 1;
      case 4:
        return 2;
      case 5:
        return 3;
      default:
        return 0;
    }
  }
}

class RecorderGetResponse {
  final int status;
  final int? localBangumiId;
  final int? bangumiId;
  final String? recorder;
  final String? date;

  RecorderGetResponse({
    required this.status,
    this.localBangumiId,
    this.bangumiId,
    this.recorder,
    this.date,
  });

  factory RecorderGetResponse.fromJson(Map<String, dynamic> json) {
    return RecorderGetResponse(
      status: json['status'] as int,
      localBangumiId: json['local_bangumi_id'] as int?,
      bangumiId: json['bangumi_id'] as int?,
      recorder: json['recorder'] as String?,
      date: json['date'] as String?,
    );
  }
}

class RecorderItem {
  final int id;
  final int localBangumiId;
  final String? bangumiId;
  final String? recorder;
  final String? date;

  RecorderItem({
    required this.id,
    required this.localBangumiId,
    this.bangumiId,
    this.recorder,
    this.date,
  });

  factory RecorderItem.fromJson(Map<String, dynamic> json) {
    return RecorderItem(
      id: json['id'] as int,
      localBangumiId: json['local_bangumi_id'] as int,
      bangumiId: json['bangumi_id']?.toString(),
      recorder: json['recorder'] as String?,
      date: json['date'] as String?,
    );
  }
}
