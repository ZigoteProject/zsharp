
bench/mcu/out/pipe.elf:	file format elf32-littlearm

Disassembly of section .text:

00000000 <vectors>:
       0: 00 00 40 20 bd 0e 00 00         ..@ ....
       8: 05 10 00 00 05 10 00 00         ........
      10: 05 10 00 00 05 10 00 00         ........
      18: 05 10 00 00 00 00 00 00         ........
      20: 00 00 00 00 00 00 00 00         ........
      28: 00 00 00 00 05 10 00 00         ........
      30: 05 10 00 00 00 00 00 00         ........
      38: 05 10 00 00 15 10 00 00         ........

00000040 <.Lclo.main$lam3.1>:
      40:      	ldr	r0, [r0, #0xc]
      42:      	adds	r0, r0, r1
      44:      	it	vc
      46:      	bxvc	lr
      48:      	push	{r7, lr}
      4a:      	movw	r0, #0x1a30
      4e:      	movt	r0, #0x0
      52:      	adds	r0, #0x8
      54:      	bl	0x464 <zs_panic_c>      @ imm = #0x40c

00000058 <.Lclodrop.main$lam3.1>:
      58:      	b.w	0x490 <zs_free>         @ imm = #0x434

0000005c <zs.List.rev<int>>:
      5c:      	push	{r4, r5, r6, r7, lr}
      5e:      	sub	sp, #0x4
      60:      	movw	r4, #0x1aa8
      64:      	movt	r4, #0x0
      68:      	movs	r5, #0x1
      6a:      	b	0x8c <zs.List.rev<int>+0x30> @ imm = #0x1e
      6c:      	subs	r1, #0x1
      6e:      	str	r1, [r0]
      70:      	ldr	r0, [r6]
      72:      	cmp	r0, #0x0
      74:      	itt	ne
      76:      	addne	r0, #0x1
      78:      	strne	r0, [r6]
      7a:      	movs	r0, #0x10
      7c:      	bl	0x3a0 <zs_alloc>        @ imm = #0x320
      80:      	strd	r5, r5, [r0]
      84:      	strd	r7, r4, [r0, #8]
      88:      	mov	r4, r0
      8a:      	mov	r0, r6
      8c:      	ldr	r1, [r0, #0x4]
      8e:      	cmp	r1, #0x1
      90:      	bne	0xa2 <zs.List.rev<int>+0x46> @ imm = #0xe
      92:      	ldr	r1, [r0]
      94:      	ldrd	r7, r6, [r0, #8]
      98:      	cmp	r1, #0x0
      9a:      	beq	0x70 <zs.List.rev<int>+0x14> @ imm = #-0x2e
      9c:      	cmp	r1, #0x1
      9e:      	beq	0x80 <zs.List.rev<int>+0x24> @ imm = #-0x22
      a0:      	b	0x6c <zs.List.rev<int>+0x10> @ imm = #-0x38
      a2:      	cbnz	r1, 0xce <zs.List.rev<int>+0x72> @ imm = #0x28
      a4:      	ldr	r1, [r0]
      a6:      	cmp	r1, #0x1
      a8:      	bne	0xba <zs.List.rev<int>+0x5e> @ imm = #0xe
      aa:      	ldr	r1, [r0, #0x4]
      ac:      	cmp	r1, #0x1
      ae:      	bne	0xc4 <zs.List.rev<int>+0x68> @ imm = #0x12
      b0:      	ldr	r5, [r0, #0xc]
      b2:      	bl	0x490 <zs_free>         @ imm = #0x3da
      b6:      	mov	r0, r5
      b8:      	b	0xa4 <zs.List.rev<int>+0x48> @ imm = #-0x18
      ba:      	cmp	r1, #0x0
      bc:      	itt	ne
      be:      	subne	r1, #0x1
      c0:      	strne	r1, [r0]
      c2:      	b	0xc8 <zs.List.rev<int>+0x6c> @ imm = #0x2
      c4:      	bl	0x490 <zs_free>         @ imm = #0x3c8
      c8:      	mov	r0, r4
      ca:      	add	sp, #0x4
      cc:      	pop	{r4, r5, r6, r7, pc}
      ce:      	movw	r0, #0x1a90
      d2:      	movt	r0, #0x0
      d6:      	adds	r0, #0x8
      d8:      	bl	0x464 <zs_panic_c>      @ imm = #0x388

000000dc <main>:
      dc:      	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
      e0:      	sub	sp, #0xc
      e2:      	bl	0xeb4 <zs_set_args>     @ imm = #0xdce
      e6:      	movs	r7, #0x0
      e8:      	movs	r4, #0x1
      ea:      	bl	0xfac <zs_ticks>        @ imm = #0xebe
      ee:      	movw	r9, #0x1aa8
      f2:      	movt	r9, #0x0
      f6:      	mov.w	r11, #0x3
      fa:      	mov.w	r8, #0x1
      fe:      	strd	r1, r0, [sp]
     102:      	nop
     104:      	movs	r0, #0x10
     106:      	str	r7, [sp, #0x8]
     108:      	bl	0x3a0 <zs_alloc>        @ imm = #0x294
     10c:      	mov	r5, r0
     10e:      	str	r4, [r0]
     110:      	movw	r0, #0x41
     114:      	movt	r0, #0x0
     118:      	str	r0, [r5, #0x4]
     11a:      	movw	r0, #0x59
     11e:      	movt	r0, #0x0
     122:      	strd	r0, r8, [r5, #8]
     126:      	movs	r7, #0xc7
     128:      	mov	r10, r9
     12a:      	mov	r0, r9
     12c:      	ldr	r2, [r5, #0x4]
     12e:      	mov	r9, r0
     130:      	mov	r0, r5
     132:      	mov	r1, r7
     134:      	blx	r2
     136:      	mov	r6, r0
     138:      	movs	r0, #0x10
     13a:      	bl	0x3a0 <zs_alloc>        @ imm = #0x262
     13e:      	subs	r7, #0x1
     140:      	adds	r1, r7, #0x1
     142:      	strd	r4, r4, [r0]
     146:      	str	r6, [r0, #0x8]
     148:      	str.w	r9, [r0, #0xc]
     14c:      	bne	0x12c <main+0x50>       @ imm = #-0x24
     14e:      	ldr	r1, [r5]
     150:      	mov	r9, r10
     152:      	cbz	r1, 0x168 <main+0x8c>   @ imm = #0x12
     154:      	cmp	r1, #0x1
     156:      	bne	0x164 <main+0x88>       @ imm = #0xa
     158:      	ldr	r1, [r5, #0x8]
     15a:      	mov	r6, r0
     15c:      	mov	r0, r5
     15e:      	blx	r1
     160:      	mov	r0, r6
     162:      	b	0x168 <main+0x8c>       @ imm = #0x2
     164:      	subs	r1, #0x1
     166:      	str	r1, [r5]
     168:      	mov	r7, r9
     16a:      	b	0x178 <main+0x9c>       @ imm = #0xa
     16c:      	strd	r4, r4, [r0]
     170:      	strd	r6, r7, [r0, #8]
     174:      	mov	r7, r0
     176:      	mov	r0, r5
     178:      	ldr	r1, [r0, #0x4]
     17a:      	cmp	r1, #0x1
     17c:      	bne	0x1b4 <main+0xd8>       @ imm = #0x34
     17e:      	ldr	r2, [r0]
     180:      	ldrd	r1, r5, [r0, #8]
     184:      	cbz	r2, 0x18e <main+0xb2>   @ imm = #0x6
     186:      	cmp	r2, #0x1
     188:      	beq	0x19a <main+0xbe>       @ imm = #0xe
     18a:      	subs	r2, #0x1
     18c:      	str	r2, [r0]
     18e:      	ldr	r0, [r5]
     190:      	cmp	r0, #0x0
     192:      	itt	ne
     194:      	addne	r0, #0x1
     196:      	strne	r0, [r5]
     198:      	movs	r0, #0x0
     19a:      	smull	r6, r1, r1, r11
     19e:      	cmp.w	r1, r6, asr #31
     1a2:      	bne.w	0x390 <main+0x2b4>      @ imm = #0x1ea
     1a6:      	cmp	r0, #0x0
     1a8:      	bne	0x16c <main+0x90>       @ imm = #-0x40
     1aa:      	movs	r0, #0x10
     1ac:      	bl	0x3a0 <zs_alloc>        @ imm = #0x1f0
     1b0:      	b	0x16c <main+0x90>       @ imm = #-0x48
     1b2:      	nop
     1b4:      	cmp	r1, #0x0
     1b6:      	bne.w	0x382 <main+0x2a6>      @ imm = #0x1c8
     1ba:      	nop
     1bc:      	ldr	r1, [r0]
     1be:      	cmp	r1, #0x1
     1c0:      	bne	0x1d4 <main+0xf8>       @ imm = #0x10
     1c2:      	ldr	r1, [r0, #0x4]
     1c4:      	cmp	r1, #0x1
     1c6:      	bne	0x1e0 <main+0x104>      @ imm = #0x16
     1c8:      	ldr	r5, [r0, #0xc]
     1ca:      	bl	0x490 <zs_free>         @ imm = #0x2c2
     1ce:      	mov	r0, r5
     1d0:      	b	0x1bc <main+0xe0>       @ imm = #-0x18
     1d2:      	nop
     1d4:      	cmp	r1, #0x0
     1d6:      	itt	ne
     1d8:      	subne	r1, #0x1
     1da:      	strne	r1, [r0]
     1dc:      	b	0x1e4 <main+0x108>      @ imm = #0x4
     1de:      	nop
     1e0:      	bl	0x490 <zs_free>         @ imm = #0x2ac
     1e4:      	mov	r0, r7
     1e6:      	bl	0x5c <zs.List.rev<int>> @ imm = #-0x18e
     1ea:      	mov	r5, r0
     1ec:      	mov	r7, r9
     1ee:      	nop
     1f0:      	mov	r0, r5
     1f2:      	ldr	r1, [r0, #0x4]
     1f4:      	cmp	r1, #0x1
     1f6:      	bne	0x244 <main+0x168>      @ imm = #0x4a
     1f8:      	ldr	r1, [r0]
     1fa:      	ldrd	r6, r5, [r0, #8]
     1fe:      	cbz	r1, 0x210 <main+0x134>  @ imm = #0xe
     200:      	cmp	r1, #0x1
     202:      	bne	0x20c <main+0x130>      @ imm = #0x6
     204:      	mov	r1, r0
     206:      	lsls	r0, r6, #0x1f
     208:      	bne	0x220 <main+0x144>      @ imm = #0x14
     20a:      	b	0x22e <main+0x152>      @ imm = #0x20
     20c:      	subs	r1, #0x1
     20e:      	str	r1, [r0]
     210:      	ldr	r0, [r5]
     212:      	movs	r1, #0x0
     214:      	cmp	r0, #0x0
     216:      	itt	ne
     218:      	addne	r0, #0x1
     21a:      	strne	r0, [r5]
     21c:      	lsls	r0, r6, #0x1f
     21e:      	beq	0x22e <main+0x152>      @ imm = #0xc
     220:      	cmp	r1, #0x0
     222:      	mov	r0, r5
     224:      	beq	0x1f2 <main+0x116>      @ imm = #-0x36
     226:      	mov	r0, r1
     228:      	bl	0x490 <zs_free>         @ imm = #0x264
     22c:      	b	0x1f0 <main+0x114>      @ imm = #-0x40
     22e:      	cbnz	r1, 0x238 <main+0x15c>  @ imm = #0x6
     230:      	movs	r0, #0x10
     232:      	bl	0x3a0 <zs_alloc>        @ imm = #0x16a
     236:      	mov	r1, r0
     238:      	strd	r4, r4, [r1]
     23c:      	strd	r6, r7, [r1, #8]
     240:      	mov	r7, r1
     242:      	b	0x1f0 <main+0x114>      @ imm = #-0x56
     244:      	cmp	r1, #0x0
     246:      	bne.w	0x382 <main+0x2a6>      @ imm = #0x138
     24a:      	nop
     24c:      	ldr	r1, [r0]
     24e:      	cmp	r1, #0x1
     250:      	bne	0x264 <main+0x188>      @ imm = #0x10
     252:      	ldr	r1, [r0, #0x4]
     254:      	cmp	r1, #0x1
     256:      	bne	0x270 <main+0x194>      @ imm = #0x16
     258:      	ldr	r5, [r0, #0xc]
     25a:      	bl	0x490 <zs_free>         @ imm = #0x232
     25e:      	mov	r0, r5
     260:      	b	0x24c <main+0x170>      @ imm = #-0x18
     262:      	nop
     264:      	cmp	r1, #0x0
     266:      	itt	ne
     268:      	subne	r1, #0x1
     26a:      	strne	r1, [r0]
     26c:      	b	0x274 <main+0x198>      @ imm = #0x4
     26e:      	nop
     270:      	bl	0x490 <zs_free>         @ imm = #0x21c
     274:      	mov	r0, r7
     276:      	bl	0x5c <zs.List.rev<int>> @ imm = #-0x21e
     27a:      	movs	r5, #0x0
     27c:      	ldr	r1, [r0, #0x4]
     27e:      	cmp	r1, #0x1
     280:      	bne	0x2ac <main+0x1d0>      @ imm = #0x28
     282:      	ldr	r1, [r0]
     284:      	ldrd	r7, r6, [r0, #8]
     288:      	cbz	r1, 0x298 <main+0x1bc>  @ imm = #0xc
     28a:      	cmp	r1, #0x1
     28c:      	bne	0x294 <main+0x1b8>      @ imm = #0x4
     28e:      	bl	0x490 <zs_free>         @ imm = #0x1fe
     292:      	b	0x2a2 <main+0x1c6>      @ imm = #0xc
     294:      	subs	r1, #0x1
     296:      	str	r1, [r0]
     298:      	ldr	r0, [r6]
     29a:      	cmp	r0, #0x0
     29c:      	itt	ne
     29e:      	addne	r0, #0x1
     2a0:      	strne	r0, [r6]
     2a2:      	adds	r5, r5, r7
     2a4:      	bvs	0x390 <main+0x2b4>      @ imm = #0xe8
     2a6:      	mov	r0, r6
     2a8:      	b	0x27c <main+0x1a0>      @ imm = #-0x30
     2aa:      	nop
     2ac:      	cmp	r1, #0x0
     2ae:      	bne	0x382 <main+0x2a6>      @ imm = #0xd0
     2b0:      	ldr	r7, [sp, #0x8]
     2b2:      	nop
     2b4:      	ldr	r1, [r0]
     2b6:      	cmp	r1, #0x1
     2b8:      	bne	0x2cc <main+0x1f0>      @ imm = #0x10
     2ba:      	ldr	r1, [r0, #0x4]
     2bc:      	cmp	r1, #0x1
     2be:      	bne	0x2dc <main+0x200>      @ imm = #0x1a
     2c0:      	ldr	r6, [r0, #0xc]
     2c2:      	bl	0x490 <zs_free>         @ imm = #0x1ca
     2c6:      	mov	r0, r6
     2c8:      	b	0x2b4 <main+0x1d8>      @ imm = #-0x18
     2ca:      	nop
     2cc:      	cmp	r1, #0x0
     2ce:      	itt	ne
     2d0:      	subne	r1, #0x1
     2d2:      	strne	r1, [r0]
     2d4:      	adds	r7, r7, r5
     2d6:      	bvc	0x2e4 <main+0x208>      @ imm = #0xa
     2d8:      	b	0x390 <main+0x2b4>      @ imm = #0xb4
     2da:      	nop
     2dc:      	bl	0x490 <zs_free>         @ imm = #0x1b0
     2e0:      	adds	r7, r7, r5
     2e2:      	bvs	0x390 <main+0x2b4>      @ imm = #0xaa
     2e4:      	add.w	r8, r8, #0x1
     2e8:      	cmp.w	r8, #0x15
     2ec:      	bne.w	0x104 <main+0x28>       @ imm = #-0x1ec
     2f0:      	bl	0xfac <zs_ticks>        @ imm = #0xcb8
     2f4:      	mov	r5, r0
     2f6:      	mov	r6, r1
     2f8:      	asrs	r1, r7, #0x1f
     2fa:      	mov	r0, r7
     2fc:      	bl	0x824 <zs_str_of_i64>   @ imm = #0x524
     300:      	ldr	r1, [sp, #0x4]
     302:      	movs	r3, #0x0
     304:      	subs	r2, r5, r1
     306:      	ldr	r1, [sp]
     308:      	sbcs.w	r1, r6, r1
     30c:      	adc	r3, r3, #0x0
     310:      	eor	r3, r3, #0x1
     314:      	cmp	r3, #0x1
     316:      	beq	0x390 <main+0x2b4>      @ imm = #0x76
     318:      	mov	r5, r0
     31a:      	mov	r0, r2
     31c:      	bl	0x4e0 <zs_str_of_u64>   @ imm = #0x1c0
     320:      	mov	r4, r0
     322:      	movw	r0, #0x1a4c
     326:      	movt	r0, #0x0
     32a:      	bl	0xa4c <zs_print>        @ imm = #0x71e
     32e:      	movw	r0, #0x1a60
     332:      	movt	r0, #0x0
     336:      	bl	0xa4c <zs_print>        @ imm = #0x712
     33a:      	mov	r0, r5
     33c:      	bl	0xa4c <zs_print>        @ imm = #0x70c
     340:      	ldr	r0, [r5]
     342:      	cbz	r0, 0x354 <main+0x278>  @ imm = #0xe
     344:      	cmp	r0, #0x1
     346:      	bne	0x350 <main+0x274>      @ imm = #0x6
     348:      	mov	r0, r5
     34a:      	bl	0x490 <zs_free>         @ imm = #0x142
     34e:      	b	0x354 <main+0x278>      @ imm = #0x2
     350:      	subs	r0, #0x1
     352:      	str	r0, [r5]
     354:      	movw	r0, #0x1a7c
     358:      	movt	r0, #0x0
     35c:      	bl	0xa4c <zs_print>        @ imm = #0x6ec
     360:      	mov	r0, r4
     362:      	bl	0xb58 <zs_println>      @ imm = #0x7f2
     366:      	ldr	r0, [r4]
     368:      	cbz	r0, 0x37a <main+0x29e>  @ imm = #0xe
     36a:      	cmp	r0, #0x1
     36c:      	bne	0x376 <main+0x29a>      @ imm = #0x6
     36e:      	mov	r0, r4
     370:      	bl	0x490 <zs_free>         @ imm = #0x11c
     374:      	b	0x37a <main+0x29e>      @ imm = #0x2
     376:      	subs	r0, #0x1
     378:      	str	r0, [r4]
     37a:      	movs	r0, #0x0
     37c:      	add	sp, #0xc
     37e:      	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
     382:      	movw	r0, #0x1a90
     386:      	movt	r0, #0x0
     38a:      	adds	r0, #0x8
     38c:      	bl	0x464 <zs_panic_c>      @ imm = #0xd4
     390:      	movw	r0, #0x1a30
     394:      	movt	r0, #0x0
     398:      	adds	r0, #0x8
     39a:      	bl	0x464 <zs_panic_c>      @ imm = #0xc6
     39e:      	bmi	0x34a <main+0x26e>      @ imm = #-0x58

000003a0 <zs_alloc>:
     3a0:      	push	{r4, r6, r7, lr}
     3a2:      	add	r7, sp, #0x8
     3a4:      	adds	r0, #0x7
     3a6:      	lsrs	r2, r0, #0x3
     3a8:      	cmp	r2, #0x20
     3aa:      	bhi	0x3c8 <zs_alloc+0x28>   @ imm = #0x1a
     3ac:      	movw	r12, #0x0
     3b0:      	movt	r12, #0x2000
     3b4:      	ldr.w	r1, [r12, r2, lsl #2]
     3b8:      	cbz	r1, 0x3c8 <zs_alloc+0x28> @ imm = #0xc
     3ba:      	mov	r0, r1
     3bc:      	ldr	r3, [r1]
     3be:      	ldr	r1, [r0, #-8]!
     3c2:      	str.w	r3, [r12, r2, lsl #2]
     3c6:      	b	0x400 <zs_alloc+0x60>   @ imm = #0x36
     3c8:      	movw	r12, #0x84
     3cc:      	movt	r12, #0x2000
     3d0:      	ldr.w	r2, [r12]
     3d4:      	bic	r1, r0, #0x7
     3d8:      	adds	r3, r1, r2
     3da:      	movw	r0, #0xfff9
     3de:      	subs	r0, r3, r0
     3e0:      	cmn.w	r0, #0x10001
     3e4:      	blo	0x456 <zs_alloc+0xb6>   @ imm = #0x6e
     3e6:      	movw	lr, #0x88
     3ea:      	movt	lr, #0x2000
     3ee:      	add.w	r0, lr, r2
     3f2:      	adds	r3, #0x8
     3f4:      	str.w	r1, [lr, r2]
     3f8:      	movs	r2, #0x0
     3fa:      	str.w	r3, [r12]
     3fe:      	str	r2, [r0, #0x4]
     400:      	movw	lr, #0x88
     404:      	movt	lr, #0x2001
     408:      	ldr.w	r2, [lr]
     40c:      	movw	r12, #0x8c
     410:      	movt	r12, #0x2001
     414:      	ldr.w	r3, [r12]
     418:      	add	r1, r2
     41a:      	str.w	r1, [lr]
     41e:      	movw	lr, #0x90
     422:      	cmp	r1, r3
     424:      	it	hi
     426:      	strhi.w	r1, [r12]
     42a:      	movt	lr, #0x2001
     42e:      	movw	r12, #0x98
     432:      	ldrd	r2, r3, [lr]
     436:      	movt	r12, #0x2001
     43a:      	ldrd	r1, r4, [r12]
     43e:      	adds	r2, #0x1
     440:      	adc	r3, r3, #0x0
     444:      	adds	r1, #0x1
     446:      	strd	r2, r3, [lr]
     44a:      	adc	r2, r4, #0x0
     44e:      	adds	r0, #0x8
     450:      	strd	r1, r2, [r12]
     454:      	pop	{r4, r6, r7, pc}
     456:      	movw	r0, #0x1ab0
     45a:      	movt	r0, #0x0
     45e:      	bl	0x464 <zs_panic_c>      @ imm = #0x2
     462:      	bmi	0x40e <zs_alloc+0x6e>   @ imm = #-0x58

00000464 <zs_panic_c>:
     464:      	push	{r4, r6, r7, lr}
     466:      	add	r7, sp, #0x8
     468:      	mov	r4, r0
     46a:      	movw	r0, #0x1b05
     46e:      	movt	r0, #0x0
     472:      	bl	0xc74 <write_c>         @ imm = #0x7fe
     476:      	mov	r0, r4
     478:      	bl	0xc74 <write_c>         @ imm = #0x7f8
     47c:      	movw	r0, #0x1b0d
     480:      	movt	r0, #0x0
     484:      	bl	0xc74 <write_c>         @ imm = #0x7ec
     488:      	movs	r0, #0x86
     48a:      	bl	0xdb8 <stop>            @ imm = #0x92a
     48e:      	bmi	0x43a <zs_alloc+0x9a>   @ imm = #-0x58

00000490 <zs_free>:
     490:      	push	{r4, r6, r7, lr}
     492:      	add	r7, sp, #0x8
     494:      	movw	lr, #0x88
     498:      	movw	r12, #0x90
     49c:      	movt	lr, #0x2001
     4a0:      	movt	r12, #0x2001
     4a4:      	ldr	r1, [r0, #-8]
     4a8:      	ldr.w	r3, [lr]
     4ac:      	ldrd	r2, r4, [r12]
     4b0:      	subs	r3, r3, r1
     4b2:      	subs	r2, #0x1
     4b4:      	str.w	r3, [lr]
     4b8:      	sbc	r3, r4, #0x0
     4bc:      	lsrs	r4, r1, #0x3
     4be:      	cmp	r4, #0x20
     4c0:      	strd	r2, r3, [r12]
     4c4:      	it	hi
     4c6:      	pophi	{r4, r6, r7, pc}
     4c8:      	mvn	r2, #0x3
     4cc:      	and.w	r1, r2, r1, lsr #1
     4d0:      	movw	r2, #0x0
     4d4:      	movt	r2, #0x2000
     4d8:      	ldr	r3, [r2, r1]
     4da:      	str	r3, [r0]
     4dc:      	str	r0, [r2, r1]
     4de:      	pop	{r4, r6, r7, pc}

000004e0 <zs_str_of_u64>:
     4e0:      	push	{r4, r5, r6, r7, lr}
     4e2:      	add	r7, sp, #0xc
     4e4:      	push.w	{r8, r9, r10, r11}
     4e8:      	sub	sp, #0x34
     4ea:      	movw	r9, #0xcccd
     4ee:      	mov	r5, r1
     4f0:      	mov	r6, r0
     4f2:      	mov.w	r10, #0x1
     4f6:      	movt	r9, #0xcccc
     4fa:      	add.w	r8, sp, #0x1c
     4fe:      	nop
     500:      	lsrs	r0, r6, #0x1
     502:      	orr.w	r0, r0, r5, lsl #31
     506:      	adds.w	r1, r0, r5, lsr #1
     50a:      	adc	r1, r1, #0x0
     50e:      	umull	r2, r3, r1, r9
     512:      	bic	r2, r3, #0x3
     516:      	add.w	r2, r2, r3, lsr #2
     51a:      	subs	r1, r1, r2
     51c:      	subs	r1, r0, r1
     51e:      	umull	r0, r2, r1, r9
     522:      	add.w	r4, r0, r0, lsl #2
     526:      	lsr.w	r3, r5, #0x1
     52a:      	sub.w	r4, r6, r4, lsl #1
     52e:      	sbc	r3, r3, #0x0
     532:      	orr	r12, r4, #0x30
     536:      	subs.w	r4, r6, #0xa
     53a:      	add.w	r11, r8, r10
     53e:      	sbcs	r4, r5, #0x0
     542:      	strb	r12, [r11, #-1]
     546:      	blo	0x636 <zs_str_of_u64+0x156> @ imm = #0xec
     548:      	mov.w	r4, #0xcccccccc
     54c:      	mla	r1, r1, r4, r2
     550:      	lsrs	r2, r0, #0x1
     552:      	mla	r1, r3, r9, r1
     556:      	and	r0, r0, #0x1
     55a:      	orr.w	r2, r2, r1, lsl #31
     55e:      	adds.w	r1, r2, r1, lsr #1
     562:      	adc	r1, r1, #0x0
     566:      	umull	r2, r3, r1, r9
     56a:      	bic	r2, r3, #0x3
     56e:      	add.w	r2, r2, r3, lsr #2
     572:      	subs	r1, r1, r2
     574:      	orr.w	r0, r0, r1, lsl #1
     578:      	subs.w	r1, r6, #0x64
     57c:      	orr	r0, r0, #0x30
     580:      	sbcs	r1, r5, #0x0
     584:      	strb.w	r0, [r8, r10]
     588:      	blo	0x63e <zs_str_of_u64+0x15e> @ imm = #0xb2
     58a:      	mov	r0, r6
     58c:      	mov	r1, r5
     58e:      	movs	r2, #0x64
     590:      	movs	r3, #0x0
     592:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xf0a
     596:      	lsrs	r2, r0, #0x1
     598:      	orr.w	r2, r2, r1, lsl #31
     59c:      	adds.w	r1, r2, r1, lsr #1
     5a0:      	adc	r1, r1, #0x0
     5a4:      	umull	r2, r3, r1, r9
     5a8:      	bic	r2, r3, #0x3
     5ac:      	add.w	r2, r2, r3, lsr #2
     5b0:      	subs	r1, r1, r2
     5b2:      	and	r0, r0, #0x1
     5b6:      	orr.w	r0, r0, r1, lsl #1
     5ba:      	subs.w	r1, r6, #0x3e8
     5be:      	orr	r0, r0, #0x30
     5c2:      	sbcs	r1, r5, #0x0
     5c6:      	strb.w	r0, [r11, #0x1]
     5ca:      	blo	0x646 <zs_str_of_u64+0x166> @ imm = #0x78
     5cc:      	mov	r0, r6
     5ce:      	mov	r1, r5
     5d0:      	mov.w	r2, #0x3e8
     5d4:      	movs	r3, #0x0
     5d6:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xec6
     5da:      	lsrs	r2, r0, #0x1
     5dc:      	orr.w	r2, r2, r1, lsl #31
     5e0:      	adds.w	r1, r2, r1, lsr #1
     5e4:      	adc	r1, r1, #0x0
     5e8:      	umull	r2, r3, r1, r9
     5ec:      	bic	r2, r3, #0x3
     5f0:      	add.w	r2, r2, r3, lsr #2
     5f4:      	subs	r1, r1, r2
     5f6:      	and	r0, r0, #0x1
     5fa:      	orr.w	r0, r0, r1, lsl #1
     5fe:      	orr	r0, r0, #0x30
     602:      	strb.w	r0, [r11, #0x2]
     606:      	mov	r0, r6
     608:      	mov	r1, r5
     60a:      	movw	r2, #0x2710
     60e:      	movs	r3, #0x0
     610:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xe8c
     614:      	movw	r2, #0x270f
     618:      	subs	r2, r2, r6
     61a:      	mov.w	r2, #0x0
     61e:      	sbcs	r2, r5
     620:      	add.w	r10, r10, #0x4
     624:      	mov	r6, r0
     626:      	mov	r5, r1
     628:      	blo.w	0x500 <zs_str_of_u64+0x20> @ imm = #-0x12c
     62c:      	sub.w	r1, r10, #0x1
     630:      	sub.w	r12, r10, #0x2
     634:      	b	0x64e <zs_str_of_u64+0x16e> @ imm = #0x16
     636:      	sub.w	r12, r10, #0x1
     63a:      	mov	r1, r10
     63c:      	b	0x650 <zs_str_of_u64+0x170> @ imm = #0x10
     63e:      	add.w	r1, r10, #0x1
     642:      	mov	r12, r10
     644:      	b	0x64e <zs_str_of_u64+0x16e> @ imm = #0x6
     646:      	add.w	r1, r10, #0x2
     64a:      	add.w	r12, r10, #0x1
     64e:      	mov	r10, r1
     650:      	and	lr, r1, #0x3
     654:      	lsrs	r3, r1, #0x2
     656:      	mov.w	r1, #0x0
     65a:      	beq	0x68e <zs_str_of_u64+0x1ae> @ imm = #0x30
     65c:      	add	r6, sp, #0x4
     65e:      	add.w	r5, r12, r8
     662:      	sub.w	r9, r1, r3, lsl #2
     666:      	subs	r6, #0x3
     668:      	subs	r5, #0x1
     66a:      	nop
     66c:      	adds	r4, r5, r1
     66e:      	ldrb	r3, [r5, r1]
     670:      	ldrb	r0, [r4, #-2]
     674:      	ldrb	r2, [r4, #-1]
     678:      	ldrb	r4, [r4, #0x1]
     67a:      	subs	r1, #0x4
     67c:      	strb	r3, [r6, #4]!
     680:      	cmp	r9, r1
     682:      	strb	r4, [r6, #-1]
     686:      	strb	r2, [r6, #0x1]
     688:      	strb	r0, [r6, #0x2]
     68a:      	bne	0x66c <zs_str_of_u64+0x18c> @ imm = #-0x22
     68c:      	rsbs	r1, r1, #0
     68e:      	cmp.w	lr, #0x0
     692:      	beq	0x6c4 <zs_str_of_u64+0x1e4> @ imm = #0x2e
     694:      	sub.w	r0, r12, r1
     698:      	ldrb.w	r0, [r8, r0]
     69c:      	add	r3, sp, #0x4
     69e:      	cmp.w	lr, #0x1
     6a2:      	strb	r0, [r3, r1]
     6a4:      	beq	0x6c4 <zs_str_of_u64+0x1e4> @ imm = #0x1c
     6a6:      	adds	r0, r1, #0x1
     6a8:      	sub.w	r2, r12, r0
     6ac:      	ldrb.w	r2, [r8, r2]
     6b0:      	cmp.w	lr, #0x2
     6b4:      	strb	r2, [r3, r0]
     6b6:      	beq	0x6c4 <zs_str_of_u64+0x1e4> @ imm = #0xa
     6b8:      	adds	r0, r1, #0x2
     6ba:      	sub.w	r1, r12, r0
     6be:      	ldrb.w	r1, [r8, r1]
     6c2:      	strb	r1, [r3, r0]
     6c4:      	add	r0, sp, #0x4
     6c6:      	mov	r1, r10
     6c8:      	bl	0x6d4 <str_of>          @ imm = #0x8
     6cc:      	add	sp, #0x34
     6ce:      	pop.w	{r8, r9, r10, r11}
     6d2:      	pop	{r4, r5, r6, r7, pc}

000006d4 <str_of>:
     6d4:      	push	{r4, r5, r6, r7, lr}
     6d6:      	add	r7, sp, #0xc
     6d8:      	str	r11, [sp, #-4]!
     6dc:      	add.w	r2, r1, #0x10
     6e0:      	lsrs	r3, r2, #0x3
     6e2:      	cmp	r3, #0x20
     6e4:      	bhi	0x702 <str_of+0x2e>     @ imm = #0x1a
     6e6:      	movw	lr, #0x0
     6ea:      	movt	lr, #0x2000
     6ee:      	ldr.w	r4, [lr, r3, lsl #2]
     6f2:      	cbz	r4, 0x702 <str_of+0x2e> @ imm = #0xc
     6f4:      	mov	r12, r4
     6f6:      	ldr	r4, [r4]
     6f8:      	ldr	r2, [r12, #-8]!
     6fc:      	str.w	r4, [lr, r3, lsl #2]
     700:      	b	0x73a <str_of+0x66>     @ imm = #0x36
     702:      	movw	lr, #0x84
     706:      	movt	lr, #0x2000
     70a:      	ldr.w	r3, [lr]
     70e:      	bic	r2, r2, #0x7
     712:      	adds	r5, r2, r3
     714:      	movw	r4, #0xfff9
     718:      	subs	r4, r5, r4
     71a:      	cmn.w	r4, #0x10001
     71e:      	blo	0x818 <str_of+0x144>    @ imm = #0xf6
     720:      	movw	r4, #0x88
     724:      	movt	r4, #0x2000
     728:      	add.w	r12, r4, r3
     72c:      	adds	r5, #0x8
     72e:      	str	r2, [r4, r3]
     730:      	movs	r3, #0x0
     732:      	str.w	r5, [lr]
     736:      	str.w	r3, [r12, #0x4]
     73a:      	movw	r5, #0x88
     73e:      	movt	r5, #0x2001
     742:      	movw	lr, #0x8c
     746:      	ldr	r4, [r5]
     748:      	movt	lr, #0x2001
     74c:      	ldr.w	r3, [lr]
     750:      	add	r2, r4
     752:      	cmp	r2, r3
     754:      	str	r2, [r5]
     756:      	it	hi
     758:      	strhi.w	r2, [lr]
     75c:      	movw	lr, #0x90
     760:      	movt	lr, #0x2001
     764:      	movw	r4, #0x98
     768:      	ldrd	r3, r5, [lr]
     76c:      	movt	r4, #0x2001
     770:      	ldrd	r2, r6, [r4]
     774:      	adds	r3, #0x1
     776:      	adc	r5, r5, #0x0
     77a:      	adds	r2, #0x1
     77c:      	strd	r3, r5, [lr]
     780:      	adc	r3, r6, #0x0
     784:      	strd	r2, r3, [r4]
     788:      	movs	r3, #0x1
     78a:      	mov	r2, r12
     78c:      	str	r3, [r2, #8]!
     790:      	add.w	lr, r2, #0x8
     794:      	movs	r3, #0x0
     796:      	str	r1, [r2, #0x4]
     798:      	strb.w	r3, [lr, r1]
     79c:      	cbz	r1, 0x810 <str_of+0x13c> @ imm = #0x70
     79e:      	ands	r3, r1, #0x3
     7a2:      	beq	0x7c0 <str_of+0xec>     @ imm = #0x1a
     7a4:      	mov	r4, r0
     7a6:      	ldrb	r6, [r4], #1
     7aa:      	cmp	r3, #0x1
     7ac:      	strb.w	r6, [r12, #0x10]
     7b0:      	bne	0x7c8 <str_of+0xf4>     @ imm = #0x14
     7b2:      	subs	r3, r1, #0x1
     7b4:      	add.w	lr, r12, #0x11
     7b8:      	mov	r0, r4
     7ba:      	cmp	r1, #0x4
     7bc:      	bhs	0x7f2 <str_of+0x11e>    @ imm = #0x32
     7be:      	b	0x810 <str_of+0x13c>    @ imm = #0x4e
     7c0:      	mov	r3, r1
     7c2:      	cmp	r1, #0x4
     7c4:      	bhs	0x7f2 <str_of+0x11e>    @ imm = #0x2a
     7c6:      	b	0x810 <str_of+0x13c>    @ imm = #0x46
     7c8:      	ldrb	r6, [r0, #0x1]
     7ca:      	cmp	r3, #0x2
     7cc:      	strb.w	r6, [r12, #0x11]
     7d0:      	bne	0x7e0 <str_of+0x10c>    @ imm = #0xc
     7d2:      	subs	r3, r1, #0x2
     7d4:      	adds	r0, #0x2
     7d6:      	add.w	lr, r12, #0x12
     7da:      	cmp	r1, #0x4
     7dc:      	bhs	0x7f2 <str_of+0x11e>    @ imm = #0x12
     7de:      	b	0x810 <str_of+0x13c>    @ imm = #0x2e
     7e0:      	ldrb	r4, [r0, #0x2]
     7e2:      	subs	r3, r1, #0x3
     7e4:      	adds	r0, #0x3
     7e6:      	add.w	lr, r12, #0x13
     7ea:      	strb.w	r4, [r12, #0x12]
     7ee:      	cmp	r1, #0x4
     7f0:      	blo	0x810 <str_of+0x13c>    @ imm = #0x1c
     7f2:      	subs	r0, #0x4
     7f4:      	sub.w	r1, lr, #0x4
     7f8:      	ldrb	r6, [r0, #4]!
     7fc:      	subs	r3, #0x4
     7fe:      	strb	r6, [r1, #4]!
     802:      	ldrb	r6, [r0, #0x1]
     804:      	strb	r6, [r1, #0x1]
     806:      	ldrb	r6, [r0, #0x2]
     808:      	strb	r6, [r1, #0x2]
     80a:      	ldrb	r6, [r0, #0x3]
     80c:      	strb	r6, [r1, #0x3]
     80e:      	bne	0x7f8 <str_of+0x124>    @ imm = #-0x1a
     810:      	mov	r0, r2
     812:      	ldr	r11, [sp], #4
     816:      	pop	{r4, r5, r6, r7, pc}
     818:      	movw	r0, #0x1ab0
     81c:      	movt	r0, #0x0
     820:      	bl	0x464 <zs_panic_c>      @ imm = #-0x3c0

00000824 <zs_str_of_i64>:
     824:      	push	{r4, r5, r6, r7, lr}
     826:      	add	r7, sp, #0xc
     828:      	push.w	{r8, r9, r10, r11}
     82c:      	sub	sp, #0x3c
     82e:      	cmp.w	r1, #0xffffffff
     832:      	add	r2, sp, #0xc
     834:      	ble	0x83c <zs_str_of_i64+0x18> @ imm = #0x4
     836:      	str	r2, [sp, #0x8]
     838:      	movs	r2, #0x0
     83a:      	b	0x848 <zs_str_of_i64+0x24> @ imm = #0xa
     83c:      	adds	r2, #0x1
     83e:      	str	r2, [sp, #0x8]
     840:      	movs	r2, #0x2d
     842:      	strb.w	r2, [sp, #0xc]
     846:      	movs	r2, #0x1
     848:      	eor.w	r0, r0, r1, asr #31
     84c:      	str	r2, [sp, #0x4]
     84e:      	eor.w	r2, r1, r1, asr #31
     852:      	subs.w	r4, r0, r1, asr #31
     856:      	movw	r8, #0xcccd
     85a:      	sbc.w	r5, r2, r1, asr #31
     85e:      	mov.w	r9, #0x1
     862:      	movt	r8, #0xcccc
     866:      	add.w	r10, sp, #0x24
     86a:      	nop
     86c:      	lsrs	r0, r4, #0x1
     86e:      	orr.w	r0, r0, r5, lsl #31
     872:      	adds.w	r1, r0, r5, lsr #1
     876:      	adc	r1, r1, #0x0
     87a:      	umull	r2, r3, r1, r8
     87e:      	bic	r2, r3, #0x3
     882:      	add.w	r2, r2, r3, lsr #2
     886:      	subs	r1, r1, r2
     888:      	subs	r1, r0, r1
     88a:      	umull	r0, r2, r1, r8
     88e:      	add.w	r6, r0, r0, lsl #2
     892:      	lsr.w	r3, r5, #0x1
     896:      	sub.w	r6, r4, r6, lsl #1
     89a:      	sbc	r3, r3, #0x0
     89e:      	orr	r12, r6, #0x30
     8a2:      	subs.w	r6, r4, #0xa
     8a6:      	add.w	r11, r10, r9
     8aa:      	sbcs	r6, r5, #0x0
     8ae:      	strb	r12, [r11, #-1]
     8b2:      	blo	0x9a2 <zs_str_of_i64+0x17e> @ imm = #0xec
     8b4:      	mov.w	r6, #0xcccccccc
     8b8:      	mla	r1, r1, r6, r2
     8bc:      	lsrs	r2, r0, #0x1
     8be:      	mla	r1, r3, r8, r1
     8c2:      	and	r0, r0, #0x1
     8c6:      	orr.w	r2, r2, r1, lsl #31
     8ca:      	adds.w	r1, r2, r1, lsr #1
     8ce:      	adc	r1, r1, #0x0
     8d2:      	umull	r2, r3, r1, r8
     8d6:      	bic	r2, r3, #0x3
     8da:      	add.w	r2, r2, r3, lsr #2
     8de:      	subs	r1, r1, r2
     8e0:      	orr.w	r0, r0, r1, lsl #1
     8e4:      	subs.w	r1, r4, #0x64
     8e8:      	orr	r0, r0, #0x30
     8ec:      	sbcs	r1, r5, #0x0
     8f0:      	strb.w	r0, [r10, r9]
     8f4:      	blo	0x9aa <zs_str_of_i64+0x186> @ imm = #0xb2
     8f6:      	mov	r0, r4
     8f8:      	mov	r1, r5
     8fa:      	movs	r2, #0x64
     8fc:      	movs	r3, #0x0
     8fe:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xb9e
     902:      	lsrs	r2, r0, #0x1
     904:      	orr.w	r2, r2, r1, lsl #31
     908:      	adds.w	r1, r2, r1, lsr #1
     90c:      	adc	r1, r1, #0x0
     910:      	umull	r2, r3, r1, r8
     914:      	bic	r2, r3, #0x3
     918:      	add.w	r2, r2, r3, lsr #2
     91c:      	subs	r1, r1, r2
     91e:      	and	r0, r0, #0x1
     922:      	orr.w	r0, r0, r1, lsl #1
     926:      	subs.w	r1, r4, #0x3e8
     92a:      	orr	r0, r0, #0x30
     92e:      	sbcs	r1, r5, #0x0
     932:      	strb.w	r0, [r11, #0x1]
     936:      	blo	0x9b2 <zs_str_of_i64+0x18e> @ imm = #0x78
     938:      	mov	r0, r4
     93a:      	mov	r1, r5
     93c:      	mov.w	r2, #0x3e8
     940:      	movs	r3, #0x0
     942:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xb5a
     946:      	lsrs	r2, r0, #0x1
     948:      	orr.w	r2, r2, r1, lsl #31
     94c:      	adds.w	r1, r2, r1, lsr #1
     950:      	adc	r1, r1, #0x0
     954:      	umull	r2, r3, r1, r8
     958:      	bic	r2, r3, #0x3
     95c:      	add.w	r2, r2, r3, lsr #2
     960:      	subs	r1, r1, r2
     962:      	and	r0, r0, #0x1
     966:      	orr.w	r0, r0, r1, lsl #1
     96a:      	orr	r0, r0, #0x30
     96e:      	strb.w	r0, [r11, #0x2]
     972:      	mov	r0, r4
     974:      	mov	r1, r5
     976:      	movw	r2, #0x2710
     97a:      	movs	r3, #0x0
     97c:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0xb20
     980:      	movw	r2, #0x270f
     984:      	subs	r2, r2, r4
     986:      	mov.w	r2, #0x0
     98a:      	sbcs	r2, r5
     98c:      	add.w	r9, r9, #0x4
     990:      	mov	r4, r0
     992:      	mov	r5, r1
     994:      	blo.w	0x86c <zs_str_of_i64+0x48> @ imm = #-0x12c
     998:      	sub.w	r1, r9, #0x1
     99c:      	sub.w	r12, r9, #0x2
     9a0:      	b	0x9ba <zs_str_of_i64+0x196> @ imm = #0x16
     9a2:      	sub.w	r12, r9, #0x1
     9a6:      	mov	r1, r9
     9a8:      	b	0x9bc <zs_str_of_i64+0x198> @ imm = #0x10
     9aa:      	add.w	r1, r9, #0x1
     9ae:      	mov	r12, r9
     9b0:      	b	0x9ba <zs_str_of_i64+0x196> @ imm = #0x6
     9b2:      	add.w	r1, r9, #0x2
     9b6:      	add.w	r12, r9, #0x1
     9ba:      	mov	r9, r1
     9bc:      	ldr.w	r8, [sp, #0x8]
     9c0:      	and	lr, r1, #0x3
     9c4:      	lsrs	r3, r1, #0x2
     9c6:      	mov.w	r1, #0x0
     9ca:      	beq	0x9fc <zs_str_of_i64+0x1d8> @ imm = #0x2e
     9cc:      	add.w	r6, r12, r10
     9d0:      	sub.w	r3, r1, r3, lsl #2
     9d4:      	sub.w	r5, r8, #0x3
     9d8:      	subs	r4, r6, #0x1
     9da:      	nop
     9dc:      	adds	r6, r4, r1
     9de:      	ldrb	r0, [r6, #0x1]
     9e0:      	ldrb	r2, [r6, #-1]
     9e4:      	strb	r0, [r5, #0x3]
     9e6:      	ldrb	r0, [r4, r1]
     9e8:      	subs	r1, #0x4
     9ea:      	strb	r0, [r5, #4]!
     9ee:      	ldrb	r0, [r6, #-2]
     9f2:      	cmp	r3, r1
     9f4:      	strb	r2, [r5, #0x1]
     9f6:      	strb	r0, [r5, #0x2]
     9f8:      	bne	0x9dc <zs_str_of_i64+0x1b8> @ imm = #-0x20
     9fa:      	rsbs	r1, r1, #0
     9fc:      	cmp.w	lr, #0x0
     a00:      	beq	0xa36 <zs_str_of_i64+0x212> @ imm = #0x32
     a02:      	sub.w	r0, r12, r1
     a06:      	ldrb.w	r0, [r10, r0]
     a0a:      	cmp.w	lr, #0x1
     a0e:      	strb.w	r0, [r8, r1]
     a12:      	beq	0xa36 <zs_str_of_i64+0x212> @ imm = #0x20
     a14:      	adds	r0, r1, #0x1
     a16:      	sub.w	r2, r12, r0
     a1a:      	ldrb.w	r2, [r10, r2]
     a1e:      	cmp.w	lr, #0x2
     a22:      	strb.w	r2, [r8, r0]
     a26:      	beq	0xa36 <zs_str_of_i64+0x212> @ imm = #0xc
     a28:      	adds	r0, r1, #0x2
     a2a:      	sub.w	r1, r12, r0
     a2e:      	ldrb.w	r1, [r10, r1]
     a32:      	strb.w	r1, [r8, r0]
     a36:      	ldr	r0, [sp, #0x4]
     a38:      	add.w	r1, r9, r0
     a3c:      	add	r0, sp, #0xc
     a3e:      	bl	0x6d4 <str_of>          @ imm = #-0x36e
     a42:      	add	sp, #0x3c
     a44:      	pop.w	{r8, r9, r10, r11}
     a48:      	pop	{r4, r5, r6, r7, pc}
     a4a:      	bmi	0x9f6 <zs_str_of_i64+0x1d2> @ imm = #-0x58

00000a4c <zs_print>:
     a4c:      	push	{r4, r5, r6, r7, lr}
     a4e:      	add	r7, sp, #0xc
     a50:      	push.w	{r8, r9, r10, r11}
     a54:      	sub	sp, #0x44
     a56:      	ldr.w	r11, [r0, #0x4]
     a5a:      	cmp.w	r11, #0x1
     a5e:      	blt	0xb50 <zs_print+0x104>  @ imm = #0xee
     a60:      	sub.w	r1, r7, #0x5d
     a64:      	movs	r2, #0x0
     a66:      	add.w	r3, r0, #0x8
     a6a:      	add.w	r12, r1, #0x1
     a6e:      	movs	r6, #0x40
     a70:      	mov.w	r9, #0x0
     a74:      	b	0xa94 <zs_print+0x48>   @ imm = #0x1c
     a76:      	nop
     a78:      	strb.w	r2, [r1, r8]
     a7c:      	movs	r0, #0x4
     a7e:      	subs.w	r11, r11, r8
     a82:      	bkpt	#0xab
     a84:      	sbc	r9, r9, #0x0
     a88:      	rsbs.w	r0, r11, #0x0
     a8c:      	sbcs.w	r0, r2, r9
     a90:      	add	r3, r8
     a92:      	bge	0xb50 <zs_print+0x104>  @ imm = #0xba
     a94:      	mov.w	r8, #0x40
     a98:      	cmp.w	r11, #0x40
     a9c:      	it	lo
     a9e:      	movlo	r8, r11
     aa0:      	cmp.w	r9, #0x0
     aa4:      	it	ne
     aa6:      	movne	r8, r6
     aa8:      	sub.w	r0, r8, #0x1
     aac:      	cmp	r0, #0x3
     aae:      	bhs	0xabc <zs_print+0x70>   @ imm = #0xa
     ab0:      	movs	r0, #0x0
     ab2:      	ands	r4, r8, #0x3
     ab6:      	bne	0xb1e <zs_print+0xd2>   @ imm = #0x64
     ab8:      	b	0xa78 <zs_print+0x2c>   @ imm = #-0x44
     aba:      	nop
     abc:      	bic	r0, r8, #0x3
     ac0:      	rsb.w	r10, r0, #0x0
     ac4:      	mov	r1, r3
     ac6:      	adds	r5, r3, #0x1
     ac8:      	mvn	r4, #0x3
     acc:      	adds	r2, r5, r4
     ace:      	ldrb	r6, [r2, #0x3]
     ad0:      	ldrb	r3, [r2, #0x4]
     ad2:      	ldrb	r0, [r2, #0x5]
     ad4:      	cmp	r6, #0x0
     ad6:      	ldrb	r2, [r2, #0x6]
     ad8:      	it	eq
     ada:      	moveq	r6, #0x20
     adc:      	add.w	lr, r12, r4
     ae0:      	cmp	r3, #0x0
     ae2:      	strb.w	r6, [lr, #0x3]
     ae6:      	it	eq
     ae8:      	moveq	r3, #0x20
     aea:      	strb.w	r3, [lr, #0x4]
     aee:      	cmp	r0, #0x0
     af0:      	it	eq
     af2:      	moveq	r0, #0x20
     af4:      	adds	r4, #0x4
     af6:      	strb.w	r0, [lr, #0x5]
     afa:      	cmp	r2, #0x0
     afc:      	add.w	r0, r10, r4
     b00:      	it	eq
     b02:      	moveq	r2, #0x20
     b04:      	adds	r0, #0x4
     b06:      	strb.w	r2, [lr, #0x6]
     b0a:      	bne	0xacc <zs_print+0x80>   @ imm = #-0x42
     b0c:      	adds	r0, r4, #0x4
     b0e:      	movs	r2, #0x0
     b10:      	mov	r3, r1
     b12:      	sub.w	r1, r7, #0x5d
     b16:      	movs	r6, #0x40
     b18:      	ands	r4, r8, #0x3
     b1c:      	beq	0xa78 <zs_print+0x2c>   @ imm = #-0xa8
     b1e:      	ldrb	r5, [r3, r0]
     b20:      	cmp	r5, #0x0
     b22:      	it	eq
     b24:      	moveq	r5, #0x20
     b26:      	cmp	r4, #0x1
     b28:      	strb	r5, [r1, r0]
     b2a:      	beq	0xa78 <zs_print+0x2c>   @ imm = #-0xb6
     b2c:      	add.w	r10, r0, #0x1
     b30:      	ldrb.w	r5, [r3, r10]
     b34:      	cmp	r5, #0x0
     b36:      	it	eq
     b38:      	moveq	r5, #0x20
     b3a:      	cmp	r4, #0x2
     b3c:      	strb.w	r5, [r1, r10]
     b40:      	beq	0xa78 <zs_print+0x2c>   @ imm = #-0xcc
     b42:      	adds	r0, #0x2
     b44:      	ldrb	r4, [r3, r0]
     b46:      	cmp	r4, #0x0
     b48:      	it	eq
     b4a:      	moveq	r4, #0x20
     b4c:      	strb	r4, [r1, r0]
     b4e:      	b	0xa78 <zs_print+0x2c>   @ imm = #-0xda
     b50:      	add	sp, #0x44
     b52:      	pop.w	{r8, r9, r10, r11}
     b56:      	pop	{r4, r5, r6, r7, pc}

00000b58 <zs_println>:
     b58:      	push	{r4, r5, r6, r7, lr}
     b5a:      	add	r7, sp, #0xc
     b5c:      	push.w	{r8, r9, r10, r11}
     b60:      	sub	sp, #0x44
     b62:      	ldr.w	r11, [r0, #0x4]
     b66:      	cmp.w	r11, #0x1
     b6a:      	blt	0xc5c <zs_println+0x104> @ imm = #0xee
     b6c:      	sub.w	r1, r7, #0x5d
     b70:      	movs	r2, #0x0
     b72:      	add.w	r3, r0, #0x8
     b76:      	add.w	r12, r1, #0x1
     b7a:      	movs	r6, #0x40
     b7c:      	mov.w	r9, #0x0
     b80:      	b	0xba0 <zs_println+0x48> @ imm = #0x1c
     b82:      	nop
     b84:      	strb.w	r2, [r1, r8]
     b88:      	movs	r0, #0x4
     b8a:      	subs.w	r11, r11, r8
     b8e:      	bkpt	#0xab
     b90:      	sbc	r9, r9, #0x0
     b94:      	rsbs.w	r0, r11, #0x0
     b98:      	sbcs.w	r0, r2, r9
     b9c:      	add	r3, r8
     b9e:      	bge	0xc5c <zs_println+0x104> @ imm = #0xba
     ba0:      	mov.w	r8, #0x40
     ba4:      	cmp.w	r11, #0x40
     ba8:      	it	lo
     baa:      	movlo	r8, r11
     bac:      	cmp.w	r9, #0x0
     bb0:      	it	ne
     bb2:      	movne	r8, r6
     bb4:      	sub.w	r0, r8, #0x1
     bb8:      	cmp	r0, #0x3
     bba:      	bhs	0xbc8 <zs_println+0x70> @ imm = #0xa
     bbc:      	movs	r0, #0x0
     bbe:      	ands	r4, r8, #0x3
     bc2:      	bne	0xc2a <zs_println+0xd2> @ imm = #0x64
     bc4:      	b	0xb84 <zs_println+0x2c> @ imm = #-0x44
     bc6:      	nop
     bc8:      	bic	r0, r8, #0x3
     bcc:      	rsb.w	r10, r0, #0x0
     bd0:      	mov	r1, r3
     bd2:      	adds	r5, r3, #0x1
     bd4:      	mvn	r4, #0x3
     bd8:      	adds	r2, r5, r4
     bda:      	ldrb	r6, [r2, #0x3]
     bdc:      	ldrb	r3, [r2, #0x4]
     bde:      	ldrb	r0, [r2, #0x5]
     be0:      	cmp	r6, #0x0
     be2:      	ldrb	r2, [r2, #0x6]
     be4:      	it	eq
     be6:      	moveq	r6, #0x20
     be8:      	add.w	lr, r12, r4
     bec:      	cmp	r3, #0x0
     bee:      	strb.w	r6, [lr, #0x3]
     bf2:      	it	eq
     bf4:      	moveq	r3, #0x20
     bf6:      	strb.w	r3, [lr, #0x4]
     bfa:      	cmp	r0, #0x0
     bfc:      	it	eq
     bfe:      	moveq	r0, #0x20
     c00:      	adds	r4, #0x4
     c02:      	strb.w	r0, [lr, #0x5]
     c06:      	cmp	r2, #0x0
     c08:      	add.w	r0, r10, r4
     c0c:      	it	eq
     c0e:      	moveq	r2, #0x20
     c10:      	adds	r0, #0x4
     c12:      	strb.w	r2, [lr, #0x6]
     c16:      	bne	0xbd8 <zs_println+0x80> @ imm = #-0x42
     c18:      	adds	r0, r4, #0x4
     c1a:      	movs	r2, #0x0
     c1c:      	mov	r3, r1
     c1e:      	sub.w	r1, r7, #0x5d
     c22:      	movs	r6, #0x40
     c24:      	ands	r4, r8, #0x3
     c28:      	beq	0xb84 <zs_println+0x2c> @ imm = #-0xa8
     c2a:      	ldrb	r5, [r3, r0]
     c2c:      	cmp	r5, #0x0
     c2e:      	it	eq
     c30:      	moveq	r5, #0x20
     c32:      	cmp	r4, #0x1
     c34:      	strb	r5, [r1, r0]
     c36:      	beq	0xb84 <zs_println+0x2c> @ imm = #-0xb6
     c38:      	add.w	r10, r0, #0x1
     c3c:      	ldrb.w	r5, [r3, r10]
     c40:      	cmp	r5, #0x0
     c42:      	it	eq
     c44:      	moveq	r5, #0x20
     c46:      	cmp	r4, #0x2
     c48:      	strb.w	r5, [r1, r10]
     c4c:      	beq	0xb84 <zs_println+0x2c> @ imm = #-0xcc
     c4e:      	adds	r0, #0x2
     c50:      	ldrb	r4, [r3, r0]
     c52:      	cmp	r4, #0x0
     c54:      	it	eq
     c56:      	moveq	r4, #0x20
     c58:      	strb	r4, [r1, r0]
     c5a:      	b	0xb84 <zs_println+0x2c> @ imm = #-0xda
     c5c:      	movs	r0, #0xa
     c5e:      	strh	r0, [r7, #-93]
     c62:      	movs	r0, #0x4
     c64:      	sub.w	r1, r7, #0x5d
     c68:      	bkpt	#0xab
     c6a:      	add	sp, #0x44
     c6c:      	pop.w	{r8, r9, r10, r11}
     c70:      	pop	{r4, r5, r6, r7, pc}
     c72:      	bmi	0xc1e <zs_println+0xc6> @ imm = #-0x58

00000c74 <write_c>:
     c74:      	push	{r4, r5, r6, r7, lr}
     c76:      	add	r7, sp, #0xc
     c78:      	push.w	{r8, r9, r10, r11}
     c7c:      	sub	sp, #0x44
     c7e:      	mov	r2, r0
     c80:      	mov.w	r11, #0xffffffff
     c84:      	add.w	r0, r2, r11
     c88:      	ldrb	r1, [r0, #0x1]
     c8a:      	cbz	r1, 0xca4 <write_c+0x30> @ imm = #0x16
     c8c:      	ldrb	r1, [r0, #0x2]
     c8e:      	cbz	r1, 0xcb0 <write_c+0x3c> @ imm = #0x1e
     c90:      	ldrb	r1, [r0, #0x3]
     c92:      	cmp	r1, #0x0
     c94:      	beq.w	0xda4 <write_c+0x130>   @ imm = #0x10c
     c98:      	ldrb	r0, [r0, #0x4]
     c9a:      	add.w	r11, r11, #0x4
     c9e:      	cmp	r0, #0x0
     ca0:      	bne	0xc84 <write_c+0x10>    @ imm = #-0x20
     ca2:      	b	0xcb4 <write_c+0x40>    @ imm = #0xe
     ca4:      	add.w	r11, r11, #0x1
     ca8:      	cmp.w	r11, #0x0
     cac:      	bne	0xcba <write_c+0x46>    @ imm = #0xa
     cae:      	b	0xdb0 <write_c+0x13c>   @ imm = #0xfe
     cb0:      	add.w	r11, r11, #0x2
     cb4:      	cmp.w	r11, #0x0
     cb8:      	beq	0xdb0 <write_c+0x13c>   @ imm = #0xf4
     cba:      	sub.w	r1, r7, #0x5d
     cbe:      	movs	r3, #0x0
     cc0:      	add.w	r12, r1, #0x1
     cc4:      	movs	r6, #0x40
     cc6:      	mov.w	r9, #0x0
     cca:      	b	0xce8 <write_c+0x74>    @ imm = #0x1a
     ccc:      	strb.w	r3, [r1, r8]
     cd0:      	movs	r0, #0x4
     cd2:      	subs.w	r11, r11, r8
     cd6:      	bkpt	#0xab
     cd8:      	sbc	r9, r9, #0x0
     cdc:      	rsbs.w	r0, r11, #0x0
     ce0:      	sbcs.w	r0, r3, r9
     ce4:      	add	r2, r8
     ce6:      	bge	0xdb0 <write_c+0x13c>   @ imm = #0xc6
     ce8:      	mov.w	r8, #0x40
     cec:      	cmp.w	r11, #0x40
     cf0:      	it	lo
     cf2:      	movlo	r8, r11
     cf4:      	cmp.w	r9, #0x0
     cf8:      	it	ne
     cfa:      	movne	r8, r6
     cfc:      	sub.w	r0, r8, #0x1
     d00:      	cmp	r0, #0x3
     d02:      	bhs	0xd10 <write_c+0x9c>    @ imm = #0xa
     d04:      	movs	r0, #0x0
     d06:      	ands	r4, r8, #0x3
     d0a:      	bne	0xd72 <write_c+0xfe>    @ imm = #0x64
     d0c:      	b	0xccc <write_c+0x58>    @ imm = #-0x44
     d0e:      	nop
     d10:      	bic	r0, r8, #0x3
     d14:      	rsb.w	r10, r0, #0x0
     d18:      	mov	r1, r2
     d1a:      	adds	r5, r2, #0x1
     d1c:      	mvn	r4, #0x3
     d20:      	adds	r3, r5, r4
     d22:      	ldrb	r6, [r3, #0x3]
     d24:      	ldrb	r2, [r3, #0x4]
     d26:      	ldrb	r0, [r3, #0x5]
     d28:      	cmp	r6, #0x0
     d2a:      	ldrb	r3, [r3, #0x6]
     d2c:      	it	eq
     d2e:      	moveq	r6, #0x20
     d30:      	add.w	lr, r12, r4
     d34:      	cmp	r2, #0x0
     d36:      	strb.w	r6, [lr, #0x3]
     d3a:      	it	eq
     d3c:      	moveq	r2, #0x20
     d3e:      	strb.w	r2, [lr, #0x4]
     d42:      	cmp	r0, #0x0
     d44:      	it	eq
     d46:      	moveq	r0, #0x20
     d48:      	adds	r4, #0x4
     d4a:      	strb.w	r0, [lr, #0x5]
     d4e:      	cmp	r3, #0x0
     d50:      	add.w	r0, r10, r4
     d54:      	it	eq
     d56:      	moveq	r3, #0x20
     d58:      	adds	r0, #0x4
     d5a:      	strb.w	r3, [lr, #0x6]
     d5e:      	bne	0xd20 <write_c+0xac>    @ imm = #-0x42
     d60:      	adds	r0, r4, #0x4
     d62:      	mov	r2, r1
     d64:      	movs	r3, #0x0
     d66:      	sub.w	r1, r7, #0x5d
     d6a:      	movs	r6, #0x40
     d6c:      	ands	r4, r8, #0x3
     d70:      	beq	0xccc <write_c+0x58>    @ imm = #-0xa8
     d72:      	ldrb	r5, [r2, r0]
     d74:      	cmp	r5, #0x0
     d76:      	it	eq
     d78:      	moveq	r5, #0x20
     d7a:      	cmp	r4, #0x1
     d7c:      	strb	r5, [r1, r0]
     d7e:      	beq	0xccc <write_c+0x58>    @ imm = #-0xb6
     d80:      	add.w	r10, r0, #0x1
     d84:      	ldrb.w	r5, [r2, r10]
     d88:      	cmp	r5, #0x0
     d8a:      	it	eq
     d8c:      	moveq	r5, #0x20
     d8e:      	cmp	r4, #0x2
     d90:      	strb.w	r5, [r1, r10]
     d94:      	beq	0xccc <write_c+0x58>    @ imm = #-0xcc
     d96:      	adds	r0, #0x2
     d98:      	ldrb	r4, [r2, r0]
     d9a:      	cmp	r4, #0x0
     d9c:      	it	eq
     d9e:      	moveq	r4, #0x20
     da0:      	strb	r4, [r1, r0]
     da2:      	b	0xccc <write_c+0x58>    @ imm = #-0xda
     da4:      	add.w	r11, r11, #0x3
     da8:      	cmp.w	r11, #0x0
     dac:      	bne.w	0xcba <write_c+0x46>    @ imm = #-0xf6
     db0:      	add	sp, #0x44
     db2:      	pop.w	{r8, r9, r10, r11}
     db6:      	pop	{r4, r5, r6, r7, pc}

00000db8 <stop>:
     db8:      	push	{r4, r5, r6, r7, lr}
     dba:      	add	r7, sp, #0xc
     dbc:      	str	r11, [sp, #-4]!
     dc0:      	sub	sp, #0x48
     dc2:      	movw	r6, #0x8000
     dc6:      	movw	r5, #0x0
     dca:      	movt	r6, #0x203f
     dce:      	movt	r5, #0x2040
     dd2:      	cmp	r6, r5
     dd4:      	mov	r4, r0
     dd6:      	bhs	0xe22 <stop+0x6a>       @ imm = #0x48
     dd8:      	movw	r0, #0x8000
     ddc:      	movt	r0, #0x203f
     de0:      	ldr	r1, [r0]
     de2:      	cmp.w	r1, #0xcdcdcdcd
     de6:      	bne	0xe20 <stop+0x68>       @ imm = #0x36
     de8:      	adds	r6, r0, #0x4
     dea:      	cmp	r6, r5
     dec:      	bhs	0xe22 <stop+0x6a>       @ imm = #0x32
     dee:      	ldr	r1, [r6]
     df0:      	cmp.w	r1, #0xcdcdcdcd
     df4:      	bne	0xe22 <stop+0x6a>       @ imm = #0x2a
     df6:      	add.w	r6, r0, #0x8
     dfa:      	cmp	r6, r5
     dfc:      	bhs	0xe22 <stop+0x6a>       @ imm = #0x22
     dfe:      	ldr	r1, [r6]
     e00:      	cmp.w	r1, #0xcdcdcdcd
     e04:      	bne	0xe22 <stop+0x6a>       @ imm = #0x1a
     e06:      	add.w	r6, r0, #0xc
     e0a:      	cmp	r6, r5
     e0c:      	bhs	0xe22 <stop+0x6a>       @ imm = #0x12
     e0e:      	ldr	r1, [r6]
     e10:      	cmp.w	r1, #0xcdcdcdcd
     e14:      	bne	0xe22 <stop+0x6a>       @ imm = #0xa
     e16:      	adds	r0, #0x10
     e18:      	cmp	r0, r5
     e1a:      	mov	r6, r0
     e1c:      	blo	0xde0 <stop+0x28>       @ imm = #-0x40
     e1e:      	b	0xe22 <stop+0x6a>       @ imm = #0x0
     e20:      	mov	r6, r0
     e22:      	movw	r0, #0x8c
     e26:      	movt	r0, #0x2001
     e2a:      	ldr	r2, [r0]
     e2c:      	movw	r0, #0x1adf
     e30:      	movt	r0, #0x0
     e34:      	movs	r3, #0x0
     e36:      	bl	0x1028 <text>           @ imm = #0x1ee
     e3a:      	movw	r0, #0x84
     e3e:      	movt	r0, #0x2000
     e42:      	ldr	r2, [r0]
     e44:      	movw	r0, #0x1af5
     e48:      	movt	r0, #0x0
     e4c:      	movs	r3, #0x0
     e4e:      	bl	0x1028 <text>           @ imm = #0x1d6
     e52:      	movw	r0, #0x98
     e56:      	movt	r0, #0x2001
     e5a:      	ldrd	r2, r3, [r0]
     e5e:      	movw	r0, #0x1ac9
     e62:      	movt	r0, #0x0
     e66:      	bl	0x1028 <text>           @ imm = #0x1be
     e6a:      	movw	r0, #0x90
     e6e:      	movt	r0, #0x2001
     e72:      	ldrd	r2, r3, [r0]
     e76:      	movw	r0, #0x1aee
     e7a:      	movt	r0, #0x0
     e7e:      	bl	0x1028 <text>           @ imm = #0x1a6
     e82:      	subs	r2, r5, r6
     e84:      	movw	r0, #0x1ad7
     e88:      	asrs	r3, r2, #0x1f
     e8a:      	movt	r0, #0x0
     e8e:      	bl	0x1028 <text>           @ imm = #0x196
     e92:      	movs	r0, #0xa
     e94:      	strh.w	r0, [sp, #0x4]
     e98:      	movs	r0, #0x4
     e9a:      	add	r1, sp, #0x4
     e9c:      	bkpt	#0xab
     e9e:      	movs	r0, #0x26
     ea0:      	movt	r0, #0x2
     ea4:      	strd	r0, r4, [sp, #4]
     ea8:      	movs	r0, #0x20
     eaa:      	add	r1, sp, #0x4
     eac:      	bkpt	#0xab
     eae:      	nop
     eb0:      	b	0xeb0 <stop+0xf8>       @ imm = #-0x4
     eb2:      	bmi	0xe5e <stop+0xa6>       @ imm = #-0x58

00000eb4 <zs_set_args>:
     eb4:      	push	{r7, lr}
     eb6:      	mov	r7, sp
     eb8:      	pop	{r7, pc}
     eba:      	bmi	0xe66 <stop+0xae>       @ imm = #-0x58

00000ebc <Reset_Handler>:
     ebc:      	push	{r7, lr}
     ebe:      	mov	r7, sp
     ec0:      	movw	r0, #0x0
     ec4:      	movw	r1, #0x0
     ec8:      	movt	r0, #0x2000
     ecc:      	movt	r1, #0x2000
     ed0:      	cmp	r1, r0
     ed2:      	bhs	0xf06 <Reset_Handler+0x4a> @ imm = #0x30
     ed4:      	movw	r2, #0x1c40
     ed8:      	movt	r2, #0x0
     edc:      	ldr	r3, [r2]
     ede:      	str	r3, [r1], #4
     ee2:      	cmp	r1, r0
     ee4:      	bhs	0xf06 <Reset_Handler+0x4a> @ imm = #0x1e
     ee6:      	ldr	r3, [r2, #0x4]
     ee8:      	str	r3, [r1], #4
     eec:      	cmp	r1, r0
     eee:      	bhs	0xf06 <Reset_Handler+0x4a> @ imm = #0x14
     ef0:      	ldr	r3, [r2, #0x8]
     ef2:      	str	r3, [r1], #4
     ef6:      	cmp	r1, r0
     ef8:      	bhs	0xf06 <Reset_Handler+0x4a> @ imm = #0xa
     efa:      	ldr	r3, [r2, #0xc]
     efc:      	adds	r2, #0x10
     efe:      	str	r3, [r1], #4
     f02:      	cmp	r1, r0
     f04:      	blo	0xedc <Reset_Handler+0x20> @ imm = #-0x2c
     f06:      	movw	r0, #0xa4
     f0a:      	movw	r1, #0x0
     f0e:      	movt	r0, #0x2001
     f12:      	movt	r1, #0x2000
     f16:      	cmp	r1, r0
     f18:      	bhs	0xf3c <Reset_Handler+0x80> @ imm = #0x20
     f1a:      	movs	r2, #0x0
     f1c:      	str	r2, [r1], #4
     f20:      	cmp	r1, r0
     f22:      	bhs	0xf3c <Reset_Handler+0x80> @ imm = #0x16
     f24:      	str	r2, [r1], #4
     f28:      	cmp	r1, r0
     f2a:      	bhs	0xf3c <Reset_Handler+0x80> @ imm = #0xe
     f2c:      	str	r2, [r1], #4
     f30:      	cmp	r1, r0
     f32:      	bhs	0xf3c <Reset_Handler+0x80> @ imm = #0x6
     f34:      	str	r2, [r1], #4
     f38:      	cmp	r1, r0
     f3a:      	blo	0xf1c <Reset_Handler+0x60> @ imm = #-0x22
     f3c:      	movw	r0, #0xed88
     f40:      	movt	r0, #0xe000
     f44:      	ldr	r1, [r0]
     f46:      	orr	r1, r1, #0xf00000
     f4a:      	str	r1, [r0]
     f4c:      	movw	r0, #0xe010
     f50:      	movt	r0, #0xe000
     f54:      	mvn	r1, #0xff000000
     f58:      	dsb	sy
     f5c:      	isb	sy
     f60:      	str	r1, [r0, #0x4]
     f62:      	movs	r1, #0x0
     f64:      	str	r1, [r0, #0x8]
     f66:      	movs	r1, #0x7
     f68:      	str	r1, [r0]
     f6a:      	mov	r0, sp
     f6c:      	movw	r1, #0x8000
     f70:      	subs	r0, #0x40
     f72:      	movt	r1, #0x203f
     f76:      	cmp	r0, r1
     f78:      	bls	0xfa0 <Reset_Handler+0xe4> @ imm = #0x24
     f7a:      	mov.w	r2, #0xcdcdcdcd
     f7e:      	nop
     f80:      	str	r2, [r1], #4
     f84:      	cmp	r1, r0
     f86:      	bhs	0xfa0 <Reset_Handler+0xe4> @ imm = #0x16
     f88:      	str	r2, [r1], #4
     f8c:      	cmp	r1, r0
     f8e:      	bhs	0xfa0 <Reset_Handler+0xe4> @ imm = #0xe
     f90:      	str	r2, [r1], #4
     f94:      	cmp	r1, r0
     f96:      	bhs	0xfa0 <Reset_Handler+0xe4> @ imm = #0x6
     f98:      	str	r2, [r1], #4
     f9c:      	cmp	r1, r0
     f9e:      	blo	0xf80 <Reset_Handler+0xc4> @ imm = #-0x22
     fa0:      	movs	r0, #0x0
     fa2:      	movs	r1, #0x0
     fa4:      	bl	0xdc <main>             @ imm = #-0xecc
     fa8:      	bl	0xdb8 <stop>            @ imm = #-0x1f4

00000fac <zs_ticks>:
     fac:      	push	{r7, lr}
     fae:      	mov	r7, sp
     fb0:      	movw	r12, #0xe018
     fb4:      	movw	r2, #0xa0
     fb8:      	movt	r12, #0xe000
     fbc:      	movt	r2, #0x2001
     fc0:      	ldr	r1, [r2]
     fc2:      	ldr.w	r3, [r12]
     fc6:      	ldr	r0, [r2]
     fc8:      	cmp	r1, r0
     fca:      	beq	0xff0 <zs_ticks+0x44>   @ imm = #0x22
     fcc:      	ldr	r1, [r2]
     fce:      	ldr.w	r3, [r12]
     fd2:      	ldr	r0, [r2]
     fd4:      	cmp	r1, r0
     fd6:      	beq	0xff0 <zs_ticks+0x44>   @ imm = #0x16
     fd8:      	ldr	r1, [r2]
     fda:      	ldr.w	r3, [r12]
     fde:      	ldr	r0, [r2]
     fe0:      	cmp	r1, r0
     fe2:      	beq	0xff0 <zs_ticks+0x44>   @ imm = #0xa
     fe4:      	ldr	r1, [r2]
     fe6:      	ldr.w	r3, [r12]
     fea:      	ldr	r0, [r2]
     fec:      	cmp	r1, r0
     fee:      	bne	0xfc0 <zs_ticks+0x14>   @ imm = #-0x32
     ff0:      	mvn	r0, #0xff000000
     ff4:      	subs	r0, r0, r3
     ff6:      	lsrs	r2, r1, #0x8
     ff8:      	adds.w	r0, r0, r1, lsl #24
     ffc:      	adc	r1, r2, #0x0
    1000:      	pop	{r7, pc}
    1002:      	bmi	0xfae <zs_ticks+0x2>    @ imm = #-0x58

00001004 <fault>:
    1004:      	push	{r7, lr}
    1006:      	mov	r7, sp
    1008:      	movw	r0, #0x1abe
    100c:      	movt	r0, #0x0
    1010:      	bl	0x464 <zs_panic_c>      @ imm = #-0xbb0

00001014 <SysTick_Handler>:
    1014:      	push	{r7, lr}
    1016:      	mov	r7, sp
    1018:      	movw	r0, #0xa0
    101c:      	movt	r0, #0x2001
    1020:      	ldr	r1, [r0]
    1022:      	adds	r1, #0x1
    1024:      	str	r1, [r0]
    1026:      	pop	{r7, pc}

00001028 <text>:
    1028:      	push	{r4, r5, r6, r7, lr}
    102a:      	add	r7, sp, #0xc
    102c:      	push.w	{r8, r9, r10, r11}
    1030:      	sub	sp, #0x64
    1032:      	strd	r2, r3, [sp]
    1036:      	mov	r3, r0
    1038:      	mov.w	r12, #0xffffffff
    103c:      	add.w	r0, r3, r12
    1040:      	ldrb	r1, [r0, #0x1]
    1042:      	cbz	r1, 0x105e <text+0x36>  @ imm = #0x18
    1044:      	ldrb	r1, [r0, #0x2]
    1046:      	cbz	r1, 0x106a <text+0x42>  @ imm = #0x20
    1048:      	ldrb	r1, [r0, #0x3]
    104a:      	cbz	r1, 0x1076 <text+0x4e>  @ imm = #0x28
    104c:      	ldrb	r0, [r0, #0x4]
    104e:      	add.w	r12, r12, #0x4
    1052:      	cmp	r0, #0x0
    1054:      	bne	0x103c <text+0x14>      @ imm = #-0x1c
    1056:      	cmp.w	r12, #0x0
    105a:      	bne	0x1080 <text+0x58>      @ imm = #0x22
    105c:      	b	0x116e <text+0x146>     @ imm = #0x10e
    105e:      	add.w	r12, r12, #0x1
    1062:      	cmp.w	r12, #0x0
    1066:      	bne	0x1080 <text+0x58>      @ imm = #0x16
    1068:      	b	0x116e <text+0x146>     @ imm = #0x102
    106a:      	add.w	r12, r12, #0x2
    106e:      	cmp.w	r12, #0x0
    1072:      	bne	0x1080 <text+0x58>      @ imm = #0xa
    1074:      	b	0x116e <text+0x146>     @ imm = #0xf6
    1076:      	add.w	r12, r12, #0x3
    107a:      	cmp.w	r12, #0x0
    107e:      	beq	0x116e <text+0x146>     @ imm = #0xec
    1080:      	sub.w	r1, r7, #0x5d
    1084:      	movs	r4, #0x0
    1086:      	add.w	r10, r1, #0x1
    108a:      	movs	r5, #0x40
    108c:      	mov.w	r9, #0x0
    1090:      	b	0x10b0 <text+0x88>      @ imm = #0x1c
    1092:      	nop
    1094:      	strb.w	r4, [r1, r11]
    1098:      	movs	r0, #0x4
    109a:      	subs.w	r12, r12, r11
    109e:      	bkpt	#0xab
    10a0:      	sbc	r9, r9, #0x0
    10a4:      	rsbs.w	r0, r12, #0x0
    10a8:      	sbcs.w	r0, r4, r9
    10ac:      	add	r3, r11
    10ae:      	bge	0x116e <text+0x146>     @ imm = #0xbc
    10b0:      	mov.w	r11, #0x40
    10b4:      	cmp.w	r12, #0x40
    10b8:      	it	lo
    10ba:      	movlo	r11, r12
    10bc:      	cmp.w	r9, #0x0
    10c0:      	it	ne
    10c2:      	movne	r11, r5
    10c4:      	sub.w	r0, r11, #0x1
    10c8:      	cmp	r0, #0x3
    10ca:      	bhs	0x10d8 <text+0xb0>      @ imm = #0xa
    10cc:      	movs	r0, #0x0
    10ce:      	ands	r2, r11, #0x3
    10d2:      	bne	0x113a <text+0x112>     @ imm = #0x64
    10d4:      	b	0x1094 <text+0x6c>      @ imm = #-0x44
    10d6:      	nop
    10d8:      	bic	r0, r11, #0x3
    10dc:      	rsb.w	lr, r0, #0x0
    10e0:      	mov	r1, r3
    10e2:      	adds	r6, r3, #0x1
    10e4:      	mvn	r2, #0x3
    10e8:      	adds	r3, r6, r2
    10ea:      	ldrb	r5, [r3, #0x3]
    10ec:      	ldrb	r4, [r3, #0x4]
    10ee:      	ldrb	r0, [r3, #0x5]
    10f0:      	cmp	r5, #0x0
    10f2:      	ldrb	r3, [r3, #0x6]
    10f4:      	it	eq
    10f6:      	moveq	r5, #0x20
    10f8:      	add.w	r8, r10, r2
    10fc:      	cmp	r4, #0x0
    10fe:      	strb.w	r5, [r8, #0x3]
    1102:      	it	eq
    1104:      	moveq	r4, #0x20
    1106:      	strb.w	r4, [r8, #0x4]
    110a:      	cmp	r0, #0x0
    110c:      	it	eq
    110e:      	moveq	r0, #0x20
    1110:      	adds	r2, #0x4
    1112:      	strb.w	r0, [r8, #0x5]
    1116:      	cmp	r3, #0x0
    1118:      	add.w	r0, lr, r2
    111c:      	it	eq
    111e:      	moveq	r3, #0x20
    1120:      	adds	r0, #0x4
    1122:      	strb.w	r3, [r8, #0x6]
    1126:      	bne	0x10e8 <text+0xc0>      @ imm = #-0x42
    1128:      	adds	r0, r2, #0x4
    112a:      	mov	r3, r1
    112c:      	movs	r4, #0x0
    112e:      	sub.w	r1, r7, #0x5d
    1132:      	movs	r5, #0x40
    1134:      	ands	r2, r11, #0x3
    1138:      	beq	0x1094 <text+0x6c>      @ imm = #-0xa8
    113a:      	ldrb	r6, [r3, r0]
    113c:      	cmp	r6, #0x0
    113e:      	it	eq
    1140:      	moveq	r6, #0x20
    1142:      	cmp	r2, #0x1
    1144:      	strb	r6, [r1, r0]
    1146:      	beq	0x1094 <text+0x6c>      @ imm = #-0xb6
    1148:      	adds	r6, r0, #0x1
    114a:      	ldrb.w	lr, [r3, r6]
    114e:      	cmp.w	lr, #0x0
    1152:      	it	eq
    1154:      	moveq.w	lr, #0x20
    1158:      	cmp	r2, #0x2
    115a:      	strb.w	lr, [r1, r6]
    115e:      	beq	0x1094 <text+0x6c>      @ imm = #-0xce
    1160:      	adds	r0, #0x2
    1162:      	ldrb	r2, [r3, r0]
    1164:      	cmp	r2, #0x0
    1166:      	it	eq
    1168:      	moveq	r2, #0x20
    116a:      	strb	r2, [r1, r0]
    116c:      	b	0x1094 <text+0x6c>      @ imm = #-0xdc
    116e:      	movw	r9, #0xcccd
    1172:      	ldrd	r4, r5, [sp]
    1176:      	mov.w	r11, #0x1
    117a:      	movt	r9, #0xcccc
    117e:      	sub.w	r10, r7, #0x5d
    1182:      	nop
    1184:      	lsrs	r0, r4, #0x1
    1186:      	orr.w	r0, r0, r5, lsl #31
    118a:      	adds.w	r1, r0, r5, lsr #1
    118e:      	adc	r1, r1, #0x0
    1192:      	umull	r2, r3, r1, r9
    1196:      	bic	r2, r3, #0x3
    119a:      	add.w	r2, r2, r3, lsr #2
    119e:      	subs	r1, r1, r2
    11a0:      	subs	r1, r0, r1
    11a2:      	umull	r0, lr, r1, r9
    11a6:      	lsr.w	r3, r5, #0x1
    11aa:      	add.w	r6, r0, r0, lsl #2
    11ae:      	sbc	r2, r3, #0x0
    11b2:      	sub.w	r6, r4, r6, lsl #1
    11b6:      	mov	r3, r4
    11b8:      	subs	r4, #0xa
    11ba:      	orr	r12, r6, #0x30
    11be:      	add.w	r8, r10, r11
    11c2:      	sbcs	r4, r5, #0x0
    11c6:      	strb	r12, [r8, #-1]
    11ca:      	blo	0x12c2 <text+0x29a>     @ imm = #0xf4
    11cc:      	mov.w	r4, #0xcccccccc
    11d0:      	mla	r1, r1, r4, lr
    11d4:      	mla	r1, r2, r9, r1
    11d8:      	lsrs	r2, r0, #0x1
    11da:      	orr.w	r2, r2, r1, lsl #31
    11de:      	adds.w	r1, r2, r1, lsr #1
    11e2:      	adc	r1, r1, #0x0
    11e6:      	umull	r2, r4, r1, r9
    11ea:      	bic	r2, r4, #0x3
    11ee:      	add.w	r2, r2, r4, lsr #2
    11f2:      	subs	r1, r1, r2
    11f4:      	and	r0, r0, #0x1
    11f8:      	orr.w	r0, r0, r1, lsl #1
    11fc:      	subs.w	r1, r3, #0x64
    1200:      	orr	r0, r0, #0x30
    1204:      	sbcs	r1, r5, #0x0
    1208:      	mov	r4, r10
    120a:      	strb.w	r0, [r10, r11]
    120e:      	blo	0x12cc <text+0x2a4>     @ imm = #0xba
    1210:      	mov	r6, r3
    1212:      	mov	r0, r3
    1214:      	mov	r1, r5
    1216:      	movs	r2, #0x64
    1218:      	movs	r3, #0x0
    121a:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x282
    121e:      	lsrs	r2, r0, #0x1
    1220:      	orr.w	r2, r2, r1, lsl #31
    1224:      	adds.w	r1, r2, r1, lsr #1
    1228:      	adc	r1, r1, #0x0
    122c:      	umull	r2, r3, r1, r9
    1230:      	bic	r2, r3, #0x3
    1234:      	add.w	r2, r2, r3, lsr #2
    1238:      	subs	r1, r1, r2
    123a:      	and	r0, r0, #0x1
    123e:      	orr.w	r0, r0, r1, lsl #1
    1242:      	subs.w	r1, r6, #0x3e8
    1246:      	orr	r0, r0, #0x30
    124a:      	sbcs	r1, r5, #0x0
    124e:      	strb.w	r0, [r8, #0x1]
    1252:      	blo	0x12d4 <text+0x2ac>     @ imm = #0x7e
    1254:      	mov	r0, r6
    1256:      	mov	r1, r5
    1258:      	mov.w	r2, #0x3e8
    125c:      	movs	r3, #0x0
    125e:      	mov	r10, r4
    1260:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x23c
    1264:      	lsrs	r2, r0, #0x1
    1266:      	orr.w	r2, r2, r1, lsl #31
    126a:      	adds.w	r1, r2, r1, lsr #1
    126e:      	adc	r1, r1, #0x0
    1272:      	umull	r2, r3, r1, r9
    1276:      	bic	r2, r3, #0x3
    127a:      	add.w	r2, r2, r3, lsr #2
    127e:      	subs	r1, r1, r2
    1280:      	and	r0, r0, #0x1
    1284:      	orr.w	r0, r0, r1, lsl #1
    1288:      	orr	r0, r0, #0x30
    128c:      	strb.w	r0, [r8, #0x2]
    1290:      	mov	r0, r6
    1292:      	mov	r1, r5
    1294:      	movw	r2, #0x2710
    1298:      	movs	r3, #0x0
    129a:      	bl	0x14a0 <compiler_rt.arm.__aeabi_uldivmod> @ imm = #0x202
    129e:      	movw	r2, #0x270f
    12a2:      	subs	r2, r2, r6
    12a4:      	mov.w	r2, #0x0
    12a8:      	sbcs	r2, r5
    12aa:      	add.w	r11, r11, #0x4
    12ae:      	mov	r4, r0
    12b0:      	mov	r5, r1
    12b2:      	blo.w	0x1184 <text+0x15c>     @ imm = #-0x132
    12b6:      	sub.w	r1, r11, #0x1
    12ba:      	sub.w	r12, r11, #0x2
    12be:      	mov	r11, r1
    12c0:      	b	0x12c8 <text+0x2a0>     @ imm = #0x4
    12c2:      	sub.w	r12, r11, #0x1
    12c6:      	mov	r1, r11
    12c8:      	mov	r4, r10
    12ca:      	b	0x12de <text+0x2b6>     @ imm = #0x10
    12cc:      	add.w	r1, r11, #0x1
    12d0:      	mov	r12, r11
    12d2:      	b	0x12dc <text+0x2b4>     @ imm = #0x6
    12d4:      	add.w	r1, r11, #0x2
    12d8:      	add.w	r12, r11, #0x1
    12dc:      	mov	r11, r1
    12de:      	and	lr, r1, #0x3
    12e2:      	lsrs	r3, r1, #0x2
    12e4:      	mov.w	r1, #0x0
    12e8:      	beq	0x1322 <text+0x2fa>     @ imm = #0x36
    12ea:      	sub.w	r6, r7, #0x75
    12ee:      	add.w	r5, r12, r4
    12f2:      	sub.w	r9, r1, r3, lsl #2
    12f6:      	subs	r6, #0x3
    12f8:      	subs	r5, #0x1
    12fa:      	nop
    12fc:      	adds	r4, r5, r1
    12fe:      	ldrb	r3, [r5, r1]
    1300:      	ldrb	r0, [r4, #-2]
    1304:      	ldrb	r2, [r4, #-1]
    1308:      	ldrb	r4, [r4, #0x1]
    130a:      	subs	r1, #0x4
    130c:      	strb	r3, [r6, #4]!
    1310:      	cmp	r9, r1
    1312:      	strb	r4, [r6, #-1]
    1316:      	strb	r2, [r6, #0x1]
    1318:      	strb	r0, [r6, #0x2]
    131a:      	bne	0x12fc <text+0x2d4>     @ imm = #-0x22
    131c:      	rsbs	r1, r1, #0
    131e:      	sub.w	r4, r7, #0x5d
    1322:      	cmp.w	lr, #0x0
    1326:      	beq	0x1354 <text+0x32c>     @ imm = #0x2a
    1328:      	sub.w	r0, r12, r1
    132c:      	ldrb	r0, [r4, r0]
    132e:      	sub.w	r3, r7, #0x75
    1332:      	cmp.w	lr, #0x1
    1336:      	strb	r0, [r3, r1]
    1338:      	beq	0x1354 <text+0x32c>     @ imm = #0x18
    133a:      	adds	r0, r1, #0x1
    133c:      	sub.w	r2, r12, r0
    1340:      	ldrb	r2, [r4, r2]
    1342:      	cmp.w	lr, #0x2
    1346:      	strb	r2, [r3, r0]
    1348:      	beq	0x1354 <text+0x32c>     @ imm = #0x8
    134a:      	adds	r0, r1, #0x2
    134c:      	sub.w	r1, r12, r0
    1350:      	ldrb	r1, [r4, r1]
    1352:      	strb	r1, [r3, r0]
    1354:      	sub.w	r0, r7, #0x75
    1358:      	movs	r1, #0x0
    135a:      	mov.w	r12, #0xffffffff
    135e:      	strb.w	r1, [r0, r11]
    1362:      	nop
    1364:      	add.w	r1, r0, r12
    1368:      	ldrb	r3, [r1, #0x1]
    136a:      	cbz	r3, 0x1386 <text+0x35e> @ imm = #0x18
    136c:      	ldrb	r3, [r1, #0x2]
    136e:      	cbz	r3, 0x1392 <text+0x36a> @ imm = #0x20
    1370:      	ldrb	r3, [r1, #0x3]
    1372:      	cbz	r3, 0x139e <text+0x376> @ imm = #0x28
    1374:      	ldrb	r1, [r1, #0x4]
    1376:      	add.w	r12, r12, #0x4
    137a:      	cmp	r1, #0x0
    137c:      	bne	0x1364 <text+0x33c>     @ imm = #-0x1c
    137e:      	cmp.w	r12, #0x0
    1382:      	bne	0x13a8 <text+0x380>     @ imm = #0x22
    1384:      	b	0x1490 <text+0x468>     @ imm = #0x108
    1386:      	add.w	r12, r12, #0x1
    138a:      	cmp.w	r12, #0x0
    138e:      	bne	0x13a8 <text+0x380>     @ imm = #0x16
    1390:      	b	0x1490 <text+0x468>     @ imm = #0xfc
    1392:      	add.w	r12, r12, #0x2
    1396:      	cmp.w	r12, #0x0
    139a:      	bne	0x13a8 <text+0x380>     @ imm = #0xa
    139c:      	b	0x1490 <text+0x468>     @ imm = #0xf0
    139e:      	add.w	r12, r12, #0x3
    13a2:      	cmp.w	r12, #0x0
    13a6:      	beq	0x1490 <text+0x468>     @ imm = #0xe6
    13a8:      	movs	r2, #0x0
    13aa:      	add.w	lr, r4, #0x1
    13ae:      	sub.w	r9, r7, #0x75
    13b2:      	movs	r3, #0x40
    13b4:      	mov.w	r11, #0x0
    13b8:      	b	0x13da <text+0x3b2>     @ imm = #0x1e
    13ba:      	nop
    13bc:      	strb.w	r2, [r4, r8]
    13c0:      	movs	r0, #0x4
    13c2:      	subs.w	r12, r12, r8
    13c6:      	mov	r1, r4
    13c8:      	bkpt	#0xab
    13ca:      	sbc	r11, r11, #0x0
    13ce:      	rsbs.w	r0, r12, #0x0
    13d2:      	sbcs.w	r0, r2, r11
    13d6:      	add	r9, r8
    13d8:      	bge	0x1490 <text+0x468>     @ imm = #0xb4
    13da:      	mov.w	r8, #0x40
    13de:      	cmp.w	r12, #0x40
    13e2:      	it	lo
    13e4:      	movlo	r8, r12
    13e6:      	cmp.w	r11, #0x0
    13ea:      	it	ne
    13ec:      	movne	r8, r3
    13ee:      	sub.w	r0, r8, #0x1
    13f2:      	cmp	r0, #0x3
    13f4:      	bhs	0x1400 <text+0x3d8>     @ imm = #0x8
    13f6:      	movs	r0, #0x0
    13f8:      	ands	r1, r8, #0x3
    13fc:      	bne	0x145a <text+0x432>     @ imm = #0x5a
    13fe:      	b	0x13bc <text+0x394>     @ imm = #-0x46
    1400:      	bic	r0, r8, #0x3
    1404:      	rsb.w	r10, r0, #0x0
    1408:      	add.w	r5, r9, #0x1
    140c:      	mvn	r1, #0x3
    1410:      	adds	r4, r5, r1
    1412:      	ldrb	r2, [r4, #0x3]
    1414:      	ldrb	r3, [r4, #0x4]
    1416:      	ldrb	r6, [r4, #0x5]
    1418:      	cmp	r2, #0x0
    141a:      	ldrb	r4, [r4, #0x6]
    141c:      	it	eq
    141e:      	moveq	r2, #0x20
    1420:      	add.w	r0, lr, r1
    1424:      	cmp	r3, #0x0
    1426:      	strb	r2, [r0, #0x3]
    1428:      	it	eq
    142a:      	moveq	r3, #0x20
    142c:      	cmp	r6, #0x0
    142e:      	add.w	r1, r1, #0x4
    1432:      	strb	r3, [r0, #0x4]
    1434:      	it	eq
    1436:      	moveq	r6, #0x20
    1438:      	cmp	r4, #0x0
    143a:      	add.w	r2, r10, r1
    143e:      	strb	r6, [r0, #0x5]
    1440:      	it	eq
    1442:      	moveq	r4, #0x20
    1444:      	adds	r2, #0x4
    1446:      	strb	r4, [r0, #0x6]
    1448:      	bne	0x1410 <text+0x3e8>     @ imm = #-0x3c
    144a:      	adds	r0, r1, #0x4
    144c:      	sub.w	r4, r7, #0x5d
    1450:      	movs	r2, #0x0
    1452:      	movs	r3, #0x40
    1454:      	ands	r1, r8, #0x3
    1458:      	beq	0x13bc <text+0x394>     @ imm = #-0xa0
    145a:      	ldrb.w	r5, [r9, r0]
    145e:      	cmp	r5, #0x0
    1460:      	it	eq
    1462:      	moveq	r5, #0x20
    1464:      	cmp	r1, #0x1
    1466:      	strb	r5, [r4, r0]
    1468:      	beq	0x13bc <text+0x394>     @ imm = #-0xb0
    146a:      	add.w	r10, r0, #0x1
    146e:      	ldrb.w	r5, [r9, r10]
    1472:      	cmp	r5, #0x0
    1474:      	it	eq
    1476:      	moveq	r5, #0x20
    1478:      	cmp	r1, #0x2
    147a:      	strb.w	r5, [r4, r10]
    147e:      	beq	0x13bc <text+0x394>     @ imm = #-0xc6
    1480:      	adds	r0, #0x2
    1482:      	ldrb.w	r1, [r9, r0]
    1486:      	cmp	r1, #0x0
    1488:      	it	eq
    148a:      	moveq	r1, #0x20
    148c:      	strb	r1, [r4, r0]
    148e:      	b	0x13bc <text+0x394>     @ imm = #-0xd6
    1490:      	add	sp, #0x64
    1492:      	pop.w	{r8, r9, r10, r11}
    1496:      	pop	{r4, r5, r6, r7, pc}

00001498 <compiler_rt.arm.__aeabi_unwind_cpp_pr0>:
    1498:      	push	{r7, lr}
    149a:      	mov	r7, sp
    149c:      	pop	{r7, pc}
    149e:      	bmi	0x144a <text+0x422>     @ imm = #-0x58

000014a0 <compiler_rt.arm.__aeabi_uldivmod>:
    14a0:      	push	{r4, lr}
    14a2:      	sub	sp, #0x10
    14a4:      	add	r4, sp, #0x8
    14a6:      	str	r4, [sp]
    14a8:      	bl	0x14b4 <compiler_rt.int.__udivmoddi4> @ imm = #0x8
    14ac:      	ldr	r2, [sp, #0x8]
    14ae:      	ldr	r3, [sp, #0xc]
    14b0:      	add	sp, #0x10
    14b2:      	pop	{r4, pc}

000014b4 <compiler_rt.int.__udivmoddi4>:
    14b4:      	push	{r4, r5, r6, r7, lr}
    14b6:      	add	r7, sp, #0xc
    14b8:      	push.w	{r8, r9, r10, r11}
    14bc:      	sub	sp, #0x20
    14be:      	mov	r5, r2
    14c0:      	ldr	r6, [r7, #0x8]
    14c2:      	subs	r2, r0, r2
    14c4:      	sbcs.w	r2, r1, r3
    14c8:      	bhs	0x14e0 <compiler_rt.int.__udivmoddi4+0x2c> @ imm = #0x14
    14ca:      	cmp	r6, #0x0
    14cc:      	it	ne
    14ce:      	strdne	r0, r1, [r6]
    14d2:      	movs	r0, #0x0
    14d4:      	movs	r1, #0x0
    14d6:      	add	sp, #0x20
    14d8:      	pop.w	{r8, r9, r10, r11}
    14dc:      	pop	{r4, r5, r6, r7, pc}
    14de:      	nop
    14e0:      	cmp	r3, #0x0
    14e2:      	beq.w	0x15ec <compiler_rt.int.__udivmoddi4+0x138> @ imm = #0x106
    14e6:      	clz	r2, r3
    14ea:      	cmp	r2, #0x0
    14ec:      	beq.w	0x1618 <compiler_rt.int.__udivmoddi4+0x164> @ imm = #0x128
    14f0:      	rsbs	r6, r2, #0
    14f2:      	and	r4, r6, #0x1f
    14f6:      	lsl.w	r12, r3, r2
    14fa:      	lsr.w	r6, r5, r4
    14fe:      	orr.w	r8, r6, r12
    1502:      	lsl.w	r2, r1, r2
    1506:      	lsr.w	r6, r0, r4
    150a:      	clz	lr, r8
    150e:      	orrs	r2, r6
    1510:      	ands	r12, lr, #0x1f
    1514:      	lsr.w	r6, r1, r4
    1518:      	str	r5, [sp, #0x10]
    151a:      	str	r0, [sp, #0x4]
    151c:      	beq	0x1538 <compiler_rt.int.__udivmoddi4+0x84> @ imm = #0x18
    151e:      	lsl.w	r4, r6, r12
    1522:      	rsb.w	r6, lr, #0x0
    1526:      	and	r6, r6, #0x1f
    152a:      	lsr.w	r6, r2, r6
    152e:      	lsl.w	r8, r8, r12
    1532:      	orrs	r6, r4
    1534:      	lsl.w	r2, r2, r12
    1538:      	lsr.w	lr, r8, #0x10
    153c:      	udiv	r4, r6, lr
    1540:      	strd	r3, r1, [sp, #8]
    1544:      	mls	r9, r4, lr, r6
    1548:      	uxth.w	r12, r8
    154c:      	lsr.w	r11, r2, #0x10
    1550:      	uxth	r3, r2
    1552:      	mov	r0, r6
    1554:      	mov.w	r10, #0x0
    1558:      	str.w	r8, [sp]
    155c:      	b	0x1570 <compiler_rt.int.__udivmoddi4+0xbc> @ imm = #0x10
    155e:      	nop
    1560:      	subs	r6, r4, #0x4
    1562:      	add.w	r9, r2, lr
    1566:      	cmp.w	r10, r9, lsr #16
    156a:      	mov	r4, r6
    156c:      	bne.w	0x17aa <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x23a
    1570:      	cmp.w	r10, r4, lsr #16
    1574:      	bne	0x1584 <compiler_rt.int.__udivmoddi4+0xd0> @ imm = #0xc
    1576:      	mul	r2, r4, r12
    157a:      	orr.w	r6, r11, r9, lsl #16
    157e:      	cmp	r2, r6
    1580:      	bls.w	0x17a8 <compiler_rt.int.__udivmoddi4+0x2f4> @ imm = #0x224
    1584:      	add.w	r2, r9, lr
    1588:      	cmp.w	r10, r2, lsr #16
    158c:      	sub.w	r6, r4, #0x1
    1590:      	bne.w	0x17aa <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x216
    1594:      	cmp.w	r10, r6, lsr #16
    1598:      	bne	0x15a8 <compiler_rt.int.__udivmoddi4+0xf4> @ imm = #0xc
    159a:      	mul	r9, r6, r12
    159e:      	orr.w	r8, r11, r2, lsl #16
    15a2:      	cmp	r9, r8
    15a4:      	bls.w	0x17aa <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x202
    15a8:      	add	r2, lr
    15aa:      	cmp.w	r10, r2, lsr #16
    15ae:      	sub.w	r6, r4, #0x2
    15b2:      	bne.w	0x17aa <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1f4
    15b6:      	cmp.w	r10, r6, lsr #16
    15ba:      	bne	0x15ca <compiler_rt.int.__udivmoddi4+0x116> @ imm = #0xc
    15bc:      	mul	r8, r6, r12
    15c0:      	orr.w	r5, r11, r2, lsl #16
    15c4:      	cmp	r8, r5
    15c6:      	bls.w	0x17aa <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1e0
    15ca:      	add	r2, lr
    15cc:      	cmp.w	r10, r2, lsr #16
    15d0:      	sub.w	r6, r4, #0x3
    15d4:      	bne.w	0x17aa <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1d2
    15d8:      	cmp.w	r10, r6, lsr #16
    15dc:      	bne	0x1560 <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x80
    15de:      	mul	r5, r6, r12
    15e2:      	orr.w	r1, r11, r2, lsl #16
    15e6:      	cmp	r5, r1
    15e8:      	bhi	0x1560 <compiler_rt.int.__udivmoddi4+0xac> @ imm = #-0x8c
    15ea:      	b	0x17aa <compiler_rt.int.__udivmoddi4+0x2f6> @ imm = #0x1bc
    15ec:      	cmp	r1, r5
    15ee:      	clz	lr, r5
    15f2:      	bhs	0x1630 <compiler_rt.int.__udivmoddi4+0x17c> @ imm = #0x3a
    15f4:      	cmp.w	lr, #0x0
    15f8:      	beq.w	0x1700 <compiler_rt.int.__udivmoddi4+0x24c> @ imm = #0x104
    15fc:      	rsb.w	r2, lr, #0x0
    1600:      	and	r2, r2, #0x1f
    1604:      	lsl.w	r1, r1, lr
    1608:      	lsr.w	r2, r0, r2
    160c:      	lsl.w	r5, r5, lr
    1610:      	orrs	r2, r1
    1612:      	lsl.w	r0, r0, lr
    1616:      	b	0x1702 <compiler_rt.int.__udivmoddi4+0x24e> @ imm = #0xe8
    1618:      	cbz	r6, 0x1622 <compiler_rt.int.__udivmoddi4+0x16e> @ imm = #0x6
    161a:      	subs	r0, r0, r5
    161c:      	sbcs	r1, r3
    161e:      	strd	r0, r1, [r6]
    1622:      	movs	r1, #0x0
    1624:      	movs	r0, #0x1
    1626:      	add	sp, #0x20
    1628:      	pop.w	{r8, r9, r10, r11}
    162c:      	pop	{r4, r5, r6, r7, pc}
    162e:      	nop
    1630:      	udiv	r2, r1, r5
    1634:      	cmp.w	lr, #0x0
    1638:      	mls	r8, r2, r5, r1
    163c:      	mov	r1, r2
    163e:      	beq	0x165c <compiler_rt.int.__udivmoddi4+0x1a8> @ imm = #0x1a
    1640:      	rsb.w	r3, lr, #0x0
    1644:      	and	r3, r3, #0x1f
    1648:      	lsl.w	r2, r8, lr
    164c:      	lsr.w	r3, r0, r3
    1650:      	lsl.w	r5, r5, lr
    1654:      	orr.w	r8, r2, r3
    1658:      	lsl.w	r0, r0, lr
    165c:      	lsrs	r4, r5, #0x10
    165e:      	str	r5, [sp, #0x10]
    1660:      	uxth.w	r12, r5
    1664:      	udiv	r5, r8, r4
    1668:      	lsr.w	r10, r0, #0x10
    166c:      	mls	r6, r5, r4, r8
    1670:      	uxth.w	r9, r0
    1674:      	movs	r3, #0x0
    1676:      	b	0x1686 <compiler_rt.int.__udivmoddi4+0x1d2> @ imm = #0xc
    1678:      	subs	r0, r5, #0x4
    167a:      	adds	r6, r2, r4
    167c:      	cmp.w	r3, r6, lsr #16
    1680:      	mov	r5, r0
    1682:      	bne.w	0x18c2 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x23c
    1686:      	cmp.w	r3, r5, lsr #16
    168a:      	bne	0x169a <compiler_rt.int.__udivmoddi4+0x1e6> @ imm = #0xc
    168c:      	mul	r0, r5, r12
    1690:      	orr.w	r2, r10, r6, lsl #16
    1694:      	cmp	r0, r2
    1696:      	bls.w	0x18c0 <compiler_rt.int.__udivmoddi4+0x40c> @ imm = #0x226
    169a:      	adds	r2, r6, r4
    169c:      	cmp.w	r3, r2, lsr #16
    16a0:      	sub.w	r0, r5, #0x1
    16a4:      	bne.w	0x18c2 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x21a
    16a8:      	cmp.w	r3, r0, lsr #16
    16ac:      	bne	0x16bc <compiler_rt.int.__udivmoddi4+0x208> @ imm = #0xc
    16ae:      	mul	r11, r0, r12
    16b2:      	orr.w	r6, r10, r2, lsl #16
    16b6:      	cmp	r11, r6
    16b8:      	bls.w	0x18c2 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x206
    16bc:      	add	r2, r4
    16be:      	cmp.w	r3, r2, lsr #16
    16c2:      	sub.w	r0, r5, #0x2
    16c6:      	bne.w	0x18c2 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1f8
    16ca:      	cmp.w	r3, r0, lsr #16
    16ce:      	bne	0x16de <compiler_rt.int.__udivmoddi4+0x22a> @ imm = #0xc
    16d0:      	mul	r11, r0, r12
    16d4:      	orr.w	r6, r10, r2, lsl #16
    16d8:      	cmp	r11, r6
    16da:      	bls.w	0x18c2 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1e4
    16de:      	add	r2, r4
    16e0:      	cmp.w	r3, r2, lsr #16
    16e4:      	sub.w	r0, r5, #0x3
    16e8:      	bne.w	0x18c2 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1d6
    16ec:      	cmp.w	r3, r0, lsr #16
    16f0:      	bne	0x1678 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x7c
    16f2:      	mul	r11, r0, r12
    16f6:      	orr.w	r6, r10, r2, lsl #16
    16fa:      	cmp	r11, r6
    16fc:      	bhi	0x1678 <compiler_rt.int.__udivmoddi4+0x1c4> @ imm = #-0x88
    16fe:      	b	0x18c2 <compiler_rt.int.__udivmoddi4+0x40e> @ imm = #0x1c0
    1700:      	mov	r2, r1
    1702:      	lsrs	r4, r5, #0x10
    1704:      	udiv	r6, r2, r4
    1708:      	mov	r11, r5
    170a:      	uxth.w	r9, r5
    170e:      	mls	r5, r6, r4, r2
    1712:      	lsr.w	r8, r0, #0x10
    1716:      	uxth.w	r12, r0
    171a:      	mov	r1, r2
    171c:      	movs	r3, #0x0
    171e:      	b	0x172e <compiler_rt.int.__udivmoddi4+0x27a> @ imm = #0xc
    1720:      	subs	r0, r6, #0x4
    1722:      	adds	r5, r2, r4
    1724:      	cmp.w	r3, r5, lsr #16
    1728:      	mov	r6, r0
    172a:      	bne.w	0x195a <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x22c
    172e:      	cmp.w	r3, r6, lsr #16
    1732:      	bne	0x1742 <compiler_rt.int.__udivmoddi4+0x28e> @ imm = #0xc
    1734:      	mul	r0, r6, r9
    1738:      	orr.w	r2, r8, r5, lsl #16
    173c:      	cmp	r0, r2
    173e:      	bls.w	0x1958 <compiler_rt.int.__udivmoddi4+0x4a4> @ imm = #0x216
    1742:      	adds	r2, r5, r4
    1744:      	cmp.w	r3, r2, lsr #16
    1748:      	sub.w	r0, r6, #0x1
    174c:      	bne.w	0x195a <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x20a
    1750:      	cmp.w	r3, r0, lsr #16
    1754:      	bne	0x1764 <compiler_rt.int.__udivmoddi4+0x2b0> @ imm = #0xc
    1756:      	mul	r10, r0, r9
    175a:      	orr.w	r5, r8, r2, lsl #16
    175e:      	cmp	r10, r5
    1760:      	bls.w	0x195a <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1f6
    1764:      	add	r2, r4
    1766:      	cmp.w	r3, r2, lsr #16
    176a:      	sub.w	r0, r6, #0x2
    176e:      	bne.w	0x195a <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1e8
    1772:      	cmp.w	r3, r0, lsr #16
    1776:      	bne	0x1786 <compiler_rt.int.__udivmoddi4+0x2d2> @ imm = #0xc
    1778:      	mul	r10, r0, r9
    177c:      	orr.w	r5, r8, r2, lsl #16
    1780:      	cmp	r10, r5
    1782:      	bls.w	0x195a <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1d4
    1786:      	add	r2, r4
    1788:      	cmp.w	r3, r2, lsr #16
    178c:      	sub.w	r0, r6, #0x3
    1790:      	bne.w	0x195a <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1c6
    1794:      	cmp.w	r3, r0, lsr #16
    1798:      	bne	0x1720 <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x7c
    179a:      	mul	r10, r0, r9
    179e:      	orr.w	r5, r8, r2, lsl #16
    17a2:      	cmp	r10, r5
    17a4:      	bhi	0x1720 <compiler_rt.int.__udivmoddi4+0x26c> @ imm = #-0x88
    17a6:      	b	0x195a <compiler_rt.int.__udivmoddi4+0x4a6> @ imm = #0x1b0
    17a8:      	mov	r6, r4
    17aa:      	orr.w	r2, r11, r0, lsl #16
    17ae:      	ldr	r0, [sp]
    17b0:      	ldr.w	r9, [sp, #0x4]
    17b4:      	mls	r2, r6, r0, r2
    17b8:      	mov.w	r8, #0x0
    17bc:      	udiv	r4, r2, lr
    17c0:      	mls	r2, r4, lr, r2
    17c4:      	b	0x17d4 <compiler_rt.int.__udivmoddi4+0x320> @ imm = #0xc
    17c6:      	nop
    17c8:      	subs	r4, #0x4
    17ca:      	add	r2, lr
    17cc:      	cmp.w	r2, #0x10000
    17d0:      	mov	r5, r4
    17d2:      	bhs	0x1846 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x70
    17d4:      	cmp.w	r8, r4, lsr #16
    17d8:      	bne	0x17e6 <compiler_rt.int.__udivmoddi4+0x332> @ imm = #0xa
    17da:      	mul	r1, r4, r12
    17de:      	orr.w	r5, r3, r2, lsl #16
    17e2:      	cmp	r1, r5
    17e4:      	bls	0x1844 <compiler_rt.int.__udivmoddi4+0x390> @ imm = #0x5c
    17e6:      	add	r2, lr
    17e8:      	cmp.w	r8, r2, lsr #16
    17ec:      	sub.w	r5, r4, #0x1
    17f0:      	bne	0x1846 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x52
    17f2:      	cmp.w	r8, r5, lsr #16
    17f6:      	bne	0x1804 <compiler_rt.int.__udivmoddi4+0x350> @ imm = #0xa
    17f8:      	mul	r1, r5, r12
    17fc:      	orr.w	r0, r3, r2, lsl #16
    1800:      	cmp	r1, r0
    1802:      	bls	0x1846 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x40
    1804:      	add	r2, lr
    1806:      	cmp.w	r8, r2, lsr #16
    180a:      	sub.w	r5, r4, #0x2
    180e:      	bne	0x1846 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x34
    1810:      	cmp.w	r8, r5, lsr #16
    1814:      	bne	0x1822 <compiler_rt.int.__udivmoddi4+0x36e> @ imm = #0xa
    1816:      	mul	r0, r5, r12
    181a:      	orr.w	r1, r3, r2, lsl #16
    181e:      	cmp	r0, r1
    1820:      	bls	0x1846 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x22
    1822:      	add	r2, lr
    1824:      	cmp.w	r8, r2, lsr #16
    1828:      	sub.w	r5, r4, #0x3
    182c:      	bne	0x1846 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x16
    182e:      	cmp.w	r8, r5, lsr #16
    1832:      	bne	0x17c8 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x6e
    1834:      	mul	r0, r5, r12
    1838:      	orr.w	r1, r3, r2, lsl #16
    183c:      	cmp	r0, r1
    183e:      	bhi	0x17c8 <compiler_rt.int.__udivmoddi4+0x314> @ imm = #-0x7a
    1840:      	b	0x1846 <compiler_rt.int.__udivmoddi4+0x392> @ imm = #0x2
    1842:      	nop
    1844:      	mov	r5, r4
    1846:      	add.w	r0, r5, r6, lsl #16
    184a:      	ldr	r2, [sp, #0x10]
    184c:      	ldr	r6, [sp, #0x8]
    184e:      	umull	r4, r1, r2, r0
    1852:      	mov	r8, r0
    1854:      	umull	r0, r3, r6, r0
    1858:      	adds	r5, r0, r1
    185a:      	mov.w	r12, #0x0
    185e:      	adc	r0, r12, #0x0
    1862:      	orrs.w	r1, r3, r0
    1866:      	ldr	r3, [r7, #0x8]
    1868:      	ldr.w	lr, [sp, #0xc]
    186c:      	strb.w	r0, [sp, #0x14]
    1870:      	bne	0x187c <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x8
    1872:      	cmp	r5, lr
    1874:      	bhi	0x187c <compiler_rt.int.__udivmoddi4+0x3c8> @ imm = #0x4
    1876:      	bne	0x1892 <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x18
    1878:      	cmp	r4, r9
    187a:      	bls	0x1892 <compiler_rt.int.__udivmoddi4+0x3de> @ imm = #0x14
    187c:      	subs	r4, r4, r2
    187e:      	adc	r0, r12, #0x0
    1882:      	eor	r0, r0, #0x1
    1886:      	strb.w	r0, [sp, #0x18]
    188a:      	add	r0, r6
    188c:      	sub.w	r8, r8, #0x1
    1890:      	subs	r5, r5, r0
    1892:      	cbz	r3, 0x18b2 <compiler_rt.int.__udivmoddi4+0x3fe> @ imm = #0x1c
    1894:      	subs.w	r0, r9, r4
    1898:      	mov.w	r1, #0x0
    189c:      	adc	r1, r1, #0x0
    18a0:      	eor	r1, r1, #0x1
    18a4:      	strb.w	r1, [sp, #0x1c]
    18a8:      	add	r1, r5
    18aa:      	sub.w	r1, lr, r1
    18ae:      	strd	r0, r1, [r3]
    18b2:      	movs	r1, #0x0
    18b4:      	mov	r0, r8
    18b6:      	add	sp, #0x20
    18b8:      	pop.w	{r8, r9, r10, r11}
    18bc:      	pop	{r4, r5, r6, r7, pc}
    18be:      	nop
    18c0:      	mov	r0, r5
    18c2:      	ldr	r3, [sp, #0x10]
    18c4:      	orr.w	r2, r10, r8, lsl #16
    18c8:      	mls	r8, r0, r3, r2
    18cc:      	mov.w	r10, #0x0
    18d0:      	udiv	r3, r8, r4
    18d4:      	mls	r5, r3, r4, r8
    18d8:      	b	0x18ea <compiler_rt.int.__udivmoddi4+0x436> @ imm = #0xe
    18da:      	nop
    18dc:      	subs	r3, #0x4
    18de:      	adds	r5, r2, r4
    18e0:      	cmp.w	r5, #0x10000
    18e4:      	mov	r6, r3
    18e6:      	bhs.w	0x19ee <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x104
    18ea:      	cmp.w	r10, r3, lsr #16
    18ee:      	bne	0x18fc <compiler_rt.int.__udivmoddi4+0x448> @ imm = #0xa
    18f0:      	mul	r2, r3, r12
    18f4:      	orr.w	r6, r9, r5, lsl #16
    18f8:      	cmp	r2, r6
    18fa:      	bls	0x19ec <compiler_rt.int.__udivmoddi4+0x538> @ imm = #0xee
    18fc:      	adds	r2, r5, r4
    18fe:      	cmp.w	r10, r2, lsr #16
    1902:      	sub.w	r6, r3, #0x1
    1906:      	bne	0x19ee <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xe4
    1908:      	cmp.w	r10, r6, lsr #16
    190c:      	bne	0x191a <compiler_rt.int.__udivmoddi4+0x466> @ imm = #0xa
    190e:      	mul	r11, r6, r12
    1912:      	orr.w	r5, r9, r2, lsl #16
    1916:      	cmp	r11, r5
    1918:      	bls	0x19ee <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xd2
    191a:      	add	r2, r4
    191c:      	cmp.w	r10, r2, lsr #16
    1920:      	sub.w	r6, r3, #0x2
    1924:      	bne	0x19ee <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xc6
    1926:      	cmp.w	r10, r6, lsr #16
    192a:      	bne	0x1938 <compiler_rt.int.__udivmoddi4+0x484> @ imm = #0xa
    192c:      	mul	r11, r6, r12
    1930:      	orr.w	r5, r9, r2, lsl #16
    1934:      	cmp	r11, r5
    1936:      	bls	0x19ee <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xb4
    1938:      	add	r2, r4
    193a:      	cmp.w	r10, r2, lsr #16
    193e:      	sub.w	r6, r3, #0x3
    1942:      	bne	0x19ee <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0xa8
    1944:      	cmp.w	r10, r6, lsr #16
    1948:      	bne	0x18dc <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x70
    194a:      	mul	r11, r6, r12
    194e:      	orr.w	r5, r9, r2, lsl #16
    1952:      	cmp	r11, r5
    1954:      	bhi	0x18dc <compiler_rt.int.__udivmoddi4+0x428> @ imm = #-0x7c
    1956:      	b	0x19ee <compiler_rt.int.__udivmoddi4+0x53a> @ imm = #0x94
    1958:      	mov	r0, r6
    195a:      	orr.w	r1, r8, r1, lsl #16
    195e:      	mls	r8, r0, r11, r1
    1962:      	mov.w	r10, #0x0
    1966:      	udiv	r1, r8, r4
    196a:      	mls	r5, r1, r4, r8
    196e:      	b	0x197c <compiler_rt.int.__udivmoddi4+0x4c8> @ imm = #0xa
    1970:      	subs	r1, #0x4
    1972:      	adds	r5, r2, r4
    1974:      	cmp.w	r5, #0x10000
    1978:      	mov	r6, r1
    197a:      	bhs	0x1a02 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x84
    197c:      	cmp.w	r10, r1, lsr #16
    1980:      	bne	0x198e <compiler_rt.int.__udivmoddi4+0x4da> @ imm = #0xa
    1982:      	mul	r2, r1, r9
    1986:      	orr.w	r6, r12, r5, lsl #16
    198a:      	cmp	r2, r6
    198c:      	bls	0x1a00 <compiler_rt.int.__udivmoddi4+0x54c> @ imm = #0x70
    198e:      	adds	r2, r5, r4
    1990:      	cmp.w	r10, r2, lsr #16
    1994:      	sub.w	r6, r1, #0x1
    1998:      	bne	0x1a02 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x66
    199a:      	cmp.w	r10, r6, lsr #16
    199e:      	bne	0x19ac <compiler_rt.int.__udivmoddi4+0x4f8> @ imm = #0xa
    19a0:      	mul	r5, r6, r9
    19a4:      	orr.w	r3, r12, r2, lsl #16
    19a8:      	cmp	r5, r3
    19aa:      	bls	0x1a02 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x54
    19ac:      	add	r2, r4
    19ae:      	cmp.w	r10, r2, lsr #16
    19b2:      	sub.w	r6, r1, #0x2
    19b6:      	bne	0x1a02 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x48
    19b8:      	cmp.w	r10, r6, lsr #16
    19bc:      	bne	0x19ca <compiler_rt.int.__udivmoddi4+0x516> @ imm = #0xa
    19be:      	mul	r3, r6, r9
    19c2:      	orr.w	r5, r12, r2, lsl #16
    19c6:      	cmp	r3, r5
    19c8:      	bls	0x1a02 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x36
    19ca:      	add	r2, r4
    19cc:      	cmp.w	r10, r2, lsr #16
    19d0:      	sub.w	r6, r1, #0x3
    19d4:      	bne	0x1a02 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x2a
    19d6:      	cmp.w	r10, r6, lsr #16
    19da:      	bne	0x1970 <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x6e
    19dc:      	mul	r3, r6, r9
    19e0:      	orr.w	r5, r12, r2, lsl #16
    19e4:      	cmp	r3, r5
    19e6:      	bhi	0x1970 <compiler_rt.int.__udivmoddi4+0x4bc> @ imm = #-0x7a
    19e8:      	b	0x1a02 <compiler_rt.int.__udivmoddi4+0x54e> @ imm = #0x16
    19ea:      	nop
    19ec:      	mov	r6, r3
    19ee:      	ldr	r3, [sp, #0x10]
    19f0:      	orr.w	r2, r9, r8, lsl #16
    19f4:      	mls	r2, r6, r3, r2
    19f8:      	lsr.w	r2, r2, lr
    19fc:      	b	0x1a10 <compiler_rt.int.__udivmoddi4+0x55c> @ imm = #0x10
    19fe:      	nop
    1a00:      	mov	r6, r1
    1a02:      	orr.w	r1, r12, r8, lsl #16
    1a06:      	mls	r1, r6, r11, r1
    1a0a:      	lsr.w	r2, r1, lr
    1a0e:      	movs	r1, #0x0
    1a10:      	ldr	r5, [r7, #0x8]
    1a12:      	add.w	r0, r6, r0, lsl #16
    1a16:      	cmp	r5, #0x0
    1a18:      	itt	ne
    1a1a:      	movne	r3, #0x0
    1a1c:      	strdne	r2, r3, [r5]
    1a20:      	add	sp, #0x20
    1a22:      	pop.w	{r8, r9, r10, r11}
    1a26:      	pop	{r4, r5, r6, r7, pc}
    1a28:      	bmi	0x19d4 <compiler_rt.int.__udivmoddi4+0x520> @ imm = #-0x58
    1a2a:      	bmi	0x19d6 <compiler_rt.int.__udivmoddi4+0x522> @ imm = #-0x58
    1a2c:      	bmi	0x19d8 <compiler_rt.int.__udivmoddi4+0x524> @ imm = #-0x58
    1a2e:      	bmi	0x19da <compiler_rt.int.__udivmoddi4+0x526> @ imm = #-0x58

00001a30 <.L.str.1>:
    1a30: 00 00 00 00 10 00 00 00         ........
    1a38: 69 6e 74 65 67 65 72 20         integer 
    1a40: 6f 76 65 72 66 6c 6f 77         overflow
    1a48: 00 00 00 00                     ....

00001a4c <.L.str.2>:
    1a4c: 00 00 00 00 00 00 00 00         ........
    1a54: 00 00 00 00 d4 d4 d4 d4         ........
    1a5c: d4 d4 d4 d4                     ....

00001a60 <.L.str.3>:
    1a60: 00 00 00 00 10 00 00 00         ........
    1a68: 70 69 70 65 6c 69 6e 65         pipeline
    1a70: 20 72 65 73 75 6c 74 3d          result=
    1a78: 00 00 00 00 00 00 00 00         ........
    1a80: 07 00 00 00 20 74 69 63         .... tic
    1a88: 6b 73 3d 00 d4 d4 d4 d4         ks=.....

00001a90 <.L.str.5>:
    1a90: 00 00 00 00 0d 00 00 00         ........
    1a98: 6d 61 74 63 68 20 66 61         match fa
    1aa0: 69 6c 75 72 65 00 00 00         ilure...
    1aa8: 00 00 00 00 00 00 00 00         ........
    1ab0: 6f 75 74 20 6f 66 20 6d         out of m
    1ab8: 65 6d 6f 72 79 00 68 61         emory.ha
    1ac0: 72 64 20 66 61 75 6c 74         rd fault
    1ac8: 00 20 61 6c 6c 6f 63 61         . alloca
    1ad0: 74 69 6f 6e 73 3d 00 20         tions=. 
    1ad8: 73 74 61 63 6b 3d 00 23         stack=.#
    1ae0: 7a 73 20 68 65 61 70 5f         zs heap_
    1ae8: 70 65 61 6b 3d 00 20 6c         peak=. l
    1af0: 69 76 65 3d 00 20 68 65         ive=. he
    1af8: 61 70 5f 72 65 73 65 72         ap_reser
    1b00: 76 65 64 3d 00 70 61 6e         ved=.pan
    1b08: 69 63 3a 20 00 0a 00 d4         ic: ....
