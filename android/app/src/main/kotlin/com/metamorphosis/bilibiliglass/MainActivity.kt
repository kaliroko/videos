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
import android.view.animation.OvershootInterpolator
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

        // ★ 自适应判断
        // Android 12+ (API 31+) → 系统 SplashScreen API 自动处理
        // Android 11 及以下      → 自定义 View 做缩放动画
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            showCustomSplash()
            // 兜底：5 秒后无论如何移除（防止首帧回调丢失导致永久卡住）
            handler.postDelayed({ removeSplash() }, 5000)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 监听 Flutter 首帧渲染完成 → 淡出自定义 splash
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
     * Android 11 及以下：显示自定义 splash
     * - 黑底 + 居中图标
     * - 图标从 0.5 倍缩放到 1.0 倍（带 Overshoot 回弹）
     * - 淡入 800ms
     */
    private fun showCustomSplash() {
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return

        // 黑底容器
        val root = FrameLayout(this).apply {
            setBackgroundColor(0xFF0A0A0F.toInt())
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // 居中图标（初始 0.5 倍 + 透明）
        val icon = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            scaleX = 0.5f
            scaleY = 0.5f
            alpha = 0f
        }

        val size = (120 * resources.displayMetrics.density).toInt()
        val lp = FrameLayout.LayoutParams(size, size).apply {
            gravity = Gravity.CENTER
        }
        root.addView(icon, lp)

        content.addView(root)
        splashView = root

        // ★ 缩放 + 淡入动画
        icon.animate()
            .scaleX(1f)
            .scaleY(1f)
            .alpha(1f)
            .setDuration(800)
            .setInterpolator(OvershootInterpolator(1.5f)) // 回弹
            .start()
    }

    /**
     * 淡出并移除 splash
     */
    private fun removeSplash() {
        if (splashRemoved) return
        splashRemoved = true

        val view = splashView ?: return
        view.animate()
            .alpha(0f)
            .setDuration(300)
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