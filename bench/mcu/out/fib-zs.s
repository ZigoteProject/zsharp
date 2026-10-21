
/tmp/fib.elf:	file format elf32-littlearm

Disassembly of section .text:

00000000 <vectors>:
       0: 00 00 40 20 25 0d 00 00         ..@ %...
       8: 6d 0e 00 00 6d 0e 00 00         m...m...
      10: 6d 0e 00 00 6d 0e 00 00         m...m...
      18: 6d 0e 00 00 00 00 00 00         m.......
      20: 00 00 00 00 00 00 00 00         ........
      28: 00 00 00 00 6d 0e 00 00         ....m...
      30: 6d 0e 00 00 00 00 00 00         m.......
      38: 6d 0e 00 00 7d 0e 00 00         m...}...

00000040 <zs.fib>:
      40:      	push	{r4, r5, r7, lr}
      42:      	cmp	r0, #0x2
      44:      	it	lt
      46:      	poplt	{r4, r5, r7, pc}
      48:      	subs	r1, r0, #0x1
      4a:      	mov	r5, r0
      4c:      	mov	r0, r1
      4e:      	bl	0x40 <zs.fib>           @ imm = #-0x12
      52:      	mov	r4, r0
      54:      	subs	r0, r5, #0x2
      56:      	bl	0x40 <zs.fib>           @ imm = #-0x1a
      5a:      	adds	r0, r0, r4
      5c:      	bvs	0x60 <zs.fib+0x20>      @ imm = #0x0
      5e:      	pop	{r4, r5, r7, pc}
      60:      	movw	r0, #0x18f0
      64:      	movt	r0, #0x0
      68:      	adds	r0, #0x10
      6a:      	bl	0x1e8 <zs_panic_c>      @ imm = #0x17a
      6e:      	bmi	0x1a <vectors+0x1a>     @ imm = #-0x58

00000070 <main>:
      70:      	push.w	{r4, r5, r6, r7, r8, r9, lr}
      74:      	sub	sp, #0x4
      76:      	bl	0xd1c <zs_set_args>     @ imm = #0xca2
      7a:      	bl	0xe14 <zs_ticks>        @ imm = #0xd96
      7e:      	mov	r9, r0
      80:      	movs	r0, #0x18
      82:      	mov	r8, r1
      84:      	bl	0x40 <zs.fib>           @ imm = #-0x48
      88:      	mov	r4, r0
      8a:      	bl	0xe14 <zs_ticks>        @ imm = #0xd86
      8e:      	mov	r6, r0
      90:      	mov	r7, r1
      92:      	asrs	r1, r4, #0x1f
      94:      	mov	r0, r4
      96:      	bl	0x79c <zs_str_of_i64>   @ imm = #0x702
      9a:      	mov	r5, r0
      9c:      	movw	r0, #0x18b0
      a0:      	movt	r0, #0x0
      a4:      	mov	r1, r5
      a6:      	bl	0x264 <zs_str_concat>   @ imm = #0x1ba
      aa:      	ldrd	r2, r1, [r5]
      ae:      	mov	r4, r0
      b0:      	orrs.w	r3, r2, r1
      b4:      	beq	0xd0 <main+0x60>        @ imm = #0x18
      b6:      	eor	r0, r2, #0x1
      ba:      	orrs	r0, r1
      bc:      	bne	0xc6 <main+0x56>        @ imm = #0x6
      be:      	mov	r0, r5
      c0:      	bl	0x214 <zs_free>         @ imm = #0x150
      c4:      	b	0xd0 <main+0x60>        @ imm = #0x8
      c6:      	subs	r0, r2, #0x1
      c8:      	sbc	r1, r1, #0x0
      cc:      	strd	r0, r1, [r5]
      d0:      	movw	r1, #0x18d0
      d4:      	movt	r1, #0x0
      d8:      	mov	r0, r4
      da:      	bl	0x264 <zs_str_concat>   @ imm = #0x186
      de:      	ldrd	r2, r1, [r4]
      e2:      	mov	r5, r0
      e4:      	orrs.w	r3, r2, r1
      e8:      	beq	0x104 <main+0x94>       @ imm = #0x18
      ea:      	eor	r0, r2, #0x1
      ee:      	orrs	r0, r1
      f0:      	bne	0xfa <main+0x8a>        @ imm = #0x6
      f2:      	mov	r0, r4
      f4:      	bl	0x214 <zs_free>         @ imm = #0x11c
      f8:      	b	0x104 <main+0x94>       @ imm = #0x8
      fa:      	subs	r0, r2, #0x1
      fc:      	sbc	r1, r1, #0x0
     100:      	strd	r0, r1, [r4]
     104:      	subs.w	r0, r6, r9
     108:      	sbcs.w	r1, r7, r8
     10c:      	mov.w	r2, #0x0
     110:      	adc	r2, r2, #0x0
     114:      	eor	r2, r2, #0x1
     118:      	cmp	r2, #0x1
     11a:      	beq	0x1da <main+0x16a>      @ imm = #0xbc
     11c:      	bl	0x450 <zs_str_of_u64>   @ imm = #0x330
     120:      	mov	r6, r0
     122:      	mov	r0, r5
     124:      	mov	r1, r6
     126:      	bl	0x264 <zs_str_concat>   @ imm = #0x13a
     12a:      	ldrd	r2, r1, [r5]
     12e:      	mov	r4, r0
     130:      	orrs.w	r3, r2, r1
     134:      	beq	0x150 <main+0xe0>       @ imm = #0x18
     136:      	eor	r0, r2, #0x1
     13a:      	orrs	r0, r1
     13c:      	bne	0x146 <main+0xd6>       @ imm = #0x6
     13e:      	mov	r0, r5
     140:      	bl	0x214 <zs_free>         @ imm = #0xd0
     144:      	b	0x150 <main+0xe0>       @ imm = #0x8
     146:      	subs	r0, r2, #0x1
     148:      	sbc	r1, r1, #0x0
     14c:      	strd	r0, r1, [r5]
     150:      	ldrd	r1, r0, [r6]
     154:      	orrs.w	r2, r1, r0
     158:      	beq	0x174 <main+0x104>      @ imm = #0x18
     15a:      	eor	r2, r1, #0x1
     15e:      	orrs	r2, r0
     160:      	bne	0x16a <main+0xfa>       @ imm = #0x6
     162:      	mov	r0, r6
     164:      	bl	0x214 <zs_free>         @ imm = #0xac
     168:      	b	0x174 <main+0x104>      @ imm = #0x8
     16a:      	subs	r1, #0x1
     16c:      	sbc	r0, r0, #0x0
     170:      	strd	r1, r0, [r6]
     174:      	movw	r0, #0x1890
     178:      	movt	r0, #0x0
     17c:      	mov	r1, r4
     17e:      	bl	0x264 <zs_str_concat>   @ imm = #0xe2
     182:      	ldrd	r2, r1, [r4]
     186:      	mov	r5, r0
     188:      	orrs.w	r3, r2, r1
     18c:      	beq	0x1a8 <main+0x138>      @ imm = #0x18
     18e:      	eor	r0, r2, #0x1
     192:      	orrs	r0, r1
     194:      	bne	0x19e <main+0x12e>      @ imm = #0x6
     196:      	mov	r0, r4
     198:      	bl	0x214 <zs_free>         @ imm = #0x78
     19c:      	b	0x1a8 <main+0x138>      @ imm = #0x8
     19e:      	subs	r0, r2, #0x1
     1a0:      	sbc	r1, r1, #0x0
     1a4:      	strd	r0, r1, [r4]
     1a8:      	mov	r0, r5
     1aa:      	bl	0x9c4 <zs_println>      @ imm = #0x816
     1ae:      	ldrd	r1, r0, [r5]
     1b2:      	orrs.w	r2, r1, r0
     1b6:      	beq	0x1d2 <main+0x162>      @ imm = #0x18
     1b8:      	eor	r2, r1, #0x1
     1bc:      	orrs	r2, r0
     1be:      	bne	0x1c8 <main+0x158>      @ imm = #0x6
     1c0:      	mov	r0, r5
     1c2:      	bl	0x214 <zs_free>         @ imm = #0x4e
     1c6:      	b	0x1d2 <main+0x162>      @ imm = #0x8
     1c8:      	subs	r1, #0x1
     1ca:      	sbc	r0, r0, #0x0
     1ce:      	strd	r1, r0, [r5]
     1d2:      	movs	r0, #0x0
     1d4:      	add	sp, #0x4
     1d6:      	pop.w	{r4, r5, r6, r7, r8, r9, pc}
     1da:      	movw	r0, #0x18f0
     1de:      	movt	r0, #0x0
     1e2:      	adds	r0, #0x10
     1e4:      	bl	0x1e8 <zs_panic_c>      @ imm = #0x0

000001e8 <zs_panic_c>:
     1e8:      	push	{r4, r6, r7, lr}
     1ea:      	add	r7, sp, #0x8
     1ec:      	mov	r4, r0
     1ee:      	movw	r0, #0x196d
     1f2:      	movt	r0, #0x0
     1f6:      	bl	0xadc <write_c>         @ imm = #0x8e2
     1fa:      	mov	r0, r4
     1fc:      	bl	0xadc <write_c>         @ imm = #0x8dc
     200:      	movw	r0, #0x1975
     204:      	movt	r0, #0x0
     208:      	bl	0xadc <write_c>         @ imm = #0x8d0
     20c:      	movs	r0, #0x86
     20e:      	bl	0xc20 <stop>            @ imm = #0xa0e
     212:      	bmi	0x1be <main+0x14e>      @ imm = #-0x58

