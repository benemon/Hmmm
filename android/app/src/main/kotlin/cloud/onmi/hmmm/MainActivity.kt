package cloud.onmi.hmmm

import android.app.Activity
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pending: ((Intent?) -> Unit)? = null

    private val documentRequest =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val callback = pending
            pending = null
            callback?.invoke(if (result.resultCode == Activity.RESULT_OK) result.data else null)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hmmm/documents")
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "A file request is already open.", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "save" -> {
                        val bytes = call.argument<ByteArray>("bytes")!!
                        pending = { data ->
                            val uri = data?.data
                            if (uri == null) {
                                result.success(false)
                            } else {
                                try {
                                    contentResolver.openOutputStream(uri, "wt")!!.use { it.write(bytes) }
                                    result.success(true)
                                } catch (error: Exception) {
                                    result.error("write", error.message, null)
                                }
                            }
                        }
                        documentRequest.launch(
                            Intent(Intent.ACTION_CREATE_DOCUMENT)
                                .addCategory(Intent.CATEGORY_OPENABLE)
                                .setType(call.argument<String>("mimeType"))
                                .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name")),
                        )
                    }
                    "open" -> {
                        pending = { data ->
                            val uri = data?.data
                            if (uri == null) {
                                result.success(null)
                            } else {
                                try {
                                    result.success(contentResolver.openInputStream(uri)!!.use { it.readBytes() })
                                } catch (error: Exception) {
                                    result.error("read", error.message, null)
                                }
                            }
                        }
                        // Shared and downloaded JSON often arrives typed as
                        // octet-stream or text, so the picker does not filter.
                        documentRequest.launch(
                            Intent(Intent.ACTION_OPEN_DOCUMENT)
                                .addCategory(Intent.CATEGORY_OPENABLE)
                                .setType("*/*"),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
