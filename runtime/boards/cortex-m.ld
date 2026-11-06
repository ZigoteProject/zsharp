/* Shared Cortex-M layout: vectors and code in FLASH; in RAM the stack first, at the bottom
   (_stack_size, 32 KB unless the board sets it), then data copied to RAM at reset, bss and the
   rest. A stack that runs past its base runs off the bottom of RAM, where a write faults (the
   runtime's fault handler says so), instead of over the program's memory. */
ENTRY(Reset_Handler)
_stack_size = DEFINED(_stack_size) ? _stack_size : 32K;
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) . = ALIGN(4); } > FLASH
  .ARM.exidx : { *(.ARM.exidx*) } > FLASH
  .stack (NOLOAD) : { _sstack = .; . += _stack_size; . = ALIGN(8); _estack = .; } > RAM
  _sidata = LOADADDR(.data);
  .data : { _sdata = .; *(.data*) . = ALIGN(4); _edata = .; } > RAM AT > FLASH
  .bss (NOLOAD) : { _sbss = .; *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
  /* [<Section ".noinit">] values (0014): neither copied nor zeroed at reset, so they keep what
     the memory held */
  .noinit (NOLOAD) : { . = ALIGN(4); *(.noinit*) . = ALIGN(4); _enoinit = .; } > RAM
  ASSERT(_sstack == ORIGIN(RAM), "the stack isn't at the bottom of RAM")
  ASSERT(_enoinit <= ORIGIN(RAM) + LENGTH(RAM), "RAM overflow: the stack, data, bss and heap don't fit")
}
