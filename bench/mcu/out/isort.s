
bench/mcu/out/isort.elf:	file format elf32-littlearm

Disassembly of section .text:

00000000 <vectors>:
       0: 00 00 40 20 e1 0e 00 00         ..@ ....
       8: 29 10 00 00 29 10 00 00         )...)...
      10: 29 10 00 00 29 10 00 00         )...)...
      18: 29 10 00 00 00 00 00 00         ).......
      20: 00 00 00 00 00 00 00 00         ........
      28: 00 00 00 00 29 10 00 00         ....)...
      30: 29 10 00 00 00 00 00 00         ).......
      38: 29 10 00 00 39 10 00 00         )...9...

00000040 <.Lcopy.array<i32>>:
      40:      	push	{r4, r5, r6, lr}
      42:      	mov	r5, r0
      44:      	ldr	r0, [r0, #0x4]
      46:      	movs	r1, #0x8
      48:      	add.w	r6, r1, r0, lsl #2
      4c:      	mov	r0, r6
      4e:      	bl	0x2f4 <zs_alloc>        @ imm = #0x2a2
      52:      	mov	r1, r5
      54:      	mov	r2, r6
      56:      	mov	r4, r0
      58:      	bl	0x1538 <compiler_rt.arm.__aeabi_memcpy> @ imm = #0x14dc
      5c:      	movs	r1, #0x1
      5e:      	str	r1, [r4]
      60:      	ldr	r1, [r5]
      62:      	cbz	r1, 0x6e <.Lcopy.array<i32>+0x2e> @ imm = #0x8
      64:      	cmp	r1, #0x1
      66:      	bne	0x72 <.Lcopy.array<i32>+0x32> @ imm = #0x8
      68:      	mov	r0, r5
      6a:      	bl	0x3e4 <zs_free>         @ imm = #0x376
      6e:      	mov	r0, r4
      70:      	pop	{r4, r5, r6, pc}
      72:      	subs	r1, #0x1
      74:      	mov	r0, r4
      76:      	str	r1, [r5]
      78:      	pop	{r4, r5, r6, pc}
      7a:      	bmi	0x26 <vectors+0x26>     @ imm = #-0x58

0000007c <main>:
      7c:      	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
      80:      	sub	sp, #0xc
      82:      	bl	0xed8 <zs_set_args>     @ imm = #0xe52
      86:      	movw	r0, #0x808
      8a:      	bl	0x2f4 <zs_alloc>        @ imm = #0x266
      8e:      	mov	r4, r0
      90:      	movs	r6, #0x1
      92:      	mov.w	r0, #0x200
      96:      	strd	r6, r0, [r4]
      9a:      	add.w	r0, r4, #0x8
      9e:      	mov.w	r1, #0x800
      a2:      	bl	0x1528 <compiler_rt.arm.__aeabi_memclr> @ imm = #0x1482
      a6:      	movw	r8, #0x4585
      aa:      	movs	r5, #0x0
      ac:      	movt	r8, #0x3ce
      b0:      	movw	r10, #0x3f1
      b4:      	movw	r11, #0x1ff
      b8:      	movw	r9, #0x1eef
      bc:      	movs	r7, #0x0
      be:      	nop
      c0:      	cmp	r6, #0x1
      c2:      	umull	r0, r6, r5, r8
      c6:      	bne	0xee <main+0x72>        @ imm = #0x24
      c8:      	ldr	r0, [r4, #0x4]
      ca:      	cmp	r7, r0
      cc:      	bhs.w	0x2d6 <main+0x25a>      @ imm = #0x206
      d0:      	subs	r0, r5, r6
      d2:      	add.w	r0, r6, r0, lsr #1
      d6:      	lsrs	r0, r0, #0x9
      d8:      	mls	r0, r0, r10, r5
      dc:      	add.w	r1, r4, r7, lsl #2
      e0:      	cmp	r7, r11
      e2:      	str	r0, [r1, #0x8]
      e4:      	beq	0xf8 <main+0x7c>        @ imm = #0x10
      e6:      	ldr	r6, [r4]
      e8:      	add	r5, r9
      ea:      	adds	r7, #0x1
      ec:      	b	0xc0 <main+0x44>        @ imm = #-0x30
      ee:      	mov	r0, r4
      f0:      	bl	0x40 <.Lcopy.array<i32>> @ imm = #-0xb4
      f4:      	mov	r4, r0
      f6:      	b	0xc8 <main+0x4c>        @ imm = #-0x32
      f8:      	bl	0xfd0 <zs_ticks>        @ imm = #0xed4
      fc:      	ldr.w	r10, [r4, #0x4]
     100:      	str	r0, [sp, #0x8]
     102:      	cmp.w	r10, #0x2
     106:      	str	r1, [sp, #0x4]
     108:      	blo	0x194 <main+0x118>      @ imm = #0x88
     10a:      	movs	r6, #0x1
     10c:      	mov.w	r8, #0x0
     110:      	mov	r0, r10
     112:      	nop
     114:      	cmp	r6, r0
     116:      	bhs.w	0x2d6 <main+0x25a>      @ imm = #0x1bc
     11a:      	add.w	r1, r4, r6, lsl #2
     11e:      	ldr	r5, [r1, #0x8]
     120:      	mov	r11, r8
     122:      	nop
     124:      	cmp	r11, r0
     126:      	bhs.w	0x2d6 <main+0x25a>      @ imm = #0x1ac
     12a:      	add.w	r1, r4, r11, lsl #2
     12e:      	ldr.w	r9, [r1, #0x8]
     132:      	add.w	r7, r11, #0x1
     136:      	cmp	r9, r5
     138:      	ble	0x16a <main+0xee>       @ imm = #0x2e
     13a:      	ldr	r1, [r4]
     13c:      	cmp	r1, #0x1
     13e:      	bne	0x158 <main+0xdc>       @ imm = #0x16
     140:      	cmp	r7, r0
     142:      	bhs.w	0x2d6 <main+0x25a>      @ imm = #0x190
     146:      	add.w	r1, r4, r11, lsl #2
     14a:      	cmp	r7, #0x1
     14c:      	sub.w	r11, r11, #0x1
     150:      	str.w	r9, [r1, #0xc]
     154:      	bgt	0x124 <main+0xa8>       @ imm = #-0x34
     156:      	b	0x168 <main+0xec>       @ imm = #0xe
     158:      	mov	r0, r4
     15a:      	bl	0x40 <.Lcopy.array<i32>> @ imm = #-0x11e
     15e:      	mov	r4, r0
     160:      	ldr	r0, [r0, #0x4]
     162:      	cmp	r7, r0
     164:      	blo	0x146 <main+0xca>       @ imm = #-0x22
     166:      	b	0x2d6 <main+0x25a>      @ imm = #0x16c
     168:      	movs	r7, #0x0
     16a:      	ldr	r0, [r4]
     16c:      	cmp	r0, #0x1
     16e:      	bne	0x18a <main+0x10e>      @ imm = #0x18
     170:      	ldr	r0, [r4, #0x4]
     172:      	cmp	r7, r0
     174:      	bhs.w	0x2d6 <main+0x25a>      @ imm = #0x15e
     178:      	adds	r6, #0x1
     17a:      	add.w	r1, r4, r7, lsl #2
     17e:      	cmp	r6, r10
     180:      	add.w	r8, r8, #0x1
     184:      	str	r5, [r1, #0x8]
     186:      	bne	0x114 <main+0x98>       @ imm = #-0x76
     188:      	b	0x194 <main+0x118>      @ imm = #0x8
     18a:      	mov	r0, r4
     18c:      	bl	0x40 <.Lcopy.array<i32>> @ imm = #-0x150
     190:      	mov	r4, r0
     192:      	b	0x170 <main+0xf4>       @ imm = #-0x26
     194:      	ldr	r0, [r4]
     196:      	cbz	r0, 0x1a2 <main+0x126>  @ imm = #0x8
     198:      	subs.w	r1, r0, #0xffffffff
     19c:      	it	ne
     19e:      	movne	r1, r0
     1a0:      	str	r1, [r4]
     1a2:      	bl	0xfd0 <zs_ticks>        @ imm = #0xe2a
     1a6:      	ldr	r2, [r4, #0x4]
     1a8:      	cmp	r2, #0x0
     1aa:      	beq.w	0x2d6 <main+0x25a>      @ imm = #0x128
     1ae:      	cmp	r2, #0xff
     1b0:      	bls.w	0x2d6 <main+0x25a>      @ imm = #0x122
     1b4:      	mov	r10, r0
     1b6:      	mov	r5, r1
     1b8:      	ldr	r0, [r4, #0x8]
     1ba:      	ldr.w	r1, [r4, #0x404]
     1be:      	adds	r0, r0, r1
     1c0:      	bvs.w	0x2e4 <main+0x268>      @ imm = #0x120
     1c4:      	movs	r1, #0x0
     1c6:      	cmp.w	r1, r2, lsr #9
     1ca:      	beq.w	0x2d6 <main+0x25a>      @ imm = #0x108
     1ce:      	ldr.w	r1, [r4, #0x804]
     1d2:      	adds	r0, r0, r1
     1d4:      	bvs.w	0x2e4 <main+0x268>      @ imm = #0x10c
     1d8:      	asrs	r1, r0, #0x1f
     1da:      	bl	0x954 <zs_str_of_i64>   @ imm = #0x776
     1de:      	mov	r6, r0
     1e0:      	movw	r0, #0x1c00
     1e4:      	movt	r0, #0x0
     1e8:      	mov	r1, r6
     1ea:      	bl	0x434 <zs_str_concat>   @ imm = #0x246
     1ee:      	ldr	r1, [r6]
     1f0:      	mov	r7, r0
     1f2:      	cbz	r1, 0x204 <main+0x188>  @ imm = #0xe
     1f4:      	cmp	r1, #0x1
     1f6:      	bne	0x200 <main+0x184>      @ imm = #0x6
     1f8:      	mov	r0, r6
     1fa:      	bl	0x3e4 <zs_free>         @ imm = #0x1e6
     1fe:      	b	0x204 <main+0x188>      @ imm = #0x2
     200:      	subs	r0, r1, #0x1
     202:      	str	r0, [r6]
     204:      	movw	r1, #0x1c18
     208:      	movt	r1, #0x0
     20c:      	mov	r0, r7
     20e:      	bl	0x434 <zs_str_concat>   @ imm = #0x222
     212:      	ldr	r1, [r7]
     214:      	mov	r6, r0
     216:      	cbz	r1, 0x228 <main+0x1ac>  @ imm = #0xe
     218:      	cmp	r1, #0x1
     21a:      	bne	0x224 <main+0x1a8>      @ imm = #0x6
     21c:      	mov	r0, r7
     21e:      	bl	0x3e4 <zs_free>         @ imm = #0x1c2
     222:      	b	0x228 <main+0x1ac>      @ imm = #0x2
     224:      	subs	r0, r1, #0x1
     226:      	str	r0, [r7]
     228:      	ldr	r0, [sp, #0x8]
     22a:      	ldr	r1, [sp, #0x4]
     22c:      	subs.w	r0, r10, r0
     230:      	sbcs.w	r1, r5, r1
     234:      	mov.w	r2, #0x0
     238:      	adc	r2, r2, #0x0
     23c:      	eor	r2, r2, #0x1
     240:      	cmp	r2, #0x1
     242:      	beq	0x2e4 <main+0x268>      @ imm = #0x9e
     244:      	bl	0x610 <zs_str_of_u64>   @ imm = #0x3c8
     248:      	mov	r7, r0
     24a:      	mov	r0, r6
     24c:      	mov	r1, r7
     24e:      	bl	0x434 <zs_str_concat>   @ imm = #0x1e2
     252:      	ldr	r1, [r6]
     254:      	mov	r5, r0
     256:      	cbz	r1, 0x268 <main+0x1ec>  @ imm = #0xe
     258:      	cmp	r1, #0x1
     25a:      	bne	0x264 <main+0x1e8>      @ imm = #0x6
     25c:      	mov	r0, r6
     25e:      	bl	0x3e4 <zs_free>         @ imm = #0x182
     262:      	b	0x268 <main+0x1ec>      @ imm = #0x2
     264:      	subs	r0, r1, #0x1
     266:      	str	r0, [r6]
     268:      	ldr	r0, [r7]
     26a:      	cbz	r0, 0x27c <main+0x200>  @ imm = #0xe
     26c:      	cmp	r0, #0x1
     26e:      	bne	0x278 <main+0x1fc>      @ imm = #0x6
     270:      	mov	r0, r7
     272:      	bl	0x3e4 <zs_free>         @ imm = #0x16e
     276:      	b	0x27c <main+0x200>      @ imm = #0x2
     278:      	subs	r0, #0x1
     27a:      	str	r0, [r7]
     27c:      	movw	r0, #0x1bec
     280:      	movt	r0, #0x0
     284:      	mov	r1, r5
     286:      	bl	0x434 <zs_str_concat>   @ imm = #0x1aa
     28a:      	ldr	r1, [r5]
     28c:      	mov	r6, r0
     28e:      	cbz	r1, 0x2a0 <main+0x224>  @ imm = #0xe
     290:      	cmp	r1, #0x1
     292:      	bne	0x29c <main+0x220>      @ imm = #0x6
     294:      	mov	r0, r5
     296:      	bl	0x3e4 <zs_free>         @ imm = #0x14a
     29a:      	b	0x2a0 <main+0x224>      @ imm = #0x2
     29c:      	subs	r0, r1, #0x1
     29e:      	str	r0, [r5]
     2a0:      	mov	r0, r6
     2a2:      	bl	0xb7c <zs_println>      @ imm = #0x8d6
     2a6:      	ldr	r0, [r6]
     2a8:      	cbz	r0, 0x2ba <main+0x23e>  @ imm = #0xe
     2aa:      	cmp	r0, #0x1
     2ac:      	bne	0x2b6 <main+0x23a>      @ imm = #0x6
     2ae:      	mov	r0, r6
     2b0:      	bl	0x3e4 <zs_free>         @ imm = #0x130
     2b4:      	b	0x2ba <main+0x23e>      @ imm = #0x2
     2b6:      	subs	r0, #0x1
     2b8:      	str	r0, [r6]
     2ba:      	ldr	r0, [r4]
     2bc:      	cbz	r0, 0x2ce <main+0x252>  @ imm = #0xe
     2be:      	cmp	r0, #0x1
     2c0:      	bne	0x2ca <main+0x24e>      @ imm = #0x6
     2c2:      	mov	r0, r4
     2c4:      	bl	0x3e4 <zs_free>         @ imm = #0x11c
     2c8:      	b	0x2ce <main+0x252>      @ imm = #0x2
     2ca:      	subs	r0, #0x1
     2cc:      	str	r0, [r4]
     2ce:      	movs	r0, #0x0
     2d0:      	add	sp, #0xc
     2d2:      	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
     2d6:      	movw	r0, #0x1bd0
     2da:      	movt	r0, #0x0
     2de:      	adds	r0, #0x8
     2e0:      	bl	0x3b8 <zs_panic_c>      @ imm = #0xd4
     2e4:      	movw	r0, #0x1bb0
     2e8:      	movt	r0, #0x0
     2ec:      	adds	r0, #0x8
     2ee:      	bl	0x3b8 <zs_panic_c>      @ imm = #0xc6
     2f2:      	bmi	0x29e <main+0x222>      @ imm = #-0x58

000002f4 <zs_alloc>:
     2f4:      	push	{r4, r6, r7, lr}
     2f6:      	add	r7, sp, #0x8
     2f8:      	adds	r0, #0x7
     2fa:      	lsrs	r2, r0, #0x3
     2fc:      	cmp	r2, #0x20
     2fe:      	bhi	0x31c <zs_alloc+0x28>   @ imm = #0x1a
     300:      	movw	r12, #0x0
     304:      	movt	r12, #0x2000
     308:      	ldr.w	r1, [r12, r2, lsl #2]
     30c:      	cbz	r1, 0x31c <zs_alloc+0x28> @ imm = #0xc
     30e:      	mov	r0, r1
     310:      	ldr	r3, [r1]
     312:      	ldr	r1, [r0, #-8]!
     316:      	str.w	r3, [r12, r2, lsl #2]
     31a:      	b	0x354 <zs_alloc+0x60>   @ imm = #0x36
     31c:      	movw	r12, #0x84
     320:      	movt	r12, #0x2000
     324:      	ldr.w	r2, [r12]
     328:      	bic	r1, r0, #0x7
     32c:      	adds	r3, r1, r2
     32e:      	movw	r0, #0xfff9
     332:      	subs	r0, r3, r0
     334:      	cmn.w	r0, #0x10001
     338:      	blo	0x3aa <zs_alloc+0xb6>   @ imm = #0x6e
     33a:      	movw	lr, #0x88
     33e:      	movt	lr, #0x2000
     342:      	add.w	r0, lr, r2
     346:      	adds	r3, #0x8
     348:      	str.w	r1, [lr, r2]
     34c:      	movs	r2, #0x0
     34e:      	str.w	r3, [r12]
     352:      	str	r2, [r0, #0x4]
     354:      	movw	lr, #0x88
     358:      	movt	lr, #0x2001
     35c:      	ldr.w	r2, [lr]
     360:      	movw	r12, #0x8c
     364:      	movt	r12, #0x2001
     368:      	ldr.w	r3, [r12]
     36c:      	add	r1, r2
     36e:      	str.w	r1, [lr]
     372:      	movw	lr, #0x90
     376:      	cmp	r1, r3
     378:      	it	hi
     37a:      	strhi.w	r1, [r12]
     37e:      	movt	lr, #0x2001
     382:      	movw	r12, #0x98
     386:      	ldrd	r2, r3, [lr]
     38a:      	movt	r12, #0x2001
     38e:      	ldrd	r1, r4, [r12]
     392:      	adds	r2, #0x1
     394:      	adc	r3, r3, #0x0
     398:      	adds	r1, #0x1
     39a:      	strd	r2, r3, [lr]
     39e:      	adc	r2, r4, #0x0
     3a2:      	adds	r0, #0x8
     3a4:      	strd	r1, r2, [r12]
     3a8:      	pop	{r4, r6, r7, pc}
     3aa:      	movw	r0, #0x1c28
     3ae:      	movt	r0, #0x0
     3b2:      	bl	0x3b8 <zs_panic_c>      @ imm = #0x2
     3b6:      	bmi	0x362 <zs_alloc+0x6e>   @ imm = #-0x58

000003b8 <zs_panic_c>:
     3b8:      	push	{r4, r6, r7, lr}
     3ba:      	add	r7, sp, #0x8
     3bc:      	mov	r4, r0
     3be:      	movw	r0, #0x1c7d
     3c2:      	movt	r0, #0x0
     3c6:      	bl	0xc98 <write_c>         @ imm = #0x8ce
     3ca:      	mov	r0, r4
     3cc:      	bl	0xc98 <write_c>         @ imm = #0x8c8
     3d0:      	movw	r0, #0x1c85
     3d4:      	movt	r0, #0x0
     3d8:      	bl	0xc98 <write_c>         @ imm = #0x8bc
     3dc:      	movs	r0, #0x86
     3de:      	bl	0xddc <stop>            @ imm = #0x9fa
     3e2:      	bmi	0x38e <zs_alloc+0x9a>   @ imm = #-0x58

000003e4 <zs_free>:
     3e4:      	push	{r4, r6, r7, lr}
     3e6:      	add	r7, sp, #0x8
     3e8:      	movw	lr, #0x88
     3ec:      	movw	r12, #0x90
     3f0:      	movt	lr, #0x2001
     3f4:      	movt	r12, #0x2001
     3f8:      	ldr	r1, [r0, #-8]
     3fc:      	ldr.w	r3, [lr]
     400:      	ldrd	r2, r4, [r12]
     404:      	subs	r3, r3, r1
     406:      	subs	r2, #0x1
     408:      	str.w	r3, [lr]
     40c:      	sbc	r3, r4, #0x0
     410:      	lsrs	r4, r1, #0x3
     412:      	cmp	r4, #0x20
     414:      	strd	r2, r3, [r12]
     418:      	it	hi
     41a:      	pophi	{r4, r6, r7, pc}
     41c:      	mvn	r2, #0x3
     420:      	and.w	r1, r2, r1, lsr #1
     424:      	movw	r2, #0x0
     428:      	movt	r2, #0x2000
     42c:      	ldr	r3, [r2, r1]
     42e:      	str	r3, [r0]
     430:      	str	r0, [r2, r1]
     432:      	pop	{r4, r6, r7, pc}

00000434 <zs_str_concat>:
     434:      	push	{r4, r5, r6, r7, lr}
     436:      	add	r7, sp, #0xc
     438:      	push.w	{r8, r9, r11}
     43c:      	mov	lr, r0
     43e:      	ldr	r0, [r0, #0x4]
     440:      	ldr	r2, [r1, #0x4]
     442:      	add.w	r9, r2, r0
     446:      	add.w	r0, r9, #0x10
     44a:      	lsrs	r6, r0, #0x3
     44c:      	cmp	r6, #0x20
     44e:      	bhi	0x46c <zs_str_concat+0x38> @ imm = #0x1a
     450:      	movw	r5, #0x0
     454:      	movt	r5, #0x2000
     458:      	ldr.w	r3, [r5, r6, lsl #2]
     45c:      	cbz	r3, 0x46c <zs_str_concat+0x38> @ imm = #0xc
     45e:      	mov	r8, r3
     460:      	ldr	r3, [r3]
     462:      	ldr	r0, [r8, #-8]!
     466:      	str.w	r3, [r5, r6, lsl #2]
     46a:      	b	0x4a2 <zs_str_concat+0x6e> @ imm = #0x34
     46c:      	movw	r5, #0x84
     470:      	movt	r5, #0x2000
     474:      	ldr	r6, [r5]
     476:      	bic	r0, r0, #0x7
     47a:      	adds	r4, r0, r6
     47c:      	movw	r3, #0xfff9
     480:      	subs	r3, r4, r3
     482:      	cmn.w	r3, #0x10001
     486:      	blo.w	0x602 <zs_str_concat+0x1ce> @ imm = #0x178
     48a:      	movw	r3, #0x88
     48e:      	movt	r3, #0x2000
     492:      	add.w	r8, r3, r6
     496:      	adds	r4, #0x8
     498:      	str	r0, [r3, r6]
     49a:      	movs	r3, #0x0
     49c:      	str	r4, [r5]
     49e:      	str.w	r3, [r8, #0x4]
     4a2:      	movw	r3, #0x88
     4a6:      	movt	r3, #0x2001
     4aa:      	movw	r6, #0x8c
     4ae:      	ldr	r5, [r3]
     4b0:      	movt	r6, #0x2001
     4b4:      	ldr	r4, [r6]
     4b6:      	add	r0, r5
     4b8:      	cmp	r0, r4
     4ba:      	str	r0, [r3]
     4bc:      	it	hi
     4be:      	strhi	r0, [r6]
     4c0:      	movw	r0, #0x90
     4c4:      	movt	r0, #0x2001
     4c8:      	ldrd	r3, r6, [r0]
     4cc:      	movw	r5, #0x98
     4d0:      	movt	r5, #0x2001
     4d4:      	adds	r3, #0x1
     4d6:      	ldrd	r4, r2, [r5]
     4da:      	adc	r6, r6, #0x0
     4de:      	strd	r3, r6, [r0]
     4e2:      	adds	r0, r4, #0x1
     4e4:      	adc	r2, r2, #0x0
     4e8:      	strd	r0, r2, [r5]
     4ec:      	movs	r2, #0x1
     4ee:      	mov	r0, r8
     4f0:      	str	r2, [r0, #8]!
     4f4:      	add.w	r12, r0, #0x8
     4f8:      	movs	r5, #0x0
     4fa:      	str.w	r9, [r0, #0x4]
     4fe:      	strb.w	r5, [r12, r9]
     502:      	ldr.w	r4, [lr, #0x4]
     506:      	cmp	r4, #0x0
     508:      	beq	0x58c <zs_str_concat+0x158> @ imm = #0x80
     50a:      	ands	r2, r4, #0x3
     50e:      	beq	0x52c <zs_str_concat+0xf8> @ imm = #0x1a
     510:      	ldrb.w	r3, [lr, #0x8]
     514:      	cmp	r2, #0x1
     516:      	strb.w	r3, [r8, #0x10]
     51a:      	bne	0x53a <zs_str_concat+0x106> @ imm = #0x1c
     51c:      	subs	r2, r4, #0x1
     51e:      	add.w	r5, lr, #0x9
     522:      	add.w	r6, r8, #0x11
     526:      	cmp	r4, #0x4
     528:      	bhs	0x56c <zs_str_concat+0x138> @ imm = #0x40
     52a:      	b	0x588 <zs_str_concat+0x154> @ imm = #0x5a
     52c:      	add.w	r5, lr, #0x8
     530:      	mov	r6, r12
     532:      	mov	r2, r4
     534:      	cmp	r4, #0x4
     536:      	bhs	0x56c <zs_str_concat+0x138> @ imm = #0x32
     538:      	b	0x588 <zs_str_concat+0x154> @ imm = #0x4c
     53a:      	ldrb.w	r3, [lr, #0x9]
     53e:      	cmp	r2, #0x2
     540:      	strb.w	r3, [r8, #0x11]
     544:      	bne	0x556 <zs_str_concat+0x122> @ imm = #0xe
     546:      	subs	r2, r4, #0x2
     548:      	add.w	r5, lr, #0xa
     54c:      	add.w	r6, r8, #0x12
     550:      	cmp	r4, #0x4
     552:      	bhs	0x56c <zs_str_concat+0x138> @ imm = #0x16
     554:      	b	0x588 <zs_str_concat+0x154> @ imm = #0x30
     556:      	ldrb.w	r3, [lr, #0xa]
     55a:      	subs	r2, r4, #0x3
     55c:      	add.w	r5, lr, #0xb
     560:      	add.w	r6, r8, #0x13
     564:      	strb.w	r3, [r8, #0x12]
     568:      	cmp	r4, #0x4
     56a:      	blo	0x588 <zs_str_concat+0x154> @ imm = #0x1a
     56c:      	subs	r3, r5, #0x4
     56e:      	subs	r4, r6, #0x4
     570:      	ldrb	r5, [r3, #4]!
     574:      	subs	r2, #0x4
     576:      	strb	r5, [r4, #4]!
     57a:      	ldrb	r5, [r3, #0x1]
     57c:      	strb	r5, [r4, #0x1]
     57e:      	ldrb	r5, [r3, #0x2]
     580:      	strb	r5, [r4, #0x2]
     582:      	ldrb	r5, [r3, #0x3]
     584:      	strb	r5, [r4, #0x3]
     586:      	bne	0x570 <zs_str_concat+0x13c> @ imm = #-0x1a
     588:      	ldr.w	r5, [lr, #0x4]
     58c:      	ldr	r3, [r1, #0x4]
     58e:      	cbz	r3, 0x5fc <zs_str_concat+0x1c8> @ imm = #0x6a
     590:      	ands	r2, r3, #0x3
     594:      	add.w	r6, r12, r5
     598:      	beq	0x5b2 <zs_str_concat+0x17e> @ imm = #0x16
     59a:      	ldrb	r5, [r1, #0x8]
     59c:      	mov	r4, r6
     59e:      	cmp	r2, #0x1
     5a0:      	strb	r5, [r4], #1
     5a4:      	bne	0x5bc <zs_str_concat+0x188> @ imm = #0x14
     5a6:      	subs	r2, r3, #0x1
     5a8:      	adds	r1, #0x9
     5aa:      	mov	r6, r4
     5ac:      	cmp	r3, #0x4
     5ae:      	bhs	0x5de <zs_str_concat+0x1aa> @ imm = #0x2c
     5b0:      	b	0x5fc <zs_str_concat+0x1c8> @ imm = #0x48
     5b2:      	adds	r1, #0x8
     5b4:      	mov	r2, r3
     5b6:      	cmp	r3, #0x4
     5b8:      	bhs	0x5de <zs_str_concat+0x1aa> @ imm = #0x22
     5ba:      	b	0x5fc <zs_str_concat+0x1c8> @ imm = #0x3e
     5bc:      	ldrb	r5, [r1, #0x9]
     5be:      	cmp	r2, #0x2
     5c0:      	strb	r5, [r6, #0x1]
     5c2:      	bne	0x5d0 <zs_str_concat+0x19c> @ imm = #0xa
     5c4:      	subs	r2, r3, #0x2
     5c6:      	adds	r1, #0xa
     5c8:      	adds	r6, #0x2
     5ca:      	cmp	r3, #0x4
     5cc:      	bhs	0x5de <zs_str_concat+0x1aa> @ imm = #0xe
     5ce:      	b	0x5fc <zs_str_concat+0x1c8> @ imm = #0x2a
     5d0:      	ldrb	r5, [r1, #0xa]
     5d2:      	subs	r2, r3, #0x3
     5d4:      	adds	r1, #0xb
     5d6:      	strb	r5, [r6, #0x2]
     5d8:      	adds	r6, #0x3
     5da:      	cmp	r3, #0x4
     5dc:      	blo	0x5fc <zs_str_concat+0x1c8> @ imm = #0x1c
     5de:      	subs	r1, #0x4
     5e0:      	subs	r3, r6, #0x4
     5e2:      	nop
     5e4:      	ldrb	r6, [r1, #4]!
     5e8:      	subs	r2, #0x4
     5ea:      	strb	r6, [r3, #4]!
     5ee:      	ldrb	r6, [r1, #0x1]
     5f0:      	strb	r6, [r3, #0x1]
     5f2:      	ldrb	r6, [r1, #0x2]
     5f4:      	strb	r6, [r3, #0x2]
     5f6:      	ldrb	r6, [r1, #0x3]
     5f8:      	strb	r6, [r3, #0x3]
     5fa:      	bne	0x5e4 <zs_str_concat+0x1b0> @ imm = #-0x1a
     5fc:      	pop.w	{r8, r9, r11}
     600:      	pop	{r4, r5, r6, r7, pc}
     602:      	movw	r0, #0x1c28
     606:      	movt	r0, #0x0
     60a:      	bl	0x3b8 <zs_panic_c>      @ imm = #-0x256
     60e:      	bmi	0x5ba <zs_str_concat+0x186> @ imm = #-0x58

00000610 <zs_str_of_u64>:
     610:      	push	{r4, r5, r6, r7, lr}
     612:      	add	r7, sp, #0xc
     614:      	push.w	{r8, r9, r10, r11}
     618:      	sub	sp, #0x34
     61a:      	movw	r9, #0xcccd
     61e:      	mov	r5, r1
     620:      	mov	r6, r0
     622:      	mov.w	r10, #0x1
     626:      	movt	r9, #0xcccc
     62a:      	add.w	r8, sp, #0x1c
     62e:      	nop
     630:      	lsrs	r0, r6, #0x1
     632:      	orr.w	r0, r0, r5, lsl #31
     636:      	adds.w	r1, r0, r5, lsr #1
     63a:      	adc	r1, r1, #0x0
     63e:      	umull	r2, r3, r1, r9
     642:      	bic	r2, r3, #0x3
     646:      	add.w	r2, r2, r3, lsr #2
     64a:      	subs	r1, r1, r2
     64c:      	subs	r1, r0, r1
     64e:      	umull	r0, r2, r1, r9
     652:      	add.w	r4, r0, r0, lsl #2
     656:      	lsr.w	r3, r5, #0x1
     65a:      	sub.w	r4, r6, r4, lsl #1
     65e:      	sbc	r3, r3, #0x0
     662:      	orr	r12, r4, #0x30
     666:      	subs.w	r4, r6, #0xa
     66a:      	add.w	r11, r8, r10
     66e:      	sbcs	r4, r5, #0x0
     672:      	strb	r12, [r11, #-1]
     676:      	blo	0x766 <zs_str_of_u64+0x156> @ imm = #0xec
     678:      	mov.w	r4, #0xcccccccc
     67c:      	mla	r1, r1, r4, r2
     680:      	lsrs	r2, r0, #0x1
     682:      	mla	r1, r3, r9, r1
     686:      	and	r0, r0, #0x1
     68a:      	orr.w	r2, r2, r1, lsl #31
     68e:      	adds.w	r1, r2, r1, lsr #1
     692:      	adc	r1, r1, #0x0
     696:      	umull	r2, r3, r1, r9
     69a:      	bic	r2, r3, #0x3
     69e:      	add.w	r2, r2, r3, lsr #2
     6a2:      	subs	r1, r1, r2
     6a4:      	orr.w	r0, r0, r1, lsl #1
     6a8:      	subs.w	r1, r6, #0x64
     6ac:      	orr	r0, r0, #0x30
     6b0:      	sbcs	r1, r5, #0x0
     6b4:      	strb.w	r0, [r8, r10]
     6b8:      	blo	0x76e <zs_str_of_u64+0x15e> @ imm = #0xb2
     6ba:      	mov	r0, r6
     6bc:      	mov	r1, r5
     6be:      	movs	r2, #0x64
     6c0:      	movs	r3, #0x0
     6c2:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf5e
     6c6:      	lsrs	r2, r0, #0x1
     6c8:      	orr.w	r2, r2, r1, lsl #31
     6cc:      	adds.w	r1, r2, r1, lsr #1
     6d0:      	adc	r1, r1, #0x0
     6d4:      	umull	r2, r3, r1, r9
     6d8:      	bic	r2, r3, #0x3
     6dc:      	add.w	r2, r2, r3, lsr #2
     6e0:      	subs	r1, r1, r2
     6e2:      	and	r0, r0, #0x1
     6e6:      	orr.w	r0, r0, r1, lsl #1
     6ea:      	subs.w	r1, r6, #0x3e8
     6ee:      	orr	r0, r0, #0x30
     6f2:      	sbcs	r1, r5, #0x0
     6f6:      	strb.w	r0, [r11, #0x1]
     6fa:      	blo	0x776 <zs_str_of_u64+0x166> @ imm = #0x78
     6fc:      	mov	r0, r6
     6fe:      	mov	r1, r5
     700:      	mov.w	r2, #0x3e8
     704:      	movs	r3, #0x0
     706:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf1a
     70a:      	lsrs	r2, r0, #0x1
     70c:      	orr.w	r2, r2, r1, lsl #31
     710:      	adds.w	r1, r2, r1, lsr #1
     714:      	adc	r1, r1, #0x0
     718:      	umull	r2, r3, r1, r9
     71c:      	bic	r2, r3, #0x3
     720:      	add.w	r2, r2, r3, lsr #2
     724:      	subs	r1, r1, r2
     726:      	and	r0, r0, #0x1
     72a:      	orr.w	r0, r0, r1, lsl #1
     72e:      	orr	r0, r0, #0x30
     732:      	strb.w	r0, [r11, #0x2]
     736:      	mov	r0, r6
     738:      	mov	r1, r5
     73a:      	movw	r2, #0x2710
     73e:      	movs	r3, #0x0
     740:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xee0
     744:      	movw	r2, #0x270f
     748:      	subs	r2, r2, r6
     74a:      	mov.w	r2, #0x0
     74e:      	sbcs	r2, r5
     750:      	add.w	r10, r10, #0x4
     754:      	mov	r6, r0
     756:      	mov	r5, r1
     758:      	blo.w	0x630 <zs_str_of_u64+0x20> @ imm = #-0x12c
     75c:      	sub.w	r1, r10, #0x1
     760:      	sub.w	r12, r10, #0x2
     764:      	b	0x77e <zs_str_of_u64+0x16e> @ imm = #0x16
     766:      	sub.w	r12, r10, #0x1
     76a:      	mov	r1, r10
     76c:      	b	0x780 <zs_str_of_u64+0x170> @ imm = #0x10
     76e:      	add.w	r1, r10, #0x1
     772:      	mov	r12, r10
     774:      	b	0x77e <zs_str_of_u64+0x16e> @ imm = #0x6
     776:      	add.w	r1, r10, #0x2
     77a:      	add.w	r12, r10, #0x1
     77e:      	mov	r10, r1
     780:      	and	lr, r1, #0x3
     784:      	lsrs	r3, r1, #0x2
     786:      	mov.w	r1, #0x0
     78a:      	beq	0x7be <zs_str_of_u64+0x1ae> @ imm = #0x30
     78c:      	add	r6, sp, #0x4
     78e:      	add.w	r5, r12, r8
     792:      	sub.w	r9, r1, r3, lsl #2
     796:      	subs	r6, #0x3
     798:      	subs	r5, #0x1
     79a:      	nop
     79c:      	adds	r4, r5, r1
     79e:      	ldrb	r3, [r5, r1]
     7a0:      	ldrb	r0, [r4, #-2]
     7a4:      	ldrb	r2, [r4, #-1]
     7a8:      	ldrb	r4, [r4, #0x1]
     7aa:      	subs	r1, #0x4
     7ac:      	strb	r3, [r6, #4]!
     7b0:      	cmp	r9, r1
     7b2:      	strb	r4, [r6, #-1]
     7b6:      	strb	r2, [r6, #0x1]
     7b8:      	strb	r0, [r6, #0x2]
     7ba:      	bne	0x79c <zs_str_of_u64+0x18c> @ imm = #-0x22
     7bc:      	rsbs	r1, r1, #0
     7be:      	cmp.w	lr, #0x0
     7c2:      	beq	0x7f4 <zs_str_of_u64+0x1e4> @ imm = #0x2e
     7c4:      	sub.w	r0, r12, r1
     7c8:      	ldrb.w	r0, [r8, r0]
     7cc:      	add	r3, sp, #0x4
     7ce:      	cmp.w	lr, #0x1
     7d2:      	strb	r0, [r3, r1]
     7d4:      	beq	0x7f4 <zs_str_of_u64+0x1e4> @ imm = #0x1c
     7d6:      	adds	r0, r1, #0x1
     7d8:      	sub.w	r2, r12, r0
     7dc:      	ldrb.w	r2, [r8, r2]
     7e0:      	cmp.w	lr, #0x2
     7e4:      	strb	r2, [r3, r0]
     7e6:      	beq	0x7f4 <zs_str_of_u64+0x1e4> @ imm = #0xa
     7e8:      	adds	r0, r1, #0x2
     7ea:      	sub.w	r1, r12, r0
     7ee:      	ldrb.w	r1, [r8, r1]
     7f2:      	strb	r1, [r3, r0]
     7f4:      	add	r0, sp, #0x4
     7f6:      	mov	r1, r10
     7f8:      	bl	0x804 <str_of>          @ imm = #0x8
     7fc:      	add	sp, #0x34
     7fe:      	pop.w	{r8, r9, r10, r11}
     802:      	pop	{r4, r5, r6, r7, pc}

00000804 <str_of>:
     804:      	push	{r4, r5, r6, r7, lr}
     806:      	add	r7, sp, #0xc
     808:      	str	r11, [sp, #-4]!
     80c:      	add.w	r2, r1, #0x10
     810:      	lsrs	r3, r2, #0x3
     812:      	cmp	r3, #0x20
     814:      	bhi	0x832 <str_of+0x2e>     @ imm = #0x1a
     816:      	movw	lr, #0x0
     81a:      	movt	lr, #0x2000
     81e:      	ldr.w	r4, [lr, r3, lsl #2]
     822:      	cbz	r4, 0x832 <str_of+0x2e> @ imm = #0xc
     824:      	mov	r12, r4
     826:      	ldr	r4, [r4]
     828:      	ldr	r2, [r12, #-8]!
     82c:      	str.w	r4, [lr, r3, lsl #2]
     830:      	b	0x86a <str_of+0x66>     @ imm = #0x36
     832:      	movw	lr, #0x84
     836:      	movt	lr, #0x2000
     83a:      	ldr.w	r3, [lr]
     83e:      	bic	r2, r2, #0x7
     842:      	adds	r5, r2, r3
     844:      	movw	r4, #0xfff9
     848:      	subs	r4, r5, r4
     84a:      	cmn.w	r4, #0x10001
     84e:      	blo	0x948 <str_of+0x144>    @ imm = #0xf6
     850:      	movw	r4, #0x88
     854:      	movt	r4, #0x2000
     858:      	add.w	r12, r4, r3
     85c:      	adds	r5, #0x8
     85e:      	str	r2, [r4, r3]
     860:      	movs	r3, #0x0
     862:      	str.w	r5, [lr]
     866:      	str.w	r3, [r12, #0x4]
     86a:      	movw	r5, #0x88
     86e:      	movt	r5, #0x2001
     872:      	movw	lr, #0x8c
     876:      	ldr	r4, [r5]
     878:      	movt	lr, #0x2001
     87c:      	ldr.w	r3, [lr]
     880:      	add	r2, r4
     882:      	cmp	r2, r3
     884:      	str	r2, [r5]
     886:      	it	hi
     888:      	strhi.w	r2, [lr]
     88c:      	movw	lr, #0x90
     890:      	movt	lr, #0x2001
     894:      	movw	r4, #0x98
     898:      	ldrd	r3, r5, [lr]
     89c:      	movt	r4, #0x2001
     8a0:      	ldrd	r2, r6, [r4]
     8a4:      	adds	r3, #0x1
     8a6:      	adc	r5, r5, #0x0
     8aa:      	adds	r2, #0x1
     8ac:      	strd	r3, r5, [lr]
     8b0:      	adc	r3, r6, #0x0
     8b4:      	strd	r2, r3, [r4]
     8b8:      	movs	r3, #0x1
     8ba:      	mov	r2, r12
     8bc:      	str	r3, [r2, #8]!
     8c0:      	add.w	lr, r2, #0x8
     8c4:      	movs	r3, #0x0
     8c6:      	str	r1, [r2, #0x4]
     8c8:      	strb.w	r3, [lr, r1]
     8cc:      	cbz	r1, 0x940 <str_of+0x13c> @ imm = #0x70
     8ce:      	ands	r3, r1, #0x3
     8d2:      	beq	0x8f0 <str_of+0xec>     @ imm = #0x1a
     8d4:      	mov	r4, r0
     8d6:      	ldrb	r6, [r4], #1
     8da:      	cmp	r3, #0x1
     8dc:      	strb.w	r6, [r12, #0x10]
     8e0:      	bne	0x8f8 <str_of+0xf4>     @ imm = #0x14
     8e2:      	subs	r3, r1, #0x1
     8e4:      	add.w	lr, r12, #0x11
     8e8:      	mov	r0, r4
     8ea:      	cmp	r1, #0x4
     8ec:      	bhs	0x922 <str_of+0x11e>    @ imm = #0x32
     8ee:      	b	0x940 <str_of+0x13c>    @ imm = #0x4e
     8f0:      	mov	r3, r1
     8f2:      	cmp	r1, #0x4
     8f4:      	bhs	0x922 <str_of+0x11e>    @ imm = #0x2a
     8f6:      	b	0x940 <str_of+0x13c>    @ imm = #0x46
     8f8:      	ldrb	r6, [r0, #0x1]
     8fa:      	cmp	r3, #0x2
     8fc:      	strb.w	r6, [r12, #0x11]
     900:      	bne	0x910 <str_of+0x10c>    @ imm = #0xc
     902:      	subs	r3, r1, #0x2
     904:      	adds	r0, #0x2
     906:      	add.w	lr, r12, #0x12
     90a:      	cmp	r1, #0x4
     90c:      	bhs	0x922 <str_of+0x11e>    @ imm = #0x12
     90e:      	b	0x940 <str_of+0x13c>    @ imm = #0x2e
     910:      	ldrb	r4, [r0, #0x2]
     912:      	subs	r3, r1, #0x3
     914:      	adds	r0, #0x3
     916:      	add.w	lr, r12, #0x13
     91a:      	strb.w	r4, [r12, #0x12]
     91e:      	cmp	r1, #0x4
     920:      	blo	0x940 <str_of+0x13c>    @ imm = #0x1c
     922:      	subs	r0, #0x4
     924:      	sub.w	r1, lr, #0x4
     928:      	ldrb	r6, [r0, #4]!
     92c:      	subs	r3, #0x4
     92e:      	strb	r6, [r1, #4]!
     932:      	ldrb	r6, [r0, #0x1]
     934:      	strb	r6, [r1, #0x1]
     936:      	ldrb	r6, [r0, #0x2]
     938:      	strb	r6, [r1, #0x2]
     93a:      	ldrb	r6, [r0, #0x3]
     93c:      	strb	r6, [r1, #0x3]
     93e:      	bne	0x928 <str_of+0x124>    @ imm = #-0x1a
     940:      	mov	r0, r2
     942:      	ldr	r11, [sp], #4
     946:      	pop	{r4, r5, r6, r7, pc}
     948:      	movw	r0, #0x1c28
     94c:      	movt	r0, #0x0
     950:      	bl	0x3b8 <zs_panic_c>      @ imm = #-0x59c

00000954 <zs_str_of_i64>:
     954:      	push	{r4, r5, r6, r7, lr}
     956:      	add	r7, sp, #0xc
     958:      	push.w	{r8, r9, r10, r11}
     95c:      	sub	sp, #0x3c
     95e:      	cmp.w	r1, #0xffffffff
     962:      	add	r2, sp, #0xc
     964:      	ble	0x96c <zs_str_of_i64+0x18> @ imm = #0x4
     966:      	str	r2, [sp, #0x8]
     968:      	movs	r2, #0x0
     96a:      	b	0x978 <zs_str_of_i64+0x24> @ imm = #0xa
     96c:      	adds	r2, #0x1
     96e:      	str	r2, [sp, #0x8]
     970:      	movs	r2, #0x2d
     972:      	strb.w	r2, [sp, #0xc]
     976:      	movs	r2, #0x1
     978:      	eor.w	r0, r0, r1, asr #31
     97c:      	str	r2, [sp, #0x4]
     97e:      	eor.w	r2, r1, r1, asr #31
     982:      	subs.w	r4, r0, r1, asr #31
     986:      	movw	r8, #0xcccd
     98a:      	sbc.w	r5, r2, r1, asr #31
     98e:      	mov.w	r9, #0x1
     992:      	movt	r8, #0xcccc
     996:      	add.w	r10, sp, #0x24
     99a:      	nop
     99c:      	lsrs	r0, r4, #0x1
     99e:      	orr.w	r0, r0, r5, lsl #31
     9a2:      	adds.w	r1, r0, r5, lsr #1
     9a6:      	adc	r1, r1, #0x0
     9aa:      	umull	r2, r3, r1, r8
     9ae:      	bic	r2, r3, #0x3
     9b2:      	add.w	r2, r2, r3, lsr #2
     9b6:      	subs	r1, r1, r2
     9b8:      	subs	r1, r0, r1
     9ba:      	umull	r0, r2, r1, r8
     9be:      	add.w	r6, r0, r0, lsl #2
     9c2:      	lsr.w	r3, r5, #0x1
     9c6:      	sub.w	r6, r4, r6, lsl #1
     9ca:      	sbc	r3, r3, #0x0
     9ce:      	orr	r12, r6, #0x30
     9d2:      	subs.w	r6, r4, #0xa
     9d6:      	add.w	r11, r10, r9
     9da:      	sbcs	r6, r5, #0x0
     9de:      	strb	r12, [r11, #-1]
     9e2:      	blo	0xad2 <zs_str_of_i64+0x17e> @ imm = #0xec
     9e4:      	mov.w	r6, #0xcccccccc
     9e8:      	mla	r1, r1, r6, r2
     9ec:      	lsrs	r2, r0, #0x1
     9ee:      	mla	r1, r3, r8, r1
     9f2:      	and	r0, r0, #0x1
     9f6:      	orr.w	r2, r2, r1, lsl #31
     9fa:      	adds.w	r1, r2, r1, lsr #1
     9fe:      	adc	r1, r1, #0x0
     a02:      	umull	r2, r3, r1, r8
     a06:      	bic	r2, r3, #0x3
     a0a:      	add.w	r2, r2, r3, lsr #2
     a0e:      	subs	r1, r1, r2
     a10:      	orr.w	r0, r0, r1, lsl #1
     a14:      	subs.w	r1, r4, #0x64
     a18:      	orr	r0, r0, #0x30
     a1c:      	sbcs	r1, r5, #0x0
     a20:      	strb.w	r0, [r10, r9]
     a24:      	blo	0xada <zs_str_of_i64+0x186> @ imm = #0xb2
     a26:      	mov	r0, r4
     a28:      	mov	r1, r5
     a2a:      	movs	r2, #0x64
     a2c:      	movs	r3, #0x0
     a2e:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xbf2
     a32:      	lsrs	r2, r0, #0x1
     a34:      	orr.w	r2, r2, r1, lsl #31
     a38:      	adds.w	r1, r2, r1, lsr #1
     a3c:      	adc	r1, r1, #0x0
     a40:      	umull	r2, r3, r1, r8
     a44:      	bic	r2, r3, #0x3
     a48:      	add.w	r2, r2, r3, lsr #2
     a4c:      	subs	r1, r1, r2
     a4e:      	and	r0, r0, #0x1
     a52:      	orr.w	r0, r0, r1, lsl #1
     a56:      	subs.w	r1, r4, #0x3e8
     a5a:      	orr	r0, r0, #0x30
     a5e:      	sbcs	r1, r5, #0x0
     a62:      	strb.w	r0, [r11, #0x1]
     a66:      	blo	0xae2 <zs_str_of_i64+0x18e> @ imm = #0x78
     a68:      	mov	r0, r4
     a6a:      	mov	r1, r5
     a6c:      	mov.w	r2, #0x3e8
     a70:      	movs	r3, #0x0
     a72:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xbae
     a76:      	lsrs	r2, r0, #0x1
     a78:      	orr.w	r2, r2, r1, lsl #31
     a7c:      	adds.w	r1, r2, r1, lsr #1
     a80:      	adc	r1, r1, #0x0
     a84:      	umull	r2, r3, r1, r8
     a88:      	bic	r2, r3, #0x3
     a8c:      	add.w	r2, r2, r3, lsr #2
     a90:      	subs	r1, r1, r2
     a92:      	and	r0, r0, #0x1
     a96:      	orr.w	r0, r0, r1, lsl #1
     a9a:      	orr	r0, r0, #0x30
     a9e:      	strb.w	r0, [r11, #0x2]
     aa2:      	mov	r0, r4
     aa4:      	mov	r1, r5
     aa6:      	movw	r2, #0x2710
     aaa:      	movs	r3, #0x0
     aac:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xb74
     ab0:      	movw	r2, #0x270f
     ab4:      	subs	r2, r2, r4
     ab6:      	mov.w	r2, #0x0
     aba:      	sbcs	r2, r5
     abc:      	add.w	r9, r9, #0x4
     ac0:      	mov	r4, r0
     ac2:      	mov	r5, r1
     ac4:      	blo.w	0x99c <zs_str_of_i64+0x48> @ imm = #-0x12c
     ac8:      	sub.w	r1, r9, #0x1
     acc:      	sub.w	r12, r9, #0x2
     ad0:      	b	0xaea <zs_str_of_i64+0x196> @ imm = #0x16
     ad2:      	sub.w	r12, r9, #0x1
     ad6:      	mov	r1, r9
     ad8:      	b	0xaec <zs_str_of_i64+0x198> @ imm = #0x10
     ada:      	add.w	r1, r9, #0x1
     ade:      	mov	r12, r9
     ae0:      	b	0xaea <zs_str_of_i64+0x196> @ imm = #0x6
     ae2:      	add.w	r1, r9, #0x2
     ae6:      	add.w	r12, r9, #0x1
     aea:      	mov	r9, r1
     aec:      	ldr.w	r8, [sp, #0x8]
     af0:      	and	lr, r1, #0x3
     af4:      	lsrs	r3, r1, #0x2
     af6:      	mov.w	r1, #0x0
     afa:      	beq	0xb2c <zs_str_of_i64+0x1d8> @ imm = #0x2e
     afc:      	add.w	r6, r12, r10
     b00:      	sub.w	r3, r1, r3, lsl #2
     b04:      	sub.w	r5, r8, #0x3
     b08:      	subs	r4, r6, #0x1
     b0a:      	nop
     b0c:      	adds	r6, r4, r1
     b0e:      	ldrb	r0, [r6, #0x1]
     b10:      	ldrb	r2, [r6, #-1]
     b14:      	strb	r0, [r5, #0x3]
     b16:      	ldrb	r0, [r4, r1]
     b18:      	subs	r1, #0x4
     b1a:      	strb	r0, [r5, #4]!
     b1e:      	ldrb	r0, [r6, #-2]
     b22:      	cmp	r3, r1
     b24:      	strb	r2, [r5, #0x1]
     b26:      	strb	r0, [r5, #0x2]
     b28:      	bne	0xb0c <zs_str_of_i64+0x1b8> @ imm = #-0x20
     b2a:      	rsbs	r1, r1, #0
     b2c:      	cmp.w	lr, #0x0
     b30:      	beq	0xb66 <zs_str_of_i64+0x212> @ imm = #0x32
     b32:      	sub.w	r0, r12, r1
     b36:      	ldrb.w	r0, [r10, r0]
     b3a:      	cmp.w	lr, #0x1
     b3e:      	strb.w	r0, [r8, r1]
     b42:      	beq	0xb66 <zs_str_of_i64+0x212> @ imm = #0x20
     b44:      	adds	r0, r1, #0x1
     b46:      	sub.w	r2, r12, r0
     b4a:      	ldrb.w	r2, [r10, r2]
     b4e:      	cmp.w	lr, #0x2
     b52:      	strb.w	r2, [r8, r0]
     b56:      	beq	0xb66 <zs_str_of_i64+0x212> @ imm = #0xc
     b58:      	adds	r0, r1, #0x2
     b5a:      	sub.w	r1, r12, r0
     b5e:      	ldrb.w	r1, [r10, r1]
     b62:      	strb.w	r1, [r8, r0]
     b66:      	ldr	r0, [sp, #0x4]
     b68:      	add.w	r1, r9, r0
     b6c:      	add	r0, sp, #0xc
     b6e:      	bl	0x804 <str_of>          @ imm = #-0x36e
     b72:      	add	sp, #0x3c
     b74:      	pop.w	{r8, r9, r10, r11}
     b78:      	pop	{r4, r5, r6, r7, pc}
     b7a:      	bmi	0xb26 <zs_str_of_i64+0x1d2> @ imm = #-0x58

00000b7c <zs_println>:
     b7c:      	push	{r4, r5, r6, r7, lr}
     b7e:      	add	r7, sp, #0xc
     b80:      	push.w	{r8, r9, r10, r11}
     b84:      	sub	sp, #0x44
     b86:      	ldr.w	r11, [r0, #0x4]
     b8a:      	cmp.w	r11, #0x1
     b8e:      	blt	0xc80 <zs_println+0x104> @ imm = #0xee
     b90:      	sub.w	r1, r7, #0x5d
     b94:      	movs	r2, #0x0
     b96:      	add.w	r3, r0, #0x8
     b9a:      	add.w	r12, r1, #0x1
     b9e:      	movs	r6, #0x40
     ba0:      	mov.w	r9, #0x0
     ba4:      	b	0xbc4 <zs_println+0x48> @ imm = #0x1c
     ba6:      	nop
     ba8:      	strb.w	r2, [r1, r8]
     bac:      	movs	r0, #0x4
     bae:      	subs.w	r11, r11, r8
     bb2:      	bkpt	#0xab
     bb4:      	sbc	r9, r9, #0x0
     bb8:      	rsbs.w	r0, r11, #0x0
     bbc:      	sbcs.w	r0, r2, r9
     bc0:      	add	r3, r8
     bc2:      	bge	0xc80 <zs_println+0x104> @ imm = #0xba
     bc4:      	mov.w	r8, #0x40
     bc8:      	cmp.w	r11, #0x40
     bcc:      	it	lo
     bce:      	movlo	r8, r11
     bd0:      	cmp.w	r9, #0x0
     bd4:      	it	ne
     bd6:      	movne	r8, r6
     bd8:      	sub.w	r0, r8, #0x1
     bdc:      	cmp	r0, #0x3
     bde:      	bhs	0xbec <zs_println+0x70> @ imm = #0xa
     be0:      	movs	r0, #0x0
     be2:      	ands	r4, r8, #0x3
     be6:      	bne	0xc4e <zs_println+0xd2> @ imm = #0x64
     be8:      	b	0xba8 <zs_println+0x2c> @ imm = #-0x44
     bea:      	nop
     bec:      	bic	r0, r8, #0x3
     bf0:      	rsb.w	r10, r0, #0x0
     bf4:      	mov	r1, r3
     bf6:      	adds	r5, r3, #0x1
     bf8:      	mvn	r4, #0x3
     bfc:      	adds	r2, r5, r4
     bfe:      	ldrb	r6, [r2, #0x3]
     c00:      	ldrb	r3, [r2, #0x4]
     c02:      	ldrb	r0, [r2, #0x5]
     c04:      	cmp	r6, #0x0
     c06:      	ldrb	r2, [r2, #0x6]
     c08:      	it	eq
     c0a:      	moveq	r6, #0x20
     c0c:      	add.w	lr, r12, r4
     c10:      	cmp	r3, #0x0
     c12:      	strb.w	r6, [lr, #0x3]
     c16:      	it	eq
     c18:      	moveq	r3, #0x20
     c1a:      	strb.w	r3, [lr, #0x4]
     c1e:      	cmp	r0, #0x0
     c20:      	it	eq
     c22:      	moveq	r0, #0x20
     c24:      	adds	r4, #0x4
     c26:      	strb.w	r0, [lr, #0x5]
     c2a:      	cmp	r2, #0x0
     c2c:      	add.w	r0, r10, r4
     c30:      	it	eq
     c32:      	moveq	r2, #0x20
     c34:      	adds	r0, #0x4
     c36:      	strb.w	r2, [lr, #0x6]
     c3a:      	bne	0xbfc <zs_println+0x80> @ imm = #-0x42
     c3c:      	adds	r0, r4, #0x4
     c3e:      	movs	r2, #0x0
     c40:      	mov	r3, r1
     c42:      	sub.w	r1, r7, #0x5d
     c46:      	movs	r6, #0x40
     c48:      	ands	r4, r8, #0x3
     c4c:      	beq	0xba8 <zs_println+0x2c> @ imm = #-0xa8
     c4e:      	ldrb	r5, [r3, r0]
     c50:      	cmp	r5, #0x0
     c52:      	it	eq
     c54:      	moveq	r5, #0x20
     c56:      	cmp	r4, #0x1
     c58:      	strb	r5, [r1, r0]
     c5a:      	beq	0xba8 <zs_println+0x2c> @ imm = #-0xb6
     c5c:      	add.w	r10, r0, #0x1
     c60:      	ldrb.w	r5, [r3, r10]
     c64:      	cmp	r5, #0x0
     c66:      	it	eq
     c68:      	moveq	r5, #0x20
     c6a:      	cmp	r4, #0x2
     c6c:      	strb.w	r5, [r1, r10]
     c70:      	beq	0xba8 <zs_println+0x2c> @ imm = #-0xcc
     c72:      	adds	r0, #0x2
     c74:      	ldrb	r4, [r3, r0]
     c76:      	cmp	r4, #0x0
     c78:      	it	eq
     c7a:      	moveq	r4, #0x20
     c7c:      	strb	r4, [r1, r0]
     c7e:      	b	0xba8 <zs_println+0x2c> @ imm = #-0xda
     c80:      	movs	r0, #0xa
     c82:      	strh	r0, [r7, #-93]
     c86:      	movs	r0, #0x4
     c88:      	sub.w	r1, r7, #0x5d
     c8c:      	bkpt	#0xab
     c8e:      	add	sp, #0x44
     c90:      	pop.w	{r8, r9, r10, r11}
     c94:      	pop	{r4, r5, r6, r7, pc}
     c96:      	bmi	0xc42 <zs_println+0xc6> @ imm = #-0x58

00000c98 <write_c>:
     c98:      	push	{r4, r5, r6, r7, lr}
     c9a:      	add	r7, sp, #0xc
     c9c:      	push.w	{r8, r9, r10, r11}
     ca0:      	sub	sp, #0x44
     ca2:      	mov	r2, r0
     ca4:      	mov.w	r11, #0xffffffff
     ca8:      	add.w	r0, r2, r11
     cac:      	ldrb	r1, [r0, #0x1]
     cae:      	cbz	r1, 0xcc8 <write_c+0x30> @ imm = #0x16
     cb0:      	ldrb	r1, [r0, #0x2]
     cb2:      	cbz	r1, 0xcd4 <write_c+0x3c> @ imm = #0x1e
     cb4:      	ldrb	r1, [r0, #0x3]
     cb6:      	cmp	r1, #0x0
     cb8:      	beq.w	0xdc8 <write_c+0x130>   @ imm = #0x10c
     cbc:      	ldrb	r0, [r0, #0x4]
     cbe:      	add.w	r11, r11, #0x4
     cc2:      	cmp	r0, #0x0
     cc4:      	bne	0xca8 <write_c+0x10>    @ imm = #-0x20
     cc6:      	b	0xcd8 <write_c+0x40>    @ imm = #0xe
     cc8:      	add.w	r11, r11, #0x1
     ccc:      	cmp.w	r11, #0x0
     cd0:      	bne	0xcde <write_c+0x46>    @ imm = #0xa
     cd2:      	b	0xdd4 <write_c+0x13c>   @ imm = #0xfe
     cd4:      	add.w	r11, r11, #0x2
     cd8:      	cmp.w	r11, #0x0
     cdc:      	beq	0xdd4 <write_c+0x13c>   @ imm = #0xf4
     cde:      	sub.w	r1, r7, #0x5d
     ce2:      	movs	r3, #0x0
     ce4:      	add.w	r12, r1, #0x1
     ce8:      	movs	r6, #0x40
     cea:      	mov.w	r9, #0x0
     cee:      	b	0xd0c <write_c+0x74>    @ imm = #0x1a
     cf0:      	strb.w	r3, [r1, r8]
     cf4:      	movs	r0, #0x4
     cf6:      	subs.w	r11, r11, r8
     cfa:      	bkpt	#0xab
     cfc:      	sbc	r9, r9, #0x0
     d00:      	rsbs.w	r0, r11, #0x0
     d04:      	sbcs.w	r0, r3, r9
     d08:      	add	r2, r8
     d0a:      	bge	0xdd4 <write_c+0x13c>   @ imm = #0xc6
     d0c:      	mov.w	r8, #0x40
     d10:      	cmp.w	r11, #0x40
     d14:      	it	lo
     d16:      	movlo	r8, r11
     d18:      	cmp.w	r9, #0x0
     d1c:      	it	ne
     d1e:      	movne	r8, r6
     d20:      	sub.w	r0, r8, #0x1
     d24:      	cmp	r0, #0x3
     d26:      	bhs	0xd34 <write_c+0x9c>    @ imm = #0xa
     d28:      	movs	r0, #0x0
     d2a:      	ands	r4, r8, #0x3
     d2e:      	bne	0xd96 <write_c+0xfe>    @ imm = #0x64
     d30:      	b	0xcf0 <write_c+0x58>    @ imm = #-0x44
     d32:      	nop
     d34:      	bic	r0, r8, #0x3
     d38:      	rsb.w	r10, r0, #0x0
     d3c:      	mov	r1, r2
     d3e:      	adds	r5, r2, #0x1
     d40:      	mvn	r4, #0x3
     d44:      	adds	r3, r5, r4
     d46:      	ldrb	r6, [r3, #0x3]
     d48:      	ldrb	r2, [r3, #0x4]
     d4a:      	ldrb	r0, [r3, #0x5]
     d4c:      	cmp	r6, #0x0
     d4e:      	ldrb	r3, [r3, #0x6]
     d50:      	it	eq
     d52:      	moveq	r6, #0x20
     d54:      	add.w	lr, r12, r4
     d58:      	cmp	r2, #0x0
     d5a:      	strb.w	r6, [lr, #0x3]
     d5e:      	it	eq
     d60:      	moveq	r2, #0x20
     d62:      	strb.w	r2, [lr, #0x4]
     d66:      	cmp	r0, #0x0
     d68:      	it	eq
     d6a:      	moveq	r0, #0x20
     d6c:      	adds	r4, #0x4
     d6e:      	strb.w	r0, [lr, #0x5]
     d72:      	cmp	r3, #0x0
     d74:      	add.w	r0, r10, r4
     d78:      	it	eq
     d7a:      	moveq	r3, #0x20
     d7c:      	adds	r0, #0x4
     d7e:      	strb.w	r3, [lr, #0x6]
     d82:      	bne	0xd44 <write_c+0xac>    @ imm = #-0x42
     d84:      	adds	r0, r4, #0x4
     d86:      	mov	r2, r1
     d88:      	movs	r3, #0x0
     d8a:      	sub.w	r1, r7, #0x5d
     d8e:      	movs	r6, #0x40
     d90:      	ands	r4, r8, #0x3
     d94:      	beq	0xcf0 <write_c+0x58>    @ imm = #-0xa8
     d96:      	ldrb	r5, [r2, r0]
     d98:      	cmp	r5, #0x0
     d9a:      	it	eq
     d9c:      	moveq	r5, #0x20
     d9e:      	cmp	r4, #0x1
     da0:      	strb	r5, [r1, r0]
     da2:      	beq	0xcf0 <write_c+0x58>    @ imm = #-0xb6
     da4:      	add.w	r10, r0, #0x1
     da8:      	ldrb.w	r5, [r2, r10]
     dac:      	cmp	r5, #0x0
     dae:      	it	eq
     db0:      	moveq	r5, #0x20
     db2:      	cmp	r4, #0x2
     db4:      	strb.w	r5, [r1, r10]
     db8:      	beq	0xcf0 <write_c+0x58>    @ imm = #-0xcc
     dba:      	adds	r0, #0x2
     dbc:      	ldrb	r4, [r2, r0]
     dbe:      	cmp	r4, #0x0
     dc0:      	it	eq
     dc2:      	moveq	r4, #0x20
     dc4:      	strb	r4, [r1, r0]
     dc6:      	b	0xcf0 <write_c+0x58>    @ imm = #-0xda
     dc8:      	add.w	r11, r11, #0x3
     dcc:      	cmp.w	r11, #0x0
     dd0:      	bne.w	0xcde <write_c+0x46>    @ imm = #-0xf6
     dd4:      	add	sp, #0x44
     dd6:      	pop.w	{r8, r9, r10, r11}
     dda:      	pop	{r4, r5, r6, r7, pc}

00000ddc <stop>:
     ddc:      	push	{r4, r5, r6, r7, lr}
     dde:      	add	r7, sp, #0xc
     de0:      	str	r11, [sp, #-4]!
     de4:      	sub	sp, #0x48
     de6:      	movw	r6, #0x8000
     dea:      	movw	r5, #0x0
     dee:      	movt	r6, #0x203f
     df2:      	movt	r5, #0x2040
     df6:      	cmp	r6, r5
     df8:      	mov	r4, r0
     dfa:      	bhs	0xe46 <stop+0x6a>       @ imm = #0x48
     dfc:      	movw	r0, #0x8000
     e00:      	movt	r0, #0x203f
     e04:      	ldr	r1, [r0]
     e06:      	cmp.w	r1, #0xcdcdcdcd
     e0a:      	bne	0xe44 <stop+0x68>       @ imm = #0x36
     e0c:      	adds	r6, r0, #0x4
     e0e:      	cmp	r6, r5
     e10:      	bhs	0xe46 <stop+0x6a>       @ imm = #0x32
     e12:      	ldr	r1, [r6]
     e14:      	cmp.w	r1, #0xcdcdcdcd
     e18:      	bne	0xe46 <stop+0x6a>       @ imm = #0x2a
     e1a:      	add.w	r6, r0, #0x8
     e1e:      	cmp	r6, r5
     e20:      	bhs	0xe46 <stop+0x6a>       @ imm = #0x22
     e22:      	ldr	r1, [r6]
     e24:      	cmp.w	r1, #0xcdcdcdcd
     e28:      	bne	0xe46 <stop+0x6a>       @ imm = #0x1a
     e2a:      	add.w	r6, r0, #0xc
     e2e:      	cmp	r6, r5
     e30:      	bhs	0xe46 <stop+0x6a>       @ imm = #0x12
     e32:      	ldr	r1, [r6]
     e34:      	cmp.w	r1, #0xcdcdcdcd
     e38:      	bne	0xe46 <stop+0x6a>       @ imm = #0xa
     e3a:      	adds	r0, #0x10
     e3c:      	cmp	r0, r5
     e3e:      	mov	r6, r0
     e40:      	blo	0xe04 <stop+0x28>       @ imm = #-0x40
     e42:      	b	0xe46 <stop+0x6a>       @ imm = #0x0
     e44:      	mov	r6, r0
     e46:      	movw	r0, #0x8c
     e4a:      	movt	r0, #0x2001
     e4e:      	ldr	r2, [r0]
     e50:      	movw	r0, #0x1c57
     e54:      	movt	r0, #0x0
     e58:      	movs	r3, #0x0
     e5a:      	bl	0x104c <text>           @ imm = #0x1ee
     e5e:      	movw	r0, #0x84
     e62:      	movt	r0, #0x2000
     e66:      	ldr	r2, [r0]
     e68:      	movw	r0, #0x1c6d
     e6c:      	movt	r0, #0x0
     e70:      	movs	r3, #0x0
     e72:      	bl	0x104c <text>           @ imm = #0x1d6
     e76:      	movw	r0, #0x98
     e7a:      	movt	r0, #0x2001
     e7e:      	ldrd	r2, r3, [r0]
     e82:      	movw	r0, #0x1c41
     e86:      	movt	r0, #0x0
     e8a:      	bl	0x104c <text>           @ imm = #0x1be
     e8e:      	movw	r0, #0x90
     e92:      	movt	r0, #0x2001
     e96:      	ldrd	r2, r3, [r0]
     e9a:      	movw	r0, #0x1c66
     e9e:      	movt	r0, #0x0
     ea2:      	bl	0x104c <text>           @ imm = #0x1a6
     ea6:      	subs	r2, r5, r6
     ea8:      	movw	r0, #0x1c4f
     eac:      	asrs	r3, r2, #0x1f
     eae:      	movt	r0, #0x0
     eb2:      	bl	0x104c <text>           @ imm = #0x196
     eb6:      	movs	r0, #0xa
     eb8:      	strh.w	r0, [sp, #0x4]
     ebc:      	movs	r0, #0x4
     ebe:      	add	r1, sp, #0x4
     ec0:      	bkpt	#0xab
     ec2:      	movs	r0, #0x26
     ec4:      	movt	r0, #0x2
     ec8:      	strd	r0, r4, [sp, #4]
     ecc:      	movs	r0, #0x20
     ece:      	add	r1, sp, #0x4
     ed0:      	bkpt	#0xab
     ed2:      	nop
     ed4:      	b	0xed4 <stop+0xf8>       @ imm = #-0x4
     ed6:      	bmi	0xe82 <stop+0xa6>       @ imm = #-0x58

00000ed8 <zs_set_args>:
     ed8:      	push	{r7, lr}
     eda:      	mov	r7, sp
     edc:      	pop	{r7, pc}
     ede:      	bmi	0xe8a <stop+0xae>       @ imm = #-0x58

00000ee0 <Reset_Handler>:
     ee0:      	push	{r7, lr}
     ee2:      	mov	r7, sp
     ee4:      	movw	r0, #0x0
     ee8:      	movw	r1, #0x0
     eec:      	movt	r0, #0x2000
     ef0:      	movt	r1, #0x2000
     ef4:      	cmp	r1, r0
     ef6:      	bhs	0xf2a <Reset_Handler+0x4a> @ imm = #0x30
     ef8:      	movw	r2, #0x1dbc
     efc:      	movt	r2, #0x0
     f00:      	ldr	r3, [r2]
     f02:      	str	r3, [r1], #4
     f06:      	cmp	r1, r0
     f08:      	bhs	0xf2a <Reset_Handler+0x4a> @ imm = #0x1e
     f0a:      	ldr	r3, [r2, #0x4]
     f0c:      	str	r3, [r1], #4
     f10:      	cmp	r1, r0
     f12:      	bhs	0xf2a <Reset_Handler+0x4a> @ imm = #0x14
     f14:      	ldr	r3, [r2, #0x8]
     f16:      	str	r3, [r1], #4
     f1a:      	cmp	r1, r0
     f1c:      	bhs	0xf2a <Reset_Handler+0x4a> @ imm = #0xa
     f1e:      	ldr	r3, [r2, #0xc]
     f20:      	adds	r2, #0x10
     f22:      	str	r3, [r1], #4
     f26:      	cmp	r1, r0
     f28:      	blo	0xf00 <Reset_Handler+0x20> @ imm = #-0x2c
     f2a:      	movw	r0, #0xa4
     f2e:      	movw	r1, #0x0
     f32:      	movt	r0, #0x2001
     f36:      	movt	r1, #0x2000
     f3a:      	cmp	r1, r0
     f3c:      	bhs	0xf60 <Reset_Handler+0x80> @ imm = #0x20
     f3e:      	movs	r2, #0x0
     f40:      	str	r2, [r1], #4
     f44:      	cmp	r1, r0
     f46:      	bhs	0xf60 <Reset_Handler+0x80> @ imm = #0x16
     f48:      	str	r2, [r1], #4
     f4c:      	cmp	r1, r0
     f4e:      	bhs	0xf60 <Reset_Handler+0x80> @ imm = #0xe
     f50:      	str	r2, [r1], #4
     f54:      	cmp	r1, r0
     f56:      	bhs	0xf60 <Reset_Handler+0x80> @ imm = #0x6
     f58:      	str	r2, [r1], #4
     f5c:      	cmp	r1, r0
     f5e:      	blo	0xf40 <Reset_Handler+0x60> @ imm = #-0x22
     f60:      	movw	r0, #0xed88
     f64:      	movt	r0, #0xe000
     f68:      	ldr	r1, [r0]
     f6a:      	orr	r1, r1, #0xf00000
     f6e:      	str	r1, [r0]
     f70:      	movw	r0, #0xe010
     f74:      	movt	r0, #0xe000
     f78:      	mvn	r1, #0xff000000
     f7c:      	dsb	sy
     f80:      	isb	sy
     f84:      	str	r1, [r0, #0x4]
     f86:      	movs	r1, #0x0
     f88:      	str	r1, [r0, #0x8]
     f8a:      	movs	r1, #0x7
     f8c:      	str	r1, [r0]
     f8e:      	mov	r0, sp
     f90:      	movw	r1, #0x8000
     f94:      	subs	r0, #0x40
     f96:      	movt	r1, #0x203f
     f9a:      	cmp	r0, r1
     f9c:      	bls	0xfc4 <Reset_Handler+0xe4> @ imm = #0x24
     f9e:      	mov.w	r2, #0xcdcdcdcd
     fa2:      	nop
     fa4:      	str	r2, [r1], #4
     fa8:      	cmp	r1, r0
     faa:      	bhs	0xfc4 <Reset_Handler+0xe4> @ imm = #0x16
     fac:      	str	r2, [r1], #4
     fb0:      	cmp	r1, r0
     fb2:      	bhs	0xfc4 <Reset_Handler+0xe4> @ imm = #0xe
     fb4:      	str	r2, [r1], #4
     fb8:      	cmp	r1, r0
     fba:      	bhs	0xfc4 <Reset_Handler+0xe4> @ imm = #0x6
     fbc:      	str	r2, [r1], #4
     fc0:      	cmp	r1, r0
     fc2:      	blo	0xfa4 <Reset_Handler+0xc4> @ imm = #-0x22
     fc4:      	movs	r0, #0x0
     fc6:      	movs	r1, #0x0
     fc8:      	bl	0x7c <main>             @ imm = #-0xf50
     fcc:      	bl	0xddc <stop>            @ imm = #-0x1f4

00000fd0 <zs_ticks>:
     fd0:      	push	{r7, lr}
     fd2:      	mov	r7, sp
     fd4:      	movw	r12, #0xe018
     fd8:      	movw	r2, #0xa0
     fdc:      	movt	r12, #0xe000
     fe0:      	movt	r2, #0x2001
     fe4:      	ldr	r1, [r2]
     fe6:      	ldr.w	r3, [r12]
     fea:      	ldr	r0, [r2]
     fec:      	cmp	r1, r0
     fee:      	beq	0x1014 <zs_ticks+0x44>  @ imm = #0x22
     ff0:      	ldr	r1, [r2]
     ff2:      	ldr.w	r3, [r12]
     ff6:      	ldr	r0, [r2]
     ff8:      	cmp	r1, r0
     ffa:      	beq	0x1014 <zs_ticks+0x44>  @ imm = #0x16
     ffc:      	ldr	r1, [r2]
     ffe:      	ldr.w	r3, [r12]
    1002:      	ldr	r0, [r2]
    1004:      	cmp	r1, r0
    1006:      	beq	0x1014 <zs_ticks+0x44>  @ imm = #0xa
    1008:      	ldr	r1, [r2]
    100a:      	ldr.w	r3, [r12]
    100e:      	ldr	r0, [r2]
    1010:      	cmp	r1, r0
    1012:      	bne	0xfe4 <zs_ticks+0x14>   @ imm = #-0x32
    1014:      	mvn	r0, #0xff000000
    1018:      	subs	r0, r0, r3
    101a:      	lsrs	r2, r1, #0x8
    101c:      	adds.w	r0, r0, r1, lsl #24
    1020:      	adc	r1, r2, #0x0
    1024:      	pop	{r7, pc}
    1026:      	bmi	0xfd2 <zs_ticks+0x2>    @ imm = #-0x58

00001028 <fault>:
    1028:      	push	{r7, lr}
    102a:      	mov	r7, sp
    102c:      	movw	r0, #0x1c36
    1030:      	movt	r0, #0x0
    1034:      	bl	0x3b8 <zs_panic_c>      @ imm = #-0xc80

00001038 <SysTick_Handler>:
    1038:      	push	{r7, lr}
    103a:      	mov	r7, sp
    103c:      	movw	r0, #0xa0
    1040:      	movt	r0, #0x2001
    1044:      	ldr	r1, [r0]
    1046:      	adds	r1, #0x1
    1048:      	str	r1, [r0]
    104a:      	pop	{r7, pc}

0000104c <text>:
    104c:      	push	{r4, r5, r6, r7, lr}
    104e:      	add	r7, sp, #0xc
    1050:      	push.w	{r8, r9, r10, r11}
    1054:      	sub	sp, #0x64
    1056:      	strd	r2, r3, [sp]
    105a:      	mov	r3, r0
    105c:      	mov.w	r12, #0xffffffff
    1060:      	add.w	r0, r3, r12
    1064:      	ldrb	r1, [r0, #0x1]
    1066:      	cbz	r1, 0x1082 <text+0x36>  @ imm = #0x18
    1068:      	ldrb	r1, [r0, #0x2]
    106a:      	cbz	r1, 0x108e <text+0x42>  @ imm = #0x20
    106c:      	ldrb	r1, [r0, #0x3]
    106e:      	cbz	r1, 0x109a <text+0x4e>  @ imm = #0x28
    1070:      	ldrb	r0, [r0, #0x4]
    1072:      	add.w	r12, r12, #0x4
    1076:      	cmp	r0, #0x0
    1078:      	bne	0x1060 <text+0x14>      @ imm = #-0x1c
    107a:      	cmp.w	r12, #0x0
    107e:      	bne	0x10a4 <text+0x58>      @ imm = #0x22
    1080:      	b	0x1192 <text+0x146>     @ imm = #0x10e
    1082:      	add.w	r12, r12, #0x1
    1086:      	cmp.w	r12, #0x0
    108a:      	bne	0x10a4 <text+0x58>      @ imm = #0x16
    108c:      	b	0x1192 <text+0x146>     @ imm = #0x102
    108e:      	add.w	r12, r12, #0x2
    1092:      	cmp.w	r12, #0x0
    1096:      	bne	0x10a4 <text+0x58>      @ imm = #0xa
    1098:      	b	0x1192 <text+0x146>     @ imm = #0xf6
    109a:      	add.w	r12, r12, #0x3
    109e:      	cmp.w	r12, #0x0
    10a2:      	beq	0x1192 <text+0x146>     @ imm = #0xec
    10a4:      	sub.w	r1, r7, #0x5d
    10a8:      	movs	r4, #0x0
    10aa:      	add.w	r10, r1, #0x1
    10ae:      	movs	r5, #0x40
    10b0:      	mov.w	r9, #0x0
    10b4:      	b	0x10d4 <text+0x88>      @ imm = #0x1c
    10b6:      	nop
    10b8:      	strb.w	r4, [r1, r11]
    10bc:      	movs	r0, #0x4
    10be:      	subs.w	r12, r12, r11
    10c2:      	bkpt	#0xab
    10c4:      	sbc	r9, r9, #0x0
    10c8:      	rsbs.w	r0, r12, #0x0
    10cc:      	sbcs.w	r0, r4, r9
    10d0:      	add	r3, r11
    10d2:      	bge	0x1192 <text+0x146>     @ imm = #0xbc
    10d4:      	mov.w	r11, #0x40
    10d8:      	cmp.w	r12, #0x40
    10dc:      	it	lo
    10de:      	movlo	r11, r12
    10e0:      	cmp.w	r9, #0x0
    10e4:      	it	ne
    10e6:      	movne	r11, r5
    10e8:      	sub.w	r0, r11, #0x1
    10ec:      	cmp	r0, #0x3
    10ee:      	bhs	0x10fc <text+0xb0>      @ imm = #0xa
    10f0:      	movs	r0, #0x0
    10f2:      	ands	r2, r11, #0x3
    10f6:      	bne	0x115e <text+0x112>     @ imm = #0x64
    10f8:      	b	0x10b8 <text+0x6c>      @ imm = #-0x44
    10fa:      	nop
    10fc:      	bic	r0, r11, #0x3
    1100:      	rsb.w	lr, r0, #0x0
    1104:      	mov	r1, r3
    1106:      	adds	r6, r3, #0x1
    1108:      	mvn	r2, #0x3
    110c:      	adds	r3, r6, r2
    110e:      	ldrb	r5, [r3, #0x3]
    1110:      	ldrb	r4, [r3, #0x4]
    1112:      	ldrb	r0, [r3, #0x5]
    1114:      	cmp	r5, #0x0
    1116:      	ldrb	r3, [r3, #0x6]
    1118:      	it	eq
    111a:      	moveq	r5, #0x20
    111c:      	add.w	r8, r10, r2
    1120:      	cmp	r4, #0x0
    1122:      	strb.w	r5, [r8, #0x3]
    1126:      	it	eq
    1128:      	moveq	r4, #0x20
    112a:      	strb.w	r4, [r8, #0x4]
    112e:      	cmp	r0, #0x0
    1130:      	it	eq
    1132:      	moveq	r0, #0x20
    1134:      	adds	r2, #0x4
    1136:      	strb.w	r0, [r8, #0x5]
    113a:      	cmp	r3, #0x0
    113c:      	add.w	r0, lr, r2
    1140:      	it	eq
    1142:      	moveq	r3, #0x20
    1144:      	adds	r0, #0x4
    1146:      	strb.w	r3, [r8, #0x6]
    114a:      	bne	0x110c <text+0xc0>      @ imm = #-0x42
    114c:      	adds	r0, r2, #0x4
    114e:      	mov	r3, r1
    1150:      	movs	r4, #0x0
    1152:      	sub.w	r1, r7, #0x5d
    1156:      	movs	r5, #0x40
    1158:      	ands	r2, r11, #0x3
    115c:      	beq	0x10b8 <text+0x6c>      @ imm = #-0xa8
    115e:      	ldrb	r6, [r3, r0]
    1160:      	cmp	r6, #0x0
    1162:      	it	eq
    1164:      	moveq	r6, #0x20
    1166:      	cmp	r2, #0x1
    1168:      	strb	r6, [r1, r0]
    116a:      	beq	0x10b8 <text+0x6c>      @ imm = #-0xb6
    116c:      	adds	r6, r0, #0x1
    116e:      	ldrb.w	lr, [r3, r6]
    1172:      	cmp.w	lr, #0x0
    1176:      	it	eq
    1178:      	moveq.w	lr, #0x20
    117c:      	cmp	r2, #0x2
    117e:      	strb.w	lr, [r1, r6]
    1182:      	beq	0x10b8 <text+0x6c>      @ imm = #-0xce
    1184:      	adds	r0, #0x2
    1186:      	ldrb	r2, [r3, r0]
    1188:      	cmp	r2, #0x0
    118a:      	it	eq
    118c:      	moveq	r2, #0x20
    118e:      	strb	r2, [r1, r0]
    1190:      	b	0x10b8 <text+0x6c>      @ imm = #-0xdc
    1192:      	movw	r9, #0xcccd
    1196:      	ldrd	r4, r5, [sp]
    119a:      	mov.w	r11, #0x1
    119e:      	movt	r9, #0xcccc
    11a2:      	sub.w	r10, r7, #0x5d
    11a6:      	nop
    11a8:      	lsrs	r0, r4, #0x1
    11aa:      	orr.w	r0, r0, r5, lsl #31
    11ae:      	adds.w	r1, r0, r5, lsr #1
    11b2:      	adc	r1, r1, #0x0
    11b6:      	umull	r2, r3, r1, r9
    11ba:      	bic	r2, r3, #0x3
    11be:      	add.w	r2, r2, r3, lsr #2
    11c2:      	subs	r1, r1, r2
    11c4:      	subs	r1, r0, r1
    11c6:      	umull	r0, lr, r1, r9
    11ca:      	lsr.w	r3, r5, #0x1
    11ce:      	add.w	r6, r0, r0, lsl #2
    11d2:      	sbc	r2, r3, #0x0
    11d6:      	sub.w	r6, r4, r6, lsl #1
    11da:      	mov	r3, r4
    11dc:      	subs	r4, #0xa
    11de:      	orr	r12, r6, #0x30
    11e2:      	add.w	r8, r10, r11
    11e6:      	sbcs	r4, r5, #0x0
    11ea:      	strb	r12, [r8, #-1]
    11ee:      	blo	0x12e6 <text+0x29a>     @ imm = #0xf4
    11f0:      	mov.w	r4, #0xcccccccc
    11f4:      	mla	r1, r1, r4, lr
    11f8:      	mla	r1, r2, r9, r1
    11fc:      	lsrs	r2, r0, #0x1
    11fe:      	orr.w	r2, r2, r1, lsl #31
    1202:      	adds.w	r1, r2, r1, lsr #1
    1206:      	adc	r1, r1, #0x0
    120a:      	umull	r2, r4, r1, r9
    120e:      	bic	r2, r4, #0x3
    1212:      	add.w	r2, r2, r4, lsr #2
    1216:      	subs	r1, r1, r2
    1218:      	and	r0, r0, #0x1
    121c:      	orr.w	r0, r0, r1, lsl #1
    1220:      	subs.w	r1, r3, #0x64
    1224:      	orr	r0, r0, #0x30
    1228:      	sbcs	r1, r5, #0x0
    122c:      	mov	r4, r10
    122e:      	strb.w	r0, [r10, r11]
    1232:      	blo	0x12f0 <text+0x2a4>     @ imm = #0xba
    1234:      	mov	r6, r3
    1236:      	mov	r0, r3
    1238:      	mov	r1, r5
    123a:      	movs	r2, #0x64
    123c:      	movs	r3, #0x0
    123e:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x3e2
    1242:      	lsrs	r2, r0, #0x1
    1244:      	orr.w	r2, r2, r1, lsl #31
    1248:      	adds.w	r1, r2, r1, lsr #1
    124c:      	adc	r1, r1, #0x0
    1250:      	umull	r2, r3, r1, r9
    1254:      	bic	r2, r3, #0x3
    1258:      	add.w	r2, r2, r3, lsr #2
    125c:      	subs	r1, r1, r2
    125e:      	and	r0, r0, #0x1
    1262:      	orr.w	r0, r0, r1, lsl #1
    1266:      	subs.w	r1, r6, #0x3e8
    126a:      	orr	r0, r0, #0x30
    126e:      	sbcs	r1, r5, #0x0
    1272:      	strb.w	r0, [r8, #0x1]
    1276:      	blo	0x12f8 <text+0x2ac>     @ imm = #0x7e
    1278:      	mov	r0, r6
    127a:      	mov	r1, r5
    127c:      	mov.w	r2, #0x3e8
    1280:      	movs	r3, #0x0
    1282:      	mov	r10, r4
    1284:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x39c
    1288:      	lsrs	r2, r0, #0x1
    128a:      	orr.w	r2, r2, r1, lsl #31
    128e:      	adds.w	r1, r2, r1, lsr #1
    1292:      	adc	r1, r1, #0x0
    1296:      	umull	r2, r3, r1, r9
    129a:      	bic	r2, r3, #0x3
    129e:      	add.w	r2, r2, r3, lsr #2
    12a2:      	subs	r1, r1, r2
    12a4:      	and	r0, r0, #0x1
    12a8:      	orr.w	r0, r0, r1, lsl #1
    12ac:      	orr	r0, r0, #0x30
    12b0:      	strb.w	r0, [r8, #0x2]
    12b4:      	mov	r0, r6
    12b6:      	mov	r1, r5
    12b8:      	movw	r2, #0x2710
    12bc:      	movs	r3, #0x0
    12be:      	bl	0x1624 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x362
    12c2:      	movw	r2, #0x270f
    12c6:      	subs	r2, r2, r6
    12c8:      	mov.w	r2, #0x0
    12cc:      	sbcs	r2, r5
    12ce:      	add.w	r11, r11, #0x4
    12d2:      	mov	r4, r0
    12d4:      	mov	r5, r1
    12d6:      	blo.w	0x11a8 <text+0x15c>     @ imm = #-0x132
    12da:      	sub.w	r1, r11, #0x1
    12de:      	sub.w	r12, r11, #0x2
    12e2:      	mov	r11, r1
    12e4:      	b	0x12ec <text+0x2a0>     @ imm = #0x4
    12e6:      	sub.w	r12, r11, #0x1
    12ea:      	mov	r1, r11
    12ec:      	mov	r4, r10
    12ee:      	b	0x1302 <text+0x2b6>     @ imm = #0x10
    12f0:      	add.w	r1, r11, #0x1
    12f4:      	mov	r12, r11
    12f6:      	b	0x1300 <text+0x2b4>     @ imm = #0x6
    12f8:      	add.w	r1, r11, #0x2
    12fc:      	add.w	r12, r11, #0x1
    1300:      	mov	r11, r1
    1302:      	and	lr, r1, #0x3
    1306:      	lsrs	r3, r1, #0x2
    1308:      	mov.w	r1, #0x0
    130c:      	beq	0x1346 <text+0x2fa>     @ imm = #0x36
    130e:      	sub.w	r6, r7, #0x75
    1312:      	add.w	r5, r12, r4
    1316:      	sub.w	r9, r1, r3, lsl #2
    131a:      	subs	r6, #0x3
    131c:      	subs	r5, #0x1
    131e:      	nop
    1320:      	adds	r4, r5, r1
    1322:      	ldrb	r3, [r5, r1]
    1324:      	ldrb	r0, [r4, #-2]
    1328:      	ldrb	r2, [r4, #-1]
    132c:      	ldrb	r4, [r4, #0x1]
    132e:      	subs	r1, #0x4
    1330:      	strb	r3, [r6, #4]!
    1334:      	cmp	r9, r1
    1336:      	strb	r4, [r6, #-1]
    133a:      	strb	r2, [r6, #0x1]
    133c:      	strb	r0, [r6, #0x2]
    133e:      	bne	0x1320 <text+0x2d4>     @ imm = #-0x22
    1340:      	rsbs	r1, r1, #0
    1342:      	sub.w	r4, r7, #0x5d
    1346:      	cmp.w	lr, #0x0
    134a:      	beq	0x1378 <text+0x32c>     @ imm = #0x2a
    134c:      	sub.w	r0, r12, r1
    1350:      	ldrb	r0, [r4, r0]
    1352:      	sub.w	r3, r7, #0x75
    1356:      	cmp.w	lr, #0x1
    135a:      	strb	r0, [r3, r1]
    135c:      	beq	0x1378 <text+0x32c>     @ imm = #0x18
    135e:      	adds	r0, r1, #0x1
    1360:      	sub.w	r2, r12, r0
    1364:      	ldrb	r2, [r4, r2]
    1366:      	cmp.w	lr, #0x2
    136a:      	strb	r2, [r3, r0]
    136c:      	beq	0x1378 <text+0x32c>     @ imm = #0x8
    136e:      	adds	r0, r1, #0x2
    1370:      	sub.w	r1, r12, r0
    1374:      	ldrb	r1, [r4, r1]
    1376:      	strb	r1, [r3, r0]
    1378:      	sub.w	r0, r7, #0x75
    137c:      	movs	r1, #0x0
    137e:      	mov.w	r12, #0xffffffff
    1382:      	strb.w	r1, [r0, r11]
    1386:      	nop
    1388:      	add.w	r1, r0, r12
    138c:      	ldrb	r3, [r1, #0x1]
    138e:      	cbz	r3, 0x13aa <text+0x35e> @ imm = #0x18
    1390:      	ldrb	r3, [r1, #0x2]
    1392:      	cbz	r3, 0x13b6 <text+0x36a> @ imm = #0x20
    1394:      	ldrb	r3, [r1, #0x3]
    1396:      	cbz	r3, 0x13c2 <text+0x376> @ imm = #0x28
    1398:      	ldrb	r1, [r1, #0x4]
    139a:      	add.w	r12, r12, #0x4
    139e:      	cmp	r1, #0x0
    13a0:      	bne	0x1388 <text+0x33c>     @ imm = #-0x1c
    13a2:      	cmp.w	r12, #0x0
    13a6:      	bne	0x13cc <text+0x380>     @ imm = #0x22
    13a8:      	b	0x14b4 <text+0x468>     @ imm = #0x108
    13aa:      	add.w	r12, r12, #0x1
    13ae:      	cmp.w	r12, #0x0
    13b2:      	bne	0x13cc <text+0x380>     @ imm = #0x16
    13b4:      	b	0x14b4 <text+0x468>     @ imm = #0xfc
    13b6:      	add.w	r12, r12, #0x2
    13ba:      	cmp.w	r12, #0x0
    13be:      	bne	0x13cc <text+0x380>     @ imm = #0xa
    13c0:      	b	0x14b4 <text+0x468>     @ imm = #0xf0
    13c2:      	add.w	r12, r12, #0x3
    13c6:      	cmp.w	r12, #0x0
    13ca:      	beq	0x14b4 <text+0x468>     @ imm = #0xe6
    13cc:      	movs	r2, #0x0
    13ce:      	add.w	lr, r4, #0x1
    13d2:      	sub.w	r9, r7, #0x75
    13d6:      	movs	r3, #0x40
    13d8:      	mov.w	r11, #0x0
    13dc:      	b	0x13fe <text+0x3b2>     @ imm = #0x1e
    13de:      	nop
    13e0:      	strb.w	r2, [r4, r8]
    13e4:      	movs	r0, #0x4
    13e6:      	subs.w	r12, r12, r8
    13ea:      	mov	r1, r4
    13ec:      	bkpt	#0xab
    13ee:      	sbc	r11, r11, #0x0
    13f2:      	rsbs.w	r0, r12, #0x0
    13f6:      	sbcs.w	r0, r2, r11
    13fa:      	add	r9, r8
    13fc:      	bge	0x14b4 <text+0x468>     @ imm = #0xb4
    13fe:      	mov.w	r8, #0x40
    1402:      	cmp.w	r12, #0x40
    1406:      	it	lo
    1408:      	movlo	r8, r12
    140a:      	cmp.w	r11, #0x0
    140e:      	it	ne
    1410:      	movne	r8, r3
    1412:      	sub.w	r0, r8, #0x1
    1416:      	cmp	r0, #0x3
    1418:      	bhs	0x1424 <text+0x3d8>     @ imm = #0x8
    141a:      	movs	r0, #0x0
    141c:      	ands	r1, r8, #0x3
    1420:      	bne	0x147e <text+0x432>     @ imm = #0x5a
    1422:      	b	0x13e0 <text+0x394>     @ imm = #-0x46
    1424:      	bic	r0, r8, #0x3
    1428:      	rsb.w	r10, r0, #0x0
    142c:      	add.w	r5, r9, #0x1
    1430:      	mvn	r1, #0x3
    1434:      	adds	r4, r5, r1
    1436:      	ldrb	r2, [r4, #0x3]
    1438:      	ldrb	r3, [r4, #0x4]
    143a:      	ldrb	r6, [r4, #0x5]
    143c:      	cmp	r2, #0x0
    143e:      	ldrb	r4, [r4, #0x6]
    1440:      	it	eq
    1442:      	moveq	r2, #0x20
    1444:      	add.w	r0, lr, r1
    1448:      	cmp	r3, #0x0
    144a:      	strb	r2, [r0, #0x3]
    144c:      	it	eq
    144e:      	moveq	r3, #0x20
    1450:      	cmp	r6, #0x0
    1452:      	add.w	r1, r1, #0x4
    1456:      	strb	r3, [r0, #0x4]
    1458:      	it	eq
    145a:      	moveq	r6, #0x20
    145c:      	cmp	r4, #0x0
    145e:      	add.w	r2, r10, r1
    1462:      	strb	r6, [r0, #0x5]
    1464:      	it	eq
    1466:      	moveq	r4, #0x20
    1468:      	adds	r2, #0x4
    146a:      	strb	r4, [r0, #0x6]
    146c:      	bne	0x1434 <text+0x3e8>     @ imm = #-0x3c
    146e:      	adds	r0, r1, #0x4
    1470:      	sub.w	r4, r7, #0x5d
    1474:      	movs	r2, #0x0
    1476:      	movs	r3, #0x40
    1478:      	ands	r1, r8, #0x3
    147c:      	beq	0x13e0 <text+0x394>     @ imm = #-0xa0
    147e:      	ldrb.w	r5, [r9, r0]
    1482:      	cmp	r5, #0x0
    1484:      	it	eq
    1486:      	moveq	r5, #0x20
    1488:      	cmp	r1, #0x1
    148a:      	strb	r5, [r4, r0]
    148c:      	beq	0x13e0 <text+0x394>     @ imm = #-0xb0
    148e:      	add.w	r10, r0, #0x1
    1492:      	ldrb.w	r5, [r9, r10]
    1496:      	cmp	r5, #0x0
    1498:      	it	eq
    149a:      	moveq	r5, #0x20
    149c:      	cmp	r1, #0x2
    149e:      	strb.w	r5, [r4, r10]
    14a2:      	beq	0x13e0 <text+0x394>     @ imm = #-0xc6
    14a4:      	adds	r0, #0x2
    14a6:      	ldrb.w	r1, [r9, r0]
    14aa:      	cmp	r1, #0x0
    14ac:      	it	eq
    14ae:      	moveq	r1, #0x20
    14b0:      	strb	r1, [r4, r0]
    14b2:      	b	0x13e0 <text+0x394>     @ imm = #-0xd6
    14b4:      	add	sp, #0x64
    14b6:      	pop.w	{r8, r9, r10, r11}
    14ba:      	pop	{r4, r5, r6, r7, pc}

000014bc <compiler_rt.memset>:
    14bc:      	cmp	r2, #0x0
    14be:      	it	eq
    14c0:      	bxeq	lr
    14c2:      	push	{r7, lr}
    14c4:      	mov	r7, sp
    14c6:      	ands	lr, r2, #0x3
    14ca:      	mov	r3, r2
    14cc:      	mov	r12, r0
    14ce:      	beq	0x14f2 <compiler_rt.memset+0x36> @ imm = #0x20
    14d0:      	mov	r12, r0
    14d2:      	cmp.w	lr, #0x1
    14d6:      	strb	r1, [r12], #1
    14da:      	bne	0x14e4 <compiler_rt.memset+0x28> @ imm = #0x6
    14dc:      	subs	r3, r2, #0x1
    14de:      	cmp	r2, #0x4
    14e0:      	bhs	0x14f6 <compiler_rt.memset+0x3a> @ imm = #0x12
    14e2:      	b	0x150a <compiler_rt.memset+0x4e> @ imm = #0x24
    14e4:      	cmp.w	lr, #0x2
    14e8:      	strb	r1, [r0, #0x1]
    14ea:      	bne	0x1510 <compiler_rt.memset+0x54> @ imm = #0x22
    14ec:      	subs	r3, r2, #0x2
    14ee:      	add.w	r12, r0, #0x2
    14f2:      	cmp	r2, #0x4
    14f4:      	blo	0x150a <compiler_rt.memset+0x4e> @ imm = #0x12
    14f6:      	sub.w	r2, r12, #0x4
    14fa:      	nop
    14fc:      	strb	r1, [r2, #4]!
    1500:      	subs	r3, #0x4
    1502:      	strb	r1, [r2, #0x1]
    1504:      	strb	r1, [r2, #0x2]
    1506:      	strb	r1, [r2, #0x3]
    1508:      	bne	0x14fc <compiler_rt.memset+0x40> @ imm = #-0x10
    150a:      	pop.w	{r7, lr}
    150e:      	bx	lr
    1510:      	subs	r3, r2, #0x3
    1512:      	add.w	r12, r0, #0x3
    1516:      	strb	r1, [r0, #0x2]
    1518:      	cmp	r2, #0x4
    151a:      	bhs	0x14f6 <compiler_rt.memset+0x3a> @ imm = #-0x28
    151c:      	b	0x150a <compiler_rt.memset+0x4e> @ imm = #-0x16
    151e:      	bmi	0x14ca <compiler_rt.memset+0xe> @ imm = #-0x58

00001520 <compiler_rt.arm.__aeabi_unwind_cpp_pr0>:
    1520:      	push	{r7, lr}
    1522:      	mov	r7, sp
    1524:      	pop	{r7, pc}
    1526:      	bmi	0x14d2 <compiler_rt.memset+0x16> @ imm = #-0x58

00001528 <compiler_rt.arm.__aeabi_memclr>:
    1528:      	push	{r7, lr}
    152a:      	mov	r7, sp
    152c:      	mov	r2, r1
    152e:      	movs	r1, #0x0
    1530:      	pop.w	{r7, lr}
    1534:      	b.w	0x14bc <compiler_rt.memset> @ imm = #-0x7c

00001538 <compiler_rt.arm.__aeabi_memcpy>:
    1538:      	push	{r4, r5, r6, r7, lr}
    153a:      	add	r7, sp, #0xc
    153c:      	push.w	{r8, r9, r10, r11}
    1540:      	sub	sp, #0x4
    1542:      	cmp	r2, #0xf
    1544:      	bhi	0x1564 <compiler_rt.arm.__aeabi_memcpy+0x2c> @ imm = #0x1c
    1546:      	cmp	r2, #0x3
    1548:      	bhi	0x158c <compiler_rt.arm.__aeabi_memcpy+0x54> @ imm = #0x40
    154a:      	cbz	r2, 0x155c <compiler_rt.arm.__aeabi_memcpy+0x24> @ imm = #0xe
    154c:      	ldrb	r3, [r1]
    154e:      	strb	r3, [r0]
    1550:      	lsrs	r3, r2, #0x1
    1552:      	subs	r2, #0x1
    1554:      	ldrb	r6, [r1, r3]
    1556:      	ldrb	r1, [r1, r2]
    1558:      	strb	r6, [r0, r3]
    155a:      	strb	r1, [r0, r2]
    155c:      	add	sp, #0x4
    155e:      	pop.w	{r8, r9, r10, r11}
    1562:      	pop	{r4, r5, r6, r7, pc}
    1564:      	ldr	r3, [r1]
    1566:      	mov.w	r6, #0xffffffff
    156a:      	str	r3, [r0]
    156c:      	and	r3, r1, #0x3
    1570:      	rsb.w	lr, r3, #0x4
    1574:      	sub.w	r4, r2, lr
    1578:      	add.w	r6, r6, r4, lsr #2
    157c:      	cmp	r6, #0x3
    157e:      	ubfx	r6, r4, #0x2, #0x2
    1582:      	str	r6, [sp]
    1584:      	bhs	0x15b0 <compiler_rt.arm.__aeabi_memcpy+0x78> @ imm = #0x28
    1586:      	movs	r3, #0x0
    1588:      	b	0x15e4 <compiler_rt.arm.__aeabi_memcpy+0xac> @ imm = #0x58
    158a:      	nop
    158c:      	movs	r3, #0x4
    158e:      	ldr	r6, [r1]
    1590:      	and.w	r3, r3, r2, lsr #1
    1594:      	subs	r2, #0x4
    1596:      	str	r6, [r0]
    1598:      	ldr	r6, [r1, r3]
    159a:      	subs	r5, r2, r3
    159c:      	str	r6, [r0, r3]
    159e:      	ldr	r3, [r1, r5]
    15a0:      	ldr	r1, [r1, r2]
    15a2:      	str	r3, [r0, r5]
    15a4:      	str	r1, [r0, r2]
    15a6:      	add	sp, #0x4
    15a8:      	pop.w	{r8, r9, r10, r11}
    15ac:      	pop	{r4, r5, r6, r7, pc}
    15ae:      	nop
    15b0:      	lsrs	r4, r4, #0x2
    15b2:      	bic	r8, r4, #0x3
    15b6:      	sub.w	r9, r0, r3
    15ba:      	sub.w	r10, r1, r3
    15be:      	movs	r3, #0x0
    15c0:      	add.w	r5, r10, r3, lsl #2
    15c4:      	add.w	r12, r5, #0x4
    15c8:      	add.w	r4, r9, r3, lsl #2
    15cc:      	ldm.w	r12, {r6, r11, r12}
    15d0:      	ldr	r5, [r5, #0x10]
    15d2:      	adds	r3, #0x4
    15d4:      	cmp	r8, r3
    15d6:      	str	r6, [r4, #0x4]
    15d8:      	str.w	r11, [r4, #0x8]
    15dc:      	str.w	r12, [r4, #0xc]
    15e0:      	str	r5, [r4, #0x10]
    15e2:      	bne	0x15c0 <compiler_rt.arm.__aeabi_memcpy+0x88> @ imm = #-0x26
    15e4:      	ldr	r4, [sp]
    15e6:      	cbz	r4, 0x1614 <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x2a
    15e8:      	add.w	r6, r1, lr
    15ec:      	ldr.w	r5, [r6, r3, lsl #2]
    15f0:      	add.w	r8, r0, lr
    15f4:      	cmp	r4, #0x1
    15f6:      	str.w	r5, [r8, r3, lsl #2]
    15fa:      	beq	0x1614 <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x16
    15fc:      	adds	r5, r3, #0x1
    15fe:      	ldr.w	r12, [r6, r5, lsl #2]
    1602:      	cmp	r4, #0x2
    1604:      	str.w	r12, [r8, r5, lsl #2]
    1608:      	beq	0x1614 <compiler_rt.arm.__aeabi_memcpy+0xdc> @ imm = #0x8
    160a:      	adds	r3, #0x2
    160c:      	ldr.w	r6, [r6, r3, lsl #2]
    1610:      	str.w	r6, [r8, r3, lsl #2]
    1614:      	subs	r2, #0x4
    1616:      	ldr	r1, [r1, r2]
    1618:      	str	r1, [r0, r2]
    161a:      	add	sp, #0x4
    161c:      	pop.w	{r8, r9, r10, r11}
    1620:      	pop	{r4, r5, r6, r7, pc}
    1622:      	bmi	0x15ce <compiler_rt.arm.__aeabi_memcpy+0x96> @ imm = #-0x58

00001624 <compiler_rt.arm.__aeabi_uldivmod>:
    1624:      	push	{r4, lr}
    1626:      	sub	sp, #0x10
    1628:      	add	r4, sp, #0x8
    162a:      	str	r4, [sp]
    162c:      	bl	0x1638 <compiler_rt.int.__udivmoddi4> @ imm = #0x8
    1630:      	ldr	r2, [sp, #0x8]
    1632:      	ldr	r3, [sp, #0xc]
    1634:      	add	sp, #0x10
    1636:      	pop	{r4, pc}

00001638 <compiler_rt.int.__udivmoddi4>:
    1638:      	push	{r4, r5, r6, r7, lr}
    163a:      	add	r7, sp, #0xc
    163c:      	push.w	{r8, r9, r10, r11}
    1640:      	sub	sp, #0x20
    1642:      	mov	r5, r2
    1644:      	ldr	r6, [r7, #0x8]
    1646:      	subs	r2, r0, r2
    1648:      	sbcs.w	r2, r1, r3
    164c:      	bhs	0x1664 <compiler_rt.int.__udivmoddi4+0x2c> @ imm = #0x14
    164e:      	cmp	r6, #0x0
    1650:      	it	ne
    1652:      	strdne	r0, r1, [r6]
    1656:      	movs	r0, #0x0
    1658:      	movs	r1, #0x0
    165a:      	add	sp, #0x20
    165c:      	pop.w	{r8, r9, r10, r11}
    1660:      	pop	{r4, r5, r6, r7, pc}
    1662:      	nop
    1664:      	cmp	r3, #0x0
    1666:      	beq.w	0x1770 <compiler_rt.int.__udivmoddi4+0x138> @ imm = #0x106
    166a:      	clz	r2, r3
    166e:      	cmp	r2, #0x0
    1670:      	beq.w	0x179c <compiler_rt.int.__udivmoddi4+0x164> @ imm = #0x128
    1674:      	rsbs	r6, r2, #0
    1676:      	and	r4, r6, #0x1f
    167a:      	lsl.w	r12, r3, r2
    167e:      	lsr.w	r6, r5, r4
    1682:      	orr.w	r8, r6, r12
    1686:      	lsl.w	r2, r1, r2
    168a:      	lsr.w	r6, r0, r4
    168e:      	clz	lr, r8
    1692:      	orrs	r2, r6
    1694:      	ands	r12, lr, #0x1f
    1698:      	lsr.w	r6, r1, r4
    169c:      	str	r5, [sp, #0x10]
    169e:      	str	r0, [sp, #0x4]
    16a0:      	beq	0x16bc <compiler_rt.int.__udivmoddi4+0x84> @ imm = #0x18
    16a2:      	lsl.w	r4, r6, r12
    16a6:      	rsb.w	r6, lr, #0x0
    16aa:      	and	r6, r6, #0x1f
    16ae:      	lsr.w	r6, r2, r6
    16b2:      	lsl.w	r8, r8, r12
    16b6:      	orrs	r6, r4
    16b8:      	lsl.w	r2, r2, r12
    16bc:      	lsr.w	lr, r8, #0x10
    16c0:      	udiv	r4, r6, lr
    16c4:      	strd	r3, r1, [sp, #8]
    16c8:      	mls	r9, r4, lr, r6
    16cc:      	uxth.w	r12, r8
    16d0:      	lsr.w	r11, r2, #0x10
    16d4:      	uxth	r3, r2
    16d6:      	mov	r0, r6
    16d8:      	mov.w	r10, #0x0
    16dc:      	str.w	r8, [sp]
    16e0:      	b	0x16f4 <compiler_rt.int.__udivmoddi4+0xbc> @ imm = #0x10
    16e2:      	nop
    16e4:      	subs	r6, r4, #0x4
    16e6:      	add.w	r9, r2, lr
    16ea:      	cmp.w	r10, r9, lsr #16
    16ee:      	mov	r4, r6
    16f0:      	bne.w	0x192e <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x23a
    16f4:      	cmp.w	r10, r4, lsr #16
    16f8:      	bne	0x1708 <compiler_rt.int.__udivmoddi4+0xd0> @ imm = #0xc
    16fa:      	mul	r2, r4, r12
    16fe:      	orr.w	r6, r11, r9, lsl #16
    1702:      	cmp	r2, r6
    1704:      	bls.w	0x192c <compiler_rt.int.__udivmoddi4+0x2f4> @ imm = #0x224
    1708:      	add.w	r2, r9, lr
    170c:      	cmp.w	r10, r2, lsr #16
    1710:      	sub.w	r6, r4, #0x1
    1714:      	bne.w	0x192e <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x216
    1718:      	cmp.w	r10, r6, lsr #16
    171c:      	bne	0x172c <compiler_rt.int.__udivmoddi4+0xf4> @ imm = #0xc
    171e:      	mul	r9, r6, r12
    1722:      	orr.w	r8, r11, r2, lsl #16
    1726:      	cmp	r9, r8
    1728:      	bls.w	0x192e <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x202
    172c:      	add	r2, lr
    172e:      	cmp.w	r10, r2, lsr #16
    1732:      	sub.w	r6, r4, #0x2
    1736:      	bne.w	0x192e <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1f4
    173a:      	cmp.w	r10, r6, lsr #16
    173e:      	bne	0x174e <compiler_rt.int.__udivmoddi4+0x116> @ imm = #0xc
    1740:      	mul	r8, r6, r12
    1744:      	orr.w	r5, r11, r2, lsl #16
    1748:      	cmp	r8, r5
    174a:      	bls.w	0x192e <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1e0
    174e:      	add	r2, lr
    1750:      	cmp.w	r10, r2, lsr #16
    1754:      	sub.w	r6, r4, #0x3
    1758:      	bne.w	0x192e <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1d2
    175c:      	cmp.w	r10, r6, lsr #16
    1760:      	bne	0x16e4 <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x80
    1762:      	mul	r5, r6, r12
    1766:      	orr.w	r1, r11, r2, lsl #16
    176a:      	cmp	r5, r1
    176c:      	bhi	0x16e4 <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x8c
    176e:      	b	0x192e <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1bc
    1770:      	cmp	r1, r5
    1772:      	clz	lr, r5
    1776:      	bhs	0x17b4 <compiler_rt.int.__udivmoddi4+0x17c> @ imm = #0x3a
    1778:      	cmp.w	lr, #0x0
    177c:      	beq.w	0x1884 <compiler_rt.int.__udivmoddi4+0x24c> @ imm = #0x104
    1780:      	rsb.w	r2, lr, #0x0
    1784:      	and	r2, r2, #0x1f
    1788:      	lsl.w	r1, r1, lr
    178c:      	lsr.w	r2, r0, r2
    1790:      	lsl.w	r5, r5, lr
    1794:      	orrs	r2, r1
    1796:      	lsl.w	r0, r0, lr
    179a:      	b	0x1886 <compiler_rt.int.__udivmoddi4+0x24e> @ imm = #0xe8
    179c:      	cbz	r6, 0x17a6 <compiler_rt.int.__udivmoddi4+0x16e> @ imm = #0x6
    179e:      	subs	r0, r0, r5
    17a0:      	sbcs	r1, r3
    17a2:      	strd	r0, r1, [r6]
    17a6:      	movs	r1, #0x0
    17a8:      	movs	r0, #0x1
    17aa:      	add	sp, #0x20
    17ac:      	pop.w	{r8, r9, r10, r11}
    17b0:      	pop	{r4, r5, r6, r7, pc}
    17b2:      	nop
    17b4:      	udiv	r2, r1, r5
    17b8:      	cmp.w	lr, #0x0
    17bc:      	mls	r8, r2, r5, r1
    17c0:      	mov	r1, r2
    17c2:      	beq	0x17e0 <compiler_rt.int.__udivmoddi4+0x1a8> @ imm = #0x1a
    17c4:      	rsb.w	r3, lr, #0x0
    17c8:      	and	r3, r3, #0x1f
    17cc:      	lsl.w	r2, r8, lr
    17d0:      	lsr.w	r3, r0, r3
    17d4:      	lsl.w	r5, r5, lr
    17d8:      	orr.w	r8, r2, r3
    17dc:      	lsl.w	r0, r0, lr
    17e0:      	lsrs	r4, r5, #0x10
    17e2:      	str	r5, [sp, #0x10]
    17e4:      	uxth.w	r12, r5
    17e8:      	udiv	r5, r8, r4
    17ec:      	lsr.w	r10, r0, #0x10
    17f0:      	mls	r6, r5, r4, r8
    17f4:      	uxth.w	r9, r0
    17f8:      	movs	r3, #0x0
    17fa:      	b	0x180a <compiler_rt.int.__udivmoddi4+0x1d2> @ imm = #0xc
    17fc:      	subs	r0, r5, #0x4
    17fe:      	adds	r6, r2, r4
    1800:      	cmp.w	r3, r6, lsr #16
    1804:      	mov	r5, r0
    1806:      	bne.w	0x1a46 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x23c
    180a:      	cmp.w	r3, r5, lsr #16
    180e:      	bne	0x181e <compiler_rt.int.__udivmoddi4+0x1e6> @ imm = #0xc
    1810:      	mul	r0, r5, r12
    1814:      	orr.w	r2, r10, r6, lsl #16
    1818:      	cmp	r0, r2
    181a:      	bls.w	0x1a44 <compiler_rt.int.__udivmoddi4+0x40c> @ imm = #0x226
    181e:      	adds	r2, r6, r4
    1820:      	cmp.w	r3, r2, lsr #16
    1824:      	sub.w	r0, r5, #0x1
    1828:      	bne.w	0x1a46 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x21a
    182c:      	cmp.w	r3, r0, lsr #16
    1830:      	bne	0x1840 <compiler_rt.int.__udivmoddi4+0x208> @ imm = #0xc
    1832:      	mul	r11, r0, r12
    1836:      	orr.w	r6, r10, r2, lsl #16
    183a:      	cmp	r11, r6
    183c:      	bls.w	0x1a46 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x206
    1840:      	add	r2, r4
    1842:      	cmp.w	r3, r2, lsr #16
    1846:      	sub.w	r0, r5, #0x2
    184a:      	bne.w	0x1a46 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1f8
    184e:      	cmp.w	r3, r0, lsr #16
    1852:      	bne	0x1862 <compiler_rt.int.__udivmoddi4+0x22a> @ imm = #0xc
    1854:      	mul	r11, r0, r12
    1858:      	orr.w	r6, r10, r2, lsl #16
    185c:      	cmp	r11, r6
    185e:      	bls.w	0x1a46 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1e4
    1862:      	add	r2, r4
    1864:      	cmp.w	r3, r2, lsr #16
    1868:      	sub.w	r0, r5, #0x3
    186c:      	bne.w	0x1a46 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1d6
    1870:      	cmp.w	r3, r0, lsr #16
    1874:      	bne	0x17fc <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x7c
    1876:      	mul	r11, r0, r12
    187a:      	orr.w	r6, r10, r2, lsl #16
    187e:      	cmp	r11, r6
    1880:      	bhi	0x17fc <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x88
    1882:      	b	0x1a46 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1c0
    1884:      	mov	r2, r1
    1886:      	lsrs	r4, r5, #0x10
    1888:      	udiv	r6, r2, r4
    188c:      	mov	r11, r5
    188e:      	uxth.w	r9, r5
    1892:      	mls	r5, r6, r4, r2
    1896:      	lsr.w	r8, r0, #0x10
    189a:      	uxth.w	r12, r0
    189e:      	mov	r1, r2
    18a0:      	movs	r3, #0x0
    18a2:      	b	0x18b2 <compiler_rt.int.__udivmoddi4+0x27a> @ imm = #0xc
    18a4:      	subs	r0, r6, #0x4
    18a6:      	adds	r5, r2, r4
    18a8:      	cmp.w	r3, r5, lsr #16
    18ac:      	mov	r6, r0
    18ae:      	bne.w	0x1ade <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x22c
    18b2:      	cmp.w	r3, r6, lsr #16
    18b6:      	bne	0x18c6 <compiler_rt.int.__udivmoddi4+0x28e> @ imm = #0xc
    18b8:      	mul	r0, r6, r9
    18bc:      	orr.w	r2, r8, r5, lsl #16
    18c0:      	cmp	r0, r2
    18c2:      	bls.w	0x1adc <compiler_rt.int.__udivmoddi4+0x4a4> @ imm = #0x216
    18c6:      	adds	r2, r5, r4
    18c8:      	cmp.w	r3, r2, lsr #16
    18cc:      	sub.w	r0, r6, #0x1
    18d0:      	bne.w	0x1ade <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x20a
    18d4:      	cmp.w	r3, r0, lsr #16
    18d8:      	bne	0x18e8 <compiler_rt.int.__udivmoddi4+0x2b0> @ imm = #0xc
    18da:      	mul	r10, r0, r9
    18de:      	orr.w	r5, r8, r2, lsl #16
    18e2:      	cmp	r10, r5
    18e4:      	bls.w	0x1ade <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1f6
    18e8:      	add	r2, r4
    18ea:      	cmp.w	r3, r2, lsr #16
    18ee:      	sub.w	r0, r6, #0x2
    18f2:      	bne.w	0x1ade <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1e8
    18f6:      	cmp.w	r3, r0, lsr #16
    18fa:      	bne	0x190a <compiler_rt.int.__udivmoddi4+0x2d2> @ imm = #0xc
    18fc:      	mul	r10, r0, r9
    1900:      	orr.w	r5, r8, r2, lsl #16
    1904:      	cmp	r10, r5
    1906:      	bls.w	0x1ade <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1d4
    190a:      	add	r2, r4
    190c:      	cmp.w	r3, r2, lsr #16
    1910:      	sub.w	r0, r6, #0x3
    1914:      	bne.w	0x1ade <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1c6
    1918:      	cmp.w	r3, r0, lsr #16
    191c:      	bne	0x18a4 <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x7c
    191e:      	mul	r10, r0, r9
    1922:      	orr.w	r5, r8, r2, lsl #16
    1926:      	cmp	r10, r5
    1928:      	bhi	0x18a4 <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x88
    192a:      	b	0x1ade <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1b0
    192c:      	mov	r6, r4
    192e:      	orr.w	r2, r11, r0, lsl #16
    1932:      	ldr	r0, [sp]
    1934:      	ldr.w	r9, [sp, #0x4]
    1938:      	mls	r2, r6, r0, r2
    193c:      	mov.w	r8, #0x0
    1940:      	udiv	r4, r2, lr
    1944:      	mls	r2, r4, lr, r2
    1948:      	b	0x1958 <compiler_rt.int.__udivmoddi4+0x320> @ imm = #0xc
    194a:      	nop
    194c:      	subs	r4, #0x4
    194e:      	add	r2, lr
    1950:      	cmp.w	r2, #0x10000
    1954:      	mov	r5, r4
    1956:      	bhs	0x19ca <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x70
    1958:      	cmp.w	r8, r4, lsr #16
    195c:      	bne	0x196a <compiler_rt.int.__udivmoddi4+0x332> @ imm = #0xa
    195e:      	mul	r1, r4, r12
    1962:      	orr.w	r5, r3, r2, lsl #16
    1966:      	cmp	r1, r5
    1968:      	bls	0x19c8 <compiler_rt.int.__udivmoddi4+0x390> @ imm = #0x5c
    196a:      	add	r2, lr
    196c:      	cmp.w	r8, r2, lsr #16
    1970:      	sub.w	r5, r4, #0x1
    1974:      	bne	0x19ca <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x52
    1976:      	cmp.w	r8, r5, lsr #16
    197a:      	bne	0x1988 <compiler_rt.int.__udivmoddi4+0x350> @ imm = #0xa
    197c:      	mul	r1, r5, r12
    1980:      	orr.w	r0, r3, r2, lsl #16
    1984:      	cmp	r1, r0
    1986:      	bls	0x19ca <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x40
    1988:      	add	r2, lr
    198a:      	cmp.w	r8, r2, lsr #16
    198e:      	sub.w	r5, r4, #0x2
    1992:      	bne	0x19ca <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x34
    1994:      	cmp.w	r8, r5, lsr #16
    1998:      	bne	0x19a6 <compiler_rt.int.__udivmoddi4+0x36e> @ imm = #0xa
    199a:      	mul	r0, r5, r12
    199e:      	orr.w	r1, r3, r2, lsl #16
    19a2:      	cmp	r0, r1
    19a4:      	bls	0x19ca <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x22
    19a6:      	add	r2, lr
    19a8:      	cmp.w	r8, r2, lsr #16
    19ac:      	sub.w	r5, r4, #0x3
    19b0:      	bne	0x19ca <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x16
    19b2:      	cmp.w	r8, r5, lsr #16
    19b6:      	bne	0x194c <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x6e
    19b8:      	mul	r0, r5, r12
    19bc:      	orr.w	r1, r3, r2, lsl #16
    19c0:      	cmp	r0, r1
    19c2:      	bhi	0x194c <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x7a
    19c4:      	b	0x19ca <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x2
    19c6:      	nop
    19c8:      	mov	r5, r4
    19ca:      	add.w	r0, r5, r6, lsl #16
    19ce:      	ldr	r2, [sp, #0x10]
    19d0:      	ldr	r6, [sp, #0x8]
    19d2:      	umull	r4, r1, r2, r0
    19d6:      	mov	r8, r0
    19d8:      	umull	r0, r3, r6, r0
    19dc:      	adds	r5, r0, r1
    19de:      	mov.w	r12, #0x0
    19e2:      	adc	r0, r12, #0x0
    19e6:      	orrs.w	r1, r3, r0
    19ea:      	ldr	r3, [r7, #0x8]
    19ec:      	ldr.w	lr, [sp, #0xc]
    19f0:      	strb.w	r0, [sp, #0x14]
    19f4:      	bne	0x1a00 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x8
    19f6:      	cmp	r5, lr
    19f8:      	bhi	0x1a00 <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x4
    19fa:      	bne	0x1a16 <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x18
    19fc:      	cmp	r4, r9
    19fe:      	bls	0x1a16 <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x14
    1a00:      	subs	r4, r4, r2
    1a02:      	adc	r0, r12, #0x0
    1a06:      	eor	r0, r0, #0x1
    1a0a:      	strb.w	r0, [sp, #0x18]
    1a0e:      	add	r0, r6
    1a10:      	sub.w	r8, r8, #0x1
    1a14:      	subs	r5, r5, r0
    1a16:      	cbz	r3, 0x1a36 <compiler_rt.int.__udivmoddi4+0x3fe> @ imm = #0x1c
    1a18:      	subs.w	r0, r9, r4
    1a1c:      	mov.w	r1, #0x0
    1a20:      	adc	r1, r1, #0x0
    1a24:      	eor	r1, r1, #0x1
    1a28:      	strb.w	r1, [sp, #0x1c]
    1a2c:      	add	r1, r5
    1a2e:      	sub.w	r1, lr, r1
    1a32:      	strd	r0, r1, [r3]
    1a36:      	movs	r1, #0x0
    1a38:      	mov	r0, r8
    1a3a:      	add	sp, #0x20
    1a3c:      	pop.w	{r8, r9, r10, r11}
    1a40:      	pop	{r4, r5, r6, r7, pc}
    1a42:      	nop
    1a44:      	mov	r0, r5
    1a46:      	ldr	r3, [sp, #0x10]
    1a48:      	orr.w	r2, r10, r8, lsl #16
    1a4c:      	mls	r8, r0, r3, r2
    1a50:      	mov.w	r10, #0x0
    1a54:      	udiv	r3, r8, r4
    1a58:      	mls	r5, r3, r4, r8
    1a5c:      	b	0x1a6e <compiler_rt.int.__udivmoddi4+0x436> @ imm = #0xe
    1a5e:      	nop
    1a60:      	subs	r3, #0x4
    1a62:      	adds	r5, r2, r4
    1a64:      	cmp.w	r5, #0x10000
    1a68:      	mov	r6, r3
    1a6a:      	bhs.w	0x1b72 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x104
    1a6e:      	cmp.w	r10, r3, lsr #16
    1a72:      	bne	0x1a80 <compiler_rt.int.__udivmoddi4+0x448> @ imm = #0xa
    1a74:      	mul	r2, r3, r12
    1a78:      	orr.w	r6, r9, r5, lsl #16
    1a7c:      	cmp	r2, r6
    1a7e:      	bls	0x1b70 <compiler_rt.int.__udivmoddi4+0x538> @ imm = #0xee
    1a80:      	adds	r2, r5, r4
    1a82:      	cmp.w	r10, r2, lsr #16
    1a86:      	sub.w	r6, r3, #0x1
    1a8a:      	bne	0x1b72 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xe4
    1a8c:      	cmp.w	r10, r6, lsr #16
    1a90:      	bne	0x1a9e <compiler_rt.int.__udivmoddi4+0x466> @ imm = #0xa
    1a92:      	mul	r11, r6, r12
    1a96:      	orr.w	r5, r9, r2, lsl #16
    1a9a:      	cmp	r11, r5
    1a9c:      	bls	0x1b72 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xd2
    1a9e:      	add	r2, r4
    1aa0:      	cmp.w	r10, r2, lsr #16
    1aa4:      	sub.w	r6, r3, #0x2
    1aa8:      	bne	0x1b72 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xc6
    1aaa:      	cmp.w	r10, r6, lsr #16
    1aae:      	bne	0x1abc <compiler_rt.int.__udivmoddi4+0x484> @ imm = #0xa
    1ab0:      	mul	r11, r6, r12
    1ab4:      	orr.w	r5, r9, r2, lsl #16
    1ab8:      	cmp	r11, r5
    1aba:      	bls	0x1b72 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xb4
    1abc:      	add	r2, r4
    1abe:      	cmp.w	r10, r2, lsr #16
    1ac2:      	sub.w	r6, r3, #0x3
    1ac6:      	bne	0x1b72 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xa8
    1ac8:      	cmp.w	r10, r6, lsr #16
    1acc:      	bne	0x1a60 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x70
    1ace:      	mul	r11, r6, r12
    1ad2:      	orr.w	r5, r9, r2, lsl #16
    1ad6:      	cmp	r11, r5
    1ad8:      	bhi	0x1a60 <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x7c
    1ada:      	b	0x1b72 <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x94
    1adc:      	mov	r0, r6
    1ade:      	orr.w	r1, r8, r1, lsl #16
    1ae2:      	mls	r8, r0, r11, r1
    1ae6:      	mov.w	r10, #0x0
    1aea:      	udiv	r1, r8, r4
    1aee:      	mls	r5, r1, r4, r8
    1af2:      	b	0x1b00 <compiler_rt.int.__udivmoddi4+0x4c8> @ imm = #0xa
    1af4:      	subs	r1, #0x4
    1af6:      	adds	r5, r2, r4
    1af8:      	cmp.w	r5, #0x10000
    1afc:      	mov	r6, r1
    1afe:      	bhs	0x1b86 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x84
    1b00:      	cmp.w	r10, r1, lsr #16
    1b04:      	bne	0x1b12 <compiler_rt.int.__udivmoddi4+0x4da> @ imm = #0xa
    1b06:      	mul	r2, r1, r9
    1b0a:      	orr.w	r6, r12, r5, lsl #16
    1b0e:      	cmp	r2, r6
    1b10:      	bls	0x1b84 <compiler_rt.int.__udivmoddi4+0x54c> @ imm = #0x70
    1b12:      	adds	r2, r5, r4
    1b14:      	cmp.w	r10, r2, lsr #16
    1b18:      	sub.w	r6, r1, #0x1
    1b1c:      	bne	0x1b86 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x66
    1b1e:      	cmp.w	r10, r6, lsr #16
    1b22:      	bne	0x1b30 <compiler_rt.int.__udivmoddi4+0x4f8> @ imm = #0xa
    1b24:      	mul	r5, r6, r9
    1b28:      	orr.w	r3, r12, r2, lsl #16
    1b2c:      	cmp	r5, r3
    1b2e:      	bls	0x1b86 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x54
    1b30:      	add	r2, r4
    1b32:      	cmp.w	r10, r2, lsr #16
    1b36:      	sub.w	r6, r1, #0x2
    1b3a:      	bne	0x1b86 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x48
    1b3c:      	cmp.w	r10, r6, lsr #16
    1b40:      	bne	0x1b4e <compiler_rt.int.__udivmoddi4+0x516> @ imm = #0xa
    1b42:      	mul	r3, r6, r9
    1b46:      	orr.w	r5, r12, r2, lsl #16
    1b4a:      	cmp	r3, r5
    1b4c:      	bls	0x1b86 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x36
    1b4e:      	add	r2, r4
    1b50:      	cmp.w	r10, r2, lsr #16
    1b54:      	sub.w	r6, r1, #0x3
    1b58:      	bne	0x1b86 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x2a
    1b5a:      	cmp.w	r10, r6, lsr #16
    1b5e:      	bne	0x1af4 <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x6e
    1b60:      	mul	r3, r6, r9
    1b64:      	orr.w	r5, r12, r2, lsl #16
    1b68:      	cmp	r3, r5
    1b6a:      	bhi	0x1af4 <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x7a
    1b6c:      	b	0x1b86 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x16
    1b6e:      	nop
    1b70:      	mov	r6, r3
    1b72:      	ldr	r3, [sp, #0x10]
    1b74:      	orr.w	r2, r9, r8, lsl #16
    1b78:      	mls	r2, r6, r3, r2
    1b7c:      	lsr.w	r2, r2, lr
    1b80:      	b	0x1b94 <compiler_rt.int.__udivmoddi4+0x55c> @ imm = #0x10
    1b82:      	nop
    1b84:      	mov	r6, r1
    1b86:      	orr.w	r1, r12, r8, lsl #16
    1b8a:      	mls	r1, r6, r11, r1
    1b8e:      	lsr.w	r2, r1, lr
    1b92:      	movs	r1, #0x0
    1b94:      	ldr	r5, [r7, #0x8]
    1b96:      	add.w	r0, r6, r0, lsl #16
    1b9a:      	cmp	r5, #0x0
    1b9c:      	itt	ne
    1b9e:      	movne	r3, #0x0
    1ba0:      	strdne	r2, r3, [r5]
    1ba4:      	add	sp, #0x20
    1ba6:      	pop.w	{r8, r9, r10, r11}
    1baa:      	pop	{r4, r5, r6, r7, pc}
    1bac:      	bmi	0x1b58 <compiler_rt.int.__udivmoddi4+0x520> @ imm = #-0x58
    1bae:      	bmi	0x1b5a <compiler_rt.int.__udivmoddi4+0x522> @ imm = #-0x58

00001bb0 <.L.str.1>:
    1bb0: 00 00 00 00 10 00 00 00         ........
    1bb8: 69 6e 74 65 67 65 72 20         integer 
    1bc0: 6f 76 65 72 66 6c 6f 77         overflow
    1bc8: 00 00 00 00 d4 d4 d4 d4         ........

00001bd0 <.L.str.3>:
    1bd0: 00 00 00 00 13 00 00 00         ........
    1bd8: 69 6e 64 65 78 20 6f 75         index ou
    1be0: 74 20 6f 66 20 62 6f 75         t of bou
    1be8: 6e 64 73 00                     nds.

00001bec <.L.str.4>:
    1bec: 00 00 00 00 00 00 00 00         ........
    1bf4: 00 00 00 00 d4 d4 d4 d4         ........
    1bfc: d4 d4 d4 d4                     ....

00001c00 <.L.str.5>:
    1c00: 00 00 00 00 0d 00 00 00         ........
    1c08: 69 73 6f 72 74 20 72 65         isort re
    1c10: 73 75 6c 74 3d 00 00 00         sult=...
    1c18: 00 00 00 00 07 00 00 00         ........
    1c20: 20 74 69 63 6b 73 3d 00          ticks=.
    1c28: 6f 75 74 20 6f 66 20 6d         out of m
    1c30: 65 6d 6f 72 79 00 68 61         emory.ha
    1c38: 72 64 20 66 61 75 6c 74         rd fault
    1c40: 00 20 61 6c 6c 6f 63 61         . alloca
    1c48: 74 69 6f 6e 73 3d 00 20         tions=. 
    1c50: 73 74 61 63 6b 3d 00 23         stack=.#
    1c58: 7a 73 20 68 65 61 70 5f         zs heap_
    1c60: 70 65 61 6b 3d 00 20 6c         peak=. l
    1c68: 69 76 65 3d 00 20 68 65         ive=. he
    1c70: 61 70 5f 72 65 73 65 72         ap_reser
    1c78: 76 65 64 3d 00 70 61 6e         ved=.pan
    1c80: 69 63 3a 20 00 0a 00 d4         ic: ....
