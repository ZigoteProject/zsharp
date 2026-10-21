
/tmp/tokens.elf:	file format elf32-littlearm

Disassembly of section .text:

00000000 <vectors>:
       0: 00 00 40 20 f1 11 00 00         ..@ ....
       8: 39 13 00 00 39 13 00 00         9...9...
      10: 39 13 00 00 39 13 00 00         9...9...
      18: 39 13 00 00 00 00 00 00         9.......
      20: 00 00 00 00 00 00 00 00         ........
      28: 00 00 00 00 39 13 00 00         ....9...
      30: 39 13 00 00 00 00 00 00         9.......
      38: 39 13 00 00 49 13 00 00         9...I...

00000040 <main>:
      40:      	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
      44:      	sub	sp, #0x1c
      46:      	bl	0x11e8 <zs_set_args>    @ imm = #0x119e
      4a:      	mov.w	r0, #0x810
      4e:      	movs	r1, #0x0
      50:      	movs	r4, #0x0
      52:      	bl	0x5c8 <zs_alloc>        @ imm = #0x572
      56:      	mov	r10, r0
      58:      	movs	r1, #0x1
      5a:      	mov.w	r0, #0x800
      5e:      	strd	r1, r4, [r10]
      62:      	strd	r0, r4, [r10, #8]
      66:      	add.w	r0, r10, #0x10
      6a:      	mov.w	r1, #0x800
      6e:      	movs	r2, #0x20
      70:      	bl	0x1838 <compiler_rt.arm.__aeabi_memset> @ imm = #0x17c4
      74:      	movw	r5, #0x1ec0
      78:      	movw	r3, #0x29e5
      7c:      	movs	r7, #0x37
      7e:      	movt	r5, #0x0
      82:      	mov.w	r9, #0x0
      86:      	mov.w	r11, #0x0
      8a:      	nop
      8c:      	uxth.w	r0, r9
      90:      	muls	r0, r3, r0
      92:      	sub.w	r1, r9, r0, lsr #16
      96:      	uxth	r1, r1
      98:      	lsrs	r1, r1, #0x1
      9a:      	add.w	r0, r1, r0, lsr #16
      9e:      	lsrs	r0, r0, #0x5
      a0:      	mls	r0, r0, r7, r9
      a4:      	movs	r3, #0x0
      a6:      	uxth	r2, r0
      a8:      	mov	r0, r5
      aa:      	movw	r4, #0x29e5
      ae:      	bl	0xe68 <zs_str_byte>     @ imm = #0xdb6
      b2:      	ldrd	r1, r2, [r10]
      b6:      	mov	r6, r0
      b8:      	eor	r1, r1, #0x1
      bc:      	orrs	r1, r2
      be:      	mov	r8, r10
      c0:      	bne	0xc8 <main+0x88>        @ imm = #0x4
      c2:      	mov	r3, r4
      c4:      	b	0x11e <main+0xde>       @ imm = #0x56
      c6:      	nop
      c8:      	ldrd	r0, r1, [r8, #8]
      cc:      	mov	r4, r5
      ce:      	adds.w	r5, r0, #0x10
      d2:      	adc	r1, r1, #0x0
      d6:      	mov	r0, r5
      d8:      	movw	r10, #0x29e5
      dc:      	bl	0x5c8 <zs_alloc>        @ imm = #0x4e8
      e0:      	mov	r1, r8
      e2:      	mov	r2, r5
      e4:      	mov	r7, r0
      e6:      	bl	0x184c <compiler_rt.arm.__aeabi_memcpy> @ imm = #0x1762
      ea:      	movs	r0, #0x0
      ec:      	movs	r1, #0x1
      ee:      	strd	r1, r0, [r7]
      f2:      	ldrd	r1, r0, [r8]
      f6:      	orrs.w	r2, r1, r0
      fa:      	beq	0x116 <main+0xd6>       @ imm = #0x18
      fc:      	eor	r2, r1, #0x1
     100:      	orrs	r2, r0
     102:      	bne	0x10c <main+0xcc>       @ imm = #0x6
     104:      	mov	r0, r8
     106:      	bl	0x6b8 <zs_free>         @ imm = #0x5ae
     10a:      	b	0x116 <main+0xd6>       @ imm = #0x8
     10c:      	subs	r1, #0x1
     10e:      	sbc	r0, r0, #0x0
     112:      	strd	r1, r0, [r8]
     116:      	mov	r8, r7
     118:      	mov	r3, r10
     11a:      	movs	r7, #0x37
     11c:      	mov	r5, r4
     11e:      	ldrd	r0, r1, [r8, #8]
     122:      	subs.w	r0, r9, r0
     126:      	sbcs.w	r0, r11, r1
     12a:      	bhs.w	0x5aa <main+0x56a>      @ imm = #0x47c
     12e:      	adds.w	r0, r9, #0x1
     132:      	movw	r2, #0x7ff
     136:      	add.w	r4, r8, #0x10
     13a:      	adc	r1, r11, #0x0
     13e:      	subs.w	r2, r9, r2
     142:      	strb.w	r6, [r4, r9]
     146:      	sbcs	r2, r11, #0x0
     14a:      	mov	r9, r0
     14c:      	mov	r11, r1
     14e:      	mov	r10, r8
     150:      	blo	0x8c <main+0x4c>        @ imm = #-0xc8
     152:      	movw	r5, #0x1f68
     156:      	movt	r5, #0x0
     15a:      	bl	0x12e0 <zs_ticks>       @ imm = #0x1182
     15e:      	strd	r1, r0, [sp, #4]
     162:      	mov.w	r8, #0x0
     166:      	mov.w	r9, #0x0
     16a:      	movs	r0, #0x0
     16c:      	mov	r12, r10
     16e:      	strd	r0, r0, [sp, #12]
     172:      	strd	r0, r0, [sp, #20]
     176:      	b	0x19c <main+0x15c>      @ imm = #0x22
     178:      	mov	r0, r7
     17a:      	bl	0x6b8 <zs_free>         @ imm = #0x53a
     17e:      	mov	r12, r10
     180:      	adds.w	r0, r8, #0x1
     184:      	movw	r2, #0x7ff
     188:      	adc	r1, r9, #0x0
     18c:      	subs.w	r2, r8, r2
     190:      	sbcs	r2, r9, #0x0
     194:      	mov	r8, r0
     196:      	mov	r9, r1
     198:      	bhs.w	0x3d4 <main+0x394>      @ imm = #0x238
     19c:      	ldrd	r1, r0, [r5]
     1a0:      	mov	r7, r5
     1a2:      	orrs.w	r2, r1, r0
     1a6:      	beq	0x1b2 <main+0x172>      @ imm = #0x8
     1a8:      	adds	r1, #0x1
     1aa:      	adc	r0, r0, #0x0
     1ae:      	strd	r1, r0, [r7]
     1b2:      	ldrd	r0, r2, [r12]
     1b6:      	orrs.w	r1, r0, r2
     1ba:      	beq	0x1e4 <main+0x1a4>      @ imm = #0x26
     1bc:      	ldrd	r1, r5, [r12, #8]
     1c0:      	adds	r3, r0, #0x1
     1c2:      	adc	r6, r2, #0x0
     1c6:      	subs.w	r1, r8, r1
     1ca:      	sbcs.w	r1, r9, r5
     1ce:      	strd	r3, r6, [r12]
     1d2:      	bhs.w	0x5aa <main+0x56a>      @ imm = #0x3d4
     1d6:      	ldrb.w	r1, [r4, r8]
     1da:      	orrs	r3, r6
     1dc:      	it	ne
     1de:      	strdne	r0, r2, [r12]
     1e2:      	b	0x1f8 <main+0x1b8>      @ imm = #0x12
     1e4:      	ldrd	r0, r1, [r12, #8]
     1e8:      	subs.w	r0, r8, r0
     1ec:      	sbcs.w	r0, r9, r1
     1f0:      	bhs.w	0x5aa <main+0x56a>      @ imm = #0x3b6
     1f4:      	ldrb.w	r1, [r4, r8]
     1f8:      	ldr	r2, [r7, #0x8]
     1fa:      	sub.w	r5, r1, #0x30
     1fe:      	cmp	r2, #0x1
     200:      	bne	0x224 <main+0x1e4>      @ imm = #0x20
     202:      	uxtb	r0, r5
     204:      	cmp	r0, #0x9
     206:      	bhi	0x224 <main+0x1e4>      @ imm = #0x1a
     208:      	ldrd	r6, r3, [r7]
     20c:      	ldrd	r2, r1, [r7, #16]
     210:      	orrs.w	r5, r6, r3
     214:      	beq	0x292 <main+0x252>      @ imm = #0x7a
     216:      	eor	r5, r6, #0x1
     21a:      	orrs	r5, r3
     21c:      	bne	0x288 <main+0x248>      @ imm = #0x68
     21e:      	mov	r5, r7
     220:      	b	0x294 <main+0x254>      @ imm = #0x70
     222:      	nop
     224:      	cmp	r2, #0x2
     226:      	sub.w	r11, r1, #0x7b
     22a:      	bne	0x264 <main+0x224>      @ imm = #0x36
     22c:      	uxtb.w	r0, r11
     230:      	cmp	r0, #0xe6
     232:      	blo	0x264 <main+0x224>      @ imm = #0x2e
     234:      	ldrd	r3, r2, [r7]
     238:      	ldrd	r1, r0, [r7, #16]
     23c:      	orrs.w	r6, r3, r2
     240:      	beq	0x312 <main+0x2d2>      @ imm = #0xce
     242:      	eor	r6, r3, #0x1
     246:      	orrs	r6, r2
     248:      	bne	0x308 <main+0x2c8>      @ imm = #0xbc
     24a:      	adds	r6, r1, #0x1
     24c:      	adc	r11, r0, #0x0
     250:      	eor.w	r1, r0, r11
     254:      	bics.w	r0, r1, r0
     258:      	bmi.w	0x5b8 <main+0x578>      @ imm = #0x35c
     25c:      	movs	r0, #0x2
     25e:      	mov	r5, r7
     260:      	b	0x3a4 <main+0x364>      @ imm = #0x140
     262:      	nop
     264:      	cmp	r2, #0x1
     266:      	beq	0x2d0 <main+0x290>      @ imm = #0x66
     268:      	ldrd	r1, r0, [r7]
     26c:      	cmp	r2, #0x2
     26e:      	bne	0x2f0 <main+0x2b0>      @ imm = #0x7e
     270:      	orrs.w	r2, r1, r0
     274:      	beq	0x348 <main+0x308>      @ imm = #0xd0
     276:      	eor	r2, r1, #0x1
     27a:      	orrs	r2, r0
     27c:      	bne	0x33e <main+0x2fe>      @ imm = #0xbe
     27e:      	mov	r0, r7
     280:      	bl	0x6b8 <zs_free>         @ imm = #0x434
     284:      	mov	r12, r10
     286:      	b	0x348 <main+0x308>      @ imm = #0xbe
     288:      	subs	r6, #0x1
     28a:      	sbc	r3, r3, #0x0
     28e:      	strd	r6, r3, [r7]
     292:      	movs	r5, #0x0
     294:      	movs	r4, #0xa
     296:      	umull	r3, r2, r2, r4
     29a:      	movs	r6, #0x0
     29c:      	smlal	r2, r6, r1, r4
     2a0:      	asrs	r1, r6, #0x1f
     2a2:      	eor.w	r1, r1, r2, asr #31
     2a6:      	eor.w	r6, r6, r2, asr #31
     2aa:      	orrs	r1, r6
     2ac:      	bne.w	0x5b8 <main+0x578>      @ imm = #0x308
     2b0:      	adds	r6, r3, r0
     2b2:      	adc	r11, r2, #0x0
     2b6:      	eor.w	r0, r2, r11
     2ba:      	bics	r0, r2
     2bc:      	cmp.w	r0, #0xffffffff
     2c0:      	ble.w	0x5b8 <main+0x578>      @ imm = #0x2f4
     2c4:      	cmp	r5, #0x0
     2c6:      	add.w	r4, r12, #0x10
     2ca:      	beq	0x380 <main+0x340>      @ imm = #0xb2
     2cc:      	movs	r0, #0x1
     2ce:      	b	0x3a4 <main+0x364>      @ imm = #0xd2
     2d0:      	ldr	r0, [sp, #0x18]
     2d2:      	ldr	r1, [sp, #0x14]
     2d4:      	adds	r0, #0x1
     2d6:      	adc	r2, r1, #0x0
     2da:      	str	r0, [sp, #0x18]
     2dc:      	eor.w	r0, r1, r2
     2e0:      	bics	r0, r1
     2e2:      	cmp.w	r0, #0xffffffff
     2e6:      	ble.w	0x5b8 <main+0x578>      @ imm = #0x2ce
     2ea:      	ldrd	r1, r0, [r7]
     2ee:      	str	r2, [sp, #0x14]
     2f0:      	orrs.w	r2, r1, r0
     2f4:      	beq	0x364 <main+0x324>      @ imm = #0x6c
     2f6:      	eor	r2, r1, #0x1
     2fa:      	orrs	r2, r0
     2fc:      	bne	0x332 <main+0x2f2>      @ imm = #0x32
     2fe:      	mov	r0, r7
     300:      	bl	0x6b8 <zs_free>         @ imm = #0x3b4
     304:      	mov	r12, r10
     306:      	b	0x364 <main+0x324>      @ imm = #0x5a
     308:      	subs	r3, #0x1
     30a:      	sbc	r2, r2, #0x0
     30e:      	strd	r3, r2, [r7]
     312:      	adds	r6, r1, #0x1
     314:      	adc	r11, r0, #0x0
     318:      	eor.w	r1, r0, r11
     31c:      	bics.w	r0, r1, r0
     320:      	bmi.w	0x5b8 <main+0x578>      @ imm = #0x294
     324:      	movs	r0, #0x18
     326:      	movs	r1, #0x0
     328:      	bl	0x5c8 <zs_alloc>        @ imm = #0x29c
     32c:      	mov	r12, r10
     32e:      	mov	r5, r0
     330:      	b	0x3a2 <main+0x362>      @ imm = #0x6e
     332:      	subs	r1, #0x1
     334:      	sbc	r0, r0, #0x0
     338:      	strd	r1, r0, [r7]
     33c:      	b	0x364 <main+0x324>      @ imm = #0x24
     33e:      	subs	r1, #0x1
     340:      	sbc	r0, r0, #0x0
     344:      	strd	r1, r0, [r7]
     348:      	ldr	r0, [sp, #0x10]
     34a:      	ldr	r2, [sp, #0xc]
     34c:      	adds	r0, #0x1
     34e:      	str	r0, [sp, #0x10]
     350:      	adc	r0, r2, #0x0
     354:      	eor.w	r1, r2, r0
     358:      	bics	r1, r2
     35a:      	cmp.w	r1, #0xffffffff
     35e:      	ble.w	0x5b8 <main+0x578>      @ imm = #0x256
     362:      	str	r0, [sp, #0xc]
     364:      	uxtb	r6, r5
     366:      	cmp	r6, #0x9
     368:      	bls	0x37c <main+0x33c>      @ imm = #0x10
     36a:      	uxtb.w	r0, r11
     36e:      	cmp	r0, #0xe6
     370:      	bhs	0x390 <main+0x350>      @ imm = #0x1c
     372:      	movw	r5, #0x1f68
     376:      	movt	r5, #0x0
     37a:      	b	0x3b2 <main+0x372>      @ imm = #0x34
     37c:      	mov.w	r11, #0x0
     380:      	movs	r0, #0x18
     382:      	movs	r1, #0x0
     384:      	bl	0x5c8 <zs_alloc>        @ imm = #0x240
     388:      	mov	r12, r10
     38a:      	mov	r5, r0
     38c:      	movs	r0, #0x1
     38e:      	b	0x3a4 <main+0x364>      @ imm = #0x12
     390:      	movs	r0, #0x18
     392:      	movs	r1, #0x0
     394:      	mov.w	r11, #0x0
     398:      	bl	0x5c8 <zs_alloc>        @ imm = #0x22c
     39c:      	mov	r12, r10
     39e:      	mov	r5, r0
     3a0:      	movs	r6, #0x1
     3a2:      	movs	r0, #0x2
     3a4:      	movs	r1, #0x1
     3a6:      	str	r1, [r5]
     3a8:      	movs	r1, #0x0
     3aa:      	strd	r6, r11, [r5, #16]
     3ae:      	strd	r1, r0, [r5, #4]
     3b2:      	ldrd	r1, r0, [r7]
     3b6:      	orrs.w	r2, r1, r0
     3ba:      	beq.w	0x180 <main+0x140>      @ imm = #-0x23e
     3be:      	eor	r2, r1, #0x1
     3c2:      	orrs	r2, r0
     3c4:      	beq.w	0x178 <main+0x138>      @ imm = #-0x250
     3c8:      	subs	r1, #0x1
     3ca:      	sbc	r0, r0, #0x0
     3ce:      	strd	r1, r0, [r7]
     3d2:      	b	0x180 <main+0x140>      @ imm = #-0x256
     3d4:      	bl	0x12e0 <zs_ticks>       @ imm = #0xf08
     3d8:      	ldr	r2, [sp, #0x18]
     3da:      	mov.w	r7, #0x3e8
     3de:      	ldr	r6, [sp, #0x14]
     3e0:      	umull	r3, r2, r2, r7
     3e4:      	mov	r4, r0
     3e6:      	movs	r0, #0x0
     3e8:      	smlal	r2, r0, r6, r7
     3ec:      	asrs	r7, r0, #0x1f
     3ee:      	eor.w	r7, r7, r2, asr #31
     3f2:      	eor.w	r0, r0, r2, asr #31
     3f6:      	orrs	r0, r7
     3f8:      	bne.w	0x5b8 <main+0x578>      @ imm = #0x1bc
     3fc:      	ldr	r0, [sp, #0x10]
     3fe:      	mov	r11, r1
     400:      	ldr	r1, [sp, #0xc]
     402:      	adds	r0, r0, r3
     404:      	eor.w	r7, r2, r1
     408:      	adcs	r1, r2
     40a:      	eors	r2, r1
     40c:      	bics	r2, r7
     40e:      	cmp.w	r2, #0xffffffff
     412:      	ble.w	0x5b8 <main+0x578>      @ imm = #0x1a2
     416:      	bl	0xc40 <zs_str_of_i64>   @ imm = #0x826
     41a:      	mov	r7, r0
     41c:      	movw	r0, #0x1fa0
     420:      	movt	r0, #0x0
     424:      	mov	r1, r7
     426:      	bl	0x708 <zs_str_concat>   @ imm = #0x2de
     42a:      	ldrd	r2, r1, [r7]
     42e:      	mov	r6, r0
     430:      	orrs.w	r3, r2, r1
     434:      	beq	0x450 <main+0x410>      @ imm = #0x18
     436:      	eor	r0, r2, #0x1
     43a:      	orrs	r0, r1
     43c:      	bne	0x446 <main+0x406>      @ imm = #0x6
     43e:      	mov	r0, r7
     440:      	bl	0x6b8 <zs_free>         @ imm = #0x274
     444:      	b	0x450 <main+0x410>      @ imm = #0x8
     446:      	subs	r0, r2, #0x1
     448:      	sbc	r1, r1, #0x0
     44c:      	strd	r0, r1, [r7]
     450:      	movw	r1, #0x1fc0
     454:      	movt	r1, #0x0
     458:      	mov	r0, r6
     45a:      	bl	0x708 <zs_str_concat>   @ imm = #0x2aa
     45e:      	ldrd	r2, r1, [r6]
     462:      	mov	r7, r0
     464:      	orrs.w	r3, r2, r1
     468:      	beq	0x484 <main+0x444>      @ imm = #0x18
     46a:      	eor	r0, r2, #0x1
     46e:      	orrs	r0, r1
     470:      	bne	0x47a <main+0x43a>      @ imm = #0x6
     472:      	mov	r0, r6
     474:      	bl	0x6b8 <zs_free>         @ imm = #0x240
     478:      	b	0x484 <main+0x444>      @ imm = #0x8
     47a:      	subs	r0, r2, #0x1
     47c:      	sbc	r1, r1, #0x0
     480:      	strd	r0, r1, [r6]
     484:      	ldr	r0, [sp, #0x8]
     486:      	ldr	r1, [sp, #0x4]
     488:      	subs	r0, r4, r0
     48a:      	sbcs.w	r1, r11, r1
     48e:      	mov.w	r2, #0x0
     492:      	adc	r2, r2, #0x0
     496:      	eor	r2, r2, #0x1
     49a:      	cmp	r2, #0x1
     49c:      	beq.w	0x5b8 <main+0x578>      @ imm = #0x118
     4a0:      	bl	0x8f4 <zs_str_of_u64>   @ imm = #0x450
     4a4:      	mov	r6, r0
     4a6:      	mov	r0, r7
     4a8:      	mov	r1, r6
     4aa:      	bl	0x708 <zs_str_concat>   @ imm = #0x25a
     4ae:      	ldrd	r2, r1, [r7]
     4b2:      	mov	r8, r0
     4b4:      	orrs.w	r3, r2, r1
     4b8:      	beq	0x4d4 <main+0x494>      @ imm = #0x18
     4ba:      	eor	r0, r2, #0x1
     4be:      	orrs	r0, r1
     4c0:      	bne	0x4ca <main+0x48a>      @ imm = #0x6
     4c2:      	mov	r0, r7
     4c4:      	bl	0x6b8 <zs_free>         @ imm = #0x1f0
     4c8:      	b	0x4d4 <main+0x494>      @ imm = #0x8
     4ca:      	subs	r0, r2, #0x1
     4cc:      	sbc	r1, r1, #0x0
     4d0:      	strd	r0, r1, [r7]
     4d4:      	ldrd	r1, r0, [r6]
     4d8:      	orrs.w	r2, r1, r0
     4dc:      	beq	0x4f8 <main+0x4b8>      @ imm = #0x18
     4de:      	eor	r2, r1, #0x1
     4e2:      	orrs	r2, r0
     4e4:      	bne	0x4ee <main+0x4ae>      @ imm = #0x6
     4e6:      	mov	r0, r6
     4e8:      	bl	0x6b8 <zs_free>         @ imm = #0x1cc
     4ec:      	b	0x4f8 <main+0x4b8>      @ imm = #0x8
     4ee:      	subs	r1, #0x1
     4f0:      	sbc	r0, r0, #0x0
     4f4:      	strd	r1, r0, [r6]
     4f8:      	movw	r0, #0x1f80
     4fc:      	movt	r0, #0x0
     500:      	mov	r1, r8
     502:      	bl	0x708 <zs_str_concat>   @ imm = #0x202
     506:      	ldrd	r2, r1, [r8]
     50a:      	mov	r6, r0
     50c:      	orrs.w	r3, r2, r1
     510:      	beq	0x52c <main+0x4ec>      @ imm = #0x18
     512:      	eor	r0, r2, #0x1
     516:      	orrs	r0, r1
     518:      	bne	0x522 <main+0x4e2>      @ imm = #0x6
     51a:      	mov	r0, r8
     51c:      	bl	0x6b8 <zs_free>         @ imm = #0x198
     520:      	b	0x52c <main+0x4ec>      @ imm = #0x8
     522:      	subs	r0, r2, #0x1
     524:      	sbc	r1, r1, #0x0
     528:      	strd	r0, r1, [r8]
     52c:      	mov	r0, r6
     52e:      	bl	0xe90 <zs_println>      @ imm = #0x95e
     532:      	ldrd	r1, r3, [r6]
     536:      	mov	r0, r10
     538:      	orrs.w	r2, r1, r3
     53c:      	beq	0x55a <main+0x51a>      @ imm = #0x1a
     53e:      	eor	r2, r1, #0x1
     542:      	orrs	r2, r3
     544:      	bne	0x550 <main+0x510>      @ imm = #0x8
     546:      	mov	r0, r6
     548:      	bl	0x6b8 <zs_free>         @ imm = #0x16c
     54c:      	mov	r0, r10
     54e:      	b	0x55a <main+0x51a>      @ imm = #0x8
     550:      	subs	r1, #0x1
     552:      	sbc	r2, r3, #0x0
     556:      	strd	r1, r2, [r6]
     55a:      	ldrd	r1, r3, [r5]
     55e:      	orrs.w	r2, r1, r3
     562:      	beq	0x580 <main+0x540>      @ imm = #0x1a
     564:      	eor	r2, r1, #0x1
     568:      	orrs	r2, r3
     56a:      	bne	0x576 <main+0x536>      @ imm = #0x8
     56c:      	mov	r0, r5
     56e:      	bl	0x6b8 <zs_free>         @ imm = #0x146
     572:      	mov	r0, r10
     574:      	b	0x580 <main+0x540>      @ imm = #0x8
     576:      	subs	r1, #0x1
     578:      	sbc	r2, r3, #0x0
     57c:      	strd	r1, r2, [r5]
     580:      	ldrd	r1, r3, [r0]
     584:      	orrs.w	r2, r1, r3
     588:      	beq	0x5a2 <main+0x562>      @ imm = #0x16
     58a:      	eor	r2, r1, #0x1
     58e:      	orrs	r2, r3
     590:      	bne	0x598 <main+0x558>      @ imm = #0x4
     592:      	bl	0x6b8 <zs_free>         @ imm = #0x122
     596:      	b	0x5a2 <main+0x562>      @ imm = #0x8
     598:      	subs	r1, #0x1
     59a:      	sbc	r2, r3, #0x0
     59e:      	strd	r1, r2, [r0]
     5a2:      	movs	r0, #0x0
     5a4:      	add	sp, #0x1c
     5a6:      	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
     5aa:      	movw	r0, #0x1f40
     5ae:      	movt	r0, #0x0
     5b2:      	adds	r0, #0x10
     5b4:      	bl	0x68c <zs_panic_c>      @ imm = #0xd4
     5b8:      	movw	r0, #0x1f10
     5bc:      	movt	r0, #0x0
     5c0:      	adds	r0, #0x10
     5c2:      	bl	0x68c <zs_panic_c>      @ imm = #0xc6
     5c6:      	bmi	0x572 <main+0x532>      @ imm = #-0x58

000005c8 <zs_alloc>:
     5c8:      	push	{r4, r6, r7, lr}
     5ca:      	add	r7, sp, #0x8
     5cc:      	adds	r0, #0x7
     5ce:      	lsrs	r2, r0, #0x3
     5d0:      	cmp	r2, #0x20
     5d2:      	bhi	0x5f0 <zs_alloc+0x28>   @ imm = #0x1a
     5d4:      	movw	r12, #0x0
     5d8:      	movt	r12, #0x2000
     5dc:      	ldr.w	r1, [r12, r2, lsl #2]
     5e0:      	cbz	r1, 0x5f0 <zs_alloc+0x28> @ imm = #0xc
     5e2:      	mov	r0, r1
     5e4:      	ldr	r3, [r1]
     5e6:      	ldr	r1, [r0, #-8]!
     5ea:      	str.w	r3, [r12, r2, lsl #2]
     5ee:      	b	0x628 <zs_alloc+0x60>   @ imm = #0x36
     5f0:      	movw	r12, #0x84
     5f4:      	movt	r12, #0x2000
     5f8:      	ldr.w	r2, [r12]
     5fc:      	bic	r1, r0, #0x7
     600:      	adds	r3, r1, r2
     602:      	movw	r0, #0xfff9
     606:      	subs	r0, r3, r0
     608:      	cmn.w	r0, #0x10001
     60c:      	blo	0x67e <zs_alloc+0xb6>   @ imm = #0x6e
     60e:      	movw	lr, #0x88
     612:      	movt	lr, #0x2000
     616:      	add.w	r0, lr, r2
     61a:      	adds	r3, #0x8
     61c:      	str.w	r1, [lr, r2]
     620:      	movs	r2, #0x0
     622:      	str.w	r3, [r12]
     626:      	str	r2, [r0, #0x4]
     628:      	movw	lr, #0x88
     62c:      	movt	lr, #0x2001
     630:      	ldr.w	r2, [lr]
     634:      	movw	r12, #0x8c
     638:      	movt	r12, #0x2001
     63c:      	ldr.w	r3, [r12]
     640:      	add	r1, r2
     642:      	str.w	r1, [lr]
     646:      	movw	lr, #0x90
     64a:      	cmp	r1, r3
     64c:      	it	hi
     64e:      	strhi.w	r1, [r12]
     652:      	movt	lr, #0x2001
     656:      	movw	r12, #0x98
     65a:      	ldrd	r2, r3, [lr]
     65e:      	movt	r12, #0x2001
     662:      	ldrd	r1, r4, [r12]
     666:      	adds	r2, #0x1
     668:      	adc	r3, r3, #0x0
     66c:      	adds	r1, #0x1
     66e:      	strd	r2, r3, [lr]
     672:      	adc	r2, r4, #0x0
     676:      	adds	r0, #0x8
     678:      	strd	r1, r2, [r12]
     67c:      	pop	{r4, r6, r7, pc}
     67e:      	movw	r0, #0x1fd8
     682:      	movt	r0, #0x0
     686:      	bl	0x68c <zs_panic_c>      @ imm = #0x2
     68a:      	bmi	0x636 <zs_alloc+0x6e>   @ imm = #-0x58

0000068c <zs_panic_c>:
     68c:      	push	{r4, r6, r7, lr}
     68e:      	add	r7, sp, #0x8
     690:      	mov	r4, r0
     692:      	movw	r0, #0x2047
     696:      	movt	r0, #0x0
     69a:      	bl	0xfa8 <write_c>         @ imm = #0x90a
     69e:      	mov	r0, r4
     6a0:      	bl	0xfa8 <write_c>         @ imm = #0x904
     6a4:      	movw	r0, #0x204f
     6a8:      	movt	r0, #0x0
     6ac:      	bl	0xfa8 <write_c>         @ imm = #0x8f8
     6b0:      	movs	r0, #0x86
     6b2:      	bl	0x10ec <stop>           @ imm = #0xa36
     6b6:      	bmi	0x662 <zs_alloc+0x9a>   @ imm = #-0x58

000006b8 <zs_free>:
     6b8:      	push	{r4, r6, r7, lr}
     6ba:      	add	r7, sp, #0x8
     6bc:      	movw	lr, #0x88
     6c0:      	movw	r12, #0x90
     6c4:      	movt	lr, #0x2001
     6c8:      	movt	r12, #0x2001
     6cc:      	ldr	r1, [r0, #-8]
     6d0:      	ldr.w	r3, [lr]
     6d4:      	ldrd	r2, r4, [r12]
     6d8:      	subs	r3, r3, r1
     6da:      	subs	r2, #0x1
     6dc:      	str.w	r3, [lr]
     6e0:      	sbc	r3, r4, #0x0
     6e4:      	lsrs	r4, r1, #0x3
     6e6:      	cmp	r4, #0x20
     6e8:      	strd	r2, r3, [r12]
     6ec:      	it	hi
     6ee:      	pophi	{r4, r6, r7, pc}
     6f0:      	mvn	r2, #0x3
     6f4:      	and.w	r1, r2, r1, lsr #1
     6f8:      	movw	r2, #0x0
     6fc:      	movt	r2, #0x2000
     700:      	ldr	r3, [r2, r1]
     702:      	str	r3, [r0]
     704:      	str	r0, [r2, r1]
     706:      	pop	{r4, r6, r7, pc}

00000708 <zs_str_concat>:
     708:      	push	{r4, r5, r6, r7, lr}
     70a:      	add	r7, sp, #0xc
     70c:      	push.w	{r8, r9, r10}
     710:      	mov	lr, r0
     712:      	ldrd	r0, r3, [r0, #8]
     716:      	ldrd	r2, r6, [r1, #8]
     71a:      	adds.w	r9, r2, r0
     71e:      	add.w	r0, r9, #0x18
     722:      	lsr.w	r4, r0, #0x3
     726:      	adc.w	r12, r6, r3
     72a:      	cmp	r4, #0x20
     72c:      	bhi	0x74a <zs_str_concat+0x42> @ imm = #0x1a
     72e:      	movw	r5, #0x0
     732:      	movt	r5, #0x2000
     736:      	ldr.w	r6, [r5, r4, lsl #2]
     73a:      	cbz	r6, 0x74a <zs_str_concat+0x42> @ imm = #0xc
     73c:      	mov	r10, r6
     73e:      	ldr	r6, [r6]
     740:      	ldr	r0, [r10, #-8]!
     744:      	str.w	r6, [r5, r4, lsl #2]
     748:      	b	0x784 <zs_str_concat+0x7c> @ imm = #0x38
     74a:      	movw	r8, #0x84
     74e:      	movt	r8, #0x2000
     752:      	ldr.w	r4, [r8]
     756:      	bic	r0, r0, #0x7
     75a:      	adds	r6, r0, r4
     75c:      	movw	r3, #0xfff9
     760:      	subs	r3, r6, r3
     762:      	cmn.w	r3, #0x10001
     766:      	blo.w	0x8e6 <zs_str_concat+0x1de> @ imm = #0x17c
     76a:      	movw	r5, #0x88
     76e:      	movt	r5, #0x2000
     772:      	add.w	r10, r5, r4
     776:      	adds	r6, #0x8
     778:      	str	r0, [r5, r4]
     77a:      	movs	r4, #0x0
     77c:      	str.w	r6, [r8]
     780:      	str.w	r4, [r10, #0x4]
     784:      	movw	r5, #0x88
     788:      	movt	r5, #0x2001
     78c:      	movw	r4, #0x8c
     790:      	ldr	r6, [r5]
     792:      	movt	r4, #0x2001
     796:      	ldr	r2, [r4]
     798:      	add	r0, r6
     79a:      	cmp	r0, r2
     79c:      	str	r0, [r5]
     79e:      	it	hi
     7a0:      	strhi	r0, [r4]
     7a2:      	movw	r0, #0x90
     7a6:      	movt	r0, #0x2001
     7aa:      	ldrd	r2, r4, [r0]
     7ae:      	movw	r5, #0x98
     7b2:      	movt	r5, #0x2001
     7b6:      	adds	r2, #0x1
     7b8:      	ldrd	r6, r3, [r5]
     7bc:      	adc	r4, r4, #0x0
     7c0:      	strd	r2, r4, [r0]
     7c4:      	adds	r0, r6, #0x1
     7c6:      	adc	r2, r3, #0x0
     7ca:      	strd	r0, r2, [r5]
     7ce:      	movs	r2, #0x1
     7d0:      	mov	r0, r10
     7d2:      	str	r2, [r0, #8]!
     7d6:      	movs	r5, #0x0
     7d8:      	adds	r2, r0, #0x4
     7da:      	stm.w	r2, {r5, r9, r12}
     7de:      	add.w	r12, r0, #0x10
     7e2:      	strb.w	r5, [r12, r9]
     7e6:      	ldr.w	r4, [lr, #0x8]
     7ea:      	cmp	r4, #0x0
     7ec:      	beq	0x870 <zs_str_concat+0x168> @ imm = #0x80
     7ee:      	ands	r2, r4, #0x3
     7f2:      	beq	0x810 <zs_str_concat+0x108> @ imm = #0x1a
     7f4:      	ldrb.w	r3, [lr, #0x10]
     7f8:      	cmp	r2, #0x1
     7fa:      	strb.w	r3, [r10, #0x18]
     7fe:      	bne	0x81e <zs_str_concat+0x116> @ imm = #0x1c
     800:      	subs	r2, r4, #0x1
     802:      	add.w	r5, lr, #0x11
     806:      	add.w	r6, r10, #0x19
     80a:      	cmp	r4, #0x4
     80c:      	bhs	0x850 <zs_str_concat+0x148> @ imm = #0x40
     80e:      	b	0x86c <zs_str_concat+0x164> @ imm = #0x5a
     810:      	add.w	r5, lr, #0x10
     814:      	mov	r6, r12
     816:      	mov	r2, r4
     818:      	cmp	r4, #0x4
     81a:      	bhs	0x850 <zs_str_concat+0x148> @ imm = #0x32
     81c:      	b	0x86c <zs_str_concat+0x164> @ imm = #0x4c
     81e:      	ldrb.w	r3, [lr, #0x11]
     822:      	cmp	r2, #0x2
     824:      	strb.w	r3, [r10, #0x19]
     828:      	bne	0x83a <zs_str_concat+0x132> @ imm = #0xe
     82a:      	subs	r2, r4, #0x2
     82c:      	add.w	r5, lr, #0x12
     830:      	add.w	r6, r10, #0x1a
     834:      	cmp	r4, #0x4
     836:      	bhs	0x850 <zs_str_concat+0x148> @ imm = #0x16
     838:      	b	0x86c <zs_str_concat+0x164> @ imm = #0x30
     83a:      	ldrb.w	r3, [lr, #0x12]
     83e:      	subs	r2, r4, #0x3
     840:      	add.w	r5, lr, #0x13
     844:      	add.w	r6, r10, #0x1b
     848:      	strb.w	r3, [r10, #0x1a]
     84c:      	cmp	r4, #0x4
     84e:      	blo	0x86c <zs_str_concat+0x164> @ imm = #0x1a
     850:      	subs	r3, r5, #0x4
     852:      	subs	r4, r6, #0x4
     854:      	ldrb	r5, [r3, #4]!
     858:      	subs	r2, #0x4
     85a:      	strb	r5, [r4, #4]!
     85e:      	ldrb	r5, [r3, #0x1]
     860:      	strb	r5, [r4, #0x1]
     862:      	ldrb	r5, [r3, #0x2]
     864:      	strb	r5, [r4, #0x2]
     866:      	ldrb	r5, [r3, #0x3]
     868:      	strb	r5, [r4, #0x3]
     86a:      	bne	0x854 <zs_str_concat+0x14c> @ imm = #-0x1a
     86c:      	ldr.w	r5, [lr, #0x8]
     870:      	ldr	r3, [r1, #0x8]
     872:      	cbz	r3, 0x8e0 <zs_str_concat+0x1d8> @ imm = #0x6a
     874:      	ands	r2, r3, #0x3
     878:      	add.w	r6, r12, r5
     87c:      	beq	0x896 <zs_str_concat+0x18e> @ imm = #0x16
     87e:      	ldrb	r5, [r1, #0x10]
     880:      	mov	r4, r6
     882:      	cmp	r2, #0x1
     884:      	strb	r5, [r4], #1
     888:      	bne	0x8a0 <zs_str_concat+0x198> @ imm = #0x14
     88a:      	subs	r2, r3, #0x1
     88c:      	adds	r1, #0x11
     88e:      	mov	r6, r4
     890:      	cmp	r3, #0x4
     892:      	bhs	0x8c2 <zs_str_concat+0x1ba> @ imm = #0x2c
     894:      	b	0x8e0 <zs_str_concat+0x1d8> @ imm = #0x48
     896:      	adds	r1, #0x10
     898:      	mov	r2, r3
     89a:      	cmp	r3, #0x4
     89c:      	bhs	0x8c2 <zs_str_concat+0x1ba> @ imm = #0x22
     89e:      	b	0x8e0 <zs_str_concat+0x1d8> @ imm = #0x3e
     8a0:      	ldrb	r5, [r1, #0x11]
     8a2:      	cmp	r2, #0x2
     8a4:      	strb	r5, [r6, #0x1]
     8a6:      	bne	0x8b4 <zs_str_concat+0x1ac> @ imm = #0xa
     8a8:      	subs	r2, r3, #0x2
     8aa:      	adds	r1, #0x12
     8ac:      	adds	r6, #0x2
     8ae:      	cmp	r3, #0x4
     8b0:      	bhs	0x8c2 <zs_str_concat+0x1ba> @ imm = #0xe
     8b2:      	b	0x8e0 <zs_str_concat+0x1d8> @ imm = #0x2a
     8b4:      	ldrb	r5, [r1, #0x12]
     8b6:      	subs	r2, r3, #0x3
     8b8:      	adds	r1, #0x13
     8ba:      	strb	r5, [r6, #0x2]
     8bc:      	adds	r6, #0x3
     8be:      	cmp	r3, #0x4
     8c0:      	blo	0x8e0 <zs_str_concat+0x1d8> @ imm = #0x1c
     8c2:      	subs	r1, #0x4
     8c4:      	subs	r3, r6, #0x4
     8c6:      	nop
     8c8:      	ldrb	r6, [r1, #4]!
     8cc:      	subs	r2, #0x4
     8ce:      	strb	r6, [r3, #4]!
     8d2:      	ldrb	r6, [r1, #0x1]
     8d4:      	strb	r6, [r3, #0x1]
     8d6:      	ldrb	r6, [r1, #0x2]
     8d8:      	strb	r6, [r3, #0x2]
     8da:      	ldrb	r6, [r1, #0x3]
     8dc:      	strb	r6, [r3, #0x3]
     8de:      	bne	0x8c8 <zs_str_concat+0x1c0> @ imm = #-0x1a
     8e0:      	pop.w	{r8, r9, r10}
     8e4:      	pop	{r4, r5, r6, r7, pc}
     8e6:      	movw	r0, #0x1fd8
     8ea:      	movt	r0, #0x0
     8ee:      	bl	0x68c <zs_panic_c>      @ imm = #-0x266
     8f2:      	bmi	0x89e <zs_str_concat+0x196> @ imm = #-0x58

000008f4 <zs_str_of_u64>:
     8f4:      	push	{r4, r5, r6, r7, lr}
     8f6:      	add	r7, sp, #0xc
     8f8:      	push.w	{r8, r9, r10, r11}
     8fc:      	sub	sp, #0x34
     8fe:      	movw	r9, #0xcccd
     902:      	mov	r5, r1
     904:      	mov	r6, r0
     906:      	mov.w	r10, #0x1
     90a:      	movt	r9, #0xcccc
     90e:      	add.w	r8, sp, #0x1c
     912:      	nop
     914:      	lsrs	r0, r6, #0x1
     916:      	orr.w	r0, r0, r5, lsl #31
     91a:      	adds.w	r1, r0, r5, lsr #1
     91e:      	adc	r1, r1, #0x0
     922:      	umull	r2, r3, r1, r9
     926:      	bic	r2, r3, #0x3
     92a:      	add.w	r2, r2, r3, lsr #2
     92e:      	subs	r1, r1, r2
     930:      	subs	r1, r0, r1
     932:      	umull	r0, r2, r1, r9
     936:      	add.w	r4, r0, r0, lsl #2
     93a:      	lsr.w	r3, r5, #0x1
     93e:      	sub.w	r4, r6, r4, lsl #1
     942:      	sbc	r3, r3, #0x0
     946:      	orr	r12, r4, #0x30
     94a:      	subs.w	r4, r6, #0xa
     94e:      	add.w	r11, r8, r10
     952:      	sbcs	r4, r5, #0x0
     956:      	strb	r12, [r11, #-1]
     95a:      	blo	0xa4a <zs_str_of_u64+0x156> @ imm = #0xec
     95c:      	mov.w	r4, #0xcccccccc
     960:      	mla	r1, r1, r4, r2
     964:      	lsrs	r2, r0, #0x1
     966:      	mla	r1, r3, r9, r1
     96a:      	and	r0, r0, #0x1
     96e:      	orr.w	r2, r2, r1, lsl #31
     972:      	adds.w	r1, r2, r1, lsr #1
     976:      	adc	r1, r1, #0x0
     97a:      	umull	r2, r3, r1, r9
     97e:      	bic	r2, r3, #0x3
     982:      	add.w	r2, r2, r3, lsr #2
     986:      	subs	r1, r1, r2
     988:      	orr.w	r0, r0, r1, lsl #1
     98c:      	subs.w	r1, r6, #0x64
     990:      	orr	r0, r0, #0x30
     994:      	sbcs	r1, r5, #0x0
     998:      	strb.w	r0, [r8, r10]
     99c:      	blo	0xa52 <zs_str_of_u64+0x15e> @ imm = #0xb2
     99e:      	mov	r0, r6
     9a0:      	mov	r1, r5
     9a2:      	movs	r2, #0x64
     9a4:      	movs	r3, #0x0
     9a6:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf8e
     9aa:      	lsrs	r2, r0, #0x1
     9ac:      	orr.w	r2, r2, r1, lsl #31
     9b0:      	adds.w	r1, r2, r1, lsr #1
     9b4:      	adc	r1, r1, #0x0
     9b8:      	umull	r2, r3, r1, r9
     9bc:      	bic	r2, r3, #0x3
     9c0:      	add.w	r2, r2, r3, lsr #2
     9c4:      	subs	r1, r1, r2
     9c6:      	and	r0, r0, #0x1
     9ca:      	orr.w	r0, r0, r1, lsl #1
     9ce:      	subs.w	r1, r6, #0x3e8
     9d2:      	orr	r0, r0, #0x30
     9d6:      	sbcs	r1, r5, #0x0
     9da:      	strb.w	r0, [r11, #0x1]
     9de:      	blo	0xa5a <zs_str_of_u64+0x166> @ imm = #0x78
     9e0:      	mov	r0, r6
     9e2:      	mov	r1, r5
     9e4:      	mov.w	r2, #0x3e8
     9e8:      	movs	r3, #0x0
     9ea:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf4a
     9ee:      	lsrs	r2, r0, #0x1
     9f0:      	orr.w	r2, r2, r1, lsl #31
     9f4:      	adds.w	r1, r2, r1, lsr #1
     9f8:      	adc	r1, r1, #0x0
     9fc:      	umull	r2, r3, r1, r9
     a00:      	bic	r2, r3, #0x3
     a04:      	add.w	r2, r2, r3, lsr #2
     a08:      	subs	r1, r1, r2
     a0a:      	and	r0, r0, #0x1
     a0e:      	orr.w	r0, r0, r1, lsl #1
     a12:      	orr	r0, r0, #0x30
     a16:      	strb.w	r0, [r11, #0x2]
     a1a:      	mov	r0, r6
     a1c:      	mov	r1, r5
     a1e:      	movw	r2, #0x2710
     a22:      	movs	r3, #0x0
     a24:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf10
     a28:      	movw	r2, #0x270f
     a2c:      	subs	r2, r2, r6
     a2e:      	mov.w	r2, #0x0
     a32:      	sbcs	r2, r5
     a34:      	add.w	r10, r10, #0x4
     a38:      	mov	r6, r0
     a3a:      	mov	r5, r1
     a3c:      	blo.w	0x914 <zs_str_of_u64+0x20> @ imm = #-0x12c
     a40:      	sub.w	r1, r10, #0x1
     a44:      	sub.w	r12, r10, #0x2
     a48:      	b	0xa62 <zs_str_of_u64+0x16e> @ imm = #0x16
     a4a:      	sub.w	r12, r10, #0x1
     a4e:      	mov	r1, r10
     a50:      	b	0xa64 <zs_str_of_u64+0x170> @ imm = #0x10
     a52:      	add.w	r1, r10, #0x1
     a56:      	mov	r12, r10
     a58:      	b	0xa62 <zs_str_of_u64+0x16e> @ imm = #0x6
     a5a:      	add.w	r1, r10, #0x2
     a5e:      	add.w	r12, r10, #0x1
     a62:      	mov	r10, r1
     a64:      	and	lr, r1, #0x3
     a68:      	lsrs	r3, r1, #0x2
     a6a:      	mov.w	r1, #0x0
     a6e:      	beq	0xaa2 <zs_str_of_u64+0x1ae> @ imm = #0x30
     a70:      	add	r6, sp, #0x4
     a72:      	add.w	r5, r12, r8
     a76:      	sub.w	r9, r1, r3, lsl #2
     a7a:      	subs	r6, #0x3
     a7c:      	subs	r5, #0x1
     a7e:      	nop
     a80:      	adds	r4, r5, r1
     a82:      	ldrb	r3, [r5, r1]
     a84:      	ldrb	r0, [r4, #-2]
     a88:      	ldrb	r2, [r4, #-1]
     a8c:      	ldrb	r4, [r4, #0x1]
     a8e:      	subs	r1, #0x4
     a90:      	strb	r3, [r6, #4]!
     a94:      	cmp	r9, r1
     a96:      	strb	r4, [r6, #-1]
     a9a:      	strb	r2, [r6, #0x1]
     a9c:      	strb	r0, [r6, #0x2]
     a9e:      	bne	0xa80 <zs_str_of_u64+0x18c> @ imm = #-0x22
     aa0:      	rsbs	r1, r1, #0
     aa2:      	cmp.w	lr, #0x0
     aa6:      	beq	0xad8 <zs_str_of_u64+0x1e4> @ imm = #0x2e
     aa8:      	sub.w	r0, r12, r1
     aac:      	ldrb.w	r0, [r8, r0]
     ab0:      	add	r3, sp, #0x4
     ab2:      	cmp.w	lr, #0x1
     ab6:      	strb	r0, [r3, r1]
     ab8:      	beq	0xad8 <zs_str_of_u64+0x1e4> @ imm = #0x1c
     aba:      	adds	r0, r1, #0x1
     abc:      	sub.w	r2, r12, r0
     ac0:      	ldrb.w	r2, [r8, r2]
     ac4:      	cmp.w	lr, #0x2
     ac8:      	strb	r2, [r3, r0]
     aca:      	beq	0xad8 <zs_str_of_u64+0x1e4> @ imm = #0xa
     acc:      	adds	r0, r1, #0x2
     ace:      	sub.w	r1, r12, r0
     ad2:      	ldrb.w	r1, [r8, r1]
     ad6:      	strb	r1, [r3, r0]
     ad8:      	add	r0, sp, #0x4
     ada:      	mov	r2, r10
     adc:      	movs	r3, #0x0
     ade:      	bl	0xaec <str_of>          @ imm = #0xa
     ae2:      	add	sp, #0x34
     ae4:      	pop.w	{r8, r9, r10, r11}
     ae8:      	pop	{r4, r5, r6, r7, pc}
     aea:      	bmi	0xa96 <zs_str_of_u64+0x1a2> @ imm = #-0x58

00000aec <str_of>:
     aec:      	push	{r4, r5, r6, r7, lr}
     aee:      	add	r7, sp, #0xc
     af0:      	str	r8, [sp, #-4]!
     af4:      	add.w	r12, r2, #0x18
     af8:      	lsr.w	r1, r12, #0x3
     afc:      	cmp	r1, #0x20
     afe:      	bhi	0xb1c <str_of+0x30>     @ imm = #0x1a
     b00:      	movw	r4, #0x0
     b04:      	movt	r4, #0x2000
     b08:      	ldr.w	r5, [r4, r1, lsl #2]
     b0c:      	cbz	r5, 0xb1c <str_of+0x30> @ imm = #0xc
     b0e:      	mov	r12, r5
     b10:      	ldr	r5, [r5]
     b12:      	ldr	lr, [r12, #-8]!
     b16:      	str.w	r5, [r4, r1, lsl #2]
     b1a:      	b	0xb54 <str_of+0x68>     @ imm = #0x36
     b1c:      	movw	r6, #0x84
     b20:      	movt	r6, #0x2000
     b24:      	ldr	r1, [r6]
     b26:      	bic	lr, r12, #0x7
     b2a:      	add.w	r5, lr, r1
     b2e:      	movw	r4, #0xfff9
     b32:      	subs	r4, r5, r4
     b34:      	cmn.w	r4, #0x10001
     b38:      	blo	0xc34 <str_of+0x148>    @ imm = #0xf8
     b3a:      	movw	r4, #0x88
     b3e:      	movt	r4, #0x2000
     b42:      	add.w	r12, r4, r1
     b46:      	adds	r5, #0x8
     b48:      	str.w	lr, [r4, r1]
     b4c:      	movs	r1, #0x0
     b4e:      	str	r5, [r6]
     b50:      	str.w	r1, [r12, #0x4]
     b54:      	movw	r4, #0x88
     b58:      	movt	r4, #0x2001
     b5c:      	movw	r1, #0x8c
     b60:      	ldr	r5, [r4]
     b62:      	movt	r1, #0x2001
     b66:      	ldr	r6, [r1]
     b68:      	add	r5, lr
     b6a:      	movw	lr, #0x90
     b6e:      	cmp	r5, r6
     b70:      	str	r5, [r4]
     b72:      	it	hi
     b74:      	strhi	r5, [r1]
     b76:      	movt	lr, #0x2001
     b7a:      	movw	r8, #0x98
     b7e:      	ldrd	r6, r5, [lr]
     b82:      	movt	r8, #0x2001
     b86:      	ldrd	r1, r4, [r8]
     b8a:      	adds	r6, #0x1
     b8c:      	adc	r5, r5, #0x0
     b90:      	adds	r1, #0x1
     b92:      	strd	r6, r5, [lr]
     b96:      	adc	r6, r4, #0x0
     b9a:      	strd	r1, r6, [r8]
     b9e:      	movs	r6, #0x1
     ba0:      	mov	r1, r12
     ba2:      	str	r6, [r1, #8]!
     ba6:      	movs	r4, #0x0
     ba8:      	add.w	lr, r1, #0x10
     bac:      	strd	r4, r2, [r1, #4]
     bb0:      	str	r3, [r1, #0xc]
     bb2:      	strb.w	r4, [lr, r2]
     bb6:      	cbz	r2, 0xc2c <str_of+0x140> @ imm = #0x72
     bb8:      	ands	r3, r2, #0x3
     bbc:      	beq	0xbda <str_of+0xee>     @ imm = #0x1a
     bbe:      	mov	r4, r0
     bc0:      	ldrb	r6, [r4], #1
     bc4:      	cmp	r3, #0x1
     bc6:      	strb.w	r6, [r12, #0x18]
     bca:      	bne	0xbe2 <str_of+0xf6>     @ imm = #0x14
     bcc:      	subs	r3, r2, #0x1
     bce:      	add.w	lr, r12, #0x19
     bd2:      	mov	r0, r4
     bd4:      	cmp	r2, #0x4
     bd6:      	bhs	0xc0c <str_of+0x120>    @ imm = #0x32
     bd8:      	b	0xc2c <str_of+0x140>    @ imm = #0x50
     bda:      	mov	r3, r2
     bdc:      	cmp	r2, #0x4
     bde:      	bhs	0xc0c <str_of+0x120>    @ imm = #0x2a
     be0:      	b	0xc2c <str_of+0x140>    @ imm = #0x48
     be2:      	ldrb	r6, [r0, #0x1]
     be4:      	cmp	r3, #0x2
     be6:      	strb.w	r6, [r12, #0x19]
     bea:      	bne	0xbfa <str_of+0x10e>    @ imm = #0xc
     bec:      	subs	r3, r2, #0x2
     bee:      	adds	r0, #0x2
     bf0:      	add.w	lr, r12, #0x1a
     bf4:      	cmp	r2, #0x4
     bf6:      	bhs	0xc0c <str_of+0x120>    @ imm = #0x12
     bf8:      	b	0xc2c <str_of+0x140>    @ imm = #0x30
     bfa:      	ldrb	r4, [r0, #0x2]
     bfc:      	subs	r3, r2, #0x3
     bfe:      	adds	r0, #0x3
     c00:      	add.w	lr, r12, #0x1b
     c04:      	strb.w	r4, [r12, #0x1a]
     c08:      	cmp	r2, #0x4
     c0a:      	blo	0xc2c <str_of+0x140>    @ imm = #0x1e
     c0c:      	subs	r0, #0x4
     c0e:      	sub.w	r2, lr, #0x4
     c12:      	nop
     c14:      	ldrb	r6, [r0, #4]!
     c18:      	subs	r3, #0x4
     c1a:      	strb	r6, [r2, #4]!
     c1e:      	ldrb	r6, [r0, #0x1]
     c20:      	strb	r6, [r2, #0x1]
     c22:      	ldrb	r6, [r0, #0x2]
     c24:      	strb	r6, [r2, #0x2]
     c26:      	ldrb	r6, [r0, #0x3]
     c28:      	strb	r6, [r2, #0x3]
     c2a:      	bne	0xc14 <str_of+0x128>    @ imm = #-0x1a
     c2c:      	mov	r0, r1
     c2e:      	ldr	r8, [sp], #4
     c32:      	pop	{r4, r5, r6, r7, pc}
     c34:      	movw	r0, #0x1fd8
     c38:      	movt	r0, #0x0
     c3c:      	bl	0x68c <zs_panic_c>      @ imm = #-0x5b4

00000c40 <zs_str_of_i64>:
     c40:      	push	{r4, r5, r6, r7, lr}
     c42:      	add	r7, sp, #0xc
     c44:      	push.w	{r8, r9, r10, r11}
     c48:      	sub	sp, #0x3c
     c4a:      	cmp.w	r1, #0xffffffff
     c4e:      	add	r2, sp, #0xc
     c50:      	ble	0xc58 <zs_str_of_i64+0x18> @ imm = #0x4
     c52:      	str	r2, [sp, #0x8]
     c54:      	movs	r2, #0x0
     c56:      	b	0xc64 <zs_str_of_i64+0x24> @ imm = #0xa
     c58:      	adds	r2, #0x1
     c5a:      	str	r2, [sp, #0x8]
     c5c:      	movs	r2, #0x2d
     c5e:      	strb.w	r2, [sp, #0xc]
     c62:      	movs	r2, #0x1
     c64:      	eor.w	r0, r0, r1, asr #31
     c68:      	str	r2, [sp, #0x4]
     c6a:      	eor.w	r2, r1, r1, asr #31
     c6e:      	subs.w	r4, r0, r1, asr #31
     c72:      	movw	r8, #0xcccd
     c76:      	sbc.w	r5, r2, r1, asr #31
     c7a:      	mov.w	r9, #0x1
     c7e:      	movt	r8, #0xcccc
     c82:      	add.w	r10, sp, #0x24
     c86:      	nop
     c88:      	lsrs	r0, r4, #0x1
     c8a:      	orr.w	r0, r0, r5, lsl #31
     c8e:      	adds.w	r1, r0, r5, lsr #1
     c92:      	adc	r1, r1, #0x0
     c96:      	umull	r2, r3, r1, r8
     c9a:      	bic	r2, r3, #0x3
     c9e:      	add.w	r2, r2, r3, lsr #2
     ca2:      	subs	r1, r1, r2
     ca4:      	subs	r1, r0, r1
     ca6:      	umull	r0, r2, r1, r8
     caa:      	add.w	r6, r0, r0, lsl #2
     cae:      	lsr.w	r3, r5, #0x1
     cb2:      	sub.w	r6, r4, r6, lsl #1
     cb6:      	sbc	r3, r3, #0x0
     cba:      	orr	r12, r6, #0x30
     cbe:      	subs.w	r6, r4, #0xa
     cc2:      	add.w	r11, r10, r9
     cc6:      	sbcs	r6, r5, #0x0
     cca:      	strb	r12, [r11, #-1]
     cce:      	blo	0xdbe <zs_str_of_i64+0x17e> @ imm = #0xec
     cd0:      	mov.w	r6, #0xcccccccc
     cd4:      	mla	r1, r1, r6, r2
     cd8:      	lsrs	r2, r0, #0x1
     cda:      	mla	r1, r3, r8, r1
     cde:      	and	r0, r0, #0x1
     ce2:      	orr.w	r2, r2, r1, lsl #31
     ce6:      	adds.w	r1, r2, r1, lsr #1
     cea:      	adc	r1, r1, #0x0
     cee:      	umull	r2, r3, r1, r8
     cf2:      	bic	r2, r3, #0x3
     cf6:      	add.w	r2, r2, r3, lsr #2
     cfa:      	subs	r1, r1, r2
     cfc:      	orr.w	r0, r0, r1, lsl #1
     d00:      	subs.w	r1, r4, #0x64
     d04:      	orr	r0, r0, #0x30
     d08:      	sbcs	r1, r5, #0x0
     d0c:      	strb.w	r0, [r10, r9]
     d10:      	blo	0xdc6 <zs_str_of_i64+0x186> @ imm = #0xb2
     d12:      	mov	r0, r4
     d14:      	mov	r1, r5
     d16:      	movs	r2, #0x64
     d18:      	movs	r3, #0x0
     d1a:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xc1a
     d1e:      	lsrs	r2, r0, #0x1
     d20:      	orr.w	r2, r2, r1, lsl #31
     d24:      	adds.w	r1, r2, r1, lsr #1
     d28:      	adc	r1, r1, #0x0
     d2c:      	umull	r2, r3, r1, r8
     d30:      	bic	r2, r3, #0x3
     d34:      	add.w	r2, r2, r3, lsr #2
     d38:      	subs	r1, r1, r2
     d3a:      	and	r0, r0, #0x1
     d3e:      	orr.w	r0, r0, r1, lsl #1
     d42:      	subs.w	r1, r4, #0x3e8
     d46:      	orr	r0, r0, #0x30
     d4a:      	sbcs	r1, r5, #0x0
     d4e:      	strb.w	r0, [r11, #0x1]
     d52:      	blo	0xdce <zs_str_of_i64+0x18e> @ imm = #0x78
     d54:      	mov	r0, r4
     d56:      	mov	r1, r5
     d58:      	mov.w	r2, #0x3e8
     d5c:      	movs	r3, #0x0
     d5e:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xbd6
     d62:      	lsrs	r2, r0, #0x1
     d64:      	orr.w	r2, r2, r1, lsl #31
     d68:      	adds.w	r1, r2, r1, lsr #1
     d6c:      	adc	r1, r1, #0x0
     d70:      	umull	r2, r3, r1, r8
     d74:      	bic	r2, r3, #0x3
     d78:      	add.w	r2, r2, r3, lsr #2
     d7c:      	subs	r1, r1, r2
     d7e:      	and	r0, r0, #0x1
     d82:      	orr.w	r0, r0, r1, lsl #1
     d86:      	orr	r0, r0, #0x30
     d8a:      	strb.w	r0, [r11, #0x2]
     d8e:      	mov	r0, r4
     d90:      	mov	r1, r5
     d92:      	movw	r2, #0x2710
     d96:      	movs	r3, #0x0
     d98:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xb9c
     d9c:      	movw	r2, #0x270f
     da0:      	subs	r2, r2, r4
     da2:      	mov.w	r2, #0x0
     da6:      	sbcs	r2, r5
     da8:      	add.w	r9, r9, #0x4
     dac:      	mov	r4, r0
     dae:      	mov	r5, r1
     db0:      	blo.w	0xc88 <zs_str_of_i64+0x48> @ imm = #-0x12c
     db4:      	sub.w	r1, r9, #0x1
     db8:      	sub.w	r12, r9, #0x2
     dbc:      	b	0xdd6 <zs_str_of_i64+0x196> @ imm = #0x16
     dbe:      	sub.w	r12, r9, #0x1
     dc2:      	mov	r1, r9
     dc4:      	b	0xdd8 <zs_str_of_i64+0x198> @ imm = #0x10
     dc6:      	add.w	r1, r9, #0x1
     dca:      	mov	r12, r9
     dcc:      	b	0xdd6 <zs_str_of_i64+0x196> @ imm = #0x6
     dce:      	add.w	r1, r9, #0x2
     dd2:      	add.w	r12, r9, #0x1
     dd6:      	mov	r9, r1
     dd8:      	ldr.w	r8, [sp, #0x8]
     ddc:      	and	lr, r1, #0x3
     de0:      	lsrs	r3, r1, #0x2
     de2:      	mov.w	r1, #0x0
     de6:      	beq	0xe18 <zs_str_of_i64+0x1d8> @ imm = #0x2e
     de8:      	add.w	r6, r12, r10
     dec:      	sub.w	r3, r1, r3, lsl #2
     df0:      	sub.w	r5, r8, #0x3
     df4:      	subs	r4, r6, #0x1
     df6:      	nop
     df8:      	adds	r6, r4, r1
     dfa:      	ldrb	r0, [r6, #0x1]
     dfc:      	ldrb	r2, [r6, #-1]
     e00:      	strb	r0, [r5, #0x3]
     e02:      	ldrb	r0, [r4, r1]
     e04:      	subs	r1, #0x4
     e06:      	strb	r0, [r5, #4]!
     e0a:      	ldrb	r0, [r6, #-2]
     e0e:      	cmp	r3, r1
     e10:      	strb	r2, [r5, #0x1]
     e12:      	strb	r0, [r5, #0x2]
     e14:      	bne	0xdf8 <zs_str_of_i64+0x1b8> @ imm = #-0x20
     e16:      	rsbs	r1, r1, #0
     e18:      	cmp.w	lr, #0x0
     e1c:      	beq	0xe52 <zs_str_of_i64+0x212> @ imm = #0x32
     e1e:      	sub.w	r0, r12, r1
     e22:      	ldrb.w	r0, [r10, r0]
     e26:      	cmp.w	lr, #0x1
     e2a:      	strb.w	r0, [r8, r1]
     e2e:      	beq	0xe52 <zs_str_of_i64+0x212> @ imm = #0x20
     e30:      	adds	r0, r1, #0x1
     e32:      	sub.w	r2, r12, r0
     e36:      	ldrb.w	r2, [r10, r2]
     e3a:      	cmp.w	lr, #0x2
     e3e:      	strb.w	r2, [r8, r0]
     e42:      	beq	0xe52 <zs_str_of_i64+0x212> @ imm = #0xc
     e44:      	adds	r0, r1, #0x2
     e46:      	sub.w	r1, r12, r0
     e4a:      	ldrb.w	r1, [r10, r1]
     e4e:      	strb.w	r1, [r8, r0]
     e52:      	ldr	r0, [sp, #0x4]
     e54:      	movs	r3, #0x0
     e56:      	add.w	r2, r9, r0
     e5a:      	add	r0, sp, #0xc
     e5c:      	bl	0xaec <str_of>          @ imm = #-0x374
     e60:      	add	sp, #0x3c
     e62:      	pop.w	{r8, r9, r10, r11}
     e66:      	pop	{r4, r5, r6, r7, pc}

00000e68 <zs_str_byte>:
     e68:      	cmp	r3, #0x0
     e6a:      	bmi	0xe7e <zs_str_byte+0x16> @ imm = #0x10
     e6c:      	ldrd	r1, r12, [r0, #8]
     e70:      	subs	r1, r2, r1
     e72:      	sbcs.w	r1, r3, r12
     e76:      	ittt	lt
     e78:      	addlt	r0, r2
     e7a:      	ldrblt	r0, [r0, #0x10]
     e7c:      	bxlt	lr
     e7e:      	push	{r7, lr}
     e80:      	mov	r7, sp
     e82:      	movw	r0, #0x1ff1
     e86:      	movt	r0, #0x0
     e8a:      	bl	0x68c <zs_panic_c>      @ imm = #-0x802
     e8e:      	bmi	0xe3a <zs_str_of_i64+0x1fa> @ imm = #-0x58

00000e90 <zs_println>:
     e90:      	push	{r4, r5, r6, r7, lr}
     e92:      	add	r7, sp, #0xc
     e94:      	push.w	{r8, r9, r10, r11}
     e98:      	sub	sp, #0x44
     e9a:      	ldrd	r11, r2, [r0, #8]
     e9e:      	subs.w	r1, r11, #0x1
     ea2:      	sbcs	r1, r2, #0x0
     ea6:      	blt	0xf92 <zs_println+0x102> @ imm = #0xe8
     ea8:      	sub.w	r1, r7, #0x5d
     eac:      	add.w	lr, r0, #0x10
     eb0:      	add.w	r9, r1, #0x1
     eb4:      	movs	r3, #0x0
     eb6:      	b	0xed4 <zs_println+0x44> @ imm = #0x1a
     eb8:      	strb.w	r3, [r1, r8]
     ebc:      	movs	r0, #0x4
     ebe:      	subs.w	r11, r11, r8
     ec2:      	bkpt	#0xab
     ec4:      	sbc	r2, r2, #0x0
     ec8:      	rsbs.w	r0, r11, #0x0
     ecc:      	sbcs.w	r0, r3, r2
     ed0:      	add	lr, r8
     ed2:      	bge	0xf92 <zs_println+0x102> @ imm = #0xbc
     ed4:      	cmp.w	r11, #0x40
     ed8:      	mov.w	r8, #0x40
     edc:      	it	lo
     ede:      	movlo	r8, r11
     ee0:      	cmp	r2, #0x0
     ee2:      	mov.w	r0, #0x40
     ee6:      	it	ne
     ee8:      	movne	r8, r0
     eea:      	lsrs.w	r0, r8, #0x2
     eee:      	beq	0xf54 <zs_println+0xc4> @ imm = #0x62
     ef0:      	mov	r1, r2
     ef2:      	sub.w	r10, r3, r0, lsl #2
     ef6:      	add.w	r5, lr, #0x1
     efa:      	mvn	r4, #0x3
     efe:      	nop
     f00:      	adds	r2, r5, r4
     f02:      	ldrb	r6, [r2, #0x3]
     f04:      	ldrb	r3, [r2, #0x4]
     f06:      	ldrb	r0, [r2, #0x5]
     f08:      	cmp	r6, #0x0
     f0a:      	ldrb	r2, [r2, #0x6]
     f0c:      	it	eq
     f0e:      	moveq	r6, #0x20
     f10:      	add.w	r12, r9, r4
     f14:      	cmp	r3, #0x0
     f16:      	strb.w	r6, [r12, #0x3]
     f1a:      	it	eq
     f1c:      	moveq	r3, #0x20
     f1e:      	strb.w	r3, [r12, #0x4]
     f22:      	cmp	r0, #0x0
     f24:      	it	eq
     f26:      	moveq	r0, #0x20
     f28:      	adds	r4, #0x4
     f2a:      	strb.w	r0, [r12, #0x5]
     f2e:      	cmp	r2, #0x0
     f30:      	add.w	r0, r10, r4
     f34:      	it	eq
     f36:      	moveq	r2, #0x20
     f38:      	adds	r0, #0x4
     f3a:      	strb.w	r2, [r12, #0x6]
     f3e:      	bne	0xf00 <zs_println+0x70> @ imm = #-0x42
     f40:      	adds	r0, r4, #0x4
     f42:      	mov	r2, r1
     f44:      	sub.w	r1, r7, #0x5d
     f48:      	movs	r3, #0x0
     f4a:      	ands	r4, r8, #0x3
     f4e:      	bne	0xf5c <zs_println+0xcc> @ imm = #0xa
     f50:      	b	0xeb8 <zs_println+0x28> @ imm = #-0x9c
     f52:      	nop
     f54:      	movs	r0, #0x0
     f56:      	ands	r4, r8, #0x3
     f5a:      	beq	0xeb8 <zs_println+0x28> @ imm = #-0xa6
     f5c:      	ldrb.w	r5, [lr, r0]
     f60:      	cmp	r5, #0x0
     f62:      	it	eq
     f64:      	moveq	r5, #0x20
     f66:      	cmp	r4, #0x1
     f68:      	strb	r5, [r1, r0]
     f6a:      	beq	0xeb8 <zs_println+0x28> @ imm = #-0xb6
     f6c:      	add.w	r10, r0, #0x1
     f70:      	ldrb.w	r5, [lr, r10]
     f74:      	cmp	r5, #0x0
     f76:      	it	eq
     f78:      	moveq	r5, #0x20
     f7a:      	cmp	r4, #0x2
     f7c:      	strb.w	r5, [r1, r10]
     f80:      	beq	0xeb8 <zs_println+0x28> @ imm = #-0xcc
     f82:      	adds	r0, #0x2
     f84:      	ldrb.w	r4, [lr, r0]
     f88:      	cmp	r4, #0x0
     f8a:      	it	eq
     f8c:      	moveq	r4, #0x20
     f8e:      	strb	r4, [r1, r0]
     f90:      	b	0xeb8 <zs_println+0x28> @ imm = #-0xdc
     f92:      	movs	r0, #0xa
     f94:      	strh	r0, [r7, #-93]
     f98:      	movs	r0, #0x4
     f9a:      	sub.w	r1, r7, #0x5d
     f9e:      	bkpt	#0xab
     fa0:      	add	sp, #0x44
     fa2:      	pop.w	{r8, r9, r10, r11}
     fa6:      	pop	{r4, r5, r6, r7, pc}

00000fa8 <write_c>:
     fa8:      	push	{r4, r5, r6, r7, lr}
     faa:      	add	r7, sp, #0xc
     fac:      	push.w	{r8, r9, r10, r11}
     fb0:      	sub	sp, #0x44
     fb2:      	mov	r2, r0
     fb4:      	mov.w	r11, #0xffffffff
     fb8:      	add.w	r0, r2, r11
     fbc:      	ldrb	r1, [r0, #0x1]
     fbe:      	cbz	r1, 0xfd8 <write_c+0x30> @ imm = #0x16
     fc0:      	ldrb	r1, [r0, #0x2]
     fc2:      	cbz	r1, 0xfe4 <write_c+0x3c> @ imm = #0x1e
     fc4:      	ldrb	r1, [r0, #0x3]
     fc6:      	cmp	r1, #0x0
     fc8:      	beq.w	0x10d8 <write_c+0x130>  @ imm = #0x10c
     fcc:      	ldrb	r0, [r0, #0x4]
     fce:      	add.w	r11, r11, #0x4
     fd2:      	cmp	r0, #0x0
     fd4:      	bne	0xfb8 <write_c+0x10>    @ imm = #-0x20
     fd6:      	b	0xfe8 <write_c+0x40>    @ imm = #0xe
     fd8:      	add.w	r11, r11, #0x1
     fdc:      	cmp.w	r11, #0x0
     fe0:      	bne	0xfee <write_c+0x46>    @ imm = #0xa
     fe2:      	b	0x10e4 <write_c+0x13c>  @ imm = #0xfe
     fe4:      	add.w	r11, r11, #0x2
     fe8:      	cmp.w	r11, #0x0
     fec:      	beq	0x10e4 <write_c+0x13c>  @ imm = #0xf4
     fee:      	sub.w	r1, r7, #0x5d
     ff2:      	movs	r3, #0x0
     ff4:      	add.w	r12, r1, #0x1
     ff8:      	movs	r6, #0x40
     ffa:      	mov.w	r9, #0x0
     ffe:      	b	0x101c <write_c+0x74>   @ imm = #0x1a
    1000:      	strb.w	r3, [r1, r8]
    1004:      	movs	r0, #0x4
    1006:      	subs.w	r11, r11, r8
    100a:      	bkpt	#0xab
    100c:      	sbc	r9, r9, #0x0
    1010:      	rsbs.w	r0, r11, #0x0
    1014:      	sbcs.w	r0, r3, r9
    1018:      	add	r2, r8
    101a:      	bge	0x10e4 <write_c+0x13c>  @ imm = #0xc6
    101c:      	mov.w	r8, #0x40
    1020:      	cmp.w	r11, #0x40
    1024:      	it	lo
    1026:      	movlo	r8, r11
    1028:      	cmp.w	r9, #0x0
    102c:      	it	ne
    102e:      	movne	r8, r6
    1030:      	sub.w	r0, r8, #0x1
    1034:      	cmp	r0, #0x3
    1036:      	bhs	0x1044 <write_c+0x9c>   @ imm = #0xa
    1038:      	movs	r0, #0x0
    103a:      	ands	r4, r8, #0x3
    103e:      	bne	0x10a6 <write_c+0xfe>   @ imm = #0x64
    1040:      	b	0x1000 <write_c+0x58>   @ imm = #-0x44
    1042:      	nop
    1044:      	bic	r0, r8, #0x3
    1048:      	rsb.w	r10, r0, #0x0
    104c:      	mov	r1, r2
    104e:      	adds	r5, r2, #0x1
    1050:      	mvn	r4, #0x3
    1054:      	adds	r3, r5, r4
    1056:      	ldrb	r6, [r3, #0x3]
    1058:      	ldrb	r2, [r3, #0x4]
    105a:      	ldrb	r0, [r3, #0x5]
    105c:      	cmp	r6, #0x0
    105e:      	ldrb	r3, [r3, #0x6]
    1060:      	it	eq
    1062:      	moveq	r6, #0x20
    1064:      	add.w	lr, r12, r4
    1068:      	cmp	r2, #0x0
    106a:      	strb.w	r6, [lr, #0x3]
    106e:      	it	eq
    1070:      	moveq	r2, #0x20
    1072:      	strb.w	r2, [lr, #0x4]
    1076:      	cmp	r0, #0x0
    1078:      	it	eq
    107a:      	moveq	r0, #0x20
    107c:      	adds	r4, #0x4
    107e:      	strb.w	r0, [lr, #0x5]
    1082:      	cmp	r3, #0x0
    1084:      	add.w	r0, r10, r4
    1088:      	it	eq
    108a:      	moveq	r3, #0x20
    108c:      	adds	r0, #0x4
    108e:      	strb.w	r3, [lr, #0x6]
    1092:      	bne	0x1054 <write_c+0xac>   @ imm = #-0x42
    1094:      	adds	r0, r4, #0x4
    1096:      	mov	r2, r1
    1098:      	movs	r3, #0x0
    109a:      	sub.w	r1, r7, #0x5d
    109e:      	movs	r6, #0x40
    10a0:      	ands	r4, r8, #0x3
    10a4:      	beq	0x1000 <write_c+0x58>   @ imm = #-0xa8
    10a6:      	ldrb	r5, [r2, r0]
    10a8:      	cmp	r5, #0x0
    10aa:      	it	eq
    10ac:      	moveq	r5, #0x20
    10ae:      	cmp	r4, #0x1
    10b0:      	strb	r5, [r1, r0]
    10b2:      	beq	0x1000 <write_c+0x58>   @ imm = #-0xb6
    10b4:      	add.w	r10, r0, #0x1
    10b8:      	ldrb.w	r5, [r2, r10]
    10bc:      	cmp	r5, #0x0
    10be:      	it	eq
    10c0:      	moveq	r5, #0x20
    10c2:      	cmp	r4, #0x2
    10c4:      	strb.w	r5, [r1, r10]
    10c8:      	beq	0x1000 <write_c+0x58>   @ imm = #-0xcc
    10ca:      	adds	r0, #0x2
    10cc:      	ldrb	r4, [r2, r0]
    10ce:      	cmp	r4, #0x0
    10d0:      	it	eq
    10d2:      	moveq	r4, #0x20
    10d4:      	strb	r4, [r1, r0]
    10d6:      	b	0x1000 <write_c+0x58>   @ imm = #-0xda
    10d8:      	add.w	r11, r11, #0x3
    10dc:      	cmp.w	r11, #0x0
    10e0:      	bne.w	0xfee <write_c+0x46>    @ imm = #-0xf6
    10e4:      	add	sp, #0x44
    10e6:      	pop.w	{r8, r9, r10, r11}
    10ea:      	pop	{r4, r5, r6, r7, pc}

000010ec <stop>:
    10ec:      	push	{r4, r5, r6, r7, lr}
    10ee:      	add	r7, sp, #0xc
    10f0:      	str	r11, [sp, #-4]!
    10f4:      	sub	sp, #0x48
    10f6:      	movw	r6, #0x8000
    10fa:      	movw	r5, #0x0
    10fe:      	movt	r6, #0x203f
    1102:      	movt	r5, #0x2040
    1106:      	cmp	r6, r5
    1108:      	mov	r4, r0
    110a:      	bhs	0x1156 <stop+0x6a>      @ imm = #0x48
    110c:      	movw	r0, #0x8000
    1110:      	movt	r0, #0x203f
    1114:      	ldr	r1, [r0]
    1116:      	cmp.w	r1, #0xcdcdcdcd
    111a:      	bne	0x1154 <stop+0x68>      @ imm = #0x36
    111c:      	adds	r6, r0, #0x4
    111e:      	cmp	r6, r5
    1120:      	bhs	0x1156 <stop+0x6a>      @ imm = #0x32
    1122:      	ldr	r1, [r6]
    1124:      	cmp.w	r1, #0xcdcdcdcd
    1128:      	bne	0x1156 <stop+0x6a>      @ imm = #0x2a
    112a:      	add.w	r6, r0, #0x8
    112e:      	cmp	r6, r5
    1130:      	bhs	0x1156 <stop+0x6a>      @ imm = #0x22
    1132:      	ldr	r1, [r6]
    1134:      	cmp.w	r1, #0xcdcdcdcd
    1138:      	bne	0x1156 <stop+0x6a>      @ imm = #0x1a
    113a:      	add.w	r6, r0, #0xc
    113e:      	cmp	r6, r5
    1140:      	bhs	0x1156 <stop+0x6a>      @ imm = #0x12
    1142:      	ldr	r1, [r6]
    1144:      	cmp.w	r1, #0xcdcdcdcd
    1148:      	bne	0x1156 <stop+0x6a>      @ imm = #0xa
    114a:      	adds	r0, #0x10
    114c:      	cmp	r0, r5
    114e:      	mov	r6, r0
    1150:      	blo	0x1114 <stop+0x28>      @ imm = #-0x40
    1152:      	b	0x1156 <stop+0x6a>      @ imm = #0x0
    1154:      	mov	r6, r0
    1156:      	movw	r0, #0x8c
    115a:      	movt	r0, #0x2001
    115e:      	ldr	r2, [r0]
    1160:      	movw	r0, #0x2021
    1164:      	movt	r0, #0x0
    1168:      	movs	r3, #0x0
    116a:      	bl	0x135c <text>           @ imm = #0x1ee
    116e:      	movw	r0, #0x84
    1172:      	movt	r0, #0x2000
    1176:      	ldr	r2, [r0]
    1178:      	movw	r0, #0x2037
    117c:      	movt	r0, #0x0
    1180:      	movs	r3, #0x0
    1182:      	bl	0x135c <text>           @ imm = #0x1d6
    1186:      	movw	r0, #0x98
    118a:      	movt	r0, #0x2001
    118e:      	ldrd	r2, r3, [r0]
    1192:      	movw	r0, #0x200b
    1196:      	movt	r0, #0x0
    119a:      	bl	0x135c <text>           @ imm = #0x1be
    119e:      	movw	r0, #0x90
    11a2:      	movt	r0, #0x2001
    11a6:      	ldrd	r2, r3, [r0]
    11aa:      	movw	r0, #0x2030
    11ae:      	movt	r0, #0x0
    11b2:      	bl	0x135c <text>           @ imm = #0x1a6
    11b6:      	subs	r2, r5, r6
    11b8:      	movw	r0, #0x2019
    11bc:      	asrs	r3, r2, #0x1f
    11be:      	movt	r0, #0x0
    11c2:      	bl	0x135c <text>           @ imm = #0x196
    11c6:      	movs	r0, #0xa
    11c8:      	strh.w	r0, [sp, #0x4]
    11cc:      	movs	r0, #0x4
    11ce:      	add	r1, sp, #0x4
    11d0:      	bkpt	#0xab
    11d2:      	movs	r0, #0x26
    11d4:      	movt	r0, #0x2
    11d8:      	strd	r0, r4, [sp, #4]
    11dc:      	movs	r0, #0x20
    11de:      	add	r1, sp, #0x4
    11e0:      	bkpt	#0xab
    11e2:      	nop
    11e4:      	b	0x11e4 <stop+0xf8>      @ imm = #-0x4
    11e6:      	bmi	0x1192 <stop+0xa6>      @ imm = #-0x58

000011e8 <zs_set_args>:
    11e8:      	push	{r7, lr}
    11ea:      	mov	r7, sp
    11ec:      	pop	{r7, pc}
    11ee:      	bmi	0x119a <stop+0xae>      @ imm = #-0x58

000011f0 <Reset_Handler>:
    11f0:      	push	{r7, lr}
    11f2:      	mov	r7, sp
    11f4:      	movw	r0, #0x0
    11f8:      	movw	r1, #0x0
    11fc:      	movt	r0, #0x2000
    1200:      	movt	r1, #0x2000
    1204:      	cmp	r1, r0
    1206:      	bhs	0x123a <Reset_Handler+0x4a> @ imm = #0x30
    1208:      	movw	r2, #0x2188
    120c:      	movt	r2, #0x0
    1210:      	ldr	r3, [r2]
    1212:      	str	r3, [r1], #4
    1216:      	cmp	r1, r0
    1218:      	bhs	0x123a <Reset_Handler+0x4a> @ imm = #0x1e
    121a:      	ldr	r3, [r2, #0x4]
    121c:      	str	r3, [r1], #4
    1220:      	cmp	r1, r0
    1222:      	bhs	0x123a <Reset_Handler+0x4a> @ imm = #0x14
    1224:      	ldr	r3, [r2, #0x8]
    1226:      	str	r3, [r1], #4
    122a:      	cmp	r1, r0
    122c:      	bhs	0x123a <Reset_Handler+0x4a> @ imm = #0xa
    122e:      	ldr	r3, [r2, #0xc]
    1230:      	adds	r2, #0x10
    1232:      	str	r3, [r1], #4
    1236:      	cmp	r1, r0
    1238:      	blo	0x1210 <Reset_Handler+0x20> @ imm = #-0x2c
    123a:      	movw	r0, #0xa4
    123e:      	movw	r1, #0x0
    1242:      	movt	r0, #0x2001
    1246:      	movt	r1, #0x2000
    124a:      	cmp	r1, r0
    124c:      	bhs	0x1270 <Reset_Handler+0x80> @ imm = #0x20
    124e:      	movs	r2, #0x0
    1250:      	str	r2, [r1], #4
    1254:      	cmp	r1, r0
    1256:      	bhs	0x1270 <Reset_Handler+0x80> @ imm = #0x16
    1258:      	str	r2, [r1], #4
    125c:      	cmp	r1, r0
    125e:      	bhs	0x1270 <Reset_Handler+0x80> @ imm = #0xe
    1260:      	str	r2, [r1], #4
    1264:      	cmp	r1, r0
    1266:      	bhs	0x1270 <Reset_Handler+0x80> @ imm = #0x6
    1268:      	str	r2, [r1], #4
    126c:      	cmp	r1, r0
    126e:      	blo	0x1250 <Reset_Handler+0x60> @ imm = #-0x22
    1270:      	movw	r0, #0xed88
    1274:      	movt	r0, #0xe000
    1278:      	ldr	r1, [r0]
    127a:      	orr	r1, r1, #0xf00000
    127e:      	str	r1, [r0]
    1280:      	movw	r0, #0xe010
    1284:      	movt	r0, #0xe000
    1288:      	mvn	r1, #0xff000000
    128c:      	dsb	sy
    1290:      	isb	sy
    1294:      	str	r1, [r0, #0x4]
    1296:      	movs	r1, #0x0
    1298:      	str	r1, [r0, #0x8]
    129a:      	movs	r1, #0x7
    129c:      	str	r1, [r0]
    129e:      	mov	r0, sp
    12a0:      	movw	r1, #0x8000
    12a4:      	subs	r0, #0x40
    12a6:      	movt	r1, #0x203f
    12aa:      	cmp	r0, r1
    12ac:      	bls	0x12d4 <Reset_Handler+0xe4> @ imm = #0x24
    12ae:      	mov.w	r2, #0xcdcdcdcd
    12b2:      	nop
    12b4:      	str	r2, [r1], #4
    12b8:      	cmp	r1, r0
    12ba:      	bhs	0x12d4 <Reset_Handler+0xe4> @ imm = #0x16
    12bc:      	str	r2, [r1], #4
    12c0:      	cmp	r1, r0
    12c2:      	bhs	0x12d4 <Reset_Handler+0xe4> @ imm = #0xe
    12c4:      	str	r2, [r1], #4
    12c8:      	cmp	r1, r0
    12ca:      	bhs	0x12d4 <Reset_Handler+0xe4> @ imm = #0x6
    12cc:      	str	r2, [r1], #4
    12d0:      	cmp	r1, r0
    12d2:      	blo	0x12b4 <Reset_Handler+0xc4> @ imm = #-0x22
    12d4:      	movs	r0, #0x0
    12d6:      	movs	r1, #0x0
    12d8:      	bl	0x40 <main>             @ imm = #-0x129c
    12dc:      	bl	0x10ec <stop>           @ imm = #-0x1f4

000012e0 <zs_ticks>:
    12e0:      	push	{r7, lr}
    12e2:      	mov	r7, sp
    12e4:      	movw	r12, #0xe018
    12e8:      	movw	r2, #0xa0
    12ec:      	movt	r12, #0xe000
    12f0:      	movt	r2, #0x2001
    12f4:      	ldr	r1, [r2]
    12f6:      	ldr.w	r3, [r12]
    12fa:      	ldr	r0, [r2]
    12fc:      	cmp	r1, r0
    12fe:      	beq	0x1324 <zs_ticks+0x44>  @ imm = #0x22
    1300:      	ldr	r1, [r2]
    1302:      	ldr.w	r3, [r12]
    1306:      	ldr	r0, [r2]
    1308:      	cmp	r1, r0
    130a:      	beq	0x1324 <zs_ticks+0x44>  @ imm = #0x16
    130c:      	ldr	r1, [r2]
    130e:      	ldr.w	r3, [r12]
    1312:      	ldr	r0, [r2]
    1314:      	cmp	r1, r0
    1316:      	beq	0x1324 <zs_ticks+0x44>  @ imm = #0xa
    1318:      	ldr	r1, [r2]
    131a:      	ldr.w	r3, [r12]
    131e:      	ldr	r0, [r2]
    1320:      	cmp	r1, r0
    1322:      	bne	0x12f4 <zs_ticks+0x14>  @ imm = #-0x32
    1324:      	mvn	r0, #0xff000000
    1328:      	subs	r0, r0, r3
    132a:      	lsrs	r2, r1, #0x8
    132c:      	adds.w	r0, r0, r1, lsl #24
    1330:      	adc	r1, r2, #0x0
    1334:      	pop	{r7, pc}
    1336:      	bmi	0x12e2 <zs_ticks+0x2>   @ imm = #-0x58

00001338 <fault>:
    1338:      	push	{r7, lr}
    133a:      	mov	r7, sp
    133c:      	movw	r0, #0x1fe6
    1340:      	movt	r0, #0x0
    1344:      	bl	0x68c <zs_panic_c>      @ imm = #-0xcbc

00001348 <SysTick_Handler>:
    1348:      	push	{r7, lr}
    134a:      	mov	r7, sp
    134c:      	movw	r0, #0xa0
    1350:      	movt	r0, #0x2001
    1354:      	ldr	r1, [r0]
    1356:      	adds	r1, #0x1
    1358:      	str	r1, [r0]
    135a:      	pop	{r7, pc}

0000135c <text>:
    135c:      	push	{r4, r5, r6, r7, lr}
    135e:      	add	r7, sp, #0xc
    1360:      	push.w	{r8, r9, r10, r11}
    1364:      	sub	sp, #0x64
    1366:      	strd	r2, r3, [sp]
    136a:      	mov	r3, r0
    136c:      	mov.w	r12, #0xffffffff
    1370:      	add.w	r0, r3, r12
    1374:      	ldrb	r1, [r0, #0x1]
    1376:      	cbz	r1, 0x1392 <text+0x36>  @ imm = #0x18
    1378:      	ldrb	r1, [r0, #0x2]
    137a:      	cbz	r1, 0x139e <text+0x42>  @ imm = #0x20
    137c:      	ldrb	r1, [r0, #0x3]
    137e:      	cbz	r1, 0x13aa <text+0x4e>  @ imm = #0x28
    1380:      	ldrb	r0, [r0, #0x4]
    1382:      	add.w	r12, r12, #0x4
    1386:      	cmp	r0, #0x0
    1388:      	bne	0x1370 <text+0x14>      @ imm = #-0x1c
    138a:      	cmp.w	r12, #0x0
    138e:      	bne	0x13b4 <text+0x58>      @ imm = #0x22
    1390:      	b	0x14a2 <text+0x146>     @ imm = #0x10e
    1392:      	add.w	r12, r12, #0x1
    1396:      	cmp.w	r12, #0x0
    139a:      	bne	0x13b4 <text+0x58>      @ imm = #0x16
    139c:      	b	0x14a2 <text+0x146>     @ imm = #0x102
    139e:      	add.w	r12, r12, #0x2
    13a2:      	cmp.w	r12, #0x0
    13a6:      	bne	0x13b4 <text+0x58>      @ imm = #0xa
    13a8:      	b	0x14a2 <text+0x146>     @ imm = #0xf6
    13aa:      	add.w	r12, r12, #0x3
    13ae:      	cmp.w	r12, #0x0
    13b2:      	beq	0x14a2 <text+0x146>     @ imm = #0xec
    13b4:      	sub.w	r1, r7, #0x5d
    13b8:      	movs	r4, #0x0
    13ba:      	add.w	r10, r1, #0x1
    13be:      	movs	r5, #0x40
    13c0:      	mov.w	r9, #0x0
    13c4:      	b	0x13e4 <text+0x88>      @ imm = #0x1c
    13c6:      	nop
    13c8:      	strb.w	r4, [r1, r11]
    13cc:      	movs	r0, #0x4
    13ce:      	subs.w	r12, r12, r11
    13d2:      	bkpt	#0xab
    13d4:      	sbc	r9, r9, #0x0
    13d8:      	rsbs.w	r0, r12, #0x0
    13dc:      	sbcs.w	r0, r4, r9
    13e0:      	add	r3, r11
    13e2:      	bge	0x14a2 <text+0x146>     @ imm = #0xbc
    13e4:      	mov.w	r11, #0x40
    13e8:      	cmp.w	r12, #0x40
    13ec:      	it	lo
    13ee:      	movlo	r11, r12
    13f0:      	cmp.w	r9, #0x0
    13f4:      	it	ne
    13f6:      	movne	r11, r5
    13f8:      	sub.w	r0, r11, #0x1
    13fc:      	cmp	r0, #0x3
    13fe:      	bhs	0x140c <text+0xb0>      @ imm = #0xa
    1400:      	movs	r0, #0x0
    1402:      	ands	r2, r11, #0x3
    1406:      	bne	0x146e <text+0x112>     @ imm = #0x64
    1408:      	b	0x13c8 <text+0x6c>      @ imm = #-0x44
    140a:      	nop
    140c:      	bic	r0, r11, #0x3
    1410:      	rsb.w	lr, r0, #0x0
    1414:      	mov	r1, r3
    1416:      	adds	r6, r3, #0x1
    1418:      	mvn	r2, #0x3
    141c:      	adds	r3, r6, r2
    141e:      	ldrb	r5, [r3, #0x3]
    1420:      	ldrb	r4, [r3, #0x4]
    1422:      	ldrb	r0, [r3, #0x5]
    1424:      	cmp	r5, #0x0
    1426:      	ldrb	r3, [r3, #0x6]
    1428:      	it	eq
    142a:      	moveq	r5, #0x20
    142c:      	add.w	r8, r10, r2
    1430:      	cmp	r4, #0x0
    1432:      	strb.w	r5, [r8, #0x3]
    1436:      	it	eq
    1438:      	moveq	r4, #0x20
    143a:      	strb.w	r4, [r8, #0x4]
    143e:      	cmp	r0, #0x0
    1440:      	it	eq
    1442:      	moveq	r0, #0x20
    1444:      	adds	r2, #0x4
    1446:      	strb.w	r0, [r8, #0x5]
    144a:      	cmp	r3, #0x0
    144c:      	add.w	r0, lr, r2
    1450:      	it	eq
    1452:      	moveq	r3, #0x20
    1454:      	adds	r0, #0x4
    1456:      	strb.w	r3, [r8, #0x6]
    145a:      	bne	0x141c <text+0xc0>      @ imm = #-0x42
    145c:      	adds	r0, r2, #0x4
    145e:      	mov	r3, r1
    1460:      	movs	r4, #0x0
    1462:      	sub.w	r1, r7, #0x5d
    1466:      	movs	r5, #0x40
    1468:      	ands	r2, r11, #0x3
    146c:      	beq	0x13c8 <text+0x6c>      @ imm = #-0xa8
    146e:      	ldrb	r6, [r3, r0]
    1470:      	cmp	r6, #0x0
    1472:      	it	eq
    1474:      	moveq	r6, #0x20
    1476:      	cmp	r2, #0x1
    1478:      	strb	r6, [r1, r0]
    147a:      	beq	0x13c8 <text+0x6c>      @ imm = #-0xb6
    147c:      	adds	r6, r0, #0x1
    147e:      	ldrb.w	lr, [r3, r6]
    1482:      	cmp.w	lr, #0x0
    1486:      	it	eq
    1488:      	moveq.w	lr, #0x20
    148c:      	cmp	r2, #0x2
    148e:      	strb.w	lr, [r1, r6]
    1492:      	beq	0x13c8 <text+0x6c>      @ imm = #-0xce
    1494:      	adds	r0, #0x2
    1496:      	ldrb	r2, [r3, r0]
    1498:      	cmp	r2, #0x0
    149a:      	it	eq
    149c:      	moveq	r2, #0x20
    149e:      	strb	r2, [r1, r0]
    14a0:      	b	0x13c8 <text+0x6c>      @ imm = #-0xdc
    14a2:      	movw	r9, #0xcccd
    14a6:      	ldrd	r4, r5, [sp]
    14aa:      	mov.w	r11, #0x1
    14ae:      	movt	r9, #0xcccc
    14b2:      	sub.w	r10, r7, #0x5d
    14b6:      	nop
    14b8:      	lsrs	r0, r4, #0x1
    14ba:      	orr.w	r0, r0, r5, lsl #31
    14be:      	adds.w	r1, r0, r5, lsr #1
    14c2:      	adc	r1, r1, #0x0
    14c6:      	umull	r2, r3, r1, r9
    14ca:      	bic	r2, r3, #0x3
    14ce:      	add.w	r2, r2, r3, lsr #2
    14d2:      	subs	r1, r1, r2
    14d4:      	subs	r1, r0, r1
    14d6:      	umull	r0, lr, r1, r9
    14da:      	lsr.w	r3, r5, #0x1
    14de:      	add.w	r6, r0, r0, lsl #2
    14e2:      	sbc	r2, r3, #0x0
    14e6:      	sub.w	r6, r4, r6, lsl #1
    14ea:      	mov	r3, r4
    14ec:      	subs	r4, #0xa
    14ee:      	orr	r12, r6, #0x30
    14f2:      	add.w	r8, r10, r11
    14f6:      	sbcs	r4, r5, #0x0
    14fa:      	strb	r12, [r8, #-1]
    14fe:      	blo	0x15f6 <text+0x29a>     @ imm = #0xf4
    1500:      	mov.w	r4, #0xcccccccc
    1504:      	mla	r1, r1, r4, lr
    1508:      	mla	r1, r2, r9, r1
    150c:      	lsrs	r2, r0, #0x1
    150e:      	orr.w	r2, r2, r1, lsl #31
    1512:      	adds.w	r1, r2, r1, lsr #1
    1516:      	adc	r1, r1, #0x0
    151a:      	umull	r2, r4, r1, r9
    151e:      	bic	r2, r4, #0x3
    1522:      	add.w	r2, r2, r4, lsr #2
    1526:      	subs	r1, r1, r2
    1528:      	and	r0, r0, #0x1
    152c:      	orr.w	r0, r0, r1, lsl #1
    1530:      	subs.w	r1, r3, #0x64
    1534:      	orr	r0, r0, #0x30
    1538:      	sbcs	r1, r5, #0x0
    153c:      	mov	r4, r10
    153e:      	strb.w	r0, [r10, r11]
    1542:      	blo	0x1600 <text+0x2a4>     @ imm = #0xba
    1544:      	mov	r6, r3
    1546:      	mov	r0, r3
    1548:      	mov	r1, r5
    154a:      	movs	r2, #0x64
    154c:      	movs	r3, #0x0
    154e:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x3e6
    1552:      	lsrs	r2, r0, #0x1
    1554:      	orr.w	r2, r2, r1, lsl #31
    1558:      	adds.w	r1, r2, r1, lsr #1
    155c:      	adc	r1, r1, #0x0
    1560:      	umull	r2, r3, r1, r9
    1564:      	bic	r2, r3, #0x3
    1568:      	add.w	r2, r2, r3, lsr #2
    156c:      	subs	r1, r1, r2
    156e:      	and	r0, r0, #0x1
    1572:      	orr.w	r0, r0, r1, lsl #1
    1576:      	subs.w	r1, r6, #0x3e8
    157a:      	orr	r0, r0, #0x30
    157e:      	sbcs	r1, r5, #0x0
    1582:      	strb.w	r0, [r8, #0x1]
    1586:      	blo	0x1608 <text+0x2ac>     @ imm = #0x7e
    1588:      	mov	r0, r6
    158a:      	mov	r1, r5
    158c:      	mov.w	r2, #0x3e8
    1590:      	movs	r3, #0x0
    1592:      	mov	r10, r4
    1594:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x3a0
    1598:      	lsrs	r2, r0, #0x1
    159a:      	orr.w	r2, r2, r1, lsl #31
    159e:      	adds.w	r1, r2, r1, lsr #1
    15a2:      	adc	r1, r1, #0x0
    15a6:      	umull	r2, r3, r1, r9
    15aa:      	bic	r2, r3, #0x3
    15ae:      	add.w	r2, r2, r3, lsr #2
    15b2:      	subs	r1, r1, r2
    15b4:      	and	r0, r0, #0x1
    15b8:      	orr.w	r0, r0, r1, lsl #1
    15bc:      	orr	r0, r0, #0x30
    15c0:      	strb.w	r0, [r8, #0x2]
    15c4:      	mov	r0, r6
    15c6:      	mov	r1, r5
    15c8:      	movw	r2, #0x2710
    15cc:      	movs	r3, #0x0
    15ce:      	bl	0x1938 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x366
    15d2:      	movw	r2, #0x270f
    15d6:      	subs	r2, r2, r6
    15d8:      	mov.w	r2, #0x0
    15dc:      	sbcs	r2, r5
    15de:      	add.w	r11, r11, #0x4
    15e2:      	mov	r4, r0
    15e4:      	mov	r5, r1
    15e6:      	blo.w	0x14b8 <text+0x15c>     @ imm = #-0x132
    15ea:      	sub.w	r1, r11, #0x1
    15ee:      	sub.w	r12, r11, #0x2
    15f2:      	mov	r11, r1
    15f4:      	b	0x15fc <text+0x2a0>     @ imm = #0x4
    15f6:      	sub.w	r12, r11, #0x1
    15fa:      	mov	r1, r11
    15fc:      	mov	r4, r10
    15fe:      	b	0x1612 <text+0x2b6>     @ imm = #0x10
    1600:      	add.w	r1, r11, #0x1
    1604:      	mov	r12, r11
    1606:      	b	0x1610 <text+0x2b4>     @ imm = #0x6
    1608:      	add.w	r1, r11, #0x2
    160c:      	add.w	r12, r11, #0x1
    1610:      	mov	r11, r1
    1612:      	and	lr, r1, #0x3
    1616:      	lsrs	r3, r1, #0x2
    1618:      	mov.w	r1, #0x0
    161c:      	beq	0x1656 <text+0x2fa>     @ imm = #0x36
    161e:      	sub.w	r6, r7, #0x75
    1622:      	add.w	r5, r12, r4
    1626:      	sub.w	r9, r1, r3, lsl #2
    162a:      	subs	r6, #0x3
    162c:      	subs	r5, #0x1
    162e:      	nop
    1630:      	adds	r4, r5, r1
    1632:      	ldrb	r3, [r5, r1]
    1634:      	ldrb	r0, [r4, #-2]
    1638:      	ldrb	r2, [r4, #-1]
    163c:      	ldrb	r4, [r4, #0x1]
    163e:      	subs	r1, #0x4
    1640:      	strb	r3, [r6, #4]!
    1644:      	cmp	r9, r1
    1646:      	strb	r4, [r6, #-1]
    164a:      	strb	r2, [r6, #0x1]
    164c:      	strb	r0, [r6, #0x2]
    164e:      	bne	0x1630 <text+0x2d4>     @ imm = #-0x22
    1650:      	rsbs	r1, r1, #0
    1652:      	sub.w	r4, r7, #0x5d
    1656:      	cmp.w	lr, #0x0
    165a:      	beq	0x1688 <text+0x32c>     @ imm = #0x2a
    165c:      	sub.w	r0, r12, r1
    1660:      	ldrb	r0, [r4, r0]
    1662:      	sub.w	r3, r7, #0x75
    1666:      	cmp.w	lr, #0x1
    166a:      	strb	r0, [r3, r1]
    166c:      	beq	0x1688 <text+0x32c>     @ imm = #0x18
    166e:      	adds	r0, r1, #0x1
    1670:      	sub.w	r2, r12, r0
    1674:      	ldrb	r2, [r4, r2]
    1676:      	cmp.w	lr, #0x2
    167a:      	strb	r2, [r3, r0]
    167c:      	beq	0x1688 <text+0x32c>     @ imm = #0x8
    167e:      	adds	r0, r1, #0x2
    1680:      	sub.w	r1, r12, r0
    1684:      	ldrb	r1, [r4, r1]
    1686:      	strb	r1, [r3, r0]
    1688:      	sub.w	r0, r7, #0x75
    168c:      	movs	r1, #0x0
    168e:      	mov.w	r12, #0xffffffff
    1692:      	strb.w	r1, [r0, r11]
    1696:      	nop
    1698:      	add.w	r1, r0, r12
    169c:      	ldrb	r3, [r1, #0x1]
    169e:      	cbz	r3, 0x16ba <text+0x35e> @ imm = #0x18
    16a0:      	ldrb	r3, [r1, #0x2]
    16a2:      	cbz	r3, 0x16c6 <text+0x36a> @ imm = #0x20
    16a4:      	ldrb	r3, [r1, #0x3]
    16a6:      	cbz	r3, 0x16d2 <text+0x376> @ imm = #0x28
    16a8:      	ldrb	r1, [r1, #0x4]
    16aa:      	add.w	r12, r12, #0x4
    16ae:      	cmp	r1, #0x0
    16b0:      	bne	0x1698 <text+0x33c>     @ imm = #-0x1c
    16b2:      	cmp.w	r12, #0x0
    16b6:      	bne	0x16dc <text+0x380>     @ imm = #0x22
    16b8:      	b	0x17c4 <text+0x468>     @ imm = #0x108
    16ba:      	add.w	r12, r12, #0x1
    16be:      	cmp.w	r12, #0x0
    16c2:      	bne	0x16dc <text+0x380>     @ imm = #0x16
    16c4:      	b	0x17c4 <text+0x468>     @ imm = #0xfc
    16c6:      	add.w	r12, r12, #0x2
    16ca:      	cmp.w	r12, #0x0
    16ce:      	bne	0x16dc <text+0x380>     @ imm = #0xa
    16d0:      	b	0x17c4 <text+0x468>     @ imm = #0xf0
    16d2:      	add.w	r12, r12, #0x3
    16d6:      	cmp.w	r12, #0x0
    16da:      	beq	0x17c4 <text+0x468>     @ imm = #0xe6
    16dc:      	movs	r2, #0x0
    16de:      	add.w	lr, r4, #0x1
    16e2:      	sub.w	r9, r7, #0x75
    16e6:      	movs	r3, #0x40
    16e8:      	mov.w	r11, #0x0
    16ec:      	b	0x170e <text+0x3b2>     @ imm = #0x1e
    16ee:      	nop
    16f0:      	strb.w	r2, [r4, r8]
    16f4:      	movs	r0, #0x4
    16f6:      	subs.w	r12, r12, r8
    16fa:      	mov	r1, r4
    16fc:      	bkpt	#0xab
    16fe:      	sbc	r11, r11, #0x0
    1702:      	rsbs.w	r0, r12, #0x0
    1706:      	sbcs.w	r0, r2, r11
    170a:      	add	r9, r8
    170c:      	bge	0x17c4 <text+0x468>     @ imm = #0xb4
    170e:      	mov.w	r8, #0x40
    1712:      	cmp.w	r12, #0x40
    1716:      	it	lo
    1718:      	movlo	r8, r12
    171a:      	cmp.w	r11, #0x0
    171e:      	it	ne
    1720:      	movne	r8, r3
    1722:      	sub.w	r0, r8, #0x1
    1726:      	cmp	r0, #0x3
    1728:      	bhs	0x1734 <text+0x3d8>     @ imm = #0x8
    172a:      	movs	r0, #0x0
    172c:      	ands	r1, r8, #0x3
    1730:      	bne	0x178e <text+0x432>     @ imm = #0x5a
    1732:      	b	0x16f0 <text+0x394>     @ imm = #-0x46
    1734:      	bic	r0, r8, #0x3
    1738:      	rsb.w	r10, r0, #0x0
    173c:      	add.w	r5, r9, #0x1
    1740:      	mvn	r1, #0x3
    1744:      	adds	r4, r5, r1
    1746:      	ldrb	r2, [r4, #0x3]
    1748:      	ldrb	r3, [r4, #0x4]
    174a:      	ldrb	r6, [r4, #0x5]
    174c:      	cmp	r2, #0x0
    174e:      	ldrb	r4, [r4, #0x6]
    1750:      	it	eq
    1752:      	moveq	r2, #0x20
    1754:      	add.w	r0, lr, r1
    1758:      	cmp	r3, #0x0
    175a:      	strb	r2, [r0, #0x3]
    175c:      	it	eq
    175e:      	moveq	r3, #0x20
    1760:      	cmp	r6, #0x0
    1762:      	add.w	r1, r1, #0x4
    1766:      	strb	r3, [r0, #0x4]
    1768:      	it	eq
    176a:      	moveq	r6, #0x20
    176c:      	cmp	r4, #0x0
    176e:      	add.w	r2, r10, r1
    1772:      	strb	r6, [r0, #0x5]
    1774:      	it	eq
    1776:      	moveq	r4, #0x20
    1778:      	adds	r2, #0x4
    177a:      	strb	r4, [r0, #0x6]
    177c:      	bne	0x1744 <text+0x3e8>     @ imm = #-0x3c
    177e:      	adds	r0, r1, #0x4
    1780:      	sub.w	r4, r7, #0x5d
    1784:      	movs	r2, #0x0
    1786:      	movs	r3, #0x40
    1788:      	ands	r1, r8, #0x3
    178c:      	beq	0x16f0 <text+0x394>     @ imm = #-0xa0
    178e:      	ldrb.w	r5, [r9, r0]
    1792:      	cmp	r5, #0x0
    1794:      	it	eq
    1796:      	moveq	r5, #0x20
    1798:      	cmp	r1, #0x1
    179a:      	strb	r5, [r4, r0]
    179c:      	beq	0x16f0 <text+0x394>     @ imm = #-0xb0
    179e:      	add.w	r10, r0, #0x1
    17a2:      	ldrb.w	r5, [r9, r10]
    17a6:      	cmp	r5, #0x0
    17a8:      	it	eq
    17aa:      	moveq	r5, #0x20
    17ac:      	cmp	r1, #0x2
    17ae:      	strb.w	r5, [r4, r10]
    17b2:      	beq	0x16f0 <text+0x394>     @ imm = #-0xc6
    17b4:      	adds	r0, #0x2
    17b6:      	ldrb.w	r1, [r9, r0]
    17ba:      	cmp	r1, #0x0
    17bc:      	it	eq
    17be:      	moveq	r1, #0x20
    17c0:      	strb	r1, [r4, r0]
    17c2:      	b	0x16f0 <text+0x394>     @ imm = #-0xd6
    17c4:      	add	sp, #0x64
    17c6:      	pop.w	{r8, r9, r10, r11}
    17ca:      	pop	{r4, r5, r6, r7, pc}

000017cc <compiler_rt.memset>:
    17cc:      	cmp	r2, #0x0
    17ce:      	it	eq
    17d0:      	bxeq	lr
    17d2:      	push	{r7, lr}
    17d4:      	mov	r7, sp
    17d6:      	ands	lr, r2, #0x3
    17da:      	mov	r3, r2
    17dc:      	mov	r12, r0
    17de:      	beq	0x1802 <compiler_rt.memset+0x36> @ imm = #0x20
    17e0:      	mov	r12, r0
    17e2:      	cmp.w	lr, #0x1
    17e6:      	strb	r1, [r12], #1
    17ea:      	bne	0x17f4 <compiler_rt.memset+0x28> @ imm = #0x6
    17ec:      	subs	r3, r2, #0x1
    17ee:      	cmp	r2, #0x4
    17f0:      	bhs	0x1806 <compiler_rt.memset+0x3a> @ imm = #0x12
    17f2:      	b	0x181a <compiler_rt.memset+0x4e> @ imm = #0x24
    17f4:      	cmp.w	lr, #0x2
    17f8:      	strb	r1, [r0, #0x1]
    17fa:      	bne	0x1820 <compiler_rt.memset+0x54> @ imm = #0x22
    17fc:      	subs	r3, r2, #0x2
    17fe:      	add.w	r12, r0, #0x2
    1802:      	cmp	r2, #0x4
    1804:      	blo	0x181a <compiler_rt.memset+0x4e> @ imm = #0x12
    1806:      	sub.w	r2, r12, #0x4
    180a:      	nop
    180c:      	strb	r1, [r2, #4]!
    1810:      	subs	r3, #0x4
    1812:      	strb	r1, [r2, #0x1]
    1814:      	strb	r1, [r2, #0x2]
    1816:      	strb	r1, [r2, #0x3]
    1818:      	bne	0x180c <compiler_rt.memset+0x40> @ imm = #-0x10
    181a:      	pop.w	{r7, lr}
    181e:      	bx	lr
    1820:      	subs	r3, r2, #0x3
    1822:      	add.w	r12, r0, #0x3
    1826:      	strb	r1, [r0, #0x2]
    1828:      	cmp	r2, #0x4
    182a:      	bhs	0x1806 <compiler_rt.memset+0x3a> @ imm = #-0x28
    182c:      	b	0x181a <compiler_rt.memset+0x4e> @ imm = #-0x16
    182e:      	bmi	0x17da <compiler_rt.memset+0xe> @ imm = #-0x58

00001830 <compiler_rt.arm.__aeabi_unwind_cpp_pr0>:
    1830:      	push	{r7, lr}
    1832:      	mov	r7, sp
    1834:      	pop	{r7, pc}
    1836:      	bmi	0x17e2 <compiler_rt.memset+0x16> @ imm = #-0x58

00001838 <compiler_rt.arm.__aeabi_memset>:
    1838:      	push	{r7, lr}
    183a:      	mov	r7, sp
    183c:      	mov	r3, r1
    183e:      	mov	r1, r2
    1840:      	mov	r2, r3
    1842:      	pop.w	{r7, lr}
    1846:      	b.w	0x17cc <compiler_rt.memset> @ imm = #-0x7e
    184a:      	bmi	0x17f6 <compiler_rt.memset+0x2a> @ imm = #-0x58

0000184c <compiler_rt.arm.__aeabi_memcpy>:
    184c:      	push	{r4, r5, r6, r7, lr}
    184e:      	add	r7, sp, #0xc
    1850:      	push.w	{r8, r9, r10, r11}
    1854:      	sub	sp, #0x4
    1856:      	cmp	r2, #0xf
    1858:      	bhi	0x1878 <compiler_rt.arm.__aeabi_memcpy+0x2c> @ imm = #0x1c
    185a:      	cmp	r2, #0x3
    185c:      	bhi	0x18a0 <compiler_rt.arm.__aeabi_memcpy+0x54> @ imm = #0x40
    185e:      	cbz	r2, 0x1870 <compiler_rt.arm.__aeabi_memcpy+0x24> @ imm = #0xe
    1860:      	ldrb	r3, [r1]
    1862:      	strb	r3, [r0]
    1864:      	lsrs	r3, r2, #0x1
    1866:      	subs	r2, #0x1
    1868:      	ldrb	r6, [r1, r3]
    186a:      	ldrb	r1, [r1, r2]
    186c:      	strb	r6, [r0, r3]
    186e:      	strb	r1, [r0, r2]
    1870:      	add	sp, #0x4
    1872:      	pop.w	{r8, r9, r10, r11}
    1876:      	pop	{r4, r5, r6, r7, pc}
    1878:      	ldr	r3, [r1]
    187a:      	mov.w	r6, #0xffffffff
    187e:      	str	r3, [r0]
    1880:      	and	r3, r1, #0x3
    1884:      	rsb.w	lr, r3, #0x4
    1888:      	sub.w	r4, r2, lr
    188c:      	add.w	r6, r6, r4, lsr #2
    1890:      	cmp	r6, #0x3
    1892:      	ubfx	r6, r4, #0x2, #0x2
    1896:      	str	r6, [sp]
    1898:      	bhs	0x18c4 <compiler_rt.arm.__aeabi_memcpy+0x78> @ imm = #0x28
    189a:      	movs	r3, #0x0
    189c:      	b	0x18f8 <compiler_rt.arm.__aeabi_memcpy+0xac> @ imm = #0x58
    189e:      	nop
    18a0:      	movs	r3, #0x4
    18a2:      	ldr	r6, [r1]
    18a4:      	and.w	r3, r3, r2, lsr #1
    18a8:      	subs	r2, #0x4
    18aa:      	str	r6, [r0]
    18ac:      	ldr	r6, [r1, r3]
    18ae:      	subs	r5, r2, r3
    18b0:      	str	r6, [r0, r3]
    18b2:      	ldr	r3, [r1, r5]
    18b4:      	ldr	r1, [r1, r2]
    18b6:      	str	r3, [r0, r5]
    18b8:      	str	r1, [r0, r2]
    18ba:      	add	sp, #0x4
    18bc:      	pop.w	{r8, r9, r10, r11}
    18c0:      	pop	{r4, r5, r6, r7, pc}
    18c2:      	nop
    18c4:      	lsrs	r4, r4, #0x2
    18c6:      	bic	r8, r4, #0x3
    18ca:      	sub.w	r9, r0, r3
    18ce:      	sub.w	r10, r1, r3
    18d2:      	movs	r3, #0x0
    18d4:      	add.w	r5, r10, r3, lsl #2
    18d8:      	add.w	r12, r5, #0x4
    18dc:      	add.w	r4, r9, r3, lsl #2
    18e0:      	ldm.w	r12, {r6, r11, r12}
    18e4:      	ldr	r5, [r5, #0x10]
    18e6:      	adds	r3, #0x4
    18e8:      	cmp	r8, r3
    18ea:      	str	r6, [r4, #0x4]
    18ec:      	str.w	r11, [r4, #0x8]
    18f0:      	str.w	r12, [r4, #0xc]
    18f4:      	str	r5, [r4, #0x10]
    18f6:      	bne	0x18d4 <compiler_rt.arm.__aeabi_memcpy+0x88> @ imm = #-0x26
    18f8:      	ldr	r4, [sp]
    18fa:      	cbz	r4, 0x1928 <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x2a
    18fc:      	add.w	r6, r1, lr
    1900:      	ldr.w	r5, [r6, r3, lsl #2]
    1904:      	add.w	r8, r0, lr
    1908:      	cmp	r4, #0x1
    190a:      	str.w	r5, [r8, r3, lsl #2]
    190e:      	beq	0x1928 <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x16
    1910:      	adds	r5, r3, #0x1
    1912:      	ldr.w	r12, [r6, r5, lsl #2]
    1916:      	cmp	r4, #0x2
    1918:      	str.w	r12, [r8, r5, lsl #2]
    191c:      	beq	0x1928 <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x8
    191e:      	adds	r3, #0x2
    1920:      	ldr.w	r6, [r6, r3, lsl #2]
    1924:      	str.w	r6, [r8, r3, lsl #2]
    1928:      	subs	r2, #0x4
    192a:      	ldr	r1, [r1, r2]
    192c:      	str	r1, [r0, r2]
    192e:      	add	sp, #0x4
    1930:      	pop.w	{r8, r9, r10, r11}
    1934:      	pop	{r4, r5, r6, r7, pc}
    1936:      	bmi	0x18e2 <compiler_rt.arm.__aeabi_memcpy+0x96> @ imm = #-0x58

00001938 <compiler_rt.arm.__aeabi_uldivmod>:
    1938:      	push	{r4, lr}
    193a:      	sub	sp, #0x10
    193c:      	add	r4, sp, #0x8
    193e:      	str	r4, [sp]
    1940:      	bl	0x194c <compiler_rt.int.__udivmoddi4> @ imm = #0x8
    1944:      	ldr	r2, [sp, #0x8]
    1946:      	ldr	r3, [sp, #0xc]
    1948:      	add	sp, #0x10
    194a:      	pop	{r4, pc}

0000194c <compiler_rt.int.__udivmoddi4>:
    194c:      	push	{r4, r5, r6, r7, lr}
    194e:      	add	r7, sp, #0xc
    1950:      	push.w	{r8, r9, r10, r11}
    1954:      	sub	sp, #0x20
    1956:      	mov	r5, r2
    1958:      	ldr	r6, [r7, #0x8]
    195a:      	subs	r2, r0, r2
    195c:      	sbcs.w	r2, r1, r3
    1960:      	bhs	0x1978 <compiler_rt.int.__udivmoddi4+0x2c> @ imm = #0x14
    1962:      	cmp	r6, #0x0
    1964:      	it	ne
    1966:      	strdne	r0, r1, [r6]
    196a:      	movs	r0, #0x0
    196c:      	movs	r1, #0x0
    196e:      	add	sp, #0x20
    1970:      	pop.w	{r8, r9, r10, r11}
    1974:      	pop	{r4, r5, r6, r7, pc}
    1976:      	nop
    1978:      	cmp	r3, #0x0
    197a:      	beq.w	0x1a84 <compiler_rt.int.__udivmoddi4+0x138> @ imm = #0x106
    197e:      	clz	r2, r3
    1982:      	cmp	r2, #0x0
    1984:      	beq.w	0x1ab0 <compiler_rt.int.__udivmoddi4+0x164> @ imm = #0x128
    1988:      	rsbs	r6, r2, #0
    198a:      	and	r4, r6, #0x1f
    198e:      	lsl.w	r12, r3, r2
    1992:      	lsr.w	r6, r5, r4
    1996:      	orr.w	r8, r6, r12
    199a:      	lsl.w	r2, r1, r2
    199e:      	lsr.w	r6, r0, r4
    19a2:      	clz	lr, r8
    19a6:      	orrs	r2, r6
    19a8:      	ands	r12, lr, #0x1f
    19ac:      	lsr.w	r6, r1, r4
    19b0:      	str	r5, [sp, #0x10]
    19b2:      	str	r0, [sp, #0x4]
    19b4:      	beq	0x19d0 <compiler_rt.int.__udivmoddi4+0x84> @ imm = #0x18
    19b6:      	lsl.w	r4, r6, r12
    19ba:      	rsb.w	r6, lr, #0x0
    19be:      	and	r6, r6, #0x1f
    19c2:      	lsr.w	r6, r2, r6
    19c6:      	lsl.w	r8, r8, r12
    19ca:      	orrs	r6, r4
    19cc:      	lsl.w	r2, r2, r12
    19d0:      	lsr.w	lr, r8, #0x10
    19d4:      	udiv	r4, r6, lr
    19d8:      	strd	r3, r1, [sp, #8]
    19dc:      	mls	r9, r4, lr, r6
    19e0:      	uxth.w	r12, r8
    19e4:      	lsr.w	r11, r2, #0x10
    19e8:      	uxth	r3, r2
    19ea:      	mov	r0, r6
    19ec:      	mov.w	r10, #0x0
    19f0:      	str.w	r8, [sp]
    19f4:      	b	0x1a08 <compiler_rt.int.__udivmoddi4+0xbc> @ imm = #0x10
    19f6:      	nop
    19f8:      	subs	r6, r4, #0x4
    19fa:      	add.w	r9, r2, lr
    19fe:      	cmp.w	r10, r9, lsr #16
    1a02:      	mov	r4, r6
    1a04:      	bne.w	0x1c42 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x23a
    1a08:      	cmp.w	r10, r4, lsr #16
    1a0c:      	bne	0x1a1c <compiler_rt.int.__udivmoddi4+0xd0> @ imm = #0xc
    1a0e:      	mul	r2, r4, r12
    1a12:      	orr.w	r6, r11, r9, lsl #16
    1a16:      	cmp	r2, r6
    1a18:      	bls.w	0x1c40 <compiler_rt.int.__udivmoddi4+0x2f4> @ imm = #0x224
    1a1c:      	add.w	r2, r9, lr
    1a20:      	cmp.w	r10, r2, lsr #16
    1a24:      	sub.w	r6, r4, #0x1
    1a28:      	bne.w	0x1c42 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x216
    1a2c:      	cmp.w	r10, r6, lsr #16
    1a30:      	bne	0x1a40 <compiler_rt.int.__udivmoddi4+0xf4> @ imm = #0xc
    1a32:      	mul	r9, r6, r12
    1a36:      	orr.w	r8, r11, r2, lsl #16
    1a3a:      	cmp	r9, r8
    1a3c:      	bls.w	0x1c42 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x202
    1a40:      	add	r2, lr
    1a42:      	cmp.w	r10, r2, lsr #16
    1a46:      	sub.w	r6, r4, #0x2
    1a4a:      	bne.w	0x1c42 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1f4
    1a4e:      	cmp.w	r10, r6, lsr #16
    1a52:      	bne	0x1a62 <compiler_rt.int.__udivmoddi4+0x116> @ imm = #0xc
    1a54:      	mul	r8, r6, r12
    1a58:      	orr.w	r5, r11, r2, lsl #16
    1a5c:      	cmp	r8, r5
    1a5e:      	bls.w	0x1c42 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1e0
    1a62:      	add	r2, lr
    1a64:      	cmp.w	r10, r2, lsr #16
    1a68:      	sub.w	r6, r4, #0x3
    1a6c:      	bne.w	0x1c42 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1d2
    1a70:      	cmp.w	r10, r6, lsr #16
    1a74:      	bne	0x19f8 <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x80
    1a76:      	mul	r5, r6, r12
    1a7a:      	orr.w	r1, r11, r2, lsl #16
    1a7e:      	cmp	r5, r1
    1a80:      	bhi	0x19f8 <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x8c
    1a82:      	b	0x1c42 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1bc
    1a84:      	cmp	r1, r5
    1a86:      	clz	lr, r5
    1a8a:      	bhs	0x1ac8 <compiler_rt.int.__udivmoddi4+0x17c> @ imm = #0x3a
    1a8c:      	cmp.w	lr, #0x0
    1a90:      	beq.w	0x1b98 <compiler_rt.int.__udivmoddi4+0x24c> @ imm = #0x104
    1a94:      	rsb.w	r2, lr, #0x0
    1a98:      	and	r2, r2, #0x1f
    1a9c:      	lsl.w	r1, r1, lr
    1aa0:      	lsr.w	r2, r0, r2
    1aa4:      	lsl.w	r5, r5, lr
    1aa8:      	orrs	r2, r1
    1aaa:      	lsl.w	r0, r0, lr
    1aae:      	b	0x1b9a <compiler_rt.int.__udivmoddi4+0x24e> @ imm = #0xe8
    1ab0:      	cbz	r6, 0x1aba <compiler_rt.int.__udivmoddi4+0x16e> @ imm = #0x6
    1ab2:      	subs	r0, r0, r5
    1ab4:      	sbcs	r1, r3
    1ab6:      	strd	r0, r1, [r6]
    1aba:      	movs	r1, #0x0
    1abc:      	movs	r0, #0x1
    1abe:      	add	sp, #0x20
    1ac0:      	pop.w	{r8, r9, r10, r11}
    1ac4:      	pop	{r4, r5, r6, r7, pc}
    1ac6:      	nop
    1ac8:      	udiv	r2, r1, r5
    1acc:      	cmp.w	lr, #0x0
    1ad0:      	mls	r8, r2, r5, r1
    1ad4:      	mov	r1, r2
    1ad6:      	beq	0x1af4 <compiler_rt.int.__udivmoddi4+0x1a8> @ imm = #0x1a
    1ad8:      	rsb.w	r3, lr, #0x0
    1adc:      	and	r3, r3, #0x1f
    1ae0:      	lsl.w	r2, r8, lr
    1ae4:      	lsr.w	r3, r0, r3
    1ae8:      	lsl.w	r5, r5, lr
    1aec:      	orr.w	r8, r2, r3
    1af0:      	lsl.w	r0, r0, lr
    1af4:      	lsrs	r4, r5, #0x10
    1af6:      	str	r5, [sp, #0x10]
    1af8:      	uxth.w	r12, r5
    1afc:      	udiv	r5, r8, r4
    1b00:      	lsr.w	r10, r0, #0x10
    1b04:      	mls	r6, r5, r4, r8
    1b08:      	uxth.w	r9, r0
    1b0c:      	movs	r3, #0x0
    1b0e:      	b	0x1b1e <compiler_rt.int.__udivmoddi4+0x1d2> @ imm = #0xc
    1b10:      	subs	r0, r5, #0x4
    1b12:      	adds	r6, r2, r4
    1b14:      	cmp.w	r3, r6, lsr #16
    1b18:      	mov	r5, r0
    1b1a:      	bne.w	0x1d5a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x23c
    1b1e:      	cmp.w	r3, r5, lsr #16
    1b22:      	bne	0x1b32 <compiler_rt.int.__udivmoddi4+0x1e6> @ imm = #0xc
    1b24:      	mul	r0, r5, r12
    1b28:      	orr.w	r2, r10, r6, lsl #16
    1b2c:      	cmp	r0, r2
    1b2e:      	bls.w	0x1d58 <compiler_rt.int.__udivmoddi4+0x40c> @ imm = #0x226
    1b32:      	adds	r2, r6, r4
    1b34:      	cmp.w	r3, r2, lsr #16
    1b38:      	sub.w	r0, r5, #0x1
    1b3c:      	bne.w	0x1d5a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x21a
    1b40:      	cmp.w	r3, r0, lsr #16
    1b44:      	bne	0x1b54 <compiler_rt.int.__udivmoddi4+0x208> @ imm = #0xc
    1b46:      	mul	r11, r0, r12
    1b4a:      	orr.w	r6, r10, r2, lsl #16
    1b4e:      	cmp	r11, r6
    1b50:      	bls.w	0x1d5a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x206
    1b54:      	add	r2, r4
    1b56:      	cmp.w	r3, r2, lsr #16
    1b5a:      	sub.w	r0, r5, #0x2
    1b5e:      	bne.w	0x1d5a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1f8
    1b62:      	cmp.w	r3, r0, lsr #16
    1b66:      	bne	0x1b76 <compiler_rt.int.__udivmoddi4+0x22a> @ imm = #0xc
    1b68:      	mul	r11, r0, r12
    1b6c:      	orr.w	r6, r10, r2, lsl #16
    1b70:      	cmp	r11, r6
    1b72:      	bls.w	0x1d5a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1e4
    1b76:      	add	r2, r4
    1b78:      	cmp.w	r3, r2, lsr #16
    1b7c:      	sub.w	r0, r5, #0x3
    1b80:      	bne.w	0x1d5a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1d6
    1b84:      	cmp.w	r3, r0, lsr #16
    1b88:      	bne	0x1b10 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x7c
    1b8a:      	mul	r11, r0, r12
    1b8e:      	orr.w	r6, r10, r2, lsl #16
    1b92:      	cmp	r11, r6
    1b94:      	bhi	0x1b10 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x88
    1b96:      	b	0x1d5a <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1c0
    1b98:      	mov	r2, r1
    1b9a:      	lsrs	r4, r5, #0x10
    1b9c:      	udiv	r6, r2, r4
    1ba0:      	mov	r11, r5
    1ba2:      	uxth.w	r9, r5
    1ba6:      	mls	r5, r6, r4, r2
    1baa:      	lsr.w	r8, r0, #0x10
    1bae:      	uxth.w	r12, r0
    1bb2:      	mov	r1, r2
    1bb4:      	movs	r3, #0x0
    1bb6:      	b	0x1bc6 <compiler_rt.int.__udivmoddi4+0x27a> @ imm = #0xc
    1bb8:      	subs	r0, r6, #0x4
    1bba:      	adds	r5, r2, r4
    1bbc:      	cmp.w	r3, r5, lsr #16
    1bc0:      	mov	r6, r0
    1bc2:      	bne.w	0x1df2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x22c
    1bc6:      	cmp.w	r3, r6, lsr #16
    1bca:      	bne	0x1bda <compiler_rt.int.__udivmoddi4+0x28e> @ imm = #0xc
    1bcc:      	mul	r0, r6, r9
    1bd0:      	orr.w	r2, r8, r5, lsl #16
    1bd4:      	cmp	r0, r2
    1bd6:      	bls.w	0x1df0 <compiler_rt.int.__udivmoddi4+0x4a4> @ imm = #0x216
    1bda:      	adds	r2, r5, r4
    1bdc:      	cmp.w	r3, r2, lsr #16
    1be0:      	sub.w	r0, r6, #0x1
    1be4:      	bne.w	0x1df2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x20a
    1be8:      	cmp.w	r3, r0, lsr #16
    1bec:      	bne	0x1bfc <compiler_rt.int.__udivmoddi4+0x2b0> @ imm = #0xc
    1bee:      	mul	r10, r0, r9
    1bf2:      	orr.w	r5, r8, r2, lsl #16
    1bf6:      	cmp	r10, r5
    1bf8:      	bls.w	0x1df2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1f6
    1bfc:      	add	r2, r4
    1bfe:      	cmp.w	r3, r2, lsr #16
    1c02:      	sub.w	r0, r6, #0x2
    1c06:      	bne.w	0x1df2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1e8
    1c0a:      	cmp.w	r3, r0, lsr #16
    1c0e:      	bne	0x1c1e <compiler_rt.int.__udivmoddi4+0x2d2> @ imm = #0xc
    1c10:      	mul	r10, r0, r9
    1c14:      	orr.w	r5, r8, r2, lsl #16
    1c18:      	cmp	r10, r5
    1c1a:      	bls.w	0x1df2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1d4
    1c1e:      	add	r2, r4
    1c20:      	cmp.w	r3, r2, lsr #16
    1c24:      	sub.w	r0, r6, #0x3
    1c28:      	bne.w	0x1df2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1c6
    1c2c:      	cmp.w	r3, r0, lsr #16
    1c30:      	bne	0x1bb8 <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x7c
    1c32:      	mul	r10, r0, r9
    1c36:      	orr.w	r5, r8, r2, lsl #16
    1c3a:      	cmp	r10, r5
    1c3c:      	bhi	0x1bb8 <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x88
    1c3e:      	b	0x1df2 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1b0
    1c40:      	mov	r6, r4
    1c42:      	orr.w	r2, r11, r0, lsl #16
    1c46:      	ldr	r0, [sp]
    1c48:      	ldr.w	r9, [sp, #0x4]
    1c4c:      	mls	r2, r6, r0, r2
    1c50:      	mov.w	r8, #0x0
    1c54:      	udiv	r4, r2, lr
    1c58:      	mls	r2, r4, lr, r2
    1c5c:      	b	0x1c6c <compiler_rt.int.__udivmoddi4+0x320> @ imm = #0xc
    1c5e:      	nop
    1c60:      	subs	r4, #0x4
    1c62:      	add	r2, lr
    1c64:      	cmp.w	r2, #0x10000
    1c68:      	mov	r5, r4
    1c6a:      	bhs	0x1cde <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x70
    1c6c:      	cmp.w	r8, r4, lsr #16
    1c70:      	bne	0x1c7e <compiler_rt.int.__udivmoddi4+0x332> @ imm = #0xa
    1c72:      	mul	r1, r4, r12
    1c76:      	orr.w	r5, r3, r2, lsl #16
    1c7a:      	cmp	r1, r5
    1c7c:      	bls	0x1cdc <compiler_rt.int.__udivmoddi4+0x390> @ imm = #0x5c
    1c7e:      	add	r2, lr
    1c80:      	cmp.w	r8, r2, lsr #16
    1c84:      	sub.w	r5, r4, #0x1
    1c88:      	bne	0x1cde <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x52
    1c8a:      	cmp.w	r8, r5, lsr #16
    1c8e:      	bne	0x1c9c <compiler_rt.int.__udivmoddi4+0x350> @ imm = #0xa
    1c90:      	mul	r1, r5, r12
    1c94:      	orr.w	r0, r3, r2, lsl #16
    1c98:      	cmp	r1, r0
    1c9a:      	bls	0x1cde <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x40
    1c9c:      	add	r2, lr
    1c9e:      	cmp.w	r8, r2, lsr #16
    1ca2:      	sub.w	r5, r4, #0x2
    1ca6:      	bne	0x1cde <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x34
    1ca8:      	cmp.w	r8, r5, lsr #16
    1cac:      	bne	0x1cba <compiler_rt.int.__udivmoddi4+0x36e> @ imm = #0xa
    1cae:      	mul	r0, r5, r12
    1cb2:      	orr.w	r1, r3, r2, lsl #16
    1cb6:      	cmp	r0, r1
    1cb8:      	bls	0x1cde <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x22
    1cba:      	add	r2, lr
    1cbc:      	cmp.w	r8, r2, lsr #16
    1cc0:      	sub.w	r5, r4, #0x3
    1cc4:      	bne	0x1cde <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x16
    1cc6:      	cmp.w	r8, r5, lsr #16
    1cca:      	bne	0x1c60 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x6e
    1ccc:      	mul	r0, r5, r12
    1cd0:      	orr.w	r1, r3, r2, lsl #16
    1cd4:      	cmp	r0, r1
    1cd6:      	bhi	0x1c60 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x7a
    1cd8:      	b	0x1cde <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x2
    1cda:      	nop
    1cdc:      	mov	r5, r4
    1cde:      	add.w	r0, r5, r6, lsl #16
    1ce2:      	ldr	r2, [sp, #0x10]
    1ce4:      	ldr	r6, [sp, #0x8]
    1ce6:      	umull	r4, r1, r2, r0
    1cea:      	mov	r8, r0
    1cec:      	umull	r0, r3, r6, r0
    1cf0:      	adds	r5, r0, r1
    1cf2:      	mov.w	r12, #0x0
    1cf6:      	adc	r0, r12, #0x0
    1cfa:      	orrs.w	r1, r3, r0
    1cfe:      	ldr	r3, [r7, #0x8]
    1d00:      	ldr.w	lr, [sp, #0xc]
    1d04:      	strb.w	r0, [sp, #0x14]
    1d08:      	bne	0x1d14 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x8
    1d0a:      	cmp	r5, lr
    1d0c:      	bhi	0x1d14 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x4
    1d0e:      	bne	0x1d2a <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x18
    1d10:      	cmp	r4, r9
    1d12:      	bls	0x1d2a <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x14
    1d14:      	subs	r4, r4, r2
    1d16:      	adc	r0, r12, #0x0
    1d1a:      	eor	r0, r0, #0x1
    1d1e:      	strb.w	r0, [sp, #0x18]
    1d22:      	add	r0, r6
    1d24:      	sub.w	r8, r8, #0x1
    1d28:      	subs	r5, r5, r0
    1d2a:      	cbz	r3, 0x1d4a <compiler_rt.int.__udivmoddi4+0x3fe> @ imm = #0x1c
    1d2c:      	subs.w	r0, r9, r4
    1d30:      	mov.w	r1, #0x0
    1d34:      	adc	r1, r1, #0x0
    1d38:      	eor	r1, r1, #0x1
    1d3c:      	strb.w	r1, [sp, #0x1c]
    1d40:      	add	r1, r5
    1d42:      	sub.w	r1, lr, r1
    1d46:      	strd	r0, r1, [r3]
    1d4a:      	movs	r1, #0x0
    1d4c:      	mov	r0, r8
    1d4e:      	add	sp, #0x20
    1d50:      	pop.w	{r8, r9, r10, r11}
    1d54:      	pop	{r4, r5, r6, r7, pc}
    1d56:      	nop
    1d58:      	mov	r0, r5
    1d5a:      	ldr	r3, [sp, #0x10]
    1d5c:      	orr.w	r2, r10, r8, lsl #16
    1d60:      	mls	r8, r0, r3, r2
    1d64:      	mov.w	r10, #0x0
    1d68:      	udiv	r3, r8, r4
    1d6c:      	mls	r5, r3, r4, r8
    1d70:      	b	0x1d82 <compiler_rt.int.__udivmoddi4+0x436> @ imm = #0xe
    1d72:      	nop
    1d74:      	subs	r3, #0x4
    1d76:      	adds	r5, r2, r4
    1d78:      	cmp.w	r5, #0x10000
    1d7c:      	mov	r6, r3
    1d7e:      	bhs.w	0x1e86 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x104
    1d82:      	cmp.w	r10, r3, lsr #16
    1d86:      	bne	0x1d94 <compiler_rt.int.__udivmoddi4+0x448> @ imm = #0xa
    1d88:      	mul	r2, r3, r12
    1d8c:      	orr.w	r6, r9, r5, lsl #16
    1d90:      	cmp	r2, r6
    1d92:      	bls	0x1e84 <compiler_rt.int.__udivmoddi4+0x538> @ imm = #0xee
    1d94:      	adds	r2, r5, r4
    1d96:      	cmp.w	r10, r2, lsr #16
    1d9a:      	sub.w	r6, r3, #0x1
    1d9e:      	bne	0x1e86 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xe4
    1da0:      	cmp.w	r10, r6, lsr #16
    1da4:      	bne	0x1db2 <compiler_rt.int.__udivmoddi4+0x466> @ imm = #0xa
    1da6:      	mul	r11, r6, r12
    1daa:      	orr.w	r5, r9, r2, lsl #16
    1dae:      	cmp	r11, r5
    1db0:      	bls	0x1e86 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xd2
    1db2:      	add	r2, r4
    1db4:      	cmp.w	r10, r2, lsr #16
    1db8:      	sub.w	r6, r3, #0x2
    1dbc:      	bne	0x1e86 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xc6
    1dbe:      	cmp.w	r10, r6, lsr #16
    1dc2:      	bne	0x1dd0 <compiler_rt.int.__udivmoddi4+0x484> @ imm = #0xa
    1dc4:      	mul	r11, r6, r12
    1dc8:      	orr.w	r5, r9, r2, lsl #16
    1dcc:      	cmp	r11, r5
    1dce:      	bls	0x1e86 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xb4
    1dd0:      	add	r2, r4
    1dd2:      	cmp.w	r10, r2, lsr #16
    1dd6:      	sub.w	r6, r3, #0x3
    1dda:      	bne	0x1e86 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xa8
    1ddc:      	cmp.w	r10, r6, lsr #16
    1de0:      	bne	0x1d74 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x70
    1de2:      	mul	r11, r6, r12
    1de6:      	orr.w	r5, r9, r2, lsl #16
    1dea:      	cmp	r11, r5
    1dec:      	bhi	0x1d74 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x7c
    1dee:      	b	0x1e86 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x94
    1df0:      	mov	r0, r6
    1df2:      	orr.w	r1, r8, r1, lsl #16
    1df6:      	mls	r8, r0, r11, r1
    1dfa:      	mov.w	r10, #0x0
    1dfe:      	udiv	r1, r8, r4
    1e02:      	mls	r5, r1, r4, r8
    1e06:      	b	0x1e14 <compiler_rt.int.__udivmoddi4+0x4c8> @ imm = #0xa
    1e08:      	subs	r1, #0x4
    1e0a:      	adds	r5, r2, r4
    1e0c:      	cmp.w	r5, #0x10000
    1e10:      	mov	r6, r1
    1e12:      	bhs	0x1e9a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x84
    1e14:      	cmp.w	r10, r1, lsr #16
    1e18:      	bne	0x1e26 <compiler_rt.int.__udivmoddi4+0x4da> @ imm = #0xa
    1e1a:      	mul	r2, r1, r9
    1e1e:      	orr.w	r6, r12, r5, lsl #16
    1e22:      	cmp	r2, r6
    1e24:      	bls	0x1e98 <compiler_rt.int.__udivmoddi4+0x54c> @ imm = #0x70
    1e26:      	adds	r2, r5, r4
    1e28:      	cmp.w	r10, r2, lsr #16
    1e2c:      	sub.w	r6, r1, #0x1
    1e30:      	bne	0x1e9a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x66
    1e32:      	cmp.w	r10, r6, lsr #16
    1e36:      	bne	0x1e44 <compiler_rt.int.__udivmoddi4+0x4f8> @ imm = #0xa
    1e38:      	mul	r5, r6, r9
    1e3c:      	orr.w	r3, r12, r2, lsl #16
    1e40:      	cmp	r5, r3
    1e42:      	bls	0x1e9a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x54
    1e44:      	add	r2, r4
    1e46:      	cmp.w	r10, r2, lsr #16
    1e4a:      	sub.w	r6, r1, #0x2
    1e4e:      	bne	0x1e9a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x48
    1e50:      	cmp.w	r10, r6, lsr #16
    1e54:      	bne	0x1e62 <compiler_rt.int.__udivmoddi4+0x516> @ imm = #0xa
    1e56:      	mul	r3, r6, r9
    1e5a:      	orr.w	r5, r12, r2, lsl #16
    1e5e:      	cmp	r3, r5
    1e60:      	bls	0x1e9a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x36
    1e62:      	add	r2, r4
    1e64:      	cmp.w	r10, r2, lsr #16
    1e68:      	sub.w	r6, r1, #0x3
    1e6c:      	bne	0x1e9a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x2a
    1e6e:      	cmp.w	r10, r6, lsr #16
    1e72:      	bne	0x1e08 <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x6e
    1e74:      	mul	r3, r6, r9
    1e78:      	orr.w	r5, r12, r2, lsl #16
    1e7c:      	cmp	r3, r5
    1e7e:      	bhi	0x1e08 <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x7a
    1e80:      	b	0x1e9a <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x16
    1e82:      	nop
    1e84:      	mov	r6, r3
    1e86:      	ldr	r3, [sp, #0x10]
    1e88:      	orr.w	r2, r9, r8, lsl #16
    1e8c:      	mls	r2, r6, r3, r2
    1e90:      	lsr.w	r2, r2, lr
    1e94:      	b	0x1ea8 <compiler_rt.int.__udivmoddi4+0x55c> @ imm = #0x10
    1e96:      	nop
    1e98:      	mov	r6, r1
    1e9a:      	orr.w	r1, r12, r8, lsl #16
    1e9e:      	mls	r1, r6, r11, r1
    1ea2:      	lsr.w	r2, r1, lr
    1ea6:      	movs	r1, #0x0
    1ea8:      	ldr	r5, [r7, #0x8]
    1eaa:      	add.w	r0, r6, r0, lsl #16
    1eae:      	cmp	r5, #0x0
    1eb0:      	itt	ne
    1eb2:      	movne	r3, #0x0
    1eb4:      	strdne	r2, r3, [r5]
    1eb8:      	add	sp, #0x20
    1eba:      	pop.w	{r8, r9, r10, r11}
    1ebe:      	pop	{r4, r5, r6, r7, pc}

00001ec0 <.L.str.0>:
    1ec0: 00 00 00 00 00 00 00 00         ........
    1ec8: 37 00 00 00 00 00 00 00         7.......
    1ed0: 73 65 74 20 31 32 20 6c         set 12 l
    1ed8: 65 64 73 20 74 6f 20 32         eds to 2
    1ee0: 35 35 20 61 6e 64 20 77         55 and w
    1ee8: 61 69 74 20 31 30 30 30         ait 1000
    1ef0: 20 6d 73 20 74 68 65 6e          ms then
    1ef8: 20 62 6c 69 6e 6b 20 33          blink 3
    1f00: 20 74 69 6d 65 73 20 00          times .
    1f08: d4 d4 d4 d4 d4 d4 d4 d4         ........

00001f10 <.L.str.3>:
    1f10: 00 00 00 00 00 00 00 00         ........
    1f18: 10 00 00 00 00 00 00 00         ........
    1f20: 69 6e 74 65 67 65 72 20         integer 
    1f28: 6f 76 65 72 66 6c 6f 77         overflow
    1f30: 00 00 00 00 00 00 00 00         ........
    1f38: d4 d4 d4 d4 d4 d4 d4 d4         ........

00001f40 <.L.str.4>:
    1f40: 00 00 00 00 00 00 00 00         ........
    1f48: 13 00 00 00 00 00 00 00         ........
    1f50: 69 6e 64 65 78 20 6f 75         index ou
    1f58: 74 20 6f 66 20 62 6f 75         t of bou
    1f60: 6e 64 73 00 00 00 00 00         nds.....
    1f68: 00 00 00 00 00 00 00 00         ........
    1f70: 00 00 00 00 00 00 00 00         ........
    1f78: d4 d4 d4 d4 d4 d4 d4 d4         ........

00001f80 <.L.str.6>:
    1f80: 00 00 00 00 00 00 00 00         ........
    1f88: 00 00 00 00 00 00 00 00         ........
    1f90: 00 00 00 00 00 00 00 00         ........
    1f98: d4 d4 d4 d4 d4 d4 d4 d4         ........
    1fa0: 00 00 00 00 00 00 00 00         ........
    1fa8: 0e 00 00 00 00 00 00 00         ........
    1fb0: 74 6f 6b 65 6e 73 20 72         tokens r
    1fb8: 65 73 75 6c 74 3d 00 00         esult=..

00001fc0 <.L.str.8>:
    1fc0: 00 00 00 00 00 00 00 00         ........
    1fc8: 07 00 00 00 00 00 00 00         ........
    1fd0: 20 74 69 63 6b 73 3d 00          ticks=.
    1fd8: 6f 75 74 20 6f 66 20 6d         out of m
    1fe0: 65 6d 6f 72 79 00 68 61         emory.ha
    1fe8: 72 64 20 66 61 75 6c 74         rd fault
    1ff0: 00 53 74 72 69 6e 67 2e         .String.
    1ff8: 62 79 74 65 3a 20 6f 75         byte: ou
    2000: 74 20 6f 66 20 72 61 6e         t of ran
    2008: 67 65 00 20 61 6c 6c 6f         ge. allo
    2010: 63 61 74 69 6f 6e 73 3d         cations=
    2018: 00 20 73 74 61 63 6b 3d         . stack=
    2020: 00 23 7a 73 20 68 65 61         .#zs hea
    2028: 70 5f 70 65 61 6b 3d 00         p_peak=.
    2030: 20 6c 69 76 65 3d 00 20          live=. 
    2038: 68 65 61 70 5f 72 65 73         heap_res
    2040: 65 72 76 65 64 3d 00 70         erved=.p
    2048: 61 6e 69 63 3a 20 00 0a         anic: ..
    2050: 00 d4 d4 d4                     ....
