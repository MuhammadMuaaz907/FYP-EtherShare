package com.example.blockchain_fyp

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import android.util.Log

class MainActivity : FlutterFragmentActivity() {
    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "EtherShare MainActivity configured - Using HTTP API for distributed system")
    }

}
