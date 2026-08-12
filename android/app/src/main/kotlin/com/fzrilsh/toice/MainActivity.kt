package com.fzrilsh.toice

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val messenger = flutterEngine.dartExecutor.binaryMessenger
    val events = HotspotEvents(messenger)
    HotspotApi.setUp(messenger, HotspotHandler(applicationContext, events))
    SensorApi.setUp(messenger, SensorHandler())
    BackgroundApi.setUp(messenger, BackgroundHandler())
  }
}
