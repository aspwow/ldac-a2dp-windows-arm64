# JBL Live 780NC：LDAC 参考会话

于 2026-10-22 在这台笔记本上录制（Intel Wireless Bluetooth，`USB\VID_8087&PID_0026`）：信源为 Alternative A2DP Driver 1.8.3.1（Luculent，服务 `AltA2DP`），接收端为 JBL Live 780NC（`12:34:56:78:9A:BC`，DID VID 0x02B0 PID 0x0000）。
工具：来自 Bluetooth Test Platform 1.14.0 的 `btvs.exe`，开启完整报文日志（Full Packet Logging）；pcap 流由 `tools/hci/pcap_tcp_dump.py` 录制，由 `tools/hci/avdtp_dump.py` 解析。原始文件位于 `captures/`（未纳入 git：其中含有设备地址）。

## 参考驱动的架构

`AltA2DP` 作为功能驱动安装在 `BTHENUM\{0000110B-0000-1000-8000-00805F9B34FB}_VID&000102B0_PID&0000\…` 上，取代 `BthA2dp`——与我们驱动（阶段 4）的规划方式相同。HFP（`0000111E`）和 AVRCP（`0000110C/110E`）仍由系统自带驱动承担。

根据其 INF（`oem96.inf`）：设备类为 `MEDIA`，绑定到通用 ID `BTHENUM\{0000110b-…}`（即所有 A2DP 设备），`Include = ks.inf, wdmaudio.inf`，接口 `KSCATEGORY_AUDIO/RENDER/TOPOLOGY`（Wave + Topology）注册在蓝牙设备本身上。也就是说，这是一个单一的 AVStream/PortCls 驱动：音频端点和 A2DP 信源是同一个设备，没有单独的虚拟音频设备，也没有用户态服务。

## 耳机的 SEP（DISCOVER / GET_ALL_CAPABILITIES）

| SEID | 编解码器 | 能力（codec info） |
|---|---|---|
| 1 | SBC | `3f ff 02 35`：44.1/48 kHz，支持全部声道模式，块长 4–16，4/8 子带，SNR/Loudness，bitpool 2–53 |
| 2 | AAC | `80 01 8c 84 00 00`：MPEG-2/4 AAC LC，VBR |
| 3 | LDAC | 44.1 / 48 / 88.2 / 96 kHz；单声道 / 双声道 / 立体声 |

所有 SEP 都是音频接收端，且都带 DELAY_REPORTING。耳机支持 GET_ALL_CAPABILITIES（AVDTP 1.3）。

## 交互序列（由信源发起）

```
> L2CAP ConnReq PSM 0x19（信令），耳机 ConfReq MTU=679
> DISCOVER                                  < 3 个 SEP
> GET_ALL_CAPABILITIES 1, 2, 3              < SBC、AAC、LDAC
> SET_CONFIGURATION acp=3 int=1  LDAC 96 kHz 立体声 + DELAY_REPORTING
                                            < ACCEPT
> OPEN 3
                                            < DELAYREPORT 150.0 ms（紧接配置之后）
                                            < ACCEPT OPEN
> L2CAP ConnReq PSM 0x19（媒体），信源 ConfReq flush timeout = 96 ms，
  耳机 ConfReq MTU=679
  ... 约 21 秒静默：只有出现声音时才发送 START ...
> START 3                                   < DELAYREPORT 150.0 ms、ACCEPT
  媒体流
> SUSPEND 3（声音结束立即发送）              < ACCEPT
```

信令字节（标签、类别顺序）与我们的实现逐字节一致——由测试 `avdtp/tests/test_replay.c` 校验。

## 媒体流（LDAC SQ，96 kHz，立体声）

- 接收端 MTU 为 679，包长 **673 字节**（12 字节 RTP + 1 字节头 + 660 字节 LDAC），每包 **3 帧**，125 包/秒，空口速率 674 kbit/s——与我们 `ldacenc --quality sq` 的输出一致。
- RTP：V=2、PT=96、**SSRC=0**，序号从 0 开始。
- **时间戳每帧 LDAC 递增 128**（3 帧 → +384），尽管每帧包含 256 个采样，采样率为 96 kHz。`ldacenc` 已调整为与这一行为一致。
- 首帧头 `aa 73 61 b0`：sync 0xAA，96 kHz，立体声。

## 驱动应借鉴的要点

- 媒体通道 L2CAP：flush timeout 设为 96 ms（过期包由控制器直接丢弃，而不是积压）。
- 在 SET_CONFIGURATION 与 OPEN 之间应等待 DELAYREPORT——耳机会在未等 OPEN 应答时先发来该报文。
- START/SUSPEND 依据是否有声音，而不是 OPEN 后立即执行（`avdtp_source` 中的 `auto_start` 仅供测试使用）。

## 同一记录中的 AVRCP（AVCTP，PSM 0x17）

Windows（自带 `AvrcpTransport`）↔ JBL，由 `tools/hci/avdtp_dump.py` 解析：

- **谁打开通道。** 首次连接时由电脑打开 AVCTP。重新配置 A2DP 时，耳机自己关闭了 AVCTP；当媒体通道重新打开后，耳机又自行将其重新打开。
- **能力查询（CT）。** Windows 请求 `GetCapabilities(EVENTS)`，耳机回复 `BATT_STATUS`、`VOLUME_CHANGED`。Windows 订阅 `VOLUME_CHANGED`，收到 `INTERIM volume=71`（满值 127），此后每收到一次 `CHANGED` 都会重新订阅。
- **耳机发起的请求（TG）。** 耳机会询问 Windows 的能力，订阅 `PLAYBACK_STATUS` 和 `TRACK_CHANGED`，并请求 `GetElementAttributes`，即曲目标题和艺术家。
- **按键**以 `PASS THROUGH` 命令形式到达。

我们对 `PLAYBACK_STATUS` 和 `TRACK_CHANGED` 的应答与 Windows 的应答逐字节一致（测试 `avdtp/tests/test_avrcp.c`）。元数据我们不提供：返回 0 个属性。

## 关于 Windows 协议栈的观察

- 通过 `Windows.Devices.Radios` 重启蓝牙射频后，JBL 的子设备（A2DP/HFP/AVRCP）被删除且没有重建：耳机会连接上，但 17 秒后即断开（`Remote User Terminated`）。用 `pnputil /restart-device` 重启适配器后恢复正常。
- WPR 配置文件 `BluetoothStack.wprp` 只记录 HCI 命令和事件；在 `HKLM\SYSTEM\CurrentControlSet\Services\BthPort\Parameters` 中未设置 `EtwDropLargeEvents=0`、`EtwLogSensitiveData=1`、`MaxEtwBytes`（即 btvs 中的 Full Packet Logging 按钮）之前，协议栈会丢弃 ACL 数据。记录完成后这些参数已被删除：`EtwLogSensitiveData` 会把加密密钥写入 ETW。
- 对 A2DP 设备执行 `pnputil /restart-device`，是在不重启射频的情况下重新完成协商的便捷方式。
