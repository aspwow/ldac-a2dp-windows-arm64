# LdacA2dp 驱动的测试台

驱动**只能安装到虚拟机中**：内核驱动出错会导致蓝屏，而 `testsigning` 会削弱系统防护。工作用笔记本上不启用上述任何一项。

## 1. 硬件与虚拟机

- **独立的 USB 蓝牙适配器**，支持 BR/EDR 和 EDR 2/3 Mbit/s（LDAC 面向 2-DH5 包设计）：采用 Intel AX2xx、Realtek RTL8761B/BU 的适配器均可。笔记本内置的 Intel 适配器留给宿主机使用。
- **VMware Workstation Pro**（个人使用免费）或 VirtualBox：两者都能把 USB 设备直通给客户机。Hyper-V 不适用——它没有 USB 直通功能。
- 客户机：Windows 11 x64。每次安装驱动之前都要**给虚拟机打快照**。

## 本机上测试台是如何搭起来的（2026-10-22）

VirtualBox 中的虚拟机 `LdacTestVM`，**Realtek Bluetooth 5.4（`0BDA:A728`）**适配器通过 USB 过滤器直通，账户 `tester`（密码见 `btp/vm-credentials.txt`，不在 git 中）。需要绕过的几点：

1. **宿主机上的 Hyper-V/VBS。** VirtualBox 运行在 Hyper-V 之上（NEM 后端）时不会给客户机提供 x2APIC，双核的 Windows 11 25H2 无法启动。已禁用：组件 `VirtualMachinePlatform` 以及 `bcdedit /set hypervisorlaunchtype off`，然后重启（恢复方式：`Enable-WindowsOptionalFeature ... VirtualMachinePlatform` 和 `hypervisorlaunchtype auto`）。
2. **VirtualBox 7.2.x + Windows 11 25H2 且 vCPU ≥2 时：** 在这台笔记本（i5-1155G7）上，WinPE 和 Windows 在任何设置下都会在启动时卡死：2–3 核、x2APIC、嵌套分页、`ExitOptimizationEnabled`，7.2.22 和 7.2.2 都试过。用**1 个核**时一切正常——虚拟机以单核运行。安装的是 VirtualBox **7.2.2**。
3. **Windows 11 25H2 安装程序**拒绝在单核上安装，`LabConfig` 也无法绕过。因此从 WinPE 手动部署 Windows（在安装程序界面按 Shift+F10）：`diskpart`（clean → GPT → EFI 200 MB → MSR → Windows）、`dism /Apply-Image ... /Index:4`、`bcdboot W:\Windows /s S: /f UEFI`、`bcdedit /store ... testsigning on`，并从第二个虚拟驱动器（VISO）复制 `unattend.xml`（账户、自动登录、首次登录时的客户机增强功能）。在宿主机上用 `diskpart` 做的分区布局不适用：`specialize` 会报错「File is not system store」。
4. Secure Boot 已关闭（UEFI 密钥库为空），`testsigning` 已开启——桌面上显示「测试模式」。

从宿主机管理客户机——`VBoxManage guestcontrol LdacTestVM run --username tester --passwordfile ...`。这类命令以非管理员权限运行，而且 `guestcontrol` 会从参数中丢弃反斜杠：路径一律用 `/` 书写。

需要管理员权限的步骤通过计划任务 `StandAdmin` 执行。它从 SYSTEM 身份运行 `C:\stand\admin.ps1`，而 `tester` 可以触发它。该任务由以管理员权限运行一次的 `tools\stand\stand-admin-setup.ps1` 注册（Win+R → Ctrl+Shift+Enter → UAC）。之后从宿主机执行：

```sh
tools/stand/run-admin.sh script.ps1 [等待秒数]   # 复制为 admin.ps1、运行并打印输出
```

`ldacsvc status` 打印驱动状态：AVDTP、媒体包、端点、音量和 AVRCP（含最近一次 AVCTP 打开的错误码）。`tools/stand/set-volume.ps1 <百分比>` 设置默认端点的音量。`tools/stand/keylog.ps1` 把媒体键记录到 `C:\stand\keys.log`；它必须在用户会话中运行（`schtasks /it`），而不能通过 `guestcontrol`。

