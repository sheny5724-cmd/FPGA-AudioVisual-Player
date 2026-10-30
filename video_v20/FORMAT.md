# HXVD0001 video stream

All integer fields are little-endian. CRC32 is ISO-HDLC, equivalent to Python `zlib.crc32`, initial internal value 0xffffffff and final inversion.

## File header: 512 bytes

| Offset | Size | Value |
|---|---|---|
| 0 | 8 | ASCII HXVD0001 |
| 8 | 2 | Width 160 |
| 10 | 2 | Height 90 |
| 12 | 2 | FPS 15 |
| 14 | 2 | Encoding 1 |
| 16 | 4 | Frame count, 1..60000 |
| 20 | 4 | Audio rate 24000 |
| 24 | 4 | Samples per frame 1600 |
| 28 | 4 | Packet bytes 16896 |
| 32 | 4 | Pixels per frame 14400 |
| 36 | 4 | Total samples = frame count × 1600 |
| 40 | 468 | Reserved, zero |
| 508 | 4 | CRC32 over bytes 0..507 |

## Frame packet: 16896 bytes (33 sectors)

| Offset | Size | Value |
|---|---|---|
| 0 | 4 | ASCII FRM1 |
| 4 | 4 | Frame index, starts at zero |
| 8 | 4 | CRC32 over payload, bytes 32..16799 |
| 12 | 4 | Payload size 16768 |
| 16 | 16 | Reserved, zero |
| 32 | 768 | 256 RGB888 entries, R then G then B |
| 800 | 14400 | 8-bit indices, top to bottom, left to right |
| 15200 | 1600 | 24 kHz mono G.711 mu-law samples; 0xff is silence |
| 16800 | 96 | Sector padding, zero, not included in CRC |

Every frame is independently decodable, but V20 reads sequentially and does not implement seeking. No FAT entry or image/song catalog changes are required; files use 8.3 names VIDEO01.FPV and VIDEO02.FPV.
