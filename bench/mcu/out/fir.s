
bench/mcu/out/fir.elf:	file format elf32-littlearm

Disassembly of section .text:

00000000 <vectors>:
       0: 00 00 40 20 45 12 00 00         ..@ E...
       8: 8d 13 00 00 8d 13 00 00         ........
      10: 8d 13 00 00 8d 13 00 00         ........
      18: 8d 13 00 00 00 00 00 00         ........
      20: 00 00 00 00 00 00 00 00         ........
      28: 00 00 00 00 8d 13 00 00         ........
      30: 8d 13 00 00 00 00 00 00         ........
      38: 8d 13 00 00 9d 13 00 00         ........

00000040 <main>:
      40:      	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
      44:      	sub	sp, #0xc
      46:      	bl	0x123c <zs_set_args>    @ imm = #0x11f2
      4a:      	movs	r0, #0x88
      4c:      	bl	0x658 <zs_alloc>        @ imm = #0x608
      50:      	mov	r4, r0
      52:      	movs	r0, #0x1
      54:      	movs	r1, #0x20
      56:      	strd	r0, r1, [r4]
      5a:      	add.w	r0, r4, #0x8
      5e:      	movs	r1, #0x80
      60:      	str	r0, [sp, #0x4]
      62:      	bl	0x188c <compiler_rt.arm.__aeabi_memclr> @ imm = #0x1826
      66:      	vldr	s0, [pc, #8]            @ 0x70 <main+0x30>
      6a:      	movs	r0, #0x10
      6c:      	movs	r1, #0x0
      6e:      	b	0x74 <main+0x34>        @ imm = #0x2
      70: 00 00 04 44  	.word	0x44040000
      74:      	sub.w	r2, r0, #0xf
      78:      	vmov	s2, r2
      7c:      	sub.w	r2, r0, #0xe
      80:      	vcvt.f32.u32	s2, s2
      84:      	vmov	s4, r2
      88:      	vdiv.f32	s2, s2, s0
      8c:      	vcvt.f32.u32	s4, s4
      90:      	vdiv.f32	s4, s4, s0
      94:      	adds	r2, r4, r1
      96:      	sub.w	r3, r0, #0xd
      9a:      	vmov	s13, r0
      9e:      	vcvt.f32.u32	s13, s13
      a2:      	vdiv.f32	s13, s13, s0
      a6:      	adds	r1, #0x40
      a8:      	vstr	s2, [r2, #8]
      ac:      	vmov	s2, r3
      b0:      	sub.w	r3, r0, #0xc
      b4:      	vstr	s4, [r2, #12]
      b8:      	vmov	s4, r3
      bc:      	sub.w	r3, r0, #0xb
      c0:      	vmov	s6, r3
      c4:      	sub.w	r3, r0, #0xa
      c8:      	vmov	s8, r3
      cc:      	sub.w	r3, r0, #0x9
      d0:      	vmov	s10, r3
      d4:      	sub.w	r3, r0, #0x8
      d8:      	vmov	s12, r3
      dc:      	subs	r3, r0, #0x7
      de:      	vmov	s14, r3
      e2:      	subs	r3, r0, #0x6
      e4:      	vmov	s1, r3
      e8:      	subs	r3, r0, #0x5
      ea:      	vmov	s3, r3
      ee:      	subs	r3, r0, #0x4
      f0:      	vmov	s5, r3
      f4:      	subs	r3, r0, #0x3
      f6:      	vmov	s7, r3
      fa:      	subs	r3, r0, #0x2
      fc:      	vmov	s9, r3
     100:      	subs	r3, r0, #0x1
     102:      	vmov	s11, r3
     106:      	vcvt.f32.u32	s2, s2
     10a:      	vcvt.f32.u32	s4, s4
     10e:      	vcvt.f32.u32	s6, s6
     112:      	vcvt.f32.u32	s8, s8
     116:      	vcvt.f32.u32	s10, s10
     11a:      	vcvt.f32.u32	s12, s12
     11e:      	vcvt.f32.u32	s14, s14
     122:      	vcvt.f32.u32	s1, s1
     126:      	vcvt.f32.u32	s3, s3
     12a:      	vcvt.f32.u32	s5, s5
     12e:      	vcvt.f32.u32	s7, s7
     132:      	vcvt.f32.u32	s9, s9
     136:      	vcvt.f32.u32	s11, s11
     13a:      	vdiv.f32	s2, s2, s0
     13e:      	vdiv.f32	s4, s4, s0
     142:      	vdiv.f32	s6, s6, s0
     146:      	vdiv.f32	s8, s8, s0
     14a:      	vdiv.f32	s10, s10, s0
     14e:      	vdiv.f32	s12, s12, s0
     152:      	vdiv.f32	s14, s14, s0
     156:      	vdiv.f32	s1, s1, s0
     15a:      	vdiv.f32	s3, s3, s0
     15e:      	vdiv.f32	s5, s5, s0
     162:      	vdiv.f32	s7, s7, s0
     166:      	vdiv.f32	s9, s9, s0
     16a:      	vdiv.f32	s11, s11, s0
     16e:      	adds	r0, #0x10
     170:      	cmp	r0, #0x30
     172:      	vstr	s2, [r2, #16]
     176:      	vstr	s4, [r2, #20]
     17a:      	vstr	s6, [r2, #24]
     17e:      	vstr	s8, [r2, #28]
     182:      	vstr	s10, [r2, #32]
     186:      	vstr	s12, [r2, #36]
     18a:      	vstr	s14, [r2, #40]
     18e:      	vstr	s1, [r2, #44]
     192:      	vstr	s3, [r2, #48]
     196:      	vstr	s5, [r2, #52]
     19a:      	vstr	s7, [r2, #56]
     19e:      	vstr	s9, [r2, #60]
     1a2:      	vstr	s11, [r2, #64]
     1a6:      	vstr	s13, [r2, #68]
     1aa:      	bne.w	0x74 <main+0x34>        @ imm = #-0x13a
     1ae:      	movw	r0, #0x1008
     1b2:      	str	r4, [sp, #0x8]
     1b4:      	bl	0x658 <zs_alloc>        @ imm = #0x4a0
     1b8:      	mov	r11, r0
     1ba:      	movs	r0, #0x1
     1bc:      	mov.w	r1, #0x400
     1c0:      	strd	r0, r1, [r11]
     1c4:      	add.w	r0, r11, #0x8
     1c8:      	mov.w	r1, #0x1000
     1cc:      	bl	0x188c <compiler_rt.arm.__aeabi_memclr> @ imm = #0x16bc
     1d0:      	movw	lr, #0x4b4b
     1d4:      	movw	r12, #0x3c3c
     1d8:      	movw	r10, #0x2d2d
     1dc:      	movw	r9, #0x1e1e
     1e0:      	movs	r0, #0xf
     1e2:      	movs	r1, #0x0
     1e4:      	movw	r3, #0xf0f1
     1e8:      	mvn	r7, #0x7
     1ec:      	movt	lr, #0xfffb
     1f0:      	movt	r12, #0xfffc
     1f4:      	movt	r10, #0xfffd
     1f8:      	movt	r9, #0xfffe
     1fc:      	movw	r6, #0x40f
     200:      	movw	r2, #0xe1e1
     204:      	movt	r2, #0xfff1
     208:      	mla	r4, r0, r3, r2
     20c:      	movw	r2, #0xd2d2
     210:      	movt	r2, #0xfff2
     214:      	lsrs	r4, r4, #0x14
     216:      	mla	r5, r0, r3, r2
     21a:      	add.w	r4, r4, r4, lsl #4
     21e:      	subs	r4, r0, r4
     220:      	lsrs	r5, r5, #0x14
     222:      	subs	r4, #0xf
     224:      	add.w	r5, r5, r5, lsl #4
     228:      	movw	r2, #0xc3c3
     22c:      	uxtah	r4, r7, r4
     230:      	subs	r5, r0, r5
     232:      	movt	r2, #0xfff3
     236:      	vmov	s0, r4
     23a:      	add.w	r4, r11, r1
     23e:      	subs	r5, #0xe
     240:      	mov	r8, r11
     242:      	mla	r11, r0, r3, r2
     246:      	vcvt.f32.s32	s0, s0
     24a:      	uxtah	r5, r7, r5
     24e:      	vstr	s0, [r4, #8]
     252:      	vmov	s0, r5
     256:      	lsr.w	r5, r11, #0x14
     25a:      	movw	r2, #0xb4b4
     25e:      	add.w	r5, r5, r5, lsl #4
     262:      	movt	r2, #0xfff4
     266:      	subs	r5, r0, r5
     268:      	mla	r2, r0, r3, r2
     26c:      	subs	r5, #0xd
     26e:      	uxtah	r5, r7, r5
     272:      	lsrs	r2, r2, #0x14
     274:      	vmov	s2, r5
     278:      	add.w	r2, r2, r2, lsl #4
     27c:      	movw	r5, #0xa5a5
     280:      	subs	r2, r0, r2
     282:      	movt	r5, #0xfff5
     286:      	subs	r2, #0xc
     288:      	mla	r5, r0, r3, r5
     28c:      	uxtah	r2, r7, r2
     290:      	vmov	s4, r2
     294:      	lsrs	r2, r5, #0x14
     296:      	add.w	r2, r2, r2, lsl #4
     29a:      	movw	r5, #0x9696
     29e:      	subs	r2, r0, r2
     2a0:      	movt	r5, #0xfff6
     2a4:      	subs	r2, #0xb
     2a6:      	mla	r5, r0, r3, r5
     2aa:      	uxtah	r2, r7, r2
     2ae:      	vmov	s6, r2
     2b2:      	lsrs	r2, r5, #0x14
     2b4:      	add.w	r2, r2, r2, lsl #4
     2b8:      	movw	r5, #0x8787
     2bc:      	subs	r2, r0, r2
     2be:      	movt	r5, #0xfff7
     2c2:      	subs	r2, #0xa
     2c4:      	mla	r5, r0, r3, r5
     2c8:      	uxtah	r2, r7, r2
     2cc:      	vmov	s8, r2
     2d0:      	lsrs	r2, r5, #0x14
     2d2:      	add.w	r2, r2, r2, lsl #4
     2d6:      	movw	r5, #0x7878
     2da:      	subs	r2, r0, r2
     2dc:      	movt	r5, #0xfff8
     2e0:      	subs	r2, #0x9
     2e2:      	mla	r5, r0, r3, r5
     2e6:      	uxtah	r2, r7, r2
     2ea:      	vmov	s10, r2
     2ee:      	lsrs	r2, r5, #0x14
     2f0:      	add.w	r2, r2, r2, lsl #4
     2f4:      	movw	r5, #0x6969
     2f8:      	subs	r2, r0, r2
     2fa:      	movt	r5, #0xfff9
     2fe:      	subs	r2, #0x8
     300:      	mla	r5, r0, r3, r5
     304:      	uxtah	r2, r7, r2
     308:      	vmov	s12, r2
     30c:      	lsrs	r2, r5, #0x14
     30e:      	add.w	r2, r2, r2, lsl #4
     312:      	movw	r5, #0x5a5a
     316:      	subs	r2, r0, r2
     318:      	movt	r5, #0xfffa
     31c:      	subs	r2, #0x7
     31e:      	mla	r5, r0, r3, r5
     322:      	uxtah	r2, r7, r2
     326:      	vmov	s14, r2
     32a:      	lsrs	r2, r5, #0x14
     32c:      	add.w	r2, r2, r2, lsl #4
     330:      	subs	r2, r0, r2
     332:      	subs	r2, #0x6
     334:      	mla	r5, r0, r3, lr
     338:      	uxtah	r2, r7, r2
     33c:      	vmov	s1, r2
     340:      	lsrs	r2, r5, #0x14
     342:      	add.w	r2, r2, r2, lsl #4
     346:      	subs	r2, r0, r2
     348:      	subs	r2, #0x5
     34a:      	mla	r5, r0, r3, r12
     34e:      	uxtah	r2, r7, r2
     352:      	vmov	s3, r2
     356:      	lsrs	r2, r5, #0x14
     358:      	add.w	r2, r2, r2, lsl #4
     35c:      	subs	r2, r0, r2
     35e:      	subs	r2, #0x4
     360:      	mla	r5, r0, r3, r10
     364:      	uxtah	r2, r7, r2
     368:      	vmov	s5, r2
     36c:      	lsrs	r2, r5, #0x14
     36e:      	add.w	r2, r2, r2, lsl #4
     372:      	subs	r2, r0, r2
     374:      	subs	r2, #0x3
     376:      	mla	r5, r0, r3, r9
     37a:      	uxtah	r2, r7, r2
     37e:      	vmov	s7, r2
     382:      	lsrs	r2, r5, #0x14
     384:      	add.w	r2, r2, r2, lsl #4
     388:      	vcvt.f32.s32	s2, s2
     38c:      	subs	r2, r0, r2
     38e:      	vstr	s2, [r4, #16]
     392:      	vcvt.f32.s32	s2, s4
     396:      	subs	r2, #0x2
     398:      	vstr	s2, [r4, #20]
     39c:      	vcvt.f32.s32	s2, s6
     3a0:      	uxtah	r2, r7, r2
     3a4:      	vstr	s2, [r4, #24]
     3a8:      	vcvt.f32.s32	s2, s8
     3ac:      	vmov	s9, r2
     3b0:      	mul	r2, r0, r3
     3b4:      	vstr	s2, [r4, #28]
     3b8:      	vcvt.f32.s32	s2, s10
     3bc:      	subs	r5, r2, r3
     3be:      	vstr	s2, [r4, #32]
     3c2:      	vcvt.f32.s32	s2, s12
     3c6:      	lsrs	r5, r5, #0x14
     3c8:      	vstr	s2, [r4, #36]
     3cc:      	vcvt.f32.s32	s2, s14
     3d0:      	add.w	r5, r5, r5, lsl #4
     3d4:      	lsrs	r2, r2, #0x14
     3d6:      	vstr	s2, [r4, #40]
     3da:      	vcvt.f32.s32	s2, s1
     3de:      	subs	r5, r5, r0
     3e0:      	add.w	r2, r2, r2, lsl #4
     3e4:      	vstr	s2, [r4, #44]
     3e8:      	vcvt.f32.s32	s2, s3
     3ec:      	mvns	r5, r5
     3ee:      	subs	r2, r0, r2
     3f0:      	vstr	s2, [r4, #48]
     3f4:      	vcvt.f32.s32	s2, s5
     3f8:      	uxtah	r5, r7, r5
     3fc:      	vcvt.f32.s32	s0, s0
     400:      	uxtah	r2, r7, r2
     404:      	vstr	s2, [r4, #52]
     408:      	vcvt.f32.s32	s2, s7
     40c:      	vmov	s11, r5
     410:      	vstr	s0, [r4, #12]
     414:      	vmov	s0, r2
     418:      	vstr	s2, [r4, #56]
     41c:      	vcvt.f32.s32	s2, s9
     420:      	adds	r0, #0x10
     422:      	mov	r11, r8
     424:      	vstr	s2, [r4, #60]
     428:      	vcvt.f32.s32	s2, s11
     42c:      	vcvt.f32.s32	s0, s0
     430:      	cmp	r0, r6
     432:      	add.w	r1, r1, #0x40
     436:      	vstr	s2, [r4, #64]
     43a:      	vstr	s0, [r4, #68]
     43e:      	bne.w	0x200 <main+0x1c0>      @ imm = #-0x242
     442:      	bl	0x1334 <zs_ticks>       @ imm = #0xeee
     446:      	ldr.w	r10, [sp, #0x8]
     44a:      	mov	r9, r0
     44c:      	ldr.w	r2, [r10]
     450:      	mov	r4, r1
     452:      	cmp	r2, #0x0
     454:      	itt	ne
     456:      	addne	r0, r2, #0x1
     458:      	strne.w	r0, [r10]
     45c:      	ldr.w	r0, [r11]
     460:      	ldr.w	lr, [sp, #0x4]
     464:      	cmp	r0, #0x0
     466:      	itte	ne
     468:      	addne.w	r12, r0, #0x1
     46c:      	strne.w	r12, [r11]
     470:      	moveq.w	r12, #0x0
     474:      	ldr.w	r1, [r11, #0x4]
     478:      	cmp	r1, #0x20
     47a:      	blo	0x4ea <main+0x4aa>      @ imm = #0x6c
     47c:      	ldr.w	r2, [r10, #0x4]
     480:      	vldr	s0, [pc, #460]          @ 0x650 <main+0x610>
     484:      	str	r4, [sp]
     486:      	add.w	r4, r11, #0x84
     48a:      	rsbs	r3, r2, #0
     48c:      	movs	r7, #0x1f
     48e:      	vmov.f32	s2, s0
     492:      	nop
     494:      	movs	r6, #0x0
     496:      	mov	r5, lr
     498:      	mov	r2, r4
     49a:      	vmov.f32	s4, s0
     49e:      	nop
     4a0:      	cmp	r3, r6
     4a2:      	beq.w	0x632 <main+0x5f2>      @ imm = #0x18c
     4a6:      	adds	r0, r7, r6
     4a8:      	cmp	r0, r1
     4aa:      	bhs.w	0x632 <main+0x5f2>      @ imm = #0x184
     4ae:      	vldmia	r5!, {s6}
     4b2:      	vldr	s8, [r2]
     4b6:      	subs	r6, #0x1
     4b8:      	vmul.f32	s6, s6, s8
     4bc:      	vadd.f32	s4, s4, s6
     4c0:      	subs	r2, #0x4
     4c2:      	adds.w	r0, r6, #0x20
     4c6:      	bne	0x4a0 <main+0x460>      @ imm = #-0x2a
     4c8:      	adds	r7, #0x1
     4ca:      	vadd.f32	s2, s2, s4
     4ce:      	cmp	r7, r1
     4d0:      	add.w	r4, r4, #0x4
     4d4:      	bne	0x494 <main+0x454>      @ imm = #-0x44
     4d6:      	vldr	s0, [pc, #380]          @ 0x654 <main+0x614>
     4da:      	ldr	r4, [sp]
     4dc:      	vmul.f32	s0, s2, s0
     4e0:      	vcvt.s32.f32	s0, s0
     4e4:      	vmov	r7, s0
     4e8:      	b	0x4ec <main+0x4ac>      @ imm = #0x0
     4ea:      	movs	r7, #0x0
     4ec:      	cmp.w	r12, #0x0
     4f0:      	itt	ne
     4f2:      	subne.w	r0, r12, #0x1
     4f6:      	strne.w	r0, [r11]
     4fa:      	ldr.w	r0, [r10]
     4fe:      	cbz	r0, 0x512 <main+0x4d2>  @ imm = #0x10
     500:      	cmp	r0, #0x1
     502:      	bne	0x50c <main+0x4cc>      @ imm = #0x6
     504:      	mov	r0, r10
     506:      	bl	0x748 <zs_free>         @ imm = #0x23e
     50a:      	b	0x512 <main+0x4d2>      @ imm = #0x4
     50c:      	subs	r0, #0x1
     50e:      	str.w	r0, [r10]
     512:      	bl	0x1334 <zs_ticks>       @ imm = #0xe1e
     516:      	mov	r11, r0
     518:      	mov	r5, r1
     51a:      	asrs	r1, r7, #0x1f
     51c:      	mov	r0, r7
     51e:      	bl	0xcb8 <zs_str_of_i64>   @ imm = #0x796
     522:      	mov	r7, r0
     524:      	movw	r0, #0x1e80
     528:      	movt	r0, #0x0
     52c:      	mov	r1, r7
     52e:      	bl	0x798 <zs_str_concat>   @ imm = #0x266
     532:      	ldr	r1, [r7]
     534:      	mov	r6, r0
     536:      	cbz	r1, 0x548 <main+0x508>  @ imm = #0xe
     538:      	cmp	r1, #0x1
     53a:      	bne	0x544 <main+0x504>      @ imm = #0x6
     53c:      	mov	r0, r7
     53e:      	bl	0x748 <zs_free>         @ imm = #0x206
     542:      	b	0x548 <main+0x508>      @ imm = #0x2
     544:      	subs	r0, r1, #0x1
     546:      	str	r0, [r7]
     548:      	movw	r1, #0x1e94
     54c:      	movt	r1, #0x0
     550:      	mov	r0, r6
     552:      	bl	0x798 <zs_str_concat>   @ imm = #0x242
     556:      	ldr	r1, [r6]
     558:      	mov	r7, r0
     55a:      	cbz	r1, 0x56c <main+0x52c>  @ imm = #0xe
     55c:      	cmp	r1, #0x1
     55e:      	bne	0x568 <main+0x528>      @ imm = #0x6
     560:      	mov	r0, r6
     562:      	bl	0x748 <zs_free>         @ imm = #0x1e2
     566:      	b	0x56c <main+0x52c>      @ imm = #0x2
     568:      	subs	r0, r1, #0x1
     56a:      	str	r0, [r6]
     56c:      	subs.w	r0, r11, r9
     570:      	sbcs.w	r1, r5, r4
     574:      	mov.w	r2, #0x0
     578:      	adc	r2, r2, #0x0
     57c:      	eor	r2, r2, #0x1
     580:      	cmp	r2, #0x1
     582:      	beq	0x640 <main+0x600>      @ imm = #0xba
     584:      	bl	0x974 <zs_str_of_u64>   @ imm = #0x3ec
     588:      	mov	r6, r0
     58a:      	mov	r0, r7
     58c:      	mov	r1, r6
     58e:      	bl	0x798 <zs_str_concat>   @ imm = #0x206
     592:      	ldr	r1, [r7]
     594:      	mov	r5, r0
     596:      	cbz	r1, 0x5a8 <main+0x568>  @ imm = #0xe
     598:      	cmp	r1, #0x1
     59a:      	bne	0x5a4 <main+0x564>      @ imm = #0x6
     59c:      	mov	r0, r7
     59e:      	bl	0x748 <zs_free>         @ imm = #0x1a6
     5a2:      	b	0x5a8 <main+0x568>      @ imm = #0x2
     5a4:      	subs	r0, r1, #0x1
     5a6:      	str	r0, [r7]
     5a8:      	ldr	r0, [r6]
     5aa:      	cbz	r0, 0x5bc <main+0x57c>  @ imm = #0xe
     5ac:      	cmp	r0, #0x1
     5ae:      	bne	0x5b8 <main+0x578>      @ imm = #0x6
     5b0:      	mov	r0, r6
     5b2:      	bl	0x748 <zs_free>         @ imm = #0x192
     5b6:      	b	0x5bc <main+0x57c>      @ imm = #0x2
     5b8:      	subs	r0, #0x1
     5ba:      	str	r0, [r6]
     5bc:      	movw	r0, #0x1e6c
     5c0:      	movt	r0, #0x0
     5c4:      	mov	r1, r5
     5c6:      	bl	0x798 <zs_str_concat>   @ imm = #0x1ce
     5ca:      	ldr	r1, [r5]
     5cc:      	mov	r6, r0
     5ce:      	cbz	r1, 0x5e0 <main+0x5a0>  @ imm = #0xe
     5d0:      	cmp	r1, #0x1
     5d2:      	bne	0x5dc <main+0x59c>      @ imm = #0x6
     5d4:      	mov	r0, r5
     5d6:      	bl	0x748 <zs_free>         @ imm = #0x16e
     5da:      	b	0x5e0 <main+0x5a0>      @ imm = #0x2
     5dc:      	subs	r0, r1, #0x1
     5de:      	str	r0, [r5]
     5e0:      	mov	r0, r6
     5e2:      	bl	0xee0 <zs_println>      @ imm = #0x8fa
     5e6:      	ldr	r0, [r6]
     5e8:      	cbz	r0, 0x5fa <main+0x5ba>  @ imm = #0xe
     5ea:      	cmp	r0, #0x1
     5ec:      	bne	0x5f6 <main+0x5b6>      @ imm = #0x6
     5ee:      	mov	r0, r6
     5f0:      	bl	0x748 <zs_free>         @ imm = #0x154
     5f4:      	b	0x5fa <main+0x5ba>      @ imm = #0x2
     5f6:      	subs	r0, #0x1
     5f8:      	str	r0, [r6]
     5fa:      	ldr.w	r0, [r8]
     5fe:      	cbz	r0, 0x612 <main+0x5d2>  @ imm = #0x10
     600:      	cmp	r0, #0x1
     602:      	bne	0x60c <main+0x5cc>      @ imm = #0x6
     604:      	mov	r0, r8
     606:      	bl	0x748 <zs_free>         @ imm = #0x13e
     60a:      	b	0x612 <main+0x5d2>      @ imm = #0x4
     60c:      	subs	r0, #0x1
     60e:      	str.w	r0, [r8]
     612:      	ldr.w	r0, [r10]
     616:      	cbz	r0, 0x62a <main+0x5ea>  @ imm = #0x10
     618:      	cmp	r0, #0x1
     61a:      	bne	0x624 <main+0x5e4>      @ imm = #0x6
     61c:      	mov	r0, r10
     61e:      	bl	0x748 <zs_free>         @ imm = #0x126
     622:      	b	0x62a <main+0x5ea>      @ imm = #0x4
     624:      	subs	r0, #0x1
     626:      	str.w	r0, [r10]
     62a:      	movs	r0, #0x0
     62c:      	add	sp, #0xc
     62e:      	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
     632:      	movw	r0, #0x1e50
     636:      	movt	r0, #0x0
     63a:      	adds	r0, #0x8
     63c:      	bl	0x71c <zs_panic_c>      @ imm = #0xdc
     640:      	movw	r0, #0x1e30
     644:      	movt	r0, #0x0
     648:      	adds	r0, #0x8
     64a:      	bl	0x71c <zs_panic_c>      @ imm = #0xce
     64e:      	nop
     650: 00 00 00 00  	.word	0x00000000
     654: 00 00 7a 44  	.word	0x447a0000

00000658 <zs_alloc>:
     658:      	push	{r4, r6, r7, lr}
     65a:      	add	r7, sp, #0x8
     65c:      	adds	r0, #0x7
     65e:      	lsrs	r2, r0, #0x3
     660:      	cmp	r2, #0x20
     662:      	bhi	0x680 <zs_alloc+0x28>   @ imm = #0x1a
     664:      	movw	r12, #0x0
     668:      	movt	r12, #0x2000
     66c:      	ldr.w	r1, [r12, r2, lsl #2]
     670:      	cbz	r1, 0x680 <zs_alloc+0x28> @ imm = #0xc
     672:      	mov	r0, r1
     674:      	ldr	r3, [r1]
     676:      	ldr	r1, [r0, #-8]!
     67a:      	str.w	r3, [r12, r2, lsl #2]
     67e:      	b	0x6b8 <zs_alloc+0x60>   @ imm = #0x36
     680:      	movw	r12, #0x84
     684:      	movt	r12, #0x2000
     688:      	ldr.w	r2, [r12]
     68c:      	bic	r1, r0, #0x7
     690:      	adds	r3, r1, r2
     692:      	movw	r0, #0xfff9
     696:      	subs	r0, r3, r0
     698:      	cmn.w	r0, #0x10001
     69c:      	blo	0x70e <zs_alloc+0xb6>   @ imm = #0x6e
     69e:      	movw	lr, #0x88
     6a2:      	movt	lr, #0x2000
     6a6:      	add.w	r0, lr, r2
     6aa:      	adds	r3, #0x8
     6ac:      	str.w	r1, [lr, r2]
     6b0:      	movs	r2, #0x0
     6b2:      	str.w	r3, [r12]
     6b6:      	str	r2, [r0, #0x4]
     6b8:      	movw	lr, #0x88
     6bc:      	movt	lr, #0x2001
     6c0:      	ldr.w	r2, [lr]
     6c4:      	movw	r12, #0x8c
     6c8:      	movt	r12, #0x2001
     6cc:      	ldr.w	r3, [r12]
     6d0:      	add	r1, r2
     6d2:      	str.w	r1, [lr]
     6d6:      	movw	lr, #0x90
     6da:      	cmp	r1, r3
     6dc:      	it	hi
     6de:      	strhi.w	r1, [r12]
     6e2:      	movt	lr, #0x2001
     6e6:      	movw	r12, #0x98
     6ea:      	ldrd	r2, r3, [lr]
     6ee:      	movt	r12, #0x2001
     6f2:      	ldrd	r1, r4, [r12]
     6f6:      	adds	r2, #0x1
     6f8:      	adc	r3, r3, #0x0
     6fc:      	adds	r1, #0x1
     6fe:      	strd	r2, r3, [lr]
     702:      	adc	r2, r4, #0x0
     706:      	adds	r0, #0x8
     708:      	strd	r1, r2, [r12]
     70c:      	pop	{r4, r6, r7, pc}
     70e:      	movw	r0, #0x1ea4
     712:      	movt	r0, #0x0
     716:      	bl	0x71c <zs_panic_c>      @ imm = #0x2
     71a:      	bmi	0x6c6 <zs_alloc+0x6e>   @ imm = #-0x58

0000071c <zs_panic_c>:
     71c:      	push	{r4, r6, r7, lr}
     71e:      	add	r7, sp, #0x8
     720:      	mov	r4, r0
     722:      	movw	r0, #0x1ef9
     726:      	movt	r0, #0x0
     72a:      	bl	0xffc <write_c>         @ imm = #0x8ce
     72e:      	mov	r0, r4
     730:      	bl	0xffc <write_c>         @ imm = #0x8c8
     734:      	movw	r0, #0x1f01
     738:      	movt	r0, #0x0
     73c:      	bl	0xffc <write_c>         @ imm = #0x8bc
     740:      	movs	r0, #0x86
     742:      	bl	0x1140 <stop>           @ imm = #0x9fa
     746:      	bmi	0x6f2 <zs_alloc+0x9a>   @ imm = #-0x58

00000748 <zs_free>:
     748:      	push	{r4, r6, r7, lr}
     74a:      	add	r7, sp, #0x8
     74c:      	movw	lr, #0x88
     750:      	movw	r12, #0x90
     754:      	movt	lr, #0x2001
     758:      	movt	r12, #0x2001
     75c:      	ldr	r1, [r0, #-8]
     760:      	ldr.w	r3, [lr]
     764:      	ldrd	r2, r4, [r12]
     768:      	subs	r3, r3, r1
     76a:      	subs	r2, #0x1
     76c:      	str.w	r3, [lr]
     770:      	sbc	r3, r4, #0x0
     774:      	lsrs	r4, r1, #0x3
     776:      	cmp	r4, #0x20
     778:      	strd	r2, r3, [r12]
     77c:      	it	hi
     77e:      	pophi	{r4, r6, r7, pc}
     780:      	mvn	r2, #0x3
     784:      	and.w	r1, r2, r1, lsr #1
     788:      	movw	r2, #0x0
     78c:      	movt	r2, #0x2000
     790:      	ldr	r3, [r2, r1]
     792:      	str	r3, [r0]
     794:      	str	r0, [r2, r1]
     796:      	pop	{r4, r6, r7, pc}

00000798 <zs_str_concat>:
     798:      	push	{r4, r5, r6, r7, lr}
     79a:      	add	r7, sp, #0xc
     79c:      	push.w	{r8, r9, r11}
     7a0:      	mov	lr, r0
     7a2:      	ldr	r0, [r0, #0x4]
     7a4:      	ldr	r2, [r1, #0x4]
     7a6:      	add.w	r9, r2, r0
     7aa:      	add.w	r0, r9, #0x10
     7ae:      	lsrs	r6, r0, #0x3
     7b0:      	cmp	r6, #0x20
     7b2:      	bhi	0x7d0 <zs_str_concat+0x38> @ imm = #0x1a
     7b4:      	movw	r5, #0x0
     7b8:      	movt	r5, #0x2000
     7bc:      	ldr.w	r3, [r5, r6, lsl #2]
     7c0:      	cbz	r3, 0x7d0 <zs_str_concat+0x38> @ imm = #0xc
     7c2:      	mov	r8, r3
     7c4:      	ldr	r3, [r3]
     7c6:      	ldr	r0, [r8, #-8]!
     7ca:      	str.w	r3, [r5, r6, lsl #2]
     7ce:      	b	0x806 <zs_str_concat+0x6e> @ imm = #0x34
     7d0:      	movw	r5, #0x84
     7d4:      	movt	r5, #0x2000
     7d8:      	ldr	r6, [r5]
     7da:      	bic	r0, r0, #0x7
     7de:      	adds	r4, r0, r6
     7e0:      	movw	r3, #0xfff9
     7e4:      	subs	r3, r4, r3
     7e6:      	cmn.w	r3, #0x10001
     7ea:      	blo.w	0x966 <zs_str_concat+0x1ce> @ imm = #0x178
     7ee:      	movw	r3, #0x88
     7f2:      	movt	r3, #0x2000
     7f6:      	add.w	r8, r3, r6
     7fa:      	adds	r4, #0x8
     7fc:      	str	r0, [r3, r6]
     7fe:      	movs	r3, #0x0
     800:      	str	r4, [r5]
     802:      	str.w	r3, [r8, #0x4]
     806:      	movw	r3, #0x88
     80a:      	movt	r3, #0x2001
     80e:      	movw	r6, #0x8c
     812:      	ldr	r5, [r3]
     814:      	movt	r6, #0x2001
     818:      	ldr	r4, [r6]
     81a:      	add	r0, r5
     81c:      	cmp	r0, r4
     81e:      	str	r0, [r3]
     820:      	it	hi
     822:      	strhi	r0, [r6]
     824:      	movw	r0, #0x90
     828:      	movt	r0, #0x2001
     82c:      	ldrd	r3, r6, [r0]
     830:      	movw	r5, #0x98
     834:      	movt	r5, #0x2001
     838:      	adds	r3, #0x1
     83a:      	ldrd	r4, r2, [r5]
     83e:      	adc	r6, r6, #0x0
     842:      	strd	r3, r6, [r0]
     846:      	adds	r0, r4, #0x1
     848:      	adc	r2, r2, #0x0
     84c:      	strd	r0, r2, [r5]
     850:      	movs	r2, #0x1
     852:      	mov	r0, r8
     854:      	str	r2, [r0, #8]!
     858:      	add.w	r12, r0, #0x8
     85c:      	movs	r5, #0x0
     85e:      	str.w	r9, [r0, #0x4]
     862:      	strb.w	r5, [r12, r9]
     866:      	ldr.w	r4, [lr, #0x4]
     86a:      	cmp	r4, #0x0
     86c:      	beq	0x8f0 <zs_str_concat+0x158> @ imm = #0x80
     86e:      	ands	r2, r4, #0x3
     872:      	beq	0x890 <zs_str_concat+0xf8> @ imm = #0x1a
     874:      	ldrb.w	r3, [lr, #0x8]
     878:      	cmp	r2, #0x1
     87a:      	strb.w	r3, [r8, #0x10]
     87e:      	bne	0x89e <zs_str_concat+0x106> @ imm = #0x1c
     880:      	subs	r2, r4, #0x1
     882:      	add.w	r5, lr, #0x9
     886:      	add.w	r6, r8, #0x11
     88a:      	cmp	r4, #0x4
     88c:      	bhs	0x8d0 <zs_str_concat+0x138> @ imm = #0x40
     88e:      	b	0x8ec <zs_str_concat+0x154> @ imm = #0x5a
     890:      	add.w	r5, lr, #0x8
     894:      	mov	r6, r12
     896:      	mov	r2, r4
     898:      	cmp	r4, #0x4
     89a:      	bhs	0x8d0 <zs_str_concat+0x138> @ imm = #0x32
     89c:      	b	0x8ec <zs_str_concat+0x154> @ imm = #0x4c
     89e:      	ldrb.w	r3, [lr, #0x9]
     8a2:      	cmp	r2, #0x2
     8a4:      	strb.w	r3, [r8, #0x11]
     8a8:      	bne	0x8ba <zs_str_concat+0x122> @ imm = #0xe
     8aa:      	subs	r2, r4, #0x2
     8ac:      	add.w	r5, lr, #0xa
     8b0:      	add.w	r6, r8, #0x12
     8b4:      	cmp	r4, #0x4
     8b6:      	bhs	0x8d0 <zs_str_concat+0x138> @ imm = #0x16
     8b8:      	b	0x8ec <zs_str_concat+0x154> @ imm = #0x30
     8ba:      	ldrb.w	r3, [lr, #0xa]
     8be:      	subs	r2, r4, #0x3
     8c0:      	add.w	r5, lr, #0xb
     8c4:      	add.w	r6, r8, #0x13
     8c8:      	strb.w	r3, [r8, #0x12]
     8cc:      	cmp	r4, #0x4
     8ce:      	blo	0x8ec <zs_str_concat+0x154> @ imm = #0x1a
     8d0:      	subs	r3, r5, #0x4
     8d2:      	subs	r4, r6, #0x4
     8d4:      	ldrb	r5, [r3, #4]!
     8d8:      	subs	r2, #0x4
     8da:      	strb	r5, [r4, #4]!
     8de:      	ldrb	r5, [r3, #0x1]
     8e0:      	strb	r5, [r4, #0x1]
     8e2:      	ldrb	r5, [r3, #0x2]
     8e4:      	strb	r5, [r4, #0x2]
     8e6:      	ldrb	r5, [r3, #0x3]
     8e8:      	strb	r5, [r4, #0x3]
     8ea:      	bne	0x8d4 <zs_str_concat+0x13c> @ imm = #-0x1a
     8ec:      	ldr.w	r5, [lr, #0x4]
     8f0:      	ldr	r3, [r1, #0x4]
     8f2:      	cbz	r3, 0x960 <zs_str_concat+0x1c8> @ imm = #0x6a
     8f4:      	ands	r2, r3, #0x3
     8f8:      	add.w	r6, r12, r5
     8fc:      	beq	0x916 <zs_str_concat+0x17e> @ imm = #0x16
     8fe:      	ldrb	r5, [r1, #0x8]
     900:      	mov	r4, r6
     902:      	cmp	r2, #0x1
     904:      	strb	r5, [r4], #1
     908:      	bne	0x920 <zs_str_concat+0x188> @ imm = #0x14
     90a:      	subs	r2, r3, #0x1
     90c:      	adds	r1, #0x9
     90e:      	mov	r6, r4
     910:      	cmp	r3, #0x4
     912:      	bhs	0x942 <zs_str_concat+0x1aa> @ imm = #0x2c
     914:      	b	0x960 <zs_str_concat+0x1c8> @ imm = #0x48
     916:      	adds	r1, #0x8
     918:      	mov	r2, r3
     91a:      	cmp	r3, #0x4
     91c:      	bhs	0x942 <zs_str_concat+0x1aa> @ imm = #0x22
     91e:      	b	0x960 <zs_str_concat+0x1c8> @ imm = #0x3e
     920:      	ldrb	r5, [r1, #0x9]
     922:      	cmp	r2, #0x2
     924:      	strb	r5, [r6, #0x1]
     926:      	bne	0x934 <zs_str_concat+0x19c> @ imm = #0xa
     928:      	subs	r2, r3, #0x2
     92a:      	adds	r1, #0xa
     92c:      	adds	r6, #0x2
     92e:      	cmp	r3, #0x4
     930:      	bhs	0x942 <zs_str_concat+0x1aa> @ imm = #0xe
     932:      	b	0x960 <zs_str_concat+0x1c8> @ imm = #0x2a
     934:      	ldrb	r5, [r1, #0xa]
     936:      	subs	r2, r3, #0x3
     938:      	adds	r1, #0xb
     93a:      	strb	r5, [r6, #0x2]
     93c:      	adds	r6, #0x3
     93e:      	cmp	r3, #0x4
     940:      	blo	0x960 <zs_str_concat+0x1c8> @ imm = #0x1c
     942:      	subs	r1, #0x4
     944:      	subs	r3, r6, #0x4
     946:      	nop
     948:      	ldrb	r6, [r1, #4]!
     94c:      	subs	r2, #0x4
     94e:      	strb	r6, [r3, #4]!
     952:      	ldrb	r6, [r1, #0x1]
     954:      	strb	r6, [r3, #0x1]
     956:      	ldrb	r6, [r1, #0x2]
     958:      	strb	r6, [r3, #0x2]
     95a:      	ldrb	r6, [r1, #0x3]
     95c:      	strb	r6, [r3, #0x3]
     95e:      	bne	0x948 <zs_str_concat+0x1b0> @ imm = #-0x1a
     960:      	pop.w	{r8, r9, r11}
     964:      	pop	{r4, r5, r6, r7, pc}
     966:      	movw	r0, #0x1ea4
     96a:      	movt	r0, #0x0
     96e:      	bl	0x71c <zs_panic_c>      @ imm = #-0x256
     972:      	bmi	0x91e <zs_str_concat+0x186> @ imm = #-0x58

00000974 <zs_str_of_u64>:
     974:      	push	{r4, r5, r6, r7, lr}
     976:      	add	r7, sp, #0xc
     978:      	push.w	{r8, r9, r10, r11}
     97c:      	sub	sp, #0x34
     97e:      	movw	r9, #0xcccd
     982:      	mov	r5, r1
     984:      	mov	r6, r0
     986:      	mov.w	r10, #0x1
     98a:      	movt	r9, #0xcccc
     98e:      	add.w	r8, sp, #0x1c
     992:      	nop
     994:      	lsrs	r0, r6, #0x1
     996:      	orr.w	r0, r0, r5, lsl #31
     99a:      	adds.w	r1, r0, r5, lsr #1
     99e:      	adc	r1, r1, #0x0
     9a2:      	umull	r2, r3, r1, r9
     9a6:      	bic	r2, r3, #0x3
     9aa:      	add.w	r2, r2, r3, lsr #2
     9ae:      	subs	r1, r1, r2
     9b0:      	subs	r1, r0, r1
     9b2:      	umull	r0, r2, r1, r9
     9b6:      	add.w	r4, r0, r0, lsl #2
     9ba:      	lsr.w	r3, r5, #0x1
     9be:      	sub.w	r4, r6, r4, lsl #1
     9c2:      	sbc	r3, r3, #0x0
     9c6:      	orr	r12, r4, #0x30
     9ca:      	subs.w	r4, r6, #0xa
     9ce:      	add.w	r11, r8, r10
     9d2:      	sbcs	r4, r5, #0x0
     9d6:      	strb	r12, [r11, #-1]
     9da:      	blo	0xaca <zs_str_of_u64+0x156> @ imm = #0xec
     9dc:      	mov.w	r4, #0xcccccccc
     9e0:      	mla	r1, r1, r4, r2
     9e4:      	lsrs	r2, r0, #0x1
     9e6:      	mla	r1, r3, r9, r1
     9ea:      	and	r0, r0, #0x1
     9ee:      	orr.w	r2, r2, r1, lsl #31
     9f2:      	adds.w	r1, r2, r1, lsr #1
     9f6:      	adc	r1, r1, #0x0
     9fa:      	umull	r2, r3, r1, r9
     9fe:      	bic	r2, r3, #0x3
     a02:      	add.w	r2, r2, r3, lsr #2
     a06:      	subs	r1, r1, r2
     a08:      	orr.w	r0, r0, r1, lsl #1
     a0c:      	subs.w	r1, r6, #0x64
     a10:      	orr	r0, r0, #0x30
     a14:      	sbcs	r1, r5, #0x0
     a18:      	strb.w	r0, [r8, r10]
     a1c:      	blo	0xad2 <zs_str_of_u64+0x15e> @ imm = #0xb2
     a1e:      	mov	r0, r6
     a20:      	mov	r1, r5
     a22:      	movs	r2, #0x64
     a24:      	movs	r3, #0x0
     a26:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xe72
     a2a:      	lsrs	r2, r0, #0x1
     a2c:      	orr.w	r2, r2, r1, lsl #31
     a30:      	adds.w	r1, r2, r1, lsr #1
     a34:      	adc	r1, r1, #0x0
     a38:      	umull	r2, r3, r1, r9
     a3c:      	bic	r2, r3, #0x3
     a40:      	add.w	r2, r2, r3, lsr #2
     a44:      	subs	r1, r1, r2
     a46:      	and	r0, r0, #0x1
     a4a:      	orr.w	r0, r0, r1, lsl #1
     a4e:      	subs.w	r1, r6, #0x3e8
     a52:      	orr	r0, r0, #0x30
     a56:      	sbcs	r1, r5, #0x0
     a5a:      	strb.w	r0, [r11, #0x1]
     a5e:      	blo	0xada <zs_str_of_u64+0x166> @ imm = #0x78
     a60:      	mov	r0, r6
     a62:      	mov	r1, r5
     a64:      	mov.w	r2, #0x3e8
     a68:      	movs	r3, #0x0
     a6a:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xe2e
     a6e:      	lsrs	r2, r0, #0x1
     a70:      	orr.w	r2, r2, r1, lsl #31
     a74:      	adds.w	r1, r2, r1, lsr #1
     a78:      	adc	r1, r1, #0x0
     a7c:      	umull	r2, r3, r1, r9
     a80:      	bic	r2, r3, #0x3
     a84:      	add.w	r2, r2, r3, lsr #2
     a88:      	subs	r1, r1, r2
     a8a:      	and	r0, r0, #0x1
     a8e:      	orr.w	r0, r0, r1, lsl #1
     a92:      	orr	r0, r0, #0x30
     a96:      	strb.w	r0, [r11, #0x2]
     a9a:      	mov	r0, r6
     a9c:      	mov	r1, r5
     a9e:      	movw	r2, #0x2710
     aa2:      	movs	r3, #0x0
     aa4:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xdf4
     aa8:      	movw	r2, #0x270f
     aac:      	subs	r2, r2, r6
     aae:      	mov.w	r2, #0x0
     ab2:      	sbcs	r2, r5
     ab4:      	add.w	r10, r10, #0x4
     ab8:      	mov	r6, r0
     aba:      	mov	r5, r1
     abc:      	blo.w	0x994 <zs_str_of_u64+0x20> @ imm = #-0x12c
     ac0:      	sub.w	r1, r10, #0x1
     ac4:      	sub.w	r12, r10, #0x2
     ac8:      	b	0xae2 <zs_str_of_u64+0x16e> @ imm = #0x16
     aca:      	sub.w	r12, r10, #0x1
     ace:      	mov	r1, r10
     ad0:      	b	0xae4 <zs_str_of_u64+0x170> @ imm = #0x10
     ad2:      	add.w	r1, r10, #0x1
     ad6:      	mov	r12, r10
     ad8:      	b	0xae2 <zs_str_of_u64+0x16e> @ imm = #0x6
     ada:      	add.w	r1, r10, #0x2
     ade:      	add.w	r12, r10, #0x1
     ae2:      	mov	r10, r1
     ae4:      	and	lr, r1, #0x3
     ae8:      	lsrs	r3, r1, #0x2
     aea:      	mov.w	r1, #0x0
     aee:      	beq	0xb22 <zs_str_of_u64+0x1ae> @ imm = #0x30
     af0:      	add	r6, sp, #0x4
     af2:      	add.w	r5, r12, r8
     af6:      	sub.w	r9, r1, r3, lsl #2
     afa:      	subs	r6, #0x3
     afc:      	subs	r5, #0x1
     afe:      	nop
     b00:      	adds	r4, r5, r1
     b02:      	ldrb	r3, [r5, r1]
     b04:      	ldrb	r0, [r4, #-2]
     b08:      	ldrb	r2, [r4, #-1]
     b0c:      	ldrb	r4, [r4, #0x1]
     b0e:      	subs	r1, #0x4
     b10:      	strb	r3, [r6, #4]!
     b14:      	cmp	r9, r1
     b16:      	strb	r4, [r6, #-1]
     b1a:      	strb	r2, [r6, #0x1]
     b1c:      	strb	r0, [r6, #0x2]
     b1e:      	bne	0xb00 <zs_str_of_u64+0x18c> @ imm = #-0x22
     b20:      	rsbs	r1, r1, #0
     b22:      	cmp.w	lr, #0x0
     b26:      	beq	0xb58 <zs_str_of_u64+0x1e4> @ imm = #0x2e
     b28:      	sub.w	r0, r12, r1
     b2c:      	ldrb.w	r0, [r8, r0]
     b30:      	add	r3, sp, #0x4
     b32:      	cmp.w	lr, #0x1
     b36:      	strb	r0, [r3, r1]
     b38:      	beq	0xb58 <zs_str_of_u64+0x1e4> @ imm = #0x1c
     b3a:      	adds	r0, r1, #0x1
     b3c:      	sub.w	r2, r12, r0
     b40:      	ldrb.w	r2, [r8, r2]
     b44:      	cmp.w	lr, #0x2
     b48:      	strb	r2, [r3, r0]
     b4a:      	beq	0xb58 <zs_str_of_u64+0x1e4> @ imm = #0xa
     b4c:      	adds	r0, r1, #0x2
     b4e:      	sub.w	r1, r12, r0
     b52:      	ldrb.w	r1, [r8, r1]
     b56:      	strb	r1, [r3, r0]
     b58:      	add	r0, sp, #0x4
     b5a:      	mov	r1, r10
     b5c:      	bl	0xb68 <str_of>          @ imm = #0x8
     b60:      	add	sp, #0x34
     b62:      	pop.w	{r8, r9, r10, r11}
     b66:      	pop	{r4, r5, r6, r7, pc}

00000b68 <str_of>:
     b68:      	push	{r4, r5, r6, r7, lr}
     b6a:      	add	r7, sp, #0xc
     b6c:      	str	r11, [sp, #-4]!
     b70:      	add.w	r2, r1, #0x10
     b74:      	lsrs	r3, r2, #0x3
     b76:      	cmp	r3, #0x20
     b78:      	bhi	0xb96 <str_of+0x2e>     @ imm = #0x1a
     b7a:      	movw	lr, #0x0
     b7e:      	movt	lr, #0x2000
     b82:      	ldr.w	r4, [lr, r3, lsl #2]
     b86:      	cbz	r4, 0xb96 <str_of+0x2e> @ imm = #0xc
     b88:      	mov	r12, r4
     b8a:      	ldr	r4, [r4]
     b8c:      	ldr	r2, [r12, #-8]!
     b90:      	str.w	r4, [lr, r3, lsl #2]
     b94:      	b	0xbce <str_of+0x66>     @ imm = #0x36
     b96:      	movw	lr, #0x84
     b9a:      	movt	lr, #0x2000
     b9e:      	ldr.w	r3, [lr]
     ba2:      	bic	r2, r2, #0x7
     ba6:      	adds	r5, r2, r3
     ba8:      	movw	r4, #0xfff9
     bac:      	subs	r4, r5, r4
     bae:      	cmn.w	r4, #0x10001
     bb2:      	blo	0xcac <str_of+0x144>    @ imm = #0xf6
     bb4:      	movw	r4, #0x88
     bb8:      	movt	r4, #0x2000
     bbc:      	add.w	r12, r4, r3
     bc0:      	adds	r5, #0x8
     bc2:      	str	r2, [r4, r3]
     bc4:      	movs	r3, #0x0
     bc6:      	str.w	r5, [lr]
     bca:      	str.w	r3, [r12, #0x4]
     bce:      	movw	r5, #0x88
     bd2:      	movt	r5, #0x2001
     bd6:      	movw	lr, #0x8c
     bda:      	ldr	r4, [r5]
     bdc:      	movt	lr, #0x2001
     be0:      	ldr.w	r3, [lr]
     be4:      	add	r2, r4
     be6:      	cmp	r2, r3
     be8:      	str	r2, [r5]
     bea:      	it	hi
     bec:      	strhi.w	r2, [lr]
     bf0:      	movw	lr, #0x90
     bf4:      	movt	lr, #0x2001
     bf8:      	movw	r4, #0x98
     bfc:      	ldrd	r3, r5, [lr]
     c00:      	movt	r4, #0x2001
     c04:      	ldrd	r2, r6, [r4]
     c08:      	adds	r3, #0x1
     c0a:      	adc	r5, r5, #0x0
     c0e:      	adds	r2, #0x1
     c10:      	strd	r3, r5, [lr]
     c14:      	adc	r3, r6, #0x0
     c18:      	strd	r2, r3, [r4]
     c1c:      	movs	r3, #0x1
     c1e:      	mov	r2, r12
     c20:      	str	r3, [r2, #8]!
     c24:      	add.w	lr, r2, #0x8
     c28:      	movs	r3, #0x0
     c2a:      	str	r1, [r2, #0x4]
     c2c:      	strb.w	r3, [lr, r1]
     c30:      	cbz	r1, 0xca4 <str_of+0x13c> @ imm = #0x70
     c32:      	ands	r3, r1, #0x3
     c36:      	beq	0xc54 <str_of+0xec>     @ imm = #0x1a
     c38:      	mov	r4, r0
     c3a:      	ldrb	r6, [r4], #1
     c3e:      	cmp	r3, #0x1
     c40:      	strb.w	r6, [r12, #0x10]
     c44:      	bne	0xc5c <str_of+0xf4>     @ imm = #0x14
     c46:      	subs	r3, r1, #0x1
     c48:      	add.w	lr, r12, #0x11
     c4c:      	mov	r0, r4
     c4e:      	cmp	r1, #0x4
     c50:      	bhs	0xc86 <str_of+0x11e>    @ imm = #0x32
     c52:      	b	0xca4 <str_of+0x13c>    @ imm = #0x4e
     c54:      	mov	r3, r1
     c56:      	cmp	r1, #0x4
     c58:      	bhs	0xc86 <str_of+0x11e>    @ imm = #0x2a
     c5a:      	b	0xca4 <str_of+0x13c>    @ imm = #0x46
     c5c:      	ldrb	r6, [r0, #0x1]
     c5e:      	cmp	r3, #0x2
     c60:      	strb.w	r6, [r12, #0x11]
     c64:      	bne	0xc74 <str_of+0x10c>    @ imm = #0xc
     c66:      	subs	r3, r1, #0x2
     c68:      	adds	r0, #0x2
     c6a:      	add.w	lr, r12, #0x12
     c6e:      	cmp	r1, #0x4
     c70:      	bhs	0xc86 <str_of+0x11e>    @ imm = #0x12
     c72:      	b	0xca4 <str_of+0x13c>    @ imm = #0x2e
     c74:      	ldrb	r4, [r0, #0x2]
     c76:      	subs	r3, r1, #0x3
     c78:      	adds	r0, #0x3
     c7a:      	add.w	lr, r12, #0x13
     c7e:      	strb.w	r4, [r12, #0x12]
     c82:      	cmp	r1, #0x4
     c84:      	blo	0xca4 <str_of+0x13c>    @ imm = #0x1c
     c86:      	subs	r0, #0x4
     c88:      	sub.w	r1, lr, #0x4
     c8c:      	ldrb	r6, [r0, #4]!
     c90:      	subs	r3, #0x4
     c92:      	strb	r6, [r1, #4]!
     c96:      	ldrb	r6, [r0, #0x1]
     c98:      	strb	r6, [r1, #0x1]
     c9a:      	ldrb	r6, [r0, #0x2]
     c9c:      	strb	r6, [r1, #0x2]
     c9e:      	ldrb	r6, [r0, #0x3]
     ca0:      	strb	r6, [r1, #0x3]
     ca2:      	bne	0xc8c <str_of+0x124>    @ imm = #-0x1a
     ca4:      	mov	r0, r2
     ca6:      	ldr	r11, [sp], #4
     caa:      	pop	{r4, r5, r6, r7, pc}
     cac:      	movw	r0, #0x1ea4
     cb0:      	movt	r0, #0x0
     cb4:      	bl	0x71c <zs_panic_c>      @ imm = #-0x59c

00000cb8 <zs_str_of_i64>:
     cb8:      	push	{r4, r5, r6, r7, lr}
     cba:      	add	r7, sp, #0xc
     cbc:      	push.w	{r8, r9, r10, r11}
     cc0:      	sub	sp, #0x3c
     cc2:      	cmp.w	r1, #0xffffffff
     cc6:      	add	r2, sp, #0xc
     cc8:      	ble	0xcd0 <zs_str_of_i64+0x18> @ imm = #0x4
     cca:      	str	r2, [sp, #0x8]
     ccc:      	movs	r2, #0x0
     cce:      	b	0xcdc <zs_str_of_i64+0x24> @ imm = #0xa
     cd0:      	adds	r2, #0x1
     cd2:      	str	r2, [sp, #0x8]
     cd4:      	movs	r2, #0x2d
     cd6:      	strb.w	r2, [sp, #0xc]
     cda:      	movs	r2, #0x1
     cdc:      	eor.w	r0, r0, r1, asr #31
     ce0:      	str	r2, [sp, #0x4]
     ce2:      	eor.w	r2, r1, r1, asr #31
     ce6:      	subs.w	r4, r0, r1, asr #31
     cea:      	movw	r8, #0xcccd
     cee:      	sbc.w	r5, r2, r1, asr #31
     cf2:      	mov.w	r9, #0x1
     cf6:      	movt	r8, #0xcccc
     cfa:      	add.w	r10, sp, #0x24
     cfe:      	nop
     d00:      	lsrs	r0, r4, #0x1
     d02:      	orr.w	r0, r0, r5, lsl #31
     d06:      	adds.w	r1, r0, r5, lsr #1
     d0a:      	adc	r1, r1, #0x0
     d0e:      	umull	r2, r3, r1, r8
     d12:      	bic	r2, r3, #0x3
     d16:      	add.w	r2, r2, r3, lsr #2
     d1a:      	subs	r1, r1, r2
     d1c:      	subs	r1, r0, r1
     d1e:      	umull	r0, r2, r1, r8
     d22:      	add.w	r6, r0, r0, lsl #2
     d26:      	lsr.w	r3, r5, #0x1
     d2a:      	sub.w	r6, r4, r6, lsl #1
     d2e:      	sbc	r3, r3, #0x0
     d32:      	orr	r12, r6, #0x30
     d36:      	subs.w	r6, r4, #0xa
     d3a:      	add.w	r11, r10, r9
     d3e:      	sbcs	r6, r5, #0x0
     d42:      	strb	r12, [r11, #-1]
     d46:      	blo	0xe36 <zs_str_of_i64+0x17e> @ imm = #0xec
     d48:      	mov.w	r6, #0xcccccccc
     d4c:      	mla	r1, r1, r6, r2
     d50:      	lsrs	r2, r0, #0x1
     d52:      	mla	r1, r3, r8, r1
     d56:      	and	r0, r0, #0x1
     d5a:      	orr.w	r2, r2, r1, lsl #31
     d5e:      	adds.w	r1, r2, r1, lsr #1
     d62:      	adc	r1, r1, #0x0
     d66:      	umull	r2, r3, r1, r8
     d6a:      	bic	r2, r3, #0x3
     d6e:      	add.w	r2, r2, r3, lsr #2
     d72:      	subs	r1, r1, r2
     d74:      	orr.w	r0, r0, r1, lsl #1
     d78:      	subs.w	r1, r4, #0x64
     d7c:      	orr	r0, r0, #0x30
     d80:      	sbcs	r1, r5, #0x0
     d84:      	strb.w	r0, [r10, r9]
     d88:      	blo	0xe3e <zs_str_of_i64+0x186> @ imm = #0xb2
     d8a:      	mov	r0, r4
     d8c:      	mov	r1, r5
     d8e:      	movs	r2, #0x64
     d90:      	movs	r3, #0x0
     d92:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xb06
     d96:      	lsrs	r2, r0, #0x1
     d98:      	orr.w	r2, r2, r1, lsl #31
     d9c:      	adds.w	r1, r2, r1, lsr #1
     da0:      	adc	r1, r1, #0x0
     da4:      	umull	r2, r3, r1, r8
     da8:      	bic	r2, r3, #0x3
     dac:      	add.w	r2, r2, r3, lsr #2
     db0:      	subs	r1, r1, r2
     db2:      	and	r0, r0, #0x1
     db6:      	orr.w	r0, r0, r1, lsl #1
     dba:      	subs.w	r1, r4, #0x3e8
     dbe:      	orr	r0, r0, #0x30
     dc2:      	sbcs	r1, r5, #0x0
     dc6:      	strb.w	r0, [r11, #0x1]
     dca:      	blo	0xe46 <zs_str_of_i64+0x18e> @ imm = #0x78
     dcc:      	mov	r0, r4
     dce:      	mov	r1, r5
     dd0:      	mov.w	r2, #0x3e8
     dd4:      	movs	r3, #0x0
     dd6:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xac2
     dda:      	lsrs	r2, r0, #0x1
     ddc:      	orr.w	r2, r2, r1, lsl #31
     de0:      	adds.w	r1, r2, r1, lsr #1
     de4:      	adc	r1, r1, #0x0
     de8:      	umull	r2, r3, r1, r8
     dec:      	bic	r2, r3, #0x3
     df0:      	add.w	r2, r2, r3, lsr #2
     df4:      	subs	r1, r1, r2
     df6:      	and	r0, r0, #0x1
     dfa:      	orr.w	r0, r0, r1, lsl #1
     dfe:      	orr	r0, r0, #0x30
     e02:      	strb.w	r0, [r11, #0x2]
     e06:      	mov	r0, r4
     e08:      	mov	r1, r5
     e0a:      	movw	r2, #0x2710
     e0e:      	movs	r3, #0x0
     e10:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xa88
     e14:      	movw	r2, #0x270f
     e18:      	subs	r2, r2, r4
     e1a:      	mov.w	r2, #0x0
     e1e:      	sbcs	r2, r5
     e20:      	add.w	r9, r9, #0x4
     e24:      	mov	r4, r0
     e26:      	mov	r5, r1
     e28:      	blo.w	0xd00 <zs_str_of_i64+0x48> @ imm = #-0x12c
     e2c:      	sub.w	r1, r9, #0x1
     e30:      	sub.w	r12, r9, #0x2
     e34:      	b	0xe4e <zs_str_of_i64+0x196> @ imm = #0x16
     e36:      	sub.w	r12, r9, #0x1
     e3a:      	mov	r1, r9
     e3c:      	b	0xe50 <zs_str_of_i64+0x198> @ imm = #0x10
     e3e:      	add.w	r1, r9, #0x1
     e42:      	mov	r12, r9
     e44:      	b	0xe4e <zs_str_of_i64+0x196> @ imm = #0x6
     e46:      	add.w	r1, r9, #0x2
     e4a:      	add.w	r12, r9, #0x1
     e4e:      	mov	r9, r1
     e50:      	ldr.w	r8, [sp, #0x8]
     e54:      	and	lr, r1, #0x3
     e58:      	lsrs	r3, r1, #0x2
     e5a:      	mov.w	r1, #0x0
     e5e:      	beq	0xe90 <zs_str_of_i64+0x1d8> @ imm = #0x2e
     e60:      	add.w	r6, r12, r10
     e64:      	sub.w	r3, r1, r3, lsl #2
     e68:      	sub.w	r5, r8, #0x3
     e6c:      	subs	r4, r6, #0x1
     e6e:      	nop
     e70:      	adds	r6, r4, r1
     e72:      	ldrb	r0, [r6, #0x1]
     e74:      	ldrb	r2, [r6, #-1]
     e78:      	strb	r0, [r5, #0x3]
     e7a:      	ldrb	r0, [r4, r1]
     e7c:      	subs	r1, #0x4
     e7e:      	strb	r0, [r5, #4]!
     e82:      	ldrb	r0, [r6, #-2]
     e86:      	cmp	r3, r1
     e88:      	strb	r2, [r5, #0x1]
     e8a:      	strb	r0, [r5, #0x2]
     e8c:      	bne	0xe70 <zs_str_of_i64+0x1b8> @ imm = #-0x20
     e8e:      	rsbs	r1, r1, #0
     e90:      	cmp.w	lr, #0x0
     e94:      	beq	0xeca <zs_str_of_i64+0x212> @ imm = #0x32
     e96:      	sub.w	r0, r12, r1
     e9a:      	ldrb.w	r0, [r10, r0]
     e9e:      	cmp.w	lr, #0x1
     ea2:      	strb.w	r0, [r8, r1]
     ea6:      	beq	0xeca <zs_str_of_i64+0x212> @ imm = #0x20
     ea8:      	adds	r0, r1, #0x1
     eaa:      	sub.w	r2, r12, r0
     eae:      	ldrb.w	r2, [r10, r2]
     eb2:      	cmp.w	lr, #0x2
     eb6:      	strb.w	r2, [r8, r0]
     eba:      	beq	0xeca <zs_str_of_i64+0x212> @ imm = #0xc
     ebc:      	adds	r0, r1, #0x2
     ebe:      	sub.w	r1, r12, r0
     ec2:      	ldrb.w	r1, [r10, r1]
     ec6:      	strb.w	r1, [r8, r0]
     eca:      	ldr	r0, [sp, #0x4]
     ecc:      	add.w	r1, r9, r0
     ed0:      	add	r0, sp, #0xc
     ed2:      	bl	0xb68 <str_of>          @ imm = #-0x36e
     ed6:      	add	sp, #0x3c
     ed8:      	pop.w	{r8, r9, r10, r11}
     edc:      	pop	{r4, r5, r6, r7, pc}
     ede:      	bmi	0xe8a <zs_str_of_i64+0x1d2> @ imm = #-0x58

00000ee0 <zs_println>:
     ee0:      	push	{r4, r5, r6, r7, lr}
     ee2:      	add	r7, sp, #0xc
     ee4:      	push.w	{r8, r9, r10, r11}
     ee8:      	sub	sp, #0x44
     eea:      	ldr.w	r11, [r0, #0x4]
     eee:      	cmp.w	r11, #0x1
     ef2:      	blt	0xfe4 <zs_println+0x104> @ imm = #0xee
     ef4:      	sub.w	r1, r7, #0x5d
     ef8:      	movs	r2, #0x0
     efa:      	add.w	r3, r0, #0x8
     efe:      	add.w	r12, r1, #0x1
     f02:      	movs	r6, #0x40
     f04:      	mov.w	r9, #0x0
     f08:      	b	0xf28 <zs_println+0x48> @ imm = #0x1c
     f0a:      	nop
     f0c:      	strb.w	r2, [r1, r8]
     f10:      	movs	r0, #0x4
     f12:      	subs.w	r11, r11, r8
     f16:      	bkpt	#0xab
     f18:      	sbc	r9, r9, #0x0
     f1c:      	rsbs.w	r0, r11, #0x0
     f20:      	sbcs.w	r0, r2, r9
     f24:      	add	r3, r8
     f26:      	bge	0xfe4 <zs_println+0x104> @ imm = #0xba
     f28:      	mov.w	r8, #0x40
     f2c:      	cmp.w	r11, #0x40
     f30:      	it	lo
     f32:      	movlo	r8, r11
     f34:      	cmp.w	r9, #0x0
     f38:      	it	ne
     f3a:      	movne	r8, r6
     f3c:      	sub.w	r0, r8, #0x1
     f40:      	cmp	r0, #0x3
     f42:      	bhs	0xf50 <zs_println+0x70> @ imm = #0xa
     f44:      	movs	r0, #0x0
     f46:      	ands	r4, r8, #0x3
     f4a:      	bne	0xfb2 <zs_println+0xd2> @ imm = #0x64
     f4c:      	b	0xf0c <zs_println+0x2c> @ imm = #-0x44
     f4e:      	nop
     f50:      	bic	r0, r8, #0x3
     f54:      	rsb.w	r10, r0, #0x0
     f58:      	mov	r1, r3
     f5a:      	adds	r5, r3, #0x1
     f5c:      	mvn	r4, #0x3
     f60:      	adds	r2, r5, r4
     f62:      	ldrb	r6, [r2, #0x3]
     f64:      	ldrb	r3, [r2, #0x4]
     f66:      	ldrb	r0, [r2, #0x5]
     f68:      	cmp	r6, #0x0
     f6a:      	ldrb	r2, [r2, #0x6]
     f6c:      	it	eq
     f6e:      	moveq	r6, #0x20
     f70:      	add.w	lr, r12, r4
     f74:      	cmp	r3, #0x0
     f76:      	strb.w	r6, [lr, #0x3]
     f7a:      	it	eq
     f7c:      	moveq	r3, #0x20
     f7e:      	strb.w	r3, [lr, #0x4]
     f82:      	cmp	r0, #0x0
     f84:      	it	eq
     f86:      	moveq	r0, #0x20
     f88:      	adds	r4, #0x4
     f8a:      	strb.w	r0, [lr, #0x5]
     f8e:      	cmp	r2, #0x0
     f90:      	add.w	r0, r10, r4
     f94:      	it	eq
     f96:      	moveq	r2, #0x20
     f98:      	adds	r0, #0x4
     f9a:      	strb.w	r2, [lr, #0x6]
     f9e:      	bne	0xf60 <zs_println+0x80> @ imm = #-0x42
     fa0:      	adds	r0, r4, #0x4
     fa2:      	movs	r2, #0x0
     fa4:      	mov	r3, r1
     fa6:      	sub.w	r1, r7, #0x5d
     faa:      	movs	r6, #0x40
     fac:      	ands	r4, r8, #0x3
     fb0:      	beq	0xf0c <zs_println+0x2c> @ imm = #-0xa8
     fb2:      	ldrb	r5, [r3, r0]
     fb4:      	cmp	r5, #0x0
     fb6:      	it	eq
     fb8:      	moveq	r5, #0x20
     fba:      	cmp	r4, #0x1
     fbc:      	strb	r5, [r1, r0]
     fbe:      	beq	0xf0c <zs_println+0x2c> @ imm = #-0xb6
     fc0:      	add.w	r10, r0, #0x1
     fc4:      	ldrb.w	r5, [r3, r10]
     fc8:      	cmp	r5, #0x0
     fca:      	it	eq
     fcc:      	moveq	r5, #0x20
     fce:      	cmp	r4, #0x2
     fd0:      	strb.w	r5, [r1, r10]
     fd4:      	beq	0xf0c <zs_println+0x2c> @ imm = #-0xcc
     fd6:      	adds	r0, #0x2
     fd8:      	ldrb	r4, [r3, r0]
     fda:      	cmp	r4, #0x0
     fdc:      	it	eq
     fde:      	moveq	r4, #0x20
     fe0:      	strb	r4, [r1, r0]
     fe2:      	b	0xf0c <zs_println+0x2c> @ imm = #-0xda
     fe4:      	movs	r0, #0xa
     fe6:      	strh	r0, [r7, #-93]
     fea:      	movs	r0, #0x4
     fec:      	sub.w	r1, r7, #0x5d
     ff0:      	bkpt	#0xab
     ff2:      	add	sp, #0x44
     ff4:      	pop.w	{r8, r9, r10, r11}
     ff8:      	pop	{r4, r5, r6, r7, pc}
     ffa:      	bmi	0xfa6 <zs_println+0xc6> @ imm = #-0x58

00000ffc <write_c>:
     ffc:      	push	{r4, r5, r6, r7, lr}
     ffe:      	add	r7, sp, #0xc
    1000:      	push.w	{r8, r9, r10, r11}
    1004:      	sub	sp, #0x44
    1006:      	mov	r2, r0
    1008:      	mov.w	r11, #0xffffffff
    100c:      	add.w	r0, r2, r11
    1010:      	ldrb	r1, [r0, #0x1]
    1012:      	cbz	r1, 0x102c <write_c+0x30> @ imm = #0x16
    1014:      	ldrb	r1, [r0, #0x2]
    1016:      	cbz	r1, 0x1038 <write_c+0x3c> @ imm = #0x1e
    1018:      	ldrb	r1, [r0, #0x3]
    101a:      	cmp	r1, #0x0
    101c:      	beq.w	0x112c <write_c+0x130>  @ imm = #0x10c
    1020:      	ldrb	r0, [r0, #0x4]
    1022:      	add.w	r11, r11, #0x4
    1026:      	cmp	r0, #0x0
    1028:      	bne	0x100c <write_c+0x10>   @ imm = #-0x20
    102a:      	b	0x103c <write_c+0x40>   @ imm = #0xe
    102c:      	add.w	r11, r11, #0x1
    1030:      	cmp.w	r11, #0x0
    1034:      	bne	0x1042 <write_c+0x46>   @ imm = #0xa
    1036:      	b	0x1138 <write_c+0x13c>  @ imm = #0xfe
    1038:      	add.w	r11, r11, #0x2
    103c:      	cmp.w	r11, #0x0
    1040:      	beq	0x1138 <write_c+0x13c>  @ imm = #0xf4
    1042:      	sub.w	r1, r7, #0x5d
    1046:      	movs	r3, #0x0
    1048:      	add.w	r12, r1, #0x1
    104c:      	movs	r6, #0x40
    104e:      	mov.w	r9, #0x0
    1052:      	b	0x1070 <write_c+0x74>   @ imm = #0x1a
    1054:      	strb.w	r3, [r1, r8]
    1058:      	movs	r0, #0x4
    105a:      	subs.w	r11, r11, r8
    105e:      	bkpt	#0xab
    1060:      	sbc	r9, r9, #0x0
    1064:      	rsbs.w	r0, r11, #0x0
    1068:      	sbcs.w	r0, r3, r9
    106c:      	add	r2, r8
    106e:      	bge	0x1138 <write_c+0x13c>  @ imm = #0xc6
    1070:      	mov.w	r8, #0x40
    1074:      	cmp.w	r11, #0x40
    1078:      	it	lo
    107a:      	movlo	r8, r11
    107c:      	cmp.w	r9, #0x0
    1080:      	it	ne
    1082:      	movne	r8, r6
    1084:      	sub.w	r0, r8, #0x1
    1088:      	cmp	r0, #0x3
    108a:      	bhs	0x1098 <write_c+0x9c>   @ imm = #0xa
    108c:      	movs	r0, #0x0
    108e:      	ands	r4, r8, #0x3
    1092:      	bne	0x10fa <write_c+0xfe>   @ imm = #0x64
    1094:      	b	0x1054 <write_c+0x58>   @ imm = #-0x44
    1096:      	nop
    1098:      	bic	r0, r8, #0x3
    109c:      	rsb.w	r10, r0, #0x0
    10a0:      	mov	r1, r2
    10a2:      	adds	r5, r2, #0x1
    10a4:      	mvn	r4, #0x3
    10a8:      	adds	r3, r5, r4
    10aa:      	ldrb	r6, [r3, #0x3]
    10ac:      	ldrb	r2, [r3, #0x4]
    10ae:      	ldrb	r0, [r3, #0x5]
    10b0:      	cmp	r6, #0x0
    10b2:      	ldrb	r3, [r3, #0x6]
    10b4:      	it	eq
    10b6:      	moveq	r6, #0x20
    10b8:      	add.w	lr, r12, r4
    10bc:      	cmp	r2, #0x0
    10be:      	strb.w	r6, [lr, #0x3]
    10c2:      	it	eq
    10c4:      	moveq	r2, #0x20
    10c6:      	strb.w	r2, [lr, #0x4]
    10ca:      	cmp	r0, #0x0
    10cc:      	it	eq
    10ce:      	moveq	r0, #0x20
    10d0:      	adds	r4, #0x4
    10d2:      	strb.w	r0, [lr, #0x5]
    10d6:      	cmp	r3, #0x0
    10d8:      	add.w	r0, r10, r4
    10dc:      	it	eq
    10de:      	moveq	r3, #0x20
    10e0:      	adds	r0, #0x4
    10e2:      	strb.w	r3, [lr, #0x6]
    10e6:      	bne	0x10a8 <write_c+0xac>   @ imm = #-0x42
    10e8:      	adds	r0, r4, #0x4
    10ea:      	mov	r2, r1
    10ec:      	movs	r3, #0x0
    10ee:      	sub.w	r1, r7, #0x5d
    10f2:      	movs	r6, #0x40
    10f4:      	ands	r4, r8, #0x3
    10f8:      	beq	0x1054 <write_c+0x58>   @ imm = #-0xa8
    10fa:      	ldrb	r5, [r2, r0]
    10fc:      	cmp	r5, #0x0
    10fe:      	it	eq
    1100:      	moveq	r5, #0x20
    1102:      	cmp	r4, #0x1
    1104:      	strb	r5, [r1, r0]
    1106:      	beq	0x1054 <write_c+0x58>   @ imm = #-0xb6
    1108:      	add.w	r10, r0, #0x1
    110c:      	ldrb.w	r5, [r2, r10]
    1110:      	cmp	r5, #0x0
    1112:      	it	eq
    1114:      	moveq	r5, #0x20
    1116:      	cmp	r4, #0x2
    1118:      	strb.w	r5, [r1, r10]
    111c:      	beq	0x1054 <write_c+0x58>   @ imm = #-0xcc
    111e:      	adds	r0, #0x2
    1120:      	ldrb	r4, [r2, r0]
    1122:      	cmp	r4, #0x0
    1124:      	it	eq
    1126:      	moveq	r4, #0x20
    1128:      	strb	r4, [r1, r0]
    112a:      	b	0x1054 <write_c+0x58>   @ imm = #-0xda
    112c:      	add.w	r11, r11, #0x3
    1130:      	cmp.w	r11, #0x0
    1134:      	bne.w	0x1042 <write_c+0x46>   @ imm = #-0xf6
    1138:      	add	sp, #0x44
    113a:      	pop.w	{r8, r9, r10, r11}
    113e:      	pop	{r4, r5, r6, r7, pc}

00001140 <stop>:
    1140:      	push	{r4, r5, r6, r7, lr}
    1142:      	add	r7, sp, #0xc
    1144:      	str	r11, [sp, #-4]!
    1148:      	sub	sp, #0x48
    114a:      	movw	r6, #0x8000
    114e:      	movw	r5, #0x0
    1152:      	movt	r6, #0x203f
    1156:      	movt	r5, #0x2040
    115a:      	cmp	r6, r5
    115c:      	mov	r4, r0
    115e:      	bhs	0x11aa <stop+0x6a>      @ imm = #0x48
    1160:      	movw	r0, #0x8000
    1164:      	movt	r0, #0x203f
    1168:      	ldr	r1, [r0]
    116a:      	cmp.w	r1, #0xcdcdcdcd
    116e:      	bne	0x11a8 <stop+0x68>      @ imm = #0x36
    1170:      	adds	r6, r0, #0x4
    1172:      	cmp	r6, r5
    1174:      	bhs	0x11aa <stop+0x6a>      @ imm = #0x32
    1176:      	ldr	r1, [r6]
    1178:      	cmp.w	r1, #0xcdcdcdcd
    117c:      	bne	0x11aa <stop+0x6a>      @ imm = #0x2a
    117e:      	add.w	r6, r0, #0x8
    1182:      	cmp	r6, r5
    1184:      	bhs	0x11aa <stop+0x6a>      @ imm = #0x22
    1186:      	ldr	r1, [r6]
    1188:      	cmp.w	r1, #0xcdcdcdcd
    118c:      	bne	0x11aa <stop+0x6a>      @ imm = #0x1a
    118e:      	add.w	r6, r0, #0xc
    1192:      	cmp	r6, r5
    1194:      	bhs	0x11aa <stop+0x6a>      @ imm = #0x12
    1196:      	ldr	r1, [r6]
    1198:      	cmp.w	r1, #0xcdcdcdcd
    119c:      	bne	0x11aa <stop+0x6a>      @ imm = #0xa
    119e:      	adds	r0, #0x10
    11a0:      	cmp	r0, r5
    11a2:      	mov	r6, r0
    11a4:      	blo	0x1168 <stop+0x28>      @ imm = #-0x40
    11a6:      	b	0x11aa <stop+0x6a>      @ imm = #0x0
    11a8:      	mov	r6, r0
    11aa:      	movw	r0, #0x8c
    11ae:      	movt	r0, #0x2001
    11b2:      	ldr	r2, [r0]
    11b4:      	movw	r0, #0x1ed3
    11b8:      	movt	r0, #0x0
    11bc:      	movs	r3, #0x0
    11be:      	bl	0x13b0 <text>           @ imm = #0x1ee
    11c2:      	movw	r0, #0x84
    11c6:      	movt	r0, #0x2000
    11ca:      	ldr	r2, [r0]
    11cc:      	movw	r0, #0x1ee9
    11d0:      	movt	r0, #0x0
    11d4:      	movs	r3, #0x0
    11d6:      	bl	0x13b0 <text>           @ imm = #0x1d6
    11da:      	movw	r0, #0x98
    11de:      	movt	r0, #0x2001
    11e2:      	ldrd	r2, r3, [r0]
    11e6:      	movw	r0, #0x1ebd
    11ea:      	movt	r0, #0x0
    11ee:      	bl	0x13b0 <text>           @ imm = #0x1be
    11f2:      	movw	r0, #0x90
    11f6:      	movt	r0, #0x2001
    11fa:      	ldrd	r2, r3, [r0]
    11fe:      	movw	r0, #0x1ee2
    1202:      	movt	r0, #0x0
    1206:      	bl	0x13b0 <text>           @ imm = #0x1a6
    120a:      	subs	r2, r5, r6
    120c:      	movw	r0, #0x1ecb
    1210:      	asrs	r3, r2, #0x1f
    1212:      	movt	r0, #0x0
    1216:      	bl	0x13b0 <text>           @ imm = #0x196
    121a:      	movs	r0, #0xa
    121c:      	strh.w	r0, [sp, #0x4]
    1220:      	movs	r0, #0x4
    1222:      	add	r1, sp, #0x4
    1224:      	bkpt	#0xab
    1226:      	movs	r0, #0x26
    1228:      	movt	r0, #0x2
    122c:      	strd	r0, r4, [sp, #4]
    1230:      	movs	r0, #0x20
    1232:      	add	r1, sp, #0x4
    1234:      	bkpt	#0xab
    1236:      	nop
    1238:      	b	0x1238 <stop+0xf8>      @ imm = #-0x4
    123a:      	bmi	0x11e6 <stop+0xa6>      @ imm = #-0x58

0000123c <zs_set_args>:
    123c:      	push	{r7, lr}
    123e:      	mov	r7, sp
    1240:      	pop	{r7, pc}
    1242:      	bmi	0x11ee <stop+0xae>      @ imm = #-0x58

00001244 <Reset_Handler>:
    1244:      	push	{r7, lr}
    1246:      	mov	r7, sp
    1248:      	movw	r0, #0x0
    124c:      	movw	r1, #0x0
    1250:      	movt	r0, #0x2000
    1254:      	movt	r1, #0x2000
    1258:      	cmp	r1, r0
    125a:      	bhs	0x128e <Reset_Handler+0x4a> @ imm = #0x30
    125c:      	movw	r2, #0x201c
    1260:      	movt	r2, #0x0
    1264:      	ldr	r3, [r2]
    1266:      	str	r3, [r1], #4
    126a:      	cmp	r1, r0
    126c:      	bhs	0x128e <Reset_Handler+0x4a> @ imm = #0x1e
    126e:      	ldr	r3, [r2, #0x4]
    1270:      	str	r3, [r1], #4
    1274:      	cmp	r1, r0
    1276:      	bhs	0x128e <Reset_Handler+0x4a> @ imm = #0x14
    1278:      	ldr	r3, [r2, #0x8]
    127a:      	str	r3, [r1], #4
    127e:      	cmp	r1, r0
    1280:      	bhs	0x128e <Reset_Handler+0x4a> @ imm = #0xa
    1282:      	ldr	r3, [r2, #0xc]
    1284:      	adds	r2, #0x10
    1286:      	str	r3, [r1], #4
    128a:      	cmp	r1, r0
    128c:      	blo	0x1264 <Reset_Handler+0x20> @ imm = #-0x2c
    128e:      	movw	r0, #0xa4
    1292:      	movw	r1, #0x0
    1296:      	movt	r0, #0x2001
    129a:      	movt	r1, #0x2000
    129e:      	cmp	r1, r0
    12a0:      	bhs	0x12c4 <Reset_Handler+0x80> @ imm = #0x20
    12a2:      	movs	r2, #0x0
    12a4:      	str	r2, [r1], #4
    12a8:      	cmp	r1, r0
    12aa:      	bhs	0x12c4 <Reset_Handler+0x80> @ imm = #0x16
    12ac:      	str	r2, [r1], #4
    12b0:      	cmp	r1, r0
    12b2:      	bhs	0x12c4 <Reset_Handler+0x80> @ imm = #0xe
    12b4:      	str	r2, [r1], #4
    12b8:      	cmp	r1, r0
    12ba:      	bhs	0x12c4 <Reset_Handler+0x80> @ imm = #0x6
    12bc:      	str	r2, [r1], #4
    12c0:      	cmp	r1, r0
    12c2:      	blo	0x12a4 <Reset_Handler+0x60> @ imm = #-0x22
    12c4:      	movw	r0, #0xed88
    12c8:      	movt	r0, #0xe000
    12cc:      	ldr	r1, [r0]
    12ce:      	orr	r1, r1, #0xf00000
    12d2:      	str	r1, [r0]
    12d4:      	movw	r0, #0xe010
    12d8:      	movt	r0, #0xe000
    12dc:      	mvn	r1, #0xff000000
    12e0:      	dsb	sy
    12e4:      	isb	sy
    12e8:      	str	r1, [r0, #0x4]
    12ea:      	movs	r1, #0x0
    12ec:      	str	r1, [r0, #0x8]
    12ee:      	movs	r1, #0x7
    12f0:      	str	r1, [r0]
    12f2:      	mov	r0, sp
    12f4:      	movw	r1, #0x8000
    12f8:      	subs	r0, #0x40
    12fa:      	movt	r1, #0x203f
    12fe:      	cmp	r0, r1
    1300:      	bls	0x1328 <Reset_Handler+0xe4> @ imm = #0x24
    1302:      	mov.w	r2, #0xcdcdcdcd
    1306:      	nop
    1308:      	str	r2, [r1], #4
    130c:      	cmp	r1, r0
    130e:      	bhs	0x1328 <Reset_Handler+0xe4> @ imm = #0x16
    1310:      	str	r2, [r1], #4
    1314:      	cmp	r1, r0
    1316:      	bhs	0x1328 <Reset_Handler+0xe4> @ imm = #0xe
    1318:      	str	r2, [r1], #4
    131c:      	cmp	r1, r0
    131e:      	bhs	0x1328 <Reset_Handler+0xe4> @ imm = #0x6
    1320:      	str	r2, [r1], #4
    1324:      	cmp	r1, r0
    1326:      	blo	0x1308 <Reset_Handler+0xc4> @ imm = #-0x22
    1328:      	movs	r0, #0x0
    132a:      	movs	r1, #0x0
    132c:      	bl	0x40 <main>             @ imm = #-0x12f0
    1330:      	bl	0x1140 <stop>           @ imm = #-0x1f4

00001334 <zs_ticks>:
    1334:      	push	{r7, lr}
    1336:      	mov	r7, sp
    1338:      	movw	r12, #0xe018
    133c:      	movw	r2, #0xa0
    1340:      	movt	r12, #0xe000
    1344:      	movt	r2, #0x2001
    1348:      	ldr	r1, [r2]
    134a:      	ldr.w	r3, [r12]
    134e:      	ldr	r0, [r2]
    1350:      	cmp	r1, r0
    1352:      	beq	0x1378 <zs_ticks+0x44>  @ imm = #0x22
    1354:      	ldr	r1, [r2]
    1356:      	ldr.w	r3, [r12]
    135a:      	ldr	r0, [r2]
    135c:      	cmp	r1, r0
    135e:      	beq	0x1378 <zs_ticks+0x44>  @ imm = #0x16
    1360:      	ldr	r1, [r2]
    1362:      	ldr.w	r3, [r12]
    1366:      	ldr	r0, [r2]
    1368:      	cmp	r1, r0
    136a:      	beq	0x1378 <zs_ticks+0x44>  @ imm = #0xa
    136c:      	ldr	r1, [r2]
    136e:      	ldr.w	r3, [r12]
    1372:      	ldr	r0, [r2]
    1374:      	cmp	r1, r0
    1376:      	bne	0x1348 <zs_ticks+0x14>  @ imm = #-0x32
    1378:      	mvn	r0, #0xff000000
    137c:      	subs	r0, r0, r3
    137e:      	lsrs	r2, r1, #0x8
    1380:      	adds.w	r0, r0, r1, lsl #24
    1384:      	adc	r1, r2, #0x0
    1388:      	pop	{r7, pc}
    138a:      	bmi	0x1336 <zs_ticks+0x2>   @ imm = #-0x58

0000138c <fault>:
    138c:      	push	{r7, lr}
    138e:      	mov	r7, sp
    1390:      	movw	r0, #0x1eb2
    1394:      	movt	r0, #0x0
    1398:      	bl	0x71c <zs_panic_c>      @ imm = #-0xc80

0000139c <SysTick_Handler>:
    139c:      	push	{r7, lr}
    139e:      	mov	r7, sp
    13a0:      	movw	r0, #0xa0
    13a4:      	movt	r0, #0x2001
    13a8:      	ldr	r1, [r0]
    13aa:      	adds	r1, #0x1
    13ac:      	str	r1, [r0]
    13ae:      	pop	{r7, pc}

000013b0 <text>:
    13b0:      	push	{r4, r5, r6, r7, lr}
    13b2:      	add	r7, sp, #0xc
    13b4:      	push.w	{r8, r9, r10, r11}
    13b8:      	sub	sp, #0x64
    13ba:      	strd	r2, r3, [sp]
    13be:      	mov	r3, r0
    13c0:      	mov.w	r12, #0xffffffff
    13c4:      	add.w	r0, r3, r12
    13c8:      	ldrb	r1, [r0, #0x1]
    13ca:      	cbz	r1, 0x13e6 <text+0x36>  @ imm = #0x18
    13cc:      	ldrb	r1, [r0, #0x2]
    13ce:      	cbz	r1, 0x13f2 <text+0x42>  @ imm = #0x20
    13d0:      	ldrb	r1, [r0, #0x3]
    13d2:      	cbz	r1, 0x13fe <text+0x4e>  @ imm = #0x28
    13d4:      	ldrb	r0, [r0, #0x4]
    13d6:      	add.w	r12, r12, #0x4
    13da:      	cmp	r0, #0x0
    13dc:      	bne	0x13c4 <text+0x14>      @ imm = #-0x1c
    13de:      	cmp.w	r12, #0x0
    13e2:      	bne	0x1408 <text+0x58>      @ imm = #0x22
    13e4:      	b	0x14f6 <text+0x146>     @ imm = #0x10e
    13e6:      	add.w	r12, r12, #0x1
    13ea:      	cmp.w	r12, #0x0
    13ee:      	bne	0x1408 <text+0x58>      @ imm = #0x16
    13f0:      	b	0x14f6 <text+0x146>     @ imm = #0x102
    13f2:      	add.w	r12, r12, #0x2
    13f6:      	cmp.w	r12, #0x0
    13fa:      	bne	0x1408 <text+0x58>      @ imm = #0xa
    13fc:      	b	0x14f6 <text+0x146>     @ imm = #0xf6
    13fe:      	add.w	r12, r12, #0x3
    1402:      	cmp.w	r12, #0x0
    1406:      	beq	0x14f6 <text+0x146>     @ imm = #0xec
    1408:      	sub.w	r1, r7, #0x5d
    140c:      	movs	r4, #0x0
    140e:      	add.w	r10, r1, #0x1
    1412:      	movs	r5, #0x40
    1414:      	mov.w	r9, #0x0
    1418:      	b	0x1438 <text+0x88>      @ imm = #0x1c
    141a:      	nop
    141c:      	strb.w	r4, [r1, r11]
    1420:      	movs	r0, #0x4
    1422:      	subs.w	r12, r12, r11
    1426:      	bkpt	#0xab
    1428:      	sbc	r9, r9, #0x0
    142c:      	rsbs.w	r0, r12, #0x0
    1430:      	sbcs.w	r0, r4, r9
    1434:      	add	r3, r11
    1436:      	bge	0x14f6 <text+0x146>     @ imm = #0xbc
    1438:      	mov.w	r11, #0x40
    143c:      	cmp.w	r12, #0x40
    1440:      	it	lo
    1442:      	movlo	r11, r12
    1444:      	cmp.w	r9, #0x0
    1448:      	it	ne
    144a:      	movne	r11, r5
    144c:      	sub.w	r0, r11, #0x1
    1450:      	cmp	r0, #0x3
    1452:      	bhs	0x1460 <text+0xb0>      @ imm = #0xa
    1454:      	movs	r0, #0x0
    1456:      	ands	r2, r11, #0x3
    145a:      	bne	0x14c2 <text+0x112>     @ imm = #0x64
    145c:      	b	0x141c <text+0x6c>      @ imm = #-0x44
    145e:      	nop
    1460:      	bic	r0, r11, #0x3
    1464:      	rsb.w	lr, r0, #0x0
    1468:      	mov	r1, r3
    146a:      	adds	r6, r3, #0x1
    146c:      	mvn	r2, #0x3
    1470:      	adds	r3, r6, r2
    1472:      	ldrb	r5, [r3, #0x3]
    1474:      	ldrb	r4, [r3, #0x4]
    1476:      	ldrb	r0, [r3, #0x5]
    1478:      	cmp	r5, #0x0
    147a:      	ldrb	r3, [r3, #0x6]
    147c:      	it	eq
    147e:      	moveq	r5, #0x20
    1480:      	add.w	r8, r10, r2
    1484:      	cmp	r4, #0x0
    1486:      	strb.w	r5, [r8, #0x3]
    148a:      	it	eq
    148c:      	moveq	r4, #0x20
    148e:      	strb.w	r4, [r8, #0x4]
    1492:      	cmp	r0, #0x0
    1494:      	it	eq
    1496:      	moveq	r0, #0x20
    1498:      	adds	r2, #0x4
    149a:      	strb.w	r0, [r8, #0x5]
    149e:      	cmp	r3, #0x0
    14a0:      	add.w	r0, lr, r2
    14a4:      	it	eq
    14a6:      	moveq	r3, #0x20
    14a8:      	adds	r0, #0x4
    14aa:      	strb.w	r3, [r8, #0x6]
    14ae:      	bne	0x1470 <text+0xc0>      @ imm = #-0x42
    14b0:      	adds	r0, r2, #0x4
    14b2:      	mov	r3, r1
    14b4:      	movs	r4, #0x0
    14b6:      	sub.w	r1, r7, #0x5d
    14ba:      	movs	r5, #0x40
    14bc:      	ands	r2, r11, #0x3
    14c0:      	beq	0x141c <text+0x6c>      @ imm = #-0xa8
    14c2:      	ldrb	r6, [r3, r0]
    14c4:      	cmp	r6, #0x0
    14c6:      	it	eq
    14c8:      	moveq	r6, #0x20
    14ca:      	cmp	r2, #0x1
    14cc:      	strb	r6, [r1, r0]
    14ce:      	beq	0x141c <text+0x6c>      @ imm = #-0xb6
    14d0:      	adds	r6, r0, #0x1
    14d2:      	ldrb.w	lr, [r3, r6]
    14d6:      	cmp.w	lr, #0x0
    14da:      	it	eq
    14dc:      	moveq.w	lr, #0x20
    14e0:      	cmp	r2, #0x2
    14e2:      	strb.w	lr, [r1, r6]
    14e6:      	beq	0x141c <text+0x6c>      @ imm = #-0xce
    14e8:      	adds	r0, #0x2
    14ea:      	ldrb	r2, [r3, r0]
    14ec:      	cmp	r2, #0x0
    14ee:      	it	eq
    14f0:      	moveq	r2, #0x20
    14f2:      	strb	r2, [r1, r0]
    14f4:      	b	0x141c <text+0x6c>      @ imm = #-0xdc
    14f6:      	movw	r9, #0xcccd
    14fa:      	ldrd	r4, r5, [sp]
    14fe:      	mov.w	r11, #0x1
    1502:      	movt	r9, #0xcccc
    1506:      	sub.w	r10, r7, #0x5d
    150a:      	nop
    150c:      	lsrs	r0, r4, #0x1
    150e:      	orr.w	r0, r0, r5, lsl #31
    1512:      	adds.w	r1, r0, r5, lsr #1
    1516:      	adc	r1, r1, #0x0
    151a:      	umull	r2, r3, r1, r9
    151e:      	bic	r2, r3, #0x3
    1522:      	add.w	r2, r2, r3, lsr #2
    1526:      	subs	r1, r1, r2
    1528:      	subs	r1, r0, r1
    152a:      	umull	r0, lr, r1, r9
    152e:      	lsr.w	r3, r5, #0x1
    1532:      	add.w	r6, r0, r0, lsl #2
    1536:      	sbc	r2, r3, #0x0
    153a:      	sub.w	r6, r4, r6, lsl #1
    153e:      	mov	r3, r4
    1540:      	subs	r4, #0xa
    1542:      	orr	r12, r6, #0x30
    1546:      	add.w	r8, r10, r11
    154a:      	sbcs	r4, r5, #0x0
    154e:      	strb	r12, [r8, #-1]
    1552:      	blo	0x164a <text+0x29a>     @ imm = #0xf4
    1554:      	mov.w	r4, #0xcccccccc
    1558:      	mla	r1, r1, r4, lr
    155c:      	mla	r1, r2, r9, r1
    1560:      	lsrs	r2, r0, #0x1
    1562:      	orr.w	r2, r2, r1, lsl #31
    1566:      	adds.w	r1, r2, r1, lsr #1
    156a:      	adc	r1, r1, #0x0
    156e:      	umull	r2, r4, r1, r9
    1572:      	bic	r2, r4, #0x3
    1576:      	add.w	r2, r2, r4, lsr #2
    157a:      	subs	r1, r1, r2
    157c:      	and	r0, r0, #0x1
    1580:      	orr.w	r0, r0, r1, lsl #1
    1584:      	subs.w	r1, r3, #0x64
    1588:      	orr	r0, r0, #0x30
    158c:      	sbcs	r1, r5, #0x0
    1590:      	mov	r4, r10
    1592:      	strb.w	r0, [r10, r11]
    1596:      	blo	0x1654 <text+0x2a4>     @ imm = #0xba
    1598:      	mov	r6, r3
    159a:      	mov	r0, r3
    159c:      	mov	r1, r5
    159e:      	movs	r2, #0x64
    15a0:      	movs	r3, #0x0
    15a2:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x2f6
    15a6:      	lsrs	r2, r0, #0x1
    15a8:      	orr.w	r2, r2, r1, lsl #31
    15ac:      	adds.w	r1, r2, r1, lsr #1
    15b0:      	adc	r1, r1, #0x0
    15b4:      	umull	r2, r3, r1, r9
    15b8:      	bic	r2, r3, #0x3
    15bc:      	add.w	r2, r2, r3, lsr #2
    15c0:      	subs	r1, r1, r2
    15c2:      	and	r0, r0, #0x1
    15c6:      	orr.w	r0, r0, r1, lsl #1
    15ca:      	subs.w	r1, r6, #0x3e8
    15ce:      	orr	r0, r0, #0x30
    15d2:      	sbcs	r1, r5, #0x0
    15d6:      	strb.w	r0, [r8, #0x1]
    15da:      	blo	0x165c <text+0x2ac>     @ imm = #0x7e
    15dc:      	mov	r0, r6
    15de:      	mov	r1, r5
    15e0:      	mov.w	r2, #0x3e8
    15e4:      	movs	r3, #0x0
    15e6:      	mov	r10, r4
    15e8:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x2b0
    15ec:      	lsrs	r2, r0, #0x1
    15ee:      	orr.w	r2, r2, r1, lsl #31
    15f2:      	adds.w	r1, r2, r1, lsr #1
    15f6:      	adc	r1, r1, #0x0
    15fa:      	umull	r2, r3, r1, r9
    15fe:      	bic	r2, r3, #0x3
    1602:      	add.w	r2, r2, r3, lsr #2
    1606:      	subs	r1, r1, r2
    1608:      	and	r0, r0, #0x1
    160c:      	orr.w	r0, r0, r1, lsl #1
    1610:      	orr	r0, r0, #0x30
    1614:      	strb.w	r0, [r8, #0x2]
    1618:      	mov	r0, r6
    161a:      	mov	r1, r5
    161c:      	movw	r2, #0x2710
    1620:      	movs	r3, #0x0
    1622:      	bl	0x189c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x276
    1626:      	movw	r2, #0x270f
    162a:      	subs	r2, r2, r6
    162c:      	mov.w	r2, #0x0
    1630:      	sbcs	r2, r5
    1632:      	add.w	r11, r11, #0x4
    1636:      	mov	r4, r0
    1638:      	mov	r5, r1
    163a:      	blo.w	0x150c <text+0x15c>     @ imm = #-0x132
    163e:      	sub.w	r1, r11, #0x1
    1642:      	sub.w	r12, r11, #0x2
    1646:      	mov	r11, r1
    1648:      	b	0x1650 <text+0x2a0>     @ imm = #0x4
    164a:      	sub.w	r12, r11, #0x1
    164e:      	mov	r1, r11
    1650:      	mov	r4, r10
    1652:      	b	0x1666 <text+0x2b6>     @ imm = #0x10
    1654:      	add.w	r1, r11, #0x1
    1658:      	mov	r12, r11
    165a:      	b	0x1664 <text+0x2b4>     @ imm = #0x6
    165c:      	add.w	r1, r11, #0x2
    1660:      	add.w	r12, r11, #0x1
    1664:      	mov	r11, r1
    1666:      	and	lr, r1, #0x3
    166a:      	lsrs	r3, r1, #0x2
    166c:      	mov.w	r1, #0x0
    1670:      	beq	0x16aa <text+0x2fa>     @ imm = #0x36
    1672:      	sub.w	r6, r7, #0x75
    1676:      	add.w	r5, r12, r4
    167a:      	sub.w	r9, r1, r3, lsl #2
    167e:      	subs	r6, #0x3
    1680:      	subs	r5, #0x1
    1682:      	nop
    1684:      	adds	r4, r5, r1
    1686:      	ldrb	r3, [r5, r1]
    1688:      	ldrb	r0, [r4, #-2]
    168c:      	ldrb	r2, [r4, #-1]
    1690:      	ldrb	r4, [r4, #0x1]
    1692:      	subs	r1, #0x4
    1694:      	strb	r3, [r6, #4]!
    1698:      	cmp	r9, r1
    169a:      	strb	r4, [r6, #-1]
    169e:      	strb	r2, [r6, #0x1]
    16a0:      	strb	r0, [r6, #0x2]
    16a2:      	bne	0x1684 <text+0x2d4>     @ imm = #-0x22
    16a4:      	rsbs	r1, r1, #0
    16a6:      	sub.w	r4, r7, #0x5d
    16aa:      	cmp.w	lr, #0x0
    16ae:      	beq	0x16dc <text+0x32c>     @ imm = #0x2a
    16b0:      	sub.w	r0, r12, r1
    16b4:      	ldrb	r0, [r4, r0]
    16b6:      	sub.w	r3, r7, #0x75
    16ba:      	cmp.w	lr, #0x1
    16be:      	strb	r0, [r3, r1]
    16c0:      	beq	0x16dc <text+0x32c>     @ imm = #0x18
    16c2:      	adds	r0, r1, #0x1
    16c4:      	sub.w	r2, r12, r0
    16c8:      	ldrb	r2, [r4, r2]
    16ca:      	cmp.w	lr, #0x2
    16ce:      	strb	r2, [r3, r0]
    16d0:      	beq	0x16dc <text+0x32c>     @ imm = #0x8
    16d2:      	adds	r0, r1, #0x2
    16d4:      	sub.w	r1, r12, r0
    16d8:      	ldrb	r1, [r4, r1]
    16da:      	strb	r1, [r3, r0]
    16dc:      	sub.w	r0, r7, #0x75
    16e0:      	movs	r1, #0x0
    16e2:      	mov.w	r12, #0xffffffff
    16e6:      	strb.w	r1, [r0, r11]
    16ea:      	nop
    16ec:      	add.w	r1, r0, r12
    16f0:      	ldrb	r3, [r1, #0x1]
    16f2:      	cbz	r3, 0x170e <text+0x35e> @ imm = #0x18
    16f4:      	ldrb	r3, [r1, #0x2]
    16f6:      	cbz	r3, 0x171a <text+0x36a> @ imm = #0x20
    16f8:      	ldrb	r3, [r1, #0x3]
    16fa:      	cbz	r3, 0x1726 <text+0x376> @ imm = #0x28
    16fc:      	ldrb	r1, [r1, #0x4]
    16fe:      	add.w	r12, r12, #0x4
    1702:      	cmp	r1, #0x0
    1704:      	bne	0x16ec <text+0x33c>     @ imm = #-0x1c
    1706:      	cmp.w	r12, #0x0
    170a:      	bne	0x1730 <text+0x380>     @ imm = #0x22
    170c:      	b	0x1818 <text+0x468>     @ imm = #0x108
    170e:      	add.w	r12, r12, #0x1
    1712:      	cmp.w	r12, #0x0
    1716:      	bne	0x1730 <text+0x380>     @ imm = #0x16
    1718:      	b	0x1818 <text+0x468>     @ imm = #0xfc
    171a:      	add.w	r12, r12, #0x2
    171e:      	cmp.w	r12, #0x0
    1722:      	bne	0x1730 <text+0x380>     @ imm = #0xa
    1724:      	b	0x1818 <text+0x468>     @ imm = #0xf0
    1726:      	add.w	r12, r12, #0x3
    172a:      	cmp.w	r12, #0x0
    172e:      	beq	0x1818 <text+0x468>     @ imm = #0xe6
    1730:      	movs	r2, #0x0
    1732:      	add.w	lr, r4, #0x1
    1736:      	sub.w	r9, r7, #0x75
    173a:      	movs	r3, #0x40
    173c:      	mov.w	r11, #0x0
    1740:      	b	0x1762 <text+0x3b2>     @ imm = #0x1e
    1742:      	nop
    1744:      	strb.w	r2, [r4, r8]
    1748:      	movs	r0, #0x4
    174a:      	subs.w	r12, r12, r8
    174e:      	mov	r1, r4
    1750:      	bkpt	#0xab
    1752:      	sbc	r11, r11, #0x0
    1756:      	rsbs.w	r0, r12, #0x0
    175a:      	sbcs.w	r0, r2, r11
    175e:      	add	r9, r8
    1760:      	bge	0x1818 <text+0x468>     @ imm = #0xb4
    1762:      	mov.w	r8, #0x40
    1766:      	cmp.w	r12, #0x40
    176a:      	it	lo
    176c:      	movlo	r8, r12
    176e:      	cmp.w	r11, #0x0
    1772:      	it	ne
    1774:      	movne	r8, r3
    1776:      	sub.w	r0, r8, #0x1
    177a:      	cmp	r0, #0x3
    177c:      	bhs	0x1788 <text+0x3d8>     @ imm = #0x8
    177e:      	movs	r0, #0x0
    1780:      	ands	r1, r8, #0x3
    1784:      	bne	0x17e2 <text+0x432>     @ imm = #0x5a
    1786:      	b	0x1744 <text+0x394>     @ imm = #-0x46
    1788:      	bic	r0, r8, #0x3
    178c:      	rsb.w	r10, r0, #0x0
    1790:      	add.w	r5, r9, #0x1
    1794:      	mvn	r1, #0x3
    1798:      	adds	r4, r5, r1
    179a:      	ldrb	r2, [r4, #0x3]
    179c:      	ldrb	r3, [r4, #0x4]
    179e:      	ldrb	r6, [r4, #0x5]
    17a0:      	cmp	r2, #0x0
    17a2:      	ldrb	r4, [r4, #0x6]
    17a4:      	it	eq
    17a6:      	moveq	r2, #0x20
    17a8:      	add.w	r0, lr, r1
    17ac:      	cmp	r3, #0x0
    17ae:      	strb	r2, [r0, #0x3]
    17b0:      	it	eq
    17b2:      	moveq	r3, #0x20
    17b4:      	cmp	r6, #0x0
    17b6:      	add.w	r1, r1, #0x4
    17ba:      	strb	r3, [r0, #0x4]
    17bc:      	it	eq
    17be:      	moveq	r6, #0x20
    17c0:      	cmp	r4, #0x0
    17c2:      	add.w	r2, r10, r1
    17c6:      	strb	r6, [r0, #0x5]
    17c8:      	it	eq
    17ca:      	moveq	r4, #0x20
    17cc:      	adds	r2, #0x4
    17ce:      	strb	r4, [r0, #0x6]
    17d0:      	bne	0x1798 <text+0x3e8>     @ imm = #-0x3c
    17d2:      	adds	r0, r1, #0x4
    17d4:      	sub.w	r4, r7, #0x5d
    17d8:      	movs	r2, #0x0
    17da:      	movs	r3, #0x40
    17dc:      	ands	r1, r8, #0x3
    17e0:      	beq	0x1744 <text+0x394>     @ imm = #-0xa0
    17e2:      	ldrb.w	r5, [r9, r0]
    17e6:      	cmp	r5, #0x0
    17e8:      	it	eq
    17ea:      	moveq	r5, #0x20
    17ec:      	cmp	r1, #0x1
    17ee:      	strb	r5, [r4, r0]
    17f0:      	beq	0x1744 <text+0x394>     @ imm = #-0xb0
    17f2:      	add.w	r10, r0, #0x1
    17f6:      	ldrb.w	r5, [r9, r10]
    17fa:      	cmp	r5, #0x0
    17fc:      	it	eq
    17fe:      	moveq	r5, #0x20
    1800:      	cmp	r1, #0x2
    1802:      	strb.w	r5, [r4, r10]
    1806:      	beq	0x1744 <text+0x394>     @ imm = #-0xc6
    1808:      	adds	r0, #0x2
    180a:      	ldrb.w	r1, [r9, r0]
    180e:      	cmp	r1, #0x0
    1810:      	it	eq
    1812:      	moveq	r1, #0x20
    1814:      	strb	r1, [r4, r0]
    1816:      	b	0x1744 <text+0x394>     @ imm = #-0xd6
    1818:      	add	sp, #0x64
    181a:      	pop.w	{r8, r9, r10, r11}
    181e:      	pop	{r4, r5, r6, r7, pc}

00001820 <compiler_rt.memset>:
    1820:      	cmp	r2, #0x0
    1822:      	it	eq
    1824:      	bxeq	lr
    1826:      	push	{r7, lr}
    1828:      	mov	r7, sp
    182a:      	ands	lr, r2, #0x3
    182e:      	mov	r3, r2
    1830:      	mov	r12, r0
    1832:      	beq	0x1856 <compiler_rt.memset+0x36> @ imm = #0x20
    1834:      	mov	r12, r0
    1836:      	cmp.w	lr, #0x1
    183a:      	strb	r1, [r12], #1
    183e:      	bne	0x1848 <compiler_rt.memset+0x28> @ imm = #0x6
    1840:      	subs	r3, r2, #0x1
    1842:      	cmp	r2, #0x4
    1844:      	bhs	0x185a <compiler_rt.memset+0x3a> @ imm = #0x12
    1846:      	b	0x186e <compiler_rt.memset+0x4e> @ imm = #0x24
    1848:      	cmp.w	lr, #0x2
    184c:      	strb	r1, [r0, #0x1]
    184e:      	bne	0x1874 <compiler_rt.memset+0x54> @ imm = #0x22
    1850:      	subs	r3, r2, #0x2
    1852:      	add.w	r12, r0, #0x2
    1856:      	cmp	r2, #0x4
    1858:      	blo	0x186e <compiler_rt.memset+0x4e> @ imm = #0x12
    185a:      	sub.w	r2, r12, #0x4
    185e:      	nop
    1860:      	strb	r1, [r2, #4]!
    1864:      	subs	r3, #0x4
    1866:      	strb	r1, [r2, #0x1]
    1868:      	strb	r1, [r2, #0x2]
    186a:      	strb	r1, [r2, #0x3]
    186c:      	bne	0x1860 <compiler_rt.memset+0x40> @ imm = #-0x10
    186e:      	pop.w	{r7, lr}
    1872:      	bx	lr
    1874:      	subs	r3, r2, #0x3
    1876:      	add.w	r12, r0, #0x3
    187a:      	strb	r1, [r0, #0x2]
    187c:      	cmp	r2, #0x4
    187e:      	bhs	0x185a <compiler_rt.memset+0x3a> @ imm = #-0x28
    1880:      	b	0x186e <compiler_rt.memset+0x4e> @ imm = #-0x16
    1882:      	bmi	0x182e <compiler_rt.memset+0xe> @ imm = #-0x58

00001884 <compiler_rt.arm.__aeabi_unwind_cpp_pr0>:
    1884:      	push	{r7, lr}
    1886:      	mov	r7, sp
    1888:      	pop	{r7, pc}
    188a:      	bmi	0x1836 <compiler_rt.memset+0x16> @ imm = #-0x58

0000188c <compiler_rt.arm.__aeabi_memclr>:
    188c:      	push	{r7, lr}
    188e:      	mov	r7, sp
    1890:      	mov	r2, r1
    1892:      	movs	r1, #0x0
    1894:      	pop.w	{r7, lr}
    1898:      	b.w	0x1820 <compiler_rt.memset> @ imm = #-0x7c

0000189c <compiler_rt.arm.__aeabi_uldivmod>:
    189c:      	push	{r4, lr}
    189e:      	sub	sp, #0x10
    18a0:      	add	r4, sp, #0x8
    18a2:      	str	r4, [sp]
    18a4:      	bl	0x18b0 <compiler_rt.int.__udivmoddi4> @ imm = #0x8
    18a8:      	ldr	r2, [sp, #0x8]
    18aa:      	ldr	r3, [sp, #0xc]
    18ac:      	add	sp, #0x10
    18ae:      	pop	{r4, pc}

000018b0 <compiler_rt.int.__udivmoddi4>:
    18b0:      	push	{r4, r5, r6, r7, lr}
    18b2:      	add	r7, sp, #0xc
    18b4:      	push.w	{r8, r9, r10, r11}
    18b8:      	sub	sp, #0x20
    18ba:      	mov	r5, r2
    18bc:      	ldr	r6, [r7, #0x8]
    18be:      	subs	r2, r0, r2
    18c0:      	sbcs.w	r2, r1, r3
    18c4:      	bhs	0x18dc <compiler_rt.int.__udivmoddi4+0x2c> @ imm = #0x14
    18c6:      	cmp	r6, #0x0
    18c8:      	it	ne
    18ca:      	strdne	r0, r1, [r6]
    18ce:      	movs	r0, #0x0
    18d0:      	movs	r1, #0x0
    18d2:      	add	sp, #0x20
    18d4:      	pop.w	{r8, r9, r10, r11}
    18d8:      	pop	{r4, r5, r6, r7, pc}
    18da:      	nop
    18dc:      	cmp	r3, #0x0
    18de:      	beq.w	0x19e8 <compiler_rt.int.__udivmoddi4+0x138> @ imm = #0x106
    18e2:      	clz	r2, r3
    18e6:      	cmp	r2, #0x0
    18e8:      	beq.w	0x1a14 <compiler_rt.int.__udivmoddi4+0x164> @ imm = #0x128
    18ec:      	rsbs	r6, r2, #0
    18ee:      	and	r4, r6, #0x1f
    18f2:      	lsl.w	r12, r3, r2
    18f6:      	lsr.w	r6, r5, r4
    18fa:      	orr.w	r8, r6, r12
    18fe:      	lsl.w	r2, r1, r2
    1902:      	lsr.w	r6, r0, r4
    1906:      	clz	lr, r8
    190a:      	orrs	r2, r6
    190c:      	ands	r12, lr, #0x1f
    1910:      	lsr.w	r6, r1, r4
    1914:      	str	r5, [sp, #0x10]
    1916:      	str	r0, [sp, #0x4]
    1918:      	beq	0x1934 <compiler_rt.int.__udivmoddi4+0x84> @ imm = #0x18
    191a:      	lsl.w	r4, r6, r12
    191e:      	rsb.w	r6, lr, #0x0
    1922:      	and	r6, r6, #0x1f
    1926:      	lsr.w	r6, r2, r6
    192a:      	lsl.w	r8, r8, r12
    192e:      	orrs	r6, r4
    1930:      	lsl.w	r2, r2, r12
    1934:      	lsr.w	lr, r8, #0x10
    1938:      	udiv	r4, r6, lr
    193c:      	strd	r3, r1, [sp, #8]
    1940:      	mls	r9, r4, lr, r6
    1944:      	uxth.w	r12, r8
    1948:      	lsr.w	r11, r2, #0x10
    194c:      	uxth	r3, r2
    194e:      	mov	r0, r6
    1950:      	mov.w	r10, #0x0
    1954:      	str.w	r8, [sp]
    1958:      	b	0x196c <compiler_rt.int.__udivmoddi4+0xbc> @ imm = #0x10
    195a:      	nop
    195c:      	subs	r6, r4, #0x4
    195e:      	add.w	r9, r2, lr
    1962:      	cmp.w	r10, r9, lsr #16
    1966:      	mov	r4, r6
    1968:      	bne.w	0x1ba6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x23a
    196c:      	cmp.w	r10, r4, lsr #16
    1970:      	bne	0x1980 <compiler_rt.int.__udivmoddi4+0xd0> @ imm = #0xc
    1972:      	mul	r2, r4, r12
    1976:      	orr.w	r6, r11, r9, lsl #16
    197a:      	cmp	r2, r6
    197c:      	bls.w	0x1ba4 <compiler_rt.int.__udivmoddi4+0x2f4> @ imm = #0x224
    1980:      	add.w	r2, r9, lr
    1984:      	cmp.w	r10, r2, lsr #16
    1988:      	sub.w	r6, r4, #0x1
    198c:      	bne.w	0x1ba6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x216
    1990:      	cmp.w	r10, r6, lsr #16
    1994:      	bne	0x19a4 <compiler_rt.int.__udivmoddi4+0xf4> @ imm = #0xc
    1996:      	mul	r9, r6, r12
    199a:      	orr.w	r8, r11, r2, lsl #16
    199e:      	cmp	r9, r8
    19a0:      	bls.w	0x1ba6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x202
    19a4:      	add	r2, lr
    19a6:      	cmp.w	r10, r2, lsr #16
    19aa:      	sub.w	r6, r4, #0x2
    19ae:      	bne.w	0x1ba6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1f4
    19b2:      	cmp.w	r10, r6, lsr #16
    19b6:      	bne	0x19c6 <compiler_rt.int.__udivmoddi4+0x116> @ imm = #0xc
    19b8:      	mul	r8, r6, r12
    19bc:      	orr.w	r5, r11, r2, lsl #16
    19c0:      	cmp	r8, r5
    19c2:      	bls.w	0x1ba6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1e0
    19c6:      	add	r2, lr
    19c8:      	cmp.w	r10, r2, lsr #16
    19cc:      	sub.w	r6, r4, #0x3
    19d0:      	bne.w	0x1ba6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1d2
    19d4:      	cmp.w	r10, r6, lsr #16
    19d8:      	bne	0x195c <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x80
    19da:      	mul	r5, r6, r12
    19de:      	orr.w	r1, r11, r2, lsl #16
    19e2:      	cmp	r5, r1
    19e4:      	bhi	0x195c <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x8c
    19e6:      	b	0x1ba6 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1bc
    19e8:      	cmp	r1, r5
    19ea:      	clz	lr, r5
    19ee:      	bhs	0x1a2c <compiler_rt.int.__udivmoddi4+0x17c> @ imm = #0x3a
    19f0:      	cmp.w	lr, #0x0
    19f4:      	beq.w	0x1afc <compiler_rt.int.__udivmoddi4+0x24c> @ imm = #0x104
    19f8:      	rsb.w	r2, lr, #0x0
    19fc:      	and	r2, r2, #0x1f
    1a00:      	lsl.w	r1, r1, lr
    1a04:      	lsr.w	r2, r0, r2
    1a08:      	lsl.w	r5, r5, lr
    1a0c:      	orrs	r2, r1
    1a0e:      	lsl.w	r0, r0, lr
    1a12:      	b	0x1afe <compiler_rt.int.__udivmoddi4+0x24e> @ imm = #0xe8
    1a14:      	cbz	r6, 0x1a1e <compiler_rt.int.__udivmoddi4+0x16e> @ imm = #0x6
    1a16:      	subs	r0, r0, r5
    1a18:      	sbcs	r1, r3
    1a1a:      	strd	r0, r1, [r6]
    1a1e:      	movs	r1, #0x0
    1a20:      	movs	r0, #0x1
    1a22:      	add	sp, #0x20
    1a24:      	pop.w	{r8, r9, r10, r11}
    1a28:      	pop	{r4, r5, r6, r7, pc}
    1a2a:      	nop
    1a2c:      	udiv	r2, r1, r5
    1a30:      	cmp.w	lr, #0x0
    1a34:      	mls	r8, r2, r5, r1
    1a38:      	mov	r1, r2
    1a3a:      	beq	0x1a58 <compiler_rt.int.__udivmoddi4+0x1a8> @ imm = #0x1a
    1a3c:      	rsb.w	r3, lr, #0x0
    1a40:      	and	r3, r3, #0x1f
    1a44:      	lsl.w	r2, r8, lr
    1a48:      	lsr.w	r3, r0, r3
    1a4c:      	lsl.w	r5, r5, lr
    1a50:      	orr.w	r8, r2, r3
    1a54:      	lsl.w	r0, r0, lr
    1a58:      	lsrs	r4, r5, #0x10
    1a5a:      	str	r5, [sp, #0x10]
    1a5c:      	uxth.w	r12, r5
    1a60:      	udiv	r5, r8, r4
    1a64:      	lsr.w	r10, r0, #0x10
    1a68:      	mls	r6, r5, r4, r8
    1a6c:      	uxth.w	r9, r0
    1a70:      	movs	r3, #0x0
    1a72:      	b	0x1a82 <compiler_rt.int.__udivmoddi4+0x1d2> @ imm = #0xc
    1a74:      	subs	r0, r5, #0x4
    1a76:      	adds	r6, r2, r4
    1a78:      	cmp.w	r3, r6, lsr #16
    1a7c:      	mov	r5, r0
    1a7e:      	bne.w	0x1cbe <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x23c
    1a82:      	cmp.w	r3, r5, lsr #16
    1a86:      	bne	0x1a96 <compiler_rt.int.__udivmoddi4+0x1e6> @ imm = #0xc
    1a88:      	mul	r0, r5, r12
    1a8c:      	orr.w	r2, r10, r6, lsl #16
    1a90:      	cmp	r0, r2
    1a92:      	bls.w	0x1cbc <compiler_rt.int.__udivmoddi4+0x40c> @ imm = #0x226
    1a96:      	adds	r2, r6, r4
    1a98:      	cmp.w	r3, r2, lsr #16
    1a9c:      	sub.w	r0, r5, #0x1
    1aa0:      	bne.w	0x1cbe <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x21a
    1aa4:      	cmp.w	r3, r0, lsr #16
    1aa8:      	bne	0x1ab8 <compiler_rt.int.__udivmoddi4+0x208> @ imm = #0xc
    1aaa:      	mul	r11, r0, r12
    1aae:      	orr.w	r6, r10, r2, lsl #16
    1ab2:      	cmp	r11, r6
    1ab4:      	bls.w	0x1cbe <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x206
    1ab8:      	add	r2, r4
    1aba:      	cmp.w	r3, r2, lsr #16
    1abe:      	sub.w	r0, r5, #0x2
    1ac2:      	bne.w	0x1cbe <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1f8
    1ac6:      	cmp.w	r3, r0, lsr #16
    1aca:      	bne	0x1ada <compiler_rt.int.__udivmoddi4+0x22a> @ imm = #0xc
    1acc:      	mul	r11, r0, r12
    1ad0:      	orr.w	r6, r10, r2, lsl #16
    1ad4:      	cmp	r11, r6
    1ad6:      	bls.w	0x1cbe <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1e4
    1ada:      	add	r2, r4
    1adc:      	cmp.w	r3, r2, lsr #16
    1ae0:      	sub.w	r0, r5, #0x3
    1ae4:      	bne.w	0x1cbe <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1d6
    1ae8:      	cmp.w	r3, r0, lsr #16
    1aec:      	bne	0x1a74 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x7c
    1aee:      	mul	r11, r0, r12
    1af2:      	orr.w	r6, r10, r2, lsl #16
    1af6:      	cmp	r11, r6
    1af8:      	bhi	0x1a74 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x88
    1afa:      	b	0x1cbe <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1c0
    1afc:      	mov	r2, r1
    1afe:      	lsrs	r4, r5, #0x10
    1b00:      	udiv	r6, r2, r4
    1b04:      	mov	r11, r5
    1b06:      	uxth.w	r9, r5
    1b0a:      	mls	r5, r6, r4, r2
    1b0e:      	lsr.w	r8, r0, #0x10
    1b12:      	uxth.w	r12, r0
    1b16:      	mov	r1, r2
    1b18:      	movs	r3, #0x0
    1b1a:      	b	0x1b2a <compiler_rt.int.__udivmoddi4+0x27a> @ imm = #0xc
    1b1c:      	subs	r0, r6, #0x4
    1b1e:      	adds	r5, r2, r4
    1b20:      	cmp.w	r3, r5, lsr #16
    1b24:      	mov	r6, r0
    1b26:      	bne.w	0x1d56 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x22c
    1b2a:      	cmp.w	r3, r6, lsr #16
    1b2e:      	bne	0x1b3e <compiler_rt.int.__udivmoddi4+0x28e> @ imm = #0xc
    1b30:      	mul	r0, r6, r9
    1b34:      	orr.w	r2, r8, r5, lsl #16
    1b38:      	cmp	r0, r2
    1b3a:      	bls.w	0x1d54 <compiler_rt.int.__udivmoddi4+0x4a4> @ imm = #0x216
    1b3e:      	adds	r2, r5, r4
    1b40:      	cmp.w	r3, r2, lsr #16
    1b44:      	sub.w	r0, r6, #0x1
    1b48:      	bne.w	0x1d56 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x20a
    1b4c:      	cmp.w	r3, r0, lsr #16
    1b50:      	bne	0x1b60 <compiler_rt.int.__udivmoddi4+0x2b0> @ imm = #0xc
    1b52:      	mul	r10, r0, r9
    1b56:      	orr.w	r5, r8, r2, lsl #16
    1b5a:      	cmp	r10, r5
    1b5c:      	bls.w	0x1d56 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1f6
    1b60:      	add	r2, r4
    1b62:      	cmp.w	r3, r2, lsr #16
    1b66:      	sub.w	r0, r6, #0x2
    1b6a:      	bne.w	0x1d56 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1e8
    1b6e:      	cmp.w	r3, r0, lsr #16
    1b72:      	bne	0x1b82 <compiler_rt.int.__udivmoddi4+0x2d2> @ imm = #0xc
    1b74:      	mul	r10, r0, r9
    1b78:      	orr.w	r5, r8, r2, lsl #16
    1b7c:      	cmp	r10, r5
    1b7e:      	bls.w	0x1d56 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1d4
    1b82:      	add	r2, r4
    1b84:      	cmp.w	r3, r2, lsr #16
    1b88:      	sub.w	r0, r6, #0x3
    1b8c:      	bne.w	0x1d56 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1c6
    1b90:      	cmp.w	r3, r0, lsr #16
    1b94:      	bne	0x1b1c <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x7c
    1b96:      	mul	r10, r0, r9
    1b9a:      	orr.w	r5, r8, r2, lsl #16
    1b9e:      	cmp	r10, r5
    1ba0:      	bhi	0x1b1c <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x88
    1ba2:      	b	0x1d56 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1b0
    1ba4:      	mov	r6, r4
    1ba6:      	orr.w	r2, r11, r0, lsl #16
    1baa:      	ldr	r0, [sp]
    1bac:      	ldr.w	r9, [sp, #0x4]
    1bb0:      	mls	r2, r6, r0, r2
    1bb4:      	mov.w	r8, #0x0
    1bb8:      	udiv	r4, r2, lr
    1bbc:      	mls	r2, r4, lr, r2
    1bc0:      	b	0x1bd0 <compiler_rt.int.__udivmoddi4+0x320> @ imm = #0xc
    1bc2:      	nop
    1bc4:      	subs	r4, #0x4
    1bc6:      	add	r2, lr
    1bc8:      	cmp.w	r2, #0x10000
    1bcc:      	mov	r5, r4
    1bce:      	bhs	0x1c42 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x70
    1bd0:      	cmp.w	r8, r4, lsr #16
    1bd4:      	bne	0x1be2 <compiler_rt.int.__udivmoddi4+0x332> @ imm = #0xa
    1bd6:      	mul	r1, r4, r12
    1bda:      	orr.w	r5, r3, r2, lsl #16
    1bde:      	cmp	r1, r5
    1be0:      	bls	0x1c40 <compiler_rt.int.__udivmoddi4+0x390> @ imm = #0x5c
    1be2:      	add	r2, lr
    1be4:      	cmp.w	r8, r2, lsr #16
    1be8:      	sub.w	r5, r4, #0x1
    1bec:      	bne	0x1c42 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x52
    1bee:      	cmp.w	r8, r5, lsr #16
    1bf2:      	bne	0x1c00 <compiler_rt.int.__udivmoddi4+0x350> @ imm = #0xa
    1bf4:      	mul	r1, r5, r12
    1bf8:      	orr.w	r0, r3, r2, lsl #16
    1bfc:      	cmp	r1, r0
    1bfe:      	bls	0x1c42 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x40
    1c00:      	add	r2, lr
    1c02:      	cmp.w	r8, r2, lsr #16
    1c06:      	sub.w	r5, r4, #0x2
    1c0a:      	bne	0x1c42 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x34
    1c0c:      	cmp.w	r8, r5, lsr #16
    1c10:      	bne	0x1c1e <compiler_rt.int.__udivmoddi4+0x36e> @ imm = #0xa
    1c12:      	mul	r0, r5, r12
    1c16:      	orr.w	r1, r3, r2, lsl #16
    1c1a:      	cmp	r0, r1
    1c1c:      	bls	0x1c42 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x22
    1c1e:      	add	r2, lr
    1c20:      	cmp.w	r8, r2, lsr #16
    1c24:      	sub.w	r5, r4, #0x3
    1c28:      	bne	0x1c42 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x16
    1c2a:      	cmp.w	r8, r5, lsr #16
    1c2e:      	bne	0x1bc4 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x6e
    1c30:      	mul	r0, r5, r12
    1c34:      	orr.w	r1, r3, r2, lsl #16
    1c38:      	cmp	r0, r1
    1c3a:      	bhi	0x1bc4 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x7a
    1c3c:      	b	0x1c42 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x2
    1c3e:      	nop
    1c40:      	mov	r5, r4
    1c42:      	add.w	r0, r5, r6, lsl #16
    1c46:      	ldr	r2, [sp, #0x10]
    1c48:      	ldr	r6, [sp, #0x8]
    1c4a:      	umull	r4, r1, r2, r0
    1c4e:      	mov	r8, r0
    1c50:      	umull	r0, r3, r6, r0
    1c54:      	adds	r5, r0, r1
    1c56:      	mov.w	r12, #0x0
    1c5a:      	adc	r0, r12, #0x0
    1c5e:      	orrs.w	r1, r3, r0
    1c62:      	ldr	r3, [r7, #0x8]
    1c64:      	ldr.w	lr, [sp, #0xc]
    1c68:      	strb.w	r0, [sp, #0x14]
    1c6c:      	bne	0x1c78 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x8
    1c6e:      	cmp	r5, lr
    1c70:      	bhi	0x1c78 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x4
    1c72:      	bne	0x1c8e <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x18
    1c74:      	cmp	r4, r9
    1c76:      	bls	0x1c8e <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x14
    1c78:      	subs	r4, r4, r2
    1c7a:      	adc	r0, r12, #0x0
    1c7e:      	eor	r0, r0, #0x1
    1c82:      	strb.w	r0, [sp, #0x18]
    1c86:      	add	r0, r6
    1c88:      	sub.w	r8, r8, #0x1
    1c8c:      	subs	r5, r5, r0
    1c8e:      	cbz	r3, 0x1cae <compiler_rt.int.__udivmoddi4+0x3fe> @ imm = #0x1c
    1c90:      	subs.w	r0, r9, r4
    1c94:      	mov.w	r1, #0x0
    1c98:      	adc	r1, r1, #0x0
    1c9c:      	eor	r1, r1, #0x1
    1ca0:      	strb.w	r1, [sp, #0x1c]
    1ca4:      	add	r1, r5
    1ca6:      	sub.w	r1, lr, r1
    1caa:      	strd	r0, r1, [r3]
    1cae:      	movs	r1, #0x0
    1cb0:      	mov	r0, r8
    1cb2:      	add	sp, #0x20
    1cb4:      	pop.w	{r8, r9, r10, r11}
    1cb8:      	pop	{r4, r5, r6, r7, pc}
    1cba:      	nop
    1cbc:      	mov	r0, r5
    1cbe:      	ldr	r3, [sp, #0x10]
    1cc0:      	orr.w	r2, r10, r8, lsl #16
    1cc4:      	mls	r8, r0, r3, r2
    1cc8:      	mov.w	r10, #0x0
    1ccc:      	udiv	r3, r8, r4
    1cd0:      	mls	r5, r3, r4, r8
    1cd4:      	b	0x1ce6 <compiler_rt.int.__udivmoddi4+0x436> @ imm = #0xe
    1cd6:      	nop
    1cd8:      	subs	r3, #0x4
    1cda:      	adds	r5, r2, r4
    1cdc:      	cmp.w	r5, #0x10000
    1ce0:      	mov	r6, r3
    1ce2:      	bhs.w	0x1dea <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x104
    1ce6:      	cmp.w	r10, r3, lsr #16
    1cea:      	bne	0x1cf8 <compiler_rt.int.__udivmoddi4+0x448> @ imm = #0xa
    1cec:      	mul	r2, r3, r12
    1cf0:      	orr.w	r6, r9, r5, lsl #16
    1cf4:      	cmp	r2, r6
    1cf6:      	bls	0x1de8 <compiler_rt.int.__udivmoddi4+0x538> @ imm = #0xee
    1cf8:      	adds	r2, r5, r4
    1cfa:      	cmp.w	r10, r2, lsr #16
    1cfe:      	sub.w	r6, r3, #0x1
    1d02:      	bne	0x1dea <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xe4
    1d04:      	cmp.w	r10, r6, lsr #16
    1d08:      	bne	0x1d16 <compiler_rt.int.__udivmoddi4+0x466> @ imm = #0xa
    1d0a:      	mul	r11, r6, r12
    1d0e:      	orr.w	r5, r9, r2, lsl #16
    1d12:      	cmp	r11, r5
    1d14:      	bls	0x1dea <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xd2
    1d16:      	add	r2, r4
    1d18:      	cmp.w	r10, r2, lsr #16
    1d1c:      	sub.w	r6, r3, #0x2
    1d20:      	bne	0x1dea <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xc6
    1d22:      	cmp.w	r10, r6, lsr #16
    1d26:      	bne	0x1d34 <compiler_rt.int.__udivmoddi4+0x484> @ imm = #0xa
    1d28:      	mul	r11, r6, r12
    1d2c:      	orr.w	r5, r9, r2, lsl #16
    1d30:      	cmp	r11, r5
    1d32:      	bls	0x1dea <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xb4
    1d34:      	add	r2, r4
    1d36:      	cmp.w	r10, r2, lsr #16
    1d3a:      	sub.w	r6, r3, #0x3
    1d3e:      	bne	0x1dea <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xa8
    1d40:      	cmp.w	r10, r6, lsr #16
    1d44:      	bne	0x1cd8 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x70
    1d46:      	mul	r11, r6, r12
    1d4a:      	orr.w	r5, r9, r2, lsl #16
    1d4e:      	cmp	r11, r5
    1d50:      	bhi	0x1cd8 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x7c
    1d52:      	b	0x1dea <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x94
    1d54:      	mov	r0, r6
    1d56:      	orr.w	r1, r8, r1, lsl #16
    1d5a:      	mls	r8, r0, r11, r1
    1d5e:      	mov.w	r10, #0x0
    1d62:      	udiv	r1, r8, r4
    1d66:      	mls	r5, r1, r4, r8
    1d6a:      	b	0x1d78 <compiler_rt.int.__udivmoddi4+0x4c8> @ imm = #0xa
    1d6c:      	subs	r1, #0x4
    1d6e:      	adds	r5, r2, r4
    1d70:      	cmp.w	r5, #0x10000
    1d74:      	mov	r6, r1
    1d76:      	bhs	0x1dfe <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x84
    1d78:      	cmp.w	r10, r1, lsr #16
    1d7c:      	bne	0x1d8a <compiler_rt.int.__udivmoddi4+0x4da> @ imm = #0xa
    1d7e:      	mul	r2, r1, r9
    1d82:      	orr.w	r6, r12, r5, lsl #16
    1d86:      	cmp	r2, r6
    1d88:      	bls	0x1dfc <compiler_rt.int.__udivmoddi4+0x54c> @ imm = #0x70
    1d8a:      	adds	r2, r5, r4
    1d8c:      	cmp.w	r10, r2, lsr #16
    1d90:      	sub.w	r6, r1, #0x1
    1d94:      	bne	0x1dfe <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x66
    1d96:      	cmp.w	r10, r6, lsr #16
    1d9a:      	bne	0x1da8 <compiler_rt.int.__udivmoddi4+0x4f8> @ imm = #0xa
    1d9c:      	mul	r5, r6, r9
    1da0:      	orr.w	r3, r12, r2, lsl #16
    1da4:      	cmp	r5, r3
    1da6:      	bls	0x1dfe <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x54
    1da8:      	add	r2, r4
    1daa:      	cmp.w	r10, r2, lsr #16
    1dae:      	sub.w	r6, r1, #0x2
    1db2:      	bne	0x1dfe <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x48
    1db4:      	cmp.w	r10, r6, lsr #16
    1db8:      	bne	0x1dc6 <compiler_rt.int.__udivmoddi4+0x516> @ imm = #0xa
    1dba:      	mul	r3, r6, r9
    1dbe:      	orr.w	r5, r12, r2, lsl #16
    1dc2:      	cmp	r3, r5
    1dc4:      	bls	0x1dfe <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x36
    1dc6:      	add	r2, r4
    1dc8:      	cmp.w	r10, r2, lsr #16
    1dcc:      	sub.w	r6, r1, #0x3
    1dd0:      	bne	0x1dfe <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x2a
    1dd2:      	cmp.w	r10, r6, lsr #16
    1dd6:      	bne	0x1d6c <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x6e
    1dd8:      	mul	r3, r6, r9
    1ddc:      	orr.w	r5, r12, r2, lsl #16
    1de0:      	cmp	r3, r5
    1de2:      	bhi	0x1d6c <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x7a
    1de4:      	b	0x1dfe <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x16
    1de6:      	nop
    1de8:      	mov	r6, r3
    1dea:      	ldr	r3, [sp, #0x10]
    1dec:      	orr.w	r2, r9, r8, lsl #16
    1df0:      	mls	r2, r6, r3, r2
    1df4:      	lsr.w	r2, r2, lr
    1df8:      	b	0x1e0c <compiler_rt.int.__udivmoddi4+0x55c> @ imm = #0x10
    1dfa:      	nop
    1dfc:      	mov	r6, r1
    1dfe:      	orr.w	r1, r12, r8, lsl #16
    1e02:      	mls	r1, r6, r11, r1
    1e06:      	lsr.w	r2, r1, lr
    1e0a:      	movs	r1, #0x0
    1e0c:      	ldr	r5, [r7, #0x8]
    1e0e:      	add.w	r0, r6, r0, lsl #16
    1e12:      	cmp	r5, #0x0
    1e14:      	itt	ne
    1e16:      	movne	r3, #0x0
    1e18:      	strdne	r2, r3, [r5]
    1e1c:      	add	sp, #0x20
    1e1e:      	pop.w	{r8, r9, r10, r11}
    1e22:      	pop	{r4, r5, r6, r7, pc}
    1e24:      	bmi	0x1dd0 <compiler_rt.int.__udivmoddi4+0x520> @ imm = #-0x58
    1e26:      	bmi	0x1dd2 <compiler_rt.int.__udivmoddi4+0x522> @ imm = #-0x58
    1e28:      	bmi	0x1dd4 <compiler_rt.int.__udivmoddi4+0x524> @ imm = #-0x58
    1e2a:      	bmi	0x1dd6 <compiler_rt.int.__udivmoddi4+0x526> @ imm = #-0x58
    1e2c:      	bmi	0x1dd8 <compiler_rt.int.__udivmoddi4+0x528> @ imm = #-0x58
    1e2e:      	bmi	0x1dda <compiler_rt.int.__udivmoddi4+0x52a> @ imm = #-0x58

00001e30 <.L.str.1>:
    1e30: 00 00 00 00 10 00 00 00         ........
    1e38: 69 6e 74 65 67 65 72 20         integer 
    1e40: 6f 76 65 72 66 6c 6f 77         overflow
    1e48: 00 00 00 00 d4 d4 d4 d4         ........

00001e50 <.L.str.2>:
    1e50: 00 00 00 00 13 00 00 00         ........
    1e58: 69 6e 64 65 78 20 6f 75         index ou
    1e60: 74 20 6f 66 20 62 6f 75         t of bou
    1e68: 6e 64 73 00                     nds.

00001e6c <.L.str.4>:
    1e6c: 00 00 00 00 00 00 00 00         ........
    1e74: 00 00 00 00 d4 d4 d4 d4         ........
    1e7c: d4 d4 d4 d4                     ....

00001e80 <.L.str.5>:
    1e80: 00 00 00 00 0b 00 00 00         ........
    1e88: 66 69 72 20 72 65 73 75         fir resu
    1e90: 6c 74 3d 00 00 00 00 00         lt=.....
    1e98: 07 00 00 00 20 74 69 63         .... tic
    1ea0: 6b 73 3d 00 6f 75 74 20         ks=.out 
    1ea8: 6f 66 20 6d 65 6d 6f 72         of memor
    1eb0: 79 00 68 61 72 64 20 66         y.hard f
    1eb8: 61 75 6c 74 00 20 61 6c         ault. al
    1ec0: 6c 6f 63 61 74 69 6f 6e         location
    1ec8: 73 3d 00 20 73 74 61 63         s=. stac
    1ed0: 6b 3d 00 23 7a 73 20 68         k=.#zs h
    1ed8: 65 61 70 5f 70 65 61 6b         eap_peak
    1ee0: 3d 00 20 6c 69 76 65 3d         =. live=
    1ee8: 00 20 68 65 61 70 5f 72         . heap_r
    1ef0: 65 73 65 72 76 65 64 3d         eserved=
    1ef8: 00 70 61 6e 69 63 3a 20         .panic: 
    1f00: 00 0a 00 d4                     ....
