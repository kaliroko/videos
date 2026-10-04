package com.metamorphosis.bilibiliglass

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
import kotlin.math.min

class MainActivity : FlutterActivity() {

    private var splashView: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var splashRemoved = false

    private val splashStartTime = System.currentTimeMillis()
    /** ★ 最小显示时长：1000ms，让动画完整播出 */
    private val minSplashMs = 1000L
    /** ★ 动画时长：1000ms */
    private val splashAnimMs = 1000L

    /** ★ 完整性校验 MethodChannel */
    private val integrityChannel = "app/integrity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ═══════════════════════════════════════════════════════
        // ★★★ 最先执行：签名校验 ★★★
        //   校验失败：Toast → finishAffinity → killProcess
        //   不区分 debug / release，一律强制校验
        // ═══════════════════════════════════════════════════════
        if (!IntegrityGuard.verifySignature(this)) {
            exitForTampered()
            return
        }

        // ── 原有 splash 逻辑 ────────────────────────────────────
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            showCustomSplash()
            // ★ 兜底：5 秒
            handler.postDelayed({ removeSplash() }, 5000)
        }
    }

    /** 被篡改 → 提示 + 退出 + 杀进程 */
    private fun exitForTampered() {
        try {
            Toast.makeText(
                applicationContext,
                "检测到应用被篡改，即将退出",
                Toast.LENGTH_SHORT
            ).show()
        } catch (_: Exception) {}

        handler.postDelayed({
            try {
                finishAffinity()
                android.os.Process.killProcess(android.os.Process.myPid())
            } catch (_: Exception) {
                try {
                    System.exit(0)
                } catch (_: Exception) {}
            }
        }, 800)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 原有 splash 逻辑 ────────────────────────────────────
        flutterEngine.renderer.addIsDisplayingFlutterUiListener(
            object : FlutterUiDisplayListener {
                override fun onFlutterUiDisplayed() {
                    handler.post { removeSplash() }
                    flutterEngine.renderer.removeIsDisplayingFlutterUiListener(this)
                }

                override fun onFlutterUiNoLongerDisplayed() {}
            }
        )

        // ── 完整性校验通道 ──────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            integrityChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "verifySignature" -> {
                    result.success(IntegrityGuard.verifySignature(this))
                }
                "verifyIntegrity" -> {
                    result.success(IntegrityGuard.verifyIntegrity(this))
                }
                "fullCheck" -> {
                    val fails = IntegrityGuard.fullCheck(this)
                    result.success(fails)
                }
                "getSignatureHash" -> {
                    result.success(IntegrityGuard.getSignatureHash(this))
                }
                "getApkHash" -> {
                    result.success(IntegrityGuard.getApkHash(this))
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
            // ★ 起始 scale 0.7
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

    /**
     * 图标尺寸 = min(192dp, 屏幕短边 × 0.45)，下限 96dp
     */
    private fun calculateIconSize(): Int {
        val dm: DisplayMetrics = resources.displayMetrics
        val density = dm.density
        val shortSideDp = min(dm.widthPixels, dm.heightPixels) / density
        val baseDp = 192f
        val maxDp = shortSideDp * 0.45f
        val finalDp = maxOf(96f, min(baseDp, maxDp))
        return (finalDp * density).toInt()
    }

    /**
     * 移除 splash（带最小显示时长保护）
     */
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
        super.onDestroy()
    }
}