import 'dart:async';
import 'package:kazumi/request/apis/recorder_api.dart';
import 'package:kazumi/utils/logger.dart';

class RecorderSyncService {
  RecorderSyncService._internal();
  static final RecorderSyncService _instance = RecorderSyncService._internal();
  factory RecorderSyncService() => _instance;

  bool _initialized = false;

  bool get initialized => _initialized && RecorderApi.isConfigured;

  int _queuedOperationCount = 0;
  int _activeOperationCount = 0;
  Future<void> _operationQueue = Future.value();

  bool get isUsing => _queuedOperationCount > 0 || _activeOperationCount > 0;

  Future<void> init() async {
    _initialized = false;
    if (!RecorderApi.isConfigured) {
      throw Exception('请先配置 Recorder API 地址和 Token');
    }
    try {
      await ping();
      _initialized = true;
    } catch (e) {
      KazumiLogger().e('RecorderSync: ping failed', error: e);
      rethrow;
    }
  }

  void reset() {
    _initialized = false;
  }

  Future<void> ping() async {
    if (isUsing) {
      throw Exception('RecorderSync: 当前有操作正在进行，请稍后再试');
    }
    await _runExclusive(() async {
      final success = await RecorderApi.ping();
      if (!success) {
        throw Exception('Recorder API 连接失败，请检查地址和 Token');
      }
    });
  }

  Future<bool> syncCollectibleWhenIdle(int bangumiId, int localType) {
    if (!RecorderApi.isConfigured) {
      return Future.value(true);
    }
    return _runExclusive(() async {
      final userStatus = RecorderApi.collectTypeToUserStatus(localType);
      return RecorderApi.addRecording(bangumiId, userStatus);
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
