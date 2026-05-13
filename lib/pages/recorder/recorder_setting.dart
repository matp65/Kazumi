import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/utils/recorder_sync_service.dart';
import 'package:kazumi/utils/storage.dart';
import 'package:hive_ce/hive.dart';

class RecorderSettingPage extends StatefulWidget {
  const RecorderSettingPage({super.key});

  @override
  State<RecorderSettingPage> createState() => _RecorderSettingPageState();
}

class _RecorderSettingPageState extends State<RecorderSettingPage> {
  final TextEditingController apiUrlController = TextEditingController();
  final TextEditingController apiTokenController = TextEditingController();
  Box setting = GStorage.setting;
  bool passwordVisible = false;
  bool isVerifying = false;

  @override
  void initState() {
    super.initState();
    apiUrlController.text = setting
        .get(SettingBoxKey.recorderApiUrl, defaultValue: 'http://127.0.0.1:8080')
        .toString()
        .trim();
    apiTokenController.text = setting
        .get(SettingBoxKey.recorderApiToken, defaultValue: '')
        .toString()
        .trim();
  }

  @override
  void dispose() {
    apiUrlController.dispose();
    apiTokenController.dispose();
    super.dispose();
  }

  Future<void> saveAndVerify() async {
    final url = apiUrlController.text.trim();
    final token = apiTokenController.text.trim();

    if (url.isEmpty) {
      KazumiDialog.showToast(message: 'API 地址不能为空');
      return;
    }

    setState(() {
      isVerifying = true;
    });

    await setting.put(SettingBoxKey.recorderApiUrl, url);
    await setting.put(SettingBoxKey.recorderApiToken, token);

    if (token.isEmpty) {
      RecorderSyncService().reset();
      KazumiDialog.showToast(message: 'Token 为空，请填写后测试');
      if (!mounted) return;
      setState(() {
        isVerifying = false;
      });
      return;
    }

    KazumiDialog.showToast(message: '正在测试连接...');
    try {
      await RecorderSyncService().init();
      await setting.put(SettingBoxKey.recorderSyncEnable, true);
      KazumiDialog.showToast(message: '连接成功，已自动开启同步');
    } catch (e) {
      KazumiDialog.showToast(message: '连接失败：$e');
    }

    if (!mounted) return;
    setState(() {
      isVerifying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return Scaffold(
      appBar: const SysAppBar(title: Text('追番进度同步')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SizedBox(
            width: (MediaQuery.of(context).size.width > 1000) ? 1000 : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: apiUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API 服务器地址',
                    hintText: 'http://127.0.0.1:8080',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: apiTokenController,
                  obscureText: !passwordVisible,
                  decoration: InputDecoration(
                    labelText: 'API Token',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          passwordVisible = !passwordVisible;
                        });
                      },
                      icon: Icon(passwordVisible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '状态码映射：想看→待定 | 在看→收录中 | 看过→已完成 | 抛弃→失败',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: fontFamily,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isVerifying ? null : saveAndVerify,
        child: isVerifying
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
      ),
    );
  }
}
