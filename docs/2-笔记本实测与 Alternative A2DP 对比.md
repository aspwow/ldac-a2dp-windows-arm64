# 笔记本上的实测与与 Alternative A2DP 的对比（2026-10-22）

笔记本：Windows 11（内部版本 26300），Intel 蓝牙适配器，耳机为 JBL Live 780NC。此前由 Alternative A2DP 1.8.3.1（Luculent Systems）为其提供服务。为进行测试，用户关闭了 Secure Boot 并开启了测试模式（`bcdedit /set testsigning on`）；机器上的 BitLocker 处于关闭状态。将软件包 `LdacA2dp-0.2.295.1846` 通过 `install.cmd` 覆盖安装到 Alternative A2DP 之上。

## 测量结果

声音素材为同一段 20 秒的提示音（`captures/beeps.wav`），由 `tools/stand/play-to.ps1` 播放到「耳机（JBL Live 780NC）」，未改动默认输出设备。

| | Alternative A2DP | LdacA2dp |
|---|---|---|
| 编解码器 | LDAC 96 kHz / 24 bit，SQ 660 kbit/s | LDAC 96 kHz / 24 bit，在 SQ（660）与 Q0（492）之间进行 ABR |
| 通道状态 | 其工具会警告：「检测到通过蓝牙传输数据包时存在高延迟……比特率超出你的系统能力」 | 发送队列 0–1 个包，播放一分钟提示音（7111 个包）以及 9 分钟音乐期间丢弃 0 个包 |
| Windows 中的设备（`tools/stand/endpoint-latency.ps1`） | 周期 10 ms，共享模式缓冲 22 ms，不报告流延迟 | 相同：周期 10 ms，缓冲 22 ms，0 |
| 音量 | 软件音量，与耳机音量分离 | 绝对音量（AVRCP）：Windows 滑块 = 耳机音量 |
| 处理器 | 低于机器本底噪声（约 15%） | 相同 |
| 听感 | — | 「相同或更好」（用户评价） |

这台笔记本的 Intel 适配器大约能承载 600 kbit/s 的有效码流：在 SQ 下队列会增长，ABR 约 4–8 秒后降到 Q0，随后再尝试 SQ。LDAC 档位切换过程中不会中断。Alternative A2DP 则始终停留在 660，并报告存在延迟。

基于 HCI「Number Of Completed Packets」事件做对比未能完成：在没有 `btvs` 完整日志的情况下（而它要求在 ETW 中记录加密密钥，这一点我们在宿主机上不开），协议栈只会给出零星的事件。

## 行为表现

- **睡眠。** 这台机器只有 Modern Standby（S0 低功耗空闲）。在 66 秒睡眠期间与耳机的连接没有断开。唤醒后声音立即播放，无需重新协商，音量保持原样。
- **距离。** 在 10×10 米的住宅内，即使在二楼对角角落连接也不会断开。9 分钟音乐：SQ/Q0，空口 520–640 kbit/s，丢弃 0 个包。
- **在播放音乐时关闭耳机**（而非离开连接范围）：
  - 断连立即被发现；当时在传输中的 48 个包被驱动标记为失败；
  - 耳机关闭期间，服务不会去呼叫它们；
  - 重新开机后，流被耳机在同一秒内拉起，AVRCP 和绝对音量恢复。
- **覆盖安装到 Alternative A2DP 之上。** 我们的 INF 绑定到耳机的完整 ID，优先级高于 Alternative A2DP 的通用 ID。删除我们的软件包后，耳机会回到 Alternative A2DP，后者仍留在驱动仓库中。

## 工具

- `tools/stand/play-to.ps1 -Wav file -Match name` —— 按名称把 WAV 播放到指定设备（共享模式，格式由 Windows 自动转换）；支持中途暂停。
- `tools/stand/endpoint-latency.ps1 -Match name` —— 设备的周期和共享模式的流延迟。
- `tools/hci/nocp.py` —— 依据 `btvs` 记录中的「Number Of Completed Packets」事件计算发送速率；在没有完整日志的宿主机上，这类事件很少。

## 结论

根据用户的决定，笔记本上保留 LdacA2dp，因此在驱动由测试证书签名期间，测试模式将保持开启，Secure Boot 保持关闭。要恢复 Alternative A2DP 可这样做：「设置 → 应用 → LDAC A2DP → 卸载」，然后执行 `bcdedit /set testsigning off`，并在 UEFI 中启用 Secure Boot。
