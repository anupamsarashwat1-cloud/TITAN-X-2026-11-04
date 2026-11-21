/* SPDX-License-Identifier: Apache-2.0 */
/* SMVDU TITAN-X ATPG Baremetal Linker Script */

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 16M
}

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) } > RAM
  .text : { *(.text .text.*) } > RAM

  . = ALIGN(0x1000);
  .tohost : { *(.tohost) } > RAM

  . = ALIGN(0x1000);
  .data : {
    *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(64);
    reg_dump_area = .;
    . += 512;
    . = ALIGN(64);
    scratch_area = .;
    . += 4096;
    . = ALIGN(64);
    completion_token_addr = .;
    . += 64;
  } > RAM

  . = ALIGN(8);
  .bss : { *(.bss .bss.*) } > RAM
  .sbss : { *(.sbss .sbss.*) } > RAM

  _end = .;
}
