/* Shared Cortex-M layout: vectors and code in FLASH, data copied to RAM at reset, then bss,
   then the stack at the top of RAM (_stack_size, 32 KB unless the board sets it). */
ENTRY(Reset_Handler)
_stack_size = DEFINED(_stack_size) ? _stack_size : 32K;
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) . = ALIGN(4); } > FLASH
  .ARM.exidx : { *(.ARM.exidx*) } > FLASH
  _sidata = LOADADDR(.data);
  .data : { _sdata = .; *(.data*) . = ALIGN(4); _edata = .; } > RAM AT > FLASH
  .bss (NOLOAD) : { _sbss = .; *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
  /* [<Section ".noinit">] values (0014): neither copied nor zeroed at reset, so they keep what
     the memory held */
  .noinit (NOLOAD) : { . = ALIGN(4); *(.noinit*) . = ALIGN(4); _enoinit = .; } > RAM
  _estack = ORIGIN(RAM) + LENGTH(RAM);
  _sstack = _estack - _stack_size;
  ASSERT(_enoinit <= _sstack, "RAM overflow: data + bss + heap don't leave room for the stack")
}
