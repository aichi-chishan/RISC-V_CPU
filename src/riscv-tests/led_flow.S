// Board program for the ATK ZYNQ-7020 (50 MHz system clock).
// The core takes five clocks per instruction.  The two-instruction delay loop
// therefore uses 2,500,000 * 10 clocks = about 0.5 seconds per LED position.
//
// LED register: 0x4000_0000, low two bits drive led[1:0].

    .section .text
    .globl _start

_start:
    lui   x1, 0x40000           // x1 = LED register address
    addi  x2, x0, 1             // initial pattern: 2'b01

loop:
    sw    x2, 0(x1)             // write LED peripheral
    lui   x3, 0x262
    addi  x3, x3, 1440          // x3 = 2,500,000

delay:
    addi  x3, x3, -1
    bne   x3, x0, delay
    xori  x2, x2, 3             // 01 <-> 10
    jal   x0, loop
