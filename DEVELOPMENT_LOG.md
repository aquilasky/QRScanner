# 开发日志

## 2026-11-03 · 初始化
- 用户授权参考开源自行实现；参考 T200 AGENTS.md 及 DEVELOPMENT.md 调整为 Swift 原生应用规范。
- 空项目；本机 Xcode 27.2、Swift 6.4.2。最低运行 macOS 14。
- 第一阶段：原生菜单栏、窗口单击/拖动选区、内存截图与 Vision、默认浏览器、系统通知、登录启动、一键入口。
- 验证预期：单击选择鼠标所指窗口，拖动距离 > 5pt 为矩形；所有方向拖动归一化；HTTP(S) 有主机且无凭据可打开；其他内容仅复制；二维码生成后识别往返一致；取消不触发识别。

## 2026-11-03 · 首版实现与验证
- 独立实现 Swift Package：AppKit 菜单栏及覆盖层、SwiftUI 设置和结果、ScreenCaptureKit 内存快照、Vision QR 识别、HTTP(S) 默认浏览器打开、ServiceManagement 登录启动、UserNotifications。
- 构建入口：Launch.command → scripts/build.sh → build/QRScanner.app（本机 arm64、ad-hoc 签名）。
- 编译阶段修复：入口 MainActor 隔离错误；权限检查 guard 分支可继续执行导致编译错误。均已在最终构建修正。
- 重要原始失败：沙箱内 `./scripts/test.sh` 的 QR 测试在 CIContext.createCGImage 返回 nil，识别尚未执行（.build/tests.log）；主 agent 在平台授权的非沙箱环境运行同一测试，6 项全通过（.build/tests-unsandboxed.log）。未改测试定义或预期。
- 独立测试：gpt-6-luna / medium。初测复现上述沙箱失败；最终用 require_escalated 独立复跑 scripts/test.sh，6 项全通过；scripts/build.sh release 成功，plutil 与 codesign 验证通过。测试角色未改代码或操作 GUI。
- 独立审查：gpt-6.1-sol / medium。发现非 key 显示器覆盖层首次点击被激活行为吞掉（P2）；已添加 acceptsFirstMouse(for:) = true，复核重要问题清零。该修复仍需多屏实机验证。
- Computer Use：Finder 从 Launch.command 进入真实 QRScanner 设置窗口；检查三个设置开关、权限按钮、开始扫描按钮及实际排版；点击开始扫描显示屏幕录制权限引导。
- 用户选择自行开启屏幕录制权限。当前等待用户完成；尚未声称截图/单击/拖动/取消/浏览器打开/通知投递、多屏实机或重登自动启动验证通过。
- 产物无 Apple 公证，仅本机开发；尚未在 Intel 或 macOS 14 实机测试。
- 实现提交：8fd20e5（feature/native-scanner）。测试与复核对应此提交的产品代码；后续仅追加记录。
- 真实设置交互：自动打开链接开关可切换为关闭，随后已恢复开启。应用保留运行供用户授权；屏幕权限操作由用户手动完成，当前不替代用户进行权限变更。
- 合并状态：保留功能分支，等待屏幕录制授权后的真实扫描验收，再合并 main。

## 2026-11-03 · 录屏权限反复请求排查
- 用户反馈系统设置已有 QRScanner 条目仍出现系统录屏请求，类似以前本地音频捕获。截图只能确认条目存在，不能单独确认当前进程获授权。
- 证据：`codesign -d -r- build/QRScanner.app` 显示 designated => cdhash，当前使用 ad-hoc 签名；旧 build.sh 无条件原地 cp 并重签；上轮应用运行后独立测试曾重建包。这会引入磁盘身份与运行进程不一致的风险，不能据此认定是本次异常的唯一原因。
- Apple 官方 TN3127 说明 ad-hoc 的 DR 绑定具体代码版本，不能可靠跨版本跟踪授权；Apple DTS 在论坛 thread/819406 确认此类 ScreenCaptureKit 重新授权问题。
- 修复 scripts/build.sh：暂存目录签名验证、相同内容不部署、运行进程存在或进程检查失败时拒绝替换、替换失败恢复旧包，支持 QRSCANNER_SIGN_IDENTITY。没有创建证书、修改钥匙串或重置 TCC。
- 主 agent 实际重新构建：.build/permission-build.log 输出内容未变保留现有应用；构建前后可执行文件 mtime 与 inode 相同。zsh -n、git diff --check 通过。
- 独立测试 gpt-6-luna / medium：隔离副本与 mock，6场景全部通过：不变保留mtime、运行时拒绝、未运行部署、pgrep异常拒绝、签名失败保留、指定身份完整传参。无真实权限操作；mock不证明真实跨版本TCC保持。
- 独立审查 gpt-6.1-sol / medium：重要问题清零。提醒 ad-hoc 更新仍可能重新授权，切换证书也可能需首次重新授权。
- README/架构同步稳定路径、退出后更新和用户手动权限恢复步骤。尚未重复真实一键GUI/录屏验收，用户此前选择自行操作系统权限；没有把构建流程通过表述为权限故障已实机解决。

