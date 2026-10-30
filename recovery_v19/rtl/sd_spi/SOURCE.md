Source: https://github.com/WangXuan95/FPGA-SDcard-Reader-SPI
License: GPL-3.0 (included).
Local changes: runtime requested_name held stable during reads; slow initialization/fast data clock selection; accept CMD55 R1 00 or 01 before ACMD41 ready; initialize missing responses to FF; valid CRC7 on fixed initialization commands; completed-session response snapshot for diagnostics.
Protocol references: https://www.sdcard.org/cms/wp-content/themes/sdcard-org/dl.php?f=Part1_Physical_Layer_Simplified_Specification_Ver5.10.pdf
Commit: 75ef4535d99e8a46b7eef17fdbd723297f26daaf
Directory changes: preserve matching entry until reset; include FAT32 first-cluster high word; reject volume/directory attributes while accepting other regular-file attribute combinations.
Additional local changes: deselected and selected dummy bytes between CMD55/ACMD41; CMD17 R1 followed directly by data-token detection (no four-byte skip); 16-bit data-token wait counter; data-token snapshot in C page during sector reads.
Scaling change: coherent pause clock-enable on sequential SD/FAT/SPI stages; hold pins under FIFO backpressure and mask paused output-valid at FIFO boundary.

V15: one CMD17 per accepted sector (remove discarded duplicate read); latch the
sector address and wait for request deassertion after completion; gate payload
with successful R1=00 and data token=FE. Retain payload+two CRC bytes, then two
selected dummy bytes and two deselected dummy bytes, instead of 255 selected
dummy bytes. Initialization and SPI bit engine/clock remain unchanged.
Read/release reference: https://elm-chan.org/docs/mmc/mmc_e.html
