
bench/mcu/out/fir.elf:	file format elf32-littlearm

Disassembly of section .text:

00000000 <vectors>:
       0: 00 00 40 20 b5 11 00 00         ..@ ....
       8: fd 12 00 00 fd 12 00 00         ........
      10: fd 12 00 00 fd 12 00 00         ........
      18: fd 12 00 00 00 00 00 00         ........
      20: 00 00 00 00 00 00 00 00         ........
      28: 00 00 00 00 fd 12 00 00         ........
      30: fd 12 00 00 00 00 00 00         ........
      38: fd 12 00 00 0d 13 00 00         ........

00000040 <main>:
      40:      	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
      44:      	sub	sp, #0x4
      46:      	vpush	{d8}
      4a:      	bl	0x11ac <zs_set_args>    @ imm = #0x115e
      4e:      	movs	r0, #0x88
      50:      	bl	0x65c <zs_alloc>        @ imm = #0x608
      54:      	mov	r4, r0
      56:      	movs	r0, #0x1
      58:      	movs	r1, #0x20
      5a:      	strd	r0, r1, [r4]
      5e:      	add.w	r0, r4, #0x8
      62:      	movs	r1, #0x80
      64:      	bl	0x17fc <compiler_rt.arm.__aeabi_memclr> @ imm = #0x1794
      68:      	vldr	s0, [pc, #8]            @ 0x74 <main+0x34>
      6c:      	movs	r0, #0x10
      6e:      	movs	r1, #0x0
      70:      	b	0x78 <main+0x38>        @ imm = #0x4
      72:      	nop
      74: 00 00 04 44  	.word	0x44040000
      78:      	sub.w	r2, r0, #0xf
      7c:      	vmov	s2, r2
      80:      	sub.w	r2, r0, #0xe
      84:      	vcvt.f32.u32	s2, s2
      88:      	vmov	s4, r2
      8c:      	vdiv.f32	s2, s2, s0
      90:      	vcvt.f32.u32	s4, s4
      94:      	vdiv.f32	s4, s4, s0
      98:      	adds	r2, r4, r1
      9a:      	sub.w	r3, r0, #0xd
      9e:      	vmov	s13, r0
      a2:      	vcvt.f32.u32	s13, s13
      a6:      	vdiv.f32	s13, s13, s0
      aa:      	adds	r1, #0x40
      ac:      	vstr	s2, [r2, #8]
      b0:      	vmov	s2, r3
      b4:      	sub.w	r3, r0, #0xc
      b8:      	vstr	s4, [r2, #12]
      bc:      	vmov	s4, r3
      c0:      	sub.w	r3, r0, #0xb
      c4:      	vmov	s6, r3
      c8:      	sub.w	r3, r0, #0xa
      cc:      	vmov	s8, r3
      d0:      	sub.w	r3, r0, #0x9
      d4:      	vmov	s10, r3
      d8:      	sub.w	r3, r0, #0x8
      dc:      	vmov	s12, r3
      e0:      	subs	r3, r0, #0x7
      e2:      	vmov	s14, r3
      e6:      	subs	r3, r0, #0x6
      e8:      	vmov	s1, r3
      ec:      	subs	r3, r0, #0x5
      ee:      	vmov	s3, r3
      f2:      	subs	r3, r0, #0x4
      f4:      	vmov	s5, r3
      f8:      	subs	r3, r0, #0x3
      fa:      	vmov	s7, r3
      fe:      	subs	r3, r0, #0x2
     100:      	vmov	s9, r3
     104:      	subs	r3, r0, #0x1
     106:      	vmov	s11, r3
     10a:      	vcvt.f32.u32	s2, s2
     10e:      	vcvt.f32.u32	s4, s4
     112:      	vcvt.f32.u32	s6, s6
     116:      	vcvt.f32.u32	s8, s8
     11a:      	vcvt.f32.u32	s10, s10
     11e:      	vcvt.f32.u32	s12, s12
     122:      	vcvt.f32.u32	s14, s14
     126:      	vcvt.f32.u32	s1, s1
     12a:      	vcvt.f32.u32	s3, s3
     12e:      	vcvt.f32.u32	s5, s5
     132:      	vcvt.f32.u32	s7, s7
     136:      	vcvt.f32.u32	s9, s9
     13a:      	vcvt.f32.u32	s11, s11
     13e:      	vdiv.f32	s2, s2, s0
     142:      	vdiv.f32	s4, s4, s0
     146:      	vdiv.f32	s6, s6, s0
     14a:      	vdiv.f32	s8, s8, s0
     14e:      	vdiv.f32	s10, s10, s0
     152:      	vdiv.f32	s12, s12, s0
     156:      	vdiv.f32	s14, s14, s0
     15a:      	vdiv.f32	s1, s1, s0
     15e:      	vdiv.f32	s3, s3, s0
     162:      	vdiv.f32	s5, s5, s0
     166:      	vdiv.f32	s7, s7, s0
     16a:      	vdiv.f32	s9, s9, s0
     16e:      	vdiv.f32	s11, s11, s0
     172:      	adds	r0, #0x10
     174:      	cmp	r0, #0x30
     176:      	vstr	s2, [r2, #16]
     17a:      	vstr	s4, [r2, #20]
     17e:      	vstr	s6, [r2, #24]
     182:      	vstr	s8, [r2, #28]
     186:      	vstr	s10, [r2, #32]
     18a:      	vstr	s12, [r2, #36]
     18e:      	vstr	s14, [r2, #40]
     192:      	vstr	s1, [r2, #44]
     196:      	vstr	s3, [r2, #48]
     19a:      	vstr	s5, [r2, #52]
     19e:      	vstr	s7, [r2, #56]
     1a2:      	vstr	s9, [r2, #60]
     1a6:      	vstr	s11, [r2, #64]
     1aa:      	vstr	s13, [r2, #68]
     1ae:      	bne.w	0x78 <main+0x38>        @ imm = #-0x13a
     1b2:      	movw	r0, #0x1008
     1b6:      	bl	0x65c <zs_alloc>        @ imm = #0x4a2
     1ba:      	mov	r5, r0
     1bc:      	movs	r0, #0x1
     1be:      	mov.w	r1, #0x400
     1c2:      	strd	r0, r1, [r5]
     1c6:      	add.w	r0, r5, #0x8
     1ca:      	mov.w	r1, #0x1000
     1ce:      	bl	0x17fc <compiler_rt.arm.__aeabi_memclr> @ imm = #0x162a
     1d2:      	movw	r9, #0x3c3c
     1d6:      	movw	r10, #0x2d2d
     1da:      	movw	r11, #0x1e1e
     1de:      	movs	r0, #0xf
     1e0:      	mov.w	r8, #0x0
     1e4:      	movw	r3, #0xf0f1
     1e8:      	mvn	r7, #0x7
     1ec:      	movt	r9, #0xfffc
     1f0:      	movt	r10, #0xfffd
     1f4:      	movt	r11, #0xfffe
     1f8:      	movw	lr, #0x40f
     1fc:      	movw	r1, #0xe1e1
     200:      	movt	r1, #0xfff1
     204:      	mla	r6, r0, r3, r1
     208:      	movw	r1, #0xd2d2
     20c:      	movt	r1, #0xfff2
     210:      	lsrs	r6, r6, #0x14
     212:      	mla	r12, r0, r3, r1
     216:      	add.w	r6, r6, r6, lsl #4
     21a:      	subs	r6, r0, r6
     21c:      	lsr.w	r2, r12, #0x14
     220:      	movw	r1, #0xc3c3
     224:      	subs	r6, #0xf
     226:      	add.w	r2, r2, r2, lsl #4
     22a:      	movt	r1, #0xfff3
     22e:      	uxtah	r6, r7, r6
     232:      	subs	r2, r0, r2
     234:      	mla	r1, r0, r3, r1
     238:      	vmov	s0, r6
     23c:      	subs	r2, #0xe
     23e:      	vcvt.f32.s32	s0, s0
     242:      	add.w	r6, r5, r8
     246:      	uxtah	r2, r7, r2
     24a:      	lsrs	r1, r1, #0x14
     24c:      	vstr	s0, [r6, #8]
     250:      	vmov	s0, r2
     254:      	add.w	r1, r1, r1, lsl #4
     258:      	movw	r2, #0xb4b4
     25c:      	subs	r1, r0, r1
     25e:      	movt	r2, #0xfff4
     262:      	subs	r1, #0xd
     264:      	mla	r2, r0, r3, r2
     268:      	uxtah	r1, r7, r1
     26c:      	vmov	s2, r1
     270:      	lsrs	r1, r2, #0x14
     272:      	add.w	r1, r1, r1, lsl #4
     276:      	movw	r2, #0xa5a5
     27a:      	subs	r1, r0, r1
     27c:      	movt	r2, #0xfff5
     280:      	subs	r1, #0xc
     282:      	mla	r2, r0, r3, r2
     286:      	uxtah	r1, r7, r1
     28a:      	vmov	s4, r1
     28e:      	lsrs	r1, r2, #0x14
     290:      	add.w	r1, r1, r1, lsl #4
     294:      	movw	r2, #0x9696
     298:      	subs	r1, r0, r1
     29a:      	movt	r2, #0xfff6
     29e:      	subs	r1, #0xb
     2a0:      	mla	r2, r0, r3, r2
     2a4:      	uxtah	r1, r7, r1
     2a8:      	vmov	s6, r1
     2ac:      	lsrs	r1, r2, #0x14
     2ae:      	add.w	r1, r1, r1, lsl #4
     2b2:      	movw	r2, #0x8787
     2b6:      	subs	r1, r0, r1
     2b8:      	movt	r2, #0xfff7
     2bc:      	subs	r1, #0xa
     2be:      	mla	r2, r0, r3, r2
     2c2:      	uxtah	r1, r7, r1
     2c6:      	vmov	s8, r1
     2ca:      	lsrs	r1, r2, #0x14
     2cc:      	add.w	r1, r1, r1, lsl #4
     2d0:      	movw	r2, #0x7878
     2d4:      	subs	r1, r0, r1
     2d6:      	movt	r2, #0xfff8
     2da:      	subs	r1, #0x9
     2dc:      	mla	r2, r0, r3, r2
     2e0:      	uxtah	r1, r7, r1
     2e4:      	vmov	s10, r1
     2e8:      	lsrs	r1, r2, #0x14
     2ea:      	add.w	r1, r1, r1, lsl #4
     2ee:      	movw	r2, #0x6969
     2f2:      	subs	r1, r0, r1
     2f4:      	movt	r2, #0xfff9
     2f8:      	subs	r1, #0x8
     2fa:      	mla	r2, r0, r3, r2
     2fe:      	uxtah	r1, r7, r1
     302:      	vmov	s12, r1
     306:      	lsrs	r1, r2, #0x14
     308:      	add.w	r1, r1, r1, lsl #4
     30c:      	movw	r2, #0x5a5a
     310:      	subs	r1, r0, r1
     312:      	movt	r2, #0xfffa
     316:      	subs	r1, #0x7
     318:      	mla	r2, r0, r3, r2
     31c:      	uxtah	r1, r7, r1
     320:      	vmov	s14, r1
     324:      	lsrs	r1, r2, #0x14
     326:      	add.w	r1, r1, r1, lsl #4
     32a:      	movw	r2, #0x4b4b
     32e:      	subs	r1, r0, r1
     330:      	movt	r2, #0xfffb
     334:      	subs	r1, #0x6
     336:      	mla	r2, r0, r3, r2
     33a:      	uxtah	r1, r7, r1
     33e:      	vmov	s1, r1
     342:      	lsrs	r1, r2, #0x14
     344:      	add.w	r1, r1, r1, lsl #4
     348:      	subs	r1, r0, r1
     34a:      	subs	r1, #0x5
     34c:      	mla	r2, r0, r3, r9
     350:      	uxtah	r1, r7, r1
     354:      	vmov	s3, r1
     358:      	lsrs	r1, r2, #0x14
     35a:      	add.w	r1, r1, r1, lsl #4
     35e:      	subs	r1, r0, r1
     360:      	subs	r1, #0x4
     362:      	mla	r2, r0, r3, r10
     366:      	uxtah	r1, r7, r1
     36a:      	vmov	s5, r1
     36e:      	lsrs	r1, r2, #0x14
     370:      	add.w	r1, r1, r1, lsl #4
     374:      	subs	r1, r0, r1
     376:      	subs	r1, #0x3
     378:      	mla	r2, r0, r3, r11
     37c:      	uxtah	r1, r7, r1
     380:      	vmov	s7, r1
     384:      	lsrs	r1, r2, #0x14
     386:      	add.w	r1, r1, r1, lsl #4
     38a:      	vcvt.f32.s32	s2, s2
     38e:      	subs	r1, r0, r1
     390:      	vstr	s2, [r6, #16]
     394:      	vcvt.f32.s32	s2, s4
     398:      	subs	r1, #0x2
     39a:      	vstr	s2, [r6, #20]
     39e:      	vcvt.f32.s32	s2, s6
     3a2:      	uxtah	r1, r7, r1
     3a6:      	vstr	s2, [r6, #24]
     3aa:      	vcvt.f32.s32	s2, s8
     3ae:      	vmov	s9, r1
     3b2:      	mul	r1, r0, r3
     3b6:      	vstr	s2, [r6, #28]
     3ba:      	vcvt.f32.s32	s2, s10
     3be:      	subs	r2, r1, r3
     3c0:      	vstr	s2, [r6, #32]
     3c4:      	vcvt.f32.s32	s2, s12
     3c8:      	lsrs	r2, r2, #0x14
     3ca:      	vstr	s2, [r6, #36]
     3ce:      	vcvt.f32.s32	s2, s14
     3d2:      	add.w	r2, r2, r2, lsl #4
     3d6:      	lsrs	r1, r1, #0x14
     3d8:      	vstr	s2, [r6, #40]
     3dc:      	vcvt.f32.s32	s2, s1
     3e0:      	subs	r2, r2, r0
     3e2:      	add.w	r1, r1, r1, lsl #4
     3e6:      	vstr	s2, [r6, #44]
     3ea:      	vcvt.f32.s32	s2, s3
     3ee:      	mvns	r2, r2
     3f0:      	subs	r1, r0, r1
     3f2:      	vstr	s2, [r6, #48]
     3f6:      	vcvt.f32.s32	s2, s5
     3fa:      	uxtah	r2, r7, r2
     3fe:      	vcvt.f32.s32	s0, s0
     402:      	uxtah	r1, r7, r1
     406:      	vstr	s2, [r6, #52]
     40a:      	vcvt.f32.s32	s2, s7
     40e:      	vmov	s11, r2
     412:      	vstr	s0, [r6, #12]
     416:      	vmov	s0, r1
     41a:      	vstr	s2, [r6, #56]
     41e:      	vcvt.f32.s32	s2, s9
     422:      	adds	r0, #0x10
     424:      	vstr	s2, [r6, #60]
     428:      	vcvt.f32.s32	s2, s11
     42c:      	vcvt.f32.s32	s0, s0
     430:      	cmp	r0, lr
     432:      	add.w	r8, r8, #0x40
     436:      	vstr	s2, [r6, #64]
     43a:      	vstr	s0, [r6, #68]
     43e:      	bne.w	0x1fc <main+0x1bc>      @ imm = #-0x246
     442:      	vldr	s16, [pc, #528]         @ 0x654 <main+0x614>
     446:      	mov.w	r10, #0x1f
     44a:      	mov.w	r11, #0x48
     44e:      	movs	r6, #0x0
     450:      	bl	0x12a4 <zs_ticks>       @ imm = #0xe50
     454:      	mov	r8, r0
     456:      	mov	r9, r1
     458:      	vmov.f32	s0, s16
     45c:      	movs	r0, #0x0
     45e:      	mov	r1, r6
     460:      	mov	r2, r11
     462:      	vmov.f32	s2, s16
     466:      	nop
     468:      	adds	r3, r4, r0
     46a:      	adds	r7, r5, r1
     46c:      	vldr	s4, [r7, #132]
     470:      	vldr	s6, [r3, #8]
     474:      	vldr	s8, [r3, #12]
     478:      	vmul.f32	s4, s6, s4
     47c:      	vldr	s6, [r7, #128]
     480:      	vldr	s10, [r3, #16]
     484:      	vadd.f32	s2, s2, s4
     488:      	vmul.f32	s4, s8, s6
     48c:      	vldr	s6, [r7, #124]
     490:      	vldr	s12, [r3, #20]
     494:      	vadd.f32	s2, s2, s4
     498:      	vmul.f32	s4, s10, s6
     49c:      	vldr	s6, [r7, #120]
     4a0:      	vadd.f32	s2, s2, s4
     4a4:      	vmul.f32	s4, s12, s6
     4a8:      	vldr	s6, [r3, #24]
     4ac:      	vldr	s8, [r7, #116]
     4b0:      	vadd.f32	s2, s2, s4
     4b4:      	vmul.f32	s4, s6, s8
     4b8:      	vldr	s6, [r3, #28]
     4bc:      	vldr	s8, [r7, #112]
     4c0:      	vadd.f32	s2, s2, s4
     4c4:      	vmul.f32	s4, s6, s8
     4c8:      	vldr	s6, [r3, #32]
     4cc:      	vldr	s8, [r7, #108]
     4d0:      	vadd.f32	s2, s2, s4
     4d4:      	vmul.f32	s4, s6, s8
     4d8:      	vldr	s6, [r3, #36]
     4dc:      	vldr	s8, [r7, #104]
     4e0:      	vadd.f32	s2, s2, s4
     4e4:      	vmul.f32	s4, s6, s8
     4e8:      	vldr	s6, [r3, #40]
     4ec:      	vldr	s8, [r7, #100]
     4f0:      	vadd.f32	s2, s2, s4
     4f4:      	vmul.f32	s4, s6, s8
     4f8:      	vldr	s6, [r3, #44]
     4fc:      	vldr	s8, [r7, #96]
     500:      	vadd.f32	s2, s2, s4
     504:      	vmul.f32	s4, s6, s8
     508:      	vadd.f32	s2, s2, s4
     50c:      	vldr	s4, [r3, #48]
     510:      	vldr	s10, [r7, #92]
     514:      	vldr	s12, [r7, #88]
     518:      	vmul.f32	s4, s4, s10
     51c:      	vldr	s10, [r3, #52]
     520:      	vldr	s8, [r7, #84]
     524:      	vadd.f32	s2, s2, s4
     528:      	vmul.f32	s4, s10, s12
     52c:      	vldr	s10, [r3, #56]
     530:      	vldr	s6, [r7, #80]
     534:      	vadd.f32	s2, s2, s4
     538:      	vmul.f32	s4, s10, s8
     53c:      	vldr	s8, [r3, #60]
     540:      	vadd.f32	s2, s2, s4
     544:      	vmul.f32	s4, s8, s6
     548:      	adds	r7, r5, r2
     54a:      	vadd.f32	s2, s2, s4
     54e:      	vldr	s4, [r3, #64]
     552:      	vldr	s6, [r7, #4]
     556:      	vldr	s8, [r7]
     55a:      	vmul.f32	s4, s4, s6
     55e:      	vldr	s6, [r3, #68]
     562:      	vadd.f32	s2, s2, s4
     566:      	vmul.f32	s4, s6, s8
     56a:      	adds	r0, #0x40
     56c:      	vadd.f32	s2, s2, s4
     570:      	subs	r2, #0x40
     572:      	cmp	r0, #0x80
     574:      	sub.w	r1, r1, #0x40
     578:      	bne.w	0x468 <main+0x428>      @ imm = #-0x114
     57c:      	add.w	r10, r10, #0x1
     580:      	vadd.f32	s0, s0, s2
     584:      	add.w	r11, r11, #0x4
     588:      	cmp.w	r10, #0x400
     58c:      	add.w	r6, r6, #0x4
     590:      	bne.w	0x45c <main+0x41c>      @ imm = #-0x138
     594:      	vldr	s2, [pc, #192]          @ 0x658 <main+0x618>
     598:      	vmul.f32	s0, s0, s2
     59c:      	vcvt.s32.f32	s0, s0
     5a0:      	vmov	r6, s0
     5a4:      	bl	0x12a4 <zs_ticks>       @ imm = #0xcfc
     5a8:      	mov	r7, r0
     5aa:      	mov	r10, r1
     5ac:      	asrs	r1, r6, #0x1f
     5ae:      	mov	r0, r6
     5b0:      	bl	0xa44 <zs_str_of_i64>   @ imm = #0x490
     5b4:      	subs.w	r2, r7, r8
     5b8:      	sbcs.w	r1, r10, r9
     5bc:      	mov.w	r3, #0x0
     5c0:      	adc	r3, r3, #0x0
     5c4:      	eor	r3, r3, #0x1
     5c8:      	cmp	r3, #0x1
     5ca:      	beq	0x646 <main+0x606>      @ imm = #0x78
     5cc:      	mov	r7, r0
     5ce:      	mov	r0, r2
     5d0:      	bl	0x750 <zs_str_of_u64>   @ imm = #0x17c
     5d4:      	mov	r6, r0
     5d6:      	movw	r0, #0x1dbc
     5da:      	movt	r0, #0x0
     5de:      	bl	0xd5c <zs_print>        @ imm = #0x77a
     5e2:      	movw	r0, #0x1dd0
     5e6:      	movt	r0, #0x0
     5ea:      	bl	0xd5c <zs_print>        @ imm = #0x76e
     5ee:      	mov	r0, r7
     5f0:      	bl	0xd5c <zs_print>        @ imm = #0x768
     5f4:      	ldr	r0, [r7]
     5f6:      	cbz	r0, 0x608 <main+0x5c8>  @ imm = #0xe
     5f8:      	cmp	r0, #0x1
     5fa:      	bne	0x604 <main+0x5c4>      @ imm = #0x6
     5fc:      	mov	r0, r7
     5fe:      	bl	0x710 <zs_free>         @ imm = #0x10e
     602:      	b	0x608 <main+0x5c8>      @ imm = #0x2
     604:      	subs	r0, #0x1
     606:      	str	r0, [r7]
     608:      	movw	r0, #0x1de4
     60c:      	movt	r0, #0x0
     610:      	bl	0xd5c <zs_print>        @ imm = #0x748
     614:      	mov	r0, r6
     616:      	bl	0xe68 <zs_println>      @ imm = #0x84e
     61a:      	ldr	r0, [r6]
     61c:      	cbz	r0, 0x62e <main+0x5ee>  @ imm = #0xe
     61e:      	cmp	r0, #0x1
     620:      	bne	0x62a <main+0x5ea>      @ imm = #0x6
     622:      	mov	r0, r6
     624:      	bl	0x710 <zs_free>         @ imm = #0xe8
     628:      	b	0x62e <main+0x5ee>      @ imm = #0x2
     62a:      	subs	r0, #0x1
     62c:      	str	r0, [r6]
     62e:      	mov	r0, r5
     630:      	bl	0x710 <zs_free>         @ imm = #0xdc
     634:      	mov	r0, r4
     636:      	bl	0x710 <zs_free>         @ imm = #0xd6
     63a:      	movs	r0, #0x0
     63c:      	vpop	{d8}
     640:      	add	sp, #0x4
     642:      	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
     646:      	movw	r0, #0x1da0
     64a:      	movt	r0, #0x0
     64e:      	adds	r0, #0x8
     650:      	bl	0x6e4 <zs_panic_c>      @ imm = #0x90
     654: 00 00 00 00  	.word	0x00000000
     658: 00 00 7a 44  	.word	0x447a0000

0000065c <zs_alloc>:
     65c:      	push	{r7, lr}
     65e:      	mov	r7, sp
     660:      	adds	r0, #0x7
     662:      	lsrs	r1, r0, #0x3
     664:      	movw	r12, #0x0
     668:      	cmp	r1, #0x20
     66a:      	movt	r12, #0x2000
     66e:      	bhi	0x684 <zs_alloc+0x28>   @ imm = #0x12
     670:      	add.w	r1, r12, r1, lsl #2
     674:      	ldr	r2, [r1, #0x14]
     676:      	cbz	r2, 0x684 <zs_alloc+0x28> @ imm = #0xa
     678:      	mov	r0, r2
     67a:      	ldr	r3, [r2]
     67c:      	ldr	r2, [r0, #-8]!
     680:      	str	r3, [r1, #0x14]
     682:      	b	0x6b4 <zs_alloc+0x58>   @ imm = #0x2e
     684:      	ldr.w	r3, [r12]
     688:      	bic	r2, r0, #0x7
     68c:      	adds	r1, r2, r3
     68e:      	movw	r0, #0xfff9
     692:      	subs	r0, r1, r0
     694:      	cmn.w	r0, #0x10001
     698:      	blo	0x6d6 <zs_alloc+0x7a>   @ imm = #0x3a
     69a:      	movw	lr, #0x98
     69e:      	movt	lr, #0x2000
     6a2:      	adds	r1, #0x8
     6a4:      	add.w	r0, lr, r3
     6a8:      	str.w	r1, [r12]
     6ac:      	movs	r1, #0x0
     6ae:      	str.w	r2, [lr, r3]
     6b2:      	str	r1, [r0, #0x4]
     6b4:      	ldrd	r1, r3, [r12, #4]
     6b8:      	adds	r0, #0x8
     6ba:      	add	r1, r2
     6bc:      	cmp	r1, r3
     6be:      	str.w	r1, [r12, #0x4]
     6c2:      	it	hi
     6c4:      	strhi.w	r1, [r12, #0x8]
     6c8:      	ldrd	r1, r2, [r12, #12]
     6cc:      	adds	r1, #0x1
     6ce:      	adds	r2, #0x1
     6d0:      	strd	r1, r2, [r12, #12]
     6d4:      	pop	{r7, pc}
     6d6:      	movw	r0, #0x1df4
     6da:      	movt	r0, #0x0
     6de:      	bl	0x6e4 <zs_panic_c>      @ imm = #0x2
     6e2:      	bmi	0x68e <zs_alloc+0x32>   @ imm = #-0x58

000006e4 <zs_panic_c>:
     6e4:      	push	{r4, r6, r7, lr}
     6e6:      	add	r7, sp, #0x8
     6e8:      	mov	r4, r0
     6ea:      	movw	r0, #0x1e49
     6ee:      	movt	r0, #0x0
     6f2:      	bl	0xf84 <write_c>         @ imm = #0x88e
     6f6:      	mov	r0, r4
     6f8:      	bl	0xf84 <write_c>         @ imm = #0x888
     6fc:      	movw	r0, #0x1e51
     700:      	movt	r0, #0x0
     704:      	bl	0xf84 <write_c>         @ imm = #0x87c
     708:      	movs	r0, #0x86
     70a:      	bl	0x10c8 <stop>           @ imm = #0x9ba
     70e:      	bmi	0x6ba <zs_alloc+0x5e>   @ imm = #-0x58

00000710 <zs_free>:
     710:      	push	{r7, lr}
     712:      	mov	r7, sp
     714:      	movw	r12, #0x0
     718:      	movt	r12, #0x2000
     71c:      	ldr	r1, [r0, #-8]
     720:      	ldr.w	r3, [r12, #0x4]
     724:      	ldr.w	r2, [r12, #0xc]
     728:      	subs	r3, r3, r1
     72a:      	str.w	r3, [r12, #0x4]
     72e:      	lsrs	r3, r1, #0x3
     730:      	subs	r2, #0x1
     732:      	cmp	r3, #0x20
     734:      	str.w	r2, [r12, #0xc]
     738:      	it	hi
     73a:      	pophi	{r7, pc}
     73c:      	mvn	r2, #0x3
     740:      	and.w	r1, r2, r1, lsr #1
     744:      	add	r1, r12
     746:      	ldr	r2, [r1, #0x14]
     748:      	str	r2, [r0]
     74a:      	str	r0, [r1, #0x14]
     74c:      	pop	{r7, pc}
     74e:      	bmi	0x6fa <zs_panic_c+0x16> @ imm = #-0x58

00000750 <zs_str_of_u64>:
     750:      	push	{r4, r5, r6, r7, lr}
     752:      	add	r7, sp, #0xc
     754:      	push.w	{r8, r9, r10, r11}
     758:      	sub	sp, #0x34
     75a:      	movw	r9, #0xcccd
     75e:      	mov	r4, r1
     760:      	mov	r5, r0
     762:      	mov.w	r10, #0x1
     766:      	movt	r9, #0xcccc
     76a:      	add.w	r8, sp, #0x1c
     76e:      	nop
     770:      	lsrs	r0, r5, #0x1
     772:      	orr.w	r0, r0, r4, lsl #31
     776:      	adds.w	r1, r0, r4, lsr #1
     77a:      	adc	r1, r1, #0x0
     77e:      	umull	r2, r3, r1, r9
     782:      	bic	r2, r3, #0x3
     786:      	add.w	r2, r2, r3, lsr #2
     78a:      	subs	r1, r1, r2
     78c:      	subs	r1, r0, r1
     78e:      	umull	r0, r2, r1, r9
     792:      	add.w	r6, r0, r0, lsl #2
     796:      	lsr.w	r3, r4, #0x1
     79a:      	sub.w	r6, r5, r6, lsl #1
     79e:      	sbc	r3, r3, #0x0
     7a2:      	orr	r12, r6, #0x30
     7a6:      	subs.w	r6, r5, #0xa
     7aa:      	add.w	r11, r8, r10
     7ae:      	sbcs	r6, r4, #0x0
     7b2:      	strb	r12, [r11, #-1]
     7b6:      	blo	0x8a6 <zs_str_of_u64+0x156> @ imm = #0xec
     7b8:      	mov.w	r6, #0xcccccccc
     7bc:      	mla	r1, r1, r6, r2
     7c0:      	lsrs	r2, r0, #0x1
     7c2:      	mla	r1, r3, r9, r1
     7c6:      	and	r0, r0, #0x1
     7ca:      	orr.w	r2, r2, r1, lsl #31
     7ce:      	adds.w	r1, r2, r1, lsr #1
     7d2:      	adc	r1, r1, #0x0
     7d6:      	umull	r2, r3, r1, r9
     7da:      	bic	r2, r3, #0x3
     7de:      	add.w	r2, r2, r3, lsr #2
     7e2:      	subs	r1, r1, r2
     7e4:      	orr.w	r0, r0, r1, lsl #1
     7e8:      	subs.w	r1, r5, #0x64
     7ec:      	orr	r0, r0, #0x30
     7f0:      	sbcs	r1, r4, #0x0
     7f4:      	strb.w	r0, [r8, r10]
     7f8:      	blo	0x8ae <zs_str_of_u64+0x15e> @ imm = #0xb2
     7fa:      	mov	r0, r5
     7fc:      	mov	r1, r4
     7fe:      	movs	r2, #0x64
     800:      	movs	r3, #0x0
     802:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x1006
     806:      	lsrs	r2, r0, #0x1
     808:      	orr.w	r2, r2, r1, lsl #31
     80c:      	adds.w	r1, r2, r1, lsr #1
     810:      	adc	r1, r1, #0x0
     814:      	umull	r2, r3, r1, r9
     818:      	bic	r2, r3, #0x3
     81c:      	add.w	r2, r2, r3, lsr #2
     820:      	subs	r1, r1, r2
     822:      	and	r0, r0, #0x1
     826:      	orr.w	r0, r0, r1, lsl #1
     82a:      	subs.w	r1, r5, #0x3e8
     82e:      	orr	r0, r0, #0x30
     832:      	sbcs	r1, r4, #0x0
     836:      	strb.w	r0, [r11, #0x1]
     83a:      	blo	0x8b6 <zs_str_of_u64+0x166> @ imm = #0x78
     83c:      	mov	r0, r5
     83e:      	mov	r1, r4
     840:      	mov.w	r2, #0x3e8
     844:      	movs	r3, #0x0
     846:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xfc2
     84a:      	lsrs	r2, r0, #0x1
     84c:      	orr.w	r2, r2, r1, lsl #31
     850:      	adds.w	r1, r2, r1, lsr #1
     854:      	adc	r1, r1, #0x0
     858:      	umull	r2, r3, r1, r9
     85c:      	bic	r2, r3, #0x3
     860:      	add.w	r2, r2, r3, lsr #2
     864:      	subs	r1, r1, r2
     866:      	and	r0, r0, #0x1
     86a:      	orr.w	r0, r0, r1, lsl #1
     86e:      	orr	r0, r0, #0x30
     872:      	strb.w	r0, [r11, #0x2]
     876:      	mov	r0, r5
     878:      	mov	r1, r4
     87a:      	movw	r2, #0x2710
     87e:      	movs	r3, #0x0
     880:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf88
     884:      	movw	r2, #0x270f
     888:      	subs	r2, r2, r5
     88a:      	mov.w	r2, #0x0
     88e:      	sbcs	r2, r4
     890:      	add.w	r10, r10, #0x4
     894:      	mov	r5, r0
     896:      	mov	r4, r1
     898:      	blo.w	0x770 <zs_str_of_u64+0x20> @ imm = #-0x12c
     89c:      	sub.w	r1, r10, #0x1
     8a0:      	sub.w	lr, r10, #0x2
     8a4:      	b	0x8be <zs_str_of_u64+0x16e> @ imm = #0x16
     8a6:      	sub.w	lr, r10, #0x1
     8aa:      	mov	r1, r10
     8ac:      	b	0x8c0 <zs_str_of_u64+0x170> @ imm = #0x10
     8ae:      	add.w	r1, r10, #0x1
     8b2:      	mov	lr, r10
     8b4:      	b	0x8be <zs_str_of_u64+0x16e> @ imm = #0x6
     8b6:      	add.w	r1, r10, #0x2
     8ba:      	add.w	lr, r10, #0x1
     8be:      	mov	r10, r1
     8c0:      	and	r12, r1, #0x3
     8c4:      	lsrs	r3, r1, #0x2
     8c6:      	mov.w	r1, #0x0
     8ca:      	beq	0x8fe <zs_str_of_u64+0x1ae> @ imm = #0x30
     8cc:      	add	r6, sp, #0x4
     8ce:      	subs	r5, r6, #0x3
     8d0:      	add.w	r6, lr, r8
     8d4:      	sub.w	r9, r1, r3, lsl #2
     8d8:      	subs	r4, r6, #0x1
     8da:      	nop
     8dc:      	adds	r6, r4, r1
     8de:      	ldrb	r3, [r4, r1]
     8e0:      	ldrb	r2, [r6, #-2]
     8e4:      	ldrb	r0, [r6, #-1]
     8e8:      	ldrb	r6, [r6, #0x1]
     8ea:      	subs	r1, #0x4
     8ec:      	strb	r3, [r5, #4]!
     8f0:      	cmp	r9, r1
     8f2:      	strb	r6, [r5, #-1]
     8f6:      	strb	r0, [r5, #0x1]
     8f8:      	strb	r2, [r5, #0x2]
     8fa:      	bne	0x8dc <zs_str_of_u64+0x18c> @ imm = #-0x22
     8fc:      	rsbs	r1, r1, #0
     8fe:      	cmp.w	r12, #0x0
     902:      	beq	0x934 <zs_str_of_u64+0x1e4> @ imm = #0x2e
     904:      	sub.w	r0, lr, r1
     908:      	ldrb.w	r0, [r8, r0]
     90c:      	add	r3, sp, #0x4
     90e:      	cmp.w	r12, #0x1
     912:      	strb	r0, [r3, r1]
     914:      	beq	0x934 <zs_str_of_u64+0x1e4> @ imm = #0x1c
     916:      	adds	r0, r1, #0x1
     918:      	sub.w	r2, lr, r0
     91c:      	ldrb.w	r2, [r8, r2]
     920:      	cmp.w	r12, #0x2
     924:      	strb	r2, [r3, r0]
     926:      	beq	0x934 <zs_str_of_u64+0x1e4> @ imm = #0xa
     928:      	adds	r0, r1, #0x2
     92a:      	sub.w	r1, lr, r0
     92e:      	ldrb.w	r1, [r8, r1]
     932:      	strb	r1, [r3, r0]
     934:      	movw	r0, #0x0
     938:      	add.w	r1, lr, #0x11
     93c:      	cmp.w	lr, #0xf6
     940:      	movt	r0, #0x2000
     944:      	bhi	0x95c <zs_str_of_u64+0x20c> @ imm = #0x14
     946:      	lsrs	r2, r1, #0x3
     948:      	add.w	r3, r0, r2, lsl #2
     94c:      	ldr	r2, [r3, #0x14]
     94e:      	cbz	r2, 0x95c <zs_str_of_u64+0x20c> @ imm = #0xa
     950:      	mov	r1, r2
     952:      	ldr	r6, [r2]
     954:      	ldr	r2, [r1, #-8]!
     958:      	str	r6, [r3, #0x14]
     95a:      	b	0x984 <zs_str_of_u64+0x234> @ imm = #0x26
     95c:      	ldr	r3, [r0]
     95e:      	bic	r2, r1, #0x7
     962:      	adds	r5, r2, r3
     964:      	movw	r1, #0xfff9
     968:      	subs	r1, r5, r1
     96a:      	cmn.w	r1, #0x10001
     96e:      	blo	0xa38 <zs_str_of_u64+0x2e8> @ imm = #0xc6
     970:      	movw	r6, #0x98
     974:      	movt	r6, #0x2000
     978:      	adds	r1, r6, r3
     97a:      	adds	r5, #0x8
     97c:      	str	r2, [r6, r3]
     97e:      	movs	r3, #0x0
     980:      	str	r5, [r0]
     982:      	str	r3, [r1, #0x4]
     984:      	ldrd	r3, r6, [r0, #4]
     988:      	add	r2, r3
     98a:      	cmp	r2, r6
     98c:      	str	r2, [r0, #0x4]
     98e:      	it	hi
     990:      	strhi	r2, [r0, #0x8]
     992:      	ldrd	r2, r3, [r0, #12]
     996:      	adds	r2, #0x1
     998:      	adds	r3, #0x1
     99a:      	strd	r2, r3, [r0, #12]
     99e:      	movs	r2, #0x1
     9a0:      	mov	r0, r1
     9a2:      	str	r2, [r0, #8]!
     9a6:      	add.w	r5, r0, #0x8
     9aa:      	movs	r2, #0x0
     9ac:      	strb.w	r2, [r5, r10]
     9b0:      	ands	r2, r10, #0x3
     9b4:      	add	r3, sp, #0x4
     9b6:      	str.w	r10, [r0, #0x4]
     9ba:      	beq	0x9d8 <zs_str_of_u64+0x288> @ imm = #0x1a
     9bc:      	ldrb.w	r6, [sp, #0x4]
     9c0:      	cmp	r2, #0x1
     9c2:      	strb	r6, [r1, #0x10]
     9c4:      	bne	0x9e2 <zs_str_of_u64+0x292> @ imm = #0x1a
     9c6:      	sub.w	r2, r10, #0x1
     9ca:      	adds	r3, #0x1
     9cc:      	add.w	r5, r1, #0x11
     9d0:      	cmp.w	r10, #0x4
     9d4:      	bhs	0xa14 <zs_str_of_u64+0x2c4> @ imm = #0x3c
     9d6:      	b	0xa30 <zs_str_of_u64+0x2e0> @ imm = #0x56
     9d8:      	mov	r2, r10
     9da:      	cmp.w	r10, #0x4
     9de:      	bhs	0xa14 <zs_str_of_u64+0x2c4> @ imm = #0x32
     9e0:      	b	0xa30 <zs_str_of_u64+0x2e0> @ imm = #0x4c
     9e2:      	ldrb.w	r6, [sp, #0x5]
     9e6:      	cmp	r2, #0x2
     9e8:      	strb	r6, [r1, #0x11]
     9ea:      	bne	0x9fe <zs_str_of_u64+0x2ae> @ imm = #0x10
     9ec:      	sub.w	r2, r10, #0x2
     9f0:      	adds	r3, #0x2
     9f2:      	add.w	r5, r1, #0x12
     9f6:      	cmp.w	r10, #0x4
     9fa:      	bhs	0xa14 <zs_str_of_u64+0x2c4> @ imm = #0x16
     9fc:      	b	0xa30 <zs_str_of_u64+0x2e0> @ imm = #0x30
     9fe:      	ldrb.w	r6, [sp, #0x6]
     a02:      	sub.w	r2, r10, #0x3
     a06:      	adds	r3, #0x3
     a08:      	add.w	r5, r1, #0x13
     a0c:      	strb	r6, [r1, #0x12]
     a0e:      	cmp.w	r10, #0x4
     a12:      	blo	0xa30 <zs_str_of_u64+0x2e0> @ imm = #0x1a
     a14:      	subs	r1, r3, #0x4
     a16:      	subs	r3, r5, #0x4
     a18:      	ldrb	r6, [r1, #4]!
     a1c:      	subs	r2, #0x4
     a1e:      	strb	r6, [r3, #4]!
     a22:      	ldrb	r6, [r1, #0x1]
     a24:      	strb	r6, [r3, #0x1]
     a26:      	ldrb	r6, [r1, #0x2]
     a28:      	strb	r6, [r3, #0x2]
     a2a:      	ldrb	r6, [r1, #0x3]
     a2c:      	strb	r6, [r3, #0x3]
     a2e:      	bne	0xa18 <zs_str_of_u64+0x2c8> @ imm = #-0x1a
     a30:      	add	sp, #0x34
     a32:      	pop.w	{r8, r9, r10, r11}
     a36:      	pop	{r4, r5, r6, r7, pc}
     a38:      	movw	r0, #0x1df4
     a3c:      	movt	r0, #0x0
     a40:      	bl	0x6e4 <zs_panic_c>      @ imm = #-0x360

00000a44 <zs_str_of_i64>:
     a44:      	push	{r4, r5, r6, r7, lr}
     a46:      	add	r7, sp, #0xc
     a48:      	push.w	{r8, r9, r10, r11}
     a4c:      	sub	sp, #0x3c
     a4e:      	cmp.w	r1, #0xffffffff
     a52:      	add	r2, sp, #0xc
     a54:      	ble	0xa5c <zs_str_of_i64+0x18> @ imm = #0x4
     a56:      	str	r2, [sp, #0x8]
     a58:      	movs	r2, #0x0
     a5a:      	b	0xa68 <zs_str_of_i64+0x24> @ imm = #0xa
     a5c:      	adds	r2, #0x1
     a5e:      	str	r2, [sp, #0x8]
     a60:      	movs	r2, #0x2d
     a62:      	strb.w	r2, [sp, #0xc]
     a66:      	movs	r2, #0x1
     a68:      	eor.w	r0, r0, r1, asr #31
     a6c:      	str	r2, [sp, #0x4]
     a6e:      	eor.w	r2, r1, r1, asr #31
     a72:      	subs.w	r4, r0, r1, asr #31
     a76:      	movw	r8, #0xcccd
     a7a:      	sbc.w	r5, r2, r1, asr #31
     a7e:      	mov.w	r9, #0x1
     a82:      	movt	r8, #0xcccc
     a86:      	add.w	r10, sp, #0x24
     a8a:      	nop
     a8c:      	lsrs	r0, r4, #0x1
     a8e:      	orr.w	r0, r0, r5, lsl #31
     a92:      	adds.w	r1, r0, r5, lsr #1
     a96:      	adc	r1, r1, #0x0
     a9a:      	umull	r2, r3, r1, r8
     a9e:      	bic	r2, r3, #0x3
     aa2:      	add.w	r2, r2, r3, lsr #2
     aa6:      	subs	r1, r1, r2
     aa8:      	subs	r1, r0, r1
     aaa:      	umull	r0, r2, r1, r8
     aae:      	add.w	r6, r0, r0, lsl #2
     ab2:      	lsr.w	r3, r5, #0x1
     ab6:      	sub.w	r6, r4, r6, lsl #1
     aba:      	sbc	r3, r3, #0x0
     abe:      	orr	r12, r6, #0x30
     ac2:      	subs.w	r6, r4, #0xa
     ac6:      	add.w	r11, r10, r9
     aca:      	sbcs	r6, r5, #0x0
     ace:      	strb	r12, [r11, #-1]
     ad2:      	blo	0xbc2 <zs_str_of_i64+0x17e> @ imm = #0xec
     ad4:      	mov.w	r6, #0xcccccccc
     ad8:      	mla	r1, r1, r6, r2
     adc:      	lsrs	r2, r0, #0x1
     ade:      	mla	r1, r3, r8, r1
     ae2:      	and	r0, r0, #0x1
     ae6:      	orr.w	r2, r2, r1, lsl #31
     aea:      	adds.w	r1, r2, r1, lsr #1
     aee:      	adc	r1, r1, #0x0
     af2:      	umull	r2, r3, r1, r8
     af6:      	bic	r2, r3, #0x3
     afa:      	add.w	r2, r2, r3, lsr #2
     afe:      	subs	r1, r1, r2
     b00:      	orr.w	r0, r0, r1, lsl #1
     b04:      	subs.w	r1, r4, #0x64
     b08:      	orr	r0, r0, #0x30
     b0c:      	sbcs	r1, r5, #0x0
     b10:      	strb.w	r0, [r10, r9]
     b14:      	blo	0xbca <zs_str_of_i64+0x186> @ imm = #0xb2
     b16:      	mov	r0, r4
     b18:      	mov	r1, r5
     b1a:      	movs	r2, #0x64
     b1c:      	movs	r3, #0x0
     b1e:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xcea
     b22:      	lsrs	r2, r0, #0x1
     b24:      	orr.w	r2, r2, r1, lsl #31
     b28:      	adds.w	r1, r2, r1, lsr #1
     b2c:      	adc	r1, r1, #0x0
     b30:      	umull	r2, r3, r1, r8
     b34:      	bic	r2, r3, #0x3
     b38:      	add.w	r2, r2, r3, lsr #2
     b3c:      	subs	r1, r1, r2
     b3e:      	and	r0, r0, #0x1
     b42:      	orr.w	r0, r0, r1, lsl #1
     b46:      	subs.w	r1, r4, #0x3e8
     b4a:      	orr	r0, r0, #0x30
     b4e:      	sbcs	r1, r5, #0x0
     b52:      	strb.w	r0, [r11, #0x1]
     b56:      	blo	0xbd2 <zs_str_of_i64+0x18e> @ imm = #0x78
     b58:      	mov	r0, r4
     b5a:      	mov	r1, r5
     b5c:      	mov.w	r2, #0x3e8
     b60:      	movs	r3, #0x0
     b62:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xca6
     b66:      	lsrs	r2, r0, #0x1
     b68:      	orr.w	r2, r2, r1, lsl #31
     b6c:      	adds.w	r1, r2, r1, lsr #1
     b70:      	adc	r1, r1, #0x0
     b74:      	umull	r2, r3, r1, r8
     b78:      	bic	r2, r3, #0x3
     b7c:      	add.w	r2, r2, r3, lsr #2
     b80:      	subs	r1, r1, r2
     b82:      	and	r0, r0, #0x1
     b86:      	orr.w	r0, r0, r1, lsl #1
     b8a:      	orr	r0, r0, #0x30
     b8e:      	strb.w	r0, [r11, #0x2]
     b92:      	mov	r0, r4
     b94:      	mov	r1, r5
     b96:      	movw	r2, #0x2710
     b9a:      	movs	r3, #0x0
     b9c:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xc6c
     ba0:      	movw	r2, #0x270f
     ba4:      	subs	r2, r2, r4
     ba6:      	mov.w	r2, #0x0
     baa:      	sbcs	r2, r5
     bac:      	add.w	r9, r9, #0x4
     bb0:      	mov	r4, r0
     bb2:      	mov	r5, r1
     bb4:      	blo.w	0xa8c <zs_str_of_i64+0x48> @ imm = #-0x12c
     bb8:      	sub.w	r1, r9, #0x1
     bbc:      	sub.w	r12, r9, #0x2
     bc0:      	b	0xbda <zs_str_of_i64+0x196> @ imm = #0x16
     bc2:      	sub.w	r12, r9, #0x1
     bc6:      	mov	r1, r9
     bc8:      	b	0xbdc <zs_str_of_i64+0x198> @ imm = #0x10
     bca:      	add.w	r1, r9, #0x1
     bce:      	mov	r12, r9
     bd0:      	b	0xbda <zs_str_of_i64+0x196> @ imm = #0x6
     bd2:      	add.w	r1, r9, #0x2
     bd6:      	add.w	r12, r9, #0x1
     bda:      	mov	r9, r1
     bdc:      	ldr.w	r8, [sp, #0x8]
     be0:      	and	lr, r1, #0x3
     be4:      	lsrs	r3, r1, #0x2
     be6:      	mov.w	r1, #0x0
     bea:      	beq	0xc1c <zs_str_of_i64+0x1d8> @ imm = #0x2e
     bec:      	add.w	r6, r12, r10
     bf0:      	sub.w	r3, r1, r3, lsl #2
     bf4:      	sub.w	r5, r8, #0x3
     bf8:      	subs	r4, r6, #0x1
     bfa:      	nop
     bfc:      	adds	r6, r4, r1
     bfe:      	ldrb	r0, [r6, #0x1]
     c00:      	ldrb	r2, [r6, #-1]
     c04:      	strb	r0, [r5, #0x3]
     c06:      	ldrb	r0, [r4, r1]
     c08:      	subs	r1, #0x4
     c0a:      	strb	r0, [r5, #4]!
     c0e:      	ldrb	r0, [r6, #-2]
     c12:      	cmp	r3, r1
     c14:      	strb	r2, [r5, #0x1]
     c16:      	strb	r0, [r5, #0x2]
     c18:      	bne	0xbfc <zs_str_of_i64+0x1b8> @ imm = #-0x20
     c1a:      	rsbs	r1, r1, #0
     c1c:      	cmp.w	lr, #0x0
     c20:      	beq	0xc56 <zs_str_of_i64+0x212> @ imm = #0x32
     c22:      	sub.w	r0, r12, r1
     c26:      	ldrb.w	r0, [r10, r0]
     c2a:      	cmp.w	lr, #0x1
     c2e:      	strb.w	r0, [r8, r1]
     c32:      	beq	0xc56 <zs_str_of_i64+0x212> @ imm = #0x20
     c34:      	adds	r0, r1, #0x1
     c36:      	sub.w	r2, r12, r0
     c3a:      	ldrb.w	r2, [r10, r2]
     c3e:      	cmp.w	lr, #0x2
     c42:      	strb.w	r2, [r8, r0]
     c46:      	beq	0xc56 <zs_str_of_i64+0x212> @ imm = #0xc
     c48:      	adds	r0, r1, #0x2
     c4a:      	sub.w	r1, r12, r0
     c4e:      	ldrb.w	r1, [r10, r1]
     c52:      	strb.w	r1, [r8, r0]
     c56:      	ldr	r0, [sp, #0x4]
     c58:      	add.w	r1, r9, r0
     c5c:      	movw	r0, #0x0
     c60:      	add.w	r2, r1, #0x10
     c64:      	cmp	r1, #0xf7
     c66:      	movt	r0, #0x2000
     c6a:      	bhi	0xc82 <zs_str_of_i64+0x23e> @ imm = #0x14
     c6c:      	lsrs	r3, r2, #0x3
     c6e:      	add.w	r6, r0, r3, lsl #2
     c72:      	ldr	r3, [r6, #0x14]
     c74:      	cbz	r3, 0xc82 <zs_str_of_i64+0x23e> @ imm = #0xa
     c76:      	mov	r2, r3
     c78:      	ldr	r5, [r3]
     c7a:      	ldr	r3, [r2, #-8]!
     c7e:      	str	r5, [r6, #0x14]
     c80:      	b	0xcaa <zs_str_of_i64+0x266> @ imm = #0x26
     c82:      	ldr	r6, [r0]
     c84:      	bic	r3, r2, #0x7
     c88:      	adds	r5, r3, r6
     c8a:      	movw	r2, #0xfff9
     c8e:      	subs	r2, r5, r2
     c90:      	cmn.w	r2, #0x10001
     c94:      	blo	0xd50 <zs_str_of_i64+0x30c> @ imm = #0xb8
     c96:      	movw	r4, #0x98
     c9a:      	movt	r4, #0x2000
     c9e:      	adds	r2, r4, r6
     ca0:      	adds	r5, #0x8
     ca2:      	str	r3, [r4, r6]
     ca4:      	movs	r6, #0x0
     ca6:      	str	r5, [r0]
     ca8:      	str	r6, [r2, #0x4]
     caa:      	ldrd	r6, r5, [r0, #4]
     cae:      	add	r3, r6
     cb0:      	cmp	r3, r5
     cb2:      	str	r3, [r0, #0x4]
     cb4:      	it	hi
     cb6:      	strhi	r3, [r0, #0x8]
     cb8:      	ldrd	r3, r6, [r0, #12]
     cbc:      	ands	r4, r1, #0x3
     cc0:      	add.w	r3, r3, #0x1
     cc4:      	add.w	r6, r6, #0x1
     cc8:      	strd	r3, r6, [r0, #12]
     ccc:      	mov.w	r3, #0x1
     cd0:      	mov	r0, r2
     cd2:      	str	r3, [r0, #8]!
     cd6:      	add.w	r5, r0, #0x8
     cda:      	mov.w	r3, #0x0
     cde:      	strb	r3, [r5, r1]
     ce0:      	sub.w	r6, r1, #0x1
     ce4:      	add	r3, sp, #0xc
     ce6:      	str	r1, [r0, #0x4]
     ce8:      	beq	0xd14 <zs_str_of_i64+0x2d0> @ imm = #0x28
     cea:      	ldrb.w	r5, [sp, #0xc]
     cee:      	cmp	r4, #0x1
     cf0:      	strb	r5, [r2, #0x10]
     cf2:      	bne	0xd02 <zs_str_of_i64+0x2be> @ imm = #0xc
     cf4:      	adds	r3, #0x1
     cf6:      	add.w	r5, r2, #0x11
     cfa:      	mov	r1, r6
     cfc:      	cmp	r6, #0x3
     cfe:      	bhs	0xd18 <zs_str_of_i64+0x2d4> @ imm = #0x16
     d00:      	b	0xd34 <zs_str_of_i64+0x2f0> @ imm = #0x30
     d02:      	ldrb.w	r5, [sp, #0xd]
     d06:      	cmp	r4, #0x2
     d08:      	strb	r5, [r2, #0x11]
     d0a:      	bne	0xd3c <zs_str_of_i64+0x2f8> @ imm = #0x2e
     d0c:      	subs	r1, #0x2
     d0e:      	adds	r3, #0x2
     d10:      	add.w	r5, r2, #0x12
     d14:      	cmp	r6, #0x3
     d16:      	blo	0xd34 <zs_str_of_i64+0x2f0> @ imm = #0x1a
     d18:      	subs	r2, r3, #0x4
     d1a:      	subs	r3, r5, #0x4
     d1c:      	ldrb	r6, [r2, #4]!
     d20:      	subs	r1, #0x4
     d22:      	strb	r6, [r3, #4]!
     d26:      	ldrb	r6, [r2, #0x1]
     d28:      	strb	r6, [r3, #0x1]
     d2a:      	ldrb	r6, [r2, #0x2]
     d2c:      	strb	r6, [r3, #0x2]
     d2e:      	ldrb	r6, [r2, #0x3]
     d30:      	strb	r6, [r3, #0x3]
     d32:      	bne	0xd1c <zs_str_of_i64+0x2d8> @ imm = #-0x1a
     d34:      	add	sp, #0x3c
     d36:      	pop.w	{r8, r9, r10, r11}
     d3a:      	pop	{r4, r5, r6, r7, pc}
     d3c:      	ldrb.w	r4, [sp, #0xe]
     d40:      	subs	r1, #0x3
     d42:      	adds	r3, #0x3
     d44:      	add.w	r5, r2, #0x13
     d48:      	strb	r4, [r2, #0x12]
     d4a:      	cmp	r6, #0x3
     d4c:      	bhs	0xd18 <zs_str_of_i64+0x2d4> @ imm = #-0x38
     d4e:      	b	0xd34 <zs_str_of_i64+0x2f0> @ imm = #-0x1e
     d50:      	movw	r0, #0x1df4
     d54:      	movt	r0, #0x0
     d58:      	bl	0x6e4 <zs_panic_c>      @ imm = #-0x678

00000d5c <zs_print>:
     d5c:      	push	{r4, r5, r6, r7, lr}
     d5e:      	add	r7, sp, #0xc
     d60:      	push.w	{r8, r9, r10, r11}
     d64:      	sub	sp, #0x44
     d66:      	ldr.w	r11, [r0, #0x4]
     d6a:      	cmp.w	r11, #0x1
     d6e:      	blt	0xe60 <zs_print+0x104>  @ imm = #0xee
     d70:      	sub.w	r1, r7, #0x5d
     d74:      	movs	r2, #0x0
     d76:      	add.w	r3, r0, #0x8
     d7a:      	add.w	r12, r1, #0x1
     d7e:      	movs	r6, #0x40
     d80:      	mov.w	r9, #0x0
     d84:      	b	0xda4 <zs_print+0x48>   @ imm = #0x1c
     d86:      	nop
     d88:      	strb.w	r2, [r1, r8]
     d8c:      	movs	r0, #0x4
     d8e:      	subs.w	r11, r11, r8
     d92:      	bkpt	#0xab
     d94:      	sbc	r9, r9, #0x0
     d98:      	rsbs.w	r0, r11, #0x0
     d9c:      	sbcs.w	r0, r2, r9
     da0:      	add	r3, r8
     da2:      	bge	0xe60 <zs_print+0x104>  @ imm = #0xba
     da4:      	mov.w	r8, #0x40
     da8:      	cmp.w	r11, #0x40
     dac:      	it	lo
     dae:      	movlo	r8, r11
     db0:      	cmp.w	r9, #0x0
     db4:      	it	ne
     db6:      	movne	r8, r6
     db8:      	sub.w	r0, r8, #0x1
     dbc:      	cmp	r0, #0x3
     dbe:      	bhs	0xdcc <zs_print+0x70>   @ imm = #0xa
     dc0:      	movs	r0, #0x0
     dc2:      	ands	r4, r8, #0x3
     dc6:      	bne	0xe2e <zs_print+0xd2>   @ imm = #0x64
     dc8:      	b	0xd88 <zs_print+0x2c>   @ imm = #-0x44
     dca:      	nop
     dcc:      	bic	r0, r8, #0x3
     dd0:      	rsb.w	r10, r0, #0x0
     dd4:      	mov	r1, r3
     dd6:      	adds	r5, r3, #0x1
     dd8:      	mvn	r4, #0x3
     ddc:      	adds	r2, r5, r4
     dde:      	ldrb	r6, [r2, #0x3]
     de0:      	ldrb	r3, [r2, #0x4]
     de2:      	ldrb	r0, [r2, #0x5]
     de4:      	cmp	r6, #0x0
     de6:      	ldrb	r2, [r2, #0x6]
     de8:      	it	eq
     dea:      	moveq	r6, #0x20
     dec:      	add.w	lr, r12, r4
     df0:      	cmp	r3, #0x0
     df2:      	strb.w	r6, [lr, #0x3]
     df6:      	it	eq
     df8:      	moveq	r3, #0x20
     dfa:      	strb.w	r3, [lr, #0x4]
     dfe:      	cmp	r0, #0x0
     e00:      	it	eq
     e02:      	moveq	r0, #0x20
     e04:      	adds	r4, #0x4
     e06:      	strb.w	r0, [lr, #0x5]
     e0a:      	cmp	r2, #0x0
     e0c:      	add.w	r0, r10, r4
     e10:      	it	eq
     e12:      	moveq	r2, #0x20
     e14:      	adds	r0, #0x4
     e16:      	strb.w	r2, [lr, #0x6]
     e1a:      	bne	0xddc <zs_print+0x80>   @ imm = #-0x42
     e1c:      	adds	r0, r4, #0x4
     e1e:      	movs	r2, #0x0
     e20:      	mov	r3, r1
     e22:      	sub.w	r1, r7, #0x5d
     e26:      	movs	r6, #0x40
     e28:      	ands	r4, r8, #0x3
     e2c:      	beq	0xd88 <zs_print+0x2c>   @ imm = #-0xa8
     e2e:      	ldrb	r5, [r3, r0]
     e30:      	cmp	r5, #0x0
     e32:      	it	eq
     e34:      	moveq	r5, #0x20
     e36:      	cmp	r4, #0x1
     e38:      	strb	r5, [r1, r0]
     e3a:      	beq	0xd88 <zs_print+0x2c>   @ imm = #-0xb6
     e3c:      	add.w	r10, r0, #0x1
     e40:      	ldrb.w	r5, [r3, r10]
     e44:      	cmp	r5, #0x0
     e46:      	it	eq
     e48:      	moveq	r5, #0x20
     e4a:      	cmp	r4, #0x2
     e4c:      	strb.w	r5, [r1, r10]
     e50:      	beq	0xd88 <zs_print+0x2c>   @ imm = #-0xcc
     e52:      	adds	r0, #0x2
     e54:      	ldrb	r4, [r3, r0]
     e56:      	cmp	r4, #0x0
     e58:      	it	eq
     e5a:      	moveq	r4, #0x20
     e5c:      	strb	r4, [r1, r0]
     e5e:      	b	0xd88 <zs_print+0x2c>   @ imm = #-0xda
     e60:      	add	sp, #0x44
     e62:      	pop.w	{r8, r9, r10, r11}
     e66:      	pop	{r4, r5, r6, r7, pc}

00000e68 <zs_println>:
     e68:      	push	{r4, r5, r6, r7, lr}
     e6a:      	add	r7, sp, #0xc
     e6c:      	push.w	{r8, r9, r10, r11}
     e70:      	sub	sp, #0x44
     e72:      	ldr.w	r11, [r0, #0x4]
     e76:      	cmp.w	r11, #0x1
     e7a:      	blt	0xf6c <zs_println+0x104> @ imm = #0xee
     e7c:      	sub.w	r1, r7, #0x5d
     e80:      	movs	r2, #0x0
     e82:      	add.w	r3, r0, #0x8
     e86:      	add.w	r12, r1, #0x1
     e8a:      	movs	r6, #0x40
     e8c:      	mov.w	r9, #0x0
     e90:      	b	0xeb0 <zs_println+0x48> @ imm = #0x1c
     e92:      	nop
     e94:      	strb.w	r2, [r1, r8]
     e98:      	movs	r0, #0x4
     e9a:      	subs.w	r11, r11, r8
     e9e:      	bkpt	#0xab
     ea0:      	sbc	r9, r9, #0x0
     ea4:      	rsbs.w	r0, r11, #0x0
     ea8:      	sbcs.w	r0, r2, r9
     eac:      	add	r3, r8
     eae:      	bge	0xf6c <zs_println+0x104> @ imm = #0xba
     eb0:      	mov.w	r8, #0x40
     eb4:      	cmp.w	r11, #0x40
     eb8:      	it	lo
     eba:      	movlo	r8, r11
     ebc:      	cmp.w	r9, #0x0
     ec0:      	it	ne
     ec2:      	movne	r8, r6
     ec4:      	sub.w	r0, r8, #0x1
     ec8:      	cmp	r0, #0x3
     eca:      	bhs	0xed8 <zs_println+0x70> @ imm = #0xa
     ecc:      	movs	r0, #0x0
     ece:      	ands	r4, r8, #0x3
     ed2:      	bne	0xf3a <zs_println+0xd2> @ imm = #0x64
     ed4:      	b	0xe94 <zs_println+0x2c> @ imm = #-0x44
     ed6:      	nop
     ed8:      	bic	r0, r8, #0x3
     edc:      	rsb.w	r10, r0, #0x0
     ee0:      	mov	r1, r3
     ee2:      	adds	r5, r3, #0x1
     ee4:      	mvn	r4, #0x3
     ee8:      	adds	r2, r5, r4
     eea:      	ldrb	r6, [r2, #0x3]
     eec:      	ldrb	r3, [r2, #0x4]
     eee:      	ldrb	r0, [r2, #0x5]
     ef0:      	cmp	r6, #0x0
     ef2:      	ldrb	r2, [r2, #0x6]
     ef4:      	it	eq
     ef6:      	moveq	r6, #0x20
     ef8:      	add.w	lr, r12, r4
     efc:      	cmp	r3, #0x0
     efe:      	strb.w	r6, [lr, #0x3]
     f02:      	it	eq
     f04:      	moveq	r3, #0x20
     f06:      	strb.w	r3, [lr, #0x4]
     f0a:      	cmp	r0, #0x0
     f0c:      	it	eq
     f0e:      	moveq	r0, #0x20
     f10:      	adds	r4, #0x4
     f12:      	strb.w	r0, [lr, #0x5]
     f16:      	cmp	r2, #0x0
     f18:      	add.w	r0, r10, r4
     f1c:      	it	eq
     f1e:      	moveq	r2, #0x20
     f20:      	adds	r0, #0x4
     f22:      	strb.w	r2, [lr, #0x6]
     f26:      	bne	0xee8 <zs_println+0x80> @ imm = #-0x42
     f28:      	adds	r0, r4, #0x4
     f2a:      	movs	r2, #0x0
     f2c:      	mov	r3, r1
     f2e:      	sub.w	r1, r7, #0x5d
     f32:      	movs	r6, #0x40
     f34:      	ands	r4, r8, #0x3
     f38:      	beq	0xe94 <zs_println+0x2c> @ imm = #-0xa8
     f3a:      	ldrb	r5, [r3, r0]
     f3c:      	cmp	r5, #0x0
     f3e:      	it	eq
     f40:      	moveq	r5, #0x20
     f42:      	cmp	r4, #0x1
     f44:      	strb	r5, [r1, r0]
     f46:      	beq	0xe94 <zs_println+0x2c> @ imm = #-0xb6
     f48:      	add.w	r10, r0, #0x1
     f4c:      	ldrb.w	r5, [r3, r10]
     f50:      	cmp	r5, #0x0
     f52:      	it	eq
     f54:      	moveq	r5, #0x20
     f56:      	cmp	r4, #0x2
     f58:      	strb.w	r5, [r1, r10]
     f5c:      	beq	0xe94 <zs_println+0x2c> @ imm = #-0xcc
     f5e:      	adds	r0, #0x2
     f60:      	ldrb	r4, [r3, r0]
     f62:      	cmp	r4, #0x0
     f64:      	it	eq
     f66:      	moveq	r4, #0x20
     f68:      	strb	r4, [r1, r0]
     f6a:      	b	0xe94 <zs_println+0x2c> @ imm = #-0xda
     f6c:      	movs	r0, #0xa
     f6e:      	strh	r0, [r7, #-93]
     f72:      	movs	r0, #0x4
     f74:      	sub.w	r1, r7, #0x5d
     f78:      	bkpt	#0xab
     f7a:      	add	sp, #0x44
     f7c:      	pop.w	{r8, r9, r10, r11}
     f80:      	pop	{r4, r5, r6, r7, pc}
     f82:      	bmi	0xf2e <zs_println+0xc6> @ imm = #-0x58

00000f84 <write_c>:
     f84:      	push	{r4, r5, r6, r7, lr}
     f86:      	add	r7, sp, #0xc
     f88:      	push.w	{r8, r9, r10, r11}
     f8c:      	sub	sp, #0x44
     f8e:      	mov	r2, r0
     f90:      	mov.w	r11, #0xffffffff
     f94:      	add.w	r0, r2, r11
     f98:      	ldrb	r1, [r0, #0x1]
     f9a:      	cbz	r1, 0xfb4 <write_c+0x30> @ imm = #0x16
     f9c:      	ldrb	r1, [r0, #0x2]
     f9e:      	cbz	r1, 0xfc0 <write_c+0x3c> @ imm = #0x1e
     fa0:      	ldrb	r1, [r0, #0x3]
     fa2:      	cmp	r1, #0x0
     fa4:      	beq.w	0x10b4 <write_c+0x130>  @ imm = #0x10c
     fa8:      	ldrb	r0, [r0, #0x4]
     faa:      	add.w	r11, r11, #0x4
     fae:      	cmp	r0, #0x0
     fb0:      	bne	0xf94 <write_c+0x10>    @ imm = #-0x20
     fb2:      	b	0xfc4 <write_c+0x40>    @ imm = #0xe
     fb4:      	add.w	r11, r11, #0x1
     fb8:      	cmp.w	r11, #0x0
     fbc:      	bne	0xfca <write_c+0x46>    @ imm = #0xa
     fbe:      	b	0x10c0 <write_c+0x13c>  @ imm = #0xfe
     fc0:      	add.w	r11, r11, #0x2
     fc4:      	cmp.w	r11, #0x0
     fc8:      	beq	0x10c0 <write_c+0x13c>  @ imm = #0xf4
     fca:      	sub.w	r1, r7, #0x5d
     fce:      	movs	r3, #0x0
     fd0:      	add.w	r12, r1, #0x1
     fd4:      	movs	r6, #0x40
     fd6:      	mov.w	r9, #0x0
     fda:      	b	0xff8 <write_c+0x74>    @ imm = #0x1a
     fdc:      	strb.w	r3, [r1, r8]
     fe0:      	movs	r0, #0x4
     fe2:      	subs.w	r11, r11, r8
     fe6:      	bkpt	#0xab
     fe8:      	sbc	r9, r9, #0x0
     fec:      	rsbs.w	r0, r11, #0x0
     ff0:      	sbcs.w	r0, r3, r9
     ff4:      	add	r2, r8
     ff6:      	bge	0x10c0 <write_c+0x13c>  @ imm = #0xc6
     ff8:      	mov.w	r8, #0x40
     ffc:      	cmp.w	r11, #0x40
    1000:      	it	lo
    1002:      	movlo	r8, r11
    1004:      	cmp.w	r9, #0x0
    1008:      	it	ne
    100a:      	movne	r8, r6
    100c:      	sub.w	r0, r8, #0x1
    1010:      	cmp	r0, #0x3
    1012:      	bhs	0x1020 <write_c+0x9c>   @ imm = #0xa
    1014:      	movs	r0, #0x0
    1016:      	ands	r4, r8, #0x3
    101a:      	bne	0x1082 <write_c+0xfe>   @ imm = #0x64
    101c:      	b	0xfdc <write_c+0x58>    @ imm = #-0x44
    101e:      	nop
    1020:      	bic	r0, r8, #0x3
    1024:      	rsb.w	r10, r0, #0x0
    1028:      	mov	r1, r2
    102a:      	adds	r5, r2, #0x1
    102c:      	mvn	r4, #0x3
    1030:      	adds	r3, r5, r4
    1032:      	ldrb	r6, [r3, #0x3]
    1034:      	ldrb	r2, [r3, #0x4]
    1036:      	ldrb	r0, [r3, #0x5]
    1038:      	cmp	r6, #0x0
    103a:      	ldrb	r3, [r3, #0x6]
    103c:      	it	eq
    103e:      	moveq	r6, #0x20
    1040:      	add.w	lr, r12, r4
    1044:      	cmp	r2, #0x0
    1046:      	strb.w	r6, [lr, #0x3]
    104a:      	it	eq
    104c:      	moveq	r2, #0x20
    104e:      	strb.w	r2, [lr, #0x4]
    1052:      	cmp	r0, #0x0
    1054:      	it	eq
    1056:      	moveq	r0, #0x20
    1058:      	adds	r4, #0x4
    105a:      	strb.w	r0, [lr, #0x5]
    105e:      	cmp	r3, #0x0
    1060:      	add.w	r0, r10, r4
    1064:      	it	eq
    1066:      	moveq	r3, #0x20
    1068:      	adds	r0, #0x4
    106a:      	strb.w	r3, [lr, #0x6]
    106e:      	bne	0x1030 <write_c+0xac>   @ imm = #-0x42
    1070:      	adds	r0, r4, #0x4
    1072:      	mov	r2, r1
    1074:      	movs	r3, #0x0
    1076:      	sub.w	r1, r7, #0x5d
    107a:      	movs	r6, #0x40
    107c:      	ands	r4, r8, #0x3
    1080:      	beq	0xfdc <write_c+0x58>    @ imm = #-0xa8
    1082:      	ldrb	r5, [r2, r0]
    1084:      	cmp	r5, #0x0
    1086:      	it	eq
    1088:      	moveq	r5, #0x20
    108a:      	cmp	r4, #0x1
    108c:      	strb	r5, [r1, r0]
    108e:      	beq	0xfdc <write_c+0x58>    @ imm = #-0xb6
    1090:      	add.w	r10, r0, #0x1
    1094:      	ldrb.w	r5, [r2, r10]
    1098:      	cmp	r5, #0x0
    109a:      	it	eq
    109c:      	moveq	r5, #0x20
    109e:      	cmp	r4, #0x2
    10a0:      	strb.w	r5, [r1, r10]
    10a4:      	beq	0xfdc <write_c+0x58>    @ imm = #-0xcc
    10a6:      	adds	r0, #0x2
    10a8:      	ldrb	r4, [r2, r0]
    10aa:      	cmp	r4, #0x0
    10ac:      	it	eq
    10ae:      	moveq	r4, #0x20
    10b0:      	strb	r4, [r1, r0]
    10b2:      	b	0xfdc <write_c+0x58>    @ imm = #-0xda
    10b4:      	add.w	r11, r11, #0x3
    10b8:      	cmp.w	r11, #0x0
    10bc:      	bne.w	0xfca <write_c+0x46>    @ imm = #-0xf6
    10c0:      	add	sp, #0x44
    10c2:      	pop.w	{r8, r9, r10, r11}
    10c6:      	pop	{r4, r5, r6, r7, pc}

000010c8 <stop>:
    10c8:      	push	{r4, r5, r6, r7, lr}
    10ca:      	add	r7, sp, #0xc
    10cc:      	str	r8, [sp, #-4]!
    10d0:      	sub	sp, #0x48
    10d2:      	movw	r6, #0x8000
    10d6:      	movw	r5, #0x0
    10da:      	movt	r6, #0x203f
    10de:      	movt	r5, #0x2040
    10e2:      	cmp	r6, r5
    10e4:      	mov	r8, r0
    10e6:      	bhs	0x1132 <stop+0x6a>      @ imm = #0x48
    10e8:      	movw	r0, #0x8000
    10ec:      	movt	r0, #0x203f
    10f0:      	ldr	r1, [r0]
    10f2:      	cmp.w	r1, #0xcdcdcdcd
    10f6:      	bne	0x1130 <stop+0x68>      @ imm = #0x36
    10f8:      	adds	r6, r0, #0x4
    10fa:      	cmp	r6, r5
    10fc:      	bhs	0x1132 <stop+0x6a>      @ imm = #0x32
    10fe:      	ldr	r1, [r6]
    1100:      	cmp.w	r1, #0xcdcdcdcd
    1104:      	bne	0x1132 <stop+0x6a>      @ imm = #0x2a
    1106:      	add.w	r6, r0, #0x8
    110a:      	cmp	r6, r5
    110c:      	bhs	0x1132 <stop+0x6a>      @ imm = #0x22
    110e:      	ldr	r1, [r6]
    1110:      	cmp.w	r1, #0xcdcdcdcd
    1114:      	bne	0x1132 <stop+0x6a>      @ imm = #0x1a
    1116:      	add.w	r6, r0, #0xc
    111a:      	cmp	r6, r5
    111c:      	bhs	0x1132 <stop+0x6a>      @ imm = #0x12
    111e:      	ldr	r1, [r6]
    1120:      	cmp.w	r1, #0xcdcdcdcd
    1124:      	bne	0x1132 <stop+0x6a>      @ imm = #0xa
    1126:      	adds	r0, #0x10
    1128:      	cmp	r0, r5
    112a:      	mov	r6, r0
    112c:      	blo	0x10f0 <stop+0x28>      @ imm = #-0x40
    112e:      	b	0x1132 <stop+0x6a>      @ imm = #0x0
    1130:      	mov	r6, r0
    1132:      	movw	r4, #0x0
    1136:      	movt	r4, #0x2000
    113a:      	ldr	r2, [r4, #0x8]
    113c:      	movw	r0, #0x1e23
    1140:      	movt	r0, #0x0
    1144:      	movs	r3, #0x0
    1146:      	bl	0x1320 <text>           @ imm = #0x1d6
    114a:      	ldr	r2, [r4]
    114c:      	movw	r0, #0x1e39
    1150:      	movt	r0, #0x0
    1154:      	movs	r3, #0x0
    1156:      	bl	0x1320 <text>           @ imm = #0x1c6
    115a:      	ldr	r2, [r4, #0x10]
    115c:      	movw	r0, #0x1e0d
    1160:      	asrs	r3, r2, #0x1f
    1162:      	movt	r0, #0x0
    1166:      	bl	0x1320 <text>           @ imm = #0x1b6
    116a:      	ldr	r2, [r4, #0xc]
    116c:      	movw	r0, #0x1e32
    1170:      	asrs	r3, r2, #0x1f
    1172:      	movt	r0, #0x0
    1176:      	bl	0x1320 <text>           @ imm = #0x1a6
    117a:      	subs	r2, r5, r6
    117c:      	movw	r0, #0x1e1b
    1180:      	asrs	r3, r2, #0x1f
    1182:      	movt	r0, #0x0
    1186:      	bl	0x1320 <text>           @ imm = #0x196
    118a:      	movs	r0, #0xa
    118c:      	strh.w	r0, [sp, #0x4]
    1190:      	movs	r0, #0x4
    1192:      	add	r1, sp, #0x4
    1194:      	bkpt	#0xab
    1196:      	movs	r0, #0x26
    1198:      	movt	r0, #0x2
    119c:      	strd	r0, r8, [sp, #4]
    11a0:      	movs	r0, #0x20
    11a2:      	add	r1, sp, #0x4
    11a4:      	bkpt	#0xab
    11a6:      	nop
    11a8:      	b	0x11a8 <stop+0xe0>      @ imm = #-0x4
    11aa:      	bmi	0x1156 <stop+0x8e>      @ imm = #-0x58

000011ac <zs_set_args>:
    11ac:      	push	{r7, lr}
    11ae:      	mov	r7, sp
    11b0:      	pop	{r7, pc}
    11b2:      	bmi	0x115e <stop+0x96>      @ imm = #-0x58

000011b4 <Reset_Handler>:
    11b4:      	push	{r7, lr}
    11b6:      	mov	r7, sp
    11b8:      	movw	r0, #0x0
    11bc:      	movw	r1, #0x0
    11c0:      	movt	r0, #0x2000
    11c4:      	movt	r1, #0x2000
    11c8:      	cmp	r1, r0
    11ca:      	bhs	0x11fe <Reset_Handler+0x4a> @ imm = #0x30
    11cc:      	movw	r2, #0x1f4c
    11d0:      	movt	r2, #0x0
    11d4:      	ldr	r3, [r2]
    11d6:      	str	r3, [r1], #4
    11da:      	cmp	r1, r0
    11dc:      	bhs	0x11fe <Reset_Handler+0x4a> @ imm = #0x1e
    11de:      	ldr	r3, [r2, #0x4]
    11e0:      	str	r3, [r1], #4
    11e4:      	cmp	r1, r0
    11e6:      	bhs	0x11fe <Reset_Handler+0x4a> @ imm = #0x14
    11e8:      	ldr	r3, [r2, #0x8]
    11ea:      	str	r3, [r1], #4
    11ee:      	cmp	r1, r0
    11f0:      	bhs	0x11fe <Reset_Handler+0x4a> @ imm = #0xa
    11f2:      	ldr	r3, [r2, #0xc]
    11f4:      	adds	r2, #0x10
    11f6:      	str	r3, [r1], #4
    11fa:      	cmp	r1, r0
    11fc:      	blo	0x11d4 <Reset_Handler+0x20> @ imm = #-0x2c
    11fe:      	movw	r0, #0x9c
    1202:      	movw	r1, #0x0
    1206:      	movt	r0, #0x2001
    120a:      	movt	r1, #0x2000
    120e:      	cmp	r1, r0
    1210:      	bhs	0x1234 <Reset_Handler+0x80> @ imm = #0x20
    1212:      	movs	r2, #0x0
    1214:      	str	r2, [r1], #4
    1218:      	cmp	r1, r0
    121a:      	bhs	0x1234 <Reset_Handler+0x80> @ imm = #0x16
    121c:      	str	r2, [r1], #4
    1220:      	cmp	r1, r0
    1222:      	bhs	0x1234 <Reset_Handler+0x80> @ imm = #0xe
    1224:      	str	r2, [r1], #4
    1228:      	cmp	r1, r0
    122a:      	bhs	0x1234 <Reset_Handler+0x80> @ imm = #0x6
    122c:      	str	r2, [r1], #4
    1230:      	cmp	r1, r0
    1232:      	blo	0x1214 <Reset_Handler+0x60> @ imm = #-0x22
    1234:      	movw	r0, #0xed88
    1238:      	movt	r0, #0xe000
    123c:      	ldr	r1, [r0]
    123e:      	orr	r1, r1, #0xf00000
    1242:      	str	r1, [r0]
    1244:      	movw	r0, #0xe010
    1248:      	movt	r0, #0xe000
    124c:      	mvn	r1, #0xff000000
    1250:      	dsb	sy
    1254:      	isb	sy
    1258:      	str	r1, [r0, #0x4]
    125a:      	movs	r1, #0x0
    125c:      	str	r1, [r0, #0x8]
    125e:      	movs	r1, #0x7
    1260:      	str	r1, [r0]
    1262:      	mov	r0, sp
    1264:      	movw	r1, #0x8000
    1268:      	subs	r0, #0x40
    126a:      	movt	r1, #0x203f
    126e:      	cmp	r0, r1
    1270:      	bls	0x1298 <Reset_Handler+0xe4> @ imm = #0x24
    1272:      	mov.w	r2, #0xcdcdcdcd
    1276:      	nop
    1278:      	str	r2, [r1], #4
    127c:      	cmp	r1, r0
    127e:      	bhs	0x1298 <Reset_Handler+0xe4> @ imm = #0x16
    1280:      	str	r2, [r1], #4
    1284:      	cmp	r1, r0
    1286:      	bhs	0x1298 <Reset_Handler+0xe4> @ imm = #0xe
    1288:      	str	r2, [r1], #4
    128c:      	cmp	r1, r0
    128e:      	bhs	0x1298 <Reset_Handler+0xe4> @ imm = #0x6
    1290:      	str	r2, [r1], #4
    1294:      	cmp	r1, r0
    1296:      	blo	0x1278 <Reset_Handler+0xc4> @ imm = #-0x22
    1298:      	movs	r0, #0x0
    129a:      	movs	r1, #0x0
    129c:      	bl	0x40 <main>             @ imm = #-0x1260
    12a0:      	bl	0x10c8 <stop>           @ imm = #-0x1dc

000012a4 <zs_ticks>:
    12a4:      	push	{r7, lr}
    12a6:      	mov	r7, sp
    12a8:      	movw	r12, #0xe018
    12ac:      	movw	r2, #0x98
    12b0:      	movt	r12, #0xe000
    12b4:      	movt	r2, #0x2001
    12b8:      	ldr	r1, [r2]
    12ba:      	ldr.w	r3, [r12]
    12be:      	ldr	r0, [r2]
    12c0:      	cmp	r1, r0
    12c2:      	beq	0x12e8 <zs_ticks+0x44>  @ imm = #0x22
    12c4:      	ldr	r1, [r2]
    12c6:      	ldr.w	r3, [r12]
    12ca:      	ldr	r0, [r2]
    12cc:      	cmp	r1, r0
    12ce:      	beq	0x12e8 <zs_ticks+0x44>  @ imm = #0x16
    12d0:      	ldr	r1, [r2]
    12d2:      	ldr.w	r3, [r12]
    12d6:      	ldr	r0, [r2]
    12d8:      	cmp	r1, r0
    12da:      	beq	0x12e8 <zs_ticks+0x44>  @ imm = #0xa
    12dc:      	ldr	r1, [r2]
    12de:      	ldr.w	r3, [r12]
    12e2:      	ldr	r0, [r2]
    12e4:      	cmp	r1, r0
    12e6:      	bne	0x12b8 <zs_ticks+0x14>  @ imm = #-0x32
    12e8:      	mvn	r0, #0xff000000
    12ec:      	subs	r0, r0, r3
    12ee:      	lsrs	r2, r1, #0x8
    12f0:      	adds.w	r0, r0, r1, lsl #24
    12f4:      	adc	r1, r2, #0x0
    12f8:      	pop	{r7, pc}
    12fa:      	bmi	0x12a6 <zs_ticks+0x2>   @ imm = #-0x58

000012fc <fault>:
    12fc:      	push	{r7, lr}
    12fe:      	mov	r7, sp
    1300:      	movw	r0, #0x1e02
    1304:      	movt	r0, #0x0
    1308:      	bl	0x6e4 <zs_panic_c>      @ imm = #-0xc28

0000130c <SysTick_Handler>:
    130c:      	push	{r7, lr}
    130e:      	mov	r7, sp
    1310:      	movw	r0, #0x98
    1314:      	movt	r0, #0x2001
    1318:      	ldr	r1, [r0]
    131a:      	adds	r1, #0x1
    131c:      	str	r1, [r0]
    131e:      	pop	{r7, pc}

00001320 <text>:
    1320:      	push	{r4, r5, r6, r7, lr}
    1322:      	add	r7, sp, #0xc
    1324:      	push.w	{r8, r9, r10, r11}
    1328:      	sub	sp, #0x64
    132a:      	strd	r2, r3, [sp]
    132e:      	mov	r3, r0
    1330:      	mov.w	r12, #0xffffffff
    1334:      	add.w	r0, r3, r12
    1338:      	ldrb	r1, [r0, #0x1]
    133a:      	cbz	r1, 0x1356 <text+0x36>  @ imm = #0x18
    133c:      	ldrb	r1, [r0, #0x2]
    133e:      	cbz	r1, 0x1362 <text+0x42>  @ imm = #0x20
    1340:      	ldrb	r1, [r0, #0x3]
    1342:      	cbz	r1, 0x136e <text+0x4e>  @ imm = #0x28
    1344:      	ldrb	r0, [r0, #0x4]
    1346:      	add.w	r12, r12, #0x4
    134a:      	cmp	r0, #0x0
    134c:      	bne	0x1334 <text+0x14>      @ imm = #-0x1c
    134e:      	cmp.w	r12, #0x0
    1352:      	bne	0x1378 <text+0x58>      @ imm = #0x22
    1354:      	b	0x1466 <text+0x146>     @ imm = #0x10e
    1356:      	add.w	r12, r12, #0x1
    135a:      	cmp.w	r12, #0x0
    135e:      	bne	0x1378 <text+0x58>      @ imm = #0x16
    1360:      	b	0x1466 <text+0x146>     @ imm = #0x102
    1362:      	add.w	r12, r12, #0x2
    1366:      	cmp.w	r12, #0x0
    136a:      	bne	0x1378 <text+0x58>      @ imm = #0xa
    136c:      	b	0x1466 <text+0x146>     @ imm = #0xf6
    136e:      	add.w	r12, r12, #0x3
    1372:      	cmp.w	r12, #0x0
    1376:      	beq	0x1466 <text+0x146>     @ imm = #0xec
    1378:      	sub.w	r1, r7, #0x5d
    137c:      	movs	r4, #0x0
    137e:      	add.w	r10, r1, #0x1
    1382:      	movs	r5, #0x40
    1384:      	mov.w	r9, #0x0
    1388:      	b	0x13a8 <text+0x88>      @ imm = #0x1c
    138a:      	nop
    138c:      	strb.w	r4, [r1, r11]
    1390:      	movs	r0, #0x4
    1392:      	subs.w	r12, r12, r11
    1396:      	bkpt	#0xab
    1398:      	sbc	r9, r9, #0x0
    139c:      	rsbs.w	r0, r12, #0x0
    13a0:      	sbcs.w	r0, r4, r9
    13a4:      	add	r3, r11
    13a6:      	bge	0x1466 <text+0x146>     @ imm = #0xbc
    13a8:      	mov.w	r11, #0x40
    13ac:      	cmp.w	r12, #0x40
    13b0:      	it	lo
    13b2:      	movlo	r11, r12
    13b4:      	cmp.w	r9, #0x0
    13b8:      	it	ne
    13ba:      	movne	r11, r5
    13bc:      	sub.w	r0, r11, #0x1
    13c0:      	cmp	r0, #0x3
    13c2:      	bhs	0x13d0 <text+0xb0>      @ imm = #0xa
    13c4:      	movs	r0, #0x0
    13c6:      	ands	r2, r11, #0x3
    13ca:      	bne	0x1432 <text+0x112>     @ imm = #0x64
    13cc:      	b	0x138c <text+0x6c>      @ imm = #-0x44
    13ce:      	nop
    13d0:      	bic	r0, r11, #0x3
    13d4:      	rsb.w	lr, r0, #0x0
    13d8:      	mov	r1, r3
    13da:      	adds	r6, r3, #0x1
    13dc:      	mvn	r2, #0x3
    13e0:      	adds	r3, r6, r2
    13e2:      	ldrb	r5, [r3, #0x3]
    13e4:      	ldrb	r4, [r3, #0x4]
    13e6:      	ldrb	r0, [r3, #0x5]
    13e8:      	cmp	r5, #0x0
    13ea:      	ldrb	r3, [r3, #0x6]
    13ec:      	it	eq
    13ee:      	moveq	r5, #0x20
    13f0:      	add.w	r8, r10, r2
    13f4:      	cmp	r4, #0x0
    13f6:      	strb.w	r5, [r8, #0x3]
    13fa:      	it	eq
    13fc:      	moveq	r4, #0x20
    13fe:      	strb.w	r4, [r8, #0x4]
    1402:      	cmp	r0, #0x0
    1404:      	it	eq
    1406:      	moveq	r0, #0x20
    1408:      	adds	r2, #0x4
    140a:      	strb.w	r0, [r8, #0x5]
    140e:      	cmp	r3, #0x0
    1410:      	add.w	r0, lr, r2
    1414:      	it	eq
    1416:      	moveq	r3, #0x20
    1418:      	adds	r0, #0x4
    141a:      	strb.w	r3, [r8, #0x6]
    141e:      	bne	0x13e0 <text+0xc0>      @ imm = #-0x42
    1420:      	adds	r0, r2, #0x4
    1422:      	mov	r3, r1
    1424:      	movs	r4, #0x0
    1426:      	sub.w	r1, r7, #0x5d
    142a:      	movs	r5, #0x40
    142c:      	ands	r2, r11, #0x3
    1430:      	beq	0x138c <text+0x6c>      @ imm = #-0xa8
    1432:      	ldrb	r6, [r3, r0]
    1434:      	cmp	r6, #0x0
    1436:      	it	eq
    1438:      	moveq	r6, #0x20
    143a:      	cmp	r2, #0x1
    143c:      	strb	r6, [r1, r0]
    143e:      	beq	0x138c <text+0x6c>      @ imm = #-0xb6
    1440:      	adds	r6, r0, #0x1
    1442:      	ldrb.w	lr, [r3, r6]
    1446:      	cmp.w	lr, #0x0
    144a:      	it	eq
    144c:      	moveq.w	lr, #0x20
    1450:      	cmp	r2, #0x2
    1452:      	strb.w	lr, [r1, r6]
    1456:      	beq	0x138c <text+0x6c>      @ imm = #-0xce
    1458:      	adds	r0, #0x2
    145a:      	ldrb	r2, [r3, r0]
    145c:      	cmp	r2, #0x0
    145e:      	it	eq
    1460:      	moveq	r2, #0x20
    1462:      	strb	r2, [r1, r0]
    1464:      	b	0x138c <text+0x6c>      @ imm = #-0xdc
    1466:      	movw	r9, #0xcccd
    146a:      	ldrd	r4, r5, [sp]
    146e:      	mov.w	r11, #0x1
    1472:      	movt	r9, #0xcccc
    1476:      	sub.w	r10, r7, #0x5d
    147a:      	nop
    147c:      	lsrs	r0, r4, #0x1
    147e:      	orr.w	r0, r0, r5, lsl #31
    1482:      	adds.w	r1, r0, r5, lsr #1
    1486:      	adc	r1, r1, #0x0
    148a:      	umull	r2, r3, r1, r9
    148e:      	bic	r2, r3, #0x3
    1492:      	add.w	r2, r2, r3, lsr #2
    1496:      	subs	r1, r1, r2
    1498:      	subs	r1, r0, r1
    149a:      	umull	r0, lr, r1, r9
    149e:      	lsr.w	r3, r5, #0x1
    14a2:      	add.w	r6, r0, r0, lsl #2
    14a6:      	sbc	r2, r3, #0x0
    14aa:      	sub.w	r6, r4, r6, lsl #1
    14ae:      	mov	r3, r4
    14b0:      	subs	r4, #0xa
    14b2:      	orr	r12, r6, #0x30
    14b6:      	add.w	r8, r10, r11
    14ba:      	sbcs	r4, r5, #0x0
    14be:      	strb	r12, [r8, #-1]
    14c2:      	blo	0x15ba <text+0x29a>     @ imm = #0xf4
    14c4:      	mov.w	r4, #0xcccccccc
    14c8:      	mla	r1, r1, r4, lr
    14cc:      	mla	r1, r2, r9, r1
    14d0:      	lsrs	r2, r0, #0x1
    14d2:      	orr.w	r2, r2, r1, lsl #31
    14d6:      	adds.w	r1, r2, r1, lsr #1
    14da:      	adc	r1, r1, #0x0
    14de:      	umull	r2, r4, r1, r9
    14e2:      	bic	r2, r4, #0x3
    14e6:      	add.w	r2, r2, r4, lsr #2
    14ea:      	subs	r1, r1, r2
    14ec:      	and	r0, r0, #0x1
    14f0:      	orr.w	r0, r0, r1, lsl #1
    14f4:      	subs.w	r1, r3, #0x64
    14f8:      	orr	r0, r0, #0x30
    14fc:      	sbcs	r1, r5, #0x0
    1500:      	mov	r4, r10
    1502:      	strb.w	r0, [r10, r11]
    1506:      	blo	0x15c4 <text+0x2a4>     @ imm = #0xba
    1508:      	mov	r6, r3
    150a:      	mov	r0, r3
    150c:      	mov	r1, r5
    150e:      	movs	r2, #0x64
    1510:      	movs	r3, #0x0
    1512:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x2f6
    1516:      	lsrs	r2, r0, #0x1
    1518:      	orr.w	r2, r2, r1, lsl #31
    151c:      	adds.w	r1, r2, r1, lsr #1
    1520:      	adc	r1, r1, #0x0
    1524:      	umull	r2, r3, r1, r9
    1528:      	bic	r2, r3, #0x3
    152c:      	add.w	r2, r2, r3, lsr #2
    1530:      	subs	r1, r1, r2
    1532:      	and	r0, r0, #0x1
    1536:      	orr.w	r0, r0, r1, lsl #1
    153a:      	subs.w	r1, r6, #0x3e8
    153e:      	orr	r0, r0, #0x30
    1542:      	sbcs	r1, r5, #0x0
    1546:      	strb.w	r0, [r8, #0x1]
    154a:      	blo	0x15cc <text+0x2ac>     @ imm = #0x7e
    154c:      	mov	r0, r6
    154e:      	mov	r1, r5
    1550:      	mov.w	r2, #0x3e8
    1554:      	movs	r3, #0x0
    1556:      	mov	r10, r4
    1558:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x2b0
    155c:      	lsrs	r2, r0, #0x1
    155e:      	orr.w	r2, r2, r1, lsl #31
    1562:      	adds.w	r1, r2, r1, lsr #1
    1566:      	adc	r1, r1, #0x0
    156a:      	umull	r2, r3, r1, r9
    156e:      	bic	r2, r3, #0x3
    1572:      	add.w	r2, r2, r3, lsr #2
    1576:      	subs	r1, r1, r2
    1578:      	and	r0, r0, #0x1
    157c:      	orr.w	r0, r0, r1, lsl #1
    1580:      	orr	r0, r0, #0x30
    1584:      	strb.w	r0, [r8, #0x2]
    1588:      	mov	r0, r6
    158a:      	mov	r1, r5
    158c:      	movw	r2, #0x2710
    1590:      	movs	r3, #0x0
    1592:      	bl	0x180c <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x276
    1596:      	movw	r2, #0x270f
    159a:      	subs	r2, r2, r6
    159c:      	mov.w	r2, #0x0
    15a0:      	sbcs	r2, r5
    15a2:      	add.w	r11, r11, #0x4
    15a6:      	mov	r4, r0
    15a8:      	mov	r5, r1
    15aa:      	blo.w	0x147c <text+0x15c>     @ imm = #-0x132
    15ae:      	sub.w	r1, r11, #0x1
    15b2:      	sub.w	r12, r11, #0x2
    15b6:      	mov	r11, r1
    15b8:      	b	0x15c0 <text+0x2a0>     @ imm = #0x4
    15ba:      	sub.w	r12, r11, #0x1
    15be:      	mov	r1, r11
    15c0:      	mov	r4, r10
    15c2:      	b	0x15d6 <text+0x2b6>     @ imm = #0x10
    15c4:      	add.w	r1, r11, #0x1
    15c8:      	mov	r12, r11
    15ca:      	b	0x15d4 <text+0x2b4>     @ imm = #0x6
    15cc:      	add.w	r1, r11, #0x2
    15d0:      	add.w	r12, r11, #0x1
    15d4:      	mov	r11, r1
    15d6:      	and	lr, r1, #0x3
    15da:      	lsrs	r3, r1, #0x2
    15dc:      	mov.w	r1, #0x0
    15e0:      	beq	0x161a <text+0x2fa>     @ imm = #0x36
    15e2:      	sub.w	r6, r7, #0x75
    15e6:      	add.w	r5, r12, r4
    15ea:      	sub.w	r9, r1, r3, lsl #2
    15ee:      	subs	r6, #0x3
    15f0:      	subs	r5, #0x1
    15f2:      	nop
    15f4:      	adds	r4, r5, r1
    15f6:      	ldrb	r3, [r5, r1]
    15f8:      	ldrb	r0, [r4, #-2]
    15fc:      	ldrb	r2, [r4, #-1]
    1600:      	ldrb	r4, [r4, #0x1]
    1602:      	subs	r1, #0x4
    1604:      	strb	r3, [r6, #4]!
    1608:      	cmp	r9, r1
    160a:      	strb	r4, [r6, #-1]
    160e:      	strb	r2, [r6, #0x1]
    1610:      	strb	r0, [r6, #0x2]
    1612:      	bne	0x15f4 <text+0x2d4>     @ imm = #-0x22
    1614:      	rsbs	r1, r1, #0
    1616:      	sub.w	r4, r7, #0x5d
    161a:      	cmp.w	lr, #0x0
    161e:      	beq	0x164c <text+0x32c>     @ imm = #0x2a
    1620:      	sub.w	r0, r12, r1
    1624:      	ldrb	r0, [r4, r0]
    1626:      	sub.w	r3, r7, #0x75
    162a:      	cmp.w	lr, #0x1
    162e:      	strb	r0, [r3, r1]
    1630:      	beq	0x164c <text+0x32c>     @ imm = #0x18
    1632:      	adds	r0, r1, #0x1
    1634:      	sub.w	r2, r12, r0
    1638:      	ldrb	r2, [r4, r2]
    163a:      	cmp.w	lr, #0x2
    163e:      	strb	r2, [r3, r0]
    1640:      	beq	0x164c <text+0x32c>     @ imm = #0x8
    1642:      	adds	r0, r1, #0x2
    1644:      	sub.w	r1, r12, r0
    1648:      	ldrb	r1, [r4, r1]
    164a:      	strb	r1, [r3, r0]
    164c:      	sub.w	r0, r7, #0x75
    1650:      	movs	r1, #0x0
    1652:      	mov.w	r12, #0xffffffff
    1656:      	strb.w	r1, [r0, r11]
    165a:      	nop
    165c:      	add.w	r1, r0, r12
    1660:      	ldrb	r3, [r1, #0x1]
    1662:      	cbz	r3, 0x167e <text+0x35e> @ imm = #0x18
    1664:      	ldrb	r3, [r1, #0x2]
    1666:      	cbz	r3, 0x168a <text+0x36a> @ imm = #0x20
    1668:      	ldrb	r3, [r1, #0x3]
    166a:      	cbz	r3, 0x1696 <text+0x376> @ imm = #0x28
    166c:      	ldrb	r1, [r1, #0x4]
    166e:      	add.w	r12, r12, #0x4
    1672:      	cmp	r1, #0x0
    1674:      	bne	0x165c <text+0x33c>     @ imm = #-0x1c
    1676:      	cmp.w	r12, #0x0
    167a:      	bne	0x16a0 <text+0x380>     @ imm = #0x22
    167c:      	b	0x1788 <text+0x468>     @ imm = #0x108
    167e:      	add.w	r12, r12, #0x1
    1682:      	cmp.w	r12, #0x0
    1686:      	bne	0x16a0 <text+0x380>     @ imm = #0x16
    1688:      	b	0x1788 <text+0x468>     @ imm = #0xfc
    168a:      	add.w	r12, r12, #0x2
    168e:      	cmp.w	r12, #0x0
    1692:      	bne	0x16a0 <text+0x380>     @ imm = #0xa
    1694:      	b	0x1788 <text+0x468>     @ imm = #0xf0
    1696:      	add.w	r12, r12, #0x3
    169a:      	cmp.w	r12, #0x0
    169e:      	beq	0x1788 <text+0x468>     @ imm = #0xe6
    16a0:      	movs	r2, #0x0
    16a2:      	add.w	lr, r4, #0x1
    16a6:      	sub.w	r9, r7, #0x75
    16aa:      	movs	r3, #0x40
    16ac:      	mov.w	r11, #0x0
    16b0:      	b	0x16d2 <text+0x3b2>     @ imm = #0x1e
    16b2:      	nop
    16b4:      	strb.w	r2, [r4, r8]
    16b8:      	movs	r0, #0x4
    16ba:      	subs.w	r12, r12, r8
    16be:      	mov	r1, r4
    16c0:      	bkpt	#0xab
    16c2:      	sbc	r11, r11, #0x0
    16c6:      	rsbs.w	r0, r12, #0x0
    16ca:      	sbcs.w	r0, r2, r11
    16ce:      	add	r9, r8
    16d0:      	bge	0x1788 <text+0x468>     @ imm = #0xb4
    16d2:      	mov.w	r8, #0x40
    16d6:      	cmp.w	r12, #0x40
    16da:      	it	lo
    16dc:      	movlo	r8, r12
    16de:      	cmp.w	r11, #0x0
    16e2:      	it	ne
    16e4:      	movne	r8, r3
    16e6:      	sub.w	r0, r8, #0x1
    16ea:      	cmp	r0, #0x3
    16ec:      	bhs	0x16f8 <text+0x3d8>     @ imm = #0x8
    16ee:      	movs	r0, #0x0
    16f0:      	ands	r1, r8, #0x3
    16f4:      	bne	0x1752 <text+0x432>     @ imm = #0x5a
    16f6:      	b	0x16b4 <text+0x394>     @ imm = #-0x46
    16f8:      	bic	r0, r8, #0x3
    16fc:      	rsb.w	r10, r0, #0x0
    1700:      	add.w	r5, r9, #0x1
    1704:      	mvn	r1, #0x3
    1708:      	adds	r4, r5, r1
    170a:      	ldrb	r2, [r4, #0x3]
    170c:      	ldrb	r3, [r4, #0x4]
    170e:      	ldrb	r6, [r4, #0x5]
    1710:      	cmp	r2, #0x0
    1712:      	ldrb	r4, [r4, #0x6]
    1714:      	it	eq
    1716:      	moveq	r2, #0x20
    1718:      	add.w	r0, lr, r1
    171c:      	cmp	r3, #0x0
    171e:      	strb	r2, [r0, #0x3]
    1720:      	it	eq
    1722:      	moveq	r3, #0x20
    1724:      	cmp	r6, #0x0
    1726:      	add.w	r1, r1, #0x4
    172a:      	strb	r3, [r0, #0x4]
    172c:      	it	eq
    172e:      	moveq	r6, #0x20
    1730:      	cmp	r4, #0x0
    1732:      	add.w	r2, r10, r1
    1736:      	strb	r6, [r0, #0x5]
    1738:      	it	eq
    173a:      	moveq	r4, #0x20
    173c:      	adds	r2, #0x4
    173e:      	strb	r4, [r0, #0x6]
    1740:      	bne	0x1708 <text+0x3e8>     @ imm = #-0x3c
    1742:      	adds	r0, r1, #0x4
    1744:      	sub.w	r4, r7, #0x5d
    1748:      	movs	r2, #0x0
    174a:      	movs	r3, #0x40
    174c:      	ands	r1, r8, #0x3
    1750:      	beq	0x16b4 <text+0x394>     @ imm = #-0xa0
    1752:      	ldrb.w	r5, [r9, r0]
    1756:      	cmp	r5, #0x0
    1758:      	it	eq
    175a:      	moveq	r5, #0x20
    175c:      	cmp	r1, #0x1
    175e:      	strb	r5, [r4, r0]
    1760:      	beq	0x16b4 <text+0x394>     @ imm = #-0xb0
    1762:      	add.w	r10, r0, #0x1
    1766:      	ldrb.w	r5, [r9, r10]
    176a:      	cmp	r5, #0x0
    176c:      	it	eq
    176e:      	moveq	r5, #0x20
    1770:      	cmp	r1, #0x2
    1772:      	strb.w	r5, [r4, r10]
    1776:      	beq	0x16b4 <text+0x394>     @ imm = #-0xc6
    1778:      	adds	r0, #0x2
    177a:      	ldrb.w	r1, [r9, r0]
    177e:      	cmp	r1, #0x0
    1780:      	it	eq
    1782:      	moveq	r1, #0x20
    1784:      	strb	r1, [r4, r0]
    1786:      	b	0x16b4 <text+0x394>     @ imm = #-0xd6
    1788:      	add	sp, #0x64
    178a:      	pop.w	{r8, r9, r10, r11}
    178e:      	pop	{r4, r5, r6, r7, pc}

00001790 <compiler_rt.memset>:
    1790:      	cmp	r2, #0x0
    1792:      	it	eq
    1794:      	bxeq	lr
    1796:      	push	{r7, lr}
    1798:      	mov	r7, sp
    179a:      	ands	lr, r2, #0x3
    179e:      	mov	r3, r2
    17a0:      	mov	r12, r0
    17a2:      	beq	0x17c6 <compiler_rt.memset+0x36> @ imm = #0x20
    17a4:      	mov	r12, r0
    17a6:      	cmp.w	lr, #0x1
    17aa:      	strb	r1, [r12], #1
    17ae:      	bne	0x17b8 <compiler_rt.memset+0x28> @ imm = #0x6
    17b0:      	subs	r3, r2, #0x1
    17b2:      	cmp	r2, #0x4
    17b4:      	bhs	0x17ca <compiler_rt.memset+0x3a> @ imm = #0x12
    17b6:      	b	0x17de <compiler_rt.memset+0x4e> @ imm = #0x24
    17b8:      	cmp.w	lr, #0x2
    17bc:      	strb	r1, [r0, #0x1]
    17be:      	bne	0x17e4 <compiler_rt.memset+0x54> @ imm = #0x22
    17c0:      	subs	r3, r2, #0x2
    17c2:      	add.w	r12, r0, #0x2
    17c6:      	cmp	r2, #0x4
    17c8:      	blo	0x17de <compiler_rt.memset+0x4e> @ imm = #0x12
    17ca:      	sub.w	r2, r12, #0x4
    17ce:      	nop
    17d0:      	strb	r1, [r2, #4]!
    17d4:      	subs	r3, #0x4
    17d6:      	strb	r1, [r2, #0x1]
    17d8:      	strb	r1, [r2, #0x2]
    17da:      	strb	r1, [r2, #0x3]
    17dc:      	bne	0x17d0 <compiler_rt.memset+0x40> @ imm = #-0x10
    17de:      	pop.w	{r7, lr}
    17e2:      	bx	lr
    17e4:      	subs	r3, r2, #0x3
    17e6:      	add.w	r12, r0, #0x3
    17ea:      	strb	r1, [r0, #0x2]
    17ec:      	cmp	r2, #0x4
    17ee:      	bhs	0x17ca <compiler_rt.memset+0x3a> @ imm = #-0x28
    17f0:      	b	0x17de <compiler_rt.memset+0x4e> @ imm = #-0x16
    17f2:      	bmi	0x179e <compiler_rt.memset+0xe> @ imm = #-0x58

000017f4 <compiler_rt.arm.__aeabi_unwind_cpp_pr0>:
    17f4:      	push	{r7, lr}
    17f6:      	mov	r7, sp
    17f8:      	pop	{r7, pc}
    17fa:      	bmi	0x17a6 <compiler_rt.memset+0x16> @ imm = #-0x58

000017fc <compiler_rt.arm.__aeabi_memclr>:
    17fc:      	push	{r7, lr}
    17fe:      	mov	r7, sp
    1800:      	mov	r2, r1
    1802:      	movs	r1, #0x0
    1804:      	pop.w	{r7, lr}
    1808:      	b.w	0x1790 <compiler_rt.memset> @ imm = #-0x7c

0000180c <compiler_rt.arm.__aeabi_uldivmod>:
    180c:      	push	{r4, lr}
    180e:      	sub	sp, #0x10
    1810:      	add	r4, sp, #0x8
    1812:      	str	r4, [sp]
    1814:      	bl	0x1820 <compiler_rt.int.__udivmoddi4> @ imm = #0x8
    1818:      	ldr	r2, [sp, #0x8]
    181a:      	ldr	r3, [sp, #0xc]
    181c:      	add	sp, #0x10
    181e:      	pop	{r4, pc}

00001820 <compiler_rt.int.__udivmoddi4>:
    1820:      	push	{r4, r5, r6, r7, lr}
    1822:      	add	r7, sp, #0xc
    1824:      	push.w	{r8, r9, r10, r11}
    1828:      	sub	sp, #0x20
    182a:      	mov	r5, r2
    182c:      	ldr	r6, [r7, #0x8]
    182e:      	subs	r2, r0, r2
    1830:      	sbcs.w	r2, r1, r3
    1834:      	bhs	0x184c <compiler_rt.int.__udivmoddi4+0x2c> @ imm = #0x14
    1836:      	cmp	r6, #0x0
    1838:      	it	ne
    183a:      	strdne	r0, r1, [r6]
    183e:      	movs	r0, #0x0
    1840:      	movs	r1, #0x0
    1842:      	add	sp, #0x20
    1844:      	pop.w	{r8, r9, r10, r11}
    1848:      	pop	{r4, r5, r6, r7, pc}
    184a:      	nop
    184c:      	cmp	r3, #0x0
    184e:      	beq.w	0x1958 <compiler_rt.int.__udivmoddi4+0x138> @ imm = #0x106
    1852:      	clz	r2, r3
    1856:      	cmp	r2, #0x0
    1858:      	beq.w	0x1984 <compiler_rt.int.__udivmoddi4+0x164> @ imm = #0x128
    185c:      	rsbs	r6, r2, #0
    185e:      	and	r4, r6, #0x1f
    1862:      	lsl.w	r12, r3, r2
    1866:      	lsr.w	r6, r5, r4
    186a:      	orr.w	r8, r6, r12
    186e:      	lsl.w	r2, r1, r2
    1872:      	lsr.w	r6, r0, r4
    1876:      	clz	lr, r8
    187a:      	orrs	r2, r6
    187c:      	ands	r12, lr, #0x1f
    1880:      	lsr.w	r6, r1, r4
    1884:      	str	r5, [sp, #0x10]
    1886:      	str	r0, [sp, #0x4]
    1888:      	beq	0x18a4 <compiler_rt.int.__udivmoddi4+0x84> @ imm = #0x18
    188a:      	lsl.w	r4, r6, r12
    188e:      	rsb.w	r6, lr, #0x0
    1892:      	and	r6, r6, #0x1f
    1896:      	lsr.w	r6, r2, r6
    189a:      	lsl.w	r8, r8, r12
    189e:      	orrs	r6, r4
    18a0:      	lsl.w	r2, r2, r12
    18a4:      	lsr.w	lr, r8, #0x10
    18a8:      	udiv	r4, r6, lr
    18ac:      	strd	r3, r1, [sp, #8]
    18b0:      	mls	r9, r4, lr, r6
    18b4:      	uxth.w	r12, r8
    18b8:      	lsr.w	r11, r2, #0x10
    18bc:      	uxth	r3, r2
    18be:      	mov	r0, r6
    18c0:      	mov.w	r10, #0x0
    18c4:      	str.w	r8, [sp]
    18c8:      	b	0x18dc <compiler_rt.int.__udivmoddi4+0xbc> @ imm = #0x10
    18ca:      	nop
    18cc:      	subs	r6, r4, #0x4
    18ce:      	add.w	r9, r2, lr
    18d2:      	cmp.w	r10, r9, lsr #16
    18d6:      	mov	r4, r6
    18d8:      	bne.w	0x1b16 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x23a
    18dc:      	cmp.w	r10, r4, lsr #16
    18e0:      	bne	0x18f0 <compiler_rt.int.__udivmoddi4+0xd0> @ imm = #0xc
    18e2:      	mul	r2, r4, r12
    18e6:      	orr.w	r6, r11, r9, lsl #16
    18ea:      	cmp	r2, r6
    18ec:      	bls.w	0x1b14 <compiler_rt.int.__udivmoddi4+0x2f4> @ imm = #0x224
    18f0:      	add.w	r2, r9, lr
    18f4:      	cmp.w	r10, r2, lsr #16
    18f8:      	sub.w	r6, r4, #0x1
    18fc:      	bne.w	0x1b16 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x216
    1900:      	cmp.w	r10, r6, lsr #16
    1904:      	bne	0x1914 <compiler_rt.int.__udivmoddi4+0xf4> @ imm = #0xc
    1906:      	mul	r9, r6, r12
    190a:      	orr.w	r8, r11, r2, lsl #16
    190e:      	cmp	r9, r8
    1910:      	bls.w	0x1b16 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x202
    1914:      	add	r2, lr
    1916:      	cmp.w	r10, r2, lsr #16
    191a:      	sub.w	r6, r4, #0x2
    191e:      	bne.w	0x1b16 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1f4
    1922:      	cmp.w	r10, r6, lsr #16
    1926:      	bne	0x1936 <compiler_rt.int.__udivmoddi4+0x116> @ imm = #0xc
    1928:      	mul	r8, r6, r12
    192c:      	orr.w	r5, r11, r2, lsl #16
    1930:      	cmp	r8, r5
    1932:      	bls.w	0x1b16 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1e0
    1936:      	add	r2, lr
    1938:      	cmp.w	r10, r2, lsr #16
    193c:      	sub.w	r6, r4, #0x3
    1940:      	bne.w	0x1b16 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1d2
    1944:      	cmp.w	r10, r6, lsr #16
    1948:      	bne	0x18cc <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x80
    194a:      	mul	r5, r6, r12
    194e:      	orr.w	r1, r11, r2, lsl #16
    1952:      	cmp	r5, r1
    1954:      	bhi	0x18cc <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x8c
    1956:      	b	0x1b16 <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1bc
    1958:      	cmp	r1, r5
    195a:      	clz	lr, r5
    195e:      	bhs	0x199c <compiler_rt.int.__udivmoddi4+0x17c> @ imm = #0x3a
    1960:      	cmp.w	lr, #0x0
    1964:      	beq.w	0x1a6c <compiler_rt.int.__udivmoddi4+0x24c> @ imm = #0x104
    1968:      	rsb.w	r2, lr, #0x0
    196c:      	and	r2, r2, #0x1f
    1970:      	lsl.w	r1, r1, lr
    1974:      	lsr.w	r2, r0, r2
    1978:      	lsl.w	r5, r5, lr
    197c:      	orrs	r2, r1
    197e:      	lsl.w	r0, r0, lr
    1982:      	b	0x1a6e <compiler_rt.int.__udivmoddi4+0x24e> @ imm = #0xe8
    1984:      	cbz	r6, 0x198e <compiler_rt.int.__udivmoddi4+0x16e> @ imm = #0x6
    1986:      	subs	r0, r0, r5
    1988:      	sbcs	r1, r3
    198a:      	strd	r0, r1, [r6]
    198e:      	movs	r1, #0x0
    1990:      	movs	r0, #0x1
    1992:      	add	sp, #0x20
    1994:      	pop.w	{r8, r9, r10, r11}
    1998:      	pop	{r4, r5, r6, r7, pc}
    199a:      	nop
    199c:      	udiv	r2, r1, r5
    19a0:      	cmp.w	lr, #0x0
    19a4:      	mls	r8, r2, r5, r1
    19a8:      	mov	r1, r2
    19aa:      	beq	0x19c8 <compiler_rt.int.__udivmoddi4+0x1a8> @ imm = #0x1a
    19ac:      	rsb.w	r3, lr, #0x0
    19b0:      	and	r3, r3, #0x1f
    19b4:      	lsl.w	r2, r8, lr
    19b8:      	lsr.w	r3, r0, r3
    19bc:      	lsl.w	r5, r5, lr
    19c0:      	orr.w	r8, r2, r3
    19c4:      	lsl.w	r0, r0, lr
    19c8:      	lsrs	r4, r5, #0x10
    19ca:      	str	r5, [sp, #0x10]
    19cc:      	uxth.w	r12, r5
    19d0:      	udiv	r5, r8, r4
    19d4:      	lsr.w	r10, r0, #0x10
    19d8:      	mls	r6, r5, r4, r8
    19dc:      	uxth.w	r9, r0
    19e0:      	movs	r3, #0x0
    19e2:      	b	0x19f2 <compiler_rt.int.__udivmoddi4+0x1d2> @ imm = #0xc
    19e4:      	subs	r0, r5, #0x4
    19e6:      	adds	r6, r2, r4
    19e8:      	cmp.w	r3, r6, lsr #16
    19ec:      	mov	r5, r0
    19ee:      	bne.w	0x1c2e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x23c
    19f2:      	cmp.w	r3, r5, lsr #16
    19f6:      	bne	0x1a06 <compiler_rt.int.__udivmoddi4+0x1e6> @ imm = #0xc
    19f8:      	mul	r0, r5, r12
    19fc:      	orr.w	r2, r10, r6, lsl #16
    1a00:      	cmp	r0, r2
    1a02:      	bls.w	0x1c2c <compiler_rt.int.__udivmoddi4+0x40c> @ imm = #0x226
    1a06:      	adds	r2, r6, r4
    1a08:      	cmp.w	r3, r2, lsr #16
    1a0c:      	sub.w	r0, r5, #0x1
    1a10:      	bne.w	0x1c2e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x21a
    1a14:      	cmp.w	r3, r0, lsr #16
    1a18:      	bne	0x1a28 <compiler_rt.int.__udivmoddi4+0x208> @ imm = #0xc
    1a1a:      	mul	r11, r0, r12
    1a1e:      	orr.w	r6, r10, r2, lsl #16
    1a22:      	cmp	r11, r6
    1a24:      	bls.w	0x1c2e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x206
    1a28:      	add	r2, r4
    1a2a:      	cmp.w	r3, r2, lsr #16
    1a2e:      	sub.w	r0, r5, #0x2
    1a32:      	bne.w	0x1c2e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1f8
    1a36:      	cmp.w	r3, r0, lsr #16
    1a3a:      	bne	0x1a4a <compiler_rt.int.__udivmoddi4+0x22a> @ imm = #0xc
    1a3c:      	mul	r11, r0, r12
    1a40:      	orr.w	r6, r10, r2, lsl #16
    1a44:      	cmp	r11, r6
    1a46:      	bls.w	0x1c2e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1e4
    1a4a:      	add	r2, r4
    1a4c:      	cmp.w	r3, r2, lsr #16
    1a50:      	sub.w	r0, r5, #0x3
    1a54:      	bne.w	0x1c2e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1d6
    1a58:      	cmp.w	r3, r0, lsr #16
    1a5c:      	bne	0x19e4 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x7c
    1a5e:      	mul	r11, r0, r12
    1a62:      	orr.w	r6, r10, r2, lsl #16
    1a66:      	cmp	r11, r6
    1a68:      	bhi	0x19e4 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x88
    1a6a:      	b	0x1c2e <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1c0
    1a6c:      	mov	r2, r1
    1a6e:      	lsrs	r4, r5, #0x10
    1a70:      	udiv	r6, r2, r4
    1a74:      	mov	r11, r5
    1a76:      	uxth.w	r9, r5
    1a7a:      	mls	r5, r6, r4, r2
    1a7e:      	lsr.w	r8, r0, #0x10
    1a82:      	uxth.w	r12, r0
    1a86:      	mov	r1, r2
    1a88:      	movs	r3, #0x0
    1a8a:      	b	0x1a9a <compiler_rt.int.__udivmoddi4+0x27a> @ imm = #0xc
    1a8c:      	subs	r0, r6, #0x4
    1a8e:      	adds	r5, r2, r4
    1a90:      	cmp.w	r3, r5, lsr #16
    1a94:      	mov	r6, r0
    1a96:      	bne.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x22c
    1a9a:      	cmp.w	r3, r6, lsr #16
    1a9e:      	bne	0x1aae <compiler_rt.int.__udivmoddi4+0x28e> @ imm = #0xc
    1aa0:      	mul	r0, r6, r9
    1aa4:      	orr.w	r2, r8, r5, lsl #16
    1aa8:      	cmp	r0, r2
    1aaa:      	bls.w	0x1cc4 <compiler_rt.int.__udivmoddi4+0x4a4> @ imm = #0x216
    1aae:      	adds	r2, r5, r4
    1ab0:      	cmp.w	r3, r2, lsr #16
    1ab4:      	sub.w	r0, r6, #0x1
    1ab8:      	bne.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x20a
    1abc:      	cmp.w	r3, r0, lsr #16
    1ac0:      	bne	0x1ad0 <compiler_rt.int.__udivmoddi4+0x2b0> @ imm = #0xc
    1ac2:      	mul	r10, r0, r9
    1ac6:      	orr.w	r5, r8, r2, lsl #16
    1aca:      	cmp	r10, r5
    1acc:      	bls.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1f6
    1ad0:      	add	r2, r4
    1ad2:      	cmp.w	r3, r2, lsr #16
    1ad6:      	sub.w	r0, r6, #0x2
    1ada:      	bne.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1e8
    1ade:      	cmp.w	r3, r0, lsr #16
    1ae2:      	bne	0x1af2 <compiler_rt.int.__udivmoddi4+0x2d2> @ imm = #0xc
    1ae4:      	mul	r10, r0, r9
    1ae8:      	orr.w	r5, r8, r2, lsl #16
    1aec:      	cmp	r10, r5
    1aee:      	bls.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1d4
    1af2:      	add	r2, r4
    1af4:      	cmp.w	r3, r2, lsr #16
    1af8:      	sub.w	r0, r6, #0x3
    1afc:      	bne.w	0x1cc6 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1c6
    1b00:      	cmp.w	r3, r0, lsr #16
    1b04:      	bne	0x1a8c <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x7c
    1b06:      	mul	r10, r0, r9
    1b0a:      	orr.w	r5, r8, r2, lsl #16
    1b0e:      	cmp	r10, r5
    1b10:      	bhi	0x1a8c <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x88
    1b12:      	b	0x1cc6 <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1b0
    1b14:      	mov	r6, r4
    1b16:      	orr.w	r2, r11, r0, lsl #16
    1b1a:      	ldr	r0, [sp]
    1b1c:      	ldr.w	r9, [sp, #0x4]
    1b20:      	mls	r2, r6, r0, r2
    1b24:      	mov.w	r8, #0x0
    1b28:      	udiv	r4, r2, lr
    1b2c:      	mls	r2, r4, lr, r2
    1b30:      	b	0x1b40 <compiler_rt.int.__udivmoddi4+0x320> @ imm = #0xc
    1b32:      	nop
    1b34:      	subs	r4, #0x4
    1b36:      	add	r2, lr
    1b38:      	cmp.w	r2, #0x10000
    1b3c:      	mov	r5, r4
    1b3e:      	bhs	0x1bb2 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x70
    1b40:      	cmp.w	r8, r4, lsr #16
    1b44:      	bne	0x1b52 <compiler_rt.int.__udivmoddi4+0x332> @ imm = #0xa
    1b46:      	mul	r1, r4, r12
    1b4a:      	orr.w	r5, r3, r2, lsl #16
    1b4e:      	cmp	r1, r5
    1b50:      	bls	0x1bb0 <compiler_rt.int.__udivmoddi4+0x390> @ imm = #0x5c
    1b52:      	add	r2, lr
    1b54:      	cmp.w	r8, r2, lsr #16
    1b58:      	sub.w	r5, r4, #0x1
    1b5c:      	bne	0x1bb2 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x52
    1b5e:      	cmp.w	r8, r5, lsr #16
    1b62:      	bne	0x1b70 <compiler_rt.int.__udivmoddi4+0x350> @ imm = #0xa
    1b64:      	mul	r1, r5, r12
    1b68:      	orr.w	r0, r3, r2, lsl #16
    1b6c:      	cmp	r1, r0
    1b6e:      	bls	0x1bb2 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x40
    1b70:      	add	r2, lr
    1b72:      	cmp.w	r8, r2, lsr #16
    1b76:      	sub.w	r5, r4, #0x2
    1b7a:      	bne	0x1bb2 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x34
    1b7c:      	cmp.w	r8, r5, lsr #16
    1b80:      	bne	0x1b8e <compiler_rt.int.__udivmoddi4+0x36e> @ imm = #0xa
    1b82:      	mul	r0, r5, r12
    1b86:      	orr.w	r1, r3, r2, lsl #16
    1b8a:      	cmp	r0, r1
    1b8c:      	bls	0x1bb2 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x22
    1b8e:      	add	r2, lr
    1b90:      	cmp.w	r8, r2, lsr #16
    1b94:      	sub.w	r5, r4, #0x3
    1b98:      	bne	0x1bb2 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x16
    1b9a:      	cmp.w	r8, r5, lsr #16
    1b9e:      	bne	0x1b34 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x6e
    1ba0:      	mul	r0, r5, r12
    1ba4:      	orr.w	r1, r3, r2, lsl #16
    1ba8:      	cmp	r0, r1
    1baa:      	bhi	0x1b34 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x7a
    1bac:      	b	0x1bb2 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x2
    1bae:      	nop
    1bb0:      	mov	r5, r4
    1bb2:      	add.w	r0, r5, r6, lsl #16
    1bb6:      	ldr	r2, [sp, #0x10]
    1bb8:      	ldr	r6, [sp, #0x8]
    1bba:      	umull	r4, r1, r2, r0
    1bbe:      	mov	r8, r0
    1bc0:      	umull	r0, r3, r6, r0
    1bc4:      	adds	r5, r0, r1
    1bc6:      	mov.w	r12, #0x0
    1bca:      	adc	r0, r12, #0x0
    1bce:      	orrs.w	r1, r3, r0
    1bd2:      	ldr	r3, [r7, #0x8]
    1bd4:      	ldr.w	lr, [sp, #0xc]
    1bd8:      	strb.w	r0, [sp, #0x14]
    1bdc:      	bne	0x1be8 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x8
    1bde:      	cmp	r5, lr
    1be0:      	bhi	0x1be8 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x4
    1be2:      	bne	0x1bfe <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x18
    1be4:      	cmp	r4, r9
    1be6:      	bls	0x1bfe <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x14
    1be8:      	subs	r4, r4, r2
    1bea:      	adc	r0, r12, #0x0
    1bee:      	eor	r0, r0, #0x1
    1bf2:      	strb.w	r0, [sp, #0x18]
    1bf6:      	add	r0, r6
    1bf8:      	sub.w	r8, r8, #0x1
    1bfc:      	subs	r5, r5, r0
    1bfe:      	cbz	r3, 0x1c1e <compiler_rt.int.__udivmoddi4+0x3fe> @ imm = #0x1c
    1c00:      	subs.w	r0, r9, r4
    1c04:      	mov.w	r1, #0x0
    1c08:      	adc	r1, r1, #0x0
    1c0c:      	eor	r1, r1, #0x1
    1c10:      	strb.w	r1, [sp, #0x1c]
    1c14:      	add	r1, r5
    1c16:      	sub.w	r1, lr, r1
    1c1a:      	strd	r0, r1, [r3]
    1c1e:      	movs	r1, #0x0
    1c20:      	mov	r0, r8
    1c22:      	add	sp, #0x20
    1c24:      	pop.w	{r8, r9, r10, r11}
    1c28:      	pop	{r4, r5, r6, r7, pc}
    1c2a:      	nop
    1c2c:      	mov	r0, r5
    1c2e:      	ldr	r3, [sp, #0x10]
    1c30:      	orr.w	r2, r10, r8, lsl #16
    1c34:      	mls	r8, r0, r3, r2
    1c38:      	mov.w	r10, #0x0
    1c3c:      	udiv	r3, r8, r4
    1c40:      	mls	r5, r3, r4, r8
    1c44:      	b	0x1c56 <compiler_rt.int.__udivmoddi4+0x436> @ imm = #0xe
    1c46:      	nop
    1c48:      	subs	r3, #0x4
    1c4a:      	adds	r5, r2, r4
    1c4c:      	cmp.w	r5, #0x10000
    1c50:      	mov	r6, r3
    1c52:      	bhs.w	0x1d5a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x104
    1c56:      	cmp.w	r10, r3, lsr #16
    1c5a:      	bne	0x1c68 <compiler_rt.int.__udivmoddi4+0x448> @ imm = #0xa
    1c5c:      	mul	r2, r3, r12
    1c60:      	orr.w	r6, r9, r5, lsl #16
    1c64:      	cmp	r2, r6
    1c66:      	bls	0x1d58 <compiler_rt.int.__udivmoddi4+0x538> @ imm = #0xee
    1c68:      	adds	r2, r5, r4
    1c6a:      	cmp.w	r10, r2, lsr #16
    1c6e:      	sub.w	r6, r3, #0x1
    1c72:      	bne	0x1d5a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xe4
    1c74:      	cmp.w	r10, r6, lsr #16
    1c78:      	bne	0x1c86 <compiler_rt.int.__udivmoddi4+0x466> @ imm = #0xa
    1c7a:      	mul	r11, r6, r12
    1c7e:      	orr.w	r5, r9, r2, lsl #16
    1c82:      	cmp	r11, r5
    1c84:      	bls	0x1d5a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xd2
    1c86:      	add	r2, r4
    1c88:      	cmp.w	r10, r2, lsr #16
    1c8c:      	sub.w	r6, r3, #0x2
    1c90:      	bne	0x1d5a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xc6
    1c92:      	cmp.w	r10, r6, lsr #16
    1c96:      	bne	0x1ca4 <compiler_rt.int.__udivmoddi4+0x484> @ imm = #0xa
    1c98:      	mul	r11, r6, r12
    1c9c:      	orr.w	r5, r9, r2, lsl #16
    1ca0:      	cmp	r11, r5
    1ca2:      	bls	0x1d5a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xb4
    1ca4:      	add	r2, r4
    1ca6:      	cmp.w	r10, r2, lsr #16
    1caa:      	sub.w	r6, r3, #0x3
    1cae:      	bne	0x1d5a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xa8
    1cb0:      	cmp.w	r10, r6, lsr #16
    1cb4:      	bne	0x1c48 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x70
    1cb6:      	mul	r11, r6, r12
    1cba:      	orr.w	r5, r9, r2, lsl #16
    1cbe:      	cmp	r11, r5
    1cc0:      	bhi	0x1c48 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x7c
    1cc2:      	b	0x1d5a <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x94
    1cc4:      	mov	r0, r6
    1cc6:      	orr.w	r1, r8, r1, lsl #16
    1cca:      	mls	r8, r0, r11, r1
    1cce:      	mov.w	r10, #0x0
    1cd2:      	udiv	r1, r8, r4
    1cd6:      	mls	r5, r1, r4, r8
    1cda:      	b	0x1ce8 <compiler_rt.int.__udivmoddi4+0x4c8> @ imm = #0xa
    1cdc:      	subs	r1, #0x4
    1cde:      	adds	r5, r2, r4
    1ce0:      	cmp.w	r5, #0x10000
    1ce4:      	mov	r6, r1
    1ce6:      	bhs	0x1d6e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x84
    1ce8:      	cmp.w	r10, r1, lsr #16
    1cec:      	bne	0x1cfa <compiler_rt.int.__udivmoddi4+0x4da> @ imm = #0xa
    1cee:      	mul	r2, r1, r9
    1cf2:      	orr.w	r6, r12, r5, lsl #16
    1cf6:      	cmp	r2, r6
    1cf8:      	bls	0x1d6c <compiler_rt.int.__udivmoddi4+0x54c> @ imm = #0x70
    1cfa:      	adds	r2, r5, r4
    1cfc:      	cmp.w	r10, r2, lsr #16
    1d00:      	sub.w	r6, r1, #0x1
    1d04:      	bne	0x1d6e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x66
    1d06:      	cmp.w	r10, r6, lsr #16
    1d0a:      	bne	0x1d18 <compiler_rt.int.__udivmoddi4+0x4f8> @ imm = #0xa
    1d0c:      	mul	r5, r6, r9
    1d10:      	orr.w	r3, r12, r2, lsl #16
    1d14:      	cmp	r5, r3
    1d16:      	bls	0x1d6e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x54
    1d18:      	add	r2, r4
    1d1a:      	cmp.w	r10, r2, lsr #16
    1d1e:      	sub.w	r6, r1, #0x2
    1d22:      	bne	0x1d6e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x48
    1d24:      	cmp.w	r10, r6, lsr #16
    1d28:      	bne	0x1d36 <compiler_rt.int.__udivmoddi4+0x516> @ imm = #0xa
    1d2a:      	mul	r3, r6, r9
    1d2e:      	orr.w	r5, r12, r2, lsl #16
    1d32:      	cmp	r3, r5
    1d34:      	bls	0x1d6e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x36
    1d36:      	add	r2, r4
    1d38:      	cmp.w	r10, r2, lsr #16
    1d3c:      	sub.w	r6, r1, #0x3
    1d40:      	bne	0x1d6e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x2a
    1d42:      	cmp.w	r10, r6, lsr #16
    1d46:      	bne	0x1cdc <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x6e
    1d48:      	mul	r3, r6, r9
    1d4c:      	orr.w	r5, r12, r2, lsl #16
    1d50:      	cmp	r3, r5
    1d52:      	bhi	0x1cdc <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x7a
    1d54:      	b	0x1d6e <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x16
    1d56:      	nop
    1d58:      	mov	r6, r3
    1d5a:      	ldr	r3, [sp, #0x10]
    1d5c:      	orr.w	r2, r9, r8, lsl #16
    1d60:      	mls	r2, r6, r3, r2
    1d64:      	lsr.w	r2, r2, lr
    1d68:      	b	0x1d7c <compiler_rt.int.__udivmoddi4+0x55c> @ imm = #0x10
    1d6a:      	nop
    1d6c:      	mov	r6, r1
    1d6e:      	orr.w	r1, r12, r8, lsl #16
    1d72:      	mls	r1, r6, r11, r1
    1d76:      	lsr.w	r2, r1, lr
    1d7a:      	movs	r1, #0x0
    1d7c:      	ldr	r5, [r7, #0x8]
    1d7e:      	add.w	r0, r6, r0, lsl #16
    1d82:      	cmp	r5, #0x0
    1d84:      	itt	ne
    1d86:      	movne	r3, #0x0
    1d88:      	strdne	r2, r3, [r5]
    1d8c:      	add	sp, #0x20
    1d8e:      	pop.w	{r8, r9, r10, r11}
    1d92:      	pop	{r4, r5, r6, r7, pc}
    1d94:      	bmi	0x1d40 <compiler_rt.int.__udivmoddi4+0x520> @ imm = #-0x58
    1d96:      	bmi	0x1d42 <compiler_rt.int.__udivmoddi4+0x522> @ imm = #-0x58
    1d98:      	bmi	0x1d44 <compiler_rt.int.__udivmoddi4+0x524> @ imm = #-0x58
    1d9a:      	bmi	0x1d46 <compiler_rt.int.__udivmoddi4+0x526> @ imm = #-0x58
    1d9c:      	bmi	0x1d48 <compiler_rt.int.__udivmoddi4+0x528> @ imm = #-0x58
    1d9e:      	bmi	0x1d4a <compiler_rt.int.__udivmoddi4+0x52a> @ imm = #-0x58

00001da0 <.L.str.1>:
    1da0: 00 00 00 00 10 00 00 00         ........
    1da8: 69 6e 74 65 67 65 72 20         integer 
    1db0: 6f 76 65 72 66 6c 6f 77         overflow
    1db8: 00 00 00 00                     ....

00001dbc <.L.str.4>:
    1dbc: 00 00 00 00 00 00 00 00         ........
    1dc4: 00 00 00 00 d4 d4 d4 d4         ........
    1dcc: d4 d4 d4 d4                     ....

00001dd0 <.L.str.5>:
    1dd0: 00 00 00 00 0b 00 00 00         ........
    1dd8: 66 69 72 20 72 65 73 75         fir resu
    1de0: 6c 74 3d 00 00 00 00 00         lt=.....
    1de8: 07 00 00 00 20 74 69 63         .... tic
    1df0: 6b 73 3d 00 6f 75 74 20         ks=.out 
    1df8: 6f 66 20 6d 65 6d 6f 72         of memor
    1e00: 79 00 68 61 72 64 20 66         y.hard f
    1e08: 61 75 6c 74 00 20 61 6c         ault. al
    1e10: 6c 6f 63 61 74 69 6f 6e         location
    1e18: 73 3d 00 20 73 74 61 63         s=. stac
    1e20: 6b 3d 00 23 7a 73 20 68         k=.#zs h
    1e28: 65 61 70 5f 70 65 61 6b         eap_peak
    1e30: 3d 00 20 6c 69 76 65 3d         =. live=
    1e38: 00 20 68 65 61 70 5f 72         . heap_r
    1e40: 65 73 65 72 76 65 64 3d         eserved=
    1e48: 00 70 61 6e 69 63 3a 20         .panic: 
    1e50: 00 0a 00 d4                     ....
