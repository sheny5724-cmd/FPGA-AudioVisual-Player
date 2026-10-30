# 第六项：V19 固化与独立上电

本目录用于将已可正常播放的 V19 写入开发板的启动 Flash。播放器逻辑、TD 工程和 TF 素材格式沿用 V19，屏幕版本仍显示 `FPGA V19`。

## 文件位置

- 固化位流：`competition_recovery_v19.bit`，与 recovery_v19 工程中的位流逐字节一致。
- 原始启动镜像：`competition_recovery_v19.bin`，由 TD 自带转换器导出，用于回读比对。
- 固化操作文件：`competition_recovery_v19_flash.svf`，由 TD 的 ChipLinker 生成，包含擦除、写入和校验步骤，参考频率 1 MHz。
- 源工程：`../recovery_v19/competition_recovery_v19.al`。
- 原启动 Flash 备份：`backup/flash_before_v19.bin`，2 MiB。
- 烧写结果：`FLASH_STATUS.json` 和 `flash_program_*.log`。

本次已完成实际烧写，完整 626777 字节镜像回读一致。2026-10-17 用户确认断电再上电后，图片和音乐均正常自动运行。详细记录见 FLASH_STATUS.json。

## 已确认的硬件

- FPGA：HX4S20C 的 EG4S20BG256，已通过下载器读取确认。
- 启动 Flash：U39，手册标注 W25Q16；实际 JEDEC ID 为 `EF 40 15`，容量 16 Mbit / 2 MiB。
- U39 接专用配置端口；板上的另一片 W25Q64 是用户数据 Flash。
- V19 原始启动镜像为 626777 字节，能放入 U39。
- 不需要为本功能增加 Verilog 控制器或修改引脚约束。

## 烧写完成后，如何确认独立启动

1. 保留当前能正常使用的 TF 卡和 HDMI 连接。
2. 关闭开发板总电源，等待约 5 秒，再打开。
3. 不点击 BitWriter 的 Download，等待原有的初始化和素材加载结束。
4. 应自动显示 V19 图片界面；SW2 打开时，音乐加载完成后应出声。
5. 若要演示自动轮播，将 SW1 打开；SW3、SW4 可关闭以隐藏波形和设置。

需要完全脱离电脑时，可在断电后把 USB 供电线改接稳定的 5 V USB 电源，再打开板卡。开发板手册说明 USB-JTAG 和 USB-UART 均可作为供电入口。只保留一路供电即可，HDMI 和 TF 卡继续连接。

独立运行不需要电脑发送图片或歌曲。上电时 FPGA 从启动 Flash 载入电路配置，随后播放器从 TF 卡读取素材清单、图片和音频。开机读取素材的时间仍然存在。

## 将来手动更新固化程序

1. USB-JTAG 接电脑并保持板卡上电。
2. 在 TD 的 `Tools → ChipLinker` 打开工具，刷新下载器；本板 FPGA 为 `EG4S20BG256`。
3. 速度选 `1 MHz`，使用 `Program SVF`，选择本目录的 `competition_recovery_v19_flash.svf`。
4. SVF 已包含从地址 `0x000000` 开始擦除、写入及校验的操作。无需另选 Dual Boot 或 Multi Boot。
5. 开始后保持供电，等待明确的成功提示；低速写入可能需要数分钟。
6. 关闭并重新打开板卡电源，确认能自动启动。

也可在 PowerShell 中运行本目录的 `PROGRAM_FLASH.ps1`。脚本只接受本包配对的 V19 BIT/BIN/SVF，检查文件哈希和目标 FPGA，再执行 SVF 写入、完整镜像回读和逐字节比对。它会覆盖当前启动镜像，不能用于其他开发板。日志出现 `FLASH_V19_BYTE_COMPARE_OK` 才表示全部步骤完成。

本次早先尝试 `PROGRAM_FLASH` 的直接 SPI 下载路径时发生过 `USB Error: read data failed`。因此提供上述 SVF 方式，并保留独立回读比对。是否成功以包内实际烧写日志为准。

## 回滚和日后换素材

- 临时运行旧版本：用 `PROGRAM_SRAM` 下载旧 `.bit`；断电后仍恢复 Flash 中的 V19。
- 永久回到其他版本：用对应 `.bit` 在 ChipLinker 重新生成 `SVF for SPI`（EG4S20BG256、W25Q16、地址 0、1 MHz、Verify），再使用 `Program SVF` 烧写。切勿直接重命名 BIN 为 BIT。
- 更换图片、歌曲：按 V18/V19 素材工具生成配套文件并复制到 TF 卡，无需重烧 Flash。
- 调整音量、亮度、对比度仍是本次运行的设置，断电后恢复默认；音量默认 10%。SW1～SW4 按上电时实际位置生效。
- `.bit` / `.bin` 不需要复制到 TF 卡，TF 卡继续使用 PLAYLST.BIN、PIC000*.BMP、MUSIC0*.FPA。

## 资料依据

- `E:/FPGA/HX4S20_Contest_202606/HX4S20开发板手册-HDL版2410.pdf`，第 9～10 页供电/JTAG、第 22 页启动 Flash。
- `E:/FPGA/TD_6.2.1_SP1_178840_NL/doc/SWUG/SWUG110_BitWizard_User_Guide.pdf`，PDF 第 20 页 Program Flash、第 21 页 Flash Read、第 22 页 Verify Flash、第 25～27 页 ChipLinker / Program SVF、第 32 页 SVF for SPI。

板卡手册第 22 页将 W25Q16 的容量写作 64 Mbit，与型号和实际 ID 不符；本次依据实际读取到的 EF4015 按 2 MiB 备份。
