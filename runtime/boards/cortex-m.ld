/* Shared Cortex-M layout: vectors and code in FLASH; in RAM the stack first, at the bottom, then
   data copied to RAM at reset, bss and the rest. The stack is all the RAM the rest leaves, as
   flip-link has it, and _stack_size at least (32 KB unless the board sets it): a program whose
   rest leaves less doesn't link. A stack that runs past its base runs off the bottom of RAM,
   where a write faults (the runtime's fault handler says so), instead of over the program's
   memory. */
ENTRY(Reset_Handler)
_stack_size = DEFINED(_stack_size) ? _stack_size : 32K;
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) . = ALIGN(4); } > FLASH
  .ARM.exidx : { *(.ARM.exidx*) } > FLASH
  /* the stack ends where the rest, as lld's last pass laid it out (the first, which hasn't, takes
     the least), fits under the end of RAM, rounded down to the rest's largest alignment (8 at
     least, the stack's own): the rest then starts right there and takes the same room wherever
     that is, so the passes agree */
  _ram_align = MAX(MAX(8, ALIGNOF(.data)),
                   MAX(MAX(ALIGNOF(.bss), ALIGNOF(.noinit)), ALIGNOF(.placed)));
  .stack (NOLOAD) : {
    _sstack = .;
    . = MAX(ALIGN(. + _stack_size, _ram_align),
            _eram > _estack
              ? (ORIGIN(RAM) + LENGTH(RAM) - (_eram - _estack)) & ~(_ram_align - 1)
              : 0);
    _estack = .;
  } > RAM
  _sidata = LOADADDR(.data);
  .data : { _sdata = .; *(.data*) . = ALIGN(4); _edata = .; } > RAM AT > FLASH
  .bss (NOLOAD) : { _sbss = .; *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
  /* [<Section ".noinit">] values (0014): neither copied nor zeroed at reset, so they keep what
     the memory held */
  .noinit (NOLOAD) : { . = ALIGN(4); *(.noinit*) . = ALIGN(4); _enoinit = .; } > RAM
  /* the writable sections named no other way (a placed value's, 0014: a DMA buffer), named here
     so the stack's room counts them and their alignment, which as orphans it couldn't: not loaded
     at reset (the startup code copies a Z# value's from its flash image). The linker's own .got,
     empty without position-independent code, comes along */
  .placed (NOLOAD) : { INPUT_SECTION_FLAGS(SHF_WRITE) *(*) } > RAM
  _eram = .;
  ASSERT(_sstack == ORIGIN(RAM), "the stack isn't at the bottom of RAM")
  ASSERT(_eram <= ORIGIN(RAM) + LENGTH(RAM),
         "RAM overflow: data, bss and the heap leave the stack less than _stack_size")
}
