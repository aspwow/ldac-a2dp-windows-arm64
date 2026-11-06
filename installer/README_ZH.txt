LDAC A2DP
=========

为支持 LDAC 的耳机自制的 Windows 蓝牙音频替代方案：LdacA2dp 驱动
（A2DP、音频设备、AVRCP）、LdacSvc 编码服务，以及 LDAC A2DP 设置工具。

支持的耳机：JBL Live 780NC，以及设备 VID 0x000A / PID 0xFFFF
（该列表可在 driver\LdacA2dp\LdacA2dp.inx 中扩展——就是「设备管理器」中的完整
hardware ID）。

要求：Windows 11 22H2 或更高版本。安装包针对特定架构编译（x64 或 ARM64——见包名和
arch.txt）；安装程序会核对驱动、服务与实用工具是否与系统匹配。

安装
  1. 在 Windows 设置（蓝牙和其他设备）中配对耳机。
  2. 运行 install.cmd 并确认管理员权限请求。
  声音设备列表中将出现「耳机(<耳机名称>)」。
  设置：开始菜单 > LDAC A2DP。

本版本的驱动由测试证书签名。Windows 仅会在测试模式下加载它，而是否启用该模式由你自己
决定：在管理员命令行中执行 "bcdedit /set testsigning on"，然后重启。若启用了
Secure Boot，需先在 UEFI 中将其关闭。在 Windows on ARM 上，并非总能关闭 Secure Boot
（部分设备的 Secure Boot 被固件锁定）——这种情况下测试版无法加载，需要微软的签名；
在 ARM64 虚拟机中测试模式可以正常运行。

安装程序不会自行更改启动参数；如果测试模式未开启，它将停止运行。

卸载
  设置 > 应用 > LDAC A2DP > 卸载，或运行 uninstall.cmd。
  耳机将恢复使用 Windows 驱动。设置会保留在
  %ProgramData%\LdacA2dp（"uninstall.ps1 -RemoveSettings" 会将其一并删除）。
  卸载不会关闭测试启动模式："bcdedit /set testsigning off"。

服务日志：%ProgramData%\LdacA2dp\ldacsvc.log
状态： "%ProgramFiles%\LdacA2dp\ldacsvc.exe" status
