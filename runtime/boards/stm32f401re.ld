/* STM32F401RE (the Nucleo-F401RE's): 512 KB flash at 0x08000000, which the chip also shows at 0
   when it boots from flash, and 96 KB SRAM at 0x20000000. The stack is the top 16 KB of SRAM. */
MEMORY { FLASH (rx) : ORIGIN = 0x08000000, LENGTH = 512K
         RAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 96K }
_stack_size = 16K;
INCLUDE cortex-m.ld
