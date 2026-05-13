import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/utils/logger.dart';
import 'package:kazumi/utils/storage.dart';
import 'package:hive_ce/hive.dart';

class RecorderApi {
  Dio get _dio => DioFactory.apiDio;

  Box get _setting => GStorage.setting;

  String get _baseUrl {
    final url = _setting
        .get(SettingBoxKey.recorderApiUrl,
            defaultValue: 'http://127.0.0.1:8080')
        .toString()
        .trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String get _token {
    return _setting
        .get(SettingBoxKey.recorderApiToken, defaultValue: '')
        .toString()
        .trim();
  }

  bool get _enabled {
    return _setting
        .get(SettingBoxKey.recorderSyncEnable, defaultValue: false);
  }

  bool get hasCredentials => _token.isNotEmpty && _baseUrl.isNotEmpty;

  bool get isConfigured => _enabled && hasCredentials;

  void _logRequest(String method, String path, Map<String, dynamic> params) {
    KazumiLogger().i(
      'RecorderApi: $method $path params=$params base=$_baseUrl token=${_token.isNotEmpty ? "***" : "<empty>"}',
      forceLog: true,
    );
  }

  void _logResponse(String method, String path, dynamic data) {
    KazumiLogger().i(
      'RecorderApi: $method $path response=$data',
      forceLog: true,
    );
  }

  void _logError(String method, String path, Object error) {
    KazumiLogger().e(
      'RecorderApi: $method $path FAILED error=$error base=$_baseUrl',
      error: error,
      forceLog: true,
    );
  }

  Future<RecorderGetResponse?> getRecording(int bangumiId) async {
    if (!hasCredentials) {
      KazumiLogger().w('RecorderApi: getRecording skipped (no credentials)', forceLog: true);
      return null;
    }
    const path = '/api/v1/open/get';
    final params = {'token': _token, 'bangumi_id': bangumiId};
    try {
      _logRequest('POST', path, params);
      final response = await _dio.post(
        '$_baseUrl$path',
        queryParameters: params,
      );
      _logResponse('POST', path, response.data);
      final data = response.data as Map<String, dynamic>;
      return RecorderGetResponse.fromJson(data);
    } on DioException catch (e) {
      _logError('POST', path, e);
      return null;
    }
  }

  Future<bool> addRecording(int bangumiId, int userStatus) async {
    if (!hasCredentials) {
      KazumiLogger().w('RecorderApi: addRecording skipped (no credentials)', forceLog: true);
      return false;
    }
    const path = '/api/v1/open/new';
    final params = {
      'token': _token,
      'bangumi_id': bangumiId,
      'user_status': userStatus,
    };
    try {
      _logRequest('POST', path, params);
      final response = await _dio.post(
        '$_baseUrl$path',
        queryParameters: params,
      );
      _logResponse('POST', path, response.data);
      final data = response.data as Map<String, dynamic>;
      if (data['status'] == 0) {
        return true;
      }
      if (data['status'] == -3) {
        // Already exists, but we don't know the collectType here.
        // Just treat as success; status will be synced via full sync.
        KazumiLogger().i('RecorderApi: already exists, treating as success', forceLog: true);
        return true;
      }
      KazumiLogger().w(
        'RecorderApi: addRecording unexpected status=${data['status']}',
        forceLog: true,
      );
      return false;
    } on DioException catch (e) {
      _logError('POST', path, e);
      return false;
    }
  }

  /// Sync collect status using update endpoint (with new user_status mapping)
  Future<bool> syncCollectStatus(int bangumiId, int collectType) async {
    if (!hasCredentials) return false;
    final updateStatus = RecorderApi.collectTypeToUpdateStatus(collectType);
    return updateRecording(bangumiId, userStatus: updateStatus);
  }

  Future<bool> updateRecording(int bangumiId, {int? userStatus, String? recorder}) async {
    if (!hasCredentials) return false;
    const path = '/api/v1/open/update';
    final params = <String, dynamic>{
      'token': _token,
      'bangumi_id': bangumiId,
    };
    if (userStatus != null) params['user_status'] = userStatus;
    if (recorder != null) params['recorder'] = recorder;
    try {
      _logRequest('POST', path, params);
      final response = await _dio.post(
        '$_baseUrl$path',
        queryParameters: params,
      );
      _logResponse('POST', path, response.data);
      final data = response.data as Map<String, dynamic>;
      return data['status'] == 0;
    } on DioException catch (e) {
      _logError('POST', path, e);
      return false;
    }
  }

  Future<bool> updateProgress(int bangumiId, String recorder) async {
    return updateRecording(bangumiId, recorder: recorder);
  }

  Future<List<RecorderItem>> listRecordings() async {
    if (!hasCredentials) return [];
    const path = '/api/v1/open/list';
    final params = {'token': _token};
    try {
      _logRequest('GET', path, params);
      final response = await _dio.get(
        '$_baseUrl$path',
        queryParameters: params,
      );
      _logResponse('GET', path, response.data);
      final data = response.data as Map<String, dynamic>;
      if (data['status'] == 0 && data['data'] != null) {
        final list = data['data'] as List<dynamic>;
        return list
            .map((e) => RecorderItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      KazumiLogger().w(
        'RecorderApi: listRecordings unexpected status=${data['status']}',
        forceLog: true,
      );
    } on DioException catch (e) {
      _logError('GET', path, e);
    }
    return [];
  }

  Future<Map<String, dynamic>> ping() async {
    if (!hasCredentials) {
      return {'success': false, 'error': '未配置 Record API 地址或 Token'};
    }
    const path = '/api/v1/open/list';
    final params = {'token': _token};
    try {
      _logRequest('GET', path, params);
      final response = await _dio.get(
        '$_baseUrl$path',
        queryParameters: params,
      );
      _logResponse('GET', path, response.data);
      final data = response.data as Map<String, dynamic>;
      if (data['status'] == 0) {
        return {'success': true};
      }
      return {
        'success': false,
        'error': '服务器返回错误状态码: ${data['status']}',
        'data': data,
      };
    } on DioException catch (e) {
      _logError('GET', path, e);
      return {
        'success': false,
        'error': '网络请求失败: ${e.type} ${e.message}',
      };
    }
  }

  static int collectTypeToUserStatus(int collectType) {
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

  static int collectTypeToUpdateStatus(int collectType) {
    // update endpoint: 0=想看, 1=在看, 2=看过, 3=搁置, 4=抛弃
    switch (collectType) {
      case 1:
        return 1;
      case 2:
        return 0;
      case 3:
        return 3;
      case 4:
        return 2;
      case 5:
        return 4;
      default:
        return 0;
    }
  }

  static int userStatusToCollectType(int userStatus) {
    // New mapping: 0=想看, 1=在看, 2=看过, 3=搁置, 4=抛弃
    switch (userStatus) {
      case 0:
        return 2;
      case 1:
        return 1;
      case 2:
        return 4;
      case 3:
        return 3;
      case 4:
        return 5;
      default:
        return 2;
    }
  }

  Future<List<DetailListItem>> detailList() async {
    if (!hasCredentials) return [];
    const path = '/api/v1/open/detail_list';
    try {
      _logRequest('GET', path, {'token': '***'});
      final response = await _dio.get(
        '$_baseUrl$path',
        queryParameters: {'token': _token},
      );
      _logResponse('GET', path, response.data);
      final data = response.data as Map<String, dynamic>;
      if (data['status'] == 0 && data['data'] != null) {
        final list = data['data'] as List<dynamic>;
        return list
            .map((e) => DetailListItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      KazumiLogger().w(
        'RecorderApi: detailList unexpected status=${data['status']}',
        forceLog: true,
      );
    } on DioException catch (e) {
      _logError('GET', path, e);
    }
    return [];
  }

  Future<bool> deleteRecording(int bangumiId) async {
    if (!hasCredentials) return false;
    const path = '/api/v1/open/delete';
    try {
      _logRequest('POST', path, {'token': '***', 'bangumi_id': bangumiId});
      final response = await _dio.post(
        '$_baseUrl$path',
        queryParameters: {
          'token': _token,
          'bangumi_id': bangumiId,
        },
      );
      _logResponse('POST', path, response.data);
      final data = response.data as Map<String, dynamic>;
      return data['status'] == 0;
    } on DioException catch (e) {
      _logError('POST', path, e);
    }
    return false;
  }
}

class RecorderGetResponse {
  final int status;
  final int? localBangumiId;
  final int? bangumiId;
  final String? recorder;
  final String? date;
  final int? userStatus;

  RecorderGetResponse({
    required this.status,
    this.localBangumiId,
    this.bangumiId,
    this.recorder,
    this.date,
    this.userStatus,
  });

  factory RecorderGetResponse.fromJson(Map<String, dynamic> json) {
    return RecorderGetResponse(
      status: json['status'] as int,
      localBangumiId: json['local_bangumi_id'] as int?,
      bangumiId: json['bangumi_id'] as int?,
      recorder: json['recorder'] as String?,
      date: json['date'] as String?,
      userStatus: json['user_status'] as int?,
    );
  }
}

class RecorderItem {
  final int id;
  final int localBangumiId;
  final String? bangumiId;
  final String? recorder;
  final String? date;
  final int? userStatus;

  RecorderItem({
    required this.id,
    required this.localBangumiId,
    this.bangumiId,
    this.recorder,
    this.date,
    this.userStatus,
  });

  factory RecorderItem.fromJson(Map<String, dynamic> json) {
    return RecorderItem(
      id: json['id'] as int,
      localBangumiId: json['local_bangumi_id'] as int,
      bangumiId: json['bangumi_id']?.toString(),
      recorder: json['recorder'] as String?,
      date: json['date'] as String?,
      userStatus: json['user_status'] as int?,
    );
  }
}

class DetailListItem {
  final int id;
  final int localBangumiId;
  final String? bangumiId;
  final String? title;
  final int? type;
  final String? author;
  final int? episodes;
  final String? coverUrl;
  final String? recorder;
  final String? updatedAt;
  final String? createdAt;
  final int? userStatus;

  DetailListItem({
    required this.id,
    required this.localBangumiId,
    this.bangumiId,
    this.title,
    this.type,
    this.author,
    this.episodes,
    this.coverUrl,
    this.recorder,
    this.updatedAt,
    this.createdAt,
    this.userStatus,
  });

  factory DetailListItem.fromJson(Map<String, dynamic> json) {
    return DetailListItem(
      id: json['id'] as int,
      localBangumiId: json['local_bangumi_id'] as int,
      bangumiId: json['bangumi_id']?.toString(),
      title: json['title'] as String?,
      type: json['type'] as int?,
      author: json['author'] as String?,
      episodes: json['episodes'] as int?,
      coverUrl: json['cover_url'] as String?,
      recorder: json['recorder'] as String?,
      updatedAt: json['updated_at'] as String?,
      createdAt: json['created_at'] as String?,
      userStatus: json['user_status'] as int?,
    );
  }
}
