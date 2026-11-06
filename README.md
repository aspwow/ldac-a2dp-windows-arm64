# 面向 Windows 的 LDAC A2DP

一个开源的 Windows 蓝牙音频源（`BthA2dp`）替代实现，可将 **LDAC**（索尼的高解析度蓝牙编解码器，最高 990 kbit/s、96 kHz / 24 位）串流到耳机，并以 SBC 作为回退方案。

**English** · [中文](#中文)

## 它能做什么

- **内核驱动**（`driver/LdacA2dp`，KMDF）：
  - 接管耳机的 A2DP 设备，自行在 L2CAP 之上运行 AVDTP（流建立、START/SUSPEND、重连）；
  - 同时也是 Windows 音频端点“耳机（*你的耳机*）”（一条 ACX 渲染回路）；
  - 实现 AVRCP：**绝对音量**（Windows 滑块直接设定耳机音量，不损失 PCM 精度）以及把耳机的**按键**映射为媒体键。
- **编码器服务** `LdacSvc`（用户态）：读取 Windows 渲染到该端点的内容，用 libldac（LDAC，带自适应比特率）或 SBC 进行编码。它作为 Windows 服务运行，支持重连，并可即时应用设置。
- **设置工具** `LdacConfig`（WPF）：编解码器、采样率、质量、声道模式，以及实时状态（编解码器、比特率、ABR 档位、音量、AVRCP、服务）。
- **安装程序**：一个包含 `install.cmd` / `uninstall.cmd` 的包。卸载后耳机回到 Windows 驱动（或回到它们此前的任何 A2DP 驱动）。

## 状态

在 Windows 11 上配合 **QCC5125 DAC** 可正常工作且日常使用中。已在 VirtualBox 测试环境和一台 Intel 网卡的笔记本上测试：
- 在 Driver Verifier 下进行一小时压力测试；
- 睡眠（Modern Standby）以及串流中途关闭耳机；
- 与 Alternative A2DP 的横向对比（`docs/real-machine.md`）。

其他 LDAC 耳机需要把它们的硬件 ID 写进 INF（`driver/LdacA2dp/LdacA2dp.inx`）。它们的 AVDTP/AVRCP 行为可能不同，因此请先在测试环境上验证。

**Windows 11 on ARM（ARM64）：** 驱动、编码服务、设置工具、打包和安装程序端到端均支持 ARM64（见“构建”）。内核路径本身是与架构无关的代码；在投入日常使用前，请像对待任何新硬件一样，先在 ARM64 测试虚拟机上用你的耳机验证 ARM64 构建。

## ⚠ 测试签名的驱动

该驱动使用自制测试证书签名。自 Windows 10 1607 起，开启 Secure Boot 的内核驱动只有经 Microsoft 签名才能加载（认证签名需要 EV 代码签名证书）。要使用这个构建，你必须：

1. 在 UEFI 中关闭 Secure Boot；
2. 以管理员身份运行 `bcdedit /set testsigning on` 并重启；
3. 从安装包中运行 `install.cmd`。

安装程序本身从不修改启动设置。测试模式会降低启动时的保护力度，一些反作弊软件会拒绝在此模式下运行。还原方法：卸载，`bcdedit /set testsigning off`，重新开启 Secure Boot。LDAC 属于索尼；在产品中使用需要索尼的认证（见 NOTICE）。

**Windows on ARM（ARM64）：** 所有内容也都能为 ARM64 构建（驱动、服务、工具——见“构建”），但有两点是 ARM64 特有的注意事项：`bcdedit /set testsigning on` 只在固件允许你关闭 Secure Boot 时有帮助（部分 ARM64 笔记本将其锁定——在那里测试签名的驱动根本无法加载，只有 Microsoft 签名的构建才能用；ARM64 虚拟机没问题）；另外安装包绝不会混合架构：`install.ps1` 会比较驱动的 PE 机器类型与正在运行的系统，架构不匹配时拒绝安装。

## 构建

要求：
- Windows 11（x64 或 ARM64——项目完全支持 Windows on ARM）；
- Visual Studio 2022 或更高版本，并安装“使用 C++ 的桌面开发”；ARM64 还需要 **“VC++ ARM64 生成工具”** 组件（`Microsoft.VisualStudio.Component.VC.Tools.ARM64`）——在 Windows on ARM 电脑上原生使用，或从 x64 电脑交叉编译 `x64_arm64`；
- 构建驱动需要 WDK 10.0.26100 或更高版本（含 ACX 1.1）以及 VS 组件“Windows Driver Kit”（ARM64 驱动构建使用 `Microsoft.Windows.WDK.ARM64` 库——已安装或从 NuGet 还原，见 `driver/packages.config`）；
- 构建工具需要 .NET 10 SDK。

```bat
build.cmd                      :: 主机架构：协议核心、编解码器、服务、测试（CMake + Ninja）
build.cmd arm64                :: 同上，但为 ARM64 交叉编译 -> build_arm64\（在 x64 主机上跳过测试）
build_driver.cmd Release       :: 面向主机架构的 KMDF 驱动（ARM64 电脑则构建 ARM64）
build_driver.cmd Release ARM64 :: 面向 ARM64 的驱动 -> build\LdacA2dp\ARM64\Release\LdacA2dp\
powershell -ExecutionPolicy Bypass -File tools\package\make-package.ps1             :: x64 安装包 + 测试签名
powershell -ExecutionPolicy Bypass -File tools\package\make-package.ps1 -Arch arm64 :: ARM64 安装包（驱动 .sys、ldacsvc.exe、win-arm64 版 LdacConfig.exe）-> build\package\*.zip
```

每个产物都是架构专属的，且安装程序会核对包与机器，因此要为 ARM64 设备构建 ARM64 包（在设备本身上构建最省事：所有脚本默认使用主机架构）。

文档（中文）：
- `docs/1-JBL Live 780NC LDAC 参考会话.md`
- `docs/2-笔记本实测与 Alternative A2DP 对比.md`
- `docs/3-设置与状态文件格式.md`
- `docs/4-阶段5 音频来源方案.md`
- `docs/5-LdacA2dp 驱动测试台.md`
- `docs/6-编码验证.md`


## 许可

Apache License 2.0（见 `LICENSE`）。第三方代码：libldac（AOSP，Apache 2.0）和 AOSP SBC 编码器（Apache 2.0），见 `NOTICE`。与索尼、HARMAN/JBL 或 Microsoft 无隶属关系。

---

## 俄语

Windows 自带 A2DP 源（`BthA2dp`）的自主替代实现：AVDTP 信令、LDAC 编码（来自 AOSP 的 libldac）与作为备选的 SBC、自有的音频设备以及 AVRCP（绝对音量、耳机按键）。驱动使用测试证书签名，因此需要 Windows 的测试模式；详见上文及 `installer/README.txt`。

## 目录结构

| 路径 | 说明 |
|---|---|
| `avdtp/` | 用 C 编写的协议核心，无堆、无 CRT：AVDTP 帧、分片、能力、LDAC/SBC、源状态机、媒体包；AVRCP/AVCTP（`avrcp.c`）。同一套源码也被编译进 KMDF 驱动。 |
| `avdtp/tests/` | 单元测试、耳机模拟器（`sim_sink`，复现 JBL Live 780NC）以及真实会话回放（`test_replay`）。 |
| `driver/LdacA2dp/` | 耳机 KMDF 驱动：A2DP（通过 BRB 的 L2CAP、AVDTP 核心、ACX 音频设备、供编码服务使用的 IOCTL）与 AVRCP（音量、通过 VHF 的按键）。面向 JBL Live 780NC 的 INF。 |
| `service/` | `ldacsvc` / 服务 `LdacSvc`：从驱动端点（或 WASAPI 环回、WAV）取音频 → 重采样 → LDAC + ABR 或 SBC → 将媒体包送入驱动（IOCTL）或送入信道模拟；读取 `settings.json`，为设置工具写入状态。 |
| `tools/hci/` | 蓝牙日志解析：`btvs` → pcap、ETL → btsnoop、L2CAP/AVDTP/媒体解码器。 |
| `tools/ldacenc/` | WAV → A2DP 的 LDAC 包、无线信道模拟与 ABR。 |
| `ui/LdacConfig/` | 设置工具（WPF、.NET 10、Fluent 主题）：编解码器、采样率、质量、声音结束后的保持时间；当前状态——编解码器、质量、音量、AVRCP、服务。 |
| `third_party/libldac` | AOSP `external/libldac`（Apache-2.0），提交 `eeee1a3f`。 |
| `third_party/sbc_encoder` | AOSP 的 SBC 编码器（`system/embdrv/sbc/encoder`，Apache-2.0），见 `SOURCE.md`。 |
| `tools/stand/` | 用测试证书对驱动签名、测试虚拟机、负载、测量（`docs/test-stand.md`）。 |
| `tools/package/`、`installer/` | 安装包构建及安装程序本身（`install.cmd`、`uninstall.cmd`）。 |
| `third_party/compat` | 使 libldac 能用 MSVC 编译的兼容垫片。 |

## 构建

```bat
build.cmd
```

它会构建 C 部分（通过 `vswhere` 找到 Visual Studio 的 CMake + Ninja）并运行测试。参数为目标架构：`build.cmd x64` 或 `build.cmd arm64`（默认是机器架构；arm64 构建输出到 `build_arm64\`，而在 x64 主机上会跳过测试，因为 arm64 二进制在那里无法运行）。需要 VS 组件：ARM64 需要“用于 ARM64 的 VC++ 生成工具”（在 Windows on ARM 上一切原生构建，从 x64 机器则通过 `x64_arm64` 交叉编译）。设置工具：

```bat
dotnet build ui\LdacConfig -c Release
```

驱动（需要 WDK 10.0.26100+ 及 ACX 1.1，以及 VS 组件“Windows Driver Kit”，ARM64 还需 ARM64 工具），产物位于 `build\LdacA2dp\<平台>\<配置>\LdacA2dp\`（`.sys`、`.inf`、`.cat`，未签名）：

```bat
build_driver.cmd Debug              :: 机器架构（在 ARM64 电脑上为 ARM64）
build_driver.cmd Release ARM64      :: 面向 Windows 11 on ARM 的驱动
```

## 安装包

```bat
powershell -ExecutionPolicy Bypass -File tools\package\make-package.ps1              :: 面向机器架构的安装包
powershell -ExecutionPolicy Bypass -File tools\package\make-package.ps1 -Arch arm64  :: 面向 Windows 11 on ARM 的安装包
```

脚本会构建服务（含测试）、所选架构的 Release 驱动并用测试证书对其签名。设置工具则发布为单个自包含 exe（`win-x64` 或 `win-arm64`）。安装包始终只针对一种架构；安装程序会将其与机器核对。在 ARM64 设备上请注意：只有当 UEFI 允许关闭 Secure Boot（或在虚拟机中）时，测试签名才有效。产物为 `build\package\LdacA2dp-<版本>-<架构>\` 及 `.zip`：`install.cmd`、`uninstall.cmd`、面向用户的 `README.txt`（`installer/`）、驱动、`ldacsvc.exe`、`LdacConfig.exe`。

- **`install.cmd`** 请求管理员权限并检查是否为 Windows 11 22H2+。对于测试签名的驱动，它要求已启用测试模式，但自己不会去启用。接着它会信任安装包的测试证书，并把文件放入 `%ProgramFiles%\LdacA2dp`。驱动会装到受支持的耳机上，`LdacSvc` 服务以驱动所接管的耳机地址注册。此外还会在“开始”菜单创建快捷方式，并在“应用”中新增一条记录。再次运行会就地进行更新安装。
- **`uninstall.cmd`**（或“设置 → 应用”）会移除服务、所有驱动程序包（耳机回到 Windows 驱动）、证书、文件、快捷方式和记录。`%ProgramData%\LdacA2dp` 中的设置会保留，`-RemoveSettings` 可将它们一并删除。

已在测试环境验证：手动安装后的卸载、安装、通过“应用”记录的卸载、再次安装以及覆盖更新。

## ldacenc

```bat
build\ldacenc.exe in.wav --quality hq|sq|mq|abr [--mtu 679] [--raw out.ldac] [--packets out.bin] [--link 0:1500,5:550,20:1500]
```

`--link` 按时间设定信道带宽（秒:千比特/秒）；在 `abr` 模式下，发送队列的深度以与 Android 相同的方式驱动 libldac 的自适应比特率。

已验证的结果（96 kHz / 24 位，MTU 679）：HQ 990、SQ 660、MQ 330 kbit/s；44.1 kHz SQ 606 kbit/s。ABR：信道收窄时 HQ → SQ → Q0（492）→ Q1（396）→ MQ，每上升一档大约需要在稳定连接约 6 秒后才会回升。

## ldacsvc

```bat
build\ldacsvc.exe --address 12:34:56:78:9A:BC --source loopback --sink null --link 0:1500,8:450,16:1500
```

作为 Windows 服务（`LdacSvc`，自动启动，以 SYSTEM 身份运行；需要管理员权限）：

```bat
build\ldacsvc.exe install --address 12:34:56:78:9A:BC [--source endpoint|loopback[:名称]]
build\ldacsvc.exe uninstall
```

服务会等待 `LdacA2dp` 设备并维持会话：在连接断开、睡眠或驱动重启之后都会重新开始。对于耳机自己发起的流，它会在一秒内接管。服务把自己的 CONNECT 绑定到蓝牙连接上。如果在连接后 2 秒内耳机没有自行打开流，则由服务打开；在没有耳机时它不会去呼叫它们。已在测试环境用 JBL Live 780NC 验证：关机、断开 66 秒、开机——就在耳机连上的那一秒流又重新开始了。在耳机已连接时的失败尝试会以最长一分钟的间隔重试。来自设置工具的更改会即时生效：采样率、声道和编解码器会重新协商流，质量与 ABR 只改变编码器。由驱动以他人的设置启动的流，服务会按其自身设置重新协商一次。删除或更新驱动时，服务会关闭句柄（query-remove 通知），因此无需重启。日志位于 `%ProgramData%\LdacA2dp\ldacsvc.log`。

`--sink driver`（默认）配合已安装的 LdacA2dp 驱动工作，`--sink null` 模拟无线信道，可在没有驱动的情况下验证一切。`--source endpoint`（配合驱动时为默认）获取应用程序输出到驱动端点“耳机（LDAC A2DP Source）”的声音：一旦有数据流动就发出 START，数据停止后 3 秒发出 SUSPEND。`--source loopback[:设备名]` 捕获在另一输出设备上播放的内容，`--source wav:文件` 实时播放文件；对这两种，START 在声音出现时发送，SUSPEND 在静音 3 秒后发送；ABR 不会把质量提升到高于设置中选择的水平。

## 各阶段状态

- [x] 阶段 2：libldac 在 Windows 下编译成功，编码工具可用，包大小适配 MTU。
- [x] 阶段 3：AVDTP 逻辑在模拟器上验证（LDAC、回退到 SBC、AVDTP 1.2 对端、来自耳机侧的配置、delay report、超时）。
- [x] 阶段 6（部分）：带服务状态、AVRCP 和音量的设置工具；设置格式见 `docs/settings-format.md`；安装包（`tools/package/make-package.ps1`、`installer/`）。
- [x] 在 JBL Live 780NC 上的 SBC：服务按设置重新协商流（SBC 48 kHz、联合立体声、bitpool 53、每包 5 帧、357 kbit/s），传输无丢包，听感干净；AVRCP 在 SBC 下也能工作。
- [x] 阶段 1：通过 `btvs` 与 JBL Live 780NC 的 LDAC 参考会话——`docs/jbl-live-780nc.md`。
- [x] 解码验证：LDAC——使用开放的 libldacdec（由 `tools/ldacverify` 脚本用 MSVC 构建），SBC——使用 ffmpeg；结果见 `docs/verification.md`。
- [x] 阶段 4：KMDF 驱动 `driver/LdacA2dp` 在硬件上运行（测试虚拟机、Realtek 5.4 网卡、JBL Live 780NC，2026 年 10 月 22 日）：自行协商 LDAC 96 kHz / MTU 679 / 延迟 150 ms，来自 `ldacsvc` 的声音在耳机中可闻，3000 个包无丢失。在 VirtualBox 信道上，ABR 保持在 SQ–Q0。
- [x] 编码服务 `ldacsvc`：LDAC 与 SBC，已在 WAV 和实时声音（环回）的信道模拟下验证，状态会在设置工具中显示；SBC 已用 ffmpeg 解码器核对（SNR 60.9 dB）。测试见 `service_tests`。在硬件上可配合驱动工作，包括作为 Windows 服务运行。
- [x] 测试环境：带 Realtek USB 网卡的 VirtualBox 虚拟机，`docs/test-stand.md`。
- [x] 阶段 7（部分）：以笔记本（Intel 网卡）替代虚拟机，并与 Alternative A2DP 对比——`docs/real-machine.md`：同样是 LDAC 96 kHz，在 Alternative A2DP 报告过载的地方，我们的 ABR 保持在 SQ/Q0 且无丢包；绝对音量；睡眠（Modern Standby）和播放中关闭耳机均已处理；听感“一样或更好”。Charge 6 与 LIVE660NC 未测试：它们不支持 LDAC。
- [ ] 阶段 7（部分）：Driver Verifier 下的负载（40 分钟：播放、暂停、音量、设备与服务重启）无违规、无泄漏。虚拟机重启后，耳机、流、AVRCP 与服务都能自行恢复。尚未测试其他耳机、真实耳机上的 SBC、与 Alternative A2DP 的对比。
- [x] 阶段 6（部分）：服务 `LdacSvc`——自动启动、重连、即时设置、删除驱动时释放；已在测试环境验证。耳机的关机与开机已验证；尚未验证离开覆盖范围和睡眠。尚待完成：把 INF 包与服务、工具一起打包，以及 AVRCP。
- [x] 阶段 5（部分）：Windows 端点“耳机（JBL Live 780NC）”——ACX 回路位于驱动本身，PCM 通过 `IOCTL_LDACA2DP_READ_PCM` 送入服务，编码保留在服务中（方案 C，`docs/stage5-audio-options.md`）。只要 Windows 保持端点流打开，流就维持 START（播放器暂停不会中断声音）。在测试环境可工作。端点按耳机名称命名（“耳机（JBL Live 780NC）”）。自有 AVRCP：绝对音量（Windows 滑块 ↔ 耳机音量），耳机按键作为 Windows 媒体键（VHF）。
