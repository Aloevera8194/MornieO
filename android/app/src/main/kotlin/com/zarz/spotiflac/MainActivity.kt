package com.zarz.spotiflac

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServicePlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicReference

class MainActivity: FlutterFragmentActivity() {
    // Mirrors audio_service's AudioServiceFragmentActivity: the shared engine
    // is owned by AudioServicePlugin's FlutterEngineCache. Without the
    // cached-engine-id + shouldDestroyEngineWithHost overrides, the activity
    // (via createFlutterFragment's destroyEngineWithFragment) destroys the
    // provided engine on exit while it stays registered in the cache; when
    // AudioService later stops, disposeFlutterEngine() destroys it a second
    // time and crashes with "FlutterJNI is not attached to native".
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return AudioServicePlugin.getFlutterEngine(context)
    }

    override fun getCachedEngineId(): String {
        AudioServicePlugin.getFlutterEngine(this)
        return AudioServicePlugin.getFlutterEngineId()
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    private val CHANNEL = "com.zarz.spotiflac/backend"
    private val LARGE_JSON_RESULT_FILE_KEY = "__json_file"
    private val LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES = 256 * 1024
    internal val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    internal var backendChannel: MethodChannel? = null
    internal var audioOutputChannel: MethodChannel? = null
    internal var concertCalendarChannel: MethodChannel? = null
    internal val coreBackend: CoreBackend by lazy { createCoreBackend(applicationContext) }
    private val nativeBackendMethods = setOf(
        "setScreenAwake",
        "getBackendImplementations",
        "ensureInstallMarker",
        "prepareRuntimeState",
        "downloadByStrategy",
        "runPostProcessingV2",
        "readAudioMetadata",
        "readFileMetadata",
        "checkHiResAuthenticity",
        "editFileMetadata",
        "reEnrichFile",
        "setLibraryCoverCacheDir",
        "scanLibraryFolderToNDJSONFile",
        "scanLibraryFolderIncremental",
        "scanSafTreeToNDJSONFile",
        "scanSafTreeIncremental",
        "getLibraryScanProgress",
        "cancelLibraryScan",
        "pauseLibraryScan",
        "resumeLibraryScan",
        "parseCueSheet",
        "pickSafTree",
        "readSetupFolderSelection",
        "acknowledgeSetupFolderSelection",
        "processPendingExtensionCallbacks",
        "safExists",
        "safExistsBatch",
        "isSafTreeAccessible",
        "probeSafTreeReadAccess",
        "safDelete",
        "safStat",
        "resolveSafFile",
        "inspectSafFiles",
        "safCopyToTemp",
        "safOpenPlaybackLease",
        "safClosePlaybackLease",
        "openContentUri",
        "shareContentUri",
        "getSafFileModTimes",
        "safCreateFromPath",
        "safCreateIfAbsentFromPath",
        "safCreateUniqueFromPath",
        "safCreateCollisionAwareFromPath",
        "writeTempToSaf",
        "writeSafSidecarLrc",
        "downloadCoverToFile",
        "extractCoverToFile",
        "rewriteSplitArtistTags",
        "writeM4AFreeformTags",
        "ensureAC4Config",
        "writeAC4Metadata",
        "releaseMemory",
        "releaseMemoryUnderPressure",
        "startDownloadService",
        "stopDownloadService",
        "updateDownloadServiceProgress",
        "isDownloadServiceRunning",
        "startBackgroundWork",
        "updateBackgroundWork",
        "stopBackgroundWork",
        "startNativeDownloadWorker",
        "appendNativeDownloadWorkerRequests",
        "finishNativeDownloadWorkerPreparation",
        "acknowledgeNativeDownloadWorkerItems",
        "pauseNativeDownloadWorker",
        "resumeNativeDownloadWorker",
        "cancelNativeDownloadWorker",
        "getNativeDownloadWorkerSnapshot",
        "consumeVerificationNotification",
        "exitApp",
    )
    private var libraryStorageReceiver: BroadcastReceiver? = null
    internal val pendingSessionGrantEvents = mutableListOf<Map<String, Any>>()
    internal var pendingVerificationNotification: String? = null
    internal val setupFolderPickerStore by lazy {
        SetupFolderPickerStore(getSharedPreferences("setup_folder_picker", Context.MODE_PRIVATE))
    }
    internal val safScanLock = Any()
    internal var safScanProgress = SafScanProgress()
    internal var downloadProgressStreamJob: Job? = null
    internal var downloadProgressConnection: AtomicReference<CoreDownloadProgress?>? = null
    internal var downloadProgressEventSink: EventChannel.EventSink? = null
    internal var lastDownloadProgressPayload: String? = null
    internal var lastDownloadProgressSeq = 0L
    internal var libraryScanProgressStreamJob: Job? = null
    internal var libraryScanProgressEventSink: EventChannel.EventSink? = null
    internal var lastLibraryScanProgressPayload: String? = null
    private var flutterBackCallback: OnBackPressedCallback? = null
    internal val playbackLeaseLock = Any()
    internal val playbackLeases = LinkedHashMap<String, ParcelFileDescriptor>()
    @Volatile internal var safScanCancel = false
    @Volatile internal var safScanPaused = false
    @Volatile internal var safScanActive = false
    internal val safTreeLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        handleSafTreeResult(activityResult)
    }

    data class SafScanProgress(
        var totalFiles: Int = 0,
        var scannedFiles: Int = 0,
        var currentFile: String = "",
        var errorCount: Int = 0,
        var progressPct: Double = 0.0,
        var isComplete: Boolean = false,
    )

    companion object {
        internal val extensionAuthCallbacks = ExtensionAuthCallbacks()
        // audio_service keeps the engine across Activity recreation. Retain
        // its outstanding picker reply for the same lifetime, not the Activity.
        internal var pendingSafTreeResult: MethodChannel.Result? = null
    }

    class ImpellerAwareFlutterFragment : FlutterFragment() {
        override fun getFlutterShellArgs(): FlutterShellArgs {
            val args = super.getFlutterShellArgs()
            if (shouldDisableImpeller()) {
                android.util.Log.w("SpotiFLAC", "Legacy/problematic GPU detected for ${Build.MODEL}")
                android.util.Log.w("SpotiFLAC", "Device: ${Build.MANUFACTURER} ${Build.MODEL}, SDK: ${Build.VERSION.SDK_INT}")
                android.util.Log.w("SpotiFLAC", "Hardware: ${Build.HARDWARE}, Board: ${Build.BOARD}")
                args.add("--enable-impeller=false")
            }
            return args
        }
    }

    override fun createFlutterFragment(): FlutterFragment {
        val backgroundMode = getBackgroundMode()
        val renderMode = getRenderMode()
        val transparencyMode =
            if (backgroundMode == BackgroundMode.opaque) TransparencyMode.opaque else TransparencyMode.transparent
        val shouldDelayFirstAndroidViewDraw = renderMode == RenderMode.surface

        getCachedEngineId()?.let { cachedEngineId ->
            return FlutterFragment.CachedEngineFragmentBuilder(
                ImpellerAwareFlutterFragment::class.java,
                cachedEngineId
            )
                .renderMode(renderMode)
                .transparencyMode(transparencyMode)
                .handleDeeplinking(shouldHandleDeeplinking())
                .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
                .destroyEngineWithFragment(shouldDestroyEngineWithHost())
                .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
                .shouldAutomaticallyHandleOnBackPressed(true)
                .build()
        }

        getCachedEngineGroupId()?.let { cachedEngineGroupId ->
            return FlutterFragment.NewEngineInGroupFragmentBuilder(
                ImpellerAwareFlutterFragment::class.java,
                cachedEngineGroupId
            )
                .dartEntrypoint(getDartEntrypointFunctionName())
                .initialRoute(getInitialRoute())
                .handleDeeplinking(shouldHandleDeeplinking())
                .renderMode(renderMode)
                .transparencyMode(transparencyMode)
                .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
                .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
                .shouldAutomaticallyHandleOnBackPressed(true)
                .build()
        }

        return FlutterFragment.NewEngineFragmentBuilder(ImpellerAwareFlutterFragment::class.java)
            .dartEntrypoint(getDartEntrypointFunctionName())
            .dartLibraryUri(getDartEntrypointLibraryUri() ?: "")
            .dartEntrypointArgs(getDartEntrypointArgs() ?: emptyList())
            .initialRoute(getInitialRoute())
            .appBundlePath(getAppBundlePath())
            .flutterShellArgs(FlutterShellArgs.fromIntent(intent))
            .handleDeeplinking(shouldHandleDeeplinking())
            .renderMode(renderMode)
            .transparencyMode(transparencyMode)
            .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
            .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
            .shouldAutomaticallyHandleOnBackPressed(true)
            .build()
    }

    private fun parseJsonValue(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> {
                val map = LinkedHashMap<String, Any?>()
                val keys = value.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = parseJsonValue(value.opt(key))
                }
                map
            }
            is JSONArray -> {
                val list = ArrayList<Any?>()
                for (i in 0 until value.length()) {
                    list.add(parseJsonValue(value.opt(i)))
                }
                list
            }
            is Number, is Boolean, is String -> value
            else -> value.toString()
        }
    }

    internal fun parseJsonPayload(payload: String): Any {
        return try {
            parseJsonValue(JSONTokener(payload).nextValue()) ?: payload
        } catch (_: Exception) {
            payload
        }
    }

    internal fun bridgeJsonResult(payload: String): Any {
        // Decide on char count where possible: UTF-8 size is >= length and
        // <= 3*length, so only the ambiguous band needs the full encode —
        // avoids duplicating multi-MB payloads just to measure them.
        val definitelySmall = payload.length * 3 < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES
        val definitelyLarge = payload.length >= LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES
        if (definitelySmall ||
            (!definitelyLarge &&
                payload.toByteArray(Charsets.UTF_8).size < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES)
        ) {
            return payload
        }

        return try {
            val file = File(cacheDir, "bridge_json_${System.nanoTime()}.json")
            file.writeText(payload, Charsets.UTF_8)
            mapOf(LARGE_JSON_RESULT_FILE_KEY to file.absolutePath)
        } catch (e: Exception) {
            android.util.Log.w(
                "SpotiFLAC",
                "Failed to spill large bridge JSON result to file: ${e.message}",
            )
            payload
        }
    }

    /**
     * Streams a JSON payload piecewise to a cache spill file so large scan
     * results never materialize on the Java heap. [result] hands back the
     * payload inline when it is small (same contract as [bridgeJsonResult]),
     * otherwise the spill-file map.
     */
    internal inner class SpillJsonWriter {
        val file = File(cacheDir, "bridge_json_${System.nanoTime()}.json")
        private val writer = file.bufferedWriter(Charsets.UTF_8)

        fun raw(fragment: String) = writer.write(fragment)

        fun result(): Any {
            writer.close()
            if (file.length() < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES) {
                val payload = file.readText(Charsets.UTF_8)
                file.delete()
                return payload
            }
            return mapOf(LARGE_JSON_RESULT_FILE_KEY to file.absolutePath)
        }

        fun abandon() {
            try { writer.close() } catch (_: Exception) {}
            try { file.delete() } catch (_: Exception) {}
        }
    }

    // Disable Flutter's built-in deep linking so that incoming ACTION_VIEW URLs
    // (Spotify, Deezer, Tidal, YouTube Music) are NOT forwarded to GoRouter.
    // We handle these URLs ourselves via receive_sharing_intent + ShareIntentService.
    override fun shouldHandleDeeplinking(): Boolean = false

    // Bridge spill files and SAF temp copies are deleted after use on the
    // normal path, but a process kill mid-operation orphans them in cacheDir
    // forever (names embed nanoTime, so nothing overwrites them). Sweep
    // leftovers from previous sessions; the 1h age guard protects in-flight
    // files from concurrent work in this session.
    private fun sweepStaleCacheFiles() {
        scope.launch(Dispatchers.IO) {
            try {
                val cutoff = System.currentTimeMillis() - 60 * 60 * 1000L
                cacheDir.listFiles()?.forEach { file ->
                    val stale = file.isFile &&
                        file.lastModified() < cutoff &&
                        (file.name.startsWith("bridge_json_") ||
                            file.name.startsWith("saf_") ||
                            file.name.startsWith("native_saf_") ||
                            file.name.startsWith("ms_"))
                    if (stale) file.delete()
                }
            } catch (_: Exception) {}
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Ensure the shared audio_service engine exists before the activity
        // delegate looks it up by cached id (see getCachedEngineId above).
        AudioServicePlugin.getFlutterEngine(this)
        super.onCreate(savedInstanceState)
        handleVerificationNotificationIntent(intent)
        handleExtensionOAuthIntent(intent)
        PlayerWidgetBridge.handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleVerificationNotificationIntent(intent)
        handleExtensionOAuthIntent(intent)
        PlayerWidgetBridge.handleIntent(intent)
    }

    internal fun reportLibraryScanError(path: String, operation: String, message: String) {
        android.util.Log.e("SpotiFLAC", "Library scan: $operation [$path]: $message")
        val payload = mapOf(
            "path" to path,
            "operation" to operation,
            "message" to message,
        )
        runOnUiThread {
            backendChannel?.invokeMethod("libraryScanError", payload)
        }
    }

    override fun onDestroy() {
        if (isFinishing) {
            val pending = pendingSafTreeResult
            pendingSafTreeResult = null
            pending?.success(null)
        }
        concertCalendarChannel?.setMethodCallHandler(null)
        concertCalendarChannel = null
        audioOutputChannel?.setMethodCallHandler(null)
        audioOutputChannel = null
        libraryStorageReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        libraryStorageReceiver = null
        // The backend belongs to the process/shared Flutter engine and download
        // service. Activity recreation must not shut it down (or wait for its
        // active scans/downloads on the UI thread).
        stopDownloadProgressStream()
        stopLibraryScanProgressStream()
        closeAllSafPlaybackLeases()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlayerWidgetBridge.attach(this, flutterEngine)
        // Select and initialize the runtime before Flutter can dispatch a call.
        val selectedBackend = coreBackend
        sweepStaleCacheFiles()

        // Always-enabled back callback to ensure back presses reach Flutter.
        // Nested tab navigators can incorrectly set frameworkHandlesBack(false),
        // which disables Flutter's own OnBackPressedCallback and causes the
        // system default (finish activity) to run. This callback guarantees
        // popRoute is always forwarded to Flutter, where PopScope handles it.
        flutterBackCallback = object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                flutterEngine.navigationChannel.popRoute()
            }
        }
        onBackPressedDispatcher.addCallback(this, flutterBackCallback!!)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        if (!flutterEngine.plugins.has(LocalNetworkPlugin::class.java)) {
            flutterEngine.plugins.add(LocalNetworkPlugin())
        }
        if (!flutterEngine.plugins.has(UsbBitPerfectPlugin::class.java)) {
            flutterEngine.plugins.add(UsbBitPerfectPlugin())
        }
        if (!flutterEngine.plugins.has(MusicHapticsPlugin::class.java)) {
            flutterEngine.plugins.add(MusicHapticsPlugin())
        }
        registerConcertCalendarChannel(messenger)
        registerAudioOutputChannel(messenger)

        registerProgressStreams(messenger)

        val channel = MethodChannel(messenger, CHANNEL)
        backendChannel = channel
        registerLibraryStorageReceiver()
        if (pendingSessionGrantEvents.isNotEmpty()) {
            val events = pendingSessionGrantEvents.toList()
            pendingSessionGrantEvents.clear()
            for (event in events) {
                channel.invokeMethod("extensionSessionGrantCompleted", event)
            }
        }

        channel.setMethodCallHandler { call, result ->
            scope.launch {
                try {
                    if (call.method !in nativeBackendMethods && dispatchBackendApplication(call, result)) {
                        return@launch
                    }
                    when (call.method) {
                        "processPendingExtensionCallbacks" -> {
                            processPendingExtensionCallbacks()
                            result.success(null)
                        }
                        "setScreenAwake" -> {
                            val flag = android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                            if (call.argument<Boolean>("enabled") == true) {
                                window.addFlags(flag)
                            } else {
                                window.clearFlags(flag)
                            }
                            result.success(null)
                        }
                        "consumeVerificationNotification" -> {
                            val payload = pendingVerificationNotification
                            pendingVerificationNotification = null
                            result.success(payload)
                        }
                        "ensureInstallMarker" -> {
                            val installState = withContext(Dispatchers.IO) {
                                ensureInstallMarker()
                            }
                            result.success(installState)
                        }
                        "prepareRuntimeState" -> {
                            val dataDir = call.argument<String>("data_dir") ?: ""
                            val runtimeState = withContext(Dispatchers.IO) {
                                require(dataDir.isNotBlank()) {
                                    "Extension data directory is required"
                                }
                                val payload = prepareRuntimeState(dataDir)
                                selectedBackend.setRuntimeState(dataDir, payload)
                                mapOf("ready" to true)
                            }
                            result.success(runtimeState)
                        }
                        "exitApp" -> {
                            flutterBackCallback?.isEnabled = false
                            finishAndRemoveTask()
                            result.success(null)
                        }
                        "downloadByStrategy" -> {
                            val requestJson = call.arguments as String
                            val response = withContext(Dispatchers.IO) {
                                SafDownloadHandler.handle(this@MainActivity, requestJson, coreBackend)
                            }
                            result.success(response)
                        }
                        "getBackendImplementations" -> {
                            result.success(
                                mapOf(
                                    "filename" to coreBackend.implementation,
                                    "file_metadata" to coreBackend.fileMetadataImplementation(call.argument<String>("file_path") ?: ""),
                                    "extensions" to coreBackend.implementation,
                                    "downloads" to coreBackend.implementation,
                                )
                            )
                        }
                        "pickSafTree" -> {
                            launchSafTreePicker(call, result)
                        }
                        "readSetupFolderSelection" -> {
                            result.success(setupFolderPickerStore.read())
                        }
                        "acknowledgeSetupFolderSelection" -> {
                            setupFolderPickerStore.acknowledge(call.argument<String>("payload") ?: "")
                            result.success(null)
                        }
                        "safExists" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val exists = withContext(Dispatchers.IO) {
                                val uri = Uri.parse(uriStr)
                                DocumentFile.fromSingleUri(this@MainActivity, uri)?.exists() == true
                            }
                            result.success(exists)
                        }
                        "safExistsBatch" -> {
                            val urisJson = call.argument<String>("uris_json") ?: "[]"
                            val response = withContext(Dispatchers.IO) {
                                safExistsBatch(urisJson)
                            }
                            result.success(response)
                        }
                        "probeSafTreeReadAccess" -> {
                            val uriStr = call.argument<String>("tree_uri") ?: ""
                            val readable = withContext(Dispatchers.IO) {
                                probeSafTreeReadAccess(
                                    hasReadPermission = {
                                        val uri = Uri.parse(uriStr)
                                        val root = DocumentsContract.buildDocumentUriUsingTree(
                                            uri,
                                            DocumentsContract.getTreeDocumentId(uri),
                                        )
                                        checkUriPermission(
                                            root,
                                            android.os.Process.myPid(),
                                            android.os.Process.myUid(),
                                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                                        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                                    },
                                    readRoot = {
                                        val uri = Uri.parse(uriStr)
                                        val root = DocumentsContract.buildDocumentUriUsingTree(
                                            uri,
                                            DocumentsContract.getTreeDocumentId(uri),
                                        )
                                        val rootPresent = contentResolver.query(
                                            root,
                                            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                                            null, null, null,
                                        )?.use { cursor ->
                                            when {
                                                cursor.moveToFirst() -> true
                                                cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false) -> null
                                                else -> false
                                            }
                                        }
                                        if (rootPresent == true) {
                                            true
                                        } else {
                                            // A reconnecting remote provider may not have
                                            // queryDocument metadata yet. A completed child
                                            // listing is stronger evidence of read access.
                                            val directory = DocumentFile.fromTreeUri(this@MainActivity, uri)
                                            if (directory != null && listSafChildrenOrThrow(directory).isNotEmpty()) {
                                                true
                                            } else {
                                                rootPresent
                                            }
                                        }
                                    },
                                    onFailure = { error ->
                                        android.util.Log.w("SpotiFLAC", "SAF library read probe failed", error)
                                    },
                                )
                            }
                            result.success(readable)
                        }
                        "isSafTreeAccessible" -> {
                            val uriStr = call.argument<String>("tree_uri") ?: ""
                            val accessible = withContext(Dispatchers.IO) {
                                try {
                                    val uri = Uri.parse(uriStr)
                                    val persisted = contentResolver.persistedUriPermissions.any {
                                        it.uri == uri && it.isReadPermission && it.isWritePermission
                                    }
                                    if (!persisted) {
                                        false
                                    } else {
                                        val doc = DocumentFile.fromTreeUri(this@MainActivity, uri)
                                        doc != null && doc.exists() && doc.canWrite()
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.w("SpotiFLAC", "SAF tree access check failed: ${e.message}")
                                    false
                                }
                            }
                            result.success(accessible)
                        }
                        "safDelete" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val deleted = withContext(Dispatchers.IO) {
                                val uri = Uri.parse(uriStr)
                                DocumentFile.fromSingleUri(this@MainActivity, uri)?.delete() == true
                            }
                            result.success(deleted)
                        }
                        "safStat" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                querySafDocumentStat(contentResolver, Uri.parse(uriStr)).toString()
                            }
                            result.success(response)
                        }
                        "resolveSafFile" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val fileName = call.argument<String>("file_name") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                resolveSafFile(treeUriStr, relativeDir, fileName)
                            }
                            result.success(response)
                        }
                        "inspectSafFiles" -> {
                            val requestsJson = call.argument<String>("requests_json") ?: "[]"
                            val response = withContext(Dispatchers.IO) {
                                inspectSafFiles(requestsJson)
                            }
                            result.success(response)
                        }
                        "safCopyToTemp" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val tempPath = withContext(Dispatchers.IO) {
                                copyUriToTemp(Uri.parse(uriStr))
                            }
                            result.success(tempPath)
                        }
                        "safOpenPlaybackLease" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val lease = withContext(Dispatchers.IO) {
                                openSafPlaybackLease(uriStr)
                            }
                            result.success(lease)
                        }
                        "safClosePlaybackLease" -> {
                            val token = call.argument<String>("token") ?: ""
                            closeSafPlaybackLease(token)
                            result.success(null)
                        }
                        "safCreateFromPath" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val fileName = SafDownloadHandler.sanitizeFilename(call.argument<String>("file_name") ?: "")
                            val mimeType = call.argument<String>("mime_type") ?: "application/octet-stream"
                            val srcPath = call.argument<String>("src_path") ?: ""
                            val createdUri = withContext(Dispatchers.IO) {
                                if (treeUriStr.isBlank()) return@withContext null
                                if (fileName.isBlank()) return@withContext null
                                val dir = SafDownloadHandler.ensureDocumentDir(this@MainActivity, Uri.parse(treeUriStr), relativeDir) ?: return@withContext null
                                val existing = findSafChild(this@MainActivity, dir, fileName)
                                val createdNew = existing == null
                                val doc = SafDownloadHandler.createOrReuseDocumentFile(this@MainActivity, dir, mimeType, fileName)
                                    ?: return@withContext null
                                if (!writeUriFromPath(doc.uri, srcPath)) {
                                    if (createdNew) {
                                        doc.delete()
                                    }
                                    return@withContext null
                                }
                                doc.uri.toString()
                            }
                            result.success(createdUri)
                        }
                        "safCreateIfAbsentFromPath" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val fileName = call.argument<String>("file_name") ?: ""
                            val mimeType = call.argument<String>("mime_type") ?: "application/octet-stream"
                            val srcPath = call.argument<String>("src_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                if (treeUriStr.isBlank() || fileName.isBlank()) return@withContext null
                                SafDownloadHandler.writeFileToSafIfAbsent(
                                    context = this@MainActivity,
                                    treeUriStr = treeUriStr,
                                    relativeDir = relativeDir,
                                    fileName = fileName,
                                    mimeType = mimeType,
                                    srcPath = srcPath,
                                )?.let { writeResult ->
                                    JSONObject()
                                        .put("uri", writeResult.uri)
                                        .put("file_name", writeResult.fileName)
                                        .put("already_exists", writeResult.alreadyExists)
                                        .put("publish_timings_ms", JSONObject(writeResult.publishTimingsMs))
                                        .toString()
                                }
                            }
                            result.success(response)
                        }
                        "safCreateUniqueFromPath" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val fileName = call.argument<String>("file_name") ?: ""
                            val mimeType = call.argument<String>("mime_type") ?: "application/octet-stream"
                            val srcPath = call.argument<String>("src_path") ?: ""
                            val preservedSuffix = call.argument<String>("preserved_suffix") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                if (treeUriStr.isBlank() || fileName.isBlank()) return@withContext null
                                SafDownloadHandler.writeFileToSafUnique(
                                    context = this@MainActivity,
                                    treeUriStr = treeUriStr,
                                    relativeDir = relativeDir,
                                    fileName = fileName,
                                    mimeType = mimeType,
                                    srcPath = srcPath,
                                    preservedSuffix = preservedSuffix,
                                )?.let { writeResult ->
                                    JSONObject()
                                        .put("uri", writeResult.uri)
                                        .put("file_name", writeResult.fileName)
                                        .put("publish_timings_ms", JSONObject(writeResult.publishTimingsMs))
                                        .toString()
                                }
                            }
                            result.success(response)
                        }
                        "safCreateCollisionAwareFromPath" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val cleanFileName = call.argument<String>("clean_file_name") ?: ""
                            val variantFileName = call.argument<String>("variant_file_name") ?: ""
                            val mimeType = call.argument<String>("mime_type") ?: "application/octet-stream"
                            val srcPath = call.argument<String>("src_path") ?: ""
                            val preservedSuffix = call.argument<String>("preserved_suffix") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                if (
                                    treeUriStr.isBlank() ||
                                    cleanFileName.isBlank() ||
                                    variantFileName.isBlank()
                                ) return@withContext null
                                SafDownloadHandler.writeFileToSafCollisionAware(
                                    context = this@MainActivity,
                                    treeUriStr = treeUriStr,
                                    relativeDir = relativeDir,
                                    cleanFileName = cleanFileName,
                                    variantFileName = variantFileName,
                                    mimeType = mimeType,
                                    srcPath = srcPath,
                                    preservedSuffix = preservedSuffix,
                                )?.let { writeResult ->
                                    JSONObject()
                                        .put("uri", writeResult.uri)
                                        .put("file_name", writeResult.fileName)
                                        .put("publish_timings_ms", JSONObject(writeResult.publishTimingsMs))
                                        .toString()
                                }
                            }
                            result.success(response)
                        }
                        "openContentUri" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val mimeType = call.argument<String>("mime_type") ?: ""
                            try {
                                val uri = Uri.parse(uriStr)
                                val type = if (mimeType.isNotBlank()) mimeType else contentResolver.getType(uri) ?: "*/*"
                                val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("open_failed", e.message, null)
                            }
                        }
                        "shareContentUri" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val title = call.argument<String>("title") ?: ""
                            try {
                                val uri = Uri.parse(uriStr)
                                val type = contentResolver.getType(uri) ?: "audio/*"
                                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    setType(type)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    if (title.isNotBlank()) {
                                        putExtra(Intent.EXTRA_SUBJECT, title)
                                    }
                                }
                                startActivity(Intent.createChooser(shareIntent, title.ifBlank { "Share" }))
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("share_failed", e.message, null)
                            }
                        }
                        "rewriteSplitArtistTags" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val artist = call.argument<String>("artist") ?: ""
                            val albumArtist = call.argument<String>("album_artist") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                if (filePath.startsWith("content://")) {
                                    val uri = Uri.parse(filePath)
                                    val tempPath = copyUriToTemp(uri, ".flac")
                                        ?: return@withContext errorJson("Failed to copy SAF file to temp")
                                    try {
                                        val raw = coreBackend.rewriteSplitArtistTags(tempPath, artist, albumArtist)
                                        val obj = JSONObject(raw)
                                        if (!obj.optBoolean("success", false)) {
                                            return@withContext raw
                                        }

                                        if (!writeUriFromPath(uri, tempPath)) {
                                            return@withContext errorJson("Failed to write rewritten tags back to SAF file")
                                        }

                                        obj.put("file_path", filePath)
                                        obj.toString()
                                    } catch (e: Exception) {
                                        errorJson("Failed to rewrite split artist tags in SAF file: ${e.message}")
                                    } finally {
                                        try {
                                            File(tempPath).delete()
                                        } catch (_: Exception) {}
                                    }
                                } else {
                                    coreBackend.rewriteSplitArtistTags(filePath, artist, albumArtist)
                                }
                            }
                            result.success(response)
                        }
                        "readFileMetadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val displayName = call.argument<String>("display_name") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        readCompleteMetadataFromUri(Uri.parse(filePath), displayName)
                                            ?.toString() ?: errorJson("Failed to read SAF metadata")
                                    } else {
                                        coreBackend.readFileMetadata(filePath, displayName)
                                    }
                                } catch (e: Exception) {
                                    errorJson(e.message ?: "Failed to read metadata")
                                }
                            }
                            result.success(response)
                        }
                        "checkHiResAuthenticity" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val optionsJson = call.argument<String>("options_json") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        checkHiResAuthenticityFromUri(Uri.parse(filePath), optionsJson)
                                            ?.toString()
                                            ?: errorJson("Failed to read SAF audio file")
                                    } else {
                                        coreBackend.checkHiResAuthenticity(filePath, optionsJson)
                                    }
                                } catch (e: Exception) {
                                    errorJson(e.message ?: "Hi-Res check failed")
                                }
                            }
                            result.success(response)
                        }
                        "editFileMetadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val metadataJson = call.argument<String>("metadata_json") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        val uri = Uri.parse(filePath)
                                        val tempPath = copyUriToTemp(uri)
                                            ?: return@withContext """{"error":"Failed to copy SAF file to temp"}"""
                                        try {
                                            val raw = coreBackend.editFileMetadata(tempPath, metadataJson)
                                            val obj = JSONObject(raw)
                                            val method = obj.optString("method", "")
                                            if (method == "ffmpeg") {
                                                // MP3/Opus: Dart needs to FFmpeg the temp file, then call writeTempToSaf
                                                obj.put("temp_path", tempPath)
                                                obj.put("saf_uri", filePath)
                                                return@withContext obj.toString()
                                                // Note: temp file NOT deleted here - Dart will clean up after FFmpeg + writeTempToSaf
                                            }
                            // FLAC: the backend wrote to temp, copy back now
                            if (!writeUriFromPath(uri, tempPath)) {
                                try { File(tempPath).delete() } catch (_: Exception) {}
                                return@withContext """{"error":"Failed to write metadata back to SAF file"}"""
                            }
                            try { File(tempPath).delete() } catch (_: Exception) {}
                            raw
                                        } catch (e: Exception) {
                                            try { File(tempPath).delete() } catch (_: Exception) {}
                                            throw e
                                        }
                                    } else {
                                        coreBackend.editFileMetadata(filePath, metadataJson)
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "editFileMetadata failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "writeM4AFreeformTags" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val metadataJson = call.argument<String>("metadata_json") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    coreBackend.writeM4aFreeformTags(filePath, metadataJson)
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "writeM4AFreeformTags failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "ensureAC4Config" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val sourcePath = call.argument<String>("source_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    coreBackend.ensureAc4Config(filePath, sourcePath)
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "ensureAC4Config failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "writeAC4Metadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val metadataJson = call.argument<String>("metadata_json") ?: "{}"
                            val coverPath = call.argument<String>("cover_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    coreBackend.writeAc4Metadata(filePath, metadataJson, coverPath)
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "writeAC4Metadata failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "writeTempToSaf" -> {
                            val tempPath = call.argument<String>("temp_path") ?: ""
                            val safUri = call.argument<String>("saf_uri") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    val uri = Uri.parse(safUri)
                                    if (writeUriFromPath(uri, tempPath)) {
                                        """{"success":true}"""
                                    } else {
                                        """{"success":false,"error":"Failed to write back to SAF"}"""
                                    }
                                } finally {
                                    try { File(tempPath).delete() } catch (_: Exception) {}
                                }
                            }
                            result.success(response)
                        }
                        "writeSafSidecarLrc" -> {
                            val safUri = call.argument<String>("saf_uri") ?: ""
                            val lyrics = call.argument<String>("lyrics") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    val uri = Uri.parse(safUri)
                                    if (writeSafSidecarLrc(uri, lyrics)) {
                                        """{"success":true}"""
                                    } else {
                                        """{"success":false,"error":"Failed to write LRC sidecar"}"""
                                    }
                                } catch (e: Exception) {
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                }
                            }
                            result.success(response)
                        }
                        "downloadCoverToFile" -> {
                            val coverUrl = call.argument<String>("cover_url") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val maxDimension = call.argument<Number>("max_dimension")
                                ?.toLong()
                                ?.coerceAtLeast(0L)
                                ?: 0L
                            val response = withContext(Dispatchers.IO) {
                                var temporaryCover: File? = null
                                try {
                                    val destination = if (outputPath.isBlank()) {
                                        coreBackend.createTemporaryMediaFile(
                                            this@MainActivity,
                                            "cover_",
                                            ".jpg",
                                        ).also { temporaryCover = it }.absolutePath
                                    } else {
                                        outputPath
                                    }
                                    coreBackend.downloadCoverToFileSized(
                                        coverUrl,
                                        destination,
                                        maxDimension
                                    )
                                    JSONObject()
                                        .put("success", true)
                                        .put("file_path", destination)
                                        .toString()
                                } catch (e: Exception) {
                                    temporaryCover?.delete()
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                }
                            }
                            result.success(response)
                        }
                        "extractCoverToFile" -> {
                            val audioPath = call.argument<String>("audio_path") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (audioPath.startsWith("content://")) {
                                        extractCoverFromUri(Uri.parse(audioPath), outputPath)
                                        """{"success":true}"""
                                    } else {
                                        coreBackend.extractCoverToFile(audioPath, outputPath)
                                        """{"success":true}"""
                                    }
                                } catch (e: Exception) {
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                }
                            }
                            result.success(response)
                        }
                        "reEnrichFile" -> {
                            val requestJson = call.argument<String>("request_json") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    val reqObj = JSONObject(requestJson)
                                    val filePath = reqObj.optString("file_path", "")

                                    // Preview only resolves online metadata; it does not need
                                    // a full SAF document copy and never writes the source.
                                    if (filePath.startsWith("content://") && !reqObj.optBoolean("preview_only", false)) {
                                        val uri = Uri.parse(filePath)
                                        val tempPath = copyUriToTemp(uri)
                                            ?: return@withContext """{"error":"Failed to copy SAF file to temp"}"""
                                        var retainedForFfmpeg = false
                                        try {
                                            reqObj.put("file_path", tempPath)
                                            val raw = coreBackend.reEnrichFile(reqObj.toString())
                                            val obj = JSONObject(raw)

                                            if (obj.has("error")) {
                                                return@withContext raw
                                            }

                                            val method = obj.optString("method", "")
                                            if (method == "ffmpeg") {
                                                // MP3/Opus: Dart handles FFmpeg on temp file, then writes back
                                                obj.put("temp_path", tempPath)
                                                obj.put("saf_uri", filePath)
                                                retainedForFfmpeg = true
                                                return@withContext obj.toString()
                                                // Dart cleans up after FFmpeg + writeTempToSaf.
                                            }

                                            // FLAC: the selected backend wrote to temp; copy back now.
                                            if (!writeUriFromPath(uri, tempPath)) {
                                                return@withContext """{"error":"Failed to write enriched metadata back to SAF file"}"""
                                            }
                                            if (obj.optBoolean("write_external_lrc", false) &&
                                                !writeSafSidecarLrc(uri, obj.optString("lyrics", ""))) {
                                                return@withContext errorJson(
                                                    "Metadata was saved, but the LRC lyrics file could not be updated"
                                                )
                                            }
                                            raw
                                        } finally {
                                            if (!retainedForFfmpeg) {
                                                try { File(tempPath).delete() } catch (_: Exception) {}
                                            }
                                        }
                                    } else {
                                        coreBackend.reEnrichFile(requestJson)
                                    }
                                } catch (e: Exception) {
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "startDownloadService" -> {
                            val trackName = call.argument<String>("track_name") ?: ""
                            val artistName = call.argument<String>("artist_name") ?: ""
                            val queueCount = call.argument<Int>("queue_count") ?: 0
                            DownloadService.start(this@MainActivity, trackName, artistName, queueCount)
                            result.success(null)
                        }
                        "stopDownloadService" -> {
                            DownloadService.stop(this@MainActivity)
                            result.success(null)
                        }
                        "updateDownloadServiceProgress" -> {
                            val trackName = call.argument<String>("track_name") ?: ""
                            val artistName = call.argument<String>("artist_name") ?: ""
                            val progress = (call.argument<Number>("progress") ?: 0).toLong()
                            val total = (call.argument<Number>("total") ?: 0).toLong()
                            val queueCount = (call.argument<Number>("queue_count") ?: 0).toInt()
                            val status = call.argument<String>("status") ?: "downloading"
                            DownloadService.updateProgress(this@MainActivity, trackName, artistName, progress, total, queueCount, status)
                            result.success(null)
                        }
                        "isDownloadServiceRunning" -> {
                            result.success(DownloadService.isServiceRunning())
                        }
                        "startBackgroundWork" -> {
                            result.success(
                                BackgroundWorkService.start(
                                    this@MainActivity,
                                    call.argument<String>("kind") ?: "",
                                    call.argument<String>("title") ?: "",
                                    call.argument<String>("text") ?: "",
                                ),
                            )
                        }
                        "updateBackgroundWork" -> {
                            BackgroundWorkService.update(
                                call.argument<String>("kind") ?: "",
                                call.argument<String>("title") ?: "",
                                call.argument<String>("text") ?: "",
                                call.argument<Int>("progress") ?: -1,
                            )
                            result.success(null)
                        }
                        "stopBackgroundWork" -> {
                            BackgroundWorkService.stop(call.argument<String>("kind") ?: "")
                            result.success(null)
                        }
                        "startNativeDownloadWorker" -> {
                            val requestsJson = call.argument<String>("requests_json") ?: "[]"
                            val settingsJson = call.argument<String>("settings_json") ?: "{}"
                            val requestsPath = call.argument<String>("requests_path") ?: ""
                            val settingsPath = call.argument<String>("settings_path") ?: ""
                            if (requestsPath.isNotBlank()) {
                                DownloadService.startNativeQueueFromFiles(
                                    this@MainActivity,
                                    requestsPath,
                                    settingsPath
                                )
                            } else {
                                DownloadService.startNativeQueue(this@MainActivity, requestsJson, settingsJson)
                            }
                            result.success(null)
                        }
                        "appendNativeDownloadWorkerRequests" -> {
                            val requestsPath = call.argument<String>("requests_path") ?: ""
                            val runId = call.argument<String>("run_id") ?: ""
                            if (requestsPath.isNotBlank() && runId.isNotBlank()) {
                                DownloadService.appendNativeQueueFromFile(
                                    this@MainActivity,
                                    requestsPath,
                                    runId,
                                )
                            }
                            result.success(null)
                        }
                        "finishNativeDownloadWorkerPreparation" -> {
                            val runId = call.argument<String>("run_id") ?: ""
                            if (runId.isNotBlank()) {
                                DownloadService.finishNativeQueuePreparation(
                                    this@MainActivity,
                                    runId,
                                )
                            }
                            result.success(null)
                        }
                        "acknowledgeNativeDownloadWorkerItems" -> {
                            val runId = call.argument<String>("run_id") ?: ""
                            val itemIdsJson = call.argument<String>("item_ids_json") ?: "[]"
                            if (runId.isNotBlank()) {
                                DownloadService.acknowledgeNativeQueueItems(
                                    this@MainActivity,
                                    runId,
                                    itemIdsJson,
                                )
                            }
                            result.success(null)
                        }
                        "pauseNativeDownloadWorker" -> {
                            DownloadService.pauseNativeQueue(this@MainActivity)
                            result.success(null)
                        }
                        "resumeNativeDownloadWorker" -> {
                            DownloadService.resumeNativeQueue(this@MainActivity)
                            result.success(null)
                        }
                        "cancelNativeDownloadWorker" -> {
                            DownloadService.cancelNativeQueue(this@MainActivity)
                            result.success(null)
                        }
                        "getNativeDownloadWorkerSnapshot" -> {
                            val sinceStateSerial =
                                (call.argument<Number>("since_state_serial") ?: 0L).toLong()
                            // The snapshot can be megabytes late in a large
                            // batch; read and parse it off the main thread.
                            val payload = withContext(Dispatchers.IO) {
                                parseJsonPayload(
                                    DownloadService.getNativeWorkerSnapshot(
                                        this@MainActivity,
                                        sinceStateSerial
                                    )
                                )
                            }
                            result.success(payload)
                        }
                        "releaseMemory" -> {
                            withContext(Dispatchers.IO) {
                                coreBackend.releaseIdleResources()
                            }
                            result.success(null)
                        }
                        "releaseMemoryUnderPressure" -> {
                            withContext(Dispatchers.IO) {
                                coreBackend.releaseMemoryUnderPressure()
                            }
                            android.util.Log.d("SpotiFLAC", "Backend memory pressure release completed")
                            result.success(null)
                        }
                        "runPostProcessingV2" -> {
                            val inputJson = call.argument<String>("input") ?: ""
                            val metadataJson = call.argument<String>("metadata") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                val inputObj = if (inputJson.isNotBlank()) JSONObject(inputJson) else JSONObject()
                                val uriStr = inputObj.optString("uri", "")
                                val pathStr = inputObj.optString("path", "")
                                val effectiveUri = when {
                                    uriStr.startsWith("content://") -> uriStr
                                    pathStr.startsWith("content://") -> pathStr
                                    else -> ""
                                }

                                if (effectiveUri.isNotBlank()) {
                                    runPostProcessingSafV2(effectiveUri, metadataJson, inputObj.optString("item_id", ""))
                                } else {
                                    if (pathStr.isNotBlank()) {
                                        inputObj.put("name", File(pathStr).name)
                                        inputObj.put("is_saf", false)
                                    }
                                    coreBackend.runPostProcessing(inputObj.toString(), metadataJson)
                                }
                            }
                            result.success(response)
                        }
                        "setLibraryCoverCacheDir" -> {
                            val cacheDir = call.argument<String>("cache_dir") ?: ""
                            withContext(Dispatchers.IO) {
                                coreBackend.setLibraryCoverCacheDirectory(cacheDir)
                            }
                            result.success(null)
                        }
                        "scanLibraryFolderToNDJSONFile" -> {
                            val folderPath = call.argument<String>("folder_path") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                safScanActive = false
                                val count = coreBackend.scanLibraryFolderToNdjsonFile(
                                    folderPath,
                                    outputPath,
                                )
                                mapOf(
                                    "path" to outputPath,
                                    "count" to count,
                                    "error_count" to JSONObject(coreBackend.getLibraryScanProgress())
                                        .getInt("error_count"),
                                )
                            }
                            result.success(response)
                        }
                        "scanLibraryFolderIncremental" -> {
                            val folderPath = call.argument<String>("folder_path") ?: ""
                            val existingFiles = call.argument<String>("existing_files") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                safScanActive = false
                                bridgeJsonResult(
                                    coreBackend.scanLibraryFolderIncremental(folderPath, existingFiles)
                                )
                            }
                            result.success(response)
                        }
                        "scanSafTreeToNDJSONFile" -> {
                            val treeUri = call.argument<String>("tree_uri") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                scanSafTree(treeUri, outputPath)
                            }
                            result.success(response)
                        }
                        "scanSafTreeIncremental" -> {
                            val treeUri = call.argument<String>("tree_uri") ?: ""
                            val existingFiles = call.argument<String>("existing_files") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                scanSafTreeIncremental(treeUri, existingFiles)
                            }
                            result.success(response)
                        }
                        "getSafFileModTimes" -> {
                            val uris = call.argument<String>("uris") ?: "[]"
                            val response = withContext(Dispatchers.IO) {
                                getSafFileModTimes(uris)
                            }
                            result.success(response)
                        }
                        "getLibraryScanProgress" -> {
                            val response = withContext(Dispatchers.IO) {
                                if (safScanActive) {
                                    safProgressToJson()
                                } else {
                                    coreBackend.getLibraryScanProgress()
                                }
                            }
                            result.success(parseJsonPayload(response))
                        }
                        "cancelLibraryScan" -> {
                            withContext(Dispatchers.IO) {
                                safScanCancel = true
                                safScanPaused = false
                                coreBackend.cancelLibraryScan()
                            }
                            result.success(null)
                        }
                        "pauseLibraryScan" -> {
                            withContext(Dispatchers.IO) {
                                safScanPaused = true
                                coreBackend.pauseLibraryScan()
                            }
                            result.success(null)
                        }
                        "resumeLibraryScan" -> {
                            withContext(Dispatchers.IO) {
                                safScanPaused = false
                                coreBackend.resumeLibraryScan()
                            }
                            result.success(null)
                        }
                        "readAudioMetadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        val uri = Uri.parse(filePath)
                                        val metadata = readAudioMetadataFromUri(uri)
                                            ?: return@withContext """{"error":"Failed to read SAF audio metadata"}"""
                                        metadata.put("filePath", filePath)
                                        metadata.toString()
                                    } else {
                                        coreBackend.readAudioMetadata(filePath, "", "")
                                    }
                                } catch (e: Exception) {
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "parseCueSheet" -> {
                            val cuePath = call.argument<String>("cue_path") ?: ""
                            val audioDir = call.argument<String>("audio_dir") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (cuePath.startsWith("content://")) {
                                        val uri = Uri.parse(cuePath)
                                        val tempCuePath = copyUriToTemp(uri, ".cue")
                                            ?: return@withContext """{"error":"Failed to copy CUE file to temp"}"""
                                        try {
                                            val audioFileName = extractCueAudioFileName(tempCuePath)

                                            val parentDir = safParentDir(uri)
                                            val audioDoc = if (parentDir != null) {
                                                val cueName = try {
                                                    DocumentFile.fromSingleUri(this@MainActivity, uri)?.name ?: ""
                                                } catch (_: Exception) { "" }
                                                findSafCueAudioSibling(this@MainActivity, parentDir, cueName, audioFileName)
                                            } else {
                                                null
                                            }

                                            if (audioDoc == null || !audioDoc.isFile) {
                                                return@withContext JSONObject()
                                                    .put("error", "Audio file not found for CUE sheet")
                                                    .toString()
                                            }

                                            // Preview parses the CUE text only; the selected audio
                                            // stays in SAF instead of copying a whole album to cache.
                                            val resultJson = coreBackend.parseCueSheetWithResolvedAudio(
                                                tempCuePath,
                                                audioDoc.uri.toString(),
                                            )
                                            JSONObject(resultJson)
                                                .put("cue_path", cuePath)
                                                .toString()
                                        } finally {
                                            try { File(tempCuePath).delete() } catch (_: Exception) {}
                                        }
                                    } else {
                                        coreBackend.parseCueSheet(cuePath, audioDir)
                                    }
                                } catch (e: Exception) {
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error(
                        ForegroundServiceStartPolicy.errorCode(e),
                        e.message,
                        null,
                    )
                }
            }
        }
    }

    private fun registerLibraryStorageReceiver() {
        if (libraryStorageReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                backendChannel?.invokeMethod(
                    "libraryStorageChanged",
                    mapOf("action" to (intent?.action ?: "")),
                )
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_MEDIA_MOUNTED)
            addAction(Intent.ACTION_MEDIA_UNMOUNTED)
            addAction(Intent.ACTION_MEDIA_EJECT)
            addAction(Intent.ACTION_MEDIA_REMOVED)
            addAction(Intent.ACTION_MEDIA_BAD_REMOVAL)
            addDataScheme("file")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }
        libraryStorageReceiver = receiver
    }
}
