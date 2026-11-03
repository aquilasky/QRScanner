# QRScanner 架构

macOS 14+，Swift / AppKit / SwiftUI，无第三方依赖。参考 QR Flick（MIT）及 QRGo 的公开交互说明，代码独立编写。

`NSStatusItem → 捕获会话 → 内存截图 → 覆盖层选择 → Vision → URL/文本处理 → 本地通知`

- 菜单栏左键扫描、右键 NSMenu。LSUIElement 隐藏 Dock。设置仅保留三个开关、两个权限入口及版本号；捕获覆盖层只显示遮罩与选区边框，不显示窗口标题或操作文字。
- ScreenCaptureKit 获取屏幕和窗口列表；扫描前捕获每块显示器一次，排除自身应用。覆盖层显示冻结帧，确保用户所选内容与识别内容一致。
- 每个 NSScreen 对应一个无边框 NSWindow。AppKit 全局坐标（原点左下）和 ScreenCaptureKit 窗口坐标（主屏左上）通过主屏上边界转换；截图裁剪按每屏实际像素比例映射。
- 窗口按屏幕上前后顺序命中，排除桌面、菜单栏和本应用；无候选时选择该显示器。拖动距离超过 5pt 切换矩形；框选限定在起始屏幕，窗口跨屏则拼接各屏交集。
- 覆盖层结束后释放快照。Vision 仅检测 QR；异步识别不阻塞主线程。
- 单 URL 自动打开（可关闭）；多结果使用列表；非网页内容通过结果窗口复制，不自动执行自定义 scheme。通知不包含完整二维码数据，避免敏感 token 出现在锁屏。
- ServiceManagement 读取系统登录项实际状态；UserDefaults 仅保存偏好，不保存截图或扫描历史。
- 屏幕录制与通知权限通过系统 API 请求；权限拒绝时提供明确可操作反馈。登录启动只有用户启用时注册。

构建：Swift Package 编译可执行文件，由 scripts/build.sh 包装为 .app，Launch.command 构建后打开。构建在临时目录准备并签名，同一内容保留现有 bundle；运行中的应用不得被新构建覆盖。默认本机开发使用 ad-hoc 签名，支持 QRSCANNER_SIGN_IDENTITY 指定稳定证书；ad-hoc 的代码身份绑定具体代码，更新后可能重新请求 TCC 授权。外部分发需 Developer ID 与公证。
