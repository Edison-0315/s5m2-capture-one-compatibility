# S5M2 Compatibility Tool

为 **Lumix S5M2** 创建 **Capture One USB/PTP 兼容副本**的独立 macOS 工具。

An independent, offline macOS utility that creates an experimental Capture One copy for the Lumix S5M2. The installed application remains unchanged.

**当前状态：0.1.0 测试版。跨版本规则识别，不等于所有版本已验证。**

## 下载与使用

前往 [Releases](https://github.com/Edison-0315/s5m2-capture-one-compatibility/releases) 下载 `S5M2-Compatibility-Tool-0.1.0-macOS.zip`。压缩包包含图形应用、源码和说明，不包含 Capture One 或任何授权文件。

1. 打开 `S5M2 Compatibility Tool.app`。
2. 选择自己安装的 `Capture One.app`。
3. 查看检查结果，选择输出文件夹，再点击“创建兼容副本”。
4. 阅读新目录里的说明，退出其他 Capture One 实例，再用独立测试会话验证。

创建需要 **Apple 芯片 Mac、macOS 14 或更高版本**。建议预留至少 4 GB 空间。不需要安装 Python、Xcode 或命令行工具即可使用已编译应用。

生成目录内的应用需要保持 `Capture One.app` 包名。可以移动或重命名整个外层目录。

## 已知兼容性与限制

| 范围 | 当前结果 |
| --- | --- |
| Capture One 16.7.4.24 的已记录 arm64 相机框架 | 已匹配，已有 USB/PTP 实机连接记录 |
| 同一实测配置的后续反馈 | 使用者报告实时取景、连续 20 张拍摄及常用功能正常 |
| 其他 Capture One 版本 | 尚未实机验证；只允许完整匹配规则的构建继续 |
| Intel Mac 相机驱动 | 当前不添加 S5M2 支持；副本中的 x86_64 架构及其代码/数据会保留 |
| 已经包含这一 S5M2 补丁的框架 | 会识别并拒绝重复修改 |
| 无法识别、符号缺失或候选不唯一 | 停止，不尝试猜测修改 |
| 签名绑定的账号权限、没有原有豁免的严格库验证 | 停止，不删除权限或降低保护强行继续 |

**目前未验证所有官方安装、账号与授权配置。** 本地签名副本可能无法登录、授权或通过系统启动检查；工具不处理授权问题。

此测试构建仅有本地签名，**尚未使用 Developer ID 签名或提交 Apple 公证**。下载后的 macOS 首次启动可能被阻止。项目不提供关闭 SIP 或全局 Gatekeeper 的使用步骤。

## 修改方式

工具解析 Mach-O 符号、ARM64 型号初始化指令及 XOR 常量，并确认该型号记录被 `PanasonicFactory::IsSupported` 引用后，在**副本**中把 `DC-S1M2` 改为 `DC-S5M2`。

- 当前规则只修改一个字节；不依赖固定文件偏移或单独的版本号判断。
- **副本中的这一 S1M2 支持项会被占用**；原版不受影响。
- 只重签副本的相机框架和外层应用，保留已有权限及运行标志，不批量重签其他组件。
- 签名后重新校验型号、代码/数据、架构和签名，并核对源文件未变。
- 每个成功副本附带 `Compatibility-Report.json`，记录版本、规则、偏移与文件摘要。

运行时离线，无上传、下载或遥测。工具不会启动 Capture One、连接相机、触发快门、开启实时取景，或修改用户偏好、会话、钥匙串和相机设置。

## 构建与验证

自行构建需要 Apple Command Line Tools：

```sh
sh Source/build.sh
python3 Source/test_rules.py
```

只读检查已有安装：

```sh
"S5M2 Compatibility Tool.app/Contents/MacOS/S5M2Compatibility" --inspect "/Applications/Capture One.app"
```

可选的签名与路径边界测试需要本机有匹配规则的 Capture One。它只对临时测试副本操作，不执行 Capture One：

```sh
python3 Source/test_signing_fences.py "/Applications/Capture One.app"
```

已完成 12 项合成规则测试、3 项签名/路径边界测试和真实安装的图形界面完整副本生成测试。合成测试不含厂商二进制，也不能代替其他 Capture One 版本的实际相机测试。

## 反馈其他版本

请在 Issue 中提供 Capture One 版本、macOS 版本、Mac 芯片类型、工具检查结果，以及功能测试步骤。分享报告前请检查路径等信息；**不要上传 Capture One、授权文件、凭据、相机序列号或个人照片**。

## 更多信息

- [完整使用说明](docs/usage.zh-CN.md)
- [验证记录与尚未覆盖的范围](docs/validation.zh-CN.md)
- [Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

本项目与 Capture One、Panasonic 均无官方关联。产品名称和商标属于各自权利人。