## 2026-11-03 · 设置与捕获画面精简
- 按用户截图反馈删除捕获覆盖层的窗口标题、操作说明、底部提示黑框及动态标签，只保留冻结画面、遮罩和选区边框。
- 设置窗口宽度由490pt缩小至360pt，仅保留三个开关、两个权限按钮和版本号；删除品牌图标、宣传语、常驻教程、技术说明、重复扫描按钮和未使用的scan闭包。原行为及错误反馈保留。
- 中断前直接swift build未使用项目缓存环境，出现SwiftShims模块缓存写入权限错误（.build/compact-build.log）。正式验证使用已有scripts/test.sh配置，没有修改测试预期。
- 独立测试 gpt-6-luna / medium：提升权限运行scripts/test.sh，6/6通过；静态确认精简内容及核心交互均保留，未操作GUI。
- 独立审查 gpt-6.1-sol / medium：未发现重要功能回归或明确布局问题，建议实机确认；未修改产品。
- Computer Use：从活动监视器正常退出旧进程；Finder通过Launch.command构建启动新版；绑定com.aquila.QRScanner真实窗口，AX显示仅3开关/2按钮/版本，截图确认完整无裁切；自动打开开关关闭再恢复开启；最后执行关闭设置窗口。
- GUI限制：菜单栏扫描图标未出现在该工具的可操作AX树，尝试菜单栏键盘聚焦无效，绑定SystemUIServer超时。故新版捕获画面、拖动与取消没有通过真实GUI复验，不将静态代码检查当作实测。
- GitHub私有仓库已创建origin=git@github.com:aquilasky/QRScanner.git；用户回复“提交 然后完成前面说的前端改动”后尝试push被自动审批再次拒绝，理由是认为未明确授权向指定仓库上传代码与历史。没有绕过或上传，等待更明确授权。本轮改动先本地提交。

## 2026-11-03 · 应用图标
- 使用内置image_gen生成绿色取景框/简化二维码、浅色圆角底板的应用图标；源PNG和完整提示词保存在Resources，标准10尺寸ICNS由sips/iconutil转换。
- scripts/Info.plist设置CFBundleIconFile=AppIcon；build.sh在签名前复制ICNS，并将图标内容比较纳入不变判断。
- 原始转换失败：沙箱内iconutil报告Invalid Iconset；平台授权的非沙箱环境转换成功，未修改图片或尺寸预期。
- 独立测试 gpt-6-luna / medium：ICNS解析含10尺寸，PNG/plist有效；隔离mock验证不变图标保留mtime及仅图标变化触发部署，2/2通过。
- 独立审查 gpt-6.1-sol / medium：无重要问题，确认资源签名和更新逻辑有效。
- Computer Use：活动监视器正常退出旧进程；Finder从Launch.command构建启动，定位build/QRScanner.app并截图确认列表已显示新图标。codesign --verify --strict通过。
- 菜单栏仍使用现有系统单色符号；新彩色图标用于应用包识别。

## 2026-11-03 · 无二维码仅通知与通知图标排查
- 用户要求去掉“没有发现二维码”空结果窗口：handle([])现在只notify并return。保留真实执行错误详情及实际识别结果操作，避免通知关闭时丢失错误反馈。
- 图标排查：系统LaunchServices只读dump已记录当前bundle路径和AppIcon.icns/CFBundleIconFile，未发现资源缺失；通知图标缺失的唯一根因尚未确认，缓存仅为推测。
- 启动时用Apple公开LSRegisterURL(bundleURL,true)更新当前应用注册，失败记录日志；升级0.1.1/build2，设置从Info.plist读取版本。该更新不能单独证明通知中心图标已修复，未重置权限或重启系统服务。
- 独立测试gpt-6-luna / medium：scripts/test.sh提升权限6/6通过；最终静态核对无二维码只通知、实际错误保留详情、注册和图标关联正确。独立审查gpt-6.1-sol / medium：复核后无未解决重要问题。
- 部署记录：一次构建因旧应用运行被保护逻辑拒绝，未覆盖；Computer Use活动监视器正常退出旧进程，再从Finder一键入口启动。实际应用设置显示v0.1.1，codesign严格验证成功，最后关闭设置窗口保留菜单栏运行。
- 实际空选区通知与通知banner图标未完成GUI复验：当前工具不能绑定菜单栏扫描图标；不将注册成功表述为实际图标显示成功。
