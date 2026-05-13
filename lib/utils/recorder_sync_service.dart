import 'dart:async';
import 'package:kazumi/request/apis/recorder_api.dart';
import 'package:kazumi/utils/logger.dart';

class RecorderSyncService {
  RecorderSyncService._internal();
  static final RecorderSyncService _instance = RecorderSyncService._internal();
  factory RecorderSyncService() => _instance;

  bool _initialized = false;

  bool get initialized => _initialized && RecorderApi().hasCredentials;

  int _queuedOperationCount = 0;
  int _activeOperationCount = 0;
  Future<void> _operationQueue = Future.value();

  bool get isUsing => _queuedOperationCount > 0 || _activeOperationCount > 0;

  Future<void> init() async {
    _initialized = false;
    final api = RecorderApi();
    if (!api.hasCredentials) {
      throw Exception('请先配置 Recorder API 地址和 Token');
    }
    await ping();
    _initialized = true;
  }

  void reset() {
    _initialized = false;
  }

  Future<void> ping() async {
    if (isUsing) {
      throw Exception('RecorderSync: 当前有操作正在进行，请稍后再试');
    }
    final result = await RecorderApi().ping();
    if (result['success'] != true) {
      final error = result['error'] ?? '未知错误';
      KazumiLogger().e('RecorderSync: ping failed: $error', forceLog: true);
      throw Exception('Recorder API 连接失败: $error');
    }
    KazumiLogger().i('RecorderSync: ping success', forceLog: true);
  }

  Future<bool> syncCollectibleWhenIdle(int bangumiId, int localType) {
    final api = RecorderApi();
    if (!api.isConfigured) {
      KazumiLogger().w('RecorderSync: sync skipped (not configured) bangumiId=$bangumiId', forceLog: true);
      return Future.value(true);
    }
    return _runExclusive(() async {
      final userStatus = RecorderApi.collectTypeToUserStatus(localType);
      KazumiLogger().i(
        'RecorderSync: syncing bangumiId=$bangumiId localType=$localType userStatus=$userStatus',
        forceLog: true,
      );
      final result = await api.addRecording(bangumiId, userStatus);
      if (result) {
        KazumiLogger().i(
          'RecorderSync: sync success bangumiId=$bangumiId',
          forceLog: true,
        );
      } else {
        KazumiLogger().w(
          'RecorderSync: sync FAILED bangumiId=$bangumiId userStatus=$userStatus',
          forceLog: true,
        );
      }
      return result;
    });
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previousOperation = _operationQueue;
    _queuedOperationCount++;

    _operationQueue = (() async {
      try {
        await previousOperation;
      } catch (_) {}

      _queuedOperationCount--;
      _activeOperationCount++;
      try {
        completer.complete(await action());
      } catch (e, stackTrace) {
        completer.completeError(e, stackTrace);
      } finally {
        _activeOperationCount--;
      }
    })();

    return completer.future;
  }
}
