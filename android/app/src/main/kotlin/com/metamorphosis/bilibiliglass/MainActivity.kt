package com.metamorphosis.bilibiliglass

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

class MainActivity : FlutterActivity() {

    private var splashView: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var splashRemoved = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ★ 自适应：Android 12+ (API 31) 用系统 API，以下走自定义
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            showCustomSplash()
            // 兜底：5 秒后无论如何移除
            handler.postDelayed({ removeSplash() }, 5000)
        }
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
    }

    /**
     * Android 11 及以下：模拟 Android 12 原生 SplashScreen
     *
     * 精确还原 Android 12 的规格：
     *  - 背景色： @android:color/black
     *  - 图标尺寸：192dp（Android 12 容器内实际显示尺寸）
     *  - 图标初始状态：scale = 0.6, alpha = 1（立刻可见，无 alpha 淡入）
     *  - 动画时长：1000ms（Android 12 默认 windowSplashScreenAnimationDuration）
     *  - 曲线：PathInterpolator(0.2, 0, 0, 1)  ← Material 3 Emphasized Decelerate
     *  - 无回弹（Overshoot 是错的）
     */
    private fun showCustomSplash() {
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return

        // 黑底容器
        val root = FrameLayout(this).apply {
            setBackgroundColor(0xFF0A0A0F.toInt())
        }

        // 图标：初始 scale = 0.6，alpha = 1（立刻可见）
        val icon = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            // ★ 关键：scale 0.6 起步，alpha 直接 1
            scaleX = 0.6f
            scaleY = 0.6f
            alpha = 1f
        }

        // ★ 192dp 图标（匹配 Android 12 规格）
        val size = (192 * resources.displayMetrics.density).toInt()
        val lp = FrameLayout.LayoutParams(size, size).apply {
            gravity = Gravity.CENTER
        }
        root.addView(icon, lp)
        content.addView(root)

        splashView = root

        // ★ 动画曲线：Material 3 Emphasized Decelerate
        //   对应 Android 12 SplashScreen 原生使用的曲线
        val m3Easing = PathInterpolator(0.2f, 0f, 0f, 1f)

        // ★ 只做缩放，不做 alpha 淡入（Android 12 的实际行为）
        icon.animate()
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(1000)   // ★ Android 12 默认时长
            .setInterpolator(m3Easing)
            .start()
    }

    /**
     * 淡出 Splash（Flutter 首帧渲染完成后调用）
     * Android 12 的退场：200ms + LinearOutSlowIn 曲线
     */
    private fun removeSplash() {
        if (splashRemoved) return
        splashRemoved = true

        val view = splashView ?: return
        // ★ 退场曲线：Material 3 Emphasized Accelerate
        val fadeOutEasing = PathInterpolator(0.4f, 0f, 1f, 1f)

        view.animate()
            .alpha(0f)
            .setDuration(200)   // Android 12 退场约 200ms
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
