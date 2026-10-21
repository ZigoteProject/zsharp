
/tmp/crc32.elf:	file format elf32-littlearm

Disassembly of section .text:

00000000 <vectors>:
       0: 00 00 40 20 39 0e 00 00         ..@ 9...
       8: 81 0f 00 00 81 0f 00 00         ........
      10: 81 0f 00 00 81 0f 00 00         ........
      18: 81 0f 00 00 00 00 00 00         ........
      20: 00 00 00 00 00 00 00 00         ........
      28: 00 00 00 00 81 0f 00 00         ........
      30: 81 0f 00 00 00 00 00 00         ........
      38: 81 0f 00 00 91 0f 00 00         ........

00000040 <main>:
      40:      	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
      44:      	sub	sp, #0x24
      46:      	bl	0xe30 <zs_set_args>     @ imm = #0xde6
      4a:      	movw	r0, #0x1010
      4e:      	movs	r1, #0x0
      50:      	movs	r4, #0x0
      52:      	bl	0x460 <zs_alloc>        @ imm = #0x40a
      56:      	mov	r11, r0
      58:      	movs	r1, #0x1
      5a:      	mov.w	r0, #0x1000
      5e:      	strd	r1, r4, [r11]
      62:      	strd	r0, r4, [r11, #8]
      66:      	add.w	r0, r11, #0x10
      6a:      	mov.w	r1, #0x1000
      6e:      	bl	0x1480 <compiler_rt.arm.__aeabi_memclr> @ imm = #0x140e
      72:      	movw	r10, #0x828d
      76:      	movs	r6, #0xfb
      78:      	movw	r7, #0xfff
      7c:      	movs	r0, #0x1
      7e:      	movs	r1, #0x0
      80:      	mov.w	r8, #0x0
      84:      	mov.w	r9, #0x0
      88:      	eor	r0, r0, #0x1
      8c:      	orrs	r0, r1
      8e:      	beq	0xe6 <main+0xa6>        @ imm = #0x54
      90:      	ldrd	r0, r1, [r11, #8]
      94:      	movs	r7, #0xfb
      96:      	adds.w	r6, r0, #0x10
      9a:      	adc	r1, r1, #0x0
      9e:      	mov	r0, r6
      a0:      	movw	r10, #0x828d
      a4:      	bl	0x460 <zs_alloc>        @ imm = #0x3b8
      a8:      	mov	r1, r11
      aa:      	mov	r2, r6
      ac:      	mov	r5, r0
      ae:      	bl	0x1490 <compiler_rt.arm.__aeabi_memcpy> @ imm = #0x13de
      b2:      	movs	r0, #0x0
      b4:      	movs	r1, #0x1
      b6:      	strd	r1, r0, [r5]
      ba:      	ldrd	r1, r0, [r11]
      be:      	orrs.w	r2, r1, r0
      c2:      	beq	0xde <main+0x9e>        @ imm = #0x18
      c4:      	eor	r2, r1, #0x1
      c8:      	orrs	r2, r0
      ca:      	bne	0xd4 <main+0x94>        @ imm = #0x6
      cc:      	mov	r0, r11
      ce:      	bl	0x550 <zs_free>         @ imm = #0x47e
      d2:      	b	0xde <main+0x9e>        @ imm = #0x8
      d4:      	subs	r1, #0x1
      d6:      	sbc	r0, r0, #0x0
      da:      	strd	r1, r0, [r11]
      de:      	mov	r11, r5
      e0:      	mov	r6, r7
      e2:      	movw	r7, #0xfff
      e6:      	ldrd	r0, r1, [r11, #8]
      ea:      	subs.w	r0, r8, r0
      ee:      	sbcs.w	r0, r9, r1
      f2:      	bhs.w	0x442 <main+0x402>      @ imm = #0x34c
      f6:      	rsb	r0, r8, r8, lsl #3
      fa:      	uxth	r1, r0
      fc:      	mul	r1, r1, r10
     100:      	lsrs	r1, r1, #0x17
     102:      	mls	r0, r1, r6, r0
     106:      	subs.w	r1, r8, r7
     10a:      	add.w	r2, r11, #0x10
     10e:      	sbcs	r1, r9, #0x0
     112:      	strb.w	r0, [r2, r8]
     116:      	bhs	0x126 <main+0xe6>       @ imm = #0xc
     118:      	adds.w	r8, r8, #0x1
     11c:      	ldrd	r0, r1, [r11]
     120:      	adc	r9, r9, #0x0
     124:      	b	0x88 <main+0x48>        @ imm = #-0xa0
     126:      	movw	r7, #0x8320
     12a:      	str	r2, [sp, #0x1c]
     12c:      	movt	r7, #0xedb8
     130:      	bl	0xf28 <zs_ticks>        @ imm = #0xdf4
     134:      	ldrd	r3, r8, [r11]
     138:      	movs	r4, #0x0
     13a:      	movs	r6, #0x1
     13c:      	strd	r1, r0, [sp]
     140:      	str.w	r11, [sp, #0x20]
     144:      	b	0x180 <main+0x140>      @ imm = #0x38
     146:      	nop
     148:      	ldr.w	r11, [sp, #0x20]
     14c:      	ldrd	r6, r4, [sp, #8]
     150:      	ldr	r3, [sp, #0x18]
     152:      	ldrd	r1, r8, [sp, #16]
     156:      	mvn.w	r5, lr
     15a:      	orrs.w	r0, r3, r1
     15e:      	beq	0x16a <main+0x12a>      @ imm = #0x8
     160:      	subs	r3, #0x1
     162:      	sbc	r8, r1, #0x0
     166:      	strd	r3, r8, [r11]
     16a:      	adds	r0, r6, #0x1
     16c:      	adc	r1, r4, #0x0
     170:      	subs.w	r2, r6, #0xa
     174:      	sbcs	r2, r4, #0x0
     178:      	mov	r6, r0
     17a:      	mov	r4, r1
     17c:      	bhs.w	0x2cc <main+0x28c>      @ imm = #0x14c
     180:      	orrs.w	r0, r3, r8
     184:      	bne.w	0x29c <main+0x25c>      @ imm = #0x114
     188:      	ldrd	r12, r10, [r11, #8]
     18c:      	movs	r3, #0x0
     18e:      	mov.w	r8, #0x0
     192:      	subs.w	r1, r12, #0x1
     196:      	sbc	r5, r10, #0x0
     19a:      	eor.w	r2, r10, r5
     19e:      	and.w	r2, r2, r10
     1a2:      	cmp.w	r2, #0xffffffff
     1a6:      	ble.w	0x450 <main+0x410>      @ imm = #0x2a6
     1aa:      	cmp	r5, #0x0
     1ac:      	bmi	0x28c <main+0x24c>      @ imm = #0xdc
     1ae:      	strd	r6, r4, [sp, #8]
     1b2:      	movs	r4, #0x0
     1b4:      	mov.w	lr, #0xffffffff
     1b8:      	mov	r2, r3
     1ba:      	mov.w	r9, #0x0
     1be:      	str.w	r8, [sp, #0x10]
     1c2:      	str	r3, [sp, #0x18]
     1c4:      	str.w	r8, [sp, #0x14]
     1c8:      	b	0x23c <main+0x1fc>      @ imm = #0x70
     1ca:      	nop
     1cc:      	ldr	r0, [sp, #0x20]
     1ce:      	str	r2, [sp, #0x18]
     1d0:      	strd	r2, r8, [r0]
     1d4:      	strd	r8, r8, [sp, #16]
     1d8:      	eor.w	r0, lr, r11
     1dc:      	eor.w	r6, r7, r0, lsr #1
     1e0:      	lsls	r3, r0, #0x1f
     1e2:      	it	eq
     1e4:      	lsreq	r6, r0, #0x1
     1e6:      	eor.w	r0, r7, r6, lsr #1
     1ea:      	lsls	r3, r6, #0x1f
     1ec:      	it	eq
     1ee:      	lsreq	r0, r6, #0x1
     1f0:      	eor.w	r3, r7, r0, lsr #1
     1f4:      	lsls	r6, r0, #0x1f
     1f6:      	it	eq
     1f8:      	lsreq	r3, r0, #0x1
     1fa:      	eor.w	r0, r7, r3, lsr #1
     1fe:      	lsls	r6, r3, #0x1f
     200:      	it	eq
     202:      	lsreq	r0, r3, #0x1
     204:      	eor.w	r3, r7, r0, lsr #1
     208:      	lsls	r6, r0, #0x1f
     20a:      	it	eq
     20c:      	lsreq	r3, r0, #0x1
     20e:      	eor.w	r0, r7, r3, lsr #1
     212:      	lsls	r6, r3, #0x1f
     214:      	it	eq
     216:      	lsreq	r0, r3, #0x1
     218:      	eor.w	r3, r7, r0, lsr #1
     21c:      	lsls	r6, r0, #0x1f
     21e:      	it	eq
     220:      	lsreq	r3, r0, #0x1
     222:      	eor.w	lr, r7, r3, lsr #1
     226:      	lsls	r0, r3, #0x1f
     228:      	it	eq
     22a:      	lsreq.w	lr, r3, #0x1
     22e:      	adds	r4, #0x1
     230:      	adc	r9, r9, #0x0
     234:      	subs	r0, r1, r4
     236:      	sbcs.w	r0, r5, r9
     23a:      	blt	0x148 <main+0x108>      @ imm = #-0xf6
     23c:      	orrs.w	r6, r2, r8
     240:      	beq	0x270 <main+0x230>      @ imm = #0x2c
     242:      	adds	r3, r2, #0x1
     244:      	adc	r6, r8, #0x0
     248:      	subs.w	r0, r4, r12
     24c:      	sbcs.w	r0, r9, r10
     250:      	ldr	r0, [sp, #0x20]
     252:      	strd	r3, r6, [r0]
     256:      	bhs.w	0x442 <main+0x402>      @ imm = #0x1e8
     25a:      	ldr	r0, [sp, #0x1c]
     25c:      	ldrb.w	r11, [r0, r4]
     260:      	orrs.w	r0, r3, r6
     264:      	bne	0x1cc <main+0x18c>      @ imm = #-0x9c
     266:      	movs	r0, #0x0
     268:      	str	r0, [sp, #0x18]
     26a:      	strd	r0, r0, [sp, #16]
     26e:      	b	0x282 <main+0x242>      @ imm = #0x10
     270:      	subs.w	r0, r4, r12
     274:      	sbcs.w	r0, r9, r10
     278:      	bhs.w	0x442 <main+0x402>      @ imm = #0x1c6
     27c:      	ldr	r0, [sp, #0x1c]
     27e:      	ldrb.w	r11, [r0, r4]
     282:      	movs	r2, #0x0
     284:      	mov.w	r8, #0x0
     288:      	b	0x1d8 <main+0x198>      @ imm = #-0xb4
     28a:      	nop
     28c:      	movs	r5, #0x0
     28e:      	mov	r1, r8
     290:      	orrs.w	r0, r3, r1
     294:      	bne.w	0x160 <main+0x120>      @ imm = #-0x138
     298:      	b	0x16a <main+0x12a>      @ imm = #-0x132
     29a:      	nop
     29c:      	adds	r1, r3, #0x1
     29e:      	adcs	r2, r8, #0x0
     2a2:      	mov.w	r3, #0x0
     2a6:      	ldrd	r12, r10, [r11, #8]
     2aa:      	adcs	r0, r3, #0x0
     2ae:      	strd	r1, r2, [r11]
     2b2:      	bne.w	0x18e <main+0x14e>      @ imm = #-0x128
     2b6:      	and.w	r3, r1, r2
     2ba:      	subs.w	r8, r3, #0xffffffff
     2be:      	ite	eq
     2c0:      	moveq	r1, r8
     2c2:      	movne	r8, r2
     2c4:      	mov	r3, r1
     2c6:      	strd	r1, r8, [r11]
     2ca:      	b	0x192 <main+0x152>      @ imm = #-0x13c
     2cc:      	bl	0xf28 <zs_ticks>        @ imm = #0xc58
     2d0:      	mov	r7, r0
     2d2:      	mov	r10, r1
     2d4:      	mov	r0, r5
     2d6:      	movs	r1, #0x0
     2d8:      	bl	0x78c <zs_str_of_u64>   @ imm = #0x4b0
     2dc:      	mov	r6, r0
     2de:      	movw	r0, #0x1b90
     2e2:      	movt	r0, #0x0
     2e6:      	mov	r1, r6
     2e8:      	bl	0x5a0 <zs_str_concat>   @ imm = #0x2b4
     2ec:      	ldrd	r2, r1, [r6]
     2f0:      	mov	r5, r0
     2f2:      	orrs.w	r3, r2, r1
     2f6:      	beq	0x312 <main+0x2d2>      @ imm = #0x18
     2f8:      	eor	r0, r2, #0x1
     2fc:      	orrs	r0, r1
     2fe:      	bne	0x308 <main+0x2c8>      @ imm = #0x6
     300:      	mov	r0, r6
     302:      	bl	0x550 <zs_free>         @ imm = #0x24a
     306:      	b	0x312 <main+0x2d2>      @ imm = #0x8
     308:      	subs	r0, r2, #0x1
     30a:      	sbc	r1, r1, #0x0
     30e:      	strd	r0, r1, [r6]
     312:      	movw	r1, #0x1bb0
     316:      	movt	r1, #0x0
     31a:      	mov	r0, r5
     31c:      	bl	0x5a0 <zs_str_concat>   @ imm = #0x280
     320:      	ldrd	r2, r1, [r5]
     324:      	mov	r6, r0
     326:      	orrs.w	r3, r2, r1
     32a:      	beq	0x346 <main+0x306>      @ imm = #0x18
     32c:      	eor	r0, r2, #0x1
     330:      	orrs	r0, r1
     332:      	bne	0x33c <main+0x2fc>      @ imm = #0x6
     334:      	mov	r0, r5
     336:      	bl	0x550 <zs_free>         @ imm = #0x216
     33a:      	b	0x346 <main+0x306>      @ imm = #0x8
     33c:      	subs	r0, r2, #0x1
     33e:      	sbc	r1, r1, #0x0
     342:      	strd	r0, r1, [r5]
     346:      	ldr	r0, [sp, #0x4]
     348:      	ldr	r1, [sp]
     34a:      	subs	r0, r7, r0
     34c:      	sbcs.w	r1, r10, r1
     350:      	mov.w	r2, #0x0
     354:      	adc	r2, r2, #0x0
     358:      	eor	r2, r2, #0x1
     35c:      	cmp	r2, #0x1
     35e:      	beq	0x450 <main+0x410>      @ imm = #0xee
     360:      	bl	0x78c <zs_str_of_u64>   @ imm = #0x428
     364:      	mov	r7, r0
     366:      	mov	r0, r6
     368:      	mov	r1, r7
     36a:      	bl	0x5a0 <zs_str_concat>   @ imm = #0x232
     36e:      	ldrd	r2, r1, [r6]
     372:      	mov	r5, r0
     374:      	orrs.w	r3, r2, r1
     378:      	beq	0x394 <main+0x354>      @ imm = #0x18
     37a:      	eor	r0, r2, #0x1
     37e:      	orrs	r0, r1
     380:      	bne	0x38a <main+0x34a>      @ imm = #0x6
     382:      	mov	r0, r6
     384:      	bl	0x550 <zs_free>         @ imm = #0x1c8
     388:      	b	0x394 <main+0x354>      @ imm = #0x8
     38a:      	subs	r0, r2, #0x1
     38c:      	sbc	r1, r1, #0x0
     390:      	strd	r0, r1, [r6]
     394:      	ldrd	r1, r0, [r7]
     398:      	orrs.w	r2, r1, r0
     39c:      	beq	0x3b8 <main+0x378>      @ imm = #0x18
     39e:      	eor	r2, r1, #0x1
     3a2:      	orrs	r2, r0
     3a4:      	bne	0x3ae <main+0x36e>      @ imm = #0x6
     3a6:      	mov	r0, r7
     3a8:      	bl	0x550 <zs_free>         @ imm = #0x1a4
     3ac:      	b	0x3b8 <main+0x378>      @ imm = #0x8
     3ae:      	subs	r1, #0x1
     3b0:      	sbc	r0, r0, #0x0
     3b4:      	strd	r1, r0, [r7]
     3b8:      	movw	r0, #0x1b70
     3bc:      	movt	r0, #0x0
     3c0:      	mov	r1, r5
     3c2:      	bl	0x5a0 <zs_str_concat>   @ imm = #0x1da
     3c6:      	ldrd	r2, r1, [r5]
     3ca:      	mov	r6, r0
     3cc:      	orrs.w	r3, r2, r1
     3d0:      	beq	0x3ec <main+0x3ac>      @ imm = #0x18
     3d2:      	eor	r0, r2, #0x1
     3d6:      	orrs	r0, r1
     3d8:      	bne	0x3e2 <main+0x3a2>      @ imm = #0x6
     3da:      	mov	r0, r5
     3dc:      	bl	0x550 <zs_free>         @ imm = #0x170
     3e0:      	b	0x3ec <main+0x3ac>      @ imm = #0x8
     3e2:      	subs	r0, r2, #0x1
     3e4:      	sbc	r1, r1, #0x0
     3e8:      	strd	r0, r1, [r5]
     3ec:      	mov	r0, r6
     3ee:      	bl	0xad8 <zs_println>      @ imm = #0x6e6
     3f2:      	ldrd	r1, r0, [r6]
     3f6:      	orrs.w	r2, r1, r0
     3fa:      	beq	0x416 <main+0x3d6>      @ imm = #0x18
     3fc:      	eor	r2, r1, #0x1
     400:      	orrs	r2, r0
     402:      	bne	0x40c <main+0x3cc>      @ imm = #0x6
     404:      	mov	r0, r6
     406:      	bl	0x550 <zs_free>         @ imm = #0x146
     40a:      	b	0x416 <main+0x3d6>      @ imm = #0x8
     40c:      	subs	r1, #0x1
     40e:      	sbc	r0, r0, #0x0
     412:      	strd	r1, r0, [r6]
     416:      	ldr	r0, [sp, #0x20]
     418:      	ldrd	r1, r3, [r0]
     41c:      	orrs.w	r2, r1, r3
     420:      	beq	0x43a <main+0x3fa>      @ imm = #0x16
     422:      	eor	r2, r1, #0x1
     426:      	orrs	r2, r3
     428:      	bne	0x430 <main+0x3f0>      @ imm = #0x4
     42a:      	bl	0x550 <zs_free>         @ imm = #0x122
     42e:      	b	0x43a <main+0x3fa>      @ imm = #0x8
     430:      	subs	r1, #0x1
     432:      	sbc	r2, r3, #0x0
     436:      	strd	r1, r2, [r0]
     43a:      	movs	r0, #0x0
     43c:      	add	sp, #0x24
     43e:      	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
     442:      	movw	r0, #0x1b40
     446:      	movt	r0, #0x0
     44a:      	adds	r0, #0x10
     44c:      	bl	0x524 <zs_panic_c>      @ imm = #0xd4
     450:      	movw	r0, #0x1b10
     454:      	movt	r0, #0x0
     458:      	adds	r0, #0x10
     45a:      	bl	0x524 <zs_panic_c>      @ imm = #0xc6
     45e:      	bmi	0x40a <main+0x3ca>      @ imm = #-0x58

00000460 <zs_alloc>:
     460:      	push	{r4, r6, r7, lr}
     462:      	add	r7, sp, #0x8
     464:      	adds	r0, #0x7
     466:      	lsrs	r2, r0, #0x3
     468:      	cmp	r2, #0x20
     46a:      	bhi	0x488 <zs_alloc+0x28>   @ imm = #0x1a
     46c:      	movw	r12, #0x0
     470:      	movt	r12, #0x2000
     474:      	ldr.w	r1, [r12, r2, lsl #2]
     478:      	cbz	r1, 0x488 <zs_alloc+0x28> @ imm = #0xc
     47a:      	mov	r0, r1
     47c:      	ldr	r3, [r1]
     47e:      	ldr	r1, [r0, #-8]!
     482:      	str.w	r3, [r12, r2, lsl #2]
     486:      	b	0x4c0 <zs_alloc+0x60>   @ imm = #0x36
     488:      	movw	r12, #0x84
     48c:      	movt	r12, #0x2000
     490:      	ldr.w	r2, [r12]
     494:      	bic	r1, r0, #0x7
     498:      	adds	r3, r1, r2
     49a:      	movw	r0, #0xfff9
     49e:      	subs	r0, r3, r0
     4a0:      	cmn.w	r0, #0x10001
     4a4:      	blo	0x516 <zs_alloc+0xb6>   @ imm = #0x6e
     4a6:      	movw	lr, #0x88
     4aa:      	movt	lr, #0x2000
     4ae:      	add.w	r0, lr, r2
     4b2:      	adds	r3, #0x8
     4b4:      	str.w	r1, [lr, r2]
     4b8:      	movs	r2, #0x0
     4ba:      	str.w	r3, [r12]
     4be:      	str	r2, [r0, #0x4]
     4c0:      	movw	lr, #0x88
     4c4:      	movt	lr, #0x2001
     4c8:      	ldr.w	r2, [lr]
     4cc:      	movw	r12, #0x8c
     4d0:      	movt	r12, #0x2001
     4d4:      	ldr.w	r3, [r12]
     4d8:      	add	r1, r2
     4da:      	str.w	r1, [lr]
     4de:      	movw	lr, #0x90
     4e2:      	cmp	r1, r3
     4e4:      	it	hi
     4e6:      	strhi.w	r1, [r12]
     4ea:      	movt	lr, #0x2001
     4ee:      	movw	r12, #0x98
     4f2:      	ldrd	r2, r3, [lr]
     4f6:      	movt	r12, #0x2001
     4fa:      	ldrd	r1, r4, [r12]
     4fe:      	adds	r2, #0x1
     500:      	adc	r3, r3, #0x0
     504:      	adds	r1, #0x1
     506:      	strd	r2, r3, [lr]
     50a:      	adc	r2, r4, #0x0
     50e:      	adds	r0, #0x8
     510:      	strd	r1, r2, [r12]
     514:      	pop	{r4, r6, r7, pc}
     516:      	movw	r0, #0x1bc8
     51a:      	movt	r0, #0x0
     51e:      	bl	0x524 <zs_panic_c>      @ imm = #0x2
     522:      	bmi	0x4ce <zs_alloc+0x6e>   @ imm = #-0x58

00000524 <zs_panic_c>:
     524:      	push	{r4, r6, r7, lr}
     526:      	add	r7, sp, #0x8
     528:      	mov	r4, r0
     52a:      	movw	r0, #0x1c1d
     52e:      	movt	r0, #0x0
     532:      	bl	0xbf0 <write_c>         @ imm = #0x6ba
     536:      	mov	r0, r4
     538:      	bl	0xbf0 <write_c>         @ imm = #0x6b4
     53c:      	movw	r0, #0x1c25
     540:      	movt	r0, #0x0
     544:      	bl	0xbf0 <write_c>         @ imm = #0x6a8
     548:      	movs	r0, #0x86
     54a:      	bl	0xd34 <stop>            @ imm = #0x7e6
     54e:      	bmi	0x4fa <zs_alloc+0x9a>   @ imm = #-0x58

00000550 <zs_free>:
     550:      	push	{r4, r6, r7, lr}
     552:      	add	r7, sp, #0x8
     554:      	movw	lr, #0x88
     558:      	movw	r12, #0x90
     55c:      	movt	lr, #0x2001
     560:      	movt	r12, #0x2001
     564:      	ldr	r1, [r0, #-8]
     568:      	ldr.w	r3, [lr]
     56c:      	ldrd	r2, r4, [r12]
     570:      	subs	r3, r3, r1
     572:      	subs	r2, #0x1
     574:      	str.w	r3, [lr]
     578:      	sbc	r3, r4, #0x0
     57c:      	lsrs	r4, r1, #0x3
     57e:      	cmp	r4, #0x20
     580:      	strd	r2, r3, [r12]
     584:      	it	hi
     586:      	pophi	{r4, r6, r7, pc}
     588:      	mvn	r2, #0x3
     58c:      	and.w	r1, r2, r1, lsr #1
     590:      	movw	r2, #0x0
     594:      	movt	r2, #0x2000
     598:      	ldr	r3, [r2, r1]
     59a:      	str	r3, [r0]
     59c:      	str	r0, [r2, r1]
     59e:      	pop	{r4, r6, r7, pc}

000005a0 <zs_str_concat>:
     5a0:      	push	{r4, r5, r6, r7, lr}
     5a2:      	add	r7, sp, #0xc
     5a4:      	push.w	{r8, r9, r10}
     5a8:      	mov	lr, r0
     5aa:      	ldrd	r0, r3, [r0, #8]
     5ae:      	ldrd	r2, r6, [r1, #8]
     5b2:      	adds.w	r9, r2, r0
     5b6:      	add.w	r0, r9, #0x18
     5ba:      	lsr.w	r4, r0, #0x3
     5be:      	adc.w	r12, r6, r3
     5c2:      	cmp	r4, #0x20
     5c4:      	bhi	0x5e2 <zs_str_concat+0x42> @ imm = #0x1a
     5c6:      	movw	r5, #0x0
     5ca:      	movt	r5, #0x2000
     5ce:      	ldr.w	r6, [r5, r4, lsl #2]
     5d2:      	cbz	r6, 0x5e2 <zs_str_concat+0x42> @ imm = #0xc
     5d4:      	mov	r10, r6
     5d6:      	ldr	r6, [r6]
     5d8:      	ldr	r0, [r10, #-8]!
     5dc:      	str.w	r6, [r5, r4, lsl #2]
     5e0:      	b	0x61c <zs_str_concat+0x7c> @ imm = #0x38
     5e2:      	movw	r8, #0x84
     5e6:      	movt	r8, #0x2000
     5ea:      	ldr.w	r4, [r8]
     5ee:      	bic	r0, r0, #0x7
     5f2:      	adds	r6, r0, r4
     5f4:      	movw	r3, #0xfff9
     5f8:      	subs	r3, r6, r3
     5fa:      	cmn.w	r3, #0x10001
     5fe:      	blo.w	0x77e <zs_str_concat+0x1de> @ imm = #0x17c
     602:      	movw	r5, #0x88
     606:      	movt	r5, #0x2000
     60a:      	add.w	r10, r5, r4
     60e:      	adds	r6, #0x8
     610:      	str	r0, [r5, r4]
     612:      	movs	r4, #0x0
     614:      	str.w	r6, [r8]
     618:      	str.w	r4, [r10, #0x4]
     61c:      	movw	r5, #0x88
     620:      	movt	r5, #0x2001
     624:      	movw	r4, #0x8c
     628:      	ldr	r6, [r5]
     62a:      	movt	r4, #0x2001
     62e:      	ldr	r2, [r4]
     630:      	add	r0, r6
     632:      	cmp	r0, r2
     634:      	str	r0, [r5]
     636:      	it	hi
     638:      	strhi	r0, [r4]
     63a:      	movw	r0, #0x90
     63e:      	movt	r0, #0x2001
     642:      	ldrd	r2, r4, [r0]
     646:      	movw	r5, #0x98
     64a:      	movt	r5, #0x2001
     64e:      	adds	r2, #0x1
     650:      	ldrd	r6, r3, [r5]
     654:      	adc	r4, r4, #0x0
     658:      	strd	r2, r4, [r0]
     65c:      	adds	r0, r6, #0x1
     65e:      	adc	r2, r3, #0x0
     662:      	strd	r0, r2, [r5]
     666:      	movs	r2, #0x1
     668:      	mov	r0, r10
     66a:      	str	r2, [r0, #8]!
     66e:      	movs	r5, #0x0
     670:      	adds	r2, r0, #0x4
     672:      	stm.w	r2, {r5, r9, r12}
     676:      	add.w	r12, r0, #0x10
     67a:      	strb.w	r5, [r12, r9]
     67e:      	ldr.w	r4, [lr, #0x8]
     682:      	cmp	r4, #0x0
     684:      	beq	0x708 <zs_str_concat+0x168> @ imm = #0x80
     686:      	ands	r2, r4, #0x3
     68a:      	beq	0x6a8 <zs_str_concat+0x108> @ imm = #0x1a
     68c:      	ldrb.w	r3, [lr, #0x10]
     690:      	cmp	r2, #0x1
     692:      	strb.w	r3, [r10, #0x18]
     696:      	bne	0x6b6 <zs_str_concat+0x116> @ imm = #0x1c
     698:      	subs	r2, r4, #0x1
     69a:      	add.w	r5, lr, #0x11
     69e:      	add.w	r6, r10, #0x19
     6a2:      	cmp	r4, #0x4
     6a4:      	bhs	0x6e8 <zs_str_concat+0x148> @ imm = #0x40
     6a6:      	b	0x704 <zs_str_concat+0x164> @ imm = #0x5a
     6a8:      	add.w	r5, lr, #0x10
     6ac:      	mov	r6, r12
     6ae:      	mov	r2, r4
     6b0:      	cmp	r4, #0x4
     6b2:      	bhs	0x6e8 <zs_str_concat+0x148> @ imm = #0x32
     6b4:      	b	0x704 <zs_str_concat+0x164> @ imm = #0x4c
     6b6:      	ldrb.w	r3, [lr, #0x11]
     6ba:      	cmp	r2, #0x2
     6bc:      	strb.w	r3, [r10, #0x19]
     6c0:      	bne	0x6d2 <zs_str_concat+0x132> @ imm = #0xe
     6c2:      	subs	r2, r4, #0x2
     6c4:      	add.w	r5, lr, #0x12
     6c8:      	add.w	r6, r10, #0x1a
     6cc:      	cmp	r4, #0x4
     6ce:      	bhs	0x6e8 <zs_str_concat+0x148> @ imm = #0x16
     6d0:      	b	0x704 <zs_str_concat+0x164> @ imm = #0x30
     6d2:      	ldrb.w	r3, [lr, #0x12]
     6d6:      	subs	r2, r4, #0x3
     6d8:      	add.w	r5, lr, #0x13
     6dc:      	add.w	r6, r10, #0x1b
     6e0:      	strb.w	r3, [r10, #0x1a]
     6e4:      	cmp	r4, #0x4
     6e6:      	blo	0x704 <zs_str_concat+0x164> @ imm = #0x1a
     6e8:      	subs	r3, r5, #0x4
     6ea:      	subs	r4, r6, #0x4
     6ec:      	ldrb	r5, [r3, #4]!
     6f0:      	subs	r2, #0x4
     6f2:      	strb	r5, [r4, #4]!
     6f6:      	ldrb	r5, [r3, #0x1]
     6f8:      	strb	r5, [r4, #0x1]
     6fa:      	ldrb	r5, [r3, #0x2]
     6fc:      	strb	r5, [r4, #0x2]
     6fe:      	ldrb	r5, [r3, #0x3]
     700:      	strb	r5, [r4, #0x3]
     702:      	bne	0x6ec <zs_str_concat+0x14c> @ imm = #-0x1a
     704:      	ldr.w	r5, [lr, #0x8]
     708:      	ldr	r3, [r1, #0x8]
     70a:      	cbz	r3, 0x778 <zs_str_concat+0x1d8> @ imm = #0x6a
     70c:      	ands	r2, r3, #0x3
     710:      	add.w	r6, r12, r5
     714:      	beq	0x72e <zs_str_concat+0x18e> @ imm = #0x16
     716:      	ldrb	r5, [r1, #0x10]
     718:      	mov	r4, r6
     71a:      	cmp	r2, #0x1
     71c:      	strb	r5, [r4], #1
     720:      	bne	0x738 <zs_str_concat+0x198> @ imm = #0x14
     722:      	subs	r2, r3, #0x1
     724:      	adds	r1, #0x11
     726:      	mov	r6, r4
     728:      	cmp	r3, #0x4
     72a:      	bhs	0x75a <zs_str_concat+0x1ba> @ imm = #0x2c
     72c:      	b	0x778 <zs_str_concat+0x1d8> @ imm = #0x48
     72e:      	adds	r1, #0x10
     730:      	mov	r2, r3
     732:      	cmp	r3, #0x4
     734:      	bhs	0x75a <zs_str_concat+0x1ba> @ imm = #0x22
     736:      	b	0x778 <zs_str_concat+0x1d8> @ imm = #0x3e
     738:      	ldrb	r5, [r1, #0x11]
     73a:      	cmp	r2, #0x2
     73c:      	strb	r5, [r6, #0x1]
     73e:      	bne	0x74c <zs_str_concat+0x1ac> @ imm = #0xa
     740:      	subs	r2, r3, #0x2
     742:      	adds	r1, #0x12
     744:      	adds	r6, #0x2
     746:      	cmp	r3, #0x4
     748:      	bhs	0x75a <zs_str_concat+0x1ba> @ imm = #0xe
     74a:      	b	0x778 <zs_str_concat+0x1d8> @ imm = #0x2a
     74c:      	ldrb	r5, [r1, #0x12]
     74e:      	subs	r2, r3, #0x3
     750:      	adds	r1, #0x13
     752:      	strb	r5, [r6, #0x2]
     754:      	adds	r6, #0x3
     756:      	cmp	r3, #0x4
     758:      	blo	0x778 <zs_str_concat+0x1d8> @ imm = #0x1c
     75a:      	subs	r1, #0x4
     75c:      	subs	r3, r6, #0x4
     75e:      	nop
     760:      	ldrb	r6, [r1, #4]!
     764:      	subs	r2, #0x4
     766:      	strb	r6, [r3, #4]!
     76a:      	ldrb	r6, [r1, #0x1]
     76c:      	strb	r6, [r3, #0x1]
     76e:      	ldrb	r6, [r1, #0x2]
     770:      	strb	r6, [r3, #0x2]
     772:      	ldrb	r6, [r1, #0x3]
     774:      	strb	r6, [r3, #0x3]
     776:      	bne	0x760 <zs_str_concat+0x1c0> @ imm = #-0x1a
     778:      	pop.w	{r8, r9, r10}
     77c:      	pop	{r4, r5, r6, r7, pc}
     77e:      	movw	r0, #0x1bc8
     782:      	movt	r0, #0x0
     786:      	bl	0x524 <zs_panic_c>      @ imm = #-0x266
     78a:      	bmi	0x736 <zs_str_concat+0x196> @ imm = #-0x58

0000078c <zs_str_of_u64>:
     78c:      	push	{r4, r5, r6, r7, lr}
     78e:      	add	r7, sp, #0xc
     790:      	push.w	{r8, r9, r10, r11}
     794:      	sub	sp, #0x34
     796:      	movw	r9, #0xcccd
     79a:      	mov	r5, r1
     79c:      	mov	r6, r0
     79e:      	mov.w	r10, #0x1
     7a2:      	movt	r9, #0xcccc
     7a6:      	add.w	r8, sp, #0x1c
     7aa:      	nop
     7ac:      	lsrs	r0, r6, #0x1
     7ae:      	orr.w	r0, r0, r5, lsl #31
     7b2:      	adds.w	r1, r0, r5, lsr #1
     7b6:      	adc	r1, r1, #0x0
     7ba:      	umull	r2, r3, r1, r9
     7be:      	bic	r2, r3, #0x3
     7c2:      	add.w	r2, r2, r3, lsr #2
     7c6:      	subs	r1, r1, r2
     7c8:      	subs	r1, r0, r1
     7ca:      	umull	r0, r2, r1, r9
     7ce:      	add.w	r4, r0, r0, lsl #2
     7d2:      	lsr.w	r3, r5, #0x1
     7d6:      	sub.w	r4, r6, r4, lsl #1
     7da:      	sbc	r3, r3, #0x0
     7de:      	orr	r12, r4, #0x30
     7e2:      	subs.w	r4, r6, #0xa
     7e6:      	add.w	r11, r8, r10
     7ea:      	sbcs	r4, r5, #0x0
     7ee:      	strb	r12, [r11, #-1]
     7f2:      	blo	0x8e2 <zs_str_of_u64+0x156> @ imm = #0xec
     7f4:      	mov.w	r4, #0xcccccccc
     7f8:      	mla	r1, r1, r4, r2
     7fc:      	lsrs	r2, r0, #0x1
     7fe:      	mla	r1, r3, r9, r1
     802:      	and	r0, r0, #0x1
     806:      	orr.w	r2, r2, r1, lsl #31
     80a:      	adds.w	r1, r2, r1, lsr #1
     80e:      	adc	r1, r1, #0x0
     812:      	umull	r2, r3, r1, r9
     816:      	bic	r2, r3, #0x3
     81a:      	add.w	r2, r2, r3, lsr #2
     81e:      	subs	r1, r1, r2
     820:      	orr.w	r0, r0, r1, lsl #1
     824:      	subs.w	r1, r6, #0x64
     828:      	orr	r0, r0, #0x30
     82c:      	sbcs	r1, r5, #0x0
     830:      	strb.w	r0, [r8, r10]
     834:      	blo	0x8ea <zs_str_of_u64+0x15e> @ imm = #0xb2
     836:      	mov	r0, r6
     838:      	mov	r1, r5
     83a:      	movs	r2, #0x64
     83c:      	movs	r3, #0x0
     83e:      	bl	0x157c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xd3a
     842:      	lsrs	r2, r0, #0x1
     844:      	orr.w	r2, r2, r1, lsl #31
     848:      	adds.w	r1, r2, r1, lsr #1
     84c:      	adc	r1, r1, #0x0
     850:      	umull	r2, r3, r1, r9
     854:      	bic	r2, r3, #0x3
     858:      	add.w	r2, r2, r3, lsr #2
     85c:      	subs	r1, r1, r2
     85e:      	and	r0, r0, #0x1
     862:      	orr.w	r0, r0, r1, lsl #1
     866:      	subs.w	r1, r6, #0x3e8
     86a:      	orr	r0, r0, #0x30
     86e:      	sbcs	r1, r5, #0x0
     872:      	strb.w	r0, [r11, #0x1]
     876:      	blo	0x8f2 <zs_str_of_u64+0x166> @ imm = #0x78
     878:      	mov	r0, r6
     87a:      	mov	r1, r5
     87c:      	mov.w	r2, #0x3e8
     880:      	movs	r3, #0x0
     882:      	bl	0x157c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xcf6
     886:      	lsrs	r2, r0, #0x1
     888:      	orr.w	r2, r2, r1, lsl #31
     88c:      	adds.w	r1, r2, r1, lsr #1
     890:      	adc	r1, r1, #0x0
     894:      	umull	r2, r3, r1, r9
     898:      	bic	r2, r3, #0x3
     89c:      	add.w	r2, r2, r3, lsr #2
     8a0:      	subs	r1, r1, r2
     8a2:      	and	r0, r0, #0x1
     8a6:      	orr.w	r0, r0, r1, lsl #1
     8aa:      	orr	r0, r0, #0x30
     8ae:      	strb.w	r0, [r11, #0x2]
     8b2:      	mov	r0, r6
     8b4:      	mov	r1, r5
     8b6:      	movw	r2, #0x2710
     8ba:      	movs	r3, #0x0
     8bc:      	bl	0x157c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xcbc
     8c0:      	movw	r2, #0x270f
     8c4:      	subs	r2, r2, r6
     8c6:      	mov.w	r2, #0x0
     8ca:      	sbcs	r2, r5
     8cc:      	add.w	r10, r10, #0x4
     8d0:      	mov	r6, r0
     8d2:      	mov	r5, r1
     8d4:      	blo.w	0x7ac <zs_str_of_u64+0x20> @ imm = #-0x12c
     8d8:      	sub.w	r1, r10, #0x1
     8dc:      	sub.w	r12, r10, #0x2
     8e0:      	b	0x8fa <zs_str_of_u64+0x16e> @ imm = #0x16
     8e2:      	sub.w	r12, r10, #0x1
     8e6:      	mov	r1, r10
     8e8:      	b	0x8fc <zs_str_of_u64+0x170> @ imm = #0x10
     8ea:      	add.w	r1, r10, #0x1
     8ee:      	mov	r12, r10
     8f0:      	b	0x8fa <zs_str_of_u64+0x16e> @ imm = #0x6
     8f2:      	add.w	r1, r10, #0x2
     8f6:      	add.w	r12, r10, #0x1
     8fa:      	mov	r10, r1
     8fc:      	and	lr, r1, #0x3
     900:      	lsrs	r3, r1, #0x2
     902:      	mov.w	r1, #0x0
     906:      	beq	0x93a <zs_str_of_u64+0x1ae> @ imm = #0x30
     908:      	add	r6, sp, #0x4
     90a:      	add.w	r5, r12, r8
     90e:      	sub.w	r9, r1, r3, lsl #2
     912:      	subs	r6, #0x3
     914:      	subs	r5, #0x1
     916:      	nop
     918:      	adds	r4, r5, r1
     91a:      	ldrb	r3, [r5, r1]
     91c:      	ldrb	r0, [r4, #-2]
     920:      	ldrb	r2, [r4, #-1]
     924:      	ldrb	r4, [r4, #0x1]
     926:      	subs	r1, #0x4
     928:      	strb	r3, [r6, #4]!
     92c:      	cmp	r9, r1
     92e:      	strb	r4, [r6, #-1]
     932:      	strb	r2, [r6, #0x1]
     934:      	strb	r0, [r6, #0x2]
     936:      	bne	0x918 <zs_str_of_u64+0x18c> @ imm = #-0x22
     938:      	rsbs	r1, r1, #0
     93a:      	cmp.w	lr, #0x0
     93e:      	beq	0x970 <zs_str_of_u64+0x1e4> @ imm = #0x2e
     940:      	sub.w	r0, r12, r1
     944:      	ldrb.w	r0, [r8, r0]
     948:      	add	r3, sp, #0x4
     94a:      	cmp.w	lr, #0x1
     94e:      	strb	r0, [r3, r1]
     950:      	beq	0x970 <zs_str_of_u64+0x1e4> @ imm = #0x1c
     952:      	adds	r0, r1, #0x1
     954:      	sub.w	r2, r12, r0
     958:      	ldrb.w	r2, [r8, r2]
     95c:      	cmp.w	lr, #0x2
     960:      	strb	r2, [r3, r0]
     962:      	beq	0x970 <zs_str_of_u64+0x1e4> @ imm = #0xa
     964:      	adds	r0, r1, #0x2
     966:      	sub.w	r1, r12, r0
     96a:      	ldrb.w	r1, [r8, r1]
     96e:      	strb	r1, [r3, r0]
     970:      	add	r0, sp, #0x4
     972:      	mov	r2, r10
     974:      	movs	r3, #0x0
     976:      	bl	0x984 <str_of>          @ imm = #0xa
     97a:      	add	sp, #0x34
     97c:      	pop.w	{r8, r9, r10, r11}
     980:      	pop	{r4, r5, r6, r7, pc}
     982:      	bmi	0x92e <zs_str_of_u64+0x1a2> @ imm = #-0x58

00000984 <str_of>:
     984:      	push	{r4, r5, r6, r7, lr}
     986:      	add	r7, sp, #0xc
     988:      	str	r8, [sp, #-4]!
     98c:      	add.w	r12, r2, #0x18
     990:      	lsr.w	r1, r12, #0x3
     994:      	cmp	r1, #0x20
     996:      	bhi	0x9b4 <str_of+0x30>     @ imm = #0x1a
     998:      	movw	r4, #0x0
     99c:      	movt	r4, #0x2000
     9a0:      	ldr.w	r5, [r4, r1, lsl #2]
     9a4:      	cbz	r5, 0x9b4 <str_of+0x30> @ imm = #0xc
     9a6:      	mov	r12, r5
     9a8:      	ldr	r5, [r5]
     9aa:      	ldr	lr, [r12, #-8]!
     9ae:      	str.w	r5, [r4, r1, lsl #2]
     9b2:      	b	0x9ec <str_of+0x68>     @ imm = #0x36
     9b4:      	movw	r6, #0x84
     9b8:      	movt	r6, #0x2000
     9bc:      	ldr	r1, [r6]
     9be:      	bic	lr, r12, #0x7
     9c2:      	add.w	r5, lr, r1
     9c6:      	movw	r4, #0xfff9
     9ca:      	subs	r4, r5, r4
     9cc:      	cmn.w	r4, #0x10001
     9d0:      	blo	0xacc <str_of+0x148>    @ imm = #0xf8
     9d2:      	movw	r4, #0x88
     9d6:      	movt	r4, #0x2000
     9da:      	add.w	r12, r4, r1
     9de:      	adds	r5, #0x8
     9e0:      	str.w	lr, [r4, r1]
     9e4:      	movs	r1, #0x0
     9e6:      	str	r5, [r6]
     9e8:      	str.w	r1, [r12, #0x4]
     9ec:      	movw	r4, #0x88
     9f0:      	movt	r4, #0x2001
     9f4:      	movw	r1, #0x8c
     9f8:      	ldr	r5, [r4]
     9fa:      	movt	r1, #0x2001
     9fe:      	ldr	r6, [r1]
     a00:      	add	r5, lr
     a02:      	movw	lr, #0x90
     a06:      	cmp	r5, r6
     a08:      	str	r5, [r4]
     a0a:      	it	hi
     a0c:      	strhi	r5, [r1]
     a0e:      	movt	lr, #0x2001
     a12:      	movw	r8, #0x98
     a16:      	ldrd	r6, r5, [lr]
     a1a:      	movt	r8, #0x2001
     a1e:      	ldrd	r1, r4, [r8]
     a22:      	adds	r6, #0x1
     a24:      	adc	r5, r5, #0x0
     a28:      	adds	r1, #0x1
     a2a:      	strd	r6, r5, [lr]
     a2e:      	adc	r6, r4, #0x0
     a32:      	strd	r1, r6, [r8]
     a36:      	movs	r6, #0x1
     a38:      	mov	r1, r12
     a3a:      	str	r6, [r1, #8]!
     a3e:      	movs	r4, #0x0
     a40:      	add.w	lr, r1, #0x10
     a44:      	strd	r4, r2, [r1, #4]
     a48:      	str	r3, [r1, #0xc]
     a4a:      	strb.w	r4, [lr, r2]
     a4e:      	cbz	r2, 0xac4 <str_of+0x140> @ imm = #0x72
     a50:      	ands	r3, r2, #0x3
     a54:      	beq	0xa72 <str_of+0xee>     @ imm = #0x1a
     a56:      	mov	r4, r0
     a58:      	ldrb	r6, [r4], #1
     a5c:      	cmp	r3, #0x1
     a5e:      	strb.w	r6, [r12, #0x18]
     a62:      	bne	0xa7a <str_of+0xf6>     @ imm = #0x14
     a64:      	subs	r3, r2, #0x1
     a66:      	add.w	lr, r12, #0x19
     a6a:      	mov	r0, r4
     a6c:      	cmp	r2, #0x4
     a6e:      	bhs	0xaa4 <str_of+0x120>    @ imm = #0x32
     a70:      	b	0xac4 <str_of+0x140>    @ imm = #0x50
     a72:      	mov	r3, r2
     a74:      	cmp	r2, #0x4
     a76:      	bhs	0xaa4 <str_of+0x120>    @ imm = #0x2a
     a78:      	b	0xac4 <str_of+0x140>    @ imm = #0x48
     a7a:      	ldrb	r6, [r0, #0x1]
     a7c:      	cmp	r3, #0x2
     a7e:      	strb.w	r6, [r12, #0x19]
     a82:      	bne	0xa92 <str_of+0x10e>    @ imm = #0xc
     a84:      	subs	r3, r2, #0x2
     a86:      	adds	r0, #0x2
     a88:      	add.w	lr, r12, #0x1a
     a8c:      	cmp	r2, #0x4
     a8e:      	bhs	0xaa4 <str_of+0x120>    @ imm = #0x12
     a90:      	b	0xac4 <str_of+0x140>    @ imm = #0x30
     a92:      	ldrb	r4, [r0, #0x2]
     a94:      	subs	r3, r2, #0x3
     a96:      	adds	r0, #0x3
     a98:      	add.w	lr, r12, #0x1b
     a9c:      	strb.w	r4, [r12, #0x1a]
     aa0:      	cmp	r2, #0x4
     aa2:      	blo	0xac4 <str_of+0x140>    @ imm = #0x1e
     aa4:      	subs	r0, #0x4
     aa6:      	sub.w	r2, lr, #0x4
     aaa:      	nop
     aac:      	ldrb	r6, [r0, #4]!
     ab0:      	subs	r3, #0x4
     ab2:      	strb	r6, [r2, #4]!
     ab6:      	ldrb	r6, [r0, #0x1]
     ab8:      	strb	r6, [r2, #0x1]
     aba:      	ldrb	r6, [r0, #0x2]
     abc:      	strb	r6, [r2, #0x2]
     abe:      	ldrb	r6, [r0, #0x3]
     ac0:      	strb	r6, [r2, #0x3]
     ac2:      	bne	0xaac <str_of+0x128>    @ imm = #-0x1a
     ac4:      	mov	r0, r1
     ac6:      	ldr	r8, [sp], #4
     aca:      	pop	{r4, r5, r6, r7, pc}
     acc:      	movw	r0, #0x1bc8
     ad0:      	movt	r0, #0x0
     ad4:      	bl	0x524 <zs_panic_c>      @ imm = #-0x5b4

00000ad8 <zs_println>:
     ad8:      	push	{r4, r5, r6, r7, lr}
     ada:      	add	r7, sp, #0xc
     adc:      	push.w	{r8, r9, r10, r11}
     ae0:      	sub	sp, #0x44
     ae2:      	ldrd	r11, r2, [r0, #8]
     ae6:      	subs.w	r1, r11, #0x1
     aea:      	sbcs	r1, r2, #0x0
     aee:      	blt	0xbda <zs_println+0x102> @ imm = #0xe8
     af0:      	sub.w	r1, r7, #0x5d
     af4:      	add.w	lr, r0, #0x10
     af8:      	add.w	r9, r1, #0x1
     afc:      	movs	r3, #0x0
     afe:      	b	0xb1c <zs_println+0x44> @ imm = #0x1a
     b00:      	strb.w	r3, [r1, r8]
     b04:      	movs	r0, #0x4
     b06:      	subs.w	r11, r11, r8
     b0a:      	bkpt	#0xab
     b0c:      	sbc	r2, r2, #0x0
     b10:      	rsbs.w	r0, r11, #0x0
     b14:      	sbcs.w	r0, r3, r2
     b18:      	add	lr, r8
     b1a:      	bge	0xbda <zs_println+0x102> @ imm = #0xbc
     b1c:      	cmp.w	r11, #0x40
     b20:      	mov.w	r8, #0x40
     b24:      	it	lo
     b26:      	movlo	r8, r11
     b28:      	cmp	r2, #0x0
     b2a:      	mov.w	r0, #0x40
     b2e:      	it	ne
     b30:      	movne	r8, r0
     b32:      	lsrs.w	r0, r8, #0x2
     b36:      	beq	0xb9c <zs_println+0xc4> @ imm = #0x62
     b38:      	mov	r1, r2
     b3a:      	sub.w	r10, r3, r0, lsl #2
     b3e:      	add.w	r5, lr, #0x1
     b42:      	mvn	r4, #0x3
     b46:      	nop
     b48:      	adds	r2, r5, r4
     b4a:      	ldrb	r6, [r2, #0x3]
     b4c:      	ldrb	r3, [r2, #0x4]
     b4e:      	ldrb	r0, [r2, #0x5]
     b50:      	cmp	r6, #0x0
     b52:      	ldrb	r2, [r2, #0x6]
     b54:      	it	eq
     b56:      	moveq	r6, #0x20
     b58:      	add.w	r12, r9, r4
     b5c:      	cmp	r3, #0x0
     b5e:      	strb.w	r6, [r12, #0x3]
     b62:      	it	eq
     b64:      	moveq	r3, #0x20
     b66:      	strb.w	r3, [r12, #0x4]
     b6a:      	cmp	r0, #0x0
     b6c:      	it	eq
     b6e:      	moveq	r0, #0x20
     b70:      	adds	r4, #0x4
     b72:      	strb.w	r0, [r12, #0x5]
     b76:      	cmp	r2, #0x0
     b78:      	add.w	r0, r10, r4
     b7c:      	it	eq
     b7e:      	moveq	r2, #0x20
     b80:      	adds	r0, #0x4
     b82:      	strb.w	r2, [r12, #0x6]
     b86:      	bne	0xb48 <zs_println+0x70> @ imm = #-0x42
     b88:      	adds	r0, r4, #0x4
     b8a:      	mov	r2, r1
     b8c:      	sub.w	r1, r7, #0x5d
     b90:      	movs	r3, #0x0
     b92:      	ands	r4, r8, #0x3
     b96:      	bne	0xba4 <zs_println+0xcc> @ imm = #0xa
     b98:      	b	0xb00 <zs_println+0x28> @ imm = #-0x9c
     b9a:      	nop
     b9c:      	movs	r0, #0x0
     b9e:      	ands	r4, r8, #0x3
     ba2:      	beq	0xb00 <zs_println+0x28> @ imm = #-0xa6
     ba4:      	ldrb.w	r5, [lr, r0]
     ba8:      	cmp	r5, #0x0
     baa:      	it	eq
     bac:      	moveq	r5, #0x20
     bae:      	cmp	r4, #0x1
     bb0:      	strb	r5, [r1, r0]
     bb2:      	beq	0xb00 <zs_println+0x28> @ imm = #-0xb6
     bb4:      	add.w	r10, r0, #0x1
     bb8:      	ldrb.w	r5, [lr, r10]
     bbc:      	cmp	r5, #0x0
     bbe:      	it	eq
     bc0:      	moveq	r5, #0x20
     bc2:      	cmp	r4, #0x2
     bc4:      	strb.w	r5, [r1, r10]
     bc8:      	beq	0xb00 <zs_println+0x28> @ imm = #-0xcc
     bca:      	adds	r0, #0x2
     bcc:      	ldrb.w	r4, [lr, r0]
     bd0:      	cmp	r4, #0x0
     bd2:      	it	eq
     bd4:      	moveq	r4, #0x20
     bd6:      	strb	r4, [r1, r0]
     bd8:      	b	0xb00 <zs_println+0x28> @ imm = #-0xdc
     bda:      	movs	r0, #0xa
     bdc:      	strh	r0, [r7, #-93]
     be0:      	movs	r0, #0x4
     be2:      	sub.w	r1, r7, #0x5d
     be6:      	bkpt	#0xab
     be8:      	add	sp, #0x44
     bea:      	pop.w	{r8, r9, r10, r11}
     bee:      	pop	{r4, r5, r6, r7, pc}

00000bf0 <write_c>:
     bf0:      	push	{r4, r5, r6, r7, lr}
     bf2:      	add	r7, sp, #0xc
     bf4:      	push.w	{r8, r9, r10, r11}
     bf8:      	sub	sp, #0x44
     bfa:      	mov	r2, r0
     bfc:      	mov.w	r11, #0xffffffff
     c00:      	add.w	r0, r2, r11
     c04:      	ldrb	r1, [r0, #0x1]
     c06:      	cbz	r1, 0xc20 <write_c+0x30> @ imm = #0x16
     c08:      	ldrb	r1, [r0, #0x2]
     c0a:      	cbz	r1, 0xc2c <write_c+0x3c> @ imm = #0x1e
     c0c:      	ldrb	r1, [r0, #0x3]
     c0e:      	cmp	r1, #0x0
     c10:      	beq.w	0xd20 <write_c+0x130>   @ imm = #0x10c
     c14:      	ldrb	r0, [r0, #0x4]
     c16:      	add.w	r11, r11, #0x4
     c1a:      	cmp	r0, #0x0
     c1c:      	bne	0xc00 <write_c+0x10>    @ imm = #-0x20
     c1e:      	b	0xc30 <write_c+0x40>    @ imm = #0xe
     c20:      	add.w	r11, r11, #0x1
     c24:      	cmp.w	r11, #0x0
     c28:      	bne	0xc36 <write_c+0x46>    @ imm = #0xa
     c2a:      	b	0xd2c <write_c+0x13c>   @ imm = #0xfe
     c2c:      	add.w	r11, r11, #0x2
     c30:      	cmp.w	r11, #0x0
     c34:      	beq	0xd2c <write_c+0x13c>   @ imm = #0xf4
     c36:      	sub.w	r1, r7, #0x5d
     c3a:      	movs	r3, #0x0
     c3c:      	add.w	r12, r1, #0x1
     c40:      	movs	r6, #0x40
     c42:      	mov.w	r9, #0x0
     c46:      	b	0xc64 <write_c+0x74>    @ imm = #0x1a
     c48:      	strb.w	r3, [r1, r8]
     c4c:      	movs	r0, #0x4
     c4e:      	subs.w	r11, r11, r8
     c52:      	bkpt	#0xab
     c54:      	sbc	r9, r9, #0x0
     c58:      	rsbs.w	r0, r11, #0x0
     c5c:      	sbcs.w	r0, r3, r9
     c60:      	add	r2, r8
     c62:      	bge	0xd2c <write_c+0x13c>   @ imm = #0xc6
     c64:      	mov.w	r8, #0x40
     c68:      	cmp.w	r11, #0x40
     c6c:      	it	lo
     c6e:      	movlo	r8, r11
     c70:      	cmp.w	r9, #0x0
     c74:      	it	ne
     c76:      	movne	r8, r6
     c78:      	sub.w	r0, r8, #0x1
     c7c:      	cmp	r0, #0x3
     c7e:      	bhs	0xc8c <write_c+0x9c>    @ imm = #0xa
     c80:      	movs	r0, #0x0
     c82:      	ands	r4, r8, #0x3
     c86:      	bne	0xcee <write_c+0xfe>    @ imm = #0x64
     c88:      	b	0xc48 <write_c+0x58>    @ imm = #-0x44
     c8a:      	nop
     c8c:      	bic	r0, r8, #0x3
     c90:      	rsb.w	r10, r0, #0x0
     c94:      	mov	r1, r2
     c96:      	adds	r5, r2, #0x1
     c98:      	mvn	r4, #0x3
     c9c:      	adds	r3, r5, r4
     c9e:      	ldrb	r6, [r3, #0x3]
     ca0:      	ldrb	r2, [r3, #0x4]
     ca2:      	ldrb	r0, [r3, #0x5]
     ca4:      	cmp	r6, #0x0
     ca6:      	ldrb	r3, [r3, #0x6]
     ca8:      	it	eq
     caa:      	moveq	r6, #0x20
     cac:      	add.w	lr, r12, r4
     cb0:      	cmp	r2, #0x0
     cb2:      	strb.w	r6, [lr, #0x3]
     cb6:      	it	eq
     cb8:      	moveq	r2, #0x20
     cba:      	strb.w	r2, [lr, #0x4]
     cbe:      	cmp	r0, #0x0
     cc0:      	it	eq
     cc2:      	moveq	r0, #0x20
     cc4:      	adds	r4, #0x4
     cc6:      	strb.w	r0, [lr, #0x5]
     cca:      	cmp	r3, #0x0
     ccc:      	add.w	r0, r10, r4
     cd0:      	it	eq
     cd2:      	moveq	r3, #0x20
     cd4:      	adds	r0, #0x4
     cd6:      	strb.w	r3, [lr, #0x6]
     cda:      	bne	0xc9c <write_c+0xac>    @ imm = #-0x42
     cdc:      	adds	r0, r4, #0x4
     cde:      	mov	r2, r1
     ce0:      	movs	r3, #0x0
     ce2:      	sub.w	r1, r7, #0x5d
     ce6:      	movs	r6, #0x40
     ce8:      	ands	r4, r8, #0x3
     cec:      	beq	0xc48 <write_c+0x58>    @ imm = #-0xa8
     cee:      	ldrb	r5, [r2, r0]
     cf0:      	cmp	r5, #0x0
     cf2:      	it	eq
     cf4:      	moveq	r5, #0x20
     cf6:      	cmp	r4, #0x1
     cf8:      	strb	r5, [r1, r0]
     cfa:      	beq	0xc48 <write_c+0x58>    @ imm = #-0xb6
     cfc:      	add.w	r10, r0, #0x1
     d00:      	ldrb.w	r5, [r2, r10]
     d04:      	cmp	r5, #0x0
     d06:      	it	eq
     d08:      	moveq	r5, #0x20
     d0a:      	cmp	r4, #0x2
     d0c:      	strb.w	r5, [r1, r10]
     d10:      	beq	0xc48 <write_c+0x58>    @ imm = #-0xcc
     d12:      	adds	r0, #0x2
     d14:      	ldrb	r4, [r2, r0]
     d16:      	cmp	r4, #0x0
     d18:      	it	eq
     d1a:      	moveq	r4, #0x20
     d1c:      	strb	r4, [r1, r0]
     d1e:      	b	0xc48 <write_c+0x58>    @ imm = #-0xda
     d20:      	add.w	r11, r11, #0x3
     d24:      	cmp.w	r11, #0x0
     d28:      	bne.w	0xc36 <write_c+0x46>    @ imm = #-0xf6
     d2c:      	add	sp, #0x44
     d2e:      	pop.w	{r8, r9, r10, r11}
     d32:      	pop	{r4, r5, r6, r7, pc}

00000d34 <stop>:
     d34:      	push	{r4, r5, r6, r7, lr}
     d36:      	add	r7, sp, #0xc
     d38:      	str	r11, [sp, #-4]!
     d3c:      	sub	sp, #0x48
     d3e:      	movw	r6, #0x8000
     d42:      	movw	r5, #0x0
     d46:      	movt	r6, #0x203f
     d4a:      	movt	r5, #0x2040
     d4e:      	cmp	r6, r5
     d50:      	mov	r4, r0
     d52:      	bhs	0xd9e <stop+0x6a>       @ imm = #0x48
     d54:      	movw	r0, #0x8000
     d58:      	movt	r0, #0x203f
     d5c:      	ldr	r1, [r0]
     d5e:      	cmp.w	r1, #0xcdcdcdcd
     d62:      	bne	0xd9c <stop+0x68>       @ imm = #0x36
     d64:      	adds	r6, r0, #0x4
     d66:      	cmp	r6, r5
     d68:      	bhs	0xd9e <stop+0x6a>       @ imm = #0x32
     d6a:      	ldr	r1, [r6]
     d6c:      	cmp.w	r1, #0xcdcdcdcd
     d70:      	bne	0xd9e <stop+0x6a>       @ imm = #0x2a
     d72:      	add.w	r6, r0, #0x8
     d76:      	cmp	r6, r5
     d78:      	bhs	0xd9e <stop+0x6a>       @ imm = #0x22
     d7a:      	ldr	r1, [r6]
     d7c:      	cmp.w	r1, #0xcdcdcdcd
     d80:      	bne	0xd9e <stop+0x6a>       @ imm = #0x1a
     d82:      	add.w	r6, r0, #0xc
     d86:      	cmp	r6, r5
     d88:      	bhs	0xd9e <stop+0x6a>       @ imm = #0x12
     d8a:      	ldr	r1, [r6]
     d8c:      	cmp.w	r1, #0xcdcdcdcd
     d90:      	bne	0xd9e <stop+0x6a>       @ imm = #0xa
     d92:      	adds	r0, #0x10
     d94:      	cmp	r0, r5
     d96:      	mov	r6, r0
     d98:      	blo	0xd5c <stop+0x28>       @ imm = #-0x40
     d9a:      	b	0xd9e <stop+0x6a>       @ imm = #0x0
     d9c:      	mov	r6, r0
     d9e:      	movw	r0, #0x8c
     da2:      	movt	r0, #0x2001
     da6:      	ldr	r2, [r0]
     da8:      	movw	r0, #0x1bf7
     dac:      	movt	r0, #0x0
     db0:      	movs	r3, #0x0
     db2:      	bl	0xfa4 <text>            @ imm = #0x1ee
     db6:      	movw	r0, #0x84
     dba:      	movt	r0, #0x2000
     dbe:      	ldr	r2, [r0]
     dc0:      	movw	r0, #0x1c0d
     dc4:      	movt	r0, #0x0
     dc8:      	movs	r3, #0x0
     dca:      	bl	0xfa4 <text>            @ imm = #0x1d6
     dce:      	movw	r0, #0x98
     dd2:      	movt	r0, #0x2001
     dd6:      	ldrd	r2, r3, [r0]
     dda:      	movw	r0, #0x1be1
     dde:      	movt	r0, #0x0
     de2:      	bl	0xfa4 <text>            @ imm = #0x1be
     de6:      	movw	r0, #0x90
     dea:      	movt	r0, #0x2001
     dee:      	ldrd	r2, r3, [r0]
     df2:      	movw	r0, #0x1c06
     df6:      	movt	r0, #0x0
     dfa:      	bl	0xfa4 <text>            @ imm = #0x1a6
     dfe:      	subs	r2, r5, r6
     e00:      	movw	r0, #0x1bef
     e04:      	asrs	r3, r2, #0x1f
     e06:      	movt	r0, #0x0
     e0a:      	bl	0xfa4 <text>            @ imm = #0x196
     e0e:      	movs	r0, #0xa
     e10:      	strh.w	r0, [sp, #0x4]
     e14:      	movs	r0, #0x4
     e16:      	add	r1, sp, #0x4
     e18:      	bkpt	#0xab
     e1a:      	movs	r0, #0x26
     e1c:      	movt	r0, #0x2
     e20:      	strd	r0, r4, [sp, #4]
     e24:      	movs	r0, #0x20
     e26:      	add	r1, sp, #0x4
     e28:      	bkpt	#0xab
     e2a:      	nop
     e2c:      	b	0xe2c <stop+0xf8>       @ imm = #-0x4
     e2e:      	bmi	0xdda <stop+0xa6>       @ imm = #-0x58

00000e30 <zs_set_args>:
     e30:      	push	{r7, lr}
     e32:      	mov	r7, sp
     e34:      	pop	{r7, pc}
     e36:      	bmi	0xde2 <stop+0xae>       @ imm = #-0x58

00000e38 <Reset_Handler>:
     e38:      	push	{r7, lr}
     e3a:      	mov	r7, sp
     e3c:      	movw	r0, #0x0
     e40:      	movw	r1, #0x0
     e44:      	movt	r0, #0x2000
     e48:      	movt	r1, #0x2000
     e4c:      	cmp	r1, r0
     e4e:      	bhs	0xe82 <Reset_Handler+0x4a> @ imm = #0x30
     e50:      	movw	r2, #0x1d40
     e54:      	movt	r2, #0x0
     e58:      	ldr	r3, [r2]
     e5a:      	str	r3, [r1], #4
     e5e:      	cmp	r1, r0
     e60:      	bhs	0xe82 <Reset_Handler+0x4a> @ imm = #0x1e
     e62:      	ldr	r3, [r2, #0x4]
     e64:      	str	r3, [r1], #4
     e68:      	cmp	r1, r0
     e6a:      	bhs	0xe82 <Reset_Handler+0x4a> @ imm = #0x14
     e6c:      	ldr	r3, [r2, #0x8]
     e6e:      	str	r3, [r1], #4
     e72:      	cmp	r1, r0
     e74:      	bhs	0xe82 <Reset_Handler+0x4a> @ imm = #0xa
     e76:      	ldr	r3, [r2, #0xc]
     e78:      	adds	r2, #0x10
     e7a:      	str	r3, [r1], #4
     e7e:      	cmp	r1, r0
     e80:      	blo	0xe58 <Reset_Handler+0x20> @ imm = #-0x2c
     e82:      	movw	r0, #0xa4
     e86:      	movw	r1, #0x0
     e8a:      	movt	r0, #0x2001
     e8e:      	movt	r1, #0x2000
     e92:      	cmp	r1, r0
     e94:      	bhs	0xeb8 <Reset_Handler+0x80> @ imm = #0x20
     e96:      	movs	r2, #0x0
     e98:      	str	r2, [r1], #4
     e9c:      	cmp	r1, r0
     e9e:      	bhs	0xeb8 <Reset_Handler+0x80> @ imm = #0x16
     ea0:      	str	r2, [r1], #4
     ea4:      	cmp	r1, r0
     ea6:      	bhs	0xeb8 <Reset_Handler+0x80> @ imm = #0xe
     ea8:      	str	r2, [r1], #4
     eac:      	cmp	r1, r0
     eae:      	bhs	0xeb8 <Reset_Handler+0x80> @ imm = #0x6
     eb0:      	str	r2, [r1], #4
     eb4:      	cmp	r1, r0
     eb6:      	blo	0xe98 <Reset_Handler+0x60> @ imm = #-0x22
     eb8:      	movw	r0, #0xed88
     ebc:      	movt	r0, #0xe000
     ec0:      	ldr	r1, [r0]
     ec2:      	orr	r1, r1, #0xf00000
     ec6:      	str	r1, [r0]
     ec8:      	movw	r0, #0xe010
     ecc:      	movt	r0, #0xe000
     ed0:      	mvn	r1, #0xff000000
     ed4:      	dsb	sy
     ed8:      	isb	sy
     edc:      	str	r1, [r0, #0x4]
     ede:      	movs	r1, #0x0
     ee0:      	str	r1, [r0, #0x8]
     ee2:      	movs	r1, #0x7
     ee4:      	str	r1, [r0]
     ee6:      	mov	r0, sp
     ee8:      	movw	r1, #0x8000
     eec:      	subs	r0, #0x40
     eee:      	movt	r1, #0x203f
     ef2:      	cmp	r0, r1
     ef4:      	bls	0xf1c <Reset_Handler+0xe4> @ imm = #0x24
     ef6:      	mov.w	r2, #0xcdcdcdcd
     efa:      	nop
     efc:      	str	r2, [r1], #4
     f00:      	cmp	r1, r0
     f02:      	bhs	0xf1c <Reset_Handler+0xe4> @ imm = #0x16
     f04:      	str	r2, [r1], #4
     f08:      	cmp	r1, r0
     f0a:      	bhs	0xf1c <Reset_Handler+0xe4> @ imm = #0xe
     f0c:      	str	r2, [r1], #4
     f10:      	cmp	r1, r0
     f12:      	bhs	0xf1c <Reset_Handler+0xe4> @ imm = #0x6
     f14:      	str	r2, [r1], #4
     f18:      	cmp	r1, r0
     f1a:      	blo	0xefc <Reset_Handler+0xc4> @ imm = #-0x22
     f1c:      	movs	r0, #0x0
     f1e:      	movs	r1, #0x0
     f20:      	bl	0x40 <main>             @ imm = #-0xee4
     f24:      	bl	0xd34 <stop>            @ imm = #-0x1f4

00000f28 <zs_ticks>:
     f28:      	push	{r7, lr}
     f2a:      	mov	r7, sp
     f2c:      	movw	r12, #0xe018
     f30:      	movw	r2, #0xa0
     f34:      	movt	r12, #0xe000
     f38:      	movt	r2, #0x2001
     f3c:      	ldr	r1, [r2]
     f3e:      	ldr.w	r3, [r12]
     f42:      	ldr	r0, [r2]
     f44:      	cmp	r1, r0
     f46:      	beq	0xf6c <zs_ticks+0x44>   @ imm = #0x22
     f48:      	ldr	r1, [r2]
     f4a:      	ldr.w	r3, [r12]
     f4e:      	ldr	r0, [r2]
     f50:      	cmp	r1, r0
     f52:      	beq	0xf6c <zs_ticks+0x44>   @ imm = #0x16
     f54:      	ldr	r1, [r2]
     f56:      	ldr.w	r3, [r12]
     f5a:      	ldr	r0, [r2]
     f5c:      	cmp	r1, r0
     f5e:      	beq	0xf6c <zs_ticks+0x44>   @ imm = #0xa
     f60:      	ldr	r1, [r2]
     f62:      	ldr.w	r3, [r12]
     f66:      	ldr	r0, [r2]
     f68:      	cmp	r1, r0
     f6a:      	bne	0xf3c <zs_ticks+0x14>   @ imm = #-0x32
     f6c:      	mvn	r0, #0xff000000
     f70:      	subs	r0, r0, r3
     f72:      	lsrs	r2, r1, #0x8
     f74:      	adds.w	r0, r0, r1, lsl #24
     f78:      	adc	r1, r2, #0x0
     f7c:      	pop	{r7, pc}
     f7e:      	bmi	0xf2a <zs_ticks+0x2>    @ imm = #-0x58

00000f80 <fault>:
     f80:      	push	{r7, lr}
     f82:      	mov	r7, sp
     f84:      	movw	r0, #0x1bd6
     f88:      	movt	r0, #0x0
     f8c:      	bl	0x524 <zs_panic_c>      @ imm = #-0xa6c

00000f90 <SysTick_Handler>:
     f90:      	push	{r7, lr}
     f92:      	mov	r7, sp
     f94:      	movw	r0, #0xa0
     f98:      	movt	r0, #0x2001
     f9c:      	ldr	r1, [r0]
     f9e:      	adds	r1, #0x1
     fa0:      	str	r1, [r0]
     fa2:      	pop	{r7, pc}

00000fa4 <text>:
     fa4:      	push	{r4, r5, r6, r7, lr}
     fa6:      	add	r7, sp, #0xc
     fa8:      	push.w	{r8, r9, r10, r11}
     fac:      	sub	sp, #0x64
     fae:      	strd	r2, r3, [sp]
     fb2:      	mov	r3, r0
     fb4:      	mov.w	r12, #0xffffffff
     fb8:      	add.w	r0, r3, r12
     fbc:      	ldrb	r1, [r0, #0x1]
     fbe:      	cbz	r1, 0xfda <text+0x36>   @ imm = #0x18
     fc0:      	ldrb	r1, [r0, #0x2]
     fc2:      	cbz	r1, 0xfe6 <text+0x42>   @ imm = #0x20
     fc4:      	ldrb	r1, [r0, #0x3]
     fc6:      	cbz	r1, 0xff2 <text+0x4e>   @ imm = #0x28
     fc8:      	ldrb	r0, [r0, #0x4]
     fca:      	add.w	r12, r12, #0x4
     fce:      	cmp	r0, #0x0
     fd0:      	bne	0xfb8 <text+0x14>       @ imm = #-0x1c
     fd2:      	cmp.w	r12, #0x0
     fd6:      	bne	0xffc <text+0x58>       @ imm = #0x22
     fd8:      	b	0x10ea <text+0x146>     @ imm = #0x10e
     fda:      	add.w	r12, r12, #0x1
     fde:      	cmp.w	r12, #0x0
     fe2:      	bne	0xffc <text+0x58>       @ imm = #0x16
     fe4:      	b	0x10ea <text+0x146>     @ imm = #0x102
     fe6:      	add.w	r12, r12, #0x2
     fea:      	cmp.w	r12, #0x0
     fee:      	bne	0xffc <text+0x58>       @ imm = #0xa
     ff0:      	b	0x10ea <text+0x146>     @ imm = #0xf6
     ff2:      	add.w	r12, r12, #0x3
     ff6:      	cmp.w	r12, #0x0
     ffa:      	beq	0x10ea <text+0x146>     @ imm = #0xec
     ffc:      	sub.w	r1, r7, #0x5d
    1000:      	movs	r4, #0x0
    1002:      	add.w	r10, r1, #0x1
    1006:      	movs	r5, #0x40
    1008:      	mov.w	r9, #0x0
    100c:      	b	0x102c <text+0x88>      @ imm = #0x1c
    100e:      	nop
    1010:      	strb.w	r4, [r1, r11]
    1014:      	movs	r0, #0x4
    1016:      	subs.w	r12, r12, r11
    101a:      	bkpt	#0xab
    101c:      	sbc	r9, r9, #0x0
    1020:      	rsbs.w	r0, r12, #0x0
    1024:      	sbcs.w	r0, r4, r9
    1028:      	add	r3, r11
    102a:      	bge	0x10ea <text+0x146>     @ imm = #0xbc
    102c:      	mov.w	r11, #0x40
    1030:      	cmp.w	r12, #0x40
    1034:      	it	lo
    1036:      	movlo	r11, r12
    1038:      	cmp.w	r9, #0x0
    103c:      	it	ne
    103e:      	movne	r11, r5
    1040:      	sub.w	r0, r11, #0x1
    1044:      	cmp	r0, #0x3
    1046:      	bhs	0x1054 <text+0xb0>      @ imm = #0xa
    1048:      	movs	r0, #0x0
    104a:      	ands	r2, r11, #0x3
    104e:      	bne	0x10b6 <text+0x112>     @ imm = #0x64
    1050:      	b	0x1010 <text+0x6c>      @ imm = #-0x44
    1052:      	nop
    1054:      	bic	r0, r11, #0x3
    1058:      	rsb.w	lr, r0, #0x0
    105c:      	mov	r1, r3
    105e:      	adds	r6, r3, #0x1
    1060:      	mvn	r2, #0x3
    1064:      	adds	r3, r6, r2
    1066:      	ldrb	r5, [r3, #0x3]
    1068:      	ldrb	r4, [r3, #0x4]
    106a:      	ldrb	r0, [r3, #0x5]
    106c:      	cmp	r5, #0x0
    106e:      	ldrb	r3, [r3, #0x6]
    1070:      	it	eq
    1072:      	moveq	r5, #0x20
    1074:      	add.w	r8, r10, r2
    1078:      	cmp	r4, #0x0
    107a:      	strb.w	r5, [r8, #0x3]
    107e:      	it	eq
    1080:      	moveq	r4, #0x20
    1082:      	strb.w	r4, [r8, #0x4]
    1086:      	cmp	r0, #0x0
    1088:      	it	eq
    108a:      	moveq	r0, #0x20
    108c:      	adds	r2, #0x4
    108e:      	strb.w	r0, [r8, #0x5]
    1092:      	cmp	r3, #0x0
    1094:      	add.w	r0, lr, r2
    1098:      	it	eq
    109a:      	moveq	r3, #0x20
    109c:      	adds	r0, #0x4
    109e:      	strb.w	r3, [r8, #0x6]
    10a2:      	bne	0x1064 <text+0xc0>      @ imm = #-0x42
    10a4:      	adds	r0, r2, #0x4
    10a6:      	mov	r3, r1
    10a8:      	movs	r4, #0x0
    10aa:      	sub.w	r1, r7, #0x5d
    10ae:      	movs	r5, #0x40
    10b0:      	ands	r2, r11, #0x3
    10b4:      	beq	0x1010 <text+0x6c>      @ imm = #-0xa8
    10b6:      	ldrb	r6, [r3, r0]
    10b8:      	cmp	r6, #0x0
    10ba:      	it	eq
    10bc:      	moveq	r6, #0x20
    10be:      	cmp	r2, #0x1
    10c0:      	strb	r6, [r1, r0]
    10c2:      	beq	0x1010 <text+0x6c>      @ imm = #-0xb6
    10c4:      	adds	r6, r0, #0x1
    10c6:      	ldrb.w	lr, [r3, r6]
    10ca:      	cmp.w	lr, #0x0
    10ce:      	it	eq
    10d0:      	moveq.w	lr, #0x20
    10d4:      	cmp	r2, #0x2
    10d6:      	strb.w	lr, [r1, r6]
    10da:      	beq	0x1010 <text+0x6c>      @ imm = #-0xce
    10dc:      	adds	r0, #0x2
    10de:      	ldrb	r2, [r3, r0]
    10e0:      	cmp	r2, #0x0
    10e2:      	it	eq
    10e4:      	moveq	r2, #0x20
    10e6:      	strb	r2, [r1, r0]
    10e8:      	b	0x1010 <text+0x6c>      @ imm = #-0xdc
    10ea:      	movw	r9, #0xcccd
    10ee:      	ldrd	r4, r5, [sp]
    10f2:      	mov.w	r11, #0x1
    10f6:      	movt	r9, #0xcccc
    10fa:      	sub.w	r10, r7, #0x5d
    10fe:      	nop
    1100:      	lsrs	r0, r4, #0x1
    1102:      	orr.w	r0, r0, r5, lsl #31
    1106:      	adds.w	r1, r0, r5, lsr #1
    110a:      	adc	r1, r1, #0x0
    110e:      	umull	r2, r3, r1, r9
    1112:      	bic	r2, r3, #0x3
    1116:      	add.w	r2, r2, r3, lsr #2
    111a:      	subs	r1, r1, r2
    111c:      	subs	r1, r0, r1
    111e:      	umull	r0, lr, r1, r9
    1122:      	lsr.w	r3, r5, #0x1
    1126:      	add.w	r6, r0, r0, lsl #2
    112a:      	sbc	r2, r3, #0x0
    112e:      	sub.w	r6, r4, r6, lsl #1
    1132:      	mov	r3, r4
    1134:      	subs	r4, #0xa
    1136:      	orr	r12, r6, #0x30
    113a:      	add.w	r8, r10, r11
    113e:      	sbcs	r4, r5, #0x0
    1142:      	strb	r12, [r8, #-1]
    1146:      	blo	0x123e <text+0x29a>     @ imm = #0xf4
    1148:      	mov.w	r4, #0xcccccccc
    114c:      	mla	r1, r1, r4, lr
    1150:      	mla	r1, r2, r9, r1
    1154:      	lsrs	r2, r0, #0x1
    1156:      	orr.w	r2, r2, r1, lsl #31
    115a:      	adds.w	r1, r2, r1, lsr #1
    115e:      	adc	r1, r1, #0x0
    1162:      	umull	r2, r4, r1, r9
    1166:      	bic	r2, r4, #0x3
    116a:      	add.w	r2, r2, r4, lsr #2
    116e:      	subs	r1, r1, r2
    1170:      	and	r0, r0, #0x1
    1174:      	orr.w	r0, r0, r1, lsl #1
    1178:      	subs.w	r1, r3, #0x64
    117c:      	orr	r0, r0, #0x30
    1180:      	sbcs	r1, r5, #0x0
    1184:      	mov	r4, r10
    1186:      	strb.w	r0, [r10, r11]
    118a:      	blo	0x1248 <text+0x2a4>     @ imm = #0xba
    118c:      	mov	r6, r3
    118e:      	mov	r0, r3
    1190:      	mov	r1, r5
    1192:      	movs	r2, #0x64
    1194:      	movs	r3, #0x0
    1196:      	bl	0x157c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x3e2
    119a:      	lsrs	r2, r0, #0x1
    119c:      	orr.w	r2, r2, r1, lsl #31
    11a0:      	adds.w	r1, r2, r1, lsr #1
    11a4:      	adc	r1, r1, #0x0
    11a8:      	umull	r2, r3, r1, r9
    11ac:      	bic	r2, r3, #0x3
    11b0:      	add.w	r2, r2, r3, lsr #2
    11b4:      	subs	r1, r1, r2
    11b6:      	and	r0, r0, #0x1
    11ba:      	orr.w	r0, r0, r1, lsl #1
    11be:      	subs.w	r1, r6, #0x3e8
    11c2:      	orr	r0, r0, #0x30
    11c6:      	sbcs	r1, r5, #0x0
    11ca:      	strb.w	r0, [r8, #0x1]
    11ce:      	blo	0x1250 <text+0x2ac>     @ imm = #0x7e
    11d0:      	mov	r0, r6
    11d2:      	mov	r1, r5
    11d4:      	mov.w	r2, #0x3e8
    11d8:      	movs	r3, #0x0
    11da:      	mov	r10, r4
    11dc:      	bl	0x157c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x39c
    11e0:      	lsrs	r2, r0, #0x1
    11e2:      	orr.w	r2, r2, r1, lsl #31
    11e6:      	adds.w	r1, r2, r1, lsr #1
    11ea:      	adc	r1, r1, #0x0
    11ee:      	umull	r2, r3, r1, r9
    11f2:      	bic	r2, r3, #0x3
    11f6:      	add.w	r2, r2, r3, lsr #2
    11fa:      	subs	r1, r1, r2
    11fc:      	and	r0, r0, #0x1
    1200:      	orr.w	r0, r0, r1, lsl #1
    1204:      	orr	r0, r0, #0x30
    1208:      	strb.w	r0, [r8, #0x2]
    120c:      	mov	r0, r6
    120e:      	mov	r1, r5
    1210:      	movw	r2, #0x2710
    1214:      	movs	r3, #0x0
    1216:      	bl	0x157c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x362
    121a:      	movw	r2, #0x270f
    121e:      	subs	r2, r2, r6
    1220:      	mov.w	r2, #0x0
    1224:      	sbcs	r2, r5
    1226:      	add.w	r11, r11, #0x4
    122a:      	mov	r4, r0
    122c:      	mov	r5, r1
    122e:      	blo.w	0x1100 <text+0x15c>     @ imm = #-0x132
    1232:      	sub.w	r1, r11, #0x1
    1236:      	sub.w	r12, r11, #0x2
    123a:      	mov	r11, r1
    123c:      	b	0x1244 <text+0x2a0>     @ imm = #0x4
    123e:      	sub.w	r12, r11, #0x1
    1242:      	mov	r1, r11
    1244:      	mov	r4, r10
    1246:      	b	0x125a <text+0x2b6>     @ imm = #0x10
    1248:      	add.w	r1, r11, #0x1
    124c:      	mov	r12, r11
    124e:      	b	0x1258 <text+0x2b4>     @ imm = #0x6
    1250:      	add.w	r1, r11, #0x2
    1254:      	add.w	r12, r11, #0x1
    1258:      	mov	r11, r1
    125a:      	and	lr, r1, #0x3
    125e:      	lsrs	r3, r1, #0x2
    1260:      	mov.w	r1, #0x0
    1264:      	beq	0x129e <text+0x2fa>     @ imm = #0x36
    1266:      	sub.w	r6, r7, #0x75
    126a:      	add.w	r5, r12, r4
    126e:      	sub.w	r9, r1, r3, lsl #2
    1272:      	subs	r6, #0x3
    1274:      	subs	r5, #0x1
    1276:      	nop
    1278:      	adds	r4, r5, r1
    127a:      	ldrb	r3, [r5, r1]
    127c:      	ldrb	r0, [r4, #-2]
    1280:      	ldrb	r2, [r4, #-1]
    1284:      	ldrb	r4, [r4, #0x1]
    1286:      	subs	r1, #0x4
    1288:      	strb	r3, [r6, #4]!
    128c:      	cmp	r9, r1
    128e:      	strb	r4, [r6, #-1]
    1292:      	strb	r2, [r6, #0x1]
    1294:      	strb	r0, [r6, #0x2]
    1296:      	bne	0x1278 <text+0x2d4>     @ imm = #-0x22
    1298:      	rsbs	r1, r1, #0
    129a:      	sub.w	r4, r7, #0x5d
    129e:      	cmp.w	lr, #0x0
    12a2:      	beq	0x12d0 <text+0x32c>     @ imm = #0x2a
    12a4:      	sub.w	r0, r12, r1
    12a8:      	ldrb	r0, [r4, r0]
    12aa:      	sub.w	r3, r7, #0x75
    12ae:      	cmp.w	lr, #0x1
    12b2:      	strb	r0, [r3, r1]
    12b4:      	beq	0x12d0 <text+0x32c>     @ imm = #0x18
    12b6:      	adds	r0, r1, #0x1
    12b8:      	sub.w	r2, r12, r0
    12bc:      	ldrb	r2, [r4, r2]
    12be:      	cmp.w	lr, #0x2
    12c2:      	strb	r2, [r3, r0]
    12c4:      	beq	0x12d0 <text+0x32c>     @ imm = #0x8
    12c6:      	adds	r0, r1, #0x2
    12c8:      	sub.w	r1, r12, r0
    12cc:      	ldrb	r1, [r4, r1]
    12ce:      	strb	r1, [r3, r0]
    12d0:      	sub.w	r0, r7, #0x75
    12d4:      	movs	r1, #0x0
    12d6:      	mov.w	r12, #0xffffffff
    12da:      	strb.w	r1, [r0, r11]
    12de:      	nop
    12e0:      	add.w	r1, r0, r12
    12e4:      	ldrb	r3, [r1, #0x1]
    12e6:      	cbz	r3, 0x1302 <text+0x35e> @ imm = #0x18
    12e8:      	ldrb	r3, [r1, #0x2]
    12ea:      	cbz	r3, 0x130e <text+0x36a> @ imm = #0x20
    12ec:      	ldrb	r3, [r1, #0x3]
    12ee:      	cbz	r3, 0x131a <text+0x376> @ imm = #0x28
    12f0:      	ldrb	r1, [r1, #0x4]
    12f2:      	add.w	r12, r12, #0x4
    12f6:      	cmp	r1, #0x0
    12f8:      	bne	0x12e0 <text+0x33c>     @ imm = #-0x1c
    12fa:      	cmp.w	r12, #0x0
    12fe:      	bne	0x1324 <text+0x380>     @ imm = #0x22
    1300:      	b	0x140c <text+0x468>     @ imm = #0x108
    1302:      	add.w	r12, r12, #0x1
    1306:      	cmp.w	r12, #0x0
    130a:      	bne	0x1324 <text+0x380>     @ imm = #0x16
    130c:      	b	0x140c <text+0x468>     @ imm = #0xfc
    130e:      	add.w	r12, r12, #0x2
    1312:      	cmp.w	r12, #0x0
    1316:      	bne	0x1324 <text+0x380>     @ imm = #0xa
    1318:      	b	0x140c <text+0x468>     @ imm = #0xf0
    131a:      	add.w	r12, r12, #0x3
    131e:      	cmp.w	r12, #0x0
    1322:      	beq	0x140c <text+0x468>     @ imm = #0xe6
    1324:      	movs	r2, #0x0
    1326:      	add.w	lr, r4, #0x1
    132a:      	sub.w	r9, r7, #0x75
    132e:      	movs	r3, #0x40
    1330:      	mov.w	r11, #0x0
    1334:      	b	0x1356 <text+0x3b2>     @ imm = #0x1e
    1336:      	nop
    1338:      	strb.w	r2, [r4, r8]
    133c:      	movs	r0, #0x4
    133e:      	subs.w	r12, r12, r8
    1342:      	mov	r1, r4
    1344:      	bkpt	#0xab
    1346:      	sbc	r11, r11, #0x0
    134a:      	rsbs.w	r0, r12, #0x0
    134e:      	sbcs.w	r0, r2, r11
    1352:      	add	r9, r8
    1354:      	bge	0x140c <text+0x468>     @ imm = #0xb4
    1356:      	mov.w	r8, #0x40
    135a:      	cmp.w	r12, #0x40
    135e:      	it	lo
    1360:      	movlo	r8, r12
    1362:      	cmp.w	r11, #0x0
    1366:      	it	ne
    1368:      	movne	r8, r3
    136a:      	sub.w	r0, r8, #0x1
    136e:      	cmp	r0, #0x3
    1370:      	bhs	0x137c <text+0x3d8>     @ imm = #0x8
    1372:      	movs	r0, #0x0
    1374:      	ands	r1, r8, #0x3
    1378:      	bne	0x13d6 <text+0x432>     @ imm = #0x5a
    137a:      	b	0x1338 <text+0x394>     @ imm = #-0x46
    137c:      	bic	r0, r8, #0x3
    1380:      	rsb.w	r10, r0, #0x0
    1384:      	add.w	r5, r9, #0x1
    1388:      	mvn	r1, #0x3
    138c:      	adds	r4, r5, r1
    138e:      	ldrb	r2, [r4, #0x3]
    1390:      	ldrb	r3, [r4, #0x4]
    1392:      	ldrb	r6, [r4, #0x5]
    1394:      	cmp	r2, #0x0
    1396:      	ldrb	r4, [r4, #0x6]
    1398:      	it	eq
    139a:      	moveq	r2, #0x20
    139c:      	add.w	r0, lr, r1
    13a0:      	cmp	r3, #0x0
    13a2:      	strb	r2, [r0, #0x3]
    13a4:      	it	eq
    13a6:      	moveq	r3, #0x20
    13a8:      	cmp	r6, #0x0
    13aa:      	add.w	r1, r1, #0x4
    13ae:      	strb	r3, [r0, #0x4]
    13b0:      	it	eq
    13b2:      	moveq	r6, #0x20
    13b4:      	cmp	r4, #0x0
    13b6:      	add.w	r2, r10, r1
    13ba:      	strb	r6, [r0, #0x5]
    13bc:      	it	eq
    13be:      	moveq	r4, #0x20
    13c0:      	adds	r2, #0x4
    13c2:      	strb	r4, [r0, #0x6]
    13c4:      	bne	0x138c <text+0x3e8>     @ imm = #-0x3c
    13c6:      	adds	r0, r1, #0x4
    13c8:      	sub.w	r4, r7, #0x5d
    13cc:      	movs	r2, #0x0
    13ce:      	movs	r3, #0x40
    13d0:      	ands	r1, r8, #0x3
    13d4:      	beq	0x1338 <text+0x394>     @ imm = #-0xa0
    13d6:      	ldrb.w	r5, [r9, r0]
    13da:      	cmp	r5, #0x0
    13dc:      	it	eq
    13de:      	moveq	r5, #0x20
    13e0:      	cmp	r1, #0x1
    13e2:      	strb	r5, [r4, r0]
    13e4:      	beq	0x1338 <text+0x394>     @ imm = #-0xb0
    13e6:      	add.w	r10, r0, #0x1
    13ea:      	ldrb.w	r5, [r9, r10]
    13ee:      	cmp	r5, #0x0
    13f0:      	it	eq
    13f2:      	moveq	r5, #0x20
    13f4:      	cmp	r1, #0x2
    13f6:      	strb.w	r5, [r4, r10]
    13fa:      	beq	0x1338 <text+0x394>     @ imm = #-0xc6
    13fc:      	adds	r0, #0x2
    13fe:      	ldrb.w	r1, [r9, r0]
    1402:      	cmp	r1, #0x0
    1404:      	it	eq
    1406:      	moveq	r1, #0x20
    1408:      	strb	r1, [r4, r0]
    140a:      	b	0x1338 <text+0x394>     @ imm = #-0xd6
    140c:      	add	sp, #0x64
    140e:      	pop.w	{r8, r9, r10, r11}
    1412:      	pop	{r4, r5, r6, r7, pc}

00001414 <compiler_rt.memset>:
    1414:      	cmp	r2, #0x0
    1416:      	it	eq
    1418:      	bxeq	lr
    141a:      	push	{r7, lr}
    141c:      	mov	r7, sp
    141e:      	ands	lr, r2, #0x3
    1422:      	mov	r3, r2
    1424:      	mov	r12, r0
    1426:      	beq	0x144a <compiler_rt.memset+0x36> @ imm = #0x20
    1428:      	mov	r12, r0
    142a:      	cmp.w	lr, #0x1
    142e:      	strb	r1, [r12], #1
    1432:      	bne	0x143c <compiler_rt.memset+0x28> @ imm = #0x6
    1434:      	subs	r3, r2, #0x1
    1436:      	cmp	r2, #0x4
    1438:      	bhs	0x144e <compiler_rt.memset+0x3a> @ imm = #0x12
    143a:      	b	0x1462 <compiler_rt.memset+0x4e> @ imm = #0x24
    143c:      	cmp.w	lr, #0x2
    1440:      	strb	r1, [r0, #0x1]
    1442:      	bne	0x1468 <compiler_rt.memset+0x54> @ imm = #0x22
    1444:      	subs	r3, r2, #0x2
    1446:      	add.w	r12, r0, #0x2
    144a:      	cmp	r2, #0x4
    144c:      	blo	0x1462 <compiler_rt.memset+0x4e> @ imm = #0x12
    144e:      	sub.w	r2, r12, #0x4
    1452:      	nop
    1454:      	strb	r1, [r2, #4]!
    1458:      	subs	r3, #0x4
    145a:      	strb	r1, [r2, #0x1]
    145c:      	strb	r1, [r2, #0x2]
    145e:      	strb	r1, [r2, #0x3]
    1460:      	bne	0x1454 <compiler_rt.memset+0x40> @ imm = #-0x10
    1462:      	pop.w	{r7, lr}
    1466:      	bx	lr
    1468:      	subs	r3, r2, #0x3
    146a:      	add.w	r12, r0, #0x3
    146e:      	strb	r1, [r0, #0x2]
    1470:      	cmp	r2, #0x4
    1472:      	bhs	0x144e <compiler_rt.memset+0x3a> @ imm = #-0x28
    1474:      	b	0x1462 <compiler_rt.memset+0x4e> @ imm = #-0x16
    1476:      	bmi	0x1422 <compiler_rt.memset+0xe> @ imm = #-0x58

00001478 <compiler_rt.arm.__aeabi_unwind_cpp_pr0>:
    1478:      	push	{r7, lr}
    147a:      	mov	r7, sp
    147c:      	pop	{r7, pc}
    147e:      	bmi	0x142a <compiler_rt.memset+0x16> @ imm = #-0x58

00001480 <compiler_rt.arm.__aeabi_memclr>:
    1480:      	push	{r7, lr}
    1482:      	mov	r7, sp
    1484:      	mov	r2, r1
    1486:      	movs	r1, #0x0
    1488:      	pop.w	{r7, lr}
    148c:      	b.w	0x1414 <compiler_rt.memset> @ imm = #-0x7c

00001490 <compiler_rt.arm.__aeabi_memcpy>:
    1490:      	push	{r4, r5, r6, r7, lr}
    1492:      	add	r7, sp, #0xc
    1494:      	push.w	{r8, r9, r10, r11}
    1498:      	sub	sp, #0x4
    149a:      	cmp	r2, #0xf
    149c:      	bhi	0x14bc <compiler_rt.arm.__aeabi_memcpy+0x2c> @ imm = #0x1c
    149e:      	cmp	r2, #0x3
    14a0:      	bhi	0x14e4 <compiler_rt.arm.__aeabi_memcpy+0x54> @ imm = #0x40
    14a2:      	cbz	r2, 0x14b4 <compiler_rt.arm.__aeabi_memcpy+0x24> @ imm = #0xe
    14a4:      	ldrb	r3, [r1]
    14a6:      	strb	r3, [r0]
    14a8:      	lsrs	r3, r2, #0x1
    14aa:      	subs	r2, #0x1
    14ac:      	ldrb	r6, [r1, r3]
    14ae:      	ldrb	r1, [r1, r2]
    14b0:      	strb	r6, [r0, r3]
    14b2:      	strb	r1, [r0, r2]
    14b4:      	add	sp, #0x4
    14b6:      	pop.w	{r8, r9, r10, r11}
    14ba:      	pop	{r4, r5, r6, r7, pc}
    14bc:      	ldr	r3, [r1]
    14be:      	mov.w	r6, #0xffffffff
    14c2:      	str	r3, [r0]
    14c4:      	and	r3, r1, #0x3
    14c8:      	rsb.w	lr, r3, #0x4
    14cc:      	sub.w	r4, r2, lr
    14d0:      	add.w	r6, r6, r4, lsr #2
    14d4:      	cmp	r6, #0x3
    14d6:      	ubfx	r6, r4, #0x2, #0x2
    14da:      	str	r6, [sp]
    14dc:      	bhs	0x1508 <compiler_rt.arm.__aeabi_memcpy+0x78> @ imm = #0x28
    14de:      	movs	r3, #0x0
    14e0:      	b	0x153c <compiler_rt.arm.__aeabi_memcpy+0xac> @ imm = #0x58
    14e2:      	nop
    14e4:      	movs	r3, #0x4
    14e6:      	ldr	r6, [r1]
    14e8:      	and.w	r3, r3, r2, lsr #1
    14ec:      	subs	r2, #0x4
    14ee:      	str	r6, [r0]
    14f0:      	ldr	r6, [r1, r3]
    14f2:      	subs	r5, r2, r3
    14f4:      	str	r6, [r0, r3]
    14f6:      	ldr	r3, [r1, r5]
    14f8:      	ldr	r1, [r1, r2]
    14fa:      	str	r3, [r0, r5]
    14fc:      	str	r1, [r0, r2]
    14fe:      	add	sp, #0x4
    1500:      	pop.w	{r8, r9, r10, r11}
    1504:      	pop	{r4, r5, r6, r7, pc}
    1506:      	nop
    1508:      	lsrs	r4, r4, #0x2
    150a:      	bic	r8, r4, #0x3
    150e:      	sub.w	r9, r0, r3
    1512:      	sub.w	r10, r1, r3
    1516:      	movs	r3, #0x0
    1518:      	add.w	r5, r10, r3, lsl #2
    151c:      	add.w	r12, r5, #0x4
    1520:      	add.w	r4, r9, r3, lsl #2
    1524:      	ldm.w	r12, {r6, r11, r12}
    1528:      	ldr	r5, [r5, #0x10]
    152a:      	adds	r3, #0x4
    152c:      	cmp	r8, r3
    152e:      	str	r6, [r4, #0x4]
    1530:      	str.w	r11, [r4, #0x8]
    1534:      	str.w	r12, [r4, #0xc]
    1538:      	str	r5, [r4, #0x10]
    153a:      	bne	0x1518 <compiler_rt.arm.__aeabi_memcpy+0x88> @ imm = #-0x26
    153c:      	ldr	r4, [sp]
    153e:      	cbz	r4, 0x156c <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x2a
    1540:      	add.w	r6, r1, lr
    1544:      	ldr.w	r5, [r6, r3, lsl #2]
    1548:      	add.w	r8, r0, lr
    154c:      	cmp	r4, #0x1
    154e:      	str.w	r5, [r8, r3, lsl #2]
    1552:      	beq	0x156c <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x16
    1554:      	adds	r5, r3, #0x1
    1556:      	ldr.w	r12, [r6, r5, lsl #2]
    155a:      	cmp	r4, #0x2
    155c:      	str.w	r12, [r8, r5, lsl #2]
    1560:      	beq	0x156c <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x8
    1562:      	adds	r3, #0x2
    1564:      	ldr.w	r6, [r6, r3, lsl #2]
    1568:      	str.w	r6, [r8, r3, lsl #2]
    156c:      	subs	r2, #0x4
    156e:      	ldr	r1, [r1, r2]
    1570:      	str	r1, [r0, r2]
    1572:      	add	sp, #0x4
    1574:      	pop.w	{r8, r9, r10, r11}
    1578:      	pop	{r4, r5, r6, r7, pc}
    157a:      	bmi	0x1526 <compiler_rt.arm.__aeabi_memcpy+0x96> @ imm = #-0x58

0000157c <compiler_rt.arm.__aeabi_uldivmod>:
    157c:      	push	{r4, lr}
    157e:      	sub	sp, #0x10
    1580:      	add	r4, sp, #0x8
    1582:      	str	r4, [sp]
    1584:      	bl	0x1590 <compiler_rt.int.__udivmoddi4> @ imm = #0x8
    1588:      	ldr	r2, [sp, #0x8]
    158a:      	ldr	r3, [sp, #0xc]
    158c:      	add	sp, #0x10
    158e:      	pop	{r4, pc}

00001590 <compiler_rt.int.__udivmoddi4>:
    1590:      	push	{r4, r5, r6, r7, lr}
    1592:      	add	r7, sp, #0xc
    1594:      	push.w	{r8, r9, r10, r11}
    1598:      	sub	sp, #0x20
    159a:      	mov	r5, r2
    159c:      	ldr	r6, [r7, #0x8]
    159e:      	subs	r2, r0, r2
    15a0:      	sbcs.w	r2, r1, r3
    15a4:      	bhs	0x15bc <compiler_rt.int.__udivmoddi4+0x2c> @ imm = #0x14
    15a6:      	cmp	r6, #0x0
    15a8:      	it	ne
    15aa:      	strdne	r0, r1, [r6]
    15ae:      	movs	r0, #0x0
    15b0:      	movs	r1, #0x0
    15b2:      	add	sp, #0x20
    15b4:      	pop.w	{r8, r9, r10, r11}
    15b8:      	pop	{r4, r5, r6, r7, pc}
    15ba:      	nop
    15bc:      	cmp	r3, #0x0
    15be:      	beq.w	0x16c8 <compiler_rt.int.__udivmoddi4+0x138> @ imm = #0x106
    15c2:      	clz	r2, r3
    15c6:      	cmp	r2, #0x0
    15c8:      	beq.w	0x16f4 <compiler_rt.int.__udivmoddi4+0x164> @ imm = #0x128
    15cc:      	rsbs	r6, r2, #0
    15ce:      	and	r4, r6, #0x1f
    15d2:      	lsl.w	r12, r3, r2
    15d6:      	lsr.w	r6, r5, r4
    15da:      	orr.w	r8, r6, r12
    15de:      	lsl.w	r2, r1, r2
    15e2:      	lsr.w	r6, r0, r4
    15e6:      	clz	lr, r8
    15ea:      	orrs	r2, r6
    15ec:      	ands	r12, lr, #0x1f
    15f0:      	lsr.w	r6, r1, r4
    15f4:      	str	r5, [sp, #0x10]
    15f6:      	str	r0, [sp, #0x4]
    15f8:      	beq	0x1614 <compiler_rt.int.__udivmoddi4+0x84> @ imm = #0x18
    15fa:      	lsl.w	r4, r6, r12
    15fe:      	rsb.w	r6, lr, #0x0
    1602:      	and	r6, r6, #0x1f
    1606:      	lsr.w	r6, r2, r6
    160a:      	lsl.w	r8, r8, r12
    160e:      	orrs	r6, r4
    1610:      	lsl.w	r2, r2, r12
    1614:      	lsr.w	lr, r8, #0x10
    1618:      	udiv	r4, r6, lr
    161c:      	strd	r3, r1, [sp, #8]
    1620:      	mls	r9, r4, lr, r6
    1624:      	uxth.w	r12, r8
    1628:      	lsr.w	r11, r2, #0x10
    162c:      	uxth	r3, r2
    162e:      	mov	r0, r6
    1630:      	mov.w	r10, #0x0
    1634:      	str.w	r8, [sp]
    1638:      	b	0x164c <compiler_rt.int.__udivmoddi4+0xbc> @ imm = #0x10
    163a:      	nop
    163c:      	subs	r6, r4, #0x4
    163e:      	add.w	r9, r2, lr
    1642:      	cmp.w	r10, r9, lsr #16
    1646:      	mov	r4, r6
    1648:      	bne.w	0x1886 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x23a
    164c:      	cmp.w	r10, r4, lsr #16
    1650:      	bne	0x1660 <compiler_rt.int.__udivmoddi4+0xd0> @ imm = #0xc
    1652:      	mul	r2, r4, r12
    1656:      	orr.w	r6, r11, r9, lsl #16
    165a:      	cmp	r2, r6
    165c:      	bls.w	0x1884 <compiler_rt.int.__udivmoddi4+0x2f4> @ imm = #0x224
    1660:      	add.w	r2, r9, lr
    1664:      	cmp.w	r10, r2, lsr #16
    1668:      	sub.w	r6, r4, #0x1
    166c:      	bne.w	0x1886 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x216
    1670:      	cmp.w	r10, r6, lsr #16
    1674:      	bne	0x1684 <compiler_rt.int.__udivmoddi4+0xf4> @ imm = #0xc
    1676:      	mul	r9, r6, r12
    167a:      	orr.w	r8, r11, r2, lsl #16
    167e:      	cmp	r9, r8
    1680:      	bls.w	0x1886 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x202
    1684:      	add	r2, lr
    1686:      	cmp.w	r10, r2, lsr #16
    168a:      	sub.w	r6, r4, #0x2
    168e:      	bne.w	0x1886 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1f4
    1692:      	cmp.w	r10, r6, lsr #16
    1696:      	bne	0x16a6 <compiler_rt.int.__udivmoddi4+0x116> @ imm = #0xc
    1698:      	mul	r8, r6, r12
    169c:      	orr.w	r5, r11, r2, lsl #16
    16a0:      	cmp	r8, r5
    16a2:      	bls.w	0x1886 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1e0
    16a6:      	add	r2, lr
    16a8:      	cmp.w	r10, r2, lsr #16
    16ac:      	sub.w	r6, r4, #0x3
    16b0:      	bne.w	0x1886 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1d2
    16b4:      	cmp.w	r10, r6, lsr #16
    16b8:      	bne	0x163c <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x80
    16ba:      	mul	r5, r6, r12
    16be:      	orr.w	r1, r11, r2, lsl #16
    16c2:      	cmp	r5, r1
    16c4:      	bhi	0x163c <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x8c
    16c6:      	b	0x1886 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1bc
    16c8:      	cmp	r1, r5
    16ca:      	clz	lr, r5
    16ce:      	bhs	0x170c <compiler_rt.int.__udivmoddi4+0x17c> @ imm = #0x3a
    16d0:      	cmp.w	lr, #0x0
    16d4:      	beq.w	0x17dc <compiler_rt.int.__udivmoddi4+0x24c> @ imm = #0x104
    16d8:      	rsb.w	r2, lr, #0x0
    16dc:      	and	r2, r2, #0x1f
    16e0:      	lsl.w	r1, r1, lr
    16e4:      	lsr.w	r2, r0, r2
    16e8:      	lsl.w	r5, r5, lr
    16ec:      	orrs	r2, r1
    16ee:      	lsl.w	r0, r0, lr
    16f2:      	b	0x17de <compiler_rt.int.__udivmoddi4+0x24e> @ imm = #0xe8
    16f4:      	cbz	r6, 0x16fe <compiler_rt.int.__udivmoddi4+0x16e> @ imm = #0x6
    16f6:      	subs	r0, r0, r5
    16f8:      	sbcs	r1, r3
    16fa:      	strd	r0, r1, [r6]
    16fe:      	movs	r1, #0x0
    1700:      	movs	r0, #0x1
    1702:      	add	sp, #0x20
    1704:      	pop.w	{r8, r9, r10, r11}
    1708:      	pop	{r4, r5, r6, r7, pc}
    170a:      	nop
    170c:      	udiv	r2, r1, r5
    1710:      	cmp.w	lr, #0x0
    1714:      	mls	r8, r2, r5, r1
    1718:      	mov	r1, r2
    171a:      	beq	0x1738 <compiler_rt.int.__udivmoddi4+0x1a8> @ imm = #0x1a
    171c:      	rsb.w	r3, lr, #0x0
    1720:      	and	r3, r3, #0x1f
    1724:      	lsl.w	r2, r8, lr
    1728:      	lsr.w	r3, r0, r3
    172c:      	lsl.w	r5, r5, lr
    1730:      	orr.w	r8, r2, r3
    1734:      	lsl.w	r0, r0, lr
    1738:      	lsrs	r4, r5, #0x10
    173a:      	str	r5, [sp, #0x10]
    173c:      	uxth.w	r12, r5
    1740:      	udiv	r5, r8, r4
    1744:      	lsr.w	r10, r0, #0x10
    1748:      	mls	r6, r5, r4, r8
    174c:      	uxth.w	r9, r0
    1750:      	movs	r3, #0x0
    1752:      	b	0x1762 <compiler_rt.int.__udivmoddi4+0x1d2> @ imm = #0xc
    1754:      	subs	r0, r5, #0x4
    1756:      	adds	r6, r2, r4
    1758:      	cmp.w	r3, r6, lsr #16
    175c:      	mov	r5, r0
    175e:      	bne.w	0x199e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x23c
    1762:      	cmp.w	r3, r5, lsr #16
    1766:      	bne	0x1776 <compiler_rt.int.__udivmoddi4+0x1e6> @ imm = #0xc
    1768:      	mul	r0, r5, r12
    176c:      	orr.w	r2, r10, r6, lsl #16
    1770:      	cmp	r0, r2
    1772:      	bls.w	0x199c <compiler_rt.int.__udivmoddi4+0x40c> @ imm = #0x226
    1776:      	adds	r2, r6, r4
    1778:      	cmp.w	r3, r2, lsr #16
    177c:      	sub.w	r0, r5, #0x1
    1780:      	bne.w	0x199e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x21a
    1784:      	cmp.w	r3, r0, lsr #16
    1788:      	bne	0x1798 <compiler_rt.int.__udivmoddi4+0x208> @ imm = #0xc
    178a:      	mul	r11, r0, r12
    178e:      	orr.w	r6, r10, r2, lsl #16
    1792:      	cmp	r11, r6
    1794:      	bls.w	0x199e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x206
    1798:      	add	r2, r4
    179a:      	cmp.w	r3, r2, lsr #16
    179e:      	sub.w	r0, r5, #0x2
    17a2:      	bne.w	0x199e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1f8
    17a6:      	cmp.w	r3, r0, lsr #16
    17aa:      	bne	0x17ba <compiler_rt.int.__udivmoddi4+0x22a> @ imm = #0xc
    17ac:      	mul	r11, r0, r12
    17b0:      	orr.w	r6, r10, r2, lsl #16
    17b4:      	cmp	r11, r6
    17b6:      	bls.w	0x199e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1e4
    17ba:      	add	r2, r4
    17bc:      	cmp.w	r3, r2, lsr #16
    17c0:      	sub.w	r0, r5, #0x3
    17c4:      	bne.w	0x199e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1d6
    17c8:      	cmp.w	r3, r0, lsr #16
    17cc:      	bne	0x1754 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x7c
    17ce:      	mul	r11, r0, r12
    17d2:      	orr.w	r6, r10, r2, lsl #16
    17d6:      	cmp	r11, r6
    17d8:      	bhi	0x1754 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x88
    17da:      	b	0x199e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1c0
    17dc:      	mov	r2, r1
    17de:      	lsrs	r4, r5, #0x10
    17e0:      	udiv	r6, r2, r4
    17e4:      	mov	r11, r5
    17e6:      	uxth.w	r9, r5
    17ea:      	mls	r5, r6, r4, r2
    17ee:      	lsr.w	r8, r0, #0x10
    17f2:      	uxth.w	r12, r0
    17f6:      	mov	r1, r2
    17f8:      	movs	r3, #0x0
    17fa:      	b	0x180a <compiler_rt.int.__udivmoddi4+0x27a> @ imm = #0xc
    17fc:      	subs	r0, r6, #0x4
    17fe:      	adds	r5, r2, r4
    1800:      	cmp.w	r3, r5, lsr #16
    1804:      	mov	r6, r0
    1806:      	bne.w	0x1a36 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x22c
    180a:      	cmp.w	r3, r6, lsr #16
    180e:      	bne	0x181e <compiler_rt.int.__udivmoddi4+0x28e> @ imm = #0xc
    1810:      	mul	r0, r6, r9
    1814:      	orr.w	r2, r8, r5, lsl #16
    1818:      	cmp	r0, r2
    181a:      	bls.w	0x1a34 <compiler_rt.int.__udivmoddi4+0x4a4> @ imm = #0x216
    181e:      	adds	r2, r5, r4
    1820:      	cmp.w	r3, r2, lsr #16
    1824:      	sub.w	r0, r6, #0x1
    1828:      	bne.w	0x1a36 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x20a
    182c:      	cmp.w	r3, r0, lsr #16
    1830:      	bne	0x1840 <compiler_rt.int.__udivmoddi4+0x2b0> @ imm = #0xc
    1832:      	mul	r10, r0, r9
    1836:      	orr.w	r5, r8, r2, lsl #16
    183a:      	cmp	r10, r5
    183c:      	bls.w	0x1a36 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1f6
    1840:      	add	r2, r4
    1842:      	cmp.w	r3, r2, lsr #16
    1846:      	sub.w	r0, r6, #0x2
    184a:      	bne.w	0x1a36 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1e8
    184e:      	cmp.w	r3, r0, lsr #16
    1852:      	bne	0x1862 <compiler_rt.int.__udivmoddi4+0x2d2> @ imm = #0xc
    1854:      	mul	r10, r0, r9
    1858:      	orr.w	r5, r8, r2, lsl #16
    185c:      	cmp	r10, r5
    185e:      	bls.w	0x1a36 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1d4
    1862:      	add	r2, r4
    1864:      	cmp.w	r3, r2, lsr #16
    1868:      	sub.w	r0, r6, #0x3
    186c:      	bne.w	0x1a36 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1c6
    1870:      	cmp.w	r3, r0, lsr #16
    1874:      	bne	0x17fc <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x7c
    1876:      	mul	r10, r0, r9
    187a:      	orr.w	r5, r8, r2, lsl #16
    187e:      	cmp	r10, r5
    1880:      	bhi	0x17fc <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x88
    1882:      	b	0x1a36 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1b0
    1884:      	mov	r6, r4
    1886:      	orr.w	r2, r11, r0, lsl #16
    188a:      	ldr	r0, [sp]
    188c:      	ldr.w	r9, [sp, #0x4]
    1890:      	mls	r2, r6, r0, r2
    1894:      	mov.w	r8, #0x0
    1898:      	udiv	r4, r2, lr
    189c:      	mls	r2, r4, lr, r2
    18a0:      	b	0x18b0 <compiler_rt.int.__udivmoddi4+0x320> @ imm = #0xc
    18a2:      	nop
    18a4:      	subs	r4, #0x4
    18a6:      	add	r2, lr
    18a8:      	cmp.w	r2, #0x10000
    18ac:      	mov	r5, r4
    18ae:      	bhs	0x1922 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x70
    18b0:      	cmp.w	r8, r4, lsr #16
    18b4:      	bne	0x18c2 <compiler_rt.int.__udivmoddi4+0x332> @ imm = #0xa
    18b6:      	mul	r1, r4, r12
    18ba:      	orr.w	r5, r3, r2, lsl #16
    18be:      	cmp	r1, r5
    18c0:      	bls	0x1920 <compiler_rt.int.__udivmoddi4+0x390> @ imm = #0x5c
    18c2:      	add	r2, lr
    18c4:      	cmp.w	r8, r2, lsr #16
    18c8:      	sub.w	r5, r4, #0x1
    18cc:      	bne	0x1922 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x52
    18ce:      	cmp.w	r8, r5, lsr #16
    18d2:      	bne	0x18e0 <compiler_rt.int.__udivmoddi4+0x350> @ imm = #0xa
    18d4:      	mul	r1, r5, r12
    18d8:      	orr.w	r0, r3, r2, lsl #16
    18dc:      	cmp	r1, r0
    18de:      	bls	0x1922 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x40
    18e0:      	add	r2, lr
    18e2:      	cmp.w	r8, r2, lsr #16
    18e6:      	sub.w	r5, r4, #0x2
    18ea:      	bne	0x1922 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x34
    18ec:      	cmp.w	r8, r5, lsr #16
    18f0:      	bne	0x18fe <compiler_rt.int.__udivmoddi4+0x36e> @ imm = #0xa
    18f2:      	mul	r0, r5, r12
    18f6:      	orr.w	r1, r3, r2, lsl #16
    18fa:      	cmp	r0, r1
    18fc:      	bls	0x1922 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x22
    18fe:      	add	r2, lr
    1900:      	cmp.w	r8, r2, lsr #16
    1904:      	sub.w	r5, r4, #0x3
    1908:      	bne	0x1922 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x16
    190a:      	cmp.w	r8, r5, lsr #16
    190e:      	bne	0x18a4 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x6e
    1910:      	mul	r0, r5, r12
    1914:      	orr.w	r1, r3, r2, lsl #16
    1918:      	cmp	r0, r1
    191a:      	bhi	0x18a4 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x7a
    191c:      	b	0x1922 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x2
    191e:      	nop
    1920:      	mov	r5, r4
    1922:      	add.w	r0, r5, r6, lsl #16
    1926:      	ldr	r2, [sp, #0x10]
    1928:      	ldr	r6, [sp, #0x8]
    192a:      	umull	r4, r1, r2, r0
    192e:      	mov	r8, r0
    1930:      	umull	r0, r3, r6, r0
    1934:      	adds	r5, r0, r1
    1936:      	mov.w	r12, #0x0
    193a:      	adc	r0, r12, #0x0
    193e:      	orrs.w	r1, r3, r0
    1942:      	ldr	r3, [r7, #0x8]
    1944:      	ldr.w	lr, [sp, #0xc]
    1948:      	strb.w	r0, [sp, #0x14]
    194c:      	bne	0x1958 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x8
    194e:      	cmp	r5, lr
    1950:      	bhi	0x1958 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x4
    1952:      	bne	0x196e <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x18
    1954:      	cmp	r4, r9
    1956:      	bls	0x196e <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x14
    1958:      	subs	r4, r4, r2
    195a:      	adc	r0, r12, #0x0
    195e:      	eor	r0, r0, #0x1
    1962:      	strb.w	r0, [sp, #0x18]
    1966:      	add	r0, r6
    1968:      	sub.w	r8, r8, #0x1
    196c:      	subs	r5, r5, r0
    196e:      	cbz	r3, 0x198e <compiler_rt.int.__udivmoddi4+0x3fe> @ imm = #0x1c
    1970:      	subs.w	r0, r9, r4
    1974:      	mov.w	r1, #0x0
    1978:      	adc	r1, r1, #0x0
    197c:      	eor	r1, r1, #0x1
    1980:      	strb.w	r1, [sp, #0x1c]
    1984:      	add	r1, r5
    1986:      	sub.w	r1, lr, r1
    198a:      	strd	r0, r1, [r3]
    198e:      	movs	r1, #0x0
    1990:      	mov	r0, r8
    1992:      	add	sp, #0x20
    1994:      	pop.w	{r8, r9, r10, r11}
    1998:      	pop	{r4, r5, r6, r7, pc}
    199a:      	nop
    199c:      	mov	r0, r5
    199e:      	ldr	r3, [sp, #0x10]
    19a0:      	orr.w	r2, r10, r8, lsl #16
    19a4:      	mls	r8, r0, r3, r2
    19a8:      	mov.w	r10, #0x0
    19ac:      	udiv	r3, r8, r4
    19b0:      	mls	r5, r3, r4, r8
    19b4:      	b	0x19c6 <compiler_rt.int.__udivmoddi4+0x436> @ imm = #0xe
    19b6:      	nop
    19b8:      	subs	r3, #0x4
    19ba:      	adds	r5, r2, r4
    19bc:      	cmp.w	r5, #0x10000
    19c0:      	mov	r6, r3
    19c2:      	bhs.w	0x1aca <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x104
    19c6:      	cmp.w	r10, r3, lsr #16
    19ca:      	bne	0x19d8 <compiler_rt.int.__udivmoddi4+0x448> @ imm = #0xa
    19cc:      	mul	r2, r3, r12
    19d0:      	orr.w	r6, r9, r5, lsl #16
    19d4:      	cmp	r2, r6
    19d6:      	bls	0x1ac8 <compiler_rt.int.__udivmoddi4+0x538> @ imm = #0xee
    19d8:      	adds	r2, r5, r4
    19da:      	cmp.w	r10, r2, lsr #16
    19de:      	sub.w	r6, r3, #0x1
    19e2:      	bne	0x1aca <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xe4
    19e4:      	cmp.w	r10, r6, lsr #16
    19e8:      	bne	0x19f6 <compiler_rt.int.__udivmoddi4+0x466> @ imm = #0xa
    19ea:      	mul	r11, r6, r12
    19ee:      	orr.w	r5, r9, r2, lsl #16
    19f2:      	cmp	r11, r5
    19f4:      	bls	0x1aca <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xd2
    19f6:      	add	r2, r4
    19f8:      	cmp.w	r10, r2, lsr #16
    19fc:      	sub.w	r6, r3, #0x2
    1a00:      	bne	0x1aca <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xc6
    1a02:      	cmp.w	r10, r6, lsr #16
    1a06:      	bne	0x1a14 <compiler_rt.int.__udivmoddi4+0x484> @ imm = #0xa
    1a08:      	mul	r11, r6, r12
    1a0c:      	orr.w	r5, r9, r2, lsl #16
    1a10:      	cmp	r11, r5
    1a12:      	bls	0x1aca <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xb4
    1a14:      	add	r2, r4
    1a16:      	cmp.w	r10, r2, lsr #16
    1a1a:      	sub.w	r6, r3, #0x3
    1a1e:      	bne	0x1aca <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xa8
    1a20:      	cmp.w	r10, r6, lsr #16
    1a24:      	bne	0x19b8 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x70
    1a26:      	mul	r11, r6, r12
    1a2a:      	orr.w	r5, r9, r2, lsl #16
    1a2e:      	cmp	r11, r5
    1a30:      	bhi	0x19b8 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x7c
    1a32:      	b	0x1aca <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x94
    1a34:      	mov	r0, r6
    1a36:      	orr.w	r1, r8, r1, lsl #16
    1a3a:      	mls	r8, r0, r11, r1
    1a3e:      	mov.w	r10, #0x0
    1a42:      	udiv	r1, r8, r4
    1a46:      	mls	r5, r1, r4, r8
    1a4a:      	b	0x1a58 <compiler_rt.int.__udivmoddi4+0x4c8> @ imm = #0xa
    1a4c:      	subs	r1, #0x4
    1a4e:      	adds	r5, r2, r4
    1a50:      	cmp.w	r5, #0x10000
    1a54:      	mov	r6, r1
    1a56:      	bhs	0x1ade <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x84
    1a58:      	cmp.w	r10, r1, lsr #16
    1a5c:      	bne	0x1a6a <compiler_rt.int.__udivmoddi4+0x4da> @ imm = #0xa
    1a5e:      	mul	r2, r1, r9
    1a62:      	orr.w	r6, r12, r5, lsl #16
    1a66:      	cmp	r2, r6
    1a68:      	bls	0x1adc <compiler_rt.int.__udivmoddi4+0x54c> @ imm = #0x70
    1a6a:      	adds	r2, r5, r4
    1a6c:      	cmp.w	r10, r2, lsr #16
    1a70:      	sub.w	r6, r1, #0x1
    1a74:      	bne	0x1ade <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x66
    1a76:      	cmp.w	r10, r6, lsr #16
    1a7a:      	bne	0x1a88 <compiler_rt.int.__udivmoddi4+0x4f8> @ imm = #0xa
    1a7c:      	mul	r5, r6, r9
    1a80:      	orr.w	r3, r12, r2, lsl #16
    1a84:      	cmp	r5, r3
    1a86:      	bls	0x1ade <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x54
    1a88:      	add	r2, r4
    1a8a:      	cmp.w	r10, r2, lsr #16
    1a8e:      	sub.w	r6, r1, #0x2
    1a92:      	bne	0x1ade <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x48
    1a94:      	cmp.w	r10, r6, lsr #16
    1a98:      	bne	0x1aa6 <compiler_rt.int.__udivmoddi4+0x516> @ imm = #0xa
    1a9a:      	mul	r3, r6, r9
    1a9e:      	orr.w	r5, r12, r2, lsl #16
    1aa2:      	cmp	r3, r5
    1aa4:      	bls	0x1ade <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x36
    1aa6:      	add	r2, r4
    1aa8:      	cmp.w	r10, r2, lsr #16
    1aac:      	sub.w	r6, r1, #0x3
    1ab0:      	bne	0x1ade <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x2a
    1ab2:      	cmp.w	r10, r6, lsr #16
    1ab6:      	bne	0x1a4c <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x6e
    1ab8:      	mul	r3, r6, r9
    1abc:      	orr.w	r5, r12, r2, lsl #16
    1ac0:      	cmp	r3, r5
    1ac2:      	bhi	0x1a4c <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x7a
    1ac4:      	b	0x1ade <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x16
    1ac6:      	nop
    1ac8:      	mov	r6, r3
    1aca:      	ldr	r3, [sp, #0x10]
    1acc:      	orr.w	r2, r9, r8, lsl #16
    1ad0:      	mls	r2, r6, r3, r2
    1ad4:      	lsr.w	r2, r2, lr
    1ad8:      	b	0x1aec <compiler_rt.int.__udivmoddi4+0x55c> @ imm = #0x10
    1ada:      	nop
    1adc:      	mov	r6, r1
    1ade:      	orr.w	r1, r12, r8, lsl #16
    1ae2:      	mls	r1, r6, r11, r1
    1ae6:      	lsr.w	r2, r1, lr
    1aea:      	movs	r1, #0x0
    1aec:      	ldr	r5, [r7, #0x8]
    1aee:      	add.w	r0, r6, r0, lsl #16
    1af2:      	cmp	r5, #0x0
    1af4:      	itt	ne
    1af6:      	movne	r3, #0x0
    1af8:      	strdne	r2, r3, [r5]
    1afc:      	add	sp, #0x20
    1afe:      	pop.w	{r8, r9, r10, r11}
    1b02:      	pop	{r4, r5, r6, r7, pc}
    1b04:      	bmi	0x1ab0 <compiler_rt.int.__udivmoddi4+0x520> @ imm = #-0x58
    1b06:      	bmi	0x1ab2 <compiler_rt.int.__udivmoddi4+0x522> @ imm = #-0x58
    1b08:      	bmi	0x1ab4 <compiler_rt.int.__udivmoddi4+0x524> @ imm = #-0x58
    1b0a:      	bmi	0x1ab6 <compiler_rt.int.__udivmoddi4+0x526> @ imm = #-0x58
    1b0c:      	bmi	0x1ab8 <compiler_rt.int.__udivmoddi4+0x528> @ imm = #-0x58
    1b0e:      	bmi	0x1aba <compiler_rt.int.__udivmoddi4+0x52a> @ imm = #-0x58

00001b10 <.L.str.1>:
    1b10: 00 00 00 00 00 00 00 00         ........
    1b18: 10 00 00 00 00 00 00 00         ........
    1b20: 69 6e 74 65 67 65 72 20         integer 
    1b28: 6f 76 65 72 66 6c 6f 77         overflow
    1b30: 00 00 00 00 00 00 00 00         ........
    1b38: d4 d4 d4 d4 d4 d4 d4 d4         ........

00001b40 <.L.str.3>:
    1b40: 00 00 00 00 00 00 00 00         ........
    1b48: 13 00 00 00 00 00 00 00         ........
    1b50: 69 6e 64 65 78 20 6f 75         index ou
    1b58: 74 20 6f 66 20 62 6f 75         t of bou
    1b60: 6e 64 73 00 00 00 00 00         nds.....
    1b68: d4 d4 d4 d4 d4 d4 d4 d4         ........

00001b70 <.L.str.4>:
    1b70: 00 00 00 00 00 00 00 00         ........
    1b78: 00 00 00 00 00 00 00 00         ........
    1b80: 00 00 00 00 00 00 00 00         ........
    1b88: d4 d4 d4 d4 d4 d4 d4 d4         ........
    1b90: 00 00 00 00 00 00 00 00         ........
    1b98: 0d 00 00 00 00 00 00 00         ........
    1ba0: 63 72 63 33 32 20 72 65         crc32 re
    1ba8: 73 75 6c 74 3d 00 00 00         sult=...

00001bb0 <.L.str.6>:
    1bb0: 00 00 00 00 00 00 00 00         ........
    1bb8: 07 00 00 00 00 00 00 00         ........
    1bc0: 20 74 69 63 6b 73 3d 00          ticks=.
    1bc8: 6f 75 74 20 6f 66 20 6d         out of m
    1bd0: 65 6d 6f 72 79 00 68 61         emory.ha
    1bd8: 72 64 20 66 61 75 6c 74         rd fault
    1be0: 00 20 61 6c 6c 6f 63 61         . alloca
    1be8: 74 69 6f 6e 73 3d 00 20         tions=. 
    1bf0: 73 74 61 63 6b 3d 00 23         stack=.#
    1bf8: 7a 73 20 68 65 61 70 5f         zs heap_
    1c00: 70 65 61 6b 3d 00 20 6c         peak=. l
    1c08: 69 76 65 3d 00 20 68 65         ive=. he
    1c10: 61 70 5f 72 65 73 65 72         ap_reser
    1c18: 76 65 64 3d 00 70 61 6e         ved=.pan
    1c20: 69 63 3a 20 00 0a 00 d4         ic: ....
