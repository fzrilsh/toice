package com.fzrilsh.toice

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val messenger = flutterEngine.dartExecutor.binaryMessenger
    HotspotApi.setUp(messenger, HotspotHandler())
    SensorApi.setUp(messenger, SensorHandler())
    BackgroundApi.setUp(messenger, BackgroundHandler())
  }
}