`tools/stand/uia-dump.ps1` 通过 UI Automation 把设置工具窗口中的文本导出到 `C:\stand\uia.txt`（须在用户会话中运行）。这样无需截图即可检查「当前状态」一节。

客户机中的 `tools/stand/stand-status.ps1` 会显示测试台文件、`LdacSvc` 状态、`LdacA2dp` 设备以及服务日志的末尾。

虚拟机没有自己的声卡。装了阶段 5 的驱动后，其中会有端点「耳机（LDAC A2DP Source）」，测试声音最方便就是送入该端点：通过 `guestcontrol` 执行 `(New-Object Media.SoundPlayer 'C:/stand/beeps.wav').PlaySync()`。`captures/beeps.wav` 是 −12 dB 的 20 秒提示音；`tone.wav` 太轻（−46 dB）。

## 2. 客户机准备（仅一次）

1. 直通适配器：VMware → VM → Removable Devices → 适配器 → Connect（最好勾选「自动连接」）。
2. 安装适配器驱动，在「设备管理器」中确认蓝牙工作正常。
3. 在**虚拟机内部**配对 JBL Live 780NC（支持多点连接的耳机会记住多个信源）。确认通过 `BthA2dp` 的系统声音可用——这是基准点。
4. 在客户机操作系统中，以管理员身份：
   ```bat
   bcdedit /set testsigning on
   ```
5. 内核调试器（二选一）：
   - **通过网络（KDNET）**：在客户机中执行 `kdnet.exe <宿主机 IP> 50000`（来自 `C:\Program Files (x86)\Windows Kits\10\Debuggers\x64`，连同 `VerifiedNICList.xml` 一起复制到客户机），该命令会给出密钥；在宿主机上执行 `windbg -k net:port=50000,key=<密钥>`。虚拟机的网卡必须是模拟的 Intel e1000e；
   - **通过 COM 端口**：在 VMware 中添加 Serial Port → 命名管道 `\\.\pipe\ldacdbg`（this end is the server，the other end is an application）；在客户机中执行 `bcdedit /debug on` 和 `bcdedit /dbgsettings serial debugport:1 baudrate:115200`；在宿主机上执行 `windbg -k com:pipe,port=\\.\pipe\ldacdbg,resets=0,reconnect`。
6. 重启客户机。

## 3. 构建与打包（在宿主机上）

```bat
build.cmd
build_driver.cmd Debug
powershell -ExecutionPolicy Bypass -File tools\stand\sign-driver.ps1 -Configuration Debug
tools\stand\make-bundle.cmd Debug
```

`sign-driver.ps1` 会在当前用户的证书存储中创建一次证书 `CN=LdacA2dp Test`，并为 `.sys` 和 `.cat` 签名。把 `build\stand` 文件夹复制到客户机中。

## 4. 在客户机中安装

```powershell
.\install-on-vm.ps1            # 信任证书 + pnputil /add-driver /install
.\install-on-vm.ps1 -Uninstall # 回退
```

脚本在 `testsigning` 未开启时会拒绝运行。结束时它会显示是哪个驱动在服务耳机的 A2DP 设备：应当是 `LdacA2dp` 服务。若仍为 `BthA2dp`——重新连接耳机，或执行 `pnputil /scan-devices`。

安装后应立即启用 Driver Verifier（并重启）：

```bat
verifier /standard /driver LdacA2dp.sys
```

## 5. 验证

1. 驱动在启动时会自行协商流（与 Alternative A2DP 一样）：DISCOVER → GET_ALL_CAPABILITIES → SET_CONFIGURATION LDAC 96 kHz → OPEN。
2. 目前声音仍由服务送入（驱动还没有自己的音频设备）：
   ```bat
   ldacsvc.exe --address 12:34:56:78:9A:BC --source wav:test.wav --sink driver -v
   ```
   或 `--source loopback:<虚拟机中输出设备的名称>`。输出中包含协商好的编解码器、采样率、MTU、延迟；每秒输出包/秒、比特率和队列。
