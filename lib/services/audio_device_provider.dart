import 'package:flutter/foundation.dart';

class AudioDeviceProvider extends ChangeNotifier {
  String? personalDeviceId;
  String? systemDeviceId;

  void setPersonalDevice(String? id) {
    personalDeviceId = id;
    notifyListeners();
  }

  void setSystemDevice(String? id) {
    systemDeviceId = id;
    notifyListeners();
  }
}
