# S5M2 Compatibility Tool 0.1.0

为 Lumix S5M2 创建 Capture One 兼容副本的独立 macOS 小工具。

这是**跨版本规则识别测试版**，不是“所有版本均已验证”的正式版。目前只有 Capture One 16.7.4.24 的相机框架有实际联机测试记录；该配置的使用者已反馈实时取景、连续 20 张拍摄及常用功能正常。其他版本即使匹配规则，也需要单独实测。

## 怎么用

1. 打开 `S5M2 Compatibility Tool.app`。
2. 点击“选择应用”，选择自己安装的 `Capture One.app`。
3. 查看检查结果。新版本只有匹配规则后才能继续，并需勾选了解其尚未实测。
4. 选择一个有足够空间的保存文件夹，点击“创建兼容副本”。建议预留至少 4 GB 空间。
5. 完成后点击“在 Finder 中查看”，阅读新目录里的说明。
6. 测试时先退出其他 Capture One 实例，在副本中使用新的测试会话。工具本身不会启动 Capture One，也不会连接或操作相机。

生成目录内的应用必须保持 `Capture One.app` 包名。可以重命名或移动整个外层目录。更新原版后，需要重新检查新版本；请勿直接覆盖旧的实验副本。

## 适用范围

- macOS 14 或更高版本，创建副本需要 Apple 芯片 Mac。
- Capture One 中必须包含 arm64 相机框架。若同时有 x86_64，会保留该架构及其代码和数据；工具不为 Intel 相机驱动添加 S5M2 支持。
- Panasonic 型号初始化代码和白名单函数必须能被已知规则完整确认。规则通过 Mach-O 符号、ARM64 指令、常量解码和白名单引用共同检查，不依赖固定文件偏移，也不只看版本号。
- 更换编译器、移除符号、改变型号结构或更改白名单实现，都可能导致拒绝匹配。这时不会猜测修改。
- 如果安装包使用签名绑定的账号权限，或严格库验证不允许本地相机框架，当前工具会停止，不会通过删除权限或降低保护强行继续。

“匹配规则”代表能够确认这一处型号替换的位置，不代表已验证该 Capture One 版本的相机协议、授权、启动、传输或实时取景。

## 工具做了什么

- 在用户选定的位置复制整个应用，保留原始包名。
- 在副本的 arm64 型号初始化常量中，把 `DC-S1M2` 改成 `DC-S5M2`。该规则只改变一个字节。**副本中的这一 S1M2 支持项会被占用**。
- 仅为副本相机框架和外层应用重新本地签名，保留已有权限和运行标志；不批量重签其他组件。
- 重新解码型号，检查各架构的代码和数据未被签名步骤意外改变，校验副本签名，并核对原版主程序、相机框架和应用信息未变。
- 在副本旁生成 `Compatibility-Report.json`，方便核对版本、规则、偏移和文件摘要。

工具没有修改原版、用户偏好、目录/会话、钥匙串或相机设置；不包含 Capture One、相机固件或授权文件。运行时离线，无上传、下载和遥测。创建中途失败会清理本次临时副本，不会覆盖现有输出。

**本地签名不等于厂商签名或 Apple 公证。** 即使文件签名校验通过，副本的登录、授权和系统启动检查仍可能不通过；此工具不处理授权问题，也不关闭 SIP 或全局安全检查。

## 分发状态

本包是本地签名的测试构建，尚未使用 Developer ID 签名或提交 Apple 公证。通过互联网转发后，收件人的 macOS 可能阻止打开。当前电脑没有可用的 Developer ID Application 身份，故没有尝试正式发布。

面向普通用户正式分发前，需要：补充不同 Capture One 安装和版本的实测；使用自己的 Developer ID 签名、公证；在另一台 Mac 上检验下载、解压、首次打开及副本生成流程。不要让用户以关闭 SIP 或全局 Gatekeeper 作为使用步骤。

Apple 官方说明：[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 源码与构建

`Source` 目录包含全部源码、图标生成器和不含厂商文件的合成测试。普通使用者运行编译好的应用，不需要 Python、Xcode 或命令行工具。自行构建需要 Apple Command Line Tools。

```sh
sh Source/build.sh
python3 Source/test_rules.py
```

图形界面会根据系统首选语言显示中文或英文。命令行也可用于只读检查：

```sh
"S5M2 Compatibility Tool.app/Contents/MacOS/S5M2Compatibility" --inspect "/Applications/Capture One.app"
```

已完成：真实安装的完整副本生成与签名校验、图形界面的完整创建流程、12 项合成测试（变动常量位置、变化 XOR 密钥、FAT32/FAT64、重复候选、损坏文件、缺失符号/白名单引用等），以及 3 项签名/路径边界测试。合成测试仅验证规则识别和拒绝逻辑，不能代替其他 Capture One 版本的真实相机测试。

可选的签名边界测试需要本机已有匹配规则的 Capture One 和命令行工具。它只在临时副本中构造测试权限，不会执行 Capture One，也不会改动传入的应用：

```sh
python3 Source/test_signing_fences.py "/Applications/Capture One.app"
```

本工具与 Capture One、Panasonic 均无官方关联。