3. 以服务方式运行（自启动、重连、设置即时切换）：
   ```bat
   ldacsvc.exe install --address 12:34:56:78:9A:BC --source wav:C:/stand/tone.wav
   ldacsvc.exe uninstall
   ```
   日志位于 `%ProgramData%\LdacA2dp\ldacsvc.log`（上一次运行在 `.log.1`），每分钟输出一行比特率信息。
4. 空口日志：在客户机中运行 `btvs.exe -mode wireshark -remote on`，配合 `tools\hci\pcap_tcp_dump.py`，解析用 `tools\hci\avdtp_dump.py`。与参考记录 `docs/jbl-live-780nc.md` 对比。
5. WDF 日志：在 WinDbg 中执行 `!wdfkd.wdflogdump LdacA2dp`。

## 6. 应优先检查的项目

| 项目 | 查看位置 | 预期 |
|---|---|---|
| L2CAP 服务器已注册 | `LDACA2DP_STATUS.ServerRegistered` | 1 |
| 媒体通道 MTU | 状态中的 `MediaMtu` / `ldacsvc` 输出 | 679（JBL） |
| 信令顺序 | `avdtp_dump.py` | 与参考一致，逐字节相同 |
| 耳机自行打开 AVDTP | 在驱动已安装时关闭/开启耳机 | `SignalingIncoming = 1`，流协商成功 |
| 媒体通道丢失 | 带着耳机走到连接范围之外 | ABORT、`LastError`、重新连接 |
| 服务释放驱动 | 在 `LdacSvc` 运行时执行 `pnputil /restart-device` | 无需重启即可重启，日志中出现「the device is being removed」，随后是新会话 |
| 设置变更 | 在工具中修改采样率 / 质量 | 采样率：流重新协商；质量：新编码器，不中断 |
| 压力测试 | `ldacsvc` 运行 30 分钟以上，Driver Verifier | 无泄漏、无 bugcheck |

## 6а. Driver Verifier 下的压力测试

```bat
verifier /standard /driver LdacA2dp.sys
reg add HKLM\SYSTEM\CurrentControlSet\Services\LdacA2dp\Parameters\Wdf /v VerifierOn /t REG_DWORD /d 1
shutdown /r /t 0
```

重启后，`tools/stand/stress.ps1` 由计划任务 `StandStress` 以 SYSTEM 身份运行（不像 `StandAdmin` 那样有 10 分钟限制）。脚本每 10–25 秒执行一次随机操作：

- 启动播放器（WPF `MediaPlayer`），暂停、继续或停止；
- 修改音量；
- 重启 A2DP 或 AVRCP 设备（`pnputil /restart-device`）；
- 重启 `LdacSvc`。

脚本每分钟写入一次 `ldacsvc status`。日志位于 `C:\stand\stress.log`。泄漏可在 `verifier /query` 中看到，即 `LdacA2dp.sys` 的「当前分配操作」。转储文件请在 `C:\Windows\Minidump` 和 `MEMORY.DMP` 中查找。

2026-10-22 的结果：

- **40 分钟，133 次操作**（8 次重启 A2DP，1 次 AVRCP，5 次服务）。107,658 个媒体包，驱动中无一次故障，无 Verifier 违规，无转储。全部结束后驱动池为 2 次分配（2.5 KB），峰值为 8：无泄漏。
- **启动时及流重开时的包失败：80 次和 227 次。** 单核虚拟机在高负载下，服务线程会有 250–500 ms 得不到 CPU，随后一次性编码超过驱动所能容纳的 32 个包。已通过两项修改修复：
  - 会话线程注册到 MMCSS（「Pro Audio」）；
  - 只要传输处于开启状态，声音中的任何间断都用静音填补，包括程序重新打开流时。

  此后连续 8 次重开流均未出现失败：125 包/秒，SQ。
- **修复服务后的复跑：20 分钟，65 次操作**（2 次重启 A2DP，4 次 AVRCP，1 次服务）。所有会话中 0 次包失败，驱动中 0 次故障。

## 7. 回退

执行 `install-on-vm.ps1 -Uninstall`，若出问题则回退虚拟机快照。工作结束后可在宿主机上删除测试证书：`certmgr.msc` → 个人 → 证书 → `LdacA2dp Test`。
