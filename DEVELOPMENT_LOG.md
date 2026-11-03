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
