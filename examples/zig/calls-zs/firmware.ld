/* QEMU's mps2-an386 (a Cortex-M4F): 4 MB of code memory at 0, 4 MB of SRAM at 0x20000000 (for a
   Nucleo-F401RE: FLASH at 0x08000000, 512K; RAM at 0x20000000, 96K). The vector table first, data
   copied to RAM at reset, bss zeroed, the stack at the top of RAM. */
MEMORY { FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 4M
         RAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 4M }
ENTRY(Reset_Handler)
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) . = ALIGN(4); } > FLASH
  .ARM.exidx : { *(.ARM.exidx*) } > FLASH
  _sidata = LOADADDR(.data);
  .data : { _sdata = .; *(.data*) . = ALIGN(4); _edata = .; } > RAM AT > FLASH
  .bss (NOLOAD) : { _sbss = .; *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
  _estack = ORIGIN(RAM) + LENGTH(RAM);
}
