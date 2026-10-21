/* QEMU's mps2-an386 (Cortex-M4F): 4 MB code memory at 0, 4 MB SRAM at 0x20000000.
   The stack is the top 32 KB of SRAM. */
MEMORY { FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 4M
         RAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 4M }
INCLUDE cortex-m.ld
