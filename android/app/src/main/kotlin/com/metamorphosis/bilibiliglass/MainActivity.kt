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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import kotlin.math.min

class MainActivity : FlutterActivity() {

    private var splashView: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var splashRemoved = false

    // ★ 4. 最小显示时长（热启动稳定性）
    private val splashStartTime = System.currentTimeMillis()
    private val minSplashMs = 300L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            showCustomSplash()
            // ★ 3. 兜底 3 秒
            handler.postDelayed({ removeSplash() }, 3000)
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

    private fun showCustomSplash() {
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return

        val iconSizePx = calculateIconSize()

        val root = FrameLayout(this).apply {
            setBackgroundColor(0xFF0A0A0F.toInt())
        }

        val icon = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            scaleType = ImageView.ScaleType.FIT_CENTER
            // ★ 2. 起始 scale 0.7
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
            // ★ 1. 时长 500ms
            .setDuration(500)
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
     * ★ 4. 热启动时如果 splash 已显示 < 300ms，等满 300ms 再移除
     */
    private fun removeSplash() {
        if (splashRemoved) return

        val elapsed = System.currentTimeMillis() - splashStartTime
        val remain = minSplashMs - elapsed

        if (remain > 0) {
            // 还没到最小显示时长，延迟执行
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
            // ★ 7. 退场 250ms
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