package com.opensolutions.huddle

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15+ expects edge-to-edge; avoids odd insets with gesture nav.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
