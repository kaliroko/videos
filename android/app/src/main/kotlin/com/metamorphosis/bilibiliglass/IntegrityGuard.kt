package com.metamorphosis.bilibiliglass

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest

object IntegrityGuard {

    // ═══════════════════════════════════════════════════════════
    // 期望值
    //   EXPECTED_SIGNATURE：APK 签名证书 SHA-256（已填好，小写无冒号）
    //   EXPECTED_APK_HASH ：APK 文件 SHA-256（保留 REPLACE_ME 跳过）
    // ═══════════════════════════════════════════════════════════
    private const val EXPECTED_SIGNATURE =
        "ee9fc0055ba0c4158df79d2b9ae24200b7a2873696d457a3684f1647f8740c1f"
    private const val EXPECTED_APK_HASH =
        "REPLACE_ME"

    // ── 签名 SHA-256 ─────────────────────────────────────────
    fun getSignatureHash(ctx: Context): String {
        return try {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ctx.packageManager.getPackageInfo(
                    ctx.packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
            } else {
                @Suppress("DEPRECATION")
                ctx.packageManager.getPackageInfo(
                    ctx.packageName,
                    PackageManager.GET_SIGNATURES
                )
            }

            val sigBytes: ByteArray? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    info.signingInfo
                        ?.apkContentsSigners
                        ?.firstOrNull()
                        ?.toByteArray()
                } else {
                    @Suppress("DEPRECATION")
                    info.signatures
                        ?.firstOrNull()
                        ?.toByteArray()
                }

            if (sigBytes == null) "" else sha256Hex(sigBytes)
        } catch (_: Exception) {
            ""
        }
    }

    // ── APK 文件 SHA-256 ─────────────────────────────────────
    fun getApkHash(ctx: Context): String {
        return try {
            val apk = File(ctx.applicationInfo.sourceDir)
            if (!apk.exists()) return ""
            val md = MessageDigest.getInstance("SHA-256")
            apk.inputStream().use { input ->
                val buf = ByteArray(8192)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    md.update(buf, 0, n)
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            ""
        }
    }

    // ── 校验签名 ─────────────────────────────────────────────
    fun verifySignature(ctx: Context): Boolean {
        if (EXPECTED_SIGNATURE.isEmpty() ||
            EXPECTED_SIGNATURE == "REPLACE_ME") {
            return true
        }
        val actual = getSignatureHash(ctx)
        return actual.isNotEmpty() && actual == EXPECTED_SIGNATURE
    }

    // ── 校验 APK 完整性 ──────────────────────────────────────
    fun verifyIntegrity(ctx: Context): Boolean {
        if (EXPECTED_APK_HASH.isEmpty() ||
            EXPECTED_APK_HASH == "REPLACE_ME") {
            return true
        }
        val actual = getApkHash(ctx)
        return actual.isNotEmpty() && actual == EXPECTED_APK_HASH
    }

    // ── 综合 ─────────────────────────────────────────────────
    /// 返回 null = 全部通过；否则返回失败原因
    fun fullCheck(ctx: Context): List<String>? {
        val fails = mutableListOf<String>()
        if (!verifySignature(ctx)) fails.add("signature")
        if (!verifyIntegrity(ctx)) fails.add("apk_integrity")
        return if (fails.isEmpty()) null else fails
    }

    // ── 工具 ─────────────────────────────────────────────────
    private fun sha256Hex(data: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        return md.digest(data).joinToString("") { "%02x".format(it) }
    }
}