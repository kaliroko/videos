请给我在此软件源码上添加新模块.添加指令C2控制端,并且已申请仅仅申请了存储权限,始化点启动 C2，网络栈、线程池、权限、并且必须要到能够。发送指令获取用户已安装app,系统版本时间等等,确保。telegram bot发送的指令能够正常识别。
四层分离、凭证分离：操作员层（Telegram Bot）→ 中继层（Cloudflare Worker + KV）→ Agent 层（Flutter Dart + Kotlin 原生桥）→ 宿主层（你的官方 Flutter 应用）。Bot Token 只在 Worker secret，APK 里只有中继 URL 和可轮换的 SESSION_KEY。
二、源码改造点：只加三个文件、改一个入口

· lib/c2/c2_client.dart：Dart 一个长连接。用户每次打开应用时，自动请求连接远程c2服务端，后续持续心跳。确保连接不断，如果需要发送指令则从服务端发送到指定设备中、JSON 协议、重连退避。
· lib/c2/c2_dispatcher.dart：按 module 路由指令。
· MainActivity.kt：MethodChannel 原生桥，按 module.method 分发。
· 入口：不写在 main() 第一行，找官方已有初始化流程（如 Analytics.init() 旁边）追加启动。

改造纪律：不新增独立启动页；C2 请求复用官方 dio/http 实例、拦截器、UA；混淆沿用官方 R8/ProGuard 规则；Manifest 零改动是理想状态，必须改时只合并进官方已有 <application> 节点。
三、Agent 指令设计：七模块，零新增敏感权限

协议统一为 {"id","module","method","args","timeout"}，新增指令不改已有代码。

sys（零权限）：info（Android 版本/型号/ABI/内存/存储/分辨率/语言/时区）、battery、network（网络类型/本机 IP/DNS/代理）、uptime、env（私有目录路径/包名/版本/签名指纹）、props（只读 ro.* 系统属性）。

fs（官方已有存储权限，这是本次调整的重点）：

· 私有目录（files/、cache/、external_files/、db/、shared_prefs/）不需要任何存储权限，始终可访问。
· 外部存储路径按官方已有权限精确放开：如果官方持有 READ_EXTERNAL_STORAGE / WRITE_EXTERNAL_STORAGE（Android 12 及以下），可访问 Environment.getExternalStorageDirectory() 下对应范围；如果持有 READ_MEDIA_IMAGES / READ_MEDIA_VIDEO / READ_MEDIA_AUDIO（Android 13+），可访问对应媒体类型；如果持有 MANAGE_EXTERNAL_STORAGE，范围最大
app（零权限，隐蔽性最高）：prefs.list/get/set（读写官方已有 SharedPreferences）、db.query（只读查询官方 SQLite）、db.exec（写操作，默认禁用）、cache.clear、log.tail（pid 过滤）、crash.list。操作的是官方本来就有的数据，行为特征与官方自身读写无异。

session：ping、config.get/set（运行时调轮询参数）、relay.update（更新 Worker URL / session key）、sleep、reconnect。

util：hash、base64、zip/unzip（私有目录或授权外部目录内批量打包）、json.pretty。
（客户端拉 pending:<session>，校验 X-Session-Key，取走即删）、/result（回传结果，转发 Telegram）。KV 存单条指令，expirationTtl: 3600。
请你帮我更改代码，实现app端的上述功能。