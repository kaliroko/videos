package com.suisuinian.app

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
    /// 返回 null = 全部通过；否则返回失败原因列表
    fun fullCheck(ctx: Context): List<String>? {
        val fails = mutableListOf<String>()
        if (!verifySignature(ctx)) fails.add("signature")
        if (!verifyIntegrity(ctx)) fails.add("apk_integrity")
        // ★ 原生层 Frida / 抓包检测（在 Flutter 初始化前执行，最可靠）
        fails.addAll(checkFrida())
        fails.addAll(checkCapture())
        return if (fails.isEmpty()) null else fails
    }

    // ── 原生 Frida 检测 ──────────────────────────────────────
    private fun checkFrida(): List<String> {
        val issues = mutableListOf<String>()
        if (checkTracerPid()) issues.add("frida_tracerpid")
        if (checkFridaMaps()) issues.add("frida_maps")
        if (checkFridaFiles()) issues.add("frida_files")
        if (checkFridaProcesses()) issues.add("frida_process")
        return issues
    }

    /** /proc/self/status TracerPid ≠ 0 → ptrace 附加（最可靠的 Frida 信号） */
    private fun checkTracerPid(): Boolean {
        return try {
            File("/proc/self/status").readText()
                .lines()
                .firstOrNull { it.startsWith("TracerPid:") }
                ?.substringAfter(":")
                ?.trim()
                ?.toIntOrNull() ?: 0 > 0
        } catch (_: Exception) {
            false
        }
    }

    /** /proc/self/maps 搜索 Frida 关键词 */
    private fun checkFridaMaps(): Boolean {
        return try {
            val maps = File("/proc/self/maps").readText().lowercase()
            val suspicious = listOf(
                "frida", "gadget", "gum-js-loop", "gum-js", "gmain",
                "gdmain", "linjector", "libfrida", "frida-agent",
                "frida-gadget", "frida-server", "frida-android",
                "fridarpc", "re.frida", "vapor", "sslkillswitch",
                "sslpinning", "fridac",
            )
            suspicious.any { maps.contains(it) }
        } catch (_: Exception) {
            false
        }
    }

    /** 扫描 frida-server / gadget 常见落盘路径 */
    private fun checkFridaFiles(): Boolean {
        val paths = listOf(
            "/data/local/tmp/frida-server",
            "/data/local/tmp/re.frida.server",
            "/data/local/tmp/frida-server-12",
            "/data/local/tmp/frida-server-13",
            "/data/local/tmp/frida-server-14",
            "/data/local/tmp/frida-server-15",
            "/data/local/tmp/frida-server-16",
            "/data/local/tmp/frida-server-17",
            "/data/local/tmp/frida-server-18",
            "/data/local/tmp/frida-server-20",
            "/data/local/tmp/frida",
            "/data/local/tmp/gadget.so",
            "/data/local/tmp/libgadget.so",
            "/data/local/tmp/frida-gadget.so",
            "/data/local/tmp/libfrida-gadget.so",
            "/data/local/bin/frida-server",
            "/data/local/bin/frida",
            "/system/bin/frida-server",
            "/system/bin/frida",
            "/system/xbin/frida-server",
            "/system/xbin/frida",
            "/data/adb/magisk/modules/",
            "/tmp/frida-server",
            "/sdcard/frida-server",
        )
        for (p in paths) {
            if (File(p).exists()) return true
        }
        // 扫描 /data/local/tmp 目录内容
        return try {
            File("/data/local/tmp").listFiles { _, name ->
                name.lowercase().contains("frida") || name.lowercase().contains("gadget")
            }?.isNotEmpty() ?: false
        } catch (_: Exception) {
            false
        }
    }

    /** 扫描 /proc 进程列表，找 frida-server 等进程 */
    private fun checkFridaProcesses(): Boolean {
        val names = listOf(
            "frida-server", "re.frida.server", "frida-gadget",
            "frida-agent", "gum-js-loop", "fridarpc",
            "vapor", "substrate", "libhooker",
        )
        return try {
            File("/proc").listFiles { _, name -> name.toIntOrNull() != null }
                ?.any { procDir ->
                    names.any { suspectName ->
                        runCatching {
                            File("$procDir/comm").readText().trim() == suspectName ||
                            File("$procDir/cmdline").readText().replace("\u0000", " ").lowercase().contains(suspectName.lowercase())
                        }.getOrDefault(false)
                    }
                } ?: false
        } catch (_: Exception) {
            false
        }
    }

    // ── 原生抓包检测 ─────────────────────────────────────────
    private fun checkCapture(): List<String> {
        val issues = mutableListOf<String>()
        if (checkCaptureProcesses()) issues.add("capture_process")
        if (checkProcNetTcp()) issues.add("proc_net_tcp")
        return issues
    }

    /** tcpdump / tshark / socat 进程检测 */
    private fun checkCaptureProcesses(): Boolean {
        val names = listOf("tcpdump", "tshark", "socat", "netcat")
        return try {
            File("/proc").listFiles { _, name -> name.toIntOrNull() != null }
                ?.any { procDir ->
                    names.any { n ->
                        runCatching {
                            File("$procDir/comm").readText().trim() == n ||
                            File("$procDir/cmdline").readText().replace("\u0000", " ").lowercase().contains(n.lowercase())
                        }.getOrDefault(false)
                    }
                } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /** 扫描 /proc/net/tcp{,6} 监听端口是否命中抓包端口 */
    private fun checkProcNetTcp(): Boolean {
        val capturePorts = setOf(
            8888, 8889, 8080, 8081, 9090, 8887, 8886,
            3128, 1080, 1087, 4444, 5678, 19876, 8899,
            8000, 3000, 28080, 4567,
        )
        for (file in listOf("/proc/net/tcp", "/proc/net/tcp6")) {
            try {
                val lines = File(file).readText().split("\n")
                for (i in 1 until lines.size) {
                    val parts = lines[i].trim().split(Regex("\\s+"))
                    if (parts.size < 4) continue
                    val localAddr = parts[1]
                    val colonIdx = localAddr.lastIndexOf(':')
                    if (colonIdx < 0) continue
                    val portHex = localAddr.substring(colonIdx + 1)
                    val port = portHex.toIntOrNull(16) ?: continue
                    // state=0A 表示 LISTEN
                    if (parts[3] == "0A" && capturePorts.contains(port)) {
                        return true
                    }
                }
            } catch (_: Exception) {}
        }
        return false
    }

    // ── 工具 ─────────────────────────────────────────────────
    private fun sha256Hex(data: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        return md.digest(data).joinToString("") { "%02x".format(it) }
    }
}
