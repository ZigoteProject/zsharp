
/tmp/isort.elf:	file format elf32-littlearm

Disassembly of section .text:

00000000 <vectors>:
       0: 00 00 40 20 79 12 00 00         ..@ y...
       8: c1 13 00 00 c1 13 00 00         ........
      10: c1 13 00 00 c1 13 00 00         ........
      18: c1 13 00 00 00 00 00 00         ........
      20: 00 00 00 00 00 00 00 00         ........
      28: 00 00 00 00 c1 13 00 00         ........
      30: c1 13 00 00 00 00 00 00         ........
      38: c1 13 00 00 d1 13 00 00         ........

00000040 <main>:
      40:      	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
      44:      	sub	sp, #0x1c
      46:      	bl	0x1270 <zs_set_args>    @ imm = #0x1226
      4a:      	mov.w	r0, #0x810
      4e:      	movs	r1, #0x0
      50:      	movs	r4, #0x0
      52:      	bl	0x678 <zs_alloc>        @ imm = #0x622
      56:      	mov	r5, r0
      58:      	movs	r1, #0x1
      5a:      	mov.w	r0, #0x200
      5e:      	strd	r1, r4, [r5]
      62:      	strd	r0, r4, [r5, #8]
      66:      	add.w	r0, r5, #0x10
      6a:      	mov.w	r1, #0x800
      6e:      	bl	0x18c0 <compiler_rt.arm.__aeabi_memclr> @ imm = #0x184e
      72:      	movw	r6, #0x4585
      76:      	movw	r11, #0x1eef
      7a:      	movt	r6, #0x3ce
      7e:      	movw	r8, #0x3f1
      82:      	movw	r4, #0x1ff
      86:      	movs	r0, #0x1
      88:      	movs	r1, #0x0
      8a:      	mov.w	r9, #0x0
      8e:      	mov.w	r10, #0x0
      92:      	nop
      94:      	eor	r0, r0, #0x1
      98:      	orrs	r0, r1
      9a:      	beq	0xfe <main+0xbe>        @ imm = #0x60
      9c:      	ldrd	r0, r1, [r5, #8]
      a0:      	movs	r2, #0x10
      a2:      	lsls	r1, r1, #0x2
      a4:      	mov	r7, r6
      a6:      	orr.w	r1, r1, r0, lsr #30
      aa:      	adds.w	r6, r2, r0, lsl #2
      ae:      	adc	r1, r1, #0x0
      b2:      	mov	r0, r6
      b4:      	movw	r8, #0x3f1
      b8:      	movw	r11, #0x1eef
      bc:      	mov	r4, r5
      be:      	bl	0x678 <zs_alloc>        @ imm = #0x5b6
      c2:      	mov	r1, r4
      c4:      	mov	r2, r6
      c6:      	mov	r5, r0
      c8:      	bl	0x18d0 <compiler_rt.arm.__aeabi_memcpy> @ imm = #0x1804
      cc:      	movs	r1, #0x0
      ce:      	movs	r2, #0x1
      d0:      	strd	r2, r1, [r5]
      d4:      	ldrd	r1, r3, [r4]
      d8:      	orrs.w	r2, r1, r3
      dc:      	beq	0xf8 <main+0xb8>        @ imm = #0x18
      de:      	eor	r2, r1, #0x1
      e2:      	orrs	r2, r3
      e4:      	bne	0xee <main+0xae>        @ imm = #0x6
      e6:      	mov	r0, r4
      e8:      	bl	0x768 <zs_free>         @ imm = #0x67c
      ec:      	b	0xf8 <main+0xb8>        @ imm = #0x8
      ee:      	subs	r1, #0x1
      f0:      	sbc	r2, r3, #0x0
      f4:      	strd	r1, r2, [r4]
      f8:      	mov	r6, r7
      fa:      	movw	r4, #0x1ff
      fe:      	ldrd	r0, r1, [r5, #8]
     102:      	subs.w	r0, r9, r0
     106:      	sbcs.w	r0, r10, r1
     10a:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x54e
     10e:      	mul	r0, r9, r11
     112:      	umull	r1, r2, r0, r6
     116:      	subs	r1, r0, r2
     118:      	add.w	r1, r2, r1, lsr #1
     11c:      	lsrs	r1, r1, #0x9
     11e:      	mls	r0, r1, r8, r0
     122:      	subs.w	r2, r9, r4
     126:      	add.w	r1, r5, r9, lsl #2
     12a:      	sbcs	r2, r10, #0x0
     12e:      	str	r0, [r1, #0x10]
     130:      	bhs	0x140 <main+0x100>      @ imm = #0xc
     132:      	adds.w	r9, r9, #0x1
     136:      	ldrd	r0, r1, [r5]
     13a:      	adc	r10, r10, #0x0
     13e:      	b	0x94 <main+0x54>        @ imm = #-0xae
     140:      	mov.w	r4, #0xffffffff
     144:      	bl	0x1368 <zs_ticks>       @ imm = #0x1220
     148:      	str	r0, [sp, #0x4]
     14a:      	ldrd	r0, r7, [r5]
     14e:      	ldrd	r3, r2, [r5, #8]
     152:      	mov	lr, r5
     154:      	orrs.w	r6, r0, r7
     158:      	str	r1, [sp]
     15a:      	beq	0x172 <main+0x132>      @ imm = #0x14
     15c:      	eor.w	r1, r0, r4
     160:      	eor.w	r6, r7, r4
     164:      	orrs	r1, r6
     166:      	ite	eq
     168:      	moveq	r0, r1
     16a:      	movne	r1, r7
     16c:      	strd	r0, r1, [lr]
     170:      	b	0x176 <main+0x136>      @ imm = #0x2
     172:      	movs	r0, #0x0
     174:      	movs	r1, #0x0
     176:      	subs	r7, r3, #0x1
     178:      	sbc	r6, r2, #0x0
     17c:      	eor.w	r3, r2, r6
     180:      	ands	r2, r3
     182:      	cmp.w	r2, #0xffffffff
     186:      	ble.w	0x66a <main+0x62a>      @ imm = #0x4e0
     18a:      	subs	r2, r7, #0x1
     18c:      	sbcs	r2, r6, #0x0
     190:      	blt.w	0x40e <main+0x3ce>      @ imm = #0x27a
     194:      	movs	r4, #0x1
     196:      	movs	r5, #0x0
     198:      	strd	r6, r7, [sp, #8]
     19c:      	ldrd	r0, r1, [lr]
     1a0:      	orrs.w	r2, r0, r1
     1a4:      	beq	0x1d0 <main+0x190>      @ imm = #0x28
     1a6:      	ldrd	r7, r6, [lr, #8]
     1aa:      	adds	r2, r0, #0x1
     1ac:      	adc	r3, r1, #0x0
     1b0:      	subs	r7, r4, r7
     1b2:      	sbcs.w	r7, r5, r6
     1b6:      	strd	r2, r3, [lr]
     1ba:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x49e
     1be:      	add.w	r7, lr, r4, lsl #2
     1c2:      	ldr	r7, [r7, #0x10]
     1c4:      	orrs	r2, r3
     1c6:      	str	r7, [sp, #0x18]
     1c8:      	it	ne
     1ca:      	strdne	r0, r1, [lr]
     1ce:      	b	0x1e6 <main+0x1a6>      @ imm = #0x14
     1d0:      	ldrd	r0, r1, [lr, #8]
     1d4:      	subs	r0, r4, r0
     1d6:      	sbcs.w	r0, r5, r1
     1da:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x47e
     1de:      	add.w	r0, lr, r4, lsl #2
     1e2:      	ldr	r0, [r0, #0x10]
     1e4:      	str	r0, [sp, #0x18]
     1e6:      	subs.w	r8, r4, #0x1
     1ea:      	sbc	r10, r5, #0x0
     1ee:      	eor.w	r0, r5, r10
     1f2:      	ands	r0, r5
     1f4:      	cmp.w	r0, #0xffffffff
     1f8:      	str	r4, [sp, #0x14]
     1fa:      	str	r5, [sp, #0x10]
     1fc:      	ble.w	0x66a <main+0x62a>      @ imm = #0x46a
     200:      	cmp.w	r10, #0x0
     204:      	bmi.w	0x350 <main+0x310>      @ imm = #0x148
     208:      	ldrd	r2, r6, [lr]
     20c:      	orrs.w	r0, r2, r6
     210:      	beq	0x240 <main+0x200>      @ imm = #0x2c
     212:      	ldrd	r0, r1, [lr, #8]
     216:      	adds	r5, r2, #0x1
     218:      	adc	r4, r6, #0x0
     21c:      	subs.w	r3, r8, r0
     220:      	sbcs.w	r3, r10, r1
     224:      	strd	r5, r4, [lr]
     228:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x430
     22c:      	add.w	r3, lr, r8, lsl #2
     230:      	ldr	r7, [r3, #16]!
     234:      	orrs	r5, r4
     236:      	beq	0x258 <main+0x218>      @ imm = #0x1e
     238:      	strd	r2, r6, [lr]
     23c:      	b	0x25c <main+0x21c>      @ imm = #0x1c
     23e:      	nop
     240:      	ldrd	r0, r1, [lr, #8]
     244:      	subs.w	r2, r8, r0
     248:      	sbcs.w	r2, r10, r1
     24c:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x40c
     250:      	add.w	r3, lr, r8, lsl #2
     254:      	ldr	r7, [r3, #16]!
     258:      	movs	r2, #0x0
     25a:      	movs	r6, #0x0
     25c:      	ldr	r5, [sp, #0x18]
     25e:      	cmp	r7, r5
     260:      	ble	0x350 <main+0x310>      @ imm = #0xec
     262:      	adds.w	r11, r8, #0x1
     266:      	adc	r7, r10, #0x0
     26a:      	eor.w	r5, r10, r7
     26e:      	bic.w	r5, r5, r10
     272:      	cmp.w	r5, #0xffffffff
     276:      	ble.w	0x66a <main+0x62a>      @ imm = #0x3f0
     27a:      	orrs.w	r5, r2, r6
     27e:      	beq	0x2b0 <main+0x270>      @ imm = #0x2e
     280:      	ldrd	r0, r1, [lr, #8]
     284:      	adds.w	r12, r2, #0x1
     288:      	adc	r4, r6, #0x0
     28c:      	subs.w	r5, r8, r0
     290:      	sbcs.w	r5, r10, r1
     294:      	strd	r12, r4, [lr]
     298:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x3c0
     29c:      	ldr.w	r9, [r3]
     2a0:      	eor	r3, r2, #0x1
     2a4:      	orrs	r3, r6
     2a6:      	strd	r2, r6, [lr]
     2aa:      	bne	0x2c0 <main+0x280>      @ imm = #0x12
     2ac:      	b	0x310 <main+0x2d0>      @ imm = #0x60
     2ae:      	nop
     2b0:      	subs.w	r2, r8, r0
     2b4:      	sbcs.w	r2, r10, r1
     2b8:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x3a0
     2bc:      	ldr.w	r9, [r3]
     2c0:      	lsls	r1, r1, #0x2
     2c2:      	movs	r2, #0x10
     2c4:      	orr.w	r1, r1, r0, lsr #30
     2c8:      	adds.w	r6, r2, r0, lsl #2
     2cc:      	adc	r1, r1, #0x0
     2d0:      	mov	r0, r6
     2d2:      	mov	r4, lr
     2d4:      	bl	0x678 <zs_alloc>        @ imm = #0x3a0
     2d8:      	mov	r1, r4
     2da:      	mov	r2, r6
     2dc:      	mov	r5, r0
     2de:      	bl	0x18d0 <compiler_rt.arm.__aeabi_memcpy> @ imm = #0x15ee
     2e2:      	movs	r1, #0x0
     2e4:      	movs	r2, #0x1
     2e6:      	strd	r2, r1, [r5]
     2ea:      	ldrd	r1, r3, [r4]
     2ee:      	orrs.w	r2, r1, r3
     2f2:      	beq	0x30e <main+0x2ce>      @ imm = #0x18
     2f4:      	eor	r2, r1, #0x1
     2f8:      	orrs	r2, r3
     2fa:      	bne	0x304 <main+0x2c4>      @ imm = #0x6
     2fc:      	mov	r0, r4
     2fe:      	bl	0x768 <zs_free>         @ imm = #0x466
     302:      	b	0x30e <main+0x2ce>      @ imm = #0x8
     304:      	subs	r1, #0x1
     306:      	sbc	r2, r3, #0x0
     30a:      	strd	r1, r2, [r4]
     30e:      	mov	lr, r5
     310:      	ldrd	r0, r1, [lr, #8]
     314:      	subs.w	r0, r11, r0
     318:      	sbcs.w	r0, r7, r1
     31c:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x33c
     320:      	add.w	r0, lr, r11, lsl #2
     324:      	str.w	r9, [r0, #0x10]
     328:      	subs.w	r0, r8, #0x1
     32c:      	sbc	r1, r10, #0x0
     330:      	rsbs.w	r2, r8, #0x0
     334:      	mov.w	r2, #0x0
     338:      	sbcs.w	r2, r2, r10
     33c:      	mov	r8, r0
     33e:      	mov	r10, r1
     340:      	blt.w	0x208 <main+0x1c8>      @ imm = #-0x13c
     344:      	mov	r11, lr
     346:      	mov.w	r8, #0xffffffff
     34a:      	mov.w	r10, #0xffffffff
     34e:      	b	0x352 <main+0x312>      @ imm = #0x0
     350:      	mov	r11, lr
     352:      	adds.w	r7, r8, #0x1
     356:      	adc	r6, r10, #0x0
     35a:      	eor.w	r0, r10, r6
     35e:      	bic.w	r0, r0, r10
     362:      	cmp.w	r0, #0xffffffff
     366:      	ble.w	0x66a <main+0x62a>      @ imm = #0x300
     36a:      	ldrd	r0, r1, [r11]
     36e:      	ldrd	r5, r4, [sp, #16]
     372:      	eor	r0, r0, #0x1
     376:      	orrs	r0, r1
     378:      	bne	0x380 <main+0x340>      @ imm = #0x4
     37a:      	mov	lr, r11
     37c:      	b	0x3d0 <main+0x390>      @ imm = #0x50
     37e:      	nop
     380:      	ldrd	r0, r1, [r11, #8]
     384:      	movs	r2, #0x10
     386:      	lsls	r1, r1, #0x2
     388:      	orr.w	r1, r1, r0, lsr #30
     38c:      	adds.w	r8, r2, r0, lsl #2
     390:      	adc	r1, r1, #0x0
     394:      	mov	r0, r8
     396:      	bl	0x678 <zs_alloc>        @ imm = #0x2de
     39a:      	mov	r1, r11
     39c:      	mov	r2, r8
     39e:      	mov	r9, r0
     3a0:      	bl	0x18d0 <compiler_rt.arm.__aeabi_memcpy> @ imm = #0x152c
     3a4:      	mov	lr, r9
     3a6:      	movs	r0, #0x0
     3a8:      	movs	r1, #0x1
     3aa:      	strd	r1, r0, [lr]
     3ae:      	ldrd	r1, r0, [r11]
     3b2:      	orrs.w	r2, r1, r0
     3b6:      	beq	0x3d0 <main+0x390>      @ imm = #0x16
     3b8:      	eor	r2, r1, #0x1
     3bc:      	ldrd	r8, r9, [sp, #8]
     3c0:      	orrs	r2, r0
     3c2:      	bne	0x3fe <main+0x3be>      @ imm = #0x38
     3c4:      	mov	r0, r11
     3c6:      	mov	r10, lr
     3c8:      	bl	0x768 <zs_free>         @ imm = #0x39c
     3cc:      	mov	lr, r10
     3ce:      	b	0x3d4 <main+0x394>      @ imm = #0x2
     3d0:      	ldrd	r8, r9, [sp, #8]
     3d4:      	ldrd	r0, r1, [lr, #8]
     3d8:      	subs	r0, r7, r0
     3da:      	sbcs.w	r0, r6, r1
     3de:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x27a
     3e2:      	adds	r4, #0x1
     3e4:      	adc	r5, r5, #0x0
     3e8:      	subs.w	r1, r9, r4
     3ec:      	sbcs.w	r1, r8, r5
     3f0:      	ldr	r1, [sp, #0x18]
     3f2:      	add.w	r0, lr, r7, lsl #2
     3f6:      	str	r1, [r0, #0x10]
     3f8:      	bge.w	0x19c <main+0x15c>      @ imm = #-0x260
     3fc:      	b	0x40a <main+0x3ca>      @ imm = #0xa
     3fe:      	subs	r1, #0x1
     400:      	sbc	r0, r0, #0x0
     404:      	strd	r1, r0, [r11]
     408:      	b	0x3d4 <main+0x394>      @ imm = #-0x38
     40a:      	ldrd	r0, r1, [lr]
     40e:      	orrs.w	r2, r0, r1
     412:      	mov.w	r3, #0xffffffff
     416:      	beq	0x42a <main+0x3ea>      @ imm = #0x10
     418:      	eor.w	r2, r0, r3
     41c:      	eors	r3, r1
     41e:      	orrs	r2, r3
     420:      	ite	eq
     422:      	moveq	r0, r2
     424:      	movne	r2, r1
     426:      	strd	r0, r2, [lr]
     42a:      	mov	r8, lr
     42c:      	bl	0x1368 <zs_ticks>       @ imm = #0xf38
     430:      	ldrd	r2, r3, [r8]
     434:      	mov	r5, r8
     436:      	mov	r10, r0
     438:      	orrs.w	r0, r2, r3
     43c:      	mov	r9, r1
     43e:      	beq	0x474 <main+0x434>      @ imm = #0x32
     440:      	ldrd	r1, r0, [r5, #8]
     444:      	adds	r6, r2, #0x1
     446:      	adc	r4, r3, #0x0
     44a:      	orrs.w	r7, r1, r0
     44e:      	strd	r6, r4, [r5]
     452:      	beq.w	0x65c <main+0x61c>      @ imm = #0x206
     456:      	ldr	r7, [r5, #0x10]
     458:      	orrs	r6, r4
     45a:      	beq	0x490 <main+0x450>      @ imm = #0x32
     45c:      	rsbs.w	r6, r1, #0xff
     460:      	mov.w	r6, #0x0
     464:      	sbcs	r6, r0
     466:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x1f2
     46a:      	ldr.w	r6, [r5, #0x40c]
     46e:      	strd	r2, r3, [r5]
     472:      	b	0x4a6 <main+0x466>      @ imm = #0x30
     474:      	ldrd	r1, r0, [r5, #8]
     478:      	orrs.w	r2, r1, r0
     47c:      	beq.w	0x65c <main+0x61c>      @ imm = #0x1dc
     480:      	subs.w	r2, r1, #0x100
     484:      	sbcs	r2, r0, #0x0
     488:      	blo.w	0x65c <main+0x61c>      @ imm = #0x1d0
     48c:      	ldr	r7, [r5, #0x10]
     48e:      	b	0x49e <main+0x45e>      @ imm = #0xc
     490:      	rsbs.w	r2, r1, #0xff
     494:      	mov.w	r2, #0x0
     498:      	sbcs	r2, r0
     49a:      	bhs.w	0x65c <main+0x61c>      @ imm = #0x1be
     49e:      	ldr.w	r6, [r5, #0x40c]
     4a2:      	movs	r2, #0x0
     4a4:      	movs	r3, #0x0
     4a6:      	adds	r7, r7, r6
     4a8:      	bvs.w	0x66a <main+0x62a>      @ imm = #0x1be
     4ac:      	orrs.w	r6, r2, r3
     4b0:      	beq	0x4d6 <main+0x496>      @ imm = #0x22
     4b2:      	ldrd	r1, r6, [r5, #8]
     4b6:      	adds	r0, r2, #0x1
     4b8:      	adc	r4, r3, #0x0
     4bc:      	orrs.w	r1, r6, r1, lsr #9
     4c0:      	strd	r0, r4, [r5]
     4c4:      	beq.w	0x65c <main+0x61c>      @ imm = #0x194
     4c8:      	ldr.w	r0, [r5, #0x80c]
     4cc:      	strd	r2, r3, [r5]
     4d0:      	adds	r0, r0, r7
     4d2:      	bvc	0x4ec <main+0x4ac>      @ imm = #0x16
     4d4:      	b	0x66a <main+0x62a>      @ imm = #0x192
     4d6:      	subs.w	r1, r1, #0x200
     4da:      	sbcs	r0, r0, #0x0
     4de:      	blo.w	0x65c <main+0x61c>      @ imm = #0x17a
     4e2:      	ldr.w	r0, [r5, #0x80c]
     4e6:      	adds	r0, r0, r7
     4e8:      	bvs.w	0x66a <main+0x62a>      @ imm = #0x17e
     4ec:      	asrs	r1, r0, #0x1f
     4ee:      	bl	0xcf0 <zs_str_of_i64>   @ imm = #0x7fe
     4f2:      	mov	r6, r0
     4f4:      	movw	r0, #0x1fd0
     4f8:      	movt	r0, #0x0
     4fc:      	mov	r1, r6
     4fe:      	bl	0x7b8 <zs_str_concat>   @ imm = #0x2b6
     502:      	ldrd	r2, r1, [r6]
     506:      	mov	r7, r0
     508:      	orrs.w	r3, r2, r1
     50c:      	beq	0x528 <main+0x4e8>      @ imm = #0x18
     50e:      	eor	r0, r2, #0x1
     512:      	orrs	r0, r1
     514:      	bne	0x51e <main+0x4de>      @ imm = #0x6
     516:      	mov	r0, r6
     518:      	bl	0x768 <zs_free>         @ imm = #0x24c
     51c:      	b	0x528 <main+0x4e8>      @ imm = #0x8
     51e:      	subs	r0, r2, #0x1
     520:      	sbc	r1, r1, #0x0
     524:      	strd	r0, r1, [r6]
     528:      	movw	r1, #0x1ff0
     52c:      	movt	r1, #0x0
     530:      	mov	r0, r7
     532:      	bl	0x7b8 <zs_str_concat>   @ imm = #0x282
     536:      	ldrd	r2, r1, [r7]
     53a:      	mov	r6, r0
     53c:      	orrs.w	r3, r2, r1
     540:      	beq	0x55c <main+0x51c>      @ imm = #0x18
     542:      	eor	r0, r2, #0x1
     546:      	orrs	r0, r1
     548:      	bne	0x552 <main+0x512>      @ imm = #0x6
     54a:      	mov	r0, r7
     54c:      	bl	0x768 <zs_free>         @ imm = #0x218
     550:      	b	0x55c <main+0x51c>      @ imm = #0x8
     552:      	subs	r0, r2, #0x1
     554:      	sbc	r1, r1, #0x0
     558:      	strd	r0, r1, [r7]
     55c:      	ldr	r0, [sp, #0x4]
     55e:      	ldr	r1, [sp]
     560:      	subs.w	r0, r10, r0
     564:      	sbcs.w	r1, r9, r1
     568:      	mov.w	r2, #0x0
     56c:      	adc	r2, r2, #0x0
     570:      	eor	r2, r2, #0x1
     574:      	cmp	r2, #0x1
     576:      	beq	0x66a <main+0x62a>      @ imm = #0xf0
     578:      	bl	0x9a4 <zs_str_of_u64>   @ imm = #0x428
     57c:      	mov	r7, r0
     57e:      	mov	r0, r6
     580:      	mov	r1, r7
     582:      	bl	0x7b8 <zs_str_concat>   @ imm = #0x232
     586:      	ldrd	r2, r1, [r6]
     58a:      	mov	r5, r0
     58c:      	orrs.w	r3, r2, r1
     590:      	beq	0x5ac <main+0x56c>      @ imm = #0x18
     592:      	eor	r0, r2, #0x1
     596:      	orrs	r0, r1
     598:      	bne	0x5a2 <main+0x562>      @ imm = #0x6
     59a:      	mov	r0, r6
     59c:      	bl	0x768 <zs_free>         @ imm = #0x1c8
     5a0:      	b	0x5ac <main+0x56c>      @ imm = #0x8
     5a2:      	subs	r0, r2, #0x1
     5a4:      	sbc	r1, r1, #0x0
     5a8:      	strd	r0, r1, [r6]
     5ac:      	ldrd	r1, r0, [r7]
     5b0:      	orrs.w	r2, r1, r0
     5b4:      	beq	0x5d0 <main+0x590>      @ imm = #0x18
     5b6:      	eor	r2, r1, #0x1
     5ba:      	orrs	r2, r0
     5bc:      	bne	0x5c6 <main+0x586>      @ imm = #0x6
     5be:      	mov	r0, r7
     5c0:      	bl	0x768 <zs_free>         @ imm = #0x1a4
     5c4:      	b	0x5d0 <main+0x590>      @ imm = #0x8
     5c6:      	subs	r1, #0x1
     5c8:      	sbc	r0, r0, #0x0
     5cc:      	strd	r1, r0, [r7]
     5d0:      	movw	r0, #0x1fb0
     5d4:      	movt	r0, #0x0
     5d8:      	mov	r1, r5
     5da:      	bl	0x7b8 <zs_str_concat>   @ imm = #0x1da
     5de:      	ldrd	r2, r1, [r5]
     5e2:      	mov	r6, r0
     5e4:      	orrs.w	r3, r2, r1
     5e8:      	beq	0x604 <main+0x5c4>      @ imm = #0x18
     5ea:      	eor	r0, r2, #0x1
     5ee:      	orrs	r0, r1
     5f0:      	bne	0x5fa <main+0x5ba>      @ imm = #0x6
     5f2:      	mov	r0, r5
     5f4:      	bl	0x768 <zs_free>         @ imm = #0x170
     5f8:      	b	0x604 <main+0x5c4>      @ imm = #0x8
     5fa:      	subs	r0, r2, #0x1
     5fc:      	sbc	r1, r1, #0x0
     600:      	strd	r0, r1, [r5]
     604:      	mov	r0, r6
     606:      	bl	0xf18 <zs_println>      @ imm = #0x90e
     60a:      	ldrd	r1, r3, [r6]
     60e:      	mov	r0, r8
     610:      	orrs.w	r2, r1, r3
     614:      	beq	0x632 <main+0x5f2>      @ imm = #0x1a
     616:      	eor	r2, r1, #0x1
     61a:      	orrs	r2, r3
     61c:      	bne	0x628 <main+0x5e8>      @ imm = #0x8
     61e:      	mov	r0, r6
     620:      	bl	0x768 <zs_free>         @ imm = #0x144
     624:      	mov	r0, r8
     626:      	b	0x632 <main+0x5f2>      @ imm = #0x8
     628:      	subs	r1, #0x1
     62a:      	sbc	r2, r3, #0x0
     62e:      	strd	r1, r2, [r6]
     632:      	ldrd	r1, r3, [r0]
     636:      	orrs.w	r2, r1, r3
     63a:      	beq	0x654 <main+0x614>      @ imm = #0x16
     63c:      	eor	r2, r1, #0x1
     640:      	orrs	r2, r3
     642:      	bne	0x64a <main+0x60a>      @ imm = #0x4
     644:      	bl	0x768 <zs_free>         @ imm = #0x120
     648:      	b	0x654 <main+0x614>      @ imm = #0x8
     64a:      	subs	r1, #0x1
     64c:      	sbc	r2, r3, #0x0
     650:      	strd	r1, r2, [r0]
     654:      	movs	r0, #0x0
     656:      	add	sp, #0x1c
     658:      	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
     65c:      	movw	r0, #0x1f80
     660:      	movt	r0, #0x0
     664:      	adds	r0, #0x10
     666:      	bl	0x73c <zs_panic_c>      @ imm = #0xd2
     66a:      	movw	r0, #0x1f50
     66e:      	movt	r0, #0x0
     672:      	adds	r0, #0x10
     674:      	bl	0x73c <zs_panic_c>      @ imm = #0xc4

00000678 <zs_alloc>:
     678:      	push	{r4, r6, r7, lr}
     67a:      	add	r7, sp, #0x8
     67c:      	adds	r0, #0x7
     67e:      	lsrs	r2, r0, #0x3
     680:      	cmp	r2, #0x20
     682:      	bhi	0x6a0 <zs_alloc+0x28>   @ imm = #0x1a
     684:      	movw	r12, #0x0
     688:      	movt	r12, #0x2000
     68c:      	ldr.w	r1, [r12, r2, lsl #2]
     690:      	cbz	r1, 0x6a0 <zs_alloc+0x28> @ imm = #0xc
     692:      	mov	r0, r1
     694:      	ldr	r3, [r1]
     696:      	ldr	r1, [r0, #-8]!
     69a:      	str.w	r3, [r12, r2, lsl #2]
     69e:      	b	0x6d8 <zs_alloc+0x60>   @ imm = #0x36
     6a0:      	movw	r12, #0x84
     6a4:      	movt	r12, #0x2000
     6a8:      	ldr.w	r2, [r12]
     6ac:      	bic	r1, r0, #0x7
     6b0:      	adds	r3, r1, r2
     6b2:      	movw	r0, #0xfff9
     6b6:      	subs	r0, r3, r0
     6b8:      	cmn.w	r0, #0x10001
     6bc:      	blo	0x72e <zs_alloc+0xb6>   @ imm = #0x6e
     6be:      	movw	lr, #0x88
     6c2:      	movt	lr, #0x2000
     6c6:      	add.w	r0, lr, r2
     6ca:      	adds	r3, #0x8
     6cc:      	str.w	r1, [lr, r2]
     6d0:      	movs	r2, #0x0
     6d2:      	str.w	r3, [r12]
     6d6:      	str	r2, [r0, #0x4]
     6d8:      	movw	lr, #0x88
     6dc:      	movt	lr, #0x2001
     6e0:      	ldr.w	r2, [lr]
     6e4:      	movw	r12, #0x8c
     6e8:      	movt	r12, #0x2001
     6ec:      	ldr.w	r3, [r12]
     6f0:      	add	r1, r2
     6f2:      	str.w	r1, [lr]
     6f6:      	movw	lr, #0x90
     6fa:      	cmp	r1, r3
     6fc:      	it	hi
     6fe:      	strhi.w	r1, [r12]
     702:      	movt	lr, #0x2001
     706:      	movw	r12, #0x98
     70a:      	ldrd	r2, r3, [lr]
     70e:      	movt	r12, #0x2001
     712:      	ldrd	r1, r4, [r12]
     716:      	adds	r2, #0x1
     718:      	adc	r3, r3, #0x0
     71c:      	adds	r1, #0x1
     71e:      	strd	r2, r3, [lr]
     722:      	adc	r2, r4, #0x0
     726:      	adds	r0, #0x8
     728:      	strd	r1, r2, [r12]
     72c:      	pop	{r4, r6, r7, pc}
     72e:      	movw	r0, #0x2008
     732:      	movt	r0, #0x0
     736:      	bl	0x73c <zs_panic_c>      @ imm = #0x2
     73a:      	bmi	0x6e6 <zs_alloc+0x6e>   @ imm = #-0x58

0000073c <zs_panic_c>:
     73c:      	push	{r4, r6, r7, lr}
     73e:      	add	r7, sp, #0x8
     740:      	mov	r4, r0
     742:      	movw	r0, #0x205d
     746:      	movt	r0, #0x0
     74a:      	bl	0x1030 <write_c>        @ imm = #0x8e2
     74e:      	mov	r0, r4
     750:      	bl	0x1030 <write_c>        @ imm = #0x8dc
     754:      	movw	r0, #0x2065
     758:      	movt	r0, #0x0
     75c:      	bl	0x1030 <write_c>        @ imm = #0x8d0
     760:      	movs	r0, #0x86
     762:      	bl	0x1174 <stop>           @ imm = #0xa0e
     766:      	bmi	0x712 <zs_alloc+0x9a>   @ imm = #-0x58

00000768 <zs_free>:
     768:      	push	{r4, r6, r7, lr}
     76a:      	add	r7, sp, #0x8
     76c:      	movw	lr, #0x88
     770:      	movw	r12, #0x90
     774:      	movt	lr, #0x2001
     778:      	movt	r12, #0x2001
     77c:      	ldr	r1, [r0, #-8]
     780:      	ldr.w	r3, [lr]
     784:      	ldrd	r2, r4, [r12]
     788:      	subs	r3, r3, r1
     78a:      	subs	r2, #0x1
     78c:      	str.w	r3, [lr]
     790:      	sbc	r3, r4, #0x0
     794:      	lsrs	r4, r1, #0x3
     796:      	cmp	r4, #0x20
     798:      	strd	r2, r3, [r12]
     79c:      	it	hi
     79e:      	pophi	{r4, r6, r7, pc}
     7a0:      	mvn	r2, #0x3
     7a4:      	and.w	r1, r2, r1, lsr #1
     7a8:      	movw	r2, #0x0
     7ac:      	movt	r2, #0x2000
     7b0:      	ldr	r3, [r2, r1]
     7b2:      	str	r3, [r0]
     7b4:      	str	r0, [r2, r1]
     7b6:      	pop	{r4, r6, r7, pc}

000007b8 <zs_str_concat>:
     7b8:      	push	{r4, r5, r6, r7, lr}
     7ba:      	add	r7, sp, #0xc
     7bc:      	push.w	{r8, r9, r10}
     7c0:      	mov	lr, r0
     7c2:      	ldrd	r0, r3, [r0, #8]
     7c6:      	ldrd	r2, r6, [r1, #8]
     7ca:      	adds.w	r9, r2, r0
     7ce:      	add.w	r0, r9, #0x18
     7d2:      	lsr.w	r4, r0, #0x3
     7d6:      	adc.w	r12, r6, r3
     7da:      	cmp	r4, #0x20
     7dc:      	bhi	0x7fa <zs_str_concat+0x42> @ imm = #0x1a
     7de:      	movw	r5, #0x0
     7e2:      	movt	r5, #0x2000
     7e6:      	ldr.w	r6, [r5, r4, lsl #2]
     7ea:      	cbz	r6, 0x7fa <zs_str_concat+0x42> @ imm = #0xc
     7ec:      	mov	r10, r6
     7ee:      	ldr	r6, [r6]
     7f0:      	ldr	r0, [r10, #-8]!
     7f4:      	str.w	r6, [r5, r4, lsl #2]
     7f8:      	b	0x834 <zs_str_concat+0x7c> @ imm = #0x38
     7fa:      	movw	r8, #0x84
     7fe:      	movt	r8, #0x2000
     802:      	ldr.w	r4, [r8]
     806:      	bic	r0, r0, #0x7
     80a:      	adds	r6, r0, r4
     80c:      	movw	r3, #0xfff9
     810:      	subs	r3, r6, r3
     812:      	cmn.w	r3, #0x10001
     816:      	blo.w	0x996 <zs_str_concat+0x1de> @ imm = #0x17c
     81a:      	movw	r5, #0x88
     81e:      	movt	r5, #0x2000
     822:      	add.w	r10, r5, r4
     826:      	adds	r6, #0x8
     828:      	str	r0, [r5, r4]
     82a:      	movs	r4, #0x0
     82c:      	str.w	r6, [r8]
     830:      	str.w	r4, [r10, #0x4]
     834:      	movw	r5, #0x88
     838:      	movt	r5, #0x2001
     83c:      	movw	r4, #0x8c
     840:      	ldr	r6, [r5]
     842:      	movt	r4, #0x2001
     846:      	ldr	r2, [r4]
     848:      	add	r0, r6
     84a:      	cmp	r0, r2
     84c:      	str	r0, [r5]
     84e:      	it	hi
     850:      	strhi	r0, [r4]
     852:      	movw	r0, #0x90
     856:      	movt	r0, #0x2001
     85a:      	ldrd	r2, r4, [r0]
     85e:      	movw	r5, #0x98
     862:      	movt	r5, #0x2001
     866:      	adds	r2, #0x1
     868:      	ldrd	r6, r3, [r5]
     86c:      	adc	r4, r4, #0x0
     870:      	strd	r2, r4, [r0]
     874:      	adds	r0, r6, #0x1
     876:      	adc	r2, r3, #0x0
     87a:      	strd	r0, r2, [r5]
     87e:      	movs	r2, #0x1
     880:      	mov	r0, r10
     882:      	str	r2, [r0, #8]!
     886:      	movs	r5, #0x0
     888:      	adds	r2, r0, #0x4
     88a:      	stm.w	r2, {r5, r9, r12}
     88e:      	add.w	r12, r0, #0x10
     892:      	strb.w	r5, [r12, r9]
     896:      	ldr.w	r4, [lr, #0x8]
     89a:      	cmp	r4, #0x0
     89c:      	beq	0x920 <zs_str_concat+0x168> @ imm = #0x80
     89e:      	ands	r2, r4, #0x3
     8a2:      	beq	0x8c0 <zs_str_concat+0x108> @ imm = #0x1a
     8a4:      	ldrb.w	r3, [lr, #0x10]
     8a8:      	cmp	r2, #0x1
     8aa:      	strb.w	r3, [r10, #0x18]
     8ae:      	bne	0x8ce <zs_str_concat+0x116> @ imm = #0x1c
     8b0:      	subs	r2, r4, #0x1
     8b2:      	add.w	r5, lr, #0x11
     8b6:      	add.w	r6, r10, #0x19
     8ba:      	cmp	r4, #0x4
     8bc:      	bhs	0x900 <zs_str_concat+0x148> @ imm = #0x40
     8be:      	b	0x91c <zs_str_concat+0x164> @ imm = #0x5a
     8c0:      	add.w	r5, lr, #0x10
     8c4:      	mov	r6, r12
     8c6:      	mov	r2, r4
     8c8:      	cmp	r4, #0x4
     8ca:      	bhs	0x900 <zs_str_concat+0x148> @ imm = #0x32
     8cc:      	b	0x91c <zs_str_concat+0x164> @ imm = #0x4c
     8ce:      	ldrb.w	r3, [lr, #0x11]
     8d2:      	cmp	r2, #0x2
     8d4:      	strb.w	r3, [r10, #0x19]
     8d8:      	bne	0x8ea <zs_str_concat+0x132> @ imm = #0xe
     8da:      	subs	r2, r4, #0x2
     8dc:      	add.w	r5, lr, #0x12
     8e0:      	add.w	r6, r10, #0x1a
     8e4:      	cmp	r4, #0x4
     8e6:      	bhs	0x900 <zs_str_concat+0x148> @ imm = #0x16
     8e8:      	b	0x91c <zs_str_concat+0x164> @ imm = #0x30
     8ea:      	ldrb.w	r3, [lr, #0x12]
     8ee:      	subs	r2, r4, #0x3
     8f0:      	add.w	r5, lr, #0x13
     8f4:      	add.w	r6, r10, #0x1b
     8f8:      	strb.w	r3, [r10, #0x1a]
     8fc:      	cmp	r4, #0x4
     8fe:      	blo	0x91c <zs_str_concat+0x164> @ imm = #0x1a
     900:      	subs	r3, r5, #0x4
     902:      	subs	r4, r6, #0x4
     904:      	ldrb	r5, [r3, #4]!
     908:      	subs	r2, #0x4
     90a:      	strb	r5, [r4, #4]!
     90e:      	ldrb	r5, [r3, #0x1]
     910:      	strb	r5, [r4, #0x1]
     912:      	ldrb	r5, [r3, #0x2]
     914:      	strb	r5, [r4, #0x2]
     916:      	ldrb	r5, [r3, #0x3]
     918:      	strb	r5, [r4, #0x3]
     91a:      	bne	0x904 <zs_str_concat+0x14c> @ imm = #-0x1a
     91c:      	ldr.w	r5, [lr, #0x8]
     920:      	ldr	r3, [r1, #0x8]
     922:      	cbz	r3, 0x990 <zs_str_concat+0x1d8> @ imm = #0x6a
     924:      	ands	r2, r3, #0x3
     928:      	add.w	r6, r12, r5
     92c:      	beq	0x946 <zs_str_concat+0x18e> @ imm = #0x16
     92e:      	ldrb	r5, [r1, #0x10]
     930:      	mov	r4, r6
     932:      	cmp	r2, #0x1
     934:      	strb	r5, [r4], #1
     938:      	bne	0x950 <zs_str_concat+0x198> @ imm = #0x14
     93a:      	subs	r2, r3, #0x1
     93c:      	adds	r1, #0x11
     93e:      	mov	r6, r4
     940:      	cmp	r3, #0x4
     942:      	bhs	0x972 <zs_str_concat+0x1ba> @ imm = #0x2c
     944:      	b	0x990 <zs_str_concat+0x1d8> @ imm = #0x48
     946:      	adds	r1, #0x10
     948:      	mov	r2, r3
     94a:      	cmp	r3, #0x4
     94c:      	bhs	0x972 <zs_str_concat+0x1ba> @ imm = #0x22
     94e:      	b	0x990 <zs_str_concat+0x1d8> @ imm = #0x3e
     950:      	ldrb	r5, [r1, #0x11]
     952:      	cmp	r2, #0x2
     954:      	strb	r5, [r6, #0x1]
     956:      	bne	0x964 <zs_str_concat+0x1ac> @ imm = #0xa
     958:      	subs	r2, r3, #0x2
     95a:      	adds	r1, #0x12
     95c:      	adds	r6, #0x2
     95e:      	cmp	r3, #0x4
     960:      	bhs	0x972 <zs_str_concat+0x1ba> @ imm = #0xe
     962:      	b	0x990 <zs_str_concat+0x1d8> @ imm = #0x2a
     964:      	ldrb	r5, [r1, #0x12]
     966:      	subs	r2, r3, #0x3
     968:      	adds	r1, #0x13
     96a:      	strb	r5, [r6, #0x2]
     96c:      	adds	r6, #0x3
     96e:      	cmp	r3, #0x4
     970:      	blo	0x990 <zs_str_concat+0x1d8> @ imm = #0x1c
     972:      	subs	r1, #0x4
     974:      	subs	r3, r6, #0x4
     976:      	nop
     978:      	ldrb	r6, [r1, #4]!
     97c:      	subs	r2, #0x4
     97e:      	strb	r6, [r3, #4]!
     982:      	ldrb	r6, [r1, #0x1]
     984:      	strb	r6, [r3, #0x1]
     986:      	ldrb	r6, [r1, #0x2]
     988:      	strb	r6, [r3, #0x2]
     98a:      	ldrb	r6, [r1, #0x3]
     98c:      	strb	r6, [r3, #0x3]
     98e:      	bne	0x978 <zs_str_concat+0x1c0> @ imm = #-0x1a
     990:      	pop.w	{r8, r9, r10}
     994:      	pop	{r4, r5, r6, r7, pc}
     996:      	movw	r0, #0x2008
     99a:      	movt	r0, #0x0
     99e:      	bl	0x73c <zs_panic_c>      @ imm = #-0x266
     9a2:      	bmi	0x94e <zs_str_concat+0x196> @ imm = #-0x58

000009a4 <zs_str_of_u64>:
     9a4:      	push	{r4, r5, r6, r7, lr}
     9a6:      	add	r7, sp, #0xc
     9a8:      	push.w	{r8, r9, r10, r11}
     9ac:      	sub	sp, #0x34
     9ae:      	movw	r9, #0xcccd
     9b2:      	mov	r5, r1
     9b4:      	mov	r6, r0
     9b6:      	mov.w	r10, #0x1
     9ba:      	movt	r9, #0xcccc
     9be:      	add.w	r8, sp, #0x1c
     9c2:      	nop
     9c4:      	lsrs	r0, r6, #0x1
     9c6:      	orr.w	r0, r0, r5, lsl #31
     9ca:      	adds.w	r1, r0, r5, lsr #1
     9ce:      	adc	r1, r1, #0x0
     9d2:      	umull	r2, r3, r1, r9
     9d6:      	bic	r2, r3, #0x3
     9da:      	add.w	r2, r2, r3, lsr #2
     9de:      	subs	r1, r1, r2
     9e0:      	subs	r1, r0, r1
     9e2:      	umull	r0, r2, r1, r9
     9e6:      	add.w	r4, r0, r0, lsl #2
     9ea:      	lsr.w	r3, r5, #0x1
     9ee:      	sub.w	r4, r6, r4, lsl #1
     9f2:      	sbc	r3, r3, #0x0
     9f6:      	orr	r12, r4, #0x30
     9fa:      	subs.w	r4, r6, #0xa
     9fe:      	add.w	r11, r8, r10
     a02:      	sbcs	r4, r5, #0x0
     a06:      	strb	r12, [r11, #-1]
     a0a:      	blo	0xafa <zs_str_of_u64+0x156> @ imm = #0xec
     a0c:      	mov.w	r4, #0xcccccccc
     a10:      	mla	r1, r1, r4, r2
     a14:      	lsrs	r2, r0, #0x1
     a16:      	mla	r1, r3, r9, r1
     a1a:      	and	r0, r0, #0x1
     a1e:      	orr.w	r2, r2, r1, lsl #31
     a22:      	adds.w	r1, r2, r1, lsr #1
     a26:      	adc	r1, r1, #0x0
     a2a:      	umull	r2, r3, r1, r9
     a2e:      	bic	r2, r3, #0x3
     a32:      	add.w	r2, r2, r3, lsr #2
     a36:      	subs	r1, r1, r2
     a38:      	orr.w	r0, r0, r1, lsl #1
     a3c:      	subs.w	r1, r6, #0x64
     a40:      	orr	r0, r0, #0x30
     a44:      	sbcs	r1, r5, #0x0
     a48:      	strb.w	r0, [r8, r10]
     a4c:      	blo	0xb02 <zs_str_of_u64+0x15e> @ imm = #0xb2
     a4e:      	mov	r0, r6
     a50:      	mov	r1, r5
     a52:      	movs	r2, #0x64
     a54:      	movs	r3, #0x0
     a56:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf62
     a5a:      	lsrs	r2, r0, #0x1
     a5c:      	orr.w	r2, r2, r1, lsl #31
     a60:      	adds.w	r1, r2, r1, lsr #1
     a64:      	adc	r1, r1, #0x0
     a68:      	umull	r2, r3, r1, r9
     a6c:      	bic	r2, r3, #0x3
     a70:      	add.w	r2, r2, r3, lsr #2
     a74:      	subs	r1, r1, r2
     a76:      	and	r0, r0, #0x1
     a7a:      	orr.w	r0, r0, r1, lsl #1
     a7e:      	subs.w	r1, r6, #0x3e8
     a82:      	orr	r0, r0, #0x30
     a86:      	sbcs	r1, r5, #0x0
     a8a:      	strb.w	r0, [r11, #0x1]
     a8e:      	blo	0xb0a <zs_str_of_u64+0x166> @ imm = #0x78
     a90:      	mov	r0, r6
     a92:      	mov	r1, r5
     a94:      	mov.w	r2, #0x3e8
     a98:      	movs	r3, #0x0
     a9a:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf1e
     a9e:      	lsrs	r2, r0, #0x1
     aa0:      	orr.w	r2, r2, r1, lsl #31
     aa4:      	adds.w	r1, r2, r1, lsr #1
     aa8:      	adc	r1, r1, #0x0
     aac:      	umull	r2, r3, r1, r9
     ab0:      	bic	r2, r3, #0x3
     ab4:      	add.w	r2, r2, r3, lsr #2
     ab8:      	subs	r1, r1, r2
     aba:      	and	r0, r0, #0x1
     abe:      	orr.w	r0, r0, r1, lsl #1
     ac2:      	orr	r0, r0, #0x30
     ac6:      	strb.w	r0, [r11, #0x2]
     aca:      	mov	r0, r6
     acc:      	mov	r1, r5
     ace:      	movw	r2, #0x2710
     ad2:      	movs	r3, #0x0
     ad4:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xee4
     ad8:      	movw	r2, #0x270f
     adc:      	subs	r2, r2, r6
     ade:      	mov.w	r2, #0x0
     ae2:      	sbcs	r2, r5
     ae4:      	add.w	r10, r10, #0x4
     ae8:      	mov	r6, r0
     aea:      	mov	r5, r1
     aec:      	blo.w	0x9c4 <zs_str_of_u64+0x20> @ imm = #-0x12c
     af0:      	sub.w	r1, r10, #0x1
     af4:      	sub.w	r12, r10, #0x2
     af8:      	b	0xb12 <zs_str_of_u64+0x16e> @ imm = #0x16
     afa:      	sub.w	r12, r10, #0x1
     afe:      	mov	r1, r10
     b00:      	b	0xb14 <zs_str_of_u64+0x170> @ imm = #0x10
     b02:      	add.w	r1, r10, #0x1
     b06:      	mov	r12, r10
     b08:      	b	0xb12 <zs_str_of_u64+0x16e> @ imm = #0x6
     b0a:      	add.w	r1, r10, #0x2
     b0e:      	add.w	r12, r10, #0x1
     b12:      	mov	r10, r1
     b14:      	and	lr, r1, #0x3
     b18:      	lsrs	r3, r1, #0x2
     b1a:      	mov.w	r1, #0x0
     b1e:      	beq	0xb52 <zs_str_of_u64+0x1ae> @ imm = #0x30
     b20:      	add	r6, sp, #0x4
     b22:      	add.w	r5, r12, r8
     b26:      	sub.w	r9, r1, r3, lsl #2
     b2a:      	subs	r6, #0x3
     b2c:      	subs	r5, #0x1
     b2e:      	nop
     b30:      	adds	r4, r5, r1
     b32:      	ldrb	r3, [r5, r1]
     b34:      	ldrb	r0, [r4, #-2]
     b38:      	ldrb	r2, [r4, #-1]
     b3c:      	ldrb	r4, [r4, #0x1]
     b3e:      	subs	r1, #0x4
     b40:      	strb	r3, [r6, #4]!
     b44:      	cmp	r9, r1
     b46:      	strb	r4, [r6, #-1]
     b4a:      	strb	r2, [r6, #0x1]
     b4c:      	strb	r0, [r6, #0x2]
     b4e:      	bne	0xb30 <zs_str_of_u64+0x18c> @ imm = #-0x22
     b50:      	rsbs	r1, r1, #0
     b52:      	cmp.w	lr, #0x0
     b56:      	beq	0xb88 <zs_str_of_u64+0x1e4> @ imm = #0x2e
     b58:      	sub.w	r0, r12, r1
     b5c:      	ldrb.w	r0, [r8, r0]
     b60:      	add	r3, sp, #0x4
     b62:      	cmp.w	lr, #0x1
     b66:      	strb	r0, [r3, r1]
     b68:      	beq	0xb88 <zs_str_of_u64+0x1e4> @ imm = #0x1c
     b6a:      	adds	r0, r1, #0x1
     b6c:      	sub.w	r2, r12, r0
     b70:      	ldrb.w	r2, [r8, r2]
     b74:      	cmp.w	lr, #0x2
     b78:      	strb	r2, [r3, r0]
     b7a:      	beq	0xb88 <zs_str_of_u64+0x1e4> @ imm = #0xa
     b7c:      	adds	r0, r1, #0x2
     b7e:      	sub.w	r1, r12, r0
     b82:      	ldrb.w	r1, [r8, r1]
     b86:      	strb	r1, [r3, r0]
     b88:      	add	r0, sp, #0x4
     b8a:      	mov	r2, r10
     b8c:      	movs	r3, #0x0
     b8e:      	bl	0xb9c <str_of>          @ imm = #0xa
     b92:      	add	sp, #0x34
     b94:      	pop.w	{r8, r9, r10, r11}
     b98:      	pop	{r4, r5, r6, r7, pc}
     b9a:      	bmi	0xb46 <zs_str_of_u64+0x1a2> @ imm = #-0x58

00000b9c <str_of>:
     b9c:      	push	{r4, r5, r6, r7, lr}
     b9e:      	add	r7, sp, #0xc
     ba0:      	str	r8, [sp, #-4]!
     ba4:      	add.w	r12, r2, #0x18
     ba8:      	lsr.w	r1, r12, #0x3
     bac:      	cmp	r1, #0x20
     bae:      	bhi	0xbcc <str_of+0x30>     @ imm = #0x1a
     bb0:      	movw	r4, #0x0
     bb4:      	movt	r4, #0x2000
     bb8:      	ldr.w	r5, [r4, r1, lsl #2]
     bbc:      	cbz	r5, 0xbcc <str_of+0x30> @ imm = #0xc
     bbe:      	mov	r12, r5
     bc0:      	ldr	r5, [r5]
     bc2:      	ldr	lr, [r12, #-8]!
     bc6:      	str.w	r5, [r4, r1, lsl #2]
     bca:      	b	0xc04 <str_of+0x68>     @ imm = #0x36
     bcc:      	movw	r6, #0x84
     bd0:      	movt	r6, #0x2000
     bd4:      	ldr	r1, [r6]
     bd6:      	bic	lr, r12, #0x7
     bda:      	add.w	r5, lr, r1
     bde:      	movw	r4, #0xfff9
     be2:      	subs	r4, r5, r4
     be4:      	cmn.w	r4, #0x10001
     be8:      	blo	0xce4 <str_of+0x148>    @ imm = #0xf8
     bea:      	movw	r4, #0x88
     bee:      	movt	r4, #0x2000
     bf2:      	add.w	r12, r4, r1
     bf6:      	adds	r5, #0x8
     bf8:      	str.w	lr, [r4, r1]
     bfc:      	movs	r1, #0x0
     bfe:      	str	r5, [r6]
     c00:      	str.w	r1, [r12, #0x4]
     c04:      	movw	r4, #0x88
     c08:      	movt	r4, #0x2001
     c0c:      	movw	r1, #0x8c
     c10:      	ldr	r5, [r4]
     c12:      	movt	r1, #0x2001
     c16:      	ldr	r6, [r1]
     c18:      	add	r5, lr
     c1a:      	movw	lr, #0x90
     c1e:      	cmp	r5, r6
     c20:      	str	r5, [r4]
     c22:      	it	hi
     c24:      	strhi	r5, [r1]
     c26:      	movt	lr, #0x2001
     c2a:      	movw	r8, #0x98
     c2e:      	ldrd	r6, r5, [lr]
     c32:      	movt	r8, #0x2001
     c36:      	ldrd	r1, r4, [r8]
     c3a:      	adds	r6, #0x1
     c3c:      	adc	r5, r5, #0x0
     c40:      	adds	r1, #0x1
     c42:      	strd	r6, r5, [lr]
     c46:      	adc	r6, r4, #0x0
     c4a:      	strd	r1, r6, [r8]
     c4e:      	movs	r6, #0x1
     c50:      	mov	r1, r12
     c52:      	str	r6, [r1, #8]!
     c56:      	movs	r4, #0x0
     c58:      	add.w	lr, r1, #0x10
     c5c:      	strd	r4, r2, [r1, #4]
     c60:      	str	r3, [r1, #0xc]
     c62:      	strb.w	r4, [lr, r2]
     c66:      	cbz	r2, 0xcdc <str_of+0x140> @ imm = #0x72
     c68:      	ands	r3, r2, #0x3
     c6c:      	beq	0xc8a <str_of+0xee>     @ imm = #0x1a
     c6e:      	mov	r4, r0
     c70:      	ldrb	r6, [r4], #1
     c74:      	cmp	r3, #0x1
     c76:      	strb.w	r6, [r12, #0x18]
     c7a:      	bne	0xc92 <str_of+0xf6>     @ imm = #0x14
     c7c:      	subs	r3, r2, #0x1
     c7e:      	add.w	lr, r12, #0x19
     c82:      	mov	r0, r4
     c84:      	cmp	r2, #0x4
     c86:      	bhs	0xcbc <str_of+0x120>    @ imm = #0x32
     c88:      	b	0xcdc <str_of+0x140>    @ imm = #0x50
     c8a:      	mov	r3, r2
     c8c:      	cmp	r2, #0x4
     c8e:      	bhs	0xcbc <str_of+0x120>    @ imm = #0x2a
     c90:      	b	0xcdc <str_of+0x140>    @ imm = #0x48
     c92:      	ldrb	r6, [r0, #0x1]
     c94:      	cmp	r3, #0x2
     c96:      	strb.w	r6, [r12, #0x19]
     c9a:      	bne	0xcaa <str_of+0x10e>    @ imm = #0xc
     c9c:      	subs	r3, r2, #0x2
     c9e:      	adds	r0, #0x2
     ca0:      	add.w	lr, r12, #0x1a
     ca4:      	cmp	r2, #0x4
     ca6:      	bhs	0xcbc <str_of+0x120>    @ imm = #0x12
     ca8:      	b	0xcdc <str_of+0x140>    @ imm = #0x30
     caa:      	ldrb	r4, [r0, #0x2]
     cac:      	subs	r3, r2, #0x3
     cae:      	adds	r0, #0x3
     cb0:      	add.w	lr, r12, #0x1b
     cb4:      	strb.w	r4, [r12, #0x1a]
     cb8:      	cmp	r2, #0x4
     cba:      	blo	0xcdc <str_of+0x140>    @ imm = #0x1e
     cbc:      	subs	r0, #0x4
     cbe:      	sub.w	r2, lr, #0x4
     cc2:      	nop
     cc4:      	ldrb	r6, [r0, #4]!
     cc8:      	subs	r3, #0x4
     cca:      	strb	r6, [r2, #4]!
     cce:      	ldrb	r6, [r0, #0x1]
     cd0:      	strb	r6, [r2, #0x1]
     cd2:      	ldrb	r6, [r0, #0x2]
     cd4:      	strb	r6, [r2, #0x2]
     cd6:      	ldrb	r6, [r0, #0x3]
     cd8:      	strb	r6, [r2, #0x3]
     cda:      	bne	0xcc4 <str_of+0x128>    @ imm = #-0x1a
     cdc:      	mov	r0, r1
     cde:      	ldr	r8, [sp], #4
     ce2:      	pop	{r4, r5, r6, r7, pc}
     ce4:      	movw	r0, #0x2008
     ce8:      	movt	r0, #0x0
     cec:      	bl	0x73c <zs_panic_c>      @ imm = #-0x5b4

00000cf0 <zs_str_of_i64>:
     cf0:      	push	{r4, r5, r6, r7, lr}
     cf2:      	add	r7, sp, #0xc
     cf4:      	push.w	{r8, r9, r10, r11}
     cf8:      	sub	sp, #0x3c
     cfa:      	cmp.w	r1, #0xffffffff
     cfe:      	add	r2, sp, #0xc
     d00:      	ble	0xd08 <zs_str_of_i64+0x18> @ imm = #0x4
     d02:      	str	r2, [sp, #0x8]
     d04:      	movs	r2, #0x0
     d06:      	b	0xd14 <zs_str_of_i64+0x24> @ imm = #0xa
     d08:      	adds	r2, #0x1
     d0a:      	str	r2, [sp, #0x8]
     d0c:      	movs	r2, #0x2d
     d0e:      	strb.w	r2, [sp, #0xc]
     d12:      	movs	r2, #0x1
     d14:      	eor.w	r0, r0, r1, asr #31
     d18:      	str	r2, [sp, #0x4]
     d1a:      	eor.w	r2, r1, r1, asr #31
     d1e:      	subs.w	r4, r0, r1, asr #31
     d22:      	movw	r8, #0xcccd
     d26:      	sbc.w	r5, r2, r1, asr #31
     d2a:      	mov.w	r9, #0x1
     d2e:      	movt	r8, #0xcccc
     d32:      	add.w	r10, sp, #0x24
     d36:      	nop
     d38:      	lsrs	r0, r4, #0x1
     d3a:      	orr.w	r0, r0, r5, lsl #31
     d3e:      	adds.w	r1, r0, r5, lsr #1
     d42:      	adc	r1, r1, #0x0
     d46:      	umull	r2, r3, r1, r8
     d4a:      	bic	r2, r3, #0x3
     d4e:      	add.w	r2, r2, r3, lsr #2
     d52:      	subs	r1, r1, r2
     d54:      	subs	r1, r0, r1
     d56:      	umull	r0, r2, r1, r8
     d5a:      	add.w	r6, r0, r0, lsl #2
     d5e:      	lsr.w	r3, r5, #0x1
     d62:      	sub.w	r6, r4, r6, lsl #1
     d66:      	sbc	r3, r3, #0x0
     d6a:      	orr	r12, r6, #0x30
     d6e:      	subs.w	r6, r4, #0xa
     d72:      	add.w	r11, r10, r9
     d76:      	sbcs	r6, r5, #0x0
     d7a:      	strb	r12, [r11, #-1]
     d7e:      	blo	0xe6e <zs_str_of_i64+0x17e> @ imm = #0xec
     d80:      	mov.w	r6, #0xcccccccc
     d84:      	mla	r1, r1, r6, r2
     d88:      	lsrs	r2, r0, #0x1
     d8a:      	mla	r1, r3, r8, r1
     d8e:      	and	r0, r0, #0x1
     d92:      	orr.w	r2, r2, r1, lsl #31
     d96:      	adds.w	r1, r2, r1, lsr #1
     d9a:      	adc	r1, r1, #0x0
     d9e:      	umull	r2, r3, r1, r8
     da2:      	bic	r2, r3, #0x3
     da6:      	add.w	r2, r2, r3, lsr #2
     daa:      	subs	r1, r1, r2
     dac:      	orr.w	r0, r0, r1, lsl #1
     db0:      	subs.w	r1, r4, #0x64
     db4:      	orr	r0, r0, #0x30
     db8:      	sbcs	r1, r5, #0x0
     dbc:      	strb.w	r0, [r10, r9]
     dc0:      	blo	0xe76 <zs_str_of_i64+0x186> @ imm = #0xb2
     dc2:      	mov	r0, r4
     dc4:      	mov	r1, r5
     dc6:      	movs	r2, #0x64
     dc8:      	movs	r3, #0x0
     dca:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xbee
     dce:      	lsrs	r2, r0, #0x1
     dd0:      	orr.w	r2, r2, r1, lsl #31
     dd4:      	adds.w	r1, r2, r1, lsr #1
     dd8:      	adc	r1, r1, #0x0
     ddc:      	umull	r2, r3, r1, r8
     de0:      	bic	r2, r3, #0x3
     de4:      	add.w	r2, r2, r3, lsr #2
     de8:      	subs	r1, r1, r2
     dea:      	and	r0, r0, #0x1
     dee:      	orr.w	r0, r0, r1, lsl #1
     df2:      	subs.w	r1, r4, #0x3e8
     df6:      	orr	r0, r0, #0x30
     dfa:      	sbcs	r1, r5, #0x0
     dfe:      	strb.w	r0, [r11, #0x1]
     e02:      	blo	0xe7e <zs_str_of_i64+0x18e> @ imm = #0x78
     e04:      	mov	r0, r4
     e06:      	mov	r1, r5
     e08:      	mov.w	r2, #0x3e8
     e0c:      	movs	r3, #0x0
     e0e:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xbaa
     e12:      	lsrs	r2, r0, #0x1
     e14:      	orr.w	r2, r2, r1, lsl #31
     e18:      	adds.w	r1, r2, r1, lsr #1
     e1c:      	adc	r1, r1, #0x0
     e20:      	umull	r2, r3, r1, r8
     e24:      	bic	r2, r3, #0x3
     e28:      	add.w	r2, r2, r3, lsr #2
     e2c:      	subs	r1, r1, r2
     e2e:      	and	r0, r0, #0x1
     e32:      	orr.w	r0, r0, r1, lsl #1
     e36:      	orr	r0, r0, #0x30
     e3a:      	strb.w	r0, [r11, #0x2]
     e3e:      	mov	r0, r4
     e40:      	mov	r1, r5
     e42:      	movw	r2, #0x2710
     e46:      	movs	r3, #0x0
     e48:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xb70
     e4c:      	movw	r2, #0x270f
     e50:      	subs	r2, r2, r4
     e52:      	mov.w	r2, #0x0
     e56:      	sbcs	r2, r5
     e58:      	add.w	r9, r9, #0x4
     e5c:      	mov	r4, r0
     e5e:      	mov	r5, r1
     e60:      	blo.w	0xd38 <zs_str_of_i64+0x48> @ imm = #-0x12c
     e64:      	sub.w	r1, r9, #0x1
     e68:      	sub.w	r12, r9, #0x2
     e6c:      	b	0xe86 <zs_str_of_i64+0x196> @ imm = #0x16
     e6e:      	sub.w	r12, r9, #0x1
     e72:      	mov	r1, r9
     e74:      	b	0xe88 <zs_str_of_i64+0x198> @ imm = #0x10
     e76:      	add.w	r1, r9, #0x1
     e7a:      	mov	r12, r9
     e7c:      	b	0xe86 <zs_str_of_i64+0x196> @ imm = #0x6
     e7e:      	add.w	r1, r9, #0x2
     e82:      	add.w	r12, r9, #0x1
     e86:      	mov	r9, r1
     e88:      	ldr.w	r8, [sp, #0x8]
     e8c:      	and	lr, r1, #0x3
     e90:      	lsrs	r3, r1, #0x2
     e92:      	mov.w	r1, #0x0
     e96:      	beq	0xec8 <zs_str_of_i64+0x1d8> @ imm = #0x2e
     e98:      	add.w	r6, r12, r10
     e9c:      	sub.w	r3, r1, r3, lsl #2
     ea0:      	sub.w	r5, r8, #0x3
     ea4:      	subs	r4, r6, #0x1
     ea6:      	nop
     ea8:      	adds	r6, r4, r1
     eaa:      	ldrb	r0, [r6, #0x1]
     eac:      	ldrb	r2, [r6, #-1]
     eb0:      	strb	r0, [r5, #0x3]
     eb2:      	ldrb	r0, [r4, r1]
     eb4:      	subs	r1, #0x4
     eb6:      	strb	r0, [r5, #4]!
     eba:      	ldrb	r0, [r6, #-2]
     ebe:      	cmp	r3, r1
     ec0:      	strb	r2, [r5, #0x1]
     ec2:      	strb	r0, [r5, #0x2]
     ec4:      	bne	0xea8 <zs_str_of_i64+0x1b8> @ imm = #-0x20
     ec6:      	rsbs	r1, r1, #0
     ec8:      	cmp.w	lr, #0x0
     ecc:      	beq	0xf02 <zs_str_of_i64+0x212> @ imm = #0x32
     ece:      	sub.w	r0, r12, r1
     ed2:      	ldrb.w	r0, [r10, r0]
     ed6:      	cmp.w	lr, #0x1
     eda:      	strb.w	r0, [r8, r1]
     ede:      	beq	0xf02 <zs_str_of_i64+0x212> @ imm = #0x20
     ee0:      	adds	r0, r1, #0x1
     ee2:      	sub.w	r2, r12, r0
     ee6:      	ldrb.w	r2, [r10, r2]
     eea:      	cmp.w	lr, #0x2
     eee:      	strb.w	r2, [r8, r0]
     ef2:      	beq	0xf02 <zs_str_of_i64+0x212> @ imm = #0xc
     ef4:      	adds	r0, r1, #0x2
     ef6:      	sub.w	r1, r12, r0
     efa:      	ldrb.w	r1, [r10, r1]
     efe:      	strb.w	r1, [r8, r0]
     f02:      	ldr	r0, [sp, #0x4]
     f04:      	movs	r3, #0x0
     f06:      	add.w	r2, r9, r0
     f0a:      	add	r0, sp, #0xc
     f0c:      	bl	0xb9c <str_of>          @ imm = #-0x374
     f10:      	add	sp, #0x3c
     f12:      	pop.w	{r8, r9, r10, r11}
     f16:      	pop	{r4, r5, r6, r7, pc}

00000f18 <zs_println>:
     f18:      	push	{r4, r5, r6, r7, lr}
     f1a:      	add	r7, sp, #0xc
     f1c:      	push.w	{r8, r9, r10, r11}
     f20:      	sub	sp, #0x44
     f22:      	ldrd	r11, r2, [r0, #8]
     f26:      	subs.w	r1, r11, #0x1
     f2a:      	sbcs	r1, r2, #0x0
     f2e:      	blt	0x101a <zs_println+0x102> @ imm = #0xe8
     f30:      	sub.w	r1, r7, #0x5d
     f34:      	add.w	lr, r0, #0x10
     f38:      	add.w	r9, r1, #0x1
     f3c:      	movs	r3, #0x0
     f3e:      	b	0xf5c <zs_println+0x44> @ imm = #0x1a
     f40:      	strb.w	r3, [r1, r8]
     f44:      	movs	r0, #0x4
     f46:      	subs.w	r11, r11, r8
     f4a:      	bkpt	#0xab
     f4c:      	sbc	r2, r2, #0x0
     f50:      	rsbs.w	r0, r11, #0x0
     f54:      	sbcs.w	r0, r3, r2
     f58:      	add	lr, r8
     f5a:      	bge	0x101a <zs_println+0x102> @ imm = #0xbc
     f5c:      	cmp.w	r11, #0x40
     f60:      	mov.w	r8, #0x40
     f64:      	it	lo
     f66:      	movlo	r8, r11
     f68:      	cmp	r2, #0x0
     f6a:      	mov.w	r0, #0x40
     f6e:      	it	ne
     f70:      	movne	r8, r0
     f72:      	lsrs.w	r0, r8, #0x2
     f76:      	beq	0xfdc <zs_println+0xc4> @ imm = #0x62
     f78:      	mov	r1, r2
     f7a:      	sub.w	r10, r3, r0, lsl #2
     f7e:      	add.w	r5, lr, #0x1
     f82:      	mvn	r4, #0x3
     f86:      	nop
     f88:      	adds	r2, r5, r4
     f8a:      	ldrb	r6, [r2, #0x3]
     f8c:      	ldrb	r3, [r2, #0x4]
     f8e:      	ldrb	r0, [r2, #0x5]
     f90:      	cmp	r6, #0x0
     f92:      	ldrb	r2, [r2, #0x6]
     f94:      	it	eq
     f96:      	moveq	r6, #0x20
     f98:      	add.w	r12, r9, r4
     f9c:      	cmp	r3, #0x0
     f9e:      	strb.w	r6, [r12, #0x3]
     fa2:      	it	eq
     fa4:      	moveq	r3, #0x20
     fa6:      	strb.w	r3, [r12, #0x4]
     faa:      	cmp	r0, #0x0
     fac:      	it	eq
     fae:      	moveq	r0, #0x20
     fb0:      	adds	r4, #0x4
     fb2:      	strb.w	r0, [r12, #0x5]
     fb6:      	cmp	r2, #0x0
     fb8:      	add.w	r0, r10, r4
     fbc:      	it	eq
     fbe:      	moveq	r2, #0x20
     fc0:      	adds	r0, #0x4
     fc2:      	strb.w	r2, [r12, #0x6]
     fc6:      	bne	0xf88 <zs_println+0x70> @ imm = #-0x42
     fc8:      	adds	r0, r4, #0x4
     fca:      	mov	r2, r1
     fcc:      	sub.w	r1, r7, #0x5d
     fd0:      	movs	r3, #0x0
     fd2:      	ands	r4, r8, #0x3
     fd6:      	bne	0xfe4 <zs_println+0xcc> @ imm = #0xa
     fd8:      	b	0xf40 <zs_println+0x28> @ imm = #-0x9c
     fda:      	nop
     fdc:      	movs	r0, #0x0
     fde:      	ands	r4, r8, #0x3
     fe2:      	beq	0xf40 <zs_println+0x28> @ imm = #-0xa6
     fe4:      	ldrb.w	r5, [lr, r0]
     fe8:      	cmp	r5, #0x0
     fea:      	it	eq
     fec:      	moveq	r5, #0x20
     fee:      	cmp	r4, #0x1
     ff0:      	strb	r5, [r1, r0]
     ff2:      	beq	0xf40 <zs_println+0x28> @ imm = #-0xb6
     ff4:      	add.w	r10, r0, #0x1
     ff8:      	ldrb.w	r5, [lr, r10]
     ffc:      	cmp	r5, #0x0
     ffe:      	it	eq
    1000:      	moveq	r5, #0x20
    1002:      	cmp	r4, #0x2
    1004:      	strb.w	r5, [r1, r10]
    1008:      	beq	0xf40 <zs_println+0x28> @ imm = #-0xcc
    100a:      	adds	r0, #0x2
    100c:      	ldrb.w	r4, [lr, r0]
    1010:      	cmp	r4, #0x0
    1012:      	it	eq
    1014:      	moveq	r4, #0x20
    1016:      	strb	r4, [r1, r0]
    1018:      	b	0xf40 <zs_println+0x28> @ imm = #-0xdc
    101a:      	movs	r0, #0xa
    101c:      	strh	r0, [r7, #-93]
    1020:      	movs	r0, #0x4
    1022:      	sub.w	r1, r7, #0x5d
    1026:      	bkpt	#0xab
    1028:      	add	sp, #0x44
    102a:      	pop.w	{r8, r9, r10, r11}
    102e:      	pop	{r4, r5, r6, r7, pc}

00001030 <write_c>:
    1030:      	push	{r4, r5, r6, r7, lr}
    1032:      	add	r7, sp, #0xc
    1034:      	push.w	{r8, r9, r10, r11}
    1038:      	sub	sp, #0x44
    103a:      	mov	r2, r0
    103c:      	mov.w	r11, #0xffffffff
    1040:      	add.w	r0, r2, r11
    1044:      	ldrb	r1, [r0, #0x1]
    1046:      	cbz	r1, 0x1060 <write_c+0x30> @ imm = #0x16
    1048:      	ldrb	r1, [r0, #0x2]
    104a:      	cbz	r1, 0x106c <write_c+0x3c> @ imm = #0x1e
    104c:      	ldrb	r1, [r0, #0x3]
    104e:      	cmp	r1, #0x0
    1050:      	beq.w	0x1160 <write_c+0x130>  @ imm = #0x10c
    1054:      	ldrb	r0, [r0, #0x4]
    1056:      	add.w	r11, r11, #0x4
    105a:      	cmp	r0, #0x0
    105c:      	bne	0x1040 <write_c+0x10>   @ imm = #-0x20
    105e:      	b	0x1070 <write_c+0x40>   @ imm = #0xe
    1060:      	add.w	r11, r11, #0x1
    1064:      	cmp.w	r11, #0x0
    1068:      	bne	0x1076 <write_c+0x46>   @ imm = #0xa
    106a:      	b	0x116c <write_c+0x13c>  @ imm = #0xfe
    106c:      	add.w	r11, r11, #0x2
    1070:      	cmp.w	r11, #0x0
    1074:      	beq	0x116c <write_c+0x13c>  @ imm = #0xf4
    1076:      	sub.w	r1, r7, #0x5d
    107a:      	movs	r3, #0x0
    107c:      	add.w	r12, r1, #0x1
    1080:      	movs	r6, #0x40
    1082:      	mov.w	r9, #0x0
    1086:      	b	0x10a4 <write_c+0x74>   @ imm = #0x1a
    1088:      	strb.w	r3, [r1, r8]
    108c:      	movs	r0, #0x4
    108e:      	subs.w	r11, r11, r8
    1092:      	bkpt	#0xab
    1094:      	sbc	r9, r9, #0x0
    1098:      	rsbs.w	r0, r11, #0x0
    109c:      	sbcs.w	r0, r3, r9
    10a0:      	add	r2, r8
    10a2:      	bge	0x116c <write_c+0x13c>  @ imm = #0xc6
    10a4:      	mov.w	r8, #0x40
    10a8:      	cmp.w	r11, #0x40
    10ac:      	it	lo
    10ae:      	movlo	r8, r11
    10b0:      	cmp.w	r9, #0x0
    10b4:      	it	ne
    10b6:      	movne	r8, r6
    10b8:      	sub.w	r0, r8, #0x1
    10bc:      	cmp	r0, #0x3
    10be:      	bhs	0x10cc <write_c+0x9c>   @ imm = #0xa
    10c0:      	movs	r0, #0x0
    10c2:      	ands	r4, r8, #0x3
    10c6:      	bne	0x112e <write_c+0xfe>   @ imm = #0x64
    10c8:      	b	0x1088 <write_c+0x58>   @ imm = #-0x44
    10ca:      	nop
    10cc:      	bic	r0, r8, #0x3
    10d0:      	rsb.w	r10, r0, #0x0
    10d4:      	mov	r1, r2
    10d6:      	adds	r5, r2, #0x1
    10d8:      	mvn	r4, #0x3
    10dc:      	adds	r3, r5, r4
    10de:      	ldrb	r6, [r3, #0x3]
    10e0:      	ldrb	r2, [r3, #0x4]
    10e2:      	ldrb	r0, [r3, #0x5]
    10e4:      	cmp	r6, #0x0
    10e6:      	ldrb	r3, [r3, #0x6]
    10e8:      	it	eq
    10ea:      	moveq	r6, #0x20
    10ec:      	add.w	lr, r12, r4
    10f0:      	cmp	r2, #0x0
    10f2:      	strb.w	r6, [lr, #0x3]
    10f6:      	it	eq
    10f8:      	moveq	r2, #0x20
    10fa:      	strb.w	r2, [lr, #0x4]
    10fe:      	cmp	r0, #0x0
    1100:      	it	eq
    1102:      	moveq	r0, #0x20
    1104:      	adds	r4, #0x4
    1106:      	strb.w	r0, [lr, #0x5]
    110a:      	cmp	r3, #0x0
    110c:      	add.w	r0, r10, r4
    1110:      	it	eq
    1112:      	moveq	r3, #0x20
    1114:      	adds	r0, #0x4
    1116:      	strb.w	r3, [lr, #0x6]
    111a:      	bne	0x10dc <write_c+0xac>   @ imm = #-0x42
    111c:      	adds	r0, r4, #0x4
    111e:      	mov	r2, r1
    1120:      	movs	r3, #0x0
    1122:      	sub.w	r1, r7, #0x5d
    1126:      	movs	r6, #0x40
    1128:      	ands	r4, r8, #0x3
    112c:      	beq	0x1088 <write_c+0x58>   @ imm = #-0xa8
    112e:      	ldrb	r5, [r2, r0]
    1130:      	cmp	r5, #0x0
    1132:      	it	eq
    1134:      	moveq	r5, #0x20
    1136:      	cmp	r4, #0x1
    1138:      	strb	r5, [r1, r0]
    113a:      	beq	0x1088 <write_c+0x58>   @ imm = #-0xb6
    113c:      	add.w	r10, r0, #0x1
    1140:      	ldrb.w	r5, [r2, r10]
    1144:      	cmp	r5, #0x0
    1146:      	it	eq
    1148:      	moveq	r5, #0x20
    114a:      	cmp	r4, #0x2
    114c:      	strb.w	r5, [r1, r10]
    1150:      	beq	0x1088 <write_c+0x58>   @ imm = #-0xcc
    1152:      	adds	r0, #0x2
    1154:      	ldrb	r4, [r2, r0]
    1156:      	cmp	r4, #0x0
    1158:      	it	eq
    115a:      	moveq	r4, #0x20
    115c:      	strb	r4, [r1, r0]
    115e:      	b	0x1088 <write_c+0x58>   @ imm = #-0xda
    1160:      	add.w	r11, r11, #0x3
    1164:      	cmp.w	r11, #0x0
    1168:      	bne.w	0x1076 <write_c+0x46>   @ imm = #-0xf6
    116c:      	add	sp, #0x44
    116e:      	pop.w	{r8, r9, r10, r11}
    1172:      	pop	{r4, r5, r6, r7, pc}

00001174 <stop>:
    1174:      	push	{r4, r5, r6, r7, lr}
    1176:      	add	r7, sp, #0xc
    1178:      	str	r11, [sp, #-4]!
    117c:      	sub	sp, #0x48
    117e:      	movw	r6, #0x8000
    1182:      	movw	r5, #0x0
    1186:      	movt	r6, #0x203f
    118a:      	movt	r5, #0x2040
    118e:      	cmp	r6, r5
    1190:      	mov	r4, r0
    1192:      	bhs	0x11de <stop+0x6a>      @ imm = #0x48
    1194:      	movw	r0, #0x8000
    1198:      	movt	r0, #0x203f
    119c:      	ldr	r1, [r0]
    119e:      	cmp.w	r1, #0xcdcdcdcd
    11a2:      	bne	0x11dc <stop+0x68>      @ imm = #0x36
    11a4:      	adds	r6, r0, #0x4
    11a6:      	cmp	r6, r5
    11a8:      	bhs	0x11de <stop+0x6a>      @ imm = #0x32
    11aa:      	ldr	r1, [r6]
    11ac:      	cmp.w	r1, #0xcdcdcdcd
    11b0:      	bne	0x11de <stop+0x6a>      @ imm = #0x2a
    11b2:      	add.w	r6, r0, #0x8
    11b6:      	cmp	r6, r5
    11b8:      	bhs	0x11de <stop+0x6a>      @ imm = #0x22
    11ba:      	ldr	r1, [r6]
    11bc:      	cmp.w	r1, #0xcdcdcdcd
    11c0:      	bne	0x11de <stop+0x6a>      @ imm = #0x1a
    11c2:      	add.w	r6, r0, #0xc
    11c6:      	cmp	r6, r5
    11c8:      	bhs	0x11de <stop+0x6a>      @ imm = #0x12
    11ca:      	ldr	r1, [r6]
    11cc:      	cmp.w	r1, #0xcdcdcdcd
    11d0:      	bne	0x11de <stop+0x6a>      @ imm = #0xa
    11d2:      	adds	r0, #0x10
    11d4:      	cmp	r0, r5
    11d6:      	mov	r6, r0
    11d8:      	blo	0x119c <stop+0x28>      @ imm = #-0x40
    11da:      	b	0x11de <stop+0x6a>      @ imm = #0x0
    11dc:      	mov	r6, r0
    11de:      	movw	r0, #0x8c
    11e2:      	movt	r0, #0x2001
    11e6:      	ldr	r2, [r0]
    11e8:      	movw	r0, #0x2037
    11ec:      	movt	r0, #0x0
    11f0:      	movs	r3, #0x0
    11f2:      	bl	0x13e4 <text>           @ imm = #0x1ee
    11f6:      	movw	r0, #0x84
    11fa:      	movt	r0, #0x2000
    11fe:      	ldr	r2, [r0]
    1200:      	movw	r0, #0x204d
    1204:      	movt	r0, #0x0
    1208:      	movs	r3, #0x0
    120a:      	bl	0x13e4 <text>           @ imm = #0x1d6
    120e:      	movw	r0, #0x98
    1212:      	movt	r0, #0x2001
    1216:      	ldrd	r2, r3, [r0]
    121a:      	movw	r0, #0x2021
    121e:      	movt	r0, #0x0
    1222:      	bl	0x13e4 <text>           @ imm = #0x1be
    1226:      	movw	r0, #0x90
    122a:      	movt	r0, #0x2001
    122e:      	ldrd	r2, r3, [r0]
    1232:      	movw	r0, #0x2046
    1236:      	movt	r0, #0x0
    123a:      	bl	0x13e4 <text>           @ imm = #0x1a6
    123e:      	subs	r2, r5, r6
    1240:      	movw	r0, #0x202f
    1244:      	asrs	r3, r2, #0x1f
    1246:      	movt	r0, #0x0
    124a:      	bl	0x13e4 <text>           @ imm = #0x196
    124e:      	movs	r0, #0xa
    1250:      	strh.w	r0, [sp, #0x4]
    1254:      	movs	r0, #0x4
    1256:      	add	r1, sp, #0x4
    1258:      	bkpt	#0xab
    125a:      	movs	r0, #0x26
    125c:      	movt	r0, #0x2
    1260:      	strd	r0, r4, [sp, #4]
    1264:      	movs	r0, #0x20
    1266:      	add	r1, sp, #0x4
    1268:      	bkpt	#0xab
    126a:      	nop
    126c:      	b	0x126c <stop+0xf8>      @ imm = #-0x4
    126e:      	bmi	0x121a <stop+0xa6>      @ imm = #-0x58

00001270 <zs_set_args>:
    1270:      	push	{r7, lr}
    1272:      	mov	r7, sp
    1274:      	pop	{r7, pc}
    1276:      	bmi	0x1222 <stop+0xae>      @ imm = #-0x58

00001278 <Reset_Handler>:
    1278:      	push	{r7, lr}
    127a:      	mov	r7, sp
    127c:      	movw	r0, #0x0
    1280:      	movw	r1, #0x0
    1284:      	movt	r0, #0x2000
    1288:      	movt	r1, #0x2000
    128c:      	cmp	r1, r0
    128e:      	bhs	0x12c2 <Reset_Handler+0x4a> @ imm = #0x30
    1290:      	movw	r2, #0x2194
    1294:      	movt	r2, #0x0
    1298:      	ldr	r3, [r2]
    129a:      	str	r3, [r1], #4
    129e:      	cmp	r1, r0
    12a0:      	bhs	0x12c2 <Reset_Handler+0x4a> @ imm = #0x1e
    12a2:      	ldr	r3, [r2, #0x4]
    12a4:      	str	r3, [r1], #4
    12a8:      	cmp	r1, r0
    12aa:      	bhs	0x12c2 <Reset_Handler+0x4a> @ imm = #0x14
    12ac:      	ldr	r3, [r2, #0x8]
    12ae:      	str	r3, [r1], #4
    12b2:      	cmp	r1, r0
    12b4:      	bhs	0x12c2 <Reset_Handler+0x4a> @ imm = #0xa
    12b6:      	ldr	r3, [r2, #0xc]
    12b8:      	adds	r2, #0x10
    12ba:      	str	r3, [r1], #4
    12be:      	cmp	r1, r0
    12c0:      	blo	0x1298 <Reset_Handler+0x20> @ imm = #-0x2c
    12c2:      	movw	r0, #0xa4
    12c6:      	movw	r1, #0x0
    12ca:      	movt	r0, #0x2001
    12ce:      	movt	r1, #0x2000
    12d2:      	cmp	r1, r0
    12d4:      	bhs	0x12f8 <Reset_Handler+0x80> @ imm = #0x20
    12d6:      	movs	r2, #0x0
    12d8:      	str	r2, [r1], #4
    12dc:      	cmp	r1, r0
    12de:      	bhs	0x12f8 <Reset_Handler+0x80> @ imm = #0x16
    12e0:      	str	r2, [r1], #4
    12e4:      	cmp	r1, r0
    12e6:      	bhs	0x12f8 <Reset_Handler+0x80> @ imm = #0xe
    12e8:      	str	r2, [r1], #4
    12ec:      	cmp	r1, r0
    12ee:      	bhs	0x12f8 <Reset_Handler+0x80> @ imm = #0x6
    12f0:      	str	r2, [r1], #4
    12f4:      	cmp	r1, r0
    12f6:      	blo	0x12d8 <Reset_Handler+0x60> @ imm = #-0x22
    12f8:      	movw	r0, #0xed88
    12fc:      	movt	r0, #0xe000
    1300:      	ldr	r1, [r0]
    1302:      	orr	r1, r1, #0xf00000
    1306:      	str	r1, [r0]
    1308:      	movw	r0, #0xe010
    130c:      	movt	r0, #0xe000
    1310:      	mvn	r1, #0xff000000
    1314:      	dsb	sy
    1318:      	isb	sy
    131c:      	str	r1, [r0, #0x4]
    131e:      	movs	r1, #0x0
    1320:      	str	r1, [r0, #0x8]
    1322:      	movs	r1, #0x7
    1324:      	str	r1, [r0]
    1326:      	mov	r0, sp
    1328:      	movw	r1, #0x8000
    132c:      	subs	r0, #0x40
    132e:      	movt	r1, #0x203f
    1332:      	cmp	r0, r1
    1334:      	bls	0x135c <Reset_Handler+0xe4> @ imm = #0x24
    1336:      	mov.w	r2, #0xcdcdcdcd
    133a:      	nop
    133c:      	str	r2, [r1], #4
    1340:      	cmp	r1, r0
    1342:      	bhs	0x135c <Reset_Handler+0xe4> @ imm = #0x16
    1344:      	str	r2, [r1], #4
    1348:      	cmp	r1, r0
    134a:      	bhs	0x135c <Reset_Handler+0xe4> @ imm = #0xe
    134c:      	str	r2, [r1], #4
    1350:      	cmp	r1, r0
    1352:      	bhs	0x135c <Reset_Handler+0xe4> @ imm = #0x6
    1354:      	str	r2, [r1], #4
    1358:      	cmp	r1, r0
    135a:      	blo	0x133c <Reset_Handler+0xc4> @ imm = #-0x22
    135c:      	movs	r0, #0x0
    135e:      	movs	r1, #0x0
    1360:      	bl	0x40 <main>             @ imm = #-0x1324
    1364:      	bl	0x1174 <stop>           @ imm = #-0x1f4

00001368 <zs_ticks>:
    1368:      	push	{r7, lr}
    136a:      	mov	r7, sp
    136c:      	movw	r12, #0xe018
    1370:      	movw	r2, #0xa0
    1374:      	movt	r12, #0xe000
    1378:      	movt	r2, #0x2001
    137c:      	ldr	r1, [r2]
    137e:      	ldr.w	r3, [r12]
    1382:      	ldr	r0, [r2]
    1384:      	cmp	r1, r0
    1386:      	beq	0x13ac <zs_ticks+0x44>  @ imm = #0x22
    1388:      	ldr	r1, [r2]
    138a:      	ldr.w	r3, [r12]
    138e:      	ldr	r0, [r2]
    1390:      	cmp	r1, r0
    1392:      	beq	0x13ac <zs_ticks+0x44>  @ imm = #0x16
    1394:      	ldr	r1, [r2]
    1396:      	ldr.w	r3, [r12]
    139a:      	ldr	r0, [r2]
    139c:      	cmp	r1, r0
    139e:      	beq	0x13ac <zs_ticks+0x44>  @ imm = #0xa
    13a0:      	ldr	r1, [r2]
    13a2:      	ldr.w	r3, [r12]
    13a6:      	ldr	r0, [r2]
    13a8:      	cmp	r1, r0
    13aa:      	bne	0x137c <zs_ticks+0x14>  @ imm = #-0x32
    13ac:      	mvn	r0, #0xff000000
    13b0:      	subs	r0, r0, r3
    13b2:      	lsrs	r2, r1, #0x8
    13b4:      	adds.w	r0, r0, r1, lsl #24
    13b8:      	adc	r1, r2, #0x0
    13bc:      	pop	{r7, pc}
    13be:      	bmi	0x136a <zs_ticks+0x2>   @ imm = #-0x58

000013c0 <fault>:
    13c0:      	push	{r7, lr}
    13c2:      	mov	r7, sp
    13c4:      	movw	r0, #0x2016
    13c8:      	movt	r0, #0x0
    13cc:      	bl	0x73c <zs_panic_c>      @ imm = #-0xc94

000013d0 <SysTick_Handler>:
    13d0:      	push	{r7, lr}
    13d2:      	mov	r7, sp
    13d4:      	movw	r0, #0xa0
    13d8:      	movt	r0, #0x2001
    13dc:      	ldr	r1, [r0]
    13de:      	adds	r1, #0x1
    13e0:      	str	r1, [r0]
    13e2:      	pop	{r7, pc}

000013e4 <text>:
    13e4:      	push	{r4, r5, r6, r7, lr}
    13e6:      	add	r7, sp, #0xc
    13e8:      	push.w	{r8, r9, r10, r11}
    13ec:      	sub	sp, #0x64
    13ee:      	strd	r2, r3, [sp]
    13f2:      	mov	r3, r0
    13f4:      	mov.w	r12, #0xffffffff
    13f8:      	add.w	r0, r3, r12
    13fc:      	ldrb	r1, [r0, #0x1]
    13fe:      	cbz	r1, 0x141a <text+0x36>  @ imm = #0x18
    1400:      	ldrb	r1, [r0, #0x2]
    1402:      	cbz	r1, 0x1426 <text+0x42>  @ imm = #0x20
    1404:      	ldrb	r1, [r0, #0x3]
    1406:      	cbz	r1, 0x1432 <text+0x4e>  @ imm = #0x28
    1408:      	ldrb	r0, [r0, #0x4]
    140a:      	add.w	r12, r12, #0x4
    140e:      	cmp	r0, #0x0
    1410:      	bne	0x13f8 <text+0x14>      @ imm = #-0x1c
    1412:      	cmp.w	r12, #0x0
    1416:      	bne	0x143c <text+0x58>      @ imm = #0x22
    1418:      	b	0x152a <text+0x146>     @ imm = #0x10e
    141a:      	add.w	r12, r12, #0x1
    141e:      	cmp.w	r12, #0x0
    1422:      	bne	0x143c <text+0x58>      @ imm = #0x16
    1424:      	b	0x152a <text+0x146>     @ imm = #0x102
    1426:      	add.w	r12, r12, #0x2
    142a:      	cmp.w	r12, #0x0
    142e:      	bne	0x143c <text+0x58>      @ imm = #0xa
    1430:      	b	0x152a <text+0x146>     @ imm = #0xf6
    1432:      	add.w	r12, r12, #0x3
    1436:      	cmp.w	r12, #0x0
    143a:      	beq	0x152a <text+0x146>     @ imm = #0xec
    143c:      	sub.w	r1, r7, #0x5d
    1440:      	movs	r4, #0x0
    1442:      	add.w	r10, r1, #0x1
    1446:      	movs	r5, #0x40
    1448:      	mov.w	r9, #0x0
    144c:      	b	0x146c <text+0x88>      @ imm = #0x1c
    144e:      	nop
    1450:      	strb.w	r4, [r1, r11]
    1454:      	movs	r0, #0x4
    1456:      	subs.w	r12, r12, r11
    145a:      	bkpt	#0xab
    145c:      	sbc	r9, r9, #0x0
    1460:      	rsbs.w	r0, r12, #0x0
    1464:      	sbcs.w	r0, r4, r9
    1468:      	add	r3, r11
    146a:      	bge	0x152a <text+0x146>     @ imm = #0xbc
    146c:      	mov.w	r11, #0x40
    1470:      	cmp.w	r12, #0x40
    1474:      	it	lo
    1476:      	movlo	r11, r12
    1478:      	cmp.w	r9, #0x0
    147c:      	it	ne
    147e:      	movne	r11, r5
    1480:      	sub.w	r0, r11, #0x1
    1484:      	cmp	r0, #0x3
    1486:      	bhs	0x1494 <text+0xb0>      @ imm = #0xa
    1488:      	movs	r0, #0x0
    148a:      	ands	r2, r11, #0x3
    148e:      	bne	0x14f6 <text+0x112>     @ imm = #0x64
    1490:      	b	0x1450 <text+0x6c>      @ imm = #-0x44
    1492:      	nop
    1494:      	bic	r0, r11, #0x3
    1498:      	rsb.w	lr, r0, #0x0
    149c:      	mov	r1, r3
    149e:      	adds	r6, r3, #0x1
    14a0:      	mvn	r2, #0x3
    14a4:      	adds	r3, r6, r2
    14a6:      	ldrb	r5, [r3, #0x3]
    14a8:      	ldrb	r4, [r3, #0x4]
    14aa:      	ldrb	r0, [r3, #0x5]
    14ac:      	cmp	r5, #0x0
    14ae:      	ldrb	r3, [r3, #0x6]
    14b0:      	it	eq
    14b2:      	moveq	r5, #0x20
    14b4:      	add.w	r8, r10, r2
    14b8:      	cmp	r4, #0x0
    14ba:      	strb.w	r5, [r8, #0x3]
    14be:      	it	eq
    14c0:      	moveq	r4, #0x20
    14c2:      	strb.w	r4, [r8, #0x4]
    14c6:      	cmp	r0, #0x0
    14c8:      	it	eq
    14ca:      	moveq	r0, #0x20
    14cc:      	adds	r2, #0x4
    14ce:      	strb.w	r0, [r8, #0x5]
    14d2:      	cmp	r3, #0x0
    14d4:      	add.w	r0, lr, r2
    14d8:      	it	eq
    14da:      	moveq	r3, #0x20
    14dc:      	adds	r0, #0x4
    14de:      	strb.w	r3, [r8, #0x6]
    14e2:      	bne	0x14a4 <text+0xc0>      @ imm = #-0x42
    14e4:      	adds	r0, r2, #0x4
    14e6:      	mov	r3, r1
    14e8:      	movs	r4, #0x0
    14ea:      	sub.w	r1, r7, #0x5d
    14ee:      	movs	r5, #0x40
    14f0:      	ands	r2, r11, #0x3
    14f4:      	beq	0x1450 <text+0x6c>      @ imm = #-0xa8
    14f6:      	ldrb	r6, [r3, r0]
    14f8:      	cmp	r6, #0x0
    14fa:      	it	eq
    14fc:      	moveq	r6, #0x20
    14fe:      	cmp	r2, #0x1
    1500:      	strb	r6, [r1, r0]
    1502:      	beq	0x1450 <text+0x6c>      @ imm = #-0xb6
    1504:      	adds	r6, r0, #0x1
    1506:      	ldrb.w	lr, [r3, r6]
    150a:      	cmp.w	lr, #0x0
    150e:      	it	eq
    1510:      	moveq.w	lr, #0x20
    1514:      	cmp	r2, #0x2
    1516:      	strb.w	lr, [r1, r6]
    151a:      	beq	0x1450 <text+0x6c>      @ imm = #-0xce
    151c:      	adds	r0, #0x2
    151e:      	ldrb	r2, [r3, r0]
    1520:      	cmp	r2, #0x0
    1522:      	it	eq
    1524:      	moveq	r2, #0x20
    1526:      	strb	r2, [r1, r0]
    1528:      	b	0x1450 <text+0x6c>      @ imm = #-0xdc
    152a:      	movw	r9, #0xcccd
    152e:      	ldrd	r4, r5, [sp]
    1532:      	mov.w	r11, #0x1
    1536:      	movt	r9, #0xcccc
    153a:      	sub.w	r10, r7, #0x5d
    153e:      	nop
    1540:      	lsrs	r0, r4, #0x1
    1542:      	orr.w	r0, r0, r5, lsl #31
    1546:      	adds.w	r1, r0, r5, lsr #1
    154a:      	adc	r1, r1, #0x0
    154e:      	umull	r2, r3, r1, r9
    1552:      	bic	r2, r3, #0x3
    1556:      	add.w	r2, r2, r3, lsr #2
    155a:      	subs	r1, r1, r2
    155c:      	subs	r1, r0, r1
    155e:      	umull	r0, lr, r1, r9
    1562:      	lsr.w	r3, r5, #0x1
    1566:      	add.w	r6, r0, r0, lsl #2
    156a:      	sbc	r2, r3, #0x0
    156e:      	sub.w	r6, r4, r6, lsl #1
    1572:      	mov	r3, r4
    1574:      	subs	r4, #0xa
    1576:      	orr	r12, r6, #0x30
    157a:      	add.w	r8, r10, r11
    157e:      	sbcs	r4, r5, #0x0
    1582:      	strb	r12, [r8, #-1]
    1586:      	blo	0x167e <text+0x29a>     @ imm = #0xf4
    1588:      	mov.w	r4, #0xcccccccc
    158c:      	mla	r1, r1, r4, lr
    1590:      	mla	r1, r2, r9, r1
    1594:      	lsrs	r2, r0, #0x1
    1596:      	orr.w	r2, r2, r1, lsl #31
    159a:      	adds.w	r1, r2, r1, lsr #1
    159e:      	adc	r1, r1, #0x0
    15a2:      	umull	r2, r4, r1, r9
    15a6:      	bic	r2, r4, #0x3
    15aa:      	add.w	r2, r2, r4, lsr #2
    15ae:      	subs	r1, r1, r2
    15b0:      	and	r0, r0, #0x1
    15b4:      	orr.w	r0, r0, r1, lsl #1
    15b8:      	subs.w	r1, r3, #0x64
    15bc:      	orr	r0, r0, #0x30
    15c0:      	sbcs	r1, r5, #0x0
    15c4:      	mov	r4, r10
    15c6:      	strb.w	r0, [r10, r11]
    15ca:      	blo	0x1688 <text+0x2a4>     @ imm = #0xba
    15cc:      	mov	r6, r3
    15ce:      	mov	r0, r3
    15d0:      	mov	r1, r5
    15d2:      	movs	r2, #0x64
    15d4:      	movs	r3, #0x0
    15d6:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x3e2
    15da:      	lsrs	r2, r0, #0x1
    15dc:      	orr.w	r2, r2, r1, lsl #31
    15e0:      	adds.w	r1, r2, r1, lsr #1
    15e4:      	adc	r1, r1, #0x0
    15e8:      	umull	r2, r3, r1, r9
    15ec:      	bic	r2, r3, #0x3
    15f0:      	add.w	r2, r2, r3, lsr #2
    15f4:      	subs	r1, r1, r2
    15f6:      	and	r0, r0, #0x1
    15fa:      	orr.w	r0, r0, r1, lsl #1
    15fe:      	subs.w	r1, r6, #0x3e8
    1602:      	orr	r0, r0, #0x30
    1606:      	sbcs	r1, r5, #0x0
    160a:      	strb.w	r0, [r8, #0x1]
    160e:      	blo	0x1690 <text+0x2ac>     @ imm = #0x7e
    1610:      	mov	r0, r6
    1612:      	mov	r1, r5
    1614:      	mov.w	r2, #0x3e8
    1618:      	movs	r3, #0x0
    161a:      	mov	r10, r4
    161c:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x39c
    1620:      	lsrs	r2, r0, #0x1
    1622:      	orr.w	r2, r2, r1, lsl #31
    1626:      	adds.w	r1, r2, r1, lsr #1
    162a:      	adc	r1, r1, #0x0
    162e:      	umull	r2, r3, r1, r9
    1632:      	bic	r2, r3, #0x3
    1636:      	add.w	r2, r2, r3, lsr #2
    163a:      	subs	r1, r1, r2
    163c:      	and	r0, r0, #0x1
    1640:      	orr.w	r0, r0, r1, lsl #1
    1644:      	orr	r0, r0, #0x30
    1648:      	strb.w	r0, [r8, #0x2]
    164c:      	mov	r0, r6
    164e:      	mov	r1, r5
    1650:      	movw	r2, #0x2710
    1654:      	movs	r3, #0x0
    1656:      	bl	0x19bc <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x362
    165a:      	movw	r2, #0x270f
    165e:      	subs	r2, r2, r6
    1660:      	mov.w	r2, #0x0
    1664:      	sbcs	r2, r5
    1666:      	add.w	r11, r11, #0x4
    166a:      	mov	r4, r0
    166c:      	mov	r5, r1
    166e:      	blo.w	0x1540 <text+0x15c>     @ imm = #-0x132
    1672:      	sub.w	r1, r11, #0x1
    1676:      	sub.w	r12, r11, #0x2
    167a:      	mov	r11, r1
    167c:      	b	0x1684 <text+0x2a0>     @ imm = #0x4
    167e:      	sub.w	r12, r11, #0x1
    1682:      	mov	r1, r11
    1684:      	mov	r4, r10
    1686:      	b	0x169a <text+0x2b6>     @ imm = #0x10
    1688:      	add.w	r1, r11, #0x1
    168c:      	mov	r12, r11
    168e:      	b	0x1698 <text+0x2b4>     @ imm = #0x6
    1690:      	add.w	r1, r11, #0x2
    1694:      	add.w	r12, r11, #0x1
    1698:      	mov	r11, r1
    169a:      	and	lr, r1, #0x3
    169e:      	lsrs	r3, r1, #0x2
    16a0:      	mov.w	r1, #0x0
    16a4:      	beq	0x16de <text+0x2fa>     @ imm = #0x36
    16a6:      	sub.w	r6, r7, #0x75
    16aa:      	add.w	r5, r12, r4
    16ae:      	sub.w	r9, r1, r3, lsl #2
    16b2:      	subs	r6, #0x3
    16b4:      	subs	r5, #0x1
    16b6:      	nop
    16b8:      	adds	r4, r5, r1
    16ba:      	ldrb	r3, [r5, r1]
    16bc:      	ldrb	r0, [r4, #-2]
    16c0:      	ldrb	r2, [r4, #-1]
    16c4:      	ldrb	r4, [r4, #0x1]
    16c6:      	subs	r1, #0x4
    16c8:      	strb	r3, [r6, #4]!
    16cc:      	cmp	r9, r1
    16ce:      	strb	r4, [r6, #-1]
    16d2:      	strb	r2, [r6, #0x1]
    16d4:      	strb	r0, [r6, #0x2]
    16d6:      	bne	0x16b8 <text+0x2d4>     @ imm = #-0x22
    16d8:      	rsbs	r1, r1, #0
    16da:      	sub.w	r4, r7, #0x5d
    16de:      	cmp.w	lr, #0x0
    16e2:      	beq	0x1710 <text+0x32c>     @ imm = #0x2a
    16e4:      	sub.w	r0, r12, r1
    16e8:      	ldrb	r0, [r4, r0]
    16ea:      	sub.w	r3, r7, #0x75
    16ee:      	cmp.w	lr, #0x1
    16f2:      	strb	r0, [r3, r1]
    16f4:      	beq	0x1710 <text+0x32c>     @ imm = #0x18
    16f6:      	adds	r0, r1, #0x1
    16f8:      	sub.w	r2, r12, r0
    16fc:      	ldrb	r2, [r4, r2]
    16fe:      	cmp.w	lr, #0x2
    1702:      	strb	r2, [r3, r0]
    1704:      	beq	0x1710 <text+0x32c>     @ imm = #0x8
    1706:      	adds	r0, r1, #0x2
    1708:      	sub.w	r1, r12, r0
    170c:      	ldrb	r1, [r4, r1]
    170e:      	strb	r1, [r3, r0]
    1710:      	sub.w	r0, r7, #0x75
    1714:      	movs	r1, #0x0
    1716:      	mov.w	r12, #0xffffffff
    171a:      	strb.w	r1, [r0, r11]
    171e:      	nop
    1720:      	add.w	r1, r0, r12
    1724:      	ldrb	r3, [r1, #0x1]
    1726:      	cbz	r3, 0x1742 <text+0x35e> @ imm = #0x18
    1728:      	ldrb	r3, [r1, #0x2]
    172a:      	cbz	r3, 0x174e <text+0x36a> @ imm = #0x20
    172c:      	ldrb	r3, [r1, #0x3]
    172e:      	cbz	r3, 0x175a <text+0x376> @ imm = #0x28
    1730:      	ldrb	r1, [r1, #0x4]
    1732:      	add.w	r12, r12, #0x4
    1736:      	cmp	r1, #0x0
    1738:      	bne	0x1720 <text+0x33c>     @ imm = #-0x1c
    173a:      	cmp.w	r12, #0x0
    173e:      	bne	0x1764 <text+0x380>     @ imm = #0x22
    1740:      	b	0x184c <text+0x468>     @ imm = #0x108
    1742:      	add.w	r12, r12, #0x1
    1746:      	cmp.w	r12, #0x0
    174a:      	bne	0x1764 <text+0x380>     @ imm = #0x16
    174c:      	b	0x184c <text+0x468>     @ imm = #0xfc
    174e:      	add.w	r12, r12, #0x2
    1752:      	cmp.w	r12, #0x0
    1756:      	bne	0x1764 <text+0x380>     @ imm = #0xa
    1758:      	b	0x184c <text+0x468>     @ imm = #0xf0
    175a:      	add.w	r12, r12, #0x3
    175e:      	cmp.w	r12, #0x0
    1762:      	beq	0x184c <text+0x468>     @ imm = #0xe6
    1764:      	movs	r2, #0x0
    1766:      	add.w	lr, r4, #0x1
    176a:      	sub.w	r9, r7, #0x75
    176e:      	movs	r3, #0x40
    1770:      	mov.w	r11, #0x0
    1774:      	b	0x1796 <text+0x3b2>     @ imm = #0x1e
    1776:      	nop
    1778:      	strb.w	r2, [r4, r8]
    177c:      	movs	r0, #0x4
    177e:      	subs.w	r12, r12, r8
    1782:      	mov	r1, r4
    1784:      	bkpt	#0xab
    1786:      	sbc	r11, r11, #0x0
    178a:      	rsbs.w	r0, r12, #0x0
    178e:      	sbcs.w	r0, r2, r11
    1792:      	add	r9, r8
    1794:      	bge	0x184c <text+0x468>     @ imm = #0xb4
    1796:      	mov.w	r8, #0x40
    179a:      	cmp.w	r12, #0x40
    179e:      	it	lo
    17a0:      	movlo	r8, r12
    17a2:      	cmp.w	r11, #0x0
    17a6:      	it	ne
    17a8:      	movne	r8, r3
    17aa:      	sub.w	r0, r8, #0x1
    17ae:      	cmp	r0, #0x3
    17b0:      	bhs	0x17bc <text+0x3d8>     @ imm = #0x8
    17b2:      	movs	r0, #0x0
    17b4:      	ands	r1, r8, #0x3
    17b8:      	bne	0x1816 <text+0x432>     @ imm = #0x5a
    17ba:      	b	0x1778 <text+0x394>     @ imm = #-0x46
    17bc:      	bic	r0, r8, #0x3
    17c0:      	rsb.w	r10, r0, #0x0
    17c4:      	add.w	r5, r9, #0x1
    17c8:      	mvn	r1, #0x3
    17cc:      	adds	r4, r5, r1
    17ce:      	ldrb	r2, [r4, #0x3]
    17d0:      	ldrb	r3, [r4, #0x4]
    17d2:      	ldrb	r6, [r4, #0x5]
    17d4:      	cmp	r2, #0x0
    17d6:      	ldrb	r4, [r4, #0x6]
    17d8:      	it	eq
    17da:      	moveq	r2, #0x20
    17dc:      	add.w	r0, lr, r1
    17e0:      	cmp	r3, #0x0
    17e2:      	strb	r2, [r0, #0x3]
    17e4:      	it	eq
    17e6:      	moveq	r3, #0x20
    17e8:      	cmp	r6, #0x0
    17ea:      	add.w	r1, r1, #0x4
    17ee:      	strb	r3, [r0, #0x4]
    17f0:      	it	eq
    17f2:      	moveq	r6, #0x20
    17f4:      	cmp	r4, #0x0
    17f6:      	add.w	r2, r10, r1
    17fa:      	strb	r6, [r0, #0x5]
    17fc:      	it	eq
    17fe:      	moveq	r4, #0x20
    1800:      	adds	r2, #0x4
    1802:      	strb	r4, [r0, #0x6]
    1804:      	bne	0x17cc <text+0x3e8>     @ imm = #-0x3c
    1806:      	adds	r0, r1, #0x4
    1808:      	sub.w	r4, r7, #0x5d
    180c:      	movs	r2, #0x0
    180e:      	movs	r3, #0x40
    1810:      	ands	r1, r8, #0x3
    1814:      	beq	0x1778 <text+0x394>     @ imm = #-0xa0
    1816:      	ldrb.w	r5, [r9, r0]
    181a:      	cmp	r5, #0x0
    181c:      	it	eq
    181e:      	moveq	r5, #0x20
    1820:      	cmp	r1, #0x1
    1822:      	strb	r5, [r4, r0]
    1824:      	beq	0x1778 <text+0x394>     @ imm = #-0xb0
    1826:      	add.w	r10, r0, #0x1
    182a:      	ldrb.w	r5, [r9, r10]
    182e:      	cmp	r5, #0x0
    1830:      	it	eq
    1832:      	moveq	r5, #0x20
    1834:      	cmp	r1, #0x2
    1836:      	strb.w	r5, [r4, r10]
    183a:      	beq	0x1778 <text+0x394>     @ imm = #-0xc6
    183c:      	adds	r0, #0x2
    183e:      	ldrb.w	r1, [r9, r0]
    1842:      	cmp	r1, #0x0
    1844:      	it	eq
    1846:      	moveq	r1, #0x20
    1848:      	strb	r1, [r4, r0]
    184a:      	b	0x1778 <text+0x394>     @ imm = #-0xd6
    184c:      	add	sp, #0x64
    184e:      	pop.w	{r8, r9, r10, r11}
    1852:      	pop	{r4, r5, r6, r7, pc}

00001854 <compiler_rt.memset>:
    1854:      	cmp	r2, #0x0
    1856:      	it	eq
    1858:      	bxeq	lr
    185a:      	push	{r7, lr}
    185c:      	mov	r7, sp
    185e:      	ands	lr, r2, #0x3
    1862:      	mov	r3, r2
    1864:      	mov	r12, r0
    1866:      	beq	0x188a <compiler_rt.memset+0x36> @ imm = #0x20
    1868:      	mov	r12, r0
    186a:      	cmp.w	lr, #0x1
    186e:      	strb	r1, [r12], #1
    1872:      	bne	0x187c <compiler_rt.memset+0x28> @ imm = #0x6
    1874:      	subs	r3, r2, #0x1
    1876:      	cmp	r2, #0x4
    1878:      	bhs	0x188e <compiler_rt.memset+0x3a> @ imm = #0x12
    187a:      	b	0x18a2 <compiler_rt.memset+0x4e> @ imm = #0x24
    187c:      	cmp.w	lr, #0x2
    1880:      	strb	r1, [r0, #0x1]
    1882:      	bne	0x18a8 <compiler_rt.memset+0x54> @ imm = #0x22
    1884:      	subs	r3, r2, #0x2
    1886:      	add.w	r12, r0, #0x2
    188a:      	cmp	r2, #0x4
    188c:      	blo	0x18a2 <compiler_rt.memset+0x4e> @ imm = #0x12
    188e:      	sub.w	r2, r12, #0x4
    1892:      	nop
    1894:      	strb	r1, [r2, #4]!
    1898:      	subs	r3, #0x4
    189a:      	strb	r1, [r2, #0x1]
    189c:      	strb	r1, [r2, #0x2]
    189e:      	strb	r1, [r2, #0x3]
    18a0:      	bne	0x1894 <compiler_rt.memset+0x40> @ imm = #-0x10
    18a2:      	pop.w	{r7, lr}
    18a6:      	bx	lr
    18a8:      	subs	r3, r2, #0x3
    18aa:      	add.w	r12, r0, #0x3
    18ae:      	strb	r1, [r0, #0x2]
    18b0:      	cmp	r2, #0x4
    18b2:      	bhs	0x188e <compiler_rt.memset+0x3a> @ imm = #-0x28
    18b4:      	b	0x18a2 <compiler_rt.memset+0x4e> @ imm = #-0x16
    18b6:      	bmi	0x1862 <compiler_rt.memset+0xe> @ imm = #-0x58

000018b8 <compiler_rt.arm.__aeabi_unwind_cpp_pr0>:
    18b8:      	push	{r7, lr}
    18ba:      	mov	r7, sp
    18bc:      	pop	{r7, pc}
    18be:      	bmi	0x186a <compiler_rt.memset+0x16> @ imm = #-0x58

000018c0 <compiler_rt.arm.__aeabi_memclr>:
    18c0:      	push	{r7, lr}
    18c2:      	mov	r7, sp
    18c4:      	mov	r2, r1
    18c6:      	movs	r1, #0x0
    18c8:      	pop.w	{r7, lr}
    18cc:      	b.w	0x1854 <compiler_rt.memset> @ imm = #-0x7c

000018d0 <compiler_rt.arm.__aeabi_memcpy>:
    18d0:      	push	{r4, r5, r6, r7, lr}
    18d2:      	add	r7, sp, #0xc
    18d4:      	push.w	{r8, r9, r10, r11}
    18d8:      	sub	sp, #0x4
    18da:      	cmp	r2, #0xf
    18dc:      	bhi	0x18fc <compiler_rt.arm.__aeabi_memcpy+0x2c> @ imm = #0x1c
    18de:      	cmp	r2, #0x3
    18e0:      	bhi	0x1924 <compiler_rt.arm.__aeabi_memcpy+0x54> @ imm = #0x40
    18e2:      	cbz	r2, 0x18f4 <compiler_rt.arm.__aeabi_memcpy+0x24> @ imm = #0xe
    18e4:      	ldrb	r3, [r1]
    18e6:      	strb	r3, [r0]
    18e8:      	lsrs	r3, r2, #0x1
    18ea:      	subs	r2, #0x1
    18ec:      	ldrb	r6, [r1, r3]
    18ee:      	ldrb	r1, [r1, r2]
    18f0:      	strb	r6, [r0, r3]
    18f2:      	strb	r1, [r0, r2]
    18f4:      	add	sp, #0x4
    18f6:      	pop.w	{r8, r9, r10, r11}
    18fa:      	pop	{r4, r5, r6, r7, pc}
    18fc:      	ldr	r3, [r1]
    18fe:      	mov.w	r6, #0xffffffff
    1902:      	str	r3, [r0]
    1904:      	and	r3, r1, #0x3
    1908:      	rsb.w	lr, r3, #0x4
    190c:      	sub.w	r4, r2, lr
    1910:      	add.w	r6, r6, r4, lsr #2
    1914:      	cmp	r6, #0x3
    1916:      	ubfx	r6, r4, #0x2, #0x2
    191a:      	str	r6, [sp]
    191c:      	bhs	0x1948 <compiler_rt.arm.__aeabi_memcpy+0x78> @ imm = #0x28
    191e:      	movs	r3, #0x0
    1920:      	b	0x197c <compiler_rt.arm.__aeabi_memcpy+0xac> @ imm = #0x58
    1922:      	nop
    1924:      	movs	r3, #0x4
    1926:      	ldr	r6, [r1]
    1928:      	and.w	r3, r3, r2, lsr #1
    192c:      	subs	r2, #0x4
    192e:      	str	r6, [r0]
    1930:      	ldr	r6, [r1, r3]
    1932:      	subs	r5, r2, r3
    1934:      	str	r6, [r0, r3]
    1936:      	ldr	r3, [r1, r5]
    1938:      	ldr	r1, [r1, r2]
    193a:      	str	r3, [r0, r5]
    193c:      	str	r1, [r0, r2]
    193e:      	add	sp, #0x4
    1940:      	pop.w	{r8, r9, r10, r11}
    1944:      	pop	{r4, r5, r6, r7, pc}
    1946:      	nop
    1948:      	lsrs	r4, r4, #0x2
    194a:      	bic	r8, r4, #0x3
    194e:      	sub.w	r9, r0, r3
    1952:      	sub.w	r10, r1, r3
    1956:      	movs	r3, #0x0
    1958:      	add.w	r5, r10, r3, lsl #2
    195c:      	add.w	r12, r5, #0x4
    1960:      	add.w	r4, r9, r3, lsl #2
    1964:      	ldm.w	r12, {r6, r11, r12}
    1968:      	ldr	r5, [r5, #0x10]
    196a:      	adds	r3, #0x4
    196c:      	cmp	r8, r3
    196e:      	str	r6, [r4, #0x4]
    1970:      	str.w	r11, [r4, #0x8]
    1974:      	str.w	r12, [r4, #0xc]
    1978:      	str	r5, [r4, #0x10]
    197a:      	bne	0x1958 <compiler_rt.arm.__aeabi_memcpy+0x88> @ imm = #-0x26
    197c:      	ldr	r4, [sp]
    197e:      	cbz	r4, 0x19ac <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x2a
    1980:      	add.w	r6, r1, lr
    1984:      	ldr.w	r5, [r6, r3, lsl #2]
    1988:      	add.w	r8, r0, lr
    198c:      	cmp	r4, #0x1
    198e:      	str.w	r5, [r8, r3, lsl #2]
    1992:      	beq	0x19ac <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x16
    1994:      	adds	r5, r3, #0x1
    1996:      	ldr.w	r12, [r6, r5, lsl #2]
    199a:      	cmp	r4, #0x2
    199c:      	str.w	r12, [r8, r5, lsl #2]
    19a0:      	beq	0x19ac <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x8
    19a2:      	adds	r3, #0x2
    19a4:      	ldr.w	r6, [r6, r3, lsl #2]
    19a8:      	str.w	r6, [r8, r3, lsl #2]
    19ac:      	subs	r2, #0x4
    19ae:      	ldr	r1, [r1, r2]
    19b0:      	str	r1, [r0, r2]
    19b2:      	add	sp, #0x4
    19b4:      	pop.w	{r8, r9, r10, r11}
    19b8:      	pop	{r4, r5, r6, r7, pc}
    19ba:      	bmi	0x1966 <compiler_rt.arm.__aeabi_memcpy+0x96> @ imm = #-0x58

000019bc <compiler_rt.arm.__aeabi_uldivmod>:
    19bc:      	push	{r4, lr}
    19be:      	sub	sp, #0x10
    19c0:      	add	r4, sp, #0x8
    19c2:      	str	r4, [sp]
    19c4:      	bl	0x19d0 <compiler_rt.int.__udivmoddi4> @ imm = #0x8
    19c8:      	ldr	r2, [sp, #0x8]
    19ca:      	ldr	r3, [sp, #0xc]
    19cc:      	add	sp, #0x10
    19ce:      	pop	{r4, pc}

000019d0 <compiler_rt.int.__udivmoddi4>:
    19d0:      	push	{r4, r5, r6, r7, lr}
    19d2:      	add	r7, sp, #0xc
    19d4:      	push.w	{r8, r9, r10, r11}
    19d8:      	sub	sp, #0x20
    19da:      	mov	r5, r2
    19dc:      	ldr	r6, [r7, #0x8]
    19de:      	subs	r2, r0, r2
    19e0:      	sbcs.w	r2, r1, r3
    19e4:      	bhs	0x19fc <compiler_rt.int.__udivmoddi4+0x2c> @ imm = #0x14
    19e6:      	cmp	r6, #0x0
    19e8:      	it	ne
    19ea:      	strdne	r0, r1, [r6]
    19ee:      	movs	r0, #0x0
    19f0:      	movs	r1, #0x0
    19f2:      	add	sp, #0x20
    19f4:      	pop.w	{r8, r9, r10, r11}
    19f8:      	pop	{r4, r5, r6, r7, pc}
    19fa:      	nop
    19fc:      	cmp	r3, #0x0
    19fe:      	beq.w	0x1b08 <compiler_rt.int.__udivmoddi4+0x138> @ imm = #0x106
    1a02:      	clz	r2, r3
    1a06:      	cmp	r2, #0x0
    1a08:      	beq.w	0x1b34 <compiler_rt.int.__udivmoddi4+0x164> @ imm = #0x128
    1a0c:      	rsbs	r6, r2, #0
    1a0e:      	and	r4, r6, #0x1f
    1a12:      	lsl.w	r12, r3, r2
    1a16:      	lsr.w	r6, r5, r4
    1a1a:      	orr.w	r8, r6, r12
    1a1e:      	lsl.w	r2, r1, r2
    1a22:      	lsr.w	r6, r0, r4
    1a26:      	clz	lr, r8
    1a2a:      	orrs	r2, r6
    1a2c:      	ands	r12, lr, #0x1f
    1a30:      	lsr.w	r6, r1, r4
    1a34:      	str	r5, [sp, #0x10]
    1a36:      	str	r0, [sp, #0x4]
    1a38:      	beq	0x1a54 <compiler_rt.int.__udivmoddi4+0x84> @ imm = #0x18
    1a3a:      	lsl.w	r4, r6, r12
    1a3e:      	rsb.w	r6, lr, #0x0
    1a42:      	and	r6, r6, #0x1f
    1a46:      	lsr.w	r6, r2, r6
    1a4a:      	lsl.w	r8, r8, r12
    1a4e:      	orrs	r6, r4
    1a50:      	lsl.w	r2, r2, r12
    1a54:      	lsr.w	lr, r8, #0x10
    1a58:      	udiv	r4, r6, lr
    1a5c:      	strd	r3, r1, [sp, #8]
    1a60:      	mls	r9, r4, lr, r6
    1a64:      	uxth.w	r12, r8
    1a68:      	lsr.w	r11, r2, #0x10
    1a6c:      	uxth	r3, r2
    1a6e:      	mov	r0, r6
    1a70:      	mov.w	r10, #0x0
    1a74:      	str.w	r8, [sp]
    1a78:      	b	0x1a8c <compiler_rt.int.__udivmoddi4+0xbc> @ imm = #0x10
    1a7a:      	nop
    1a7c:      	subs	r6, r4, #0x4
    1a7e:      	add.w	r9, r2, lr
    1a82:      	cmp.w	r10, r9, lsr #16
    1a86:      	mov	r4, r6
    1a88:      	bne.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x23a
    1a8c:      	cmp.w	r10, r4, lsr #16
    1a90:      	bne	0x1aa0 <compiler_rt.int.__udivmoddi4+0xd0> @ imm = #0xc
    1a92:      	mul	r2, r4, r12
    1a96:      	orr.w	r6, r11, r9, lsl #16
    1a9a:      	cmp	r2, r6
    1a9c:      	bls.w	0x1cc4 <compiler_rt.int.__udivmoddi4+0x2f4> @ imm = #0x224
    1aa0:      	add.w	r2, r9, lr
    1aa4:      	cmp.w	r10, r2, lsr #16
    1aa8:      	sub.w	r6, r4, #0x1
    1aac:      	bne.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x216
    1ab0:      	cmp.w	r10, r6, lsr #16
    1ab4:      	bne	0x1ac4 <compiler_rt.int.__udivmoddi4+0xf4> @ imm = #0xc
    1ab6:      	mul	r9, r6, r12
    1aba:      	orr.w	r8, r11, r2, lsl #16
    1abe:      	cmp	r9, r8
    1ac0:      	bls.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x202
    1ac4:      	add	r2, lr
    1ac6:      	cmp.w	r10, r2, lsr #16
    1aca:      	sub.w	r6, r4, #0x2
    1ace:      	bne.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1f4
    1ad2:      	cmp.w	r10, r6, lsr #16
    1ad6:      	bne	0x1ae6 <compiler_rt.int.__udivmoddi4+0x116> @ imm = #0xc
    1ad8:      	mul	r8, r6, r12
    1adc:      	orr.w	r5, r11, r2, lsl #16
    1ae0:      	cmp	r8, r5
    1ae2:      	bls.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1e0
    1ae6:      	add	r2, lr
    1ae8:      	cmp.w	r10, r2, lsr #16
    1aec:      	sub.w	r6, r4, #0x3
    1af0:      	bne.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1d2
    1af4:      	cmp.w	r10, r6, lsr #16
    1af8:      	bne	0x1a7c <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x80
    1afa:      	mul	r5, r6, r12
    1afe:      	orr.w	r1, r11, r2, lsl #16
    1b02:      	cmp	r5, r1
    1b04:      	bhi	0x1a7c <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x8c
    1b06:      	b	0x1cc6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1bc
    1b08:      	cmp	r1, r5
    1b0a:      	clz	lr, r5
    1b0e:      	bhs	0x1b4c <compiler_rt.int.__udivmoddi4+0x17c> @ imm = #0x3a
    1b10:      	cmp.w	lr, #0x0
    1b14:      	beq.w	0x1c1c <compiler_rt.int.__udivmoddi4+0x24c> @ imm = #0x104
    1b18:      	rsb.w	r2, lr, #0x0
    1b1c:      	and	r2, r2, #0x1f
    1b20:      	lsl.w	r1, r1, lr
    1b24:      	lsr.w	r2, r0, r2
    1b28:      	lsl.w	r5, r5, lr
    1b2c:      	orrs	r2, r1
    1b2e:      	lsl.w	r0, r0, lr
    1b32:      	b	0x1c1e <compiler_rt.int.__udivmoddi4+0x24e> @ imm = #0xe8
    1b34:      	cbz	r6, 0x1b3e <compiler_rt.int.__udivmoddi4+0x16e> @ imm = #0x6
    1b36:      	subs	r0, r0, r5
    1b38:      	sbcs	r1, r3
    1b3a:      	strd	r0, r1, [r6]
    1b3e:      	movs	r1, #0x0
    1b40:      	movs	r0, #0x1
    1b42:      	add	sp, #0x20
    1b44:      	pop.w	{r8, r9, r10, r11}
    1b48:      	pop	{r4, r5, r6, r7, pc}
    1b4a:      	nop
    1b4c:      	udiv	r2, r1, r5
    1b50:      	cmp.w	lr, #0x0
    1b54:      	mls	r8, r2, r5, r1
    1b58:      	mov	r1, r2
    1b5a:      	beq	0x1b78 <compiler_rt.int.__udivmoddi4+0x1a8> @ imm = #0x1a
    1b5c:      	rsb.w	r3, lr, #0x0
    1b60:      	and	r3, r3, #0x1f
    1b64:      	lsl.w	r2, r8, lr
    1b68:      	lsr.w	r3, r0, r3
    1b6c:      	lsl.w	r5, r5, lr
    1b70:      	orr.w	r8, r2, r3
    1b74:      	lsl.w	r0, r0, lr
    1b78:      	lsrs	r4, r5, #0x10
    1b7a:      	str	r5, [sp, #0x10]
    1b7c:      	uxth.w	r12, r5
    1b80:      	udiv	r5, r8, r4
    1b84:      	lsr.w	r10, r0, #0x10
    1b88:      	mls	r6, r5, r4, r8
    1b8c:      	uxth.w	r9, r0
    1b90:      	movs	r3, #0x0
    1b92:      	b	0x1ba2 <compiler_rt.int.__udivmoddi4+0x1d2> @ imm = #0xc
    1b94:      	subs	r0, r5, #0x4
    1b96:      	adds	r6, r2, r4
    1b98:      	cmp.w	r3, r6, lsr #16
    1b9c:      	mov	r5, r0
    1b9e:      	bne.w	0x1dde <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x23c
    1ba2:      	cmp.w	r3, r5, lsr #16
    1ba6:      	bne	0x1bb6 <compiler_rt.int.__udivmoddi4+0x1e6> @ imm = #0xc
    1ba8:      	mul	r0, r5, r12
    1bac:      	orr.w	r2, r10, r6, lsl #16
    1bb0:      	cmp	r0, r2
    1bb2:      	bls.w	0x1ddc <compiler_rt.int.__udivmoddi4+0x40c> @ imm = #0x226
    1bb6:      	adds	r2, r6, r4
    1bb8:      	cmp.w	r3, r2, lsr #16
    1bbc:      	sub.w	r0, r5, #0x1
    1bc0:      	bne.w	0x1dde <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x21a
    1bc4:      	cmp.w	r3, r0, lsr #16
    1bc8:      	bne	0x1bd8 <compiler_rt.int.__udivmoddi4+0x208> @ imm = #0xc
    1bca:      	mul	r11, r0, r12
    1bce:      	orr.w	r6, r10, r2, lsl #16
    1bd2:      	cmp	r11, r6
    1bd4:      	bls.w	0x1dde <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x206
    1bd8:      	add	r2, r4
    1bda:      	cmp.w	r3, r2, lsr #16
    1bde:      	sub.w	r0, r5, #0x2
    1be2:      	bne.w	0x1dde <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1f8
    1be6:      	cmp.w	r3, r0, lsr #16
    1bea:      	bne	0x1bfa <compiler_rt.int.__udivmoddi4+0x22a> @ imm = #0xc
    1bec:      	mul	r11, r0, r12
    1bf0:      	orr.w	r6, r10, r2, lsl #16
    1bf4:      	cmp	r11, r6
    1bf6:      	bls.w	0x1dde <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1e4
    1bfa:      	add	r2, r4
    1bfc:      	cmp.w	r3, r2, lsr #16
    1c00:      	sub.w	r0, r5, #0x3
    1c04:      	bne.w	0x1dde <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1d6
    1c08:      	cmp.w	r3, r0, lsr #16
    1c0c:      	bne	0x1b94 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x7c
    1c0e:      	mul	r11, r0, r12
    1c12:      	orr.w	r6, r10, r2, lsl #16
    1c16:      	cmp	r11, r6
    1c18:      	bhi	0x1b94 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x88
    1c1a:      	b	0x1dde <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1c0
    1c1c:      	mov	r2, r1
    1c1e:      	lsrs	r4, r5, #0x10
    1c20:      	udiv	r6, r2, r4
    1c24:      	mov	r11, r5
    1c26:      	uxth.w	r9, r5
    1c2a:      	mls	r5, r6, r4, r2
    1c2e:      	lsr.w	r8, r0, #0x10
    1c32:      	uxth.w	r12, r0
    1c36:      	mov	r1, r2
    1c38:      	movs	r3, #0x0
    1c3a:      	b	0x1c4a <compiler_rt.int.__udivmoddi4+0x27a> @ imm = #0xc
    1c3c:      	subs	r0, r6, #0x4
    1c3e:      	adds	r5, r2, r4
    1c40:      	cmp.w	r3, r5, lsr #16
    1c44:      	mov	r6, r0
    1c46:      	bne.w	0x1e76 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x22c
    1c4a:      	cmp.w	r3, r6, lsr #16
    1c4e:      	bne	0x1c5e <compiler_rt.int.__udivmoddi4+0x28e> @ imm = #0xc
    1c50:      	mul	r0, r6, r9
    1c54:      	orr.w	r2, r8, r5, lsl #16
    1c58:      	cmp	r0, r2
    1c5a:      	bls.w	0x1e74 <compiler_rt.int.__udivmoddi4+0x4a4> @ imm = #0x216
    1c5e:      	adds	r2, r5, r4
    1c60:      	cmp.w	r3, r2, lsr #16
    1c64:      	sub.w	r0, r6, #0x1
    1c68:      	bne.w	0x1e76 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x20a
    1c6c:      	cmp.w	r3, r0, lsr #16
    1c70:      	bne	0x1c80 <compiler_rt.int.__udivmoddi4+0x2b0> @ imm = #0xc
    1c72:      	mul	r10, r0, r9
    1c76:      	orr.w	r5, r8, r2, lsl #16
    1c7a:      	cmp	r10, r5
    1c7c:      	bls.w	0x1e76 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1f6
    1c80:      	add	r2, r4
    1c82:      	cmp.w	r3, r2, lsr #16
    1c86:      	sub.w	r0, r6, #0x2
    1c8a:      	bne.w	0x1e76 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1e8
    1c8e:      	cmp.w	r3, r0, lsr #16
    1c92:      	bne	0x1ca2 <compiler_rt.int.__udivmoddi4+0x2d2> @ imm = #0xc
    1c94:      	mul	r10, r0, r9
    1c98:      	orr.w	r5, r8, r2, lsl #16
    1c9c:      	cmp	r10, r5
    1c9e:      	bls.w	0x1e76 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1d4
    1ca2:      	add	r2, r4
    1ca4:      	cmp.w	r3, r2, lsr #16
    1ca8:      	sub.w	r0, r6, #0x3
    1cac:      	bne.w	0x1e76 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1c6
    1cb0:      	cmp.w	r3, r0, lsr #16
    1cb4:      	bne	0x1c3c <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x7c
    1cb6:      	mul	r10, r0, r9
    1cba:      	orr.w	r5, r8, r2, lsl #16
    1cbe:      	cmp	r10, r5
    1cc0:      	bhi	0x1c3c <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x88
    1cc2:      	b	0x1e76 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1b0
    1cc4:      	mov	r6, r4
    1cc6:      	orr.w	r2, r11, r0, lsl #16
    1cca:      	ldr	r0, [sp]
    1ccc:      	ldr.w	r9, [sp, #0x4]
    1cd0:      	mls	r2, r6, r0, r2
    1cd4:      	mov.w	r8, #0x0
    1cd8:      	udiv	r4, r2, lr
    1cdc:      	mls	r2, r4, lr, r2
    1ce0:      	b	0x1cf0 <compiler_rt.int.__udivmoddi4+0x320> @ imm = #0xc
    1ce2:      	nop
    1ce4:      	subs	r4, #0x4
    1ce6:      	add	r2, lr
    1ce8:      	cmp.w	r2, #0x10000
    1cec:      	mov	r5, r4
    1cee:      	bhs	0x1d62 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x70
    1cf0:      	cmp.w	r8, r4, lsr #16
    1cf4:      	bne	0x1d02 <compiler_rt.int.__udivmoddi4+0x332> @ imm = #0xa
    1cf6:      	mul	r1, r4, r12
    1cfa:      	orr.w	r5, r3, r2, lsl #16
    1cfe:      	cmp	r1, r5
    1d00:      	bls	0x1d60 <compiler_rt.int.__udivmoddi4+0x390> @ imm = #0x5c
    1d02:      	add	r2, lr
    1d04:      	cmp.w	r8, r2, lsr #16
    1d08:      	sub.w	r5, r4, #0x1
    1d0c:      	bne	0x1d62 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x52
    1d0e:      	cmp.w	r8, r5, lsr #16
    1d12:      	bne	0x1d20 <compiler_rt.int.__udivmoddi4+0x350> @ imm = #0xa
    1d14:      	mul	r1, r5, r12
    1d18:      	orr.w	r0, r3, r2, lsl #16
    1d1c:      	cmp	r1, r0
    1d1e:      	bls	0x1d62 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x40
    1d20:      	add	r2, lr
    1d22:      	cmp.w	r8, r2, lsr #16
    1d26:      	sub.w	r5, r4, #0x2
    1d2a:      	bne	0x1d62 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x34
    1d2c:      	cmp.w	r8, r5, lsr #16
    1d30:      	bne	0x1d3e <compiler_rt.int.__udivmoddi4+0x36e> @ imm = #0xa
    1d32:      	mul	r0, r5, r12
    1d36:      	orr.w	r1, r3, r2, lsl #16
    1d3a:      	cmp	r0, r1
    1d3c:      	bls	0x1d62 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x22
    1d3e:      	add	r2, lr
    1d40:      	cmp.w	r8, r2, lsr #16
    1d44:      	sub.w	r5, r4, #0x3
    1d48:      	bne	0x1d62 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x16
    1d4a:      	cmp.w	r8, r5, lsr #16
    1d4e:      	bne	0x1ce4 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x6e
    1d50:      	mul	r0, r5, r12
    1d54:      	orr.w	r1, r3, r2, lsl #16
    1d58:      	cmp	r0, r1
    1d5a:      	bhi	0x1ce4 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x7a
    1d5c:      	b	0x1d62 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x2
    1d5e:      	nop
    1d60:      	mov	r5, r4
    1d62:      	add.w	r0, r5, r6, lsl #16
    1d66:      	ldr	r2, [sp, #0x10]
    1d68:      	ldr	r6, [sp, #0x8]
    1d6a:      	umull	r4, r1, r2, r0
    1d6e:      	mov	r8, r0
    1d70:      	umull	r0, r3, r6, r0
    1d74:      	adds	r5, r0, r1
    1d76:      	mov.w	r12, #0x0
    1d7a:      	adc	r0, r12, #0x0
    1d7e:      	orrs.w	r1, r3, r0
    1d82:      	ldr	r3, [r7, #0x8]
    1d84:      	ldr.w	lr, [sp, #0xc]
    1d88:      	strb.w	r0, [sp, #0x14]
    1d8c:      	bne	0x1d98 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x8
    1d8e:      	cmp	r5, lr
    1d90:      	bhi	0x1d98 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x4
    1d92:      	bne	0x1dae <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x18
    1d94:      	cmp	r4, r9
    1d96:      	bls	0x1dae <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x14
    1d98:      	subs	r4, r4, r2
    1d9a:      	adc	r0, r12, #0x0
    1d9e:      	eor	r0, r0, #0x1
    1da2:      	strb.w	r0, [sp, #0x18]
    1da6:      	add	r0, r6
    1da8:      	sub.w	r8, r8, #0x1
    1dac:      	subs	r5, r5, r0
    1dae:      	cbz	r3, 0x1dce <compiler_rt.int.__udivmoddi4+0x3fe> @ imm = #0x1c
    1db0:      	subs.w	r0, r9, r4
    1db4:      	mov.w	r1, #0x0
    1db8:      	adc	r1, r1, #0x0
    1dbc:      	eor	r1, r1, #0x1
    1dc0:      	strb.w	r1, [sp, #0x1c]
    1dc4:      	add	r1, r5
    1dc6:      	sub.w	r1, lr, r1
    1dca:      	strd	r0, r1, [r3]
    1dce:      	movs	r1, #0x0
    1dd0:      	mov	r0, r8
    1dd2:      	add	sp, #0x20
    1dd4:      	pop.w	{r8, r9, r10, r11}
    1dd8:      	pop	{r4, r5, r6, r7, pc}
    1dda:      	nop
    1ddc:      	mov	r0, r5
    1dde:      	ldr	r3, [sp, #0x10]
    1de0:      	orr.w	r2, r10, r8, lsl #16
    1de4:      	mls	r8, r0, r3, r2
    1de8:      	mov.w	r10, #0x0
    1dec:      	udiv	r3, r8, r4
    1df0:      	mls	r5, r3, r4, r8
    1df4:      	b	0x1e06 <compiler_rt.int.__udivmoddi4+0x436> @ imm = #0xe
    1df6:      	nop
    1df8:      	subs	r3, #0x4
    1dfa:      	adds	r5, r2, r4
    1dfc:      	cmp.w	r5, #0x10000
    1e00:      	mov	r6, r3
    1e02:      	bhs.w	0x1f0a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x104
    1e06:      	cmp.w	r10, r3, lsr #16
    1e0a:      	bne	0x1e18 <compiler_rt.int.__udivmoddi4+0x448> @ imm = #0xa
    1e0c:      	mul	r2, r3, r12
    1e10:      	orr.w	r6, r9, r5, lsl #16
    1e14:      	cmp	r2, r6
    1e16:      	bls	0x1f08 <compiler_rt.int.__udivmoddi4+0x538> @ imm = #0xee
    1e18:      	adds	r2, r5, r4
    1e1a:      	cmp.w	r10, r2, lsr #16
    1e1e:      	sub.w	r6, r3, #0x1
    1e22:      	bne	0x1f0a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xe4
    1e24:      	cmp.w	r10, r6, lsr #16
    1e28:      	bne	0x1e36 <compiler_rt.int.__udivmoddi4+0x466> @ imm = #0xa
    1e2a:      	mul	r11, r6, r12
    1e2e:      	orr.w	r5, r9, r2, lsl #16
    1e32:      	cmp	r11, r5
    1e34:      	bls	0x1f0a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xd2
    1e36:      	add	r2, r4
    1e38:      	cmp.w	r10, r2, lsr #16
    1e3c:      	sub.w	r6, r3, #0x2
    1e40:      	bne	0x1f0a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xc6
    1e42:      	cmp.w	r10, r6, lsr #16
    1e46:      	bne	0x1e54 <compiler_rt.int.__udivmoddi4+0x484> @ imm = #0xa
    1e48:      	mul	r11, r6, r12
    1e4c:      	orr.w	r5, r9, r2, lsl #16
    1e50:      	cmp	r11, r5
    1e52:      	bls	0x1f0a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xb4
    1e54:      	add	r2, r4
    1e56:      	cmp.w	r10, r2, lsr #16
    1e5a:      	sub.w	r6, r3, #0x3
    1e5e:      	bne	0x1f0a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xa8
    1e60:      	cmp.w	r10, r6, lsr #16
    1e64:      	bne	0x1df8 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x70
    1e66:      	mul	r11, r6, r12
    1e6a:      	orr.w	r5, r9, r2, lsl #16
    1e6e:      	cmp	r11, r5
    1e70:      	bhi	0x1df8 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x7c
    1e72:      	b	0x1f0a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x94
    1e74:      	mov	r0, r6
    1e76:      	orr.w	r1, r8, r1, lsl #16
    1e7a:      	mls	r8, r0, r11, r1
    1e7e:      	mov.w	r10, #0x0
    1e82:      	udiv	r1, r8, r4
    1e86:      	mls	r5, r1, r4, r8
    1e8a:      	b	0x1e98 <compiler_rt.int.__udivmoddi4+0x4c8> @ imm = #0xa
    1e8c:      	subs	r1, #0x4
    1e8e:      	adds	r5, r2, r4
    1e90:      	cmp.w	r5, #0x10000
    1e94:      	mov	r6, r1
    1e96:      	bhs	0x1f1e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x84
    1e98:      	cmp.w	r10, r1, lsr #16
    1e9c:      	bne	0x1eaa <compiler_rt.int.__udivmoddi4+0x4da> @ imm = #0xa
    1e9e:      	mul	r2, r1, r9
    1ea2:      	orr.w	r6, r12, r5, lsl #16
    1ea6:      	cmp	r2, r6
    1ea8:      	bls	0x1f1c <compiler_rt.int.__udivmoddi4+0x54c> @ imm = #0x70
    1eaa:      	adds	r2, r5, r4
    1eac:      	cmp.w	r10, r2, lsr #16
    1eb0:      	sub.w	r6, r1, #0x1
    1eb4:      	bne	0x1f1e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x66
    1eb6:      	cmp.w	r10, r6, lsr #16
    1eba:      	bne	0x1ec8 <compiler_rt.int.__udivmoddi4+0x4f8> @ imm = #0xa
    1ebc:      	mul	r5, r6, r9
    1ec0:      	orr.w	r3, r12, r2, lsl #16
    1ec4:      	cmp	r5, r3
    1ec6:      	bls	0x1f1e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x54
    1ec8:      	add	r2, r4
    1eca:      	cmp.w	r10, r2, lsr #16
    1ece:      	sub.w	r6, r1, #0x2
    1ed2:      	bne	0x1f1e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x48
    1ed4:      	cmp.w	r10, r6, lsr #16
    1ed8:      	bne	0x1ee6 <compiler_rt.int.__udivmoddi4+0x516> @ imm = #0xa
    1eda:      	mul	r3, r6, r9
    1ede:      	orr.w	r5, r12, r2, lsl #16
    1ee2:      	cmp	r3, r5
    1ee4:      	bls	0x1f1e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x36
    1ee6:      	add	r2, r4
    1ee8:      	cmp.w	r10, r2, lsr #16
    1eec:      	sub.w	r6, r1, #0x3
    1ef0:      	bne	0x1f1e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x2a
    1ef2:      	cmp.w	r10, r6, lsr #16
    1ef6:      	bne	0x1e8c <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x6e
    1ef8:      	mul	r3, r6, r9
    1efc:      	orr.w	r5, r12, r2, lsl #16
    1f00:      	cmp	r3, r5
    1f02:      	bhi	0x1e8c <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x7a
    1f04:      	b	0x1f1e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x16
    1f06:      	nop
    1f08:      	mov	r6, r3
    1f0a:      	ldr	r3, [sp, #0x10]
    1f0c:      	orr.w	r2, r9, r8, lsl #16
    1f10:      	mls	r2, r6, r3, r2
    1f14:      	lsr.w	r2, r2, lr
    1f18:      	b	0x1f2c <compiler_rt.int.__udivmoddi4+0x55c> @ imm = #0x10
    1f1a:      	nop
    1f1c:      	mov	r6, r1
    1f1e:      	orr.w	r1, r12, r8, lsl #16
    1f22:      	mls	r1, r6, r11, r1
    1f26:      	lsr.w	r2, r1, lr
    1f2a:      	movs	r1, #0x0
    1f2c:      	ldr	r5, [r7, #0x8]
    1f2e:      	add.w	r0, r6, r0, lsl #16
    1f32:      	cmp	r5, #0x0
    1f34:      	itt	ne
    1f36:      	movne	r3, #0x0
    1f38:      	strdne	r2, r3, [r5]
    1f3c:      	add	sp, #0x20
    1f3e:      	pop.w	{r8, r9, r10, r11}
    1f42:      	pop	{r4, r5, r6, r7, pc}
    1f44:      	bmi	0x1ef0 <compiler_rt.int.__udivmoddi4+0x520> @ imm = #-0x58
    1f46:      	bmi	0x1ef2 <compiler_rt.int.__udivmoddi4+0x522> @ imm = #-0x58
    1f48:      	bmi	0x1ef4 <compiler_rt.int.__udivmoddi4+0x524> @ imm = #-0x58
    1f4a:      	bmi	0x1ef6 <compiler_rt.int.__udivmoddi4+0x526> @ imm = #-0x58
    1f4c:      	bmi	0x1ef8 <compiler_rt.int.__udivmoddi4+0x528> @ imm = #-0x58
    1f4e:      	bmi	0x1efa <compiler_rt.int.__udivmoddi4+0x52a> @ imm = #-0x58

00001f50 <.L.str.1>:
    1f50: 00 00 00 00 00 00 00 00         ........
    1f58: 10 00 00 00 00 00 00 00         ........
    1f60: 69 6e 74 65 67 65 72 20         integer 
    1f68: 6f 76 65 72 66 6c 6f 77         overflow
    1f70: 00 00 00 00 00 00 00 00         ........
    1f78: d4 d4 d4 d4 d4 d4 d4 d4         ........

00001f80 <.L.str.3>:
    1f80: 00 00 00 00 00 00 00 00         ........
    1f88: 13 00 00 00 00 00 00 00         ........
    1f90: 69 6e 64 65 78 20 6f 75         index ou
    1f98: 74 20 6f 66 20 62 6f 75         t of bou
    1fa0: 6e 64 73 00 00 00 00 00         nds.....
    1fa8: d4 d4 d4 d4 d4 d4 d4 d4         ........

00001fb0 <.L.str.4>:
    1fb0: 00 00 00 00 00 00 00 00         ........
    1fb8: 00 00 00 00 00 00 00 00         ........
    1fc0: 00 00 00 00 00 00 00 00         ........
    1fc8: d4 d4 d4 d4 d4 d4 d4 d4         ........
    1fd0: 00 00 00 00 00 00 00 00         ........
    1fd8: 0d 00 00 00 00 00 00 00         ........
    1fe0: 69 73 6f 72 74 20 72 65         isort re
    1fe8: 73 75 6c 74 3d 00 00 00         sult=...

00001ff0 <.L.str.6>:
    1ff0: 00 00 00 00 00 00 00 00         ........
    1ff8: 07 00 00 00 00 00 00 00         ........
    2000: 20 74 69 63 6b 73 3d 00          ticks=.
    2008: 6f 75 74 20 6f 66 20 6d         out of m
    2010: 65 6d 6f 72 79 00 68 61         emory.ha
    2018: 72 64 20 66 61 75 6c 74         rd fault
    2020: 00 20 61 6c 6c 6f 63 61         . alloca
    2028: 74 69 6f 6e 73 3d 00 20         tions=. 
    2030: 73 74 61 63 6b 3d 00 23         stack=.#
    2038: 7a 73 20 68 65 61 70 5f         zs heap_
    2040: 70 65 61 6b 3d 00 20 6c         peak=. l
    2048: 69 76 65 3d 00 20 68 65         ive=. he
    2050: 61 70 5f 72 65 73 65 72         ap_reser
    2058: 76 65 64 3d 00 70 61 6e         ved=.pan
    2060: 69 63 3a 20 00 0a 00 d4         ic: ....
