/* QEMU's microbit (nRF51822, Cortex-M0): 256 KB flash, 16 KB RAM. The stack is the top 4 KB. */
MEMORY { FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 256K
         RAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 16K }
_stack_size = 4K;
INCLUDE cortex-m.ld