00000214 <zs_free>:
     214:      	push	{r4, r6, r7, lr}
     216:      	add	r7, sp, #0x8
     218:      	movw	lr, #0x88
     21c:      	movw	r12, #0x90
     220:      	movt	lr, #0x2001
     224:      	movt	r12, #0x2001
     228:      	ldr	r1, [r0, #-8]
     22c:      	ldr.w	r3, [lr]
     230:      	ldrd	r2, r4, [r12]
     234:      	subs	r3, r3, r1
     236:      	subs	r2, #0x1
     238:      	str.w	r3, [lr]
     23c:      	sbc	r3, r4, #0x0
     240:      	lsrs	r4, r1, #0x3
     242:      	cmp	r4, #0x20
     244:      	strd	r2, r3, [r12]
     248:      	it	hi
     24a:      	pophi	{r4, r6, r7, pc}
     24c:      	mvn	r2, #0x3
     250:      	and.w	r1, r2, r1, lsr #1
     254:      	movw	r2, #0x0
     258:      	movt	r2, #0x2000
     25c:      	ldr	r3, [r2, r1]
     25e:      	str	r3, [r0]
     260:      	str	r0, [r2, r1]
     262:      	pop	{r4, r6, r7, pc}

00000264 <zs_str_concat>:
     264:      	push	{r4, r5, r6, r7, lr}
     266:      	add	r7, sp, #0xc
     268:      	push.w	{r8, r9, r10}
     26c:      	mov	lr, r0
     26e:      	ldrd	r0, r3, [r0, #8]
     272:      	ldrd	r2, r6, [r1, #8]
     276:      	adds.w	r9, r2, r0
     27a:      	add.w	r0, r9, #0x18
     27e:      	lsr.w	r4, r0, #0x3
     282:      	adc.w	r12, r6, r3
     286:      	cmp	r4, #0x20
     288:      	bhi	0x2a6 <zs_str_concat+0x42> @ imm = #0x1a
     28a:      	movw	r5, #0x0
     28e:      	movt	r5, #0x2000
     292:      	ldr.w	r6, [r5, r4, lsl #2]
     296:      	cbz	r6, 0x2a6 <zs_str_concat+0x42> @ imm = #0xc
     298:      	mov	r10, r6
     29a:      	ldr	r6, [r6]
     29c:      	ldr	r0, [r10, #-8]!
     2a0:      	str.w	r6, [r5, r4, lsl #2]
     2a4:      	b	0x2e0 <zs_str_concat+0x7c> @ imm = #0x38
     2a6:      	movw	r8, #0x84
     2aa:      	movt	r8, #0x2000
     2ae:      	ldr.w	r4, [r8]
     2b2:      	bic	r0, r0, #0x7
     2b6:      	adds	r6, r0, r4
     2b8:      	movw	r3, #0xfff9
     2bc:      	subs	r3, r6, r3
     2be:      	cmn.w	r3, #0x10001
     2c2:      	blo.w	0x442 <zs_str_concat+0x1de> @ imm = #0x17c
     2c6:      	movw	r5, #0x88
     2ca:      	movt	r5, #0x2000
     2ce:      	add.w	r10, r5, r4
     2d2:      	adds	r6, #0x8
     2d4:      	str	r0, [r5, r4]
     2d6:      	movs	r4, #0x0
     2d8:      	str.w	r6, [r8]
     2dc:      	str.w	r4, [r10, #0x4]
     2e0:      	movw	r5, #0x88
     2e4:      	movt	r5, #0x2001
     2e8:      	movw	r4, #0x8c
     2ec:      	ldr	r6, [r5]
     2ee:      	movt	r4, #0x2001
     2f2:      	ldr	r2, [r4]
     2f4:      	add	r0, r6
     2f6:      	cmp	r0, r2
     2f8:      	str	r0, [r5]
     2fa:      	it	hi
     2fc:      	strhi	r0, [r4]
     2fe:      	movw	r0, #0x90
     302:      	movt	r0, #0x2001
     306:      	ldrd	r2, r4, [r0]
     30a:      	movw	r5, #0x98
     30e:      	movt	r5, #0x2001
     312:      	adds	r2, #0x1
     314:      	ldrd	r6, r3, [r5]
     318:      	adc	r4, r4, #0x0
     31c:      	strd	r2, r4, [r0]
     320:      	adds	r0, r6, #0x1
     322:      	adc	r2, r3, #0x0
     326:      	strd	r0, r2, [r5]
     32a:      	movs	r2, #0x1
     32c:      	mov	r0, r10
     32e:      	str	r2, [r0, #8]!
     332:      	movs	r5, #0x0
     334:      	adds	r2, r0, #0x4
     336:      	stm.w	r2, {r5, r9, r12}
     33a:      	add.w	r12, r0, #0x10
     33e:      	strb.w	r5, [r12, r9]
     342:      	ldr.w	r4, [lr, #0x8]
     346:      	cmp	r4, #0x0
     348:      	beq	0x3cc <zs_str_concat+0x168> @ imm = #0x80
     34a:      	ands	r2, r4, #0x3
     34e:      	beq	0x36c <zs_str_concat+0x108> @ imm = #0x1a
     350:      	ldrb.w	r3, [lr, #0x10]
     354:      	cmp	r2, #0x1
     356:      	strb.w	r3, [r10, #0x18]
     35a:      	bne	0x37a <zs_str_concat+0x116> @ imm = #0x1c
     35c:      	subs	r2, r4, #0x1
     35e:      	add.w	r5, lr, #0x11
     362:      	add.w	r6, r10, #0x19
     366:      	cmp	r4, #0x4
     368:      	bhs	0x3ac <zs_str_concat+0x148> @ imm = #0x40
     36a:      	b	0x3c8 <zs_str_concat+0x164> @ imm = #0x5a
     36c:      	add.w	r5, lr, #0x10
     370:      	mov	r6, r12
     372:      	mov	r2, r4
     374:      	cmp	r4, #0x4
     376:      	bhs	0x3ac <zs_str_concat+0x148> @ imm = #0x32
     378:      	b	0x3c8 <zs_str_concat+0x164> @ imm = #0x4c
     37a:      	ldrb.w	r3, [lr, #0x11]
     37e:      	cmp	r2, #0x2
     380:      	strb.w	r3, [r10, #0x19]
     384:      	bne	0x396 <zs_str_concat+0x132> @ imm = #0xe
     386:      	subs	r2, r4, #0x2
     388:      	add.w	r5, lr, #0x12
     38c:      	add.w	r6, r10, #0x1a
     390:      	cmp	r4, #0x4
     392:      	bhs	0x3ac <zs_str_concat+0x148> @ imm = #0x16
     394:      	b	0x3c8 <zs_str_concat+0x164> @ imm = #0x30
     396:      	ldrb.w	r3, [lr, #0x12]
     39a:      	subs	r2, r4, #0x3
     39c:      	add.w	r5, lr, #0x13
     3a0:      	add.w	r6, r10, #0x1b
     3a4:      	strb.w	r3, [r10, #0x1a]
     3a8:      	cmp	r4, #0x4
     3aa:      	blo	0x3c8 <zs_str_concat+0x164> @ imm = #0x1a
     3ac:      	subs	r3, r5, #0x4
     3ae:      	subs	r4, r6, #0x4
     3b0:      	ldrb	r5, [r3, #4]!
     3b4:      	subs	r2, #0x4
     3b6:      	strb	r5, [r4, #4]!
     3ba:      	ldrb	r5, [r3, #0x1]
     3bc:      	strb	r5, [r4, #0x1]
     3be:      	ldrb	r5, [r3, #0x2]
     3c0:      	strb	r5, [r4, #0x2]
     3c2:      	ldrb	r5, [r3, #0x3]
     3c4:      	strb	r5, [r4, #0x3]
     3c6:      	bne	0x3b0 <zs_str_concat+0x14c> @ imm = #-0x1a
     3c8:      	ldr.w	r5, [lr, #0x8]
     3cc:      	ldr	r3, [r1, #0x8]
     3ce:      	cbz	r3, 0x43c <zs_str_concat+0x1d8> @ imm = #0x6a
     3d0:      	ands	r2, r3, #0x3
     3d4:      	add.w	r6, r12, r5
     3d8:      	beq	0x3f2 <zs_str_concat+0x18e> @ imm = #0x16
     3da:      	ldrb	r5, [r1, #0x10]
     3dc:      	mov	r4, r6
     3de:      	cmp	r2, #0x1
     3e0:      	strb	r5, [r4], #1
     3e4:      	bne	0x3fc <zs_str_concat+0x198> @ imm = #0x14
     3e6:      	subs	r2, r3, #0x1
     3e8:      	adds	r1, #0x11
     3ea:      	mov	r6, r4
     3ec:      	cmp	r3, #0x4
     3ee:      	bhs	0x41e <zs_str_concat+0x1ba> @ imm = #0x2c
     3f0:      	b	0x43c <zs_str_concat+0x1d8> @ imm = #0x48
     3f2:      	adds	r1, #0x10
     3f4:      	mov	r2, r3
     3f6:      	cmp	r3, #0x4
     3f8:      	bhs	0x41e <zs_str_concat+0x1ba> @ imm = #0x22
     3fa:      	b	0x43c <zs_str_concat+0x1d8> @ imm = #0x3e
     3fc:      	ldrb	r5, [r1, #0x11]
     3fe:      	cmp	r2, #0x2
     400:      	strb	r5, [r6, #0x1]
     402:      	bne	0x410 <zs_str_concat+0x1ac> @ imm = #0xa
     404:      	subs	r2, r3, #0x2
     406:      	adds	r1, #0x12
     408:      	adds	r6, #0x2
     40a:      	cmp	r3, #0x4
     40c:      	bhs	0x41e <zs_str_concat+0x1ba> @ imm = #0xe
     40e:      	b	0x43c <zs_str_concat+0x1d8> @ imm = #0x2a
     410:      	ldrb	r5, [r1, #0x12]
     412:      	subs	r2, r3, #0x3
     414:      	adds	r1, #0x13
     416:      	strb	r5, [r6, #0x2]
     418:      	adds	r6, #0x3
     41a:      	cmp	r3, #0x4
     41c:      	blo	0x43c <zs_str_concat+0x1d8> @ imm = #0x1c
     41e:      	subs	r1, #0x4
     420:      	subs	r3, r6, #0x4
     422:      	nop
     424:      	ldrb	r6, [r1, #4]!
     428:      	subs	r2, #0x4
     42a:      	strb	r6, [r3, #4]!
     42e:      	ldrb	r6, [r1, #0x1]
     430:      	strb	r6, [r3, #0x1]
     432:      	ldrb	r6, [r1, #0x2]
     434:      	strb	r6, [r3, #0x2]
     436:      	ldrb	r6, [r1, #0x3]
     438:      	strb	r6, [r3, #0x3]
     43a:      	bne	0x424 <zs_str_concat+0x1c0> @ imm = #-0x1a
     43c:      	pop.w	{r8, r9, r10}
     440:      	pop	{r4, r5, r6, r7, pc}
     442:      	movw	r0, #0x1918
     446:      	movt	r0, #0x0
     44a:      	bl	0x1e8 <zs_panic_c>      @ imm = #-0x266
     44e:      	bmi	0x3fa <zs_str_concat+0x196> @ imm = #-0x58

00000450 <zs_str_of_u64>:
     450:      	push	{r4, r5, r6, r7, lr}
     452:      	add	r7, sp, #0xc
     454:      	push.w	{r8, r9, r10, r11}
     458:      	sub	sp, #0x34
     45a:      	movw	r9, #0xcccd
     45e:      	mov	r5, r1
     460:      	mov	r6, r0
     462:      	mov.w	r10, #0x1
     466:      	movt	r9, #0xcccc
     46a:      	add.w	r8, sp, #0x1c
     46e:      	nop
     470:      	lsrs	r0, r6, #0x1
     472:      	orr.w	r0, r0, r5, lsl #31
     476:      	adds.w	r1, r0, r5, lsr #1
     47a:      	adc	r1, r1, #0x0
     47e:      	umull	r2, r3, r1, r9
     482:      	bic	r2, r3, #0x3
     486:      	add.w	r2, r2, r3, lsr #2
     48a:      	subs	r1, r1, r2
     48c:      	subs	r1, r0, r1
     48e:      	umull	r0, r2, r1, r9
     492:      	add.w	r4, r0, r0, lsl #2
     496:      	lsr.w	r3, r5, #0x1
     49a:      	sub.w	r4, r6, r4, lsl #1
     49e:      	sbc	r3, r3, #0x0
     4a2:      	orr	r12, r4, #0x30
     4a6:      	subs.w	r4, r6, #0xa
     4aa:      	add.w	r11, r8, r10
     4ae:      	sbcs	r4, r5, #0x0
     4b2:      	strb	r12, [r11, #-1]
     4b6:      	blo	0x5a6 <zs_str_of_u64+0x156> @ imm = #0xec
     4b8:      	mov.w	r4, #0xcccccccc
     4bc:      	mla	r1, r1, r4, r2
     4c0:      	lsrs	r2, r0, #0x1
     4c2:      	mla	r1, r3, r9, r1
     4c6:      	and	r0, r0, #0x1
     4ca:      	orr.w	r2, r2, r1, lsl #31
     4ce:      	adds.w	r1, r2, r1, lsr #1
     4d2:      	adc	r1, r1, #0x0
     4d6:      	umull	r2, r3, r1, r9
     4da:      	bic	r2, r3, #0x3
     4de:      	add.w	r2, r2, r3, lsr #2
     4e2:      	subs	r1, r1, r2
     4e4:      	orr.w	r0, r0, r1, lsl #1
     4e8:      	subs.w	r1, r6, #0x64
     4ec:      	orr	r0, r0, #0x30
     4f0:      	sbcs	r1, r5, #0x0
     4f4:      	strb.w	r0, [r8, r10]
     4f8:      	blo	0x5ae <zs_str_of_u64+0x15e> @ imm = #0xb2
     4fa:      	mov	r0, r6
     4fc:      	mov	r1, r5
     4fe:      	movs	r2, #0x64
     500:      	movs	r3, #0x0
     502:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xe02
     506:      	lsrs	r2, r0, #0x1
     508:      	orr.w	r2, r2, r1, lsl #31
     50c:      	adds.w	r1, r2, r1, lsr #1
     510:      	adc	r1, r1, #0x0
     514:      	umull	r2, r3, r1, r9
     518:      	bic	r2, r3, #0x3
     51c:      	add.w	r2, r2, r3, lsr #2
     520:      	subs	r1, r1, r2
     522:      	and	r0, r0, #0x1
     526:      	orr.w	r0, r0, r1, lsl #1
     52a:      	subs.w	r1, r6, #0x3e8
     52e:      	orr	r0, r0, #0x30
     532:      	sbcs	r1, r5, #0x0
     536:      	strb.w	r0, [r11, #0x1]
     53a:      	blo	0x5b6 <zs_str_of_u64+0x166> @ imm = #0x78
     53c:      	mov	r0, r6
     53e:      	mov	r1, r5
     540:      	mov.w	r2, #0x3e8
     544:      	movs	r3, #0x0
     546:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xdbe
     54a:      	lsrs	r2, r0, #0x1
     54c:      	orr.w	r2, r2, r1, lsl #31
     550:      	adds.w	r1, r2, r1, lsr #1
     554:      	adc	r1, r1, #0x0
     558:      	umull	r2, r3, r1, r9
     55c:      	bic	r2, r3, #0x3
     560:      	add.w	r2, r2, r3, lsr #2
     564:      	subs	r1, r1, r2
     566:      	and	r0, r0, #0x1
     56a:      	orr.w	r0, r0, r1, lsl #1
     56e:      	orr	r0, r0, #0x30
     572:      	strb.w	r0, [r11, #0x2]
     576:      	mov	r0, r6
     578:      	mov	r1, r5
     57a:      	movw	r2, #0x2710
     57e:      	movs	r3, #0x0
     580:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xd84
     584:      	movw	r2, #0x270f
     588:      	subs	r2, r2, r6
     58a:      	mov.w	r2, #0x0
     58e:      	sbcs	r2, r5
     590:      	add.w	r10, r10, #0x4
     594:      	mov	r6, r0
     596:      	mov	r5, r1
     598:      	blo.w	0x470 <zs_str_of_u64+0x20> @ imm = #-0x12c
     59c:      	sub.w	r1, r10, #0x1
     5a0:      	sub.w	r12, r10, #0x2
     5a4:      	b	0x5be <zs_str_of_u64+0x16e> @ imm = #0x16
     5a6:      	sub.w	r12, r10, #0x1
     5aa:      	mov	r1, r10
     5ac:      	b	0x5c0 <zs_str_of_u64+0x170> @ imm = #0x10
     5ae:      	add.w	r1, r10, #0x1
     5b2:      	mov	r12, r10
     5b4:      	b	0x5be <zs_str_of_u64+0x16e> @ imm = #0x6
     5b6:      	add.w	r1, r10, #0x2
     5ba:      	add.w	r12, r10, #0x1
     5be:      	mov	r10, r1
     5c0:      	and	lr, r1, #0x3
     5c4:      	lsrs	r3, r1, #0x2
     5c6:      	mov.w	r1, #0x0
     5ca:      	beq	0x5fe <zs_str_of_u64+0x1ae> @ imm = #0x30
     5cc:      	add	r6, sp, #0x4
     5ce:      	add.w	r5, r12, r8
     5d2:      	sub.w	r9, r1, r3, lsl #2
     5d6:      	subs	r6, #0x3
     5d8:      	subs	r5, #0x1
     5da:      	nop
     5dc:      	adds	r4, r5, r1
     5de:      	ldrb	r3, [r5, r1]
     5e0:      	ldrb	r0, [r4, #-2]
     5e4:      	ldrb	r2, [r4, #-1]
     5e8:      	ldrb	r4, [r4, #0x1]
     5ea:      	subs	r1, #0x4
     5ec:      	strb	r3, [r6, #4]!
     5f0:      	cmp	r9, r1
     5f2:      	strb	r4, [r6, #-1]
     5f6:      	strb	r2, [r6, #0x1]
     5f8:      	strb	r0, [r6, #0x2]
     5fa:      	bne	0x5dc <zs_str_of_u64+0x18c> @ imm = #-0x22
     5fc:      	rsbs	r1, r1, #0
     5fe:      	cmp.w	lr, #0x0
     602:      	beq	0x634 <zs_str_of_u64+0x1e4> @ imm = #0x2e
     604:      	sub.w	r0, r12, r1
     608:      	ldrb.w	r0, [r8, r0]
     60c:      	add	r3, sp, #0x4
     60e:      	cmp.w	lr, #0x1
     612:      	strb	r0, [r3, r1]
     614:      	beq	0x634 <zs_str_of_u64+0x1e4> @ imm = #0x1c
     616:      	adds	r0, r1, #0x1
     618:      	sub.w	r2, r12, r0
     61c:      	ldrb.w	r2, [r8, r2]
     620:      	cmp.w	lr, #0x2
     624:      	strb	r2, [r3, r0]
     626:      	beq	0x634 <zs_str_of_u64+0x1e4> @ imm = #0xa
     628:      	adds	r0, r1, #0x2
     62a:      	sub.w	r1, r12, r0
     62e:      	ldrb.w	r1, [r8, r1]
     632:      	strb	r1, [r3, r0]
     634:      	add	r0, sp, #0x4
     636:      	mov	r2, r10
     638:      	movs	r3, #0x0
     63a:      	bl	0x648 <str_of>          @ imm = #0xa
     63e:      	add	sp, #0x34
     640:      	pop.w	{r8, r9, r10, r11}
     644:      	pop	{r4, r5, r6, r7, pc}
     646:      	bmi	0x5f2 <zs_str_of_u64+0x1a2> @ imm = #-0x58

00000648 <str_of>:
     648:      	push	{r4, r5, r6, r7, lr}
     64a:      	add	r7, sp, #0xc
     64c:      	str	r8, [sp, #-4]!
     650:      	add.w	r12, r2, #0x18
     654:      	lsr.w	r1, r12, #0x3
     658:      	cmp	r1, #0x20
     65a:      	bhi	0x678 <str_of+0x30>     @ imm = #0x1a
     65c:      	movw	r4, #0x0
     660:      	movt	r4, #0x2000
     664:      	ldr.w	r5, [r4, r1, lsl #2]
     668:      	cbz	r5, 0x678 <str_of+0x30> @ imm = #0xc
     66a:      	mov	r12, r5
     66c:      	ldr	r5, [r5]
     66e:      	ldr	lr, [r12, #-8]!
     672:      	str.w	r5, [r4, r1, lsl #2]
     676:      	b	0x6b0 <str_of+0x68>     @ imm = #0x36
     678:      	movw	r6, #0x84
     67c:      	movt	r6, #0x2000
     680:      	ldr	r1, [r6]
     682:      	bic	lr, r12, #0x7
     686:      	add.w	r5, lr, r1
     68a:      	movw	r4, #0xfff9
     68e:      	subs	r4, r5, r4
     690:      	cmn.w	r4, #0x10001
     694:      	blo	0x790 <str_of+0x148>    @ imm = #0xf8
     696:      	movw	r4, #0x88
     69a:      	movt	r4, #0x2000
     69e:      	add.w	r12, r4, r1
     6a2:      	adds	r5, #0x8
     6a4:      	str.w	lr, [r4, r1]
     6a8:      	movs	r1, #0x0
     6aa:      	str	r5, [r6]
     6ac:      	str.w	r1, [r12, #0x4]
     6b0:      	movw	r4, #0x88
     6b4:      	movt	r4, #0x2001
     6b8:      	movw	r1, #0x8c
     6bc:      	ldr	r5, [r4]
     6be:      	movt	r1, #0x2001
     6c2:      	ldr	r6, [r1]
     6c4:      	add	r5, lr
     6c6:      	movw	lr, #0x90
     6ca:      	cmp	r5, r6
     6cc:      	str	r5, [r4]
     6ce:      	it	hi
     6d0:      	strhi	r5, [r1]
     6d2:      	movt	lr, #0x2001
     6d6:      	movw	r8, #0x98
     6da:      	ldrd	r6, r5, [lr]
     6de:      	movt	r8, #0x2001
     6e2:      	ldrd	r1, r4, [r8]
     6e6:      	adds	r6, #0x1
     6e8:      	adc	r5, r5, #0x0
     6ec:      	adds	r1, #0x1
     6ee:      	strd	r6, r5, [lr]
     6f2:      	adc	r6, r4, #0x0
     6f6:      	strd	r1, r6, [r8]
     6fa:      	movs	r6, #0x1
     6fc:      	mov	r1, r12
     6fe:      	str	r6, [r1, #8]!
     702:      	movs	r4, #0x0
     704:      	add.w	lr, r1, #0x10
     708:      	strd	r4, r2, [r1, #4]
     70c:      	str	r3, [r1, #0xc]
     70e:      	strb.w	r4, [lr, r2]
     712:      	cbz	r2, 0x788 <str_of+0x140> @ imm = #0x72
     714:      	ands	r3, r2, #0x3
     718:      	beq	0x736 <str_of+0xee>     @ imm = #0x1a
     71a:      	mov	r4, r0
     71c:      	ldrb	r6, [r4], #1
     720:      	cmp	r3, #0x1
     722:      	strb.w	r6, [r12, #0x18]
     726:      	bne	0x73e <str_of+0xf6>     @ imm = #0x14
     728:      	subs	r3, r2, #0x1
     72a:      	add.w	lr, r12, #0x19
     72e:      	mov	r0, r4
     730:      	cmp	r2, #0x4
     732:      	bhs	0x768 <str_of+0x120>    @ imm = #0x32
     734:      	b	0x788 <str_of+0x140>    @ imm = #0x50
     736:      	mov	r3, r2
     738:      	cmp	r2, #0x4
     73a:      	bhs	0x768 <str_of+0x120>    @ imm = #0x2a
     73c:      	b	0x788 <str_of+0x140>    @ imm = #0x48
     73e:      	ldrb	r6, [r0, #0x1]
     740:      	cmp	r3, #0x2
     742:      	strb.w	r6, [r12, #0x19]
     746:      	bne	0x756 <str_of+0x10e>    @ imm = #0xc
     748:      	subs	r3, r2, #0x2
     74a:      	adds	r0, #0x2
     74c:      	add.w	lr, r12, #0x1a
     750:      	cmp	r2, #0x4
     752:      	bhs	0x768 <str_of+0x120>    @ imm = #0x12
     754:      	b	0x788 <str_of+0x140>    @ imm = #0x30
     756:      	ldrb	r4, [r0, #0x2]
     758:      	subs	r3, r2, #0x3
     75a:      	adds	r0, #0x3
     75c:      	add.w	lr, r12, #0x1b
     760:      	strb.w	r4, [r12, #0x1a]
     764:      	cmp	r2, #0x4
     766:      	blo	0x788 <str_of+0x140>    @ imm = #0x1e
     768:      	subs	r0, #0x4
     76a:      	sub.w	r2, lr, #0x4
     76e:      	nop
     770:      	ldrb	r6, [r0, #4]!
     774:      	subs	r3, #0x4
     776:      	strb	r6, [r2, #4]!
     77a:      	ldrb	r6, [r0, #0x1]
     77c:      	strb	r6, [r2, #0x1]
     77e:      	ldrb	r6, [r0, #0x2]
     780:      	strb	r6, [r2, #0x2]
     782:      	ldrb	r6, [r0, #0x3]
     784:      	strb	r6, [r2, #0x3]
     786:      	bne	0x770 <str_of+0x128>    @ imm = #-0x1a
     788:      	mov	r0, r1
     78a:      	ldr	r8, [sp], #4
     78e:      	pop	{r4, r5, r6, r7, pc}
     790:      	movw	r0, #0x1918
     794:      	movt	r0, #0x0
     798:      	bl	0x1e8 <zs_panic_c>      @ imm = #-0x5b4

0000079c <zs_str_of_i64>:
     79c:      	push	{r4, r5, r6, r7, lr}
     79e:      	add	r7, sp, #0xc
     7a0:      	push.w	{r8, r9, r10, r11}
     7a4:      	sub	sp, #0x3c
     7a6:      	cmp.w	r1, #0xffffffff
     7aa:      	add	r2, sp, #0xc
     7ac:      	ble	0x7b4 <zs_str_of_i64+0x18> @ imm = #0x4
     7ae:      	str	r2, [sp, #0x8]
     7b0:      	movs	r2, #0x0
     7b2:      	b	0x7c0 <zs_str_of_i64+0x24> @ imm = #0xa
     7b4:      	adds	r2, #0x1
     7b6:      	str	r2, [sp, #0x8]
     7b8:      	movs	r2, #0x2d
     7ba:      	strb.w	r2, [sp, #0xc]
     7be:      	movs	r2, #0x1
     7c0:      	eor.w	r0, r0, r1, asr #31
     7c4:      	str	r2, [sp, #0x4]
     7c6:      	eor.w	r2, r1, r1, asr #31
     7ca:      	subs.w	r4, r0, r1, asr #31
     7ce:      	movw	r8, #0xcccd
     7d2:      	sbc.w	r5, r2, r1, asr #31
     7d6:      	mov.w	r9, #0x1
     7da:      	movt	r8, #0xcccc
     7de:      	add.w	r10, sp, #0x24
     7e2:      	nop
     7e4:      	lsrs	r0, r4, #0x1
     7e6:      	orr.w	r0, r0, r5, lsl #31
     7ea:      	adds.w	r1, r0, r5, lsr #1
     7ee:      	adc	r1, r1, #0x0
     7f2:      	umull	r2, r3, r1, r8
     7f6:      	bic	r2, r3, #0x3
     7fa:      	add.w	r2, r2, r3, lsr #2
     7fe:      	subs	r1, r1, r2
     800:      	subs	r1, r0, r1
     802:      	umull	r0, r2, r1, r8
     806:      	add.w	r6, r0, r0, lsl #2
     80a:      	lsr.w	r3, r5, #0x1
     80e:      	sub.w	r6, r4, r6, lsl #1
     812:      	sbc	r3, r3, #0x0
     816:      	orr	r12, r6, #0x30
     81a:      	subs.w	r6, r4, #0xa
     81e:      	add.w	r11, r10, r9
     822:      	sbcs	r6, r5, #0x0
     826:      	strb	r12, [r11, #-1]
     82a:      	blo	0x91a <zs_str_of_i64+0x17e> @ imm = #0xec
     82c:      	mov.w	r6, #0xcccccccc
     830:      	mla	r1, r1, r6, r2
     834:      	lsrs	r2, r0, #0x1
     836:      	mla	r1, r3, r8, r1
     83a:      	and	r0, r0, #0x1
     83e:      	orr.w	r2, r2, r1, lsl #31
     842:      	adds.w	r1, r2, r1, lsr #1
     846:      	adc	r1, r1, #0x0
     84a:      	umull	r2, r3, r1, r8
     84e:      	bic	r2, r3, #0x3
     852:      	add.w	r2, r2, r3, lsr #2
     856:      	subs	r1, r1, r2
     858:      	orr.w	r0, r0, r1, lsl #1
     85c:      	subs.w	r1, r4, #0x64
     860:      	orr	r0, r0, #0x30
     864:      	sbcs	r1, r5, #0x0
     868:      	strb.w	r0, [r10, r9]
     86c:      	blo	0x922 <zs_str_of_i64+0x186> @ imm = #0xb2
     86e:      	mov	r0, r4
     870:      	mov	r1, r5
     872:      	movs	r2, #0x64
     874:      	movs	r3, #0x0
     876:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xa8e
     87a:      	lsrs	r2, r0, #0x1
     87c:      	orr.w	r2, r2, r1, lsl #31
     880:      	adds.w	r1, r2, r1, lsr #1
     884:      	adc	r1, r1, #0x0
     888:      	umull	r2, r3, r1, r8
     88c:      	bic	r2, r3, #0x3
     890:      	add.w	r2, r2, r3, lsr #2
     894:      	subs	r1, r1, r2
     896:      	and	r0, r0, #0x1
     89a:      	orr.w	r0, r0, r1, lsl #1
     89e:      	subs.w	r1, r4, #0x3e8
     8a2:      	orr	r0, r0, #0x30
     8a6:      	sbcs	r1, r5, #0x0
     8aa:      	strb.w	r0, [r11, #0x1]
     8ae:      	blo	0x92a <zs_str_of_i64+0x18e> @ imm = #0x78
     8b0:      	mov	r0, r4
     8b2:      	mov	r1, r5
     8b4:      	mov.w	r2, #0x3e8
     8b8:      	movs	r3, #0x0
     8ba:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xa4a
     8be:      	lsrs	r2, r0, #0x1
     8c0:      	orr.w	r2, r2, r1, lsl #31
     8c4:      	adds.w	r1, r2, r1, lsr #1
     8c8:      	adc	r1, r1, #0x0
     8cc:      	umull	r2, r3, r1, r8
     8d0:      	bic	r2, r3, #0x3
     8d4:      	add.w	r2, r2, r3, lsr #2
     8d8:      	subs	r1, r1, r2
     8da:      	and	r0, r0, #0x1
     8de:      	orr.w	r0, r0, r1, lsl #1
     8e2:      	orr	r0, r0, #0x30
     8e6:      	strb.w	r0, [r11, #0x2]
     8ea:      	mov	r0, r4
     8ec:      	mov	r1, r5
     8ee:      	movw	r2, #0x2710
     8f2:      	movs	r3, #0x0
     8f4:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xa10
     8f8:      	movw	r2, #0x270f
     8fc:      	subs	r2, r2, r4
     8fe:      	mov.w	r2, #0x0
     902:      	sbcs	r2, r5
     904:      	add.w	r9, r9, #0x4
     908:      	mov	r4, r0
     90a:      	mov	r5, r1
     90c:      	blo.w	0x7e4 <zs_str_of_i64+0x48> @ imm = #-0x12c
     910:      	sub.w	r1, r9, #0x1
     914:      	sub.w	r12, r9, #0x2
     918:      	b	0x932 <zs_str_of_i64+0x196> @ imm = #0x16
     91a:      	sub.w	r12, r9, #0x1
     91e:      	mov	r1, r9
     920:      	b	0x934 <zs_str_of_i64+0x198> @ imm = #0x10
     922:      	add.w	r1, r9, #0x1
     926:      	mov	r12, r9
     928:      	b	0x932 <zs_str_of_i64+0x196> @ imm = #0x6
     92a:      	add.w	r1, r9, #0x2
     92e:      	add.w	r12, r9, #0x1
     932:      	mov	r9, r1
     934:      	ldr.w	r8, [sp, #0x8]
     938:      	and	lr, r1, #0x3
     93c:      	lsrs	r3, r1, #0x2
     93e:      	mov.w	r1, #0x0
     942:      	beq	0x974 <zs_str_of_i64+0x1d8> @ imm = #0x2e
     944:      	add.w	r6, r12, r10
     948:      	sub.w	r3, r1, r3, lsl #2
     94c:      	sub.w	r5, r8, #0x3
     950:      	subs	r4, r6, #0x1
     952:      	nop
     954:      	adds	r6, r4, r1
     956:      	ldrb	r0, [r6, #0x1]
     958:      	ldrb	r2, [r6, #-1]
     95c:      	strb	r0, [r5, #0x3]
     95e:      	ldrb	r0, [r4, r1]
     960:      	subs	r1, #0x4
     962:      	strb	r0, [r5, #4]!
     966:      	ldrb	r0, [r6, #-2]
     96a:      	cmp	r3, r1
     96c:      	strb	r2, [r5, #0x1]
     96e:      	strb	r0, [r5, #0x2]
     970:      	bne	0x954 <zs_str_of_i64+0x1b8> @ imm = #-0x20
     972:      	rsbs	r1, r1, #0
     974:      	cmp.w	lr, #0x0
     978:      	beq	0x9ae <zs_str_of_i64+0x212> @ imm = #0x32
     97a:      	sub.w	r0, r12, r1
     97e:      	ldrb.w	r0, [r10, r0]
     982:      	cmp.w	lr, #0x1
     986:      	strb.w	r0, [r8, r1]
     98a:      	beq	0x9ae <zs_str_of_i64+0x212> @ imm = #0x20
     98c:      	adds	r0, r1, #0x1
     98e:      	sub.w	r2, r12, r0
     992:      	ldrb.w	r2, [r10, r2]
     996:      	cmp.w	lr, #0x2
     99a:      	strb.w	r2, [r8, r0]
     99e:      	beq	0x9ae <zs_str_of_i64+0x212> @ imm = #0xc
     9a0:      	adds	r0, r1, #0x2
     9a2:      	sub.w	r1, r12, r0
     9a6:      	ldrb.w	r1, [r10, r1]
     9aa:      	strb.w	r1, [r8, r0]
     9ae:      	ldr	r0, [sp, #0x4]
     9b0:      	movs	r3, #0x0
     9b2:      	add.w	r2, r9, r0
     9b6:      	add	r0, sp, #0xc
     9b8:      	bl	0x648 <str_of>          @ imm = #-0x374
     9bc:      	add	sp, #0x3c
     9be:      	pop.w	{r8, r9, r10, r11}
     9c2:      	pop	{r4, r5, r6, r7, pc}

000009c4 <zs_println>:
     9c4:      	push	{r4, r5, r6, r7, lr}
     9c6:      	add	r7, sp, #0xc
     9c8:      	push.w	{r8, r9, r10, r11}
     9cc:      	sub	sp, #0x44
     9ce:      	ldrd	r11, r2, [r0, #8]
     9d2:      	subs.w	r1, r11, #0x1
     9d6:      	sbcs	r1, r2, #0x0
     9da:      	blt	0xac6 <zs_println+0x102> @ imm = #0xe8
     9dc:      	sub.w	r1, r7, #0x5d
     9e0:      	add.w	lr, r0, #0x10
     9e4:      	add.w	r9, r1, #0x1
     9e8:      	movs	r3, #0x0
     9ea:      	b	0xa08 <zs_println+0x44> @ imm = #0x1a
     9ec:      	strb.w	r3, [r1, r8]
     9f0:      	movs	r0, #0x4
     9f2:      	subs.w	r11, r11, r8
     9f6:      	bkpt	#0xab
     9f8:      	sbc	r2, r2, #0x0
     9fc:      	rsbs.w	r0, r11, #0x0
     a00:      	sbcs.w	r0, r3, r2
     a04:      	add	lr, r8
     a06:      	bge	0xac6 <zs_println+0x102> @ imm = #0xbc
     a08:      	cmp.w	r11, #0x40
     a0c:      	mov.w	r8, #0x40
     a10:      	it	lo
     a12:      	movlo	r8, r11
     a14:      	cmp	r2, #0x0
     a16:      	mov.w	r0, #0x40
     a1a:      	it	ne
     a1c:      	movne	r8, r0
     a1e:      	lsrs.w	r0, r8, #0x2
     a22:      	beq	0xa88 <zs_println+0xc4> @ imm = #0x62
     a24:      	mov	r1, r2
     a26:      	sub.w	r10, r3, r0, lsl #2
     a2a:      	add.w	r5, lr, #0x1
     a2e:      	mvn	r4, #0x3
     a32:      	nop
     a34:      	adds	r2, r5, r4
     a36:      	ldrb	r6, [r2, #0x3]
     a38:      	ldrb	r3, [r2, #0x4]
     a3a:      	ldrb	r0, [r2, #0x5]
     a3c:      	cmp	r6, #0x0
     a3e:      	ldrb	r2, [r2, #0x6]
     a40:      	it	eq
     a42:      	moveq	r6, #0x20
     a44:      	add.w	r12, r9, r4
     a48:      	cmp	r3, #0x0
     a4a:      	strb.w	r6, [r12, #0x3]
     a4e:      	it	eq
     a50:      	moveq	r3, #0x20
     a52:      	strb.w	r3, [r12, #0x4]
     a56:      	cmp	r0, #0x0
     a58:      	it	eq
     a5a:      	moveq	r0, #0x20
     a5c:      	adds	r4, #0x4
     a5e:      	strb.w	r0, [r12, #0x5]
     a62:      	cmp	r2, #0x0
     a64:      	add.w	r0, r10, r4
     a68:      	it	eq
     a6a:      	moveq	r2, #0x20
     a6c:      	adds	r0, #0x4
     a6e:      	strb.w	r2, [r12, #0x6]
     a72:      	bne	0xa34 <zs_println+0x70> @ imm = #-0x42
     a74:      	adds	r0, r4, #0x4
     a76:      	mov	r2, r1
     a78:      	sub.w	r1, r7, #0x5d
     a7c:      	movs	r3, #0x0
     a7e:      	ands	r4, r8, #0x3
     a82:      	bne	0xa90 <zs_println+0xcc> @ imm = #0xa
     a84:      	b	0x9ec <zs_println+0x28> @ imm = #-0x9c
     a86:      	nop
     a88:      	movs	r0, #0x0
     a8a:      	ands	r4, r8, #0x3
     a8e:      	beq	0x9ec <zs_println+0x28> @ imm = #-0xa6
     a90:      	ldrb.w	r5, [lr, r0]
     a94:      	cmp	r5, #0x0
     a96:      	it	eq
     a98:      	moveq	r5, #0x20
     a9a:      	cmp	r4, #0x1
     a9c:      	strb	r5, [r1, r0]
     a9e:      	beq	0x9ec <zs_println+0x28> @ imm = #-0xb6
     aa0:      	add.w	r10, r0, #0x1
     aa4:      	ldrb.w	r5, [lr, r10]
     aa8:      	cmp	r5, #0x0
     aaa:      	it	eq
     aac:      	moveq	r5, #0x20
     aae:      	cmp	r4, #0x2
     ab0:      	strb.w	r5, [r1, r10]
     ab4:      	beq	0x9ec <zs_println+0x28> @ imm = #-0xcc
     ab6:      	adds	r0, #0x2
     ab8:      	ldrb.w	r4, [lr, r0]
     abc:      	cmp	r4, #0x0
     abe:      	it	eq
     ac0:      	moveq	r4, #0x20
     ac2:      	strb	r4, [r1, r0]
     ac4:      	b	0x9ec <zs_println+0x28> @ imm = #-0xdc
     ac6:      	movs	r0, #0xa
     ac8:      	strh	r0, [r7, #-93]
     acc:      	movs	r0, #0x4
     ace:      	sub.w	r1, r7, #0x5d
     ad2:      	bkpt	#0xab
     ad4:      	add	sp, #0x44
     ad6:      	pop.w	{r8, r9, r10, r11}
     ada:      	pop	{r4, r5, r6, r7, pc}

00000adc <write_c>:
     adc:      	push	{r4, r5, r6, r7, lr}
     ade:      	add	r7, sp, #0xc
     ae0:      	push.w	{r8, r9, r10, r11}
     ae4:      	sub	sp, #0x44
     ae6:      	mov	r2, r0
     ae8:      	mov.w	r11, #0xffffffff
     aec:      	add.w	r0, r2, r11
     af0:      	ldrb	r1, [r0, #0x1]
     af2:      	cbz	r1, 0xb0c <write_c+0x30> @ imm = #0x16
     af4:      	ldrb	r1, [r0, #0x2]
     af6:      	cbz	r1, 0xb18 <write_c+0x3c> @ imm = #0x1e
     af8:      	ldrb	r1, [r0, #0x3]
     afa:      	cmp	r1, #0x0
     afc:      	beq.w	0xc0c <write_c+0x130>   @ imm = #0x10c
     b00:      	ldrb	r0, [r0, #0x4]
     b02:      	add.w	r11, r11, #0x4
     b06:      	cmp	r0, #0x0
     b08:      	bne	0xaec <write_c+0x10>    @ imm = #-0x20
     b0a:      	b	0xb1c <write_c+0x40>    @ imm = #0xe
     b0c:      	add.w	r11, r11, #0x1
     b10:      	cmp.w	r11, #0x0
     b14:      	bne	0xb22 <write_c+0x46>    @ imm = #0xa
     b16:      	b	0xc18 <write_c+0x13c>   @ imm = #0xfe
     b18:      	add.w	r11, r11, #0x2
     b1c:      	cmp.w	r11, #0x0
     b20:      	beq	0xc18 <write_c+0x13c>   @ imm = #0xf4
     b22:      	sub.w	r1, r7, #0x5d
     b26:      	movs	r3, #0x0
     b28:      	add.w	r12, r1, #0x1
     b2c:      	movs	r6, #0x40
     b2e:      	mov.w	r9, #0x0
     b32:      	b	0xb50 <write_c+0x74>    @ imm = #0x1a
     b34:      	strb.w	r3, [r1, r8]
     b38:      	movs	r0, #0x4
     b3a:      	subs.w	r11, r11, r8
     b3e:      	bkpt	#0xab
     b40:      	sbc	r9, r9, #0x0
     b44:      	rsbs.w	r0, r11, #0x0
     b48:      	sbcs.w	r0, r3, r9
     b4c:      	add	r2, r8
     b4e:      	bge	0xc18 <write_c+0x13c>   @ imm = #0xc6
     b50:      	mov.w	r8, #0x40
     b54:      	cmp.w	r11, #0x40
     b58:      	it	lo
     b5a:      	movlo	r8, r11
     b5c:      	cmp.w	r9, #0x0
     b60:      	it	ne
     b62:      	movne	r8, r6
     b64:      	sub.w	r0, r8, #0x1
     b68:      	cmp	r0, #0x3
     b6a:      	bhs	0xb78 <write_c+0x9c>    @ imm = #0xa
     b6c:      	movs	r0, #0x0
     b6e:      	ands	r4, r8, #0x3
     b72:      	bne	0xbda <write_c+0xfe>    @ imm = #0x64
     b74:      	b	0xb34 <write_c+0x58>    @ imm = #-0x44
     b76:      	nop
     b78:      	bic	r0, r8, #0x3
     b7c:      	rsb.w	r10, r0, #0x0
     b80:      	mov	r1, r2
     b82:      	adds	r5, r2, #0x1
     b84:      	mvn	r4, #0x3
     b88:      	adds	r3, r5, r4
     b8a:      	ldrb	r6, [r3, #0x3]
     b8c:      	ldrb	r2, [r3, #0x4]
     b8e:      	ldrb	r0, [r3, #0x5]
     b90:      	cmp	r6, #0x0
     b92:      	ldrb	r3, [r3, #0x6]
     b94:      	it	eq
     b96:      	moveq	r6, #0x20
     b98:      	add.w	lr, r12, r4
     b9c:      	cmp	r2, #0x0
     b9e:      	strb.w	r6, [lr, #0x3]
     ba2:      	it	eq
     ba4:      	moveq	r2, #0x20
     ba6:      	strb.w	r2, [lr, #0x4]
     baa:      	cmp	r0, #0x0
     bac:      	it	eq
     bae:      	moveq	r0, #0x20
     bb0:      	adds	r4, #0x4
     bb2:      	strb.w	r0, [lr, #0x5]
     bb6:      	cmp	r3, #0x0
     bb8:      	add.w	r0, r10, r4
     bbc:      	it	eq
     bbe:      	moveq	r3, #0x20
     bc0:      	adds	r0, #0x4
     bc2:      	strb.w	r3, [lr, #0x6]
     bc6:      	bne	0xb88 <write_c+0xac>    @ imm = #-0x42
     bc8:      	adds	r0, r4, #0x4
     bca:      	mov	r2, r1
     bcc:      	movs	r3, #0x0
     bce:      	sub.w	r1, r7, #0x5d
     bd2:      	movs	r6, #0x40
     bd4:      	ands	r4, r8, #0x3
     bd8:      	beq	0xb34 <write_c+0x58>    @ imm = #-0xa8
     bda:      	ldrb	r5, [r2, r0]
     bdc:      	cmp	r5, #0x0
     bde:      	it	eq
     be0:      	moveq	r5, #0x20
     be2:      	cmp	r4, #0x1
     be4:      	strb	r5, [r1, r0]
     be6:      	beq	0xb34 <write_c+0x58>    @ imm = #-0xb6
     be8:      	add.w	r10, r0, #0x1
     bec:      	ldrb.w	r5, [r2, r10]
     bf0:      	cmp	r5, #0x0
     bf2:      	it	eq
     bf4:      	moveq	r5, #0x20
     bf6:      	cmp	r4, #0x2
     bf8:      	strb.w	r5, [r1, r10]
     bfc:      	beq	0xb34 <write_c+0x58>    @ imm = #-0xcc
     bfe:      	adds	r0, #0x2
     c00:      	ldrb	r4, [r2, r0]
     c02:      	cmp	r4, #0x0
     c04:      	it	eq
     c06:      	moveq	r4, #0x20
     c08:      	strb	r4, [r1, r0]
     c0a:      	b	0xb34 <write_c+0x58>    @ imm = #-0xda
     c0c:      	add.w	r11, r11, #0x3
     c10:      	cmp.w	r11, #0x0
     c14:      	bne.w	0xb22 <write_c+0x46>    @ imm = #-0xf6
     c18:      	add	sp, #0x44
     c1a:      	pop.w	{r8, r9, r10, r11}
     c1e:      	pop	{r4, r5, r6, r7, pc}

00000c20 <stop>:
     c20:      	push	{r4, r5, r6, r7, lr}
     c22:      	add	r7, sp, #0xc
     c24:      	str	r11, [sp, #-4]!
     c28:      	sub	sp, #0x48
     c2a:      	movw	r6, #0x8000
     c2e:      	movw	r5, #0x0
     c32:      	movt	r6, #0x203f
     c36:      	movt	r5, #0x2040
     c3a:      	cmp	r6, r5
     c3c:      	mov	r4, r0
     c3e:      	bhs	0xc8a <stop+0x6a>       @ imm = #0x48
     c40:      	movw	r0, #0x8000
     c44:      	movt	r0, #0x203f
     c48:      	ldr	r1, [r0]
     c4a:      	cmp.w	r1, #0xcdcdcdcd
     c4e:      	bne	0xc88 <stop+0x68>       @ imm = #0x36
     c50:      	adds	r6, r0, #0x4
     c52:      	cmp	r6, r5
     c54:      	bhs	0xc8a <stop+0x6a>       @ imm = #0x32
     c56:      	ldr	r1, [r6]
     c58:      	cmp.w	r1, #0xcdcdcdcd
     c5c:      	bne	0xc8a <stop+0x6a>       @ imm = #0x2a
     c5e:      	add.w	r6, r0, #0x8
     c62:      	cmp	r6, r5
     c64:      	bhs	0xc8a <stop+0x6a>       @ imm = #0x22
     c66:      	ldr	r1, [r6]
     c68:      	cmp.w	r1, #0xcdcdcdcd
     c6c:      	bne	0xc8a <stop+0x6a>       @ imm = #0x1a
     c6e:      	add.w	r6, r0, #0xc
     c72:      	cmp	r6, r5
     c74:      	bhs	0xc8a <stop+0x6a>       @ imm = #0x12
     c76:      	ldr	r1, [r6]
     c78:      	cmp.w	r1, #0xcdcdcdcd
     c7c:      	bne	0xc8a <stop+0x6a>       @ imm = #0xa
     c7e:      	adds	r0, #0x10
     c80:      	cmp	r0, r5
     c82:      	mov	r6, r0
     c84:      	blo	0xc48 <stop+0x28>       @ imm = #-0x40
     c86:      	b	0xc8a <stop+0x6a>       @ imm = #0x0
     c88:      	mov	r6, r0
     c8a:      	movw	r0, #0x8c
     c8e:      	movt	r0, #0x2001
     c92:      	ldr	r2, [r0]
     c94:      	movw	r0, #0x1947
     c98:      	movt	r0, #0x0
     c9c:      	movs	r3, #0x0
     c9e:      	bl	0xe90 <text>            @ imm = #0x1ee
     ca2:      	movw	r0, #0x84
     ca6:      	movt	r0, #0x2000
     caa:      	ldr	r2, [r0]
     cac:      	movw	r0, #0x195d
     cb0:      	movt	r0, #0x0
     cb4:      	movs	r3, #0x0
     cb6:      	bl	0xe90 <text>            @ imm = #0x1d6
     cba:      	movw	r0, #0x98
     cbe:      	movt	r0, #0x2001
     cc2:      	ldrd	r2, r3, [r0]
     cc6:      	movw	r0, #0x1931
     cca:      	movt	r0, #0x0
     cce:      	bl	0xe90 <text>            @ imm = #0x1be
     cd2:      	movw	r0, #0x90
     cd6:      	movt	r0, #0x2001
     cda:      	ldrd	r2, r3, [r0]
     cde:      	movw	r0, #0x1956
     ce2:      	movt	r0, #0x0
     ce6:      	bl	0xe90 <text>            @ imm = #0x1a6
     cea:      	subs	r2, r5, r6
     cec:      	movw	r0, #0x193f
     cf0:      	asrs	r3, r2, #0x1f
     cf2:      	movt	r0, #0x0
     cf6:      	bl	0xe90 <text>            @ imm = #0x196
     cfa:      	movs	r0, #0xa
     cfc:      	strh.w	r0, [sp, #0x4]
     d00:      	movs	r0, #0x4
     d02:      	add	r1, sp, #0x4
     d04:      	bkpt	#0xab
     d06:      	movs	r0, #0x26
     d08:      	movt	r0, #0x2
     d0c:      	strd	r0, r4, [sp, #4]
     d10:      	movs	r0, #0x20
     d12:      	add	r1, sp, #0x4
     d14:      	bkpt	#0xab
     d16:      	nop
     d18:      	b	0xd18 <stop+0xf8>       @ imm = #-0x4
     d1a:      	bmi	0xcc6 <stop+0xa6>       @ imm = #-0x58

00000d1c <zs_set_args>:
     d1c:      	push	{r7, lr}
     d1e:      	mov	r7, sp
     d20:      	pop	{r7, pc}
     d22:      	bmi	0xcce <stop+0xae>       @ imm = #-0x58

00000d24 <Reset_Handler>:
     d24:      	push	{r7, lr}
     d26:      	mov	r7, sp
     d28:      	movw	r0, #0x0
     d2c:      	movw	r1, #0x0
     d30:      	movt	r0, #0x2000
     d34:      	movt	r1, #0x2000
     d38:      	cmp	r1, r0
     d3a:      	bhs	0xd6e <Reset_Handler+0x4a> @ imm = #0x30
     d3c:      	movw	r2, #0x1a84
     d40:      	movt	r2, #0x0
     d44:      	ldr	r3, [r2]
     d46:      	str	r3, [r1], #4
     d4a:      	cmp	r1, r0
     d4c:      	bhs	0xd6e <Reset_Handler+0x4a> @ imm = #0x1e
     d4e:      	ldr	r3, [r2, #0x4]
     d50:      	str	r3, [r1], #4
     d54:      	cmp	r1, r0
     d56:      	bhs	0xd6e <Reset_Handler+0x4a> @ imm = #0x14
     d58:      	ldr	r3, [r2, #0x8]
     d5a:      	str	r3, [r1], #4
     d5e:      	cmp	r1, r0
     d60:      	bhs	0xd6e <Reset_Handler+0x4a> @ imm = #0xa
     d62:      	ldr	r3, [r2, #0xc]
     d64:      	adds	r2, #0x10
     d66:      	str	r3, [r1], #4
     d6a:      	cmp	r1, r0
     d6c:      	blo	0xd44 <Reset_Handler+0x20> @ imm = #-0x2c
     d6e:      	movw	r0, #0xa4
     d72:      	movw	r1, #0x0
     d76:      	movt	r0, #0x2001
     d7a:      	movt	r1, #0x2000
     d7e:      	cmp	r1, r0
     d80:      	bhs	0xda4 <Reset_Handler+0x80> @ imm = #0x20
     d82:      	movs	r2, #0x0
     d84:      	str	r2, [r1], #4
     d88:      	cmp	r1, r0
     d8a:      	bhs	0xda4 <Reset_Handler+0x80> @ imm = #0x16
     d8c:      	str	r2, [r1], #4
     d90:      	cmp	r1, r0
     d92:      	bhs	0xda4 <Reset_Handler+0x80> @ imm = #0xe
     d94:      	str	r2, [r1], #4
     d98:      	cmp	r1, r0
     d9a:      	bhs	0xda4 <Reset_Handler+0x80> @ imm = #0x6
     d9c:      	str	r2, [r1], #4
     da0:      	cmp	r1, r0
     da2:      	blo	0xd84 <Reset_Handler+0x60> @ imm = #-0x22
     da4:      	movw	r0, #0xed88
     da8:      	movt	r0, #0xe000
     dac:      	ldr	r1, [r0]
     dae:      	orr	r1, r1, #0xf00000
     db2:      	str	r1, [r0]
     db4:      	movw	r0, #0xe010
     db8:      	movt	r0, #0xe000
     dbc:      	mvn	r1, #0xff000000
     dc0:      	dsb	sy
     dc4:      	isb	sy
     dc8:      	str	r1, [r0, #0x4]
     dca:      	movs	r1, #0x0
     dcc:      	str	r1, [r0, #0x8]
     dce:      	movs	r1, #0x7
     dd0:      	str	r1, [r0]
     dd2:      	mov	r0, sp
     dd4:      	movw	r1, #0x8000
     dd8:      	subs	r0, #0x40
     dda:      	movt	r1, #0x203f
     dde:      	cmp	r0, r1
     de0:      	bls	0xe08 <Reset_Handler+0xe4> @ imm = #0x24
     de2:      	mov.w	r2, #0xcdcdcdcd
     de6:      	nop
     de8:      	str	r2, [r1], #4
     dec:      	cmp	r1, r0
     dee:      	bhs	0xe08 <Reset_Handler+0xe4> @ imm = #0x16
     df0:      	str	r2, [r1], #4
     df4:      	cmp	r1, r0
     df6:      	bhs	0xe08 <Reset_Handler+0xe4> @ imm = #0xe
     df8:      	str	r2, [r1], #4
     dfc:      	cmp	r1, r0
     dfe:      	bhs	0xe08 <Reset_Handler+0xe4> @ imm = #0x6
     e00:      	str	r2, [r1], #4
     e04:      	cmp	r1, r0
     e06:      	blo	0xde8 <Reset_Handler+0xc4> @ imm = #-0x22
     e08:      	movs	r0, #0x0
     e0a:      	movs	r1, #0x0
     e0c:      	bl	0x70 <main>             @ imm = #-0xda0
     e10:      	bl	0xc20 <stop>            @ imm = #-0x1f4

00000e14 <zs_ticks>:
     e14:      	push	{r7, lr}
     e16:      	mov	r7, sp
     e18:      	movw	r12, #0xe018
     e1c:      	movw	r2, #0xa0
     e20:      	movt	r12, #0xe000
     e24:      	movt	r2, #0x2001
     e28:      	ldr	r1, [r2]
     e2a:      	ldr.w	r3, [r12]
     e2e:      	ldr	r0, [r2]
     e30:      	cmp	r1, r0
     e32:      	beq	0xe58 <zs_ticks+0x44>   @ imm = #0x22
     e34:      	ldr	r1, [r2]
     e36:      	ldr.w	r3, [r12]
     e3a:      	ldr	r0, [r2]
     e3c:      	cmp	r1, r0
     e3e:      	beq	0xe58 <zs_ticks+0x44>   @ imm = #0x16
     e40:      	ldr	r1, [r2]
     e42:      	ldr.w	r3, [r12]
     e46:      	ldr	r0, [r2]
     e48:      	cmp	r1, r0
     e4a:      	beq	0xe58 <zs_ticks+0x44>   @ imm = #0xa
     e4c:      	ldr	r1, [r2]
     e4e:      	ldr.w	r3, [r12]
     e52:      	ldr	r0, [r2]
     e54:      	cmp	r1, r0
     e56:      	bne	0xe28 <zs_ticks+0x14>   @ imm = #-0x32
     e58:      	mvn	r0, #0xff000000
     e5c:      	subs	r0, r0, r3
     e5e:      	lsrs	r2, r1, #0x8
     e60:      	adds.w	r0, r0, r1, lsl #24
     e64:      	adc	r1, r2, #0x0
     e68:      	pop	{r7, pc}
     e6a:      	bmi	0xe16 <zs_ticks+0x2>    @ imm = #-0x58

00000e6c <fault>:
     e6c:      	push	{r7, lr}
     e6e:      	mov	r7, sp
     e70:      	movw	r0, #0x1926
     e74:      	movt	r0, #0x0
     e78:      	bl	0x1e8 <zs_panic_c>      @ imm = #-0xc94

00000e7c <SysTick_Handler>:
     e7c:      	push	{r7, lr}
     e7e:      	mov	r7, sp
     e80:      	movw	r0, #0xa0
     e84:      	movt	r0, #0x2001
     e88:      	ldr	r1, [r0]
     e8a:      	adds	r1, #0x1
     e8c:      	str	r1, [r0]
     e8e:      	pop	{r7, pc}

00000e90 <text>:
     e90:      	push	{r4, r5, r6, r7, lr}
     e92:      	add	r7, sp, #0xc
     e94:      	push.w	{r8, r9, r10, r11}
     e98:      	sub	sp, #0x64
     e9a:      	strd	r2, r3, [sp]
     e9e:      	mov	r3, r0
     ea0:      	mov.w	r12, #0xffffffff
     ea4:      	add.w	r0, r3, r12
     ea8:      	ldrb	r1, [r0, #0x1]
     eaa:      	cbz	r1, 0xec6 <text+0x36>   @ imm = #0x18
     eac:      	ldrb	r1, [r0, #0x2]
     eae:      	cbz	r1, 0xed2 <text+0x42>   @ imm = #0x20
     eb0:      	ldrb	r1, [r0, #0x3]
     eb2:      	cbz	r1, 0xede <text+0x4e>   @ imm = #0x28
     eb4:      	ldrb	r0, [r0, #0x4]
     eb6:      	add.w	r12, r12, #0x4
     eba:      	cmp	r0, #0x0
     ebc:      	bne	0xea4 <text+0x14>       @ imm = #-0x1c
     ebe:      	cmp.w	r12, #0x0
     ec2:      	bne	0xee8 <text+0x58>       @ imm = #0x22
     ec4:      	b	0xfd6 <text+0x146>      @ imm = #0x10e
     ec6:      	add.w	r12, r12, #0x1
     eca:      	cmp.w	r12, #0x0
     ece:      	bne	0xee8 <text+0x58>       @ imm = #0x16
     ed0:      	b	0xfd6 <text+0x146>      @ imm = #0x102
     ed2:      	add.w	r12, r12, #0x2
     ed6:      	cmp.w	r12, #0x0
     eda:      	bne	0xee8 <text+0x58>       @ imm = #0xa
     edc:      	b	0xfd6 <text+0x146>      @ imm = #0xf6
     ede:      	add.w	r12, r12, #0x3
     ee2:      	cmp.w	r12, #0x0
     ee6:      	beq	0xfd6 <text+0x146>      @ imm = #0xec
     ee8:      	sub.w	r1, r7, #0x5d
     eec:      	movs	r4, #0x0
     eee:      	add.w	r10, r1, #0x1
     ef2:      	movs	r5, #0x40
     ef4:      	mov.w	r9, #0x0
     ef8:      	b	0xf18 <text+0x88>       @ imm = #0x1c
     efa:      	nop
     efc:      	strb.w	r4, [r1, r11]
     f00:      	movs	r0, #0x4
     f02:      	subs.w	r12, r12, r11
     f06:      	bkpt	#0xab
     f08:      	sbc	r9, r9, #0x0
     f0c:      	rsbs.w	r0, r12, #0x0
     f10:      	sbcs.w	r0, r4, r9
     f14:      	add	r3, r11
     f16:      	bge	0xfd6 <text+0x146>      @ imm = #0xbc
     f18:      	mov.w	r11, #0x40
     f1c:      	cmp.w	r12, #0x40
     f20:      	it	lo
     f22:      	movlo	r11, r12
     f24:      	cmp.w	r9, #0x0
     f28:      	it	ne
     f2a:      	movne	r11, r5
     f2c:      	sub.w	r0, r11, #0x1
     f30:      	cmp	r0, #0x3
     f32:      	bhs	0xf40 <text+0xb0>       @ imm = #0xa
     f34:      	movs	r0, #0x0
     f36:      	ands	r2, r11, #0x3
     f3a:      	bne	0xfa2 <text+0x112>      @ imm = #0x64
     f3c:      	b	0xefc <text+0x6c>       @ imm = #-0x44
     f3e:      	nop
     f40:      	bic	r0, r11, #0x3
     f44:      	rsb.w	lr, r0, #0x0
     f48:      	mov	r1, r3
     f4a:      	adds	r6, r3, #0x1
     f4c:      	mvn	r2, #0x3
     f50:      	adds	r3, r6, r2
     f52:      	ldrb	r5, [r3, #0x3]
     f54:      	ldrb	r4, [r3, #0x4]
     f56:      	ldrb	r0, [r3, #0x5]
     f58:      	cmp	r5, #0x0
     f5a:      	ldrb	r3, [r3, #0x6]
     f5c:      	it	eq
     f5e:      	moveq	r5, #0x20
     f60:      	add.w	r8, r10, r2
     f64:      	cmp	r4, #0x0
     f66:      	strb.w	r5, [r8, #0x3]
     f6a:      	it	eq
     f6c:      	moveq	r4, #0x20
     f6e:      	strb.w	r4, [r8, #0x4]
     f72:      	cmp	r0, #0x0
     f74:      	it	eq
     f76:      	moveq	r0, #0x20
     f78:      	adds	r2, #0x4
     f7a:      	strb.w	r0, [r8, #0x5]
     f7e:      	cmp	r3, #0x0
     f80:      	add.w	r0, lr, r2
     f84:      	it	eq
     f86:      	moveq	r3, #0x20
     f88:      	adds	r0, #0x4
     f8a:      	strb.w	r3, [r8, #0x6]
     f8e:      	bne	0xf50 <text+0xc0>       @ imm = #-0x42
     f90:      	adds	r0, r2, #0x4
     f92:      	mov	r3, r1
     f94:      	movs	r4, #0x0
     f96:      	sub.w	r1, r7, #0x5d
     f9a:      	movs	r5, #0x40
     f9c:      	ands	r2, r11, #0x3
     fa0:      	beq	0xefc <text+0x6c>       @ imm = #-0xa8
     fa2:      	ldrb	r6, [r3, r0]
     fa4:      	cmp	r6, #0x0
     fa6:      	it	eq
     fa8:      	moveq	r6, #0x20
     faa:      	cmp	r2, #0x1
     fac:      	strb	r6, [r1, r0]
     fae:      	beq	0xefc <text+0x6c>       @ imm = #-0xb6
     fb0:      	adds	r6, r0, #0x1
     fb2:      	ldrb.w	lr, [r3, r6]
     fb6:      	cmp.w	lr, #0x0
     fba:      	it	eq
     fbc:      	moveq.w	lr, #0x20
     fc0:      	cmp	r2, #0x2
     fc2:      	strb.w	lr, [r1, r6]
     fc6:      	beq	0xefc <text+0x6c>       @ imm = #-0xce
     fc8:      	adds	r0, #0x2
     fca:      	ldrb	r2, [r3, r0]
     fcc:      	cmp	r2, #0x0
     fce:      	it	eq
     fd0:      	moveq	r2, #0x20
     fd2:      	strb	r2, [r1, r0]
     fd4:      	b	0xefc <text+0x6c>       @ imm = #-0xdc
     fd6:      	movw	r9, #0xcccd
     fda:      	ldrd	r4, r5, [sp]
     fde:      	mov.w	r11, #0x1
     fe2:      	movt	r9, #0xcccc
     fe6:      	sub.w	r10, r7, #0x5d
     fea:      	nop
     fec:      	lsrs	r0, r4, #0x1
     fee:      	orr.w	r0, r0, r5, lsl #31
     ff2:      	adds.w	r1, r0, r5, lsr #1
     ff6:      	adc	r1, r1, #0x0
     ffa:      	umull	r2, r3, r1, r9
     ffe:      	bic	r2, r3, #0x3
    1002:      	add.w	r2, r2, r3, lsr #2
    1006:      	subs	r1, r1, r2
    1008:      	subs	r1, r0, r1
    100a:      	umull	r0, lr, r1, r9
    100e:      	lsr.w	r3, r5, #0x1
    1012:      	add.w	r6, r0, r0, lsl #2
    1016:      	sbc	r2, r3, #0x0
    101a:      	sub.w	r6, r4, r6, lsl #1
    101e:      	mov	r3, r4
    1020:      	subs	r4, #0xa
    1022:      	orr	r12, r6, #0x30
    1026:      	add.w	r8, r10, r11
    102a:      	sbcs	r4, r5, #0x0
    102e:      	strb	r12, [r8, #-1]
    1032:      	blo	0x112a <text+0x29a>     @ imm = #0xf4
    1034:      	mov.w	r4, #0xcccccccc
    1038:      	mla	r1, r1, r4, lr
    103c:      	mla	r1, r2, r9, r1
    1040:      	lsrs	r2, r0, #0x1
    1042:      	orr.w	r2, r2, r1, lsl #31
    1046:      	adds.w	r1, r2, r1, lsr #1
    104a:      	adc	r1, r1, #0x0
    104e:      	umull	r2, r4, r1, r9
    1052:      	bic	r2, r4, #0x3
    1056:      	add.w	r2, r2, r4, lsr #2
    105a:      	subs	r1, r1, r2
    105c:      	and	r0, r0, #0x1
    1060:      	orr.w	r0, r0, r1, lsl #1
    1064:      	subs.w	r1, r3, #0x64
    1068:      	orr	r0, r0, #0x30
    106c:      	sbcs	r1, r5, #0x0
    1070:      	mov	r4, r10
    1072:      	strb.w	r0, [r10, r11]
    1076:      	blo	0x1134 <text+0x2a4>     @ imm = #0xba
    1078:      	mov	r6, r3
    107a:      	mov	r0, r3
    107c:      	mov	r1, r5
    107e:      	movs	r2, #0x64
    1080:      	movs	r3, #0x0
    1082:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x282
    1086:      	lsrs	r2, r0, #0x1
    1088:      	orr.w	r2, r2, r1, lsl #31
    108c:      	adds.w	r1, r2, r1, lsr #1
    1090:      	adc	r1, r1, #0x0
    1094:      	umull	r2, r3, r1, r9
    1098:      	bic	r2, r3, #0x3
    109c:      	add.w	r2, r2, r3, lsr #2
    10a0:      	subs	r1, r1, r2
    10a2:      	and	r0, r0, #0x1
    10a6:      	orr.w	r0, r0, r1, lsl #1
    10aa:      	subs.w	r1, r6, #0x3e8
    10ae:      	orr	r0, r0, #0x30
    10b2:      	sbcs	r1, r5, #0x0
    10b6:      	strb.w	r0, [r8, #0x1]
    10ba:      	blo	0x113c <text+0x2ac>     @ imm = #0x7e
    10bc:      	mov	r0, r6
    10be:      	mov	r1, r5
    10c0:      	mov.w	r2, #0x3e8
    10c4:      	movs	r3, #0x0
    10c6:      	mov	r10, r4
    10c8:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x23c
    10cc:      	lsrs	r2, r0, #0x1
    10ce:      	orr.w	r2, r2, r1, lsl #31
    10d2:      	adds.w	r1, r2, r1, lsr #1
    10d6:      	adc	r1, r1, #0x0
    10da:      	umull	r2, r3, r1, r9
    10de:      	bic	r2, r3, #0x3
    10e2:      	add.w	r2, r2, r3, lsr #2
    10e6:      	subs	r1, r1, r2
    10e8:      	and	r0, r0, #0x1
    10ec:      	orr.w	r0, r0, r1, lsl #1
    10f0:      	orr	r0, r0, #0x30
    10f4:      	strb.w	r0, [r8, #0x2]
    10f8:      	mov	r0, r6
    10fa:      	mov	r1, r5
    10fc:      	movw	r2, #0x2710
    1100:      	movs	r3, #0x0
    1102:      	bl	0x1308 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x202
    1106:      	movw	r2, #0x270f
    110a:      	subs	r2, r2, r6
    110c:      	mov.w	r2, #0x0
    1110:      	sbcs	r2, r5
    1112:      	add.w	r11, r11, #0x4
    1116:      	mov	r4, r0
    1118:      	mov	r5, r1
    111a:      	blo.w	0xfec <text+0x15c>      @ imm = #-0x132
    111e:      	sub.w	r1, r11, #0x1
    1122:      	sub.w	r12, r11, #0x2
    1126:      	mov	r11, r1
    1128:      	b	0x1130 <text+0x2a0>     @ imm = #0x4
    112a:      	sub.w	r12, r11, #0x1
    112e:      	mov	r1, r11
    1130:      	mov	r4, r10
    1132:      	b	0x1146 <text+0x2b6>     @ imm = #0x10
    1134:      	add.w	r1, r11, #0x1
    1138:      	mov	r12, r11
    113a:      	b	0x1144 <text+0x2b4>     @ imm = #0x6
    113c:      	add.w	r1, r11, #0x2
    1140:      	add.w	r12, r11, #0x1
    1144:      	mov	r11, r1
    1146:      	and	lr, r1, #0x3
    114a:      	lsrs	r3, r1, #0x2
    114c:      	mov.w	r1, #0x0
    1150:      	beq	0x118a <text+0x2fa>     @ imm = #0x36
    1152:      	sub.w	r6, r7, #0x75
    1156:      	add.w	r5, r12, r4
    115a:      	sub.w	r9, r1, r3, lsl #2
    115e:      	subs	r6, #0x3
    1160:      	subs	r5, #0x1
    1162:      	nop
    1164:      	adds	r4, r5, r1
    1166:      	ldrb	r3, [r5, r1]
    1168:      	ldrb	r0, [r4, #-2]
    116c:      	ldrb	r2, [r4, #-1]
    1170:      	ldrb	r4, [r4, #0x1]
    1172:      	subs	r1, #0x4
    1174:      	strb	r3, [r6, #4]!
    1178:      	cmp	r9, r1
    117a:      	strb	r4, [r6, #-1]
    117e:      	strb	r2, [r6, #0x1]
    1180:      	strb	r0, [r6, #0x2]
    1182:      	bne	0x1164 <text+0x2d4>     @ imm = #-0x22
    1184:      	rsbs	r1, r1, #0
    1186:      	sub.w	r4, r7, #0x5d
    118a:      	cmp.w	lr, #0x0
    118e:      	beq	0x11bc <text+0x32c>     @ imm = #0x2a
    1190:      	sub.w	r0, r12, r1
    1194:      	ldrb	r0, [r4, r0]
    1196:      	sub.w	r3, r7, #0x75
    119a:      	cmp.w	lr, #0x1
    119e:      	strb	r0, [r3, r1]
    11a0:      	beq	0x11bc <text+0x32c>     @ imm = #0x18
    11a2:      	adds	r0, r1, #0x1
    11a4:      	sub.w	r2, r12, r0
    11a8:      	ldrb	r2, [r4, r2]
    11aa:      	cmp.w	lr, #0x2
    11ae:      	strb	r2, [r3, r0]
    11b0:      	beq	0x11bc <text+0x32c>     @ imm = #0x8
    11b2:      	adds	r0, r1, #0x2
    11b4:      	sub.w	r1, r12, r0
    11b8:      	ldrb	r1, [r4, r1]
    11ba:      	strb	r1, [r3, r0]
    11bc:      	sub.w	r0, r7, #0x75
    11c0:      	movs	r1, #0x0
    11c2:      	mov.w	r12, #0xffffffff
    11c6:      	strb.w	r1, [r0, r11]
    11ca:      	nop
    11cc:      	add.w	r1, r0, r12
    11d0:      	ldrb	r3, [r1, #0x1]
    11d2:      	cbz	r3, 0x11ee <text+0x35e> @ imm = #0x18
    11d4:      	ldrb	r3, [r1, #0x2]
    11d6:      	cbz	r3, 0x11fa <text+0x36a> @ imm = #0x20
    11d8:      	ldrb	r3, [r1, #0x3]
    11da:      	cbz	r3, 0x1206 <text+0x376> @ imm = #0x28
    11dc:      	ldrb	r1, [r1, #0x4]
    11de:      	add.w	r12, r12, #0x4
    11e2:      	cmp	r1, #0x0
    11e4:      	bne	0x11cc <text+0x33c>     @ imm = #-0x1c
    11e6:      	cmp.w	r12, #0x0
    11ea:      	bne	0x1210 <text+0x380>     @ imm = #0x22
    11ec:      	b	0x12f8 <text+0x468>     @ imm = #0x108
    11ee:      	add.w	r12, r12, #0x1
    11f2:      	cmp.w	r12, #0x0
    11f6:      	bne	0x1210 <text+0x380>     @ imm = #0x16
    11f8:      	b	0x12f8 <text+0x468>     @ imm = #0xfc
    11fa:      	add.w	r12, r12, #0x2
    11fe:      	cmp.w	r12, #0x0
    1202:      	bne	0x1210 <text+0x380>     @ imm = #0xa
    1204:      	b	0x12f8 <text+0x468>     @ imm = #0xf0
    1206:      	add.w	r12, r12, #0x3
    120a:      	cmp.w	r12, #0x0
    120e:      	beq	0x12f8 <text+0x468>     @ imm = #0xe6
    1210:      	movs	r2, #0x0
    1212:      	add.w	lr, r4, #0x1
    1216:      	sub.w	r9, r7, #0x75
    121a:      	movs	r3, #0x40
    121c:      	mov.w	r11, #0x0
    1220:      	b	0x1242 <text+0x3b2>     @ imm = #0x1e
    1222:      	nop
    1224:      	strb.w	r2, [r4, r8]
    1228:      	movs	r0, #0x4
    122a:      	subs.w	r12, r12, r8
    122e:      	mov	r1, r4
    1230:      	bkpt	#0xab
    1232:      	sbc	r11, r11, #0x0
    1236:      	rsbs.w	r0, r12, #0x0
    123a:      	sbcs.w	r0, r2, r11
    123e:      	add	r9, r8
    1240:      	bge	0x12f8 <text+0x468>     @ imm = #0xb4
    1242:      	mov.w	r8, #0x40
    1246:      	cmp.w	r12, #0x40
    124a:      	it	lo
    124c:      	movlo	r8, r12
    124e:      	cmp.w	r11, #0x0
    1252:      	it	ne
    1254:      	movne	r8, r3
    1256:      	sub.w	r0, r8, #0x1
    125a:      	cmp	r0, #0x3
    125c:      	bhs	0x1268 <text+0x3d8>     @ imm = #0x8
    125e:      	movs	r0, #0x0
    1260:      	ands	r1, r8, #0x3
    1264:      	bne	0x12c2 <text+0x432>     @ imm = #0x5a
    1266:      	b	0x1224 <text+0x394>     @ imm = #-0x46
    1268:      	bic	r0, r8, #0x3
    126c:      	rsb.w	r10, r0, #0x0
    1270:      	add.w	r5, r9, #0x1
    1274:      	mvn	r1, #0x3
    1278:      	adds	r4, r5, r1
    127a:      	ldrb	r2, [r4, #0x3]
    127c:      	ldrb	r3, [r4, #0x4]
    127e:      	ldrb	r6, [r4, #0x5]
    1280:      	cmp	r2, #0x0
    1282:      	ldrb	r4, [r4, #0x6]
    1284:      	it	eq
    1286:      	moveq	r2, #0x20
    1288:      	add.w	r0, lr, r1
    128c:      	cmp	r3, #0x0
    128e:      	strb	r2, [r0, #0x3]
    1290:      	it	eq
    1292:      	moveq	r3, #0x20
    1294:      	cmp	r6, #0x0
    1296:      	add.w	r1, r1, #0x4
    129a:      	strb	r3, [r0, #0x4]
    129c:      	it	eq
    129e:      	moveq	r6, #0x20
    12a0:      	cmp	r4, #0x0
    12a2:      	add.w	r2, r10, r1
    12a6:      	strb	r6, [r0, #0x5]
    12a8:      	it	eq
    12aa:      	moveq	r4, #0x20
    12ac:      	adds	r2, #0x4
    12ae:      	strb	r4, [r0, #0x6]
    12b0:      	bne	0x1278 <text+0x3e8>     @ imm = #-0x3c
    12b2:      	adds	r0, r1, #0x4
    12b4:      	sub.w	r4, r7, #0x5d
    12b8:      	movs	r2, #0x0
    12ba:      	movs	r3, #0x40
    12bc:      	ands	r1, r8, #0x3
    12c0:      	beq	0x1224 <text+0x394>     @ imm = #-0xa0
    12c2:      	ldrb.w	r5, [r9, r0]
    12c6:      	cmp	r5, #0x0
    12c8:      	it	eq
    12ca:      	moveq	r5, #0x20
    12cc:      	cmp	r1, #0x1
    12ce:      	strb	r5, [r4, r0]
    12d0:      	beq	0x1224 <text+0x394>     @ imm = #-0xb0
    12d2:      	add.w	r10, r0, #0x1
    12d6:      	ldrb.w	r5, [r9, r10]
    12da:      	cmp	r5, #0x0
    12dc:      	it	eq
    12de:      	moveq	r5, #0x20
    12e0:      	cmp	r1, #0x2
    12e2:      	strb.w	r5, [r4, r10]
    12e6:      	beq	0x1224 <text+0x394>     @ imm = #-0xc6
    12e8:      	adds	r0, #0x2
    12ea:      	ldrb.w	r1, [r9, r0]
    12ee:      	cmp	r1, #0x0
    12f0:      	it	eq
    12f2:      	moveq	r1, #0x20
    12f4:      	strb	r1, [r4, r0]
    12f6:      	b	0x1224 <text+0x394>     @ imm = #-0xd6
    12f8:      	add	sp, #0x64
    12fa:      	pop.w	{r8, r9, r10, r11}
    12fe:      	pop	{r4, r5, r6, r7, pc}

00001300 <compiler_rt.arm.__aeabi_unwind_cpp_pr0>:
    1300:      	push	{r7, lr}
    1302:      	mov	r7, sp
    1304:      	pop	{r7, pc}
    1306:      	bmi	0x12b2 <text+0x422>     @ imm = #-0x58

00001308 <compiler_rt.arm.__aeabi_uldivmod>:
    1308:      	push	{r4, lr}
    130a:      	sub	sp, #0x10
    130c:      	add	r4, sp, #0x8
    130e:      	str	r4, [sp]
    1310:      	bl	0x131c <compiler_rt.int.__udivmoddi4> @ imm = #0x8
    1314:      	ldr	r2, [sp, #0x8]
    1316:      	ldr	r3, [sp, #0xc]
    1318:      	add	sp, #0x10
    131a:      	pop	{r4, pc}

0000131c <compiler_rt.int.__udivmoddi4>:
    131c:      	push	{r4, r5, r6, r7, lr}
    131e:      	add	r7, sp, #0xc
    1320:      	push.w	{r8, r9, r10, r11}
    1324:      	sub	sp, #0x20
    1326:      	mov	r5, r2
    1328:      	ldr	r6, [r7, #0x8]
    132a:      	subs	r2, r0, r2
    132c:      	sbcs.w	r2, r1, r3
    1330:      	bhs	0x1348 <compiler_rt.int.__udivmoddi4+0x2c> @ imm = #0x14
    1332:      	cmp	r6, #0x0
    1334:      	it	ne
    1336:      	strdne	r0, r1, [r6]
    133a:      	movs	r0, #0x0
    133c:      	movs	r1, #0x0
    133e:      	add	sp, #0x20
    1340:      	pop.w	{r8, r9, r10, r11}
    1344:      	pop	{r4, r5, r6, r7, pc}
    1346:      	nop
    1348:      	cmp	r3, #0x0
    134a:      	beq.w	0x1454 <compiler_rt.int.__udivmoddi4+0x138> @ imm = #0x106
    134e:      	clz	r2, r3
    1352:      	cmp	r2, #0x0
    1354:      	beq.w	0x1480 <compiler_rt.int.__udivmoddi4+0x164> @ imm = #0x128
    1358:      	rsbs	r6, r2, #0
    135a:      	and	r4, r6, #0x1f
    135e:      	lsl.w	r12, r3, r2
    1362:      	lsr.w	r6, r5, r4
    1366:      	orr.w	r8, r6, r12
    136a:      	lsl.w	r2, r1, r2
    136e:      	lsr.w	r6, r0, r4
    1372:      	clz	lr, r8
    1376:      	orrs	r2, r6
    1378:      	ands	r12, lr, #0x1f
    137c:      	lsr.w	r6, r1, r4
    1380:      	str	r5, [sp, #0x10]
    1382:      	str	r0, [sp, #0x4]
    1384:      	beq	0x13a0 <compiler_rt.int.__udivmoddi4+0x84> @ imm = #0x18
    1386:      	lsl.w	r4, r6, r12
    138a:      	rsb.w	r6, lr, #0x0
    138e:      	and	r6, r6, #0x1f
    1392:      	lsr.w	r6, r2, r6
    1396:      	lsl.w	r8, r8, r12
    139a:      	orrs	r6, r4
    139c:      	lsl.w	r2, r2, r12
    13a0:      	lsr.w	lr, r8, #0x10
    13a4:      	udiv	r4, r6, lr
    13a8:      	strd	r3, r1, [sp, #8]
    13ac:      	mls	r9, r4, lr, r6
    13b0:      	uxth.w	r12, r8
    13b4:      	lsr.w	r11, r2, #0x10
    13b8:      	uxth	r3, r2
    13ba:      	mov	r0, r6
    13bc:      	mov.w	r10, #0x0
    13c0:      	str.w	r8, [sp]
    13c4:      	b	0x13d8 <compiler_rt.int.__udivmoddi4+0xbc> @ imm = #0x10
    13c6:      	nop
    13c8:      	subs	r6, r4, #0x4
    13ca:      	add.w	r9, r2, lr
    13ce:      	cmp.w	r10, r9, lsr #16
    13d2:      	mov	r4, r6
    13d4:      	bne.w	0x1612 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x23a
    13d8:      	cmp.w	r10, r4, lsr #16
    13dc:      	bne	0x13ec <compiler_rt.int.__udivmoddi4+0xd0> @ imm = #0xc
    13de:      	mul	r2, r4, r12
    13e2:      	orr.w	r6, r11, r9, lsl #16
    13e6:      	cmp	r2, r6
    13e8:      	bls.w	0x1610 <compiler_rt.int.__udivmoddi4+0x2f4> @ imm = #0x224
    13ec:      	add.w	r2, r9, lr
    13f0:      	cmp.w	r10, r2, lsr #16
    13f4:      	sub.w	r6, r4, #0x1
    13f8:      	bne.w	0x1612 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x216
    13fc:      	cmp.w	r10, r6, lsr #16
    1400:      	bne	0x1410 <compiler_rt.int.__udivmoddi4+0xf4> @ imm = #0xc
    1402:      	mul	r9, r6, r12
    1406:      	orr.w	r8, r11, r2, lsl #16
    140a:      	cmp	r9, r8
    140c:      	bls.w	0x1612 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x202
    1410:      	add	r2, lr
    1412:      	cmp.w	r10, r2, lsr #16
    1416:      	sub.w	r6, r4, #0x2
    141a:      	bne.w	0x1612 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1f4
    141e:      	cmp.w	r10, r6, lsr #16
    1422:      	bne	0x1432 <compiler_rt.int.__udivmoddi4+0x116> @ imm = #0xc
    1424:      	mul	r8, r6, r12
    1428:      	orr.w	r5, r11, r2, lsl #16
    142c:      	cmp	r8, r5
    142e:      	bls.w	0x1612 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1e0
    1432:      	add	r2, lr
    1434:      	cmp.w	r10, r2, lsr #16
    1438:      	sub.w	r6, r4, #0x3
    143c:      	bne.w	0x1612 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1d2
    1440:      	cmp.w	r10, r6, lsr #16
    1444:      	bne	0x13c8 <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x80
    1446:      	mul	r5, r6, r12
    144a:      	orr.w	r1, r11, r2, lsl #16
    144e:      	cmp	r5, r1
    1450:      	bhi	0x13c8 <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x8c
    1452:      	b	0x1612 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1bc
    1454:      	cmp	r1, r5
    1456:      	clz	lr, r5
    145a:      	bhs	0x1498 <compiler_rt.int.__udivmoddi4+0x17c> @ imm = #0x3a
    145c:      	cmp.w	lr, #0x0
    1460:      	beq.w	0x1568 <compiler_rt.int.__udivmoddi4+0x24c> @ imm = #0x104
    1464:      	rsb.w	r2, lr, #0x0
    1468:      	and	r2, r2, #0x1f
    146c:      	lsl.w	r1, r1, lr
    1470:      	lsr.w	r2, r0, r2
    1474:      	lsl.w	r5, r5, lr
    1478:      	orrs	r2, r1
    147a:      	lsl.w	r0, r0, lr
    147e:      	b	0x156a <compiler_rt.int.__udivmoddi4+0x24e> @ imm = #0xe8
    1480:      	cbz	r6, 0x148a <compiler_rt.int.__udivmoddi4+0x16e> @ imm = #0x6
    1482:      	subs	r0, r0, r5
    1484:      	sbcs	r1, r3
    1486:      	strd	r0, r1, [r6]
    148a:      	movs	r1, #0x0
    148c:      	movs	r0, #0x1
    148e:      	add	sp, #0x20
    1490:      	pop.w	{r8, r9, r10, r11}
    1494:      	pop	{r4, r5, r6, r7, pc}
    1496:      	nop
    1498:      	udiv	r2, r1, r5
    149c:      	cmp.w	lr, #0x0
    14a0:      	mls	r8, r2, r5, r1
    14a4:      	mov	r1, r2
    14a6:      	beq	0x14c4 <compiler_rt.int.__udivmoddi4+0x1a8> @ imm = #0x1a
    14a8:      	rsb.w	r3, lr, #0x0
    14ac:      	and	r3, r3, #0x1f
    14b0:      	lsl.w	r2, r8, lr
    14b4:      	lsr.w	r3, r0, r3
    14b8:      	lsl.w	r5, r5, lr
    14bc:      	orr.w	r8, r2, r3
    14c0:      	lsl.w	r0, r0, lr
    14c4:      	lsrs	r4, r5, #0x10
    14c6:      	str	r5, [sp, #0x10]
    14c8:      	uxth.w	r12, r5
    14cc:      	udiv	r5, r8, r4
    14d0:      	lsr.w	r10, r0, #0x10
    14d4:      	mls	r6, r5, r4, r8
    14d8:      	uxth.w	r9, r0
    14dc:      	movs	r3, #0x0
    14de:      	b	0x14ee <compiler_rt.int.__udivmoddi4+0x1d2> @ imm = #0xc
    14e0:      	subs	r0, r5, #0x4
    14e2:      	adds	r6, r2, r4
    14e4:      	cmp.w	r3, r6, lsr #16
    14e8:      	mov	r5, r0
    14ea:      	bne.w	0x172a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x23c
    14ee:      	cmp.w	r3, r5, lsr #16
    14f2:      	bne	0x1502 <compiler_rt.int.__udivmoddi4+0x1e6> @ imm = #0xc
    14f4:      	mul	r0, r5, r12
    14f8:      	orr.w	r2, r10, r6, lsl #16
    14fc:      	cmp	r0, r2
    14fe:      	bls.w	0x1728 <compiler_rt.int.__udivmoddi4+0x40c> @ imm = #0x226
    1502:      	adds	r2, r6, r4
    1504:      	cmp.w	r3, r2, lsr #16
    1508:      	sub.w	r0, r5, #0x1
    150c:      	bne.w	0x172a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x21a
    1510:      	cmp.w	r3, r0, lsr #16
    1514:      	bne	0x1524 <compiler_rt.int.__udivmoddi4+0x208> @ imm = #0xc
    1516:      	mul	r11, r0, r12
    151a:      	orr.w	r6, r10, r2, lsl #16
    151e:      	cmp	r11, r6
    1520:      	bls.w	0x172a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x206
    1524:      	add	r2, r4
    1526:      	cmp.w	r3, r2, lsr #16
    152a:      	sub.w	r0, r5, #0x2
    152e:      	bne.w	0x172a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1f8
    1532:      	cmp.w	r3, r0, lsr #16
    1536:      	bne	0x1546 <compiler_rt.int.__udivmoddi4+0x22a> @ imm = #0xc
    1538:      	mul	r11, r0, r12
    153c:      	orr.w	r6, r10, r2, lsl #16
    1540:      	cmp	r11, r6
    1542:      	bls.w	0x172a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1e4
    1546:      	add	r2, r4
    1548:      	cmp.w	r3, r2, lsr #16
    154c:      	sub.w	r0, r5, #0x3
    1550:      	bne.w	0x172a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1d6
    1554:      	cmp.w	r3, r0, lsr #16
    1558:      	bne	0x14e0 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x7c
    155a:      	mul	r11, r0, r12
    155e:      	orr.w	r6, r10, r2, lsl #16
    1562:      	cmp	r11, r6
    1564:      	bhi	0x14e0 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x88
    1566:      	b	0x172a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1c0
    1568:      	mov	r2, r1
    156a:      	lsrs	r4, r5, #0x10
    156c:      	udiv	r6, r2, r4
    1570:      	mov	r11, r5
    1572:      	uxth.w	r9, r5
    1576:      	mls	r5, r6, r4, r2
    157a:      	lsr.w	r8, r0, #0x10
    157e:      	uxth.w	r12, r0
    1582:      	mov	r1, r2
    1584:      	movs	r3, #0x0
    1586:      	b	0x1596 <compiler_rt.int.__udivmoddi4+0x27a> @ imm = #0xc
    1588:      	subs	r0, r6, #0x4
    158a:      	adds	r5, r2, r4
    158c:      	cmp.w	r3, r5, lsr #16
    1590:      	mov	r6, r0
    1592:      	bne.w	0x17c2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x22c
    1596:      	cmp.w	r3, r6, lsr #16
    159a:      	bne	0x15aa <compiler_rt.int.__udivmoddi4+0x28e> @ imm = #0xc
    159c:      	mul	r0, r6, r9
    15a0:      	orr.w	r2, r8, r5, lsl #16
    15a4:      	cmp	r0, r2
    15a6:      	bls.w	0x17c0 <compiler_rt.int.__udivmoddi4+0x4a4> @ imm = #0x216
    15aa:      	adds	r2, r5, r4
    15ac:      	cmp.w	r3, r2, lsr #16
    15b0:      	sub.w	r0, r6, #0x1
    15b4:      	bne.w	0x17c2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x20a
    15b8:      	cmp.w	r3, r0, lsr #16
    15bc:      	bne	0x15cc <compiler_rt.int.__udivmoddi4+0x2b0> @ imm = #0xc
    15be:      	mul	r10, r0, r9
    15c2:      	orr.w	r5, r8, r2, lsl #16
    15c6:      	cmp	r10, r5
    15c8:      	bls.w	0x17c2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1f6
    15cc:      	add	r2, r4
    15ce:      	cmp.w	r3, r2, lsr #16
    15d2:      	sub.w	r0, r6, #0x2
    15d6:      	bne.w	0x17c2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1e8
    15da:      	cmp.w	r3, r0, lsr #16
    15de:      	bne	0x15ee <compiler_rt.int.__udivmoddi4+0x2d2> @ imm = #0xc
    15e0:      	mul	r10, r0, r9
    15e4:      	orr.w	r5, r8, r2, lsl #16
    15e8:      	cmp	r10, r5
    15ea:      	bls.w	0x17c2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1d4
    15ee:      	add	r2, r4
    15f0:      	cmp.w	r3, r2, lsr #16
    15f4:      	sub.w	r0, r6, #0x3
    15f8:      	bne.w	0x17c2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1c6
    15fc:      	cmp.w	r3, r0, lsr #16
    1600:      	bne	0x1588 <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x7c
    1602:      	mul	r10, r0, r9
    1606:      	orr.w	r5, r8, r2, lsl #16
    160a:      	cmp	r10, r5
    160c:      	bhi	0x1588 <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x88
    160e:      	b	0x17c2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1b0
    1610:      	mov	r6, r4
    1612:      	orr.w	r2, r11, r0, lsl #16
    1616:      	ldr	r0, [sp]
    1618:      	ldr.w	r9, [sp, #0x4]
    161c:      	mls	r2, r6, r0, r2
    1620:      	mov.w	r8, #0x0
    1624:      	udiv	r4, r2, lr
    1628:      	mls	r2, r4, lr, r2
    162c:      	b	0x163c <compiler_rt.int.__udivmoddi4+0x320> @ imm = #0xc
    162e:      	nop
    1630:      	subs	r4, #0x4
    1632:      	add	r2, lr
    1634:      	cmp.w	r2, #0x10000
    1638:      	mov	r5, r4
    163a:      	bhs	0x16ae <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x70
    163c:      	cmp.w	r8, r4, lsr #16
    1640:      	bne	0x164e <compiler_rt.int.__udivmoddi4+0x332> @ imm = #0xa
    1642:      	mul	r1, r4, r12
    1646:      	orr.w	r5, r3, r2, lsl #16
    164a:      	cmp	r1, r5
    164c:      	bls	0x16ac <compiler_rt.int.__udivmoddi4+0x390> @ imm = #0x5c
    164e:      	add	r2, lr
    1650:      	cmp.w	r8, r2, lsr #16
    1654:      	sub.w	r5, r4, #0x1
    1658:      	bne	0x16ae <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x52
    165a:      	cmp.w	r8, r5, lsr #16
    165e:      	bne	0x166c <compiler_rt.int.__udivmoddi4+0x350> @ imm = #0xa
    1660:      	mul	r1, r5, r12
    1664:      	orr.w	r0, r3, r2, lsl #16
    1668:      	cmp	r1, r0
    166a:      	bls	0x16ae <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x40
    166c:      	add	r2, lr
    166e:      	cmp.w	r8, r2, lsr #16
    1672:      	sub.w	r5, r4, #0x2
    1676:      	bne	0x16ae <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x34
    1678:      	cmp.w	r8, r5, lsr #16
    167c:      	bne	0x168a <compiler_rt.int.__udivmoddi4+0x36e> @ imm = #0xa
    167e:      	mul	r0, r5, r12
    1682:      	orr.w	r1, r3, r2, lsl #16
    1686:      	cmp	r0, r1
    1688:      	bls	0x16ae <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x22
    168a:      	add	r2, lr
    168c:      	cmp.w	r8, r2, lsr #16
    1690:      	sub.w	r5, r4, #0x3
    1694:      	bne	0x16ae <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x16
    1696:      	cmp.w	r8, r5, lsr #16
    169a:      	bne	0x1630 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x6e
    169c:      	mul	r0, r5, r12
    16a0:      	orr.w	r1, r3, r2, lsl #16
    16a4:      	cmp	r0, r1
    16a6:      	bhi	0x1630 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x7a
    16a8:      	b	0x16ae <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x2
    16aa:      	nop
    16ac:      	mov	r5, r4
    16ae:      	add.w	r0, r5, r6, lsl #16
    16b2:      	ldr	r2, [sp, #0x10]
    16b4:      	ldr	r6, [sp, #0x8]
    16b6:      	umull	r4, r1, r2, r0
    16ba:      	mov	r8, r0
    16bc:      	umull	r0, r3, r6, r0
    16c0:      	adds	r5, r0, r1
    16c2:      	mov.w	r12, #0x0
    16c6:      	adc	r0, r12, #0x0
    16ca:      	orrs.w	r1, r3, r0
    16ce:      	ldr	r3, [r7, #0x8]
    16d0:      	ldr.w	lr, [sp, #0xc]
    16d4:      	strb.w	r0, [sp, #0x14]
    16d8:      	bne	0x16e4 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x8
    16da:      	cmp	r5, lr
    16dc:      	bhi	0x16e4 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x4
    16de:      	bne	0x16fa <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x18
    16e0:      	cmp	r4, r9
    16e2:      	bls	0x16fa <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x14
    16e4:      	subs	r4, r4, r2
    16e6:      	adc	r0, r12, #0x0
    16ea:      	eor	r0, r0, #0x1
    16ee:      	strb.w	r0, [sp, #0x18]
    16f2:      	add	r0, r6
    16f4:      	sub.w	r8, r8, #0x1
    16f8:      	subs	r5, r5, r0
    16fa:      	cbz	r3, 0x171a <compiler_rt.int.__udivmoddi4+0x3fe> @ imm = #0x1c
    16fc:      	subs.w	r0, r9, r4
    1700:      	mov.w	r1, #0x0
    1704:      	adc	r1, r1, #0x0
    1708:      	eor	r1, r1, #0x1
    170c:      	strb.w	r1, [sp, #0x1c]
    1710:      	add	r1, r5
    1712:      	sub.w	r1, lr, r1
    1716:      	strd	r0, r1, [r3]
    171a:      	movs	r1, #0x0
    171c:      	mov	r0, r8
    171e:      	add	sp, #0x20
    1720:      	pop.w	{r8, r9, r10, r11}
    1724:      	pop	{r4, r5, r6, r7, pc}
    1726:      	nop
    1728:      	mov	r0, r5
    172a:      	ldr	r3, [sp, #0x10]
    172c:      	orr.w	r2, r10, r8, lsl #16
    1730:      	mls	r8, r0, r3, r2
    1734:      	mov.w	r10, #0x0
    1738:      	udiv	r3, r8, r4
    173c:      	mls	r5, r3, r4, r8
    1740:      	b	0x1752 <compiler_rt.int.__udivmoddi4+0x436> @ imm = #0xe
    1742:      	nop
    1744:      	subs	r3, #0x4
    1746:      	adds	r5, r2, r4
    1748:      	cmp.w	r5, #0x10000
    174c:      	mov	r6, r3
    174e:      	bhs.w	0x1856 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x104
    1752:      	cmp.w	r10, r3, lsr #16
    1756:      	bne	0x1764 <compiler_rt.int.__udivmoddi4+0x448> @ imm = #0xa
    1758:      	mul	r2, r3, r12
    175c:      	orr.w	r6, r9, r5, lsl #16
    1760:      	cmp	r2, r6
    1762:      	bls	0x1854 <compiler_rt.int.__udivmoddi4+0x538> @ imm = #0xee
    1764:      	adds	r2, r5, r4
    1766:      	cmp.w	r10, r2, lsr #16
    176a:      	sub.w	r6, r3, #0x1
    176e:      	bne	0x1856 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xe4
    1770:      	cmp.w	r10, r6, lsr #16
    1774:      	bne	0x1782 <compiler_rt.int.__udivmoddi4+0x466> @ imm = #0xa
    1776:      	mul	r11, r6, r12
    177a:      	orr.w	r5, r9, r2, lsl #16
    177e:      	cmp	r11, r5
    1780:      	bls	0x1856 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xd2
    1782:      	add	r2, r4
    1784:      	cmp.w	r10, r2, lsr #16
    1788:      	sub.w	r6, r3, #0x2
    178c:      	bne	0x1856 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xc6
    178e:      	cmp.w	r10, r6, lsr #16
    1792:      	bne	0x17a0 <compiler_rt.int.__udivmoddi4+0x484> @ imm = #0xa
    1794:      	mul	r11, r6, r12
    1798:      	orr.w	r5, r9, r2, lsl #16
    179c:      	cmp	r11, r5
    179e:      	bls	0x1856 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xb4
    17a0:      	add	r2, r4
    17a2:      	cmp.w	r10, r2, lsr #16
    17a6:      	sub.w	r6, r3, #0x3
    17aa:      	bne	0x1856 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xa8
    17ac:      	cmp.w	r10, r6, lsr #16
    17b0:      	bne	0x1744 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x70
    17b2:      	mul	r11, r6, r12
    17b6:      	orr.w	r5, r9, r2, lsl #16
    17ba:      	cmp	r11, r5
    17bc:      	bhi	0x1744 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x7c
    17be:      	b	0x1856 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x94
    17c0:      	mov	r0, r6
    17c2:      	orr.w	r1, r8, r1, lsl #16
    17c6:      	mls	r8, r0, r11, r1
    17ca:      	mov.w	r10, #0x0
    17ce:      	udiv	r1, r8, r4
    17d2:      	mls	r5, r1, r4, r8
    17d6:      	b	0x17e4 <compiler_rt.int.__udivmoddi4+0x4c8> @ imm = #0xa
    17d8:      	subs	r1, #0x4
    17da:      	adds	r5, r2, r4
    17dc:      	cmp.w	r5, #0x10000
    17e0:      	mov	r6, r1
    17e2:      	bhs	0x186a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x84
    17e4:      	cmp.w	r10, r1, lsr #16
    17e8:      	bne	0x17f6 <compiler_rt.int.__udivmoddi4+0x4da> @ imm = #0xa
    17ea:      	mul	r2, r1, r9
    17ee:      	orr.w	r6, r12, r5, lsl #16
    17f2:      	cmp	r2, r6
    17f4:      	bls	0x1868 <compiler_rt.int.__udivmoddi4+0x54c> @ imm = #0x70
    17f6:      	adds	r2, r5, r4
    17f8:      	cmp.w	r10, r2, lsr #16
    17fc:      	sub.w	r6, r1, #0x1
    1800:      	bne	0x186a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x66
    1802:      	cmp.w	r10, r6, lsr #16
    1806:      	bne	0x1814 <compiler_rt.int.__udivmoddi4+0x4f8> @ imm = #0xa
    1808:      	mul	r5, r6, r9
    180c:      	orr.w	r3, r12, r2, lsl #16
    1810:      	cmp	r5, r3
    1812:      	bls	0x186a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x54
    1814:      	add	r2, r4
    1816:      	cmp.w	r10, r2, lsr #16
    181a:      	sub.w	r6, r1, #0x2
    181e:      	bne	0x186a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x48
    1820:      	cmp.w	r10, r6, lsr #16
    1824:      	bne	0x1832 <compiler_rt.int.__udivmoddi4+0x516> @ imm = #0xa
    1826:      	mul	r3, r6, r9
    182a:      	orr.w	r5, r12, r2, lsl #16
    182e:      	cmp	r3, r5
    1830:      	bls	0x186a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x36
    1832:      	add	r2, r4
    1834:      	cmp.w	r10, r2, lsr #16
    1838:      	sub.w	r6, r1, #0x3
    183c:      	bne	0x186a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x2a
    183e:      	cmp.w	r10, r6, lsr #16
    1842:      	bne	0x17d8 <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x6e
    1844:      	mul	r3, r6, r9
    1848:      	orr.w	r5, r12, r2, lsl #16
    184c:      	cmp	r3, r5
    184e:      	bhi	0x17d8 <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x7a
    1850:      	b	0x186a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x16
    1852:      	nop
    1854:      	mov	r6, r3
    1856:      	ldr	r3, [sp, #0x10]
    1858:      	orr.w	r2, r9, r8, lsl #16
    185c:      	mls	r2, r6, r3, r2
    1860:      	lsr.w	r2, r2, lr
    1864:      	b	0x1878 <compiler_rt.int.__udivmoddi4+0x55c> @ imm = #0x10
    1866:      	nop
    1868:      	mov	r6, r1
    186a:      	orr.w	r1, r12, r8, lsl #16
    186e:      	mls	r1, r6, r11, r1
    1872:      	lsr.w	r2, r1, lr
    1876:      	movs	r1, #0x0
    1878:      	ldr	r5, [r7, #0x8]
    187a:      	add.w	r0, r6, r0, lsl #16
    187e:      	cmp	r5, #0x0
    1880:      	itt	ne
    1882:      	movne	r3, #0x0
    1884:      	strdne	r2, r3, [r5]
    1888:      	add	sp, #0x20
    188a:      	pop.w	{r8, r9, r10, r11}
    188e:      	pop	{r4, r5, r6, r7, pc}

00001890 <.L.str.0>:
    1890: 00 00 00 00 00 00 00 00         ........
    1898: 00 00 00 00 00 00 00 00         ........
    18a0: 00 00 00 00 00 00 00 00         ........
    18a8: d4 d4 d4 d4 d4 d4 d4 d4         ........
    18b0: 00 00 00 00 00 00 00 00         ........
    18b8: 0b 00 00 00 00 00 00 00         ........
    18c0: 66 69 62 20 72 65 73 75         fib resu
    18c8: 6c 74 3d 00 00 00 00 00         lt=.....

000018d0 <.L.str.2>:
    18d0: 00 00 00 00 00 00 00 00         ........
    18d8: 07 00 00 00 00 00 00 00         ........
    18e0: 20 74 69 63 6b 73 3d 00          ticks=.
    18e8: d4 d4 d4 d4 d4 d4 d4 d4         ........

000018f0 <.L.str.3>:
    18f0: 00 00 00 00 00 00 00 00         ........
    18f8: 10 00 00 00 00 00 00 00         ........
    1900: 69 6e 74 65 67 65 72 20         integer 
    1908: 6f 76 65 72 66 6c 6f 77         overflow
    1910: 00 00 00 00 00 00 00 00         ........
    1918: 6f 75 74 20 6f 66 20 6d         out of m
    1920: 65 6d 6f 72 79 00 68 61         emory.ha
    1928: 72 64 20 66 61 75 6c 74         rd fault
    1930: 00 20 61 6c 6c 6f 63 61         . alloca
    1938: 74 69 6f 6e 73 3d 00 20         tions=. 
    1940: 73 74 61 63 6b 3d 00 23         stack=.#
    1948: 7a 73 20 68 65 61 70 5f         zs heap_
    1950: 70 65 61 6b 3d 00 20 6c         peak=. l
    1958: 69 76 65 3d 00 20 68 65         ive=. he
    1960: 61 70 5f 72 65 73 65 72         ap_reser
    1968: 76 65 64 3d 00 70 61 6e         ved=.pan
    1970: 69 63 3a 20 00 0a 00 d4         ic: ....
