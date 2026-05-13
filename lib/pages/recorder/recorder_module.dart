import 'package:kazumi/pages/recorder/recorder_setting.dart';
import 'package:flutter_modular/flutter_modular.dart';

class RecorderModule extends Module {
  @override
  void binds(i) {}

  @override
  void routes(r) {
    r.child('/', child: (_) => const RecorderSettingPage());
  }
}
