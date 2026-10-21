
bench/mcu/out/isort-os.o:	file format elf32-littlearm

Disassembly of section .text.unlikely..Lcopy.array<i32>:

00000000 <.Lcopy.array<i32>>:
       0:      	push	{r4, r5, r6, lr}
       2:      	mov	r5, r0
       4:      	ldr	r0, [r0, #0x4]
       6:      	movs	r1, #0x8
       8:      	add.w	r6, r1, r0, lsl #2
       c:      	mov	r0, r6
       e:      	bl	0xe <.Lcopy.array<i32>+0xe> @ imm = #-0x4
      12:      	mov	r1, r5
      14:      	mov	r2, r6
      16:      	mov	r4, r0
      18:      	bl	0x18 <.Lcopy.array<i32>+0x18> @ imm = #-0x4
      1c:      	movs	r1, #0x1
      1e:      	str	r1, [r4]
      20:      	ldr	r1, [r5]
      22:      	cbz	r1, 0x2e <.Lcopy.array<i32>+0x2e> @ imm = #0x8
      24:      	cmp	r1, #0x1
      26:      	bne	0x32 <.Lcopy.array<i32>+0x32> @ imm = #0x8
      28:      	mov	r0, r5
      2a:      	bl	0x2a <.Lcopy.array<i32>+0x2a> @ imm = #-0x4
      2e:      	mov	r0, r4
      30:      	pop	{r4, r5, r6, pc}
      32:      	subs	r1, #0x1
      34:      	mov	r0, r4
      36:      	str	r1, [r5]
      38:      	pop	{r4, r5, r6, pc}

Disassembly of section .text.main:

00000000 <main>:
       0:      	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
       4:      	sub	sp, #0xec
       6:      	movw	r8, #0xbef1
       a:      	movw	r10, #0x4335
       e:      	movw	r7, #0x2446
      12:      	movw	r11, #0x5445
      16:      	movw	r6, #0x3556
      1a:      	movw	r4, #0x1667
      1e:      	movt	r8, #0x3
      22:      	movt	r10, #0x3
      26:      	movt	r7, #0x3
      2a:      	movt	r11, #0x1
      2e:      	movt	r6, #0x1
      32:      	movt	r4, #0x1
      36:      	bl	0x36 <main+0x36>        @ imm = #-0x4
      3a:      	movw	r0, #0x808
      3e:      	bl	0x3e <main+0x3e>        @ imm = #-0x4
      42:      	movs	r2, #0x1
      44:      	mov.w	r1, #0x200
      48:      	strd	r2, r1, [r0]
      4c:      	str	r0, [sp]
      4e:      	adds	r0, #0x8
      50:      	mov.w	r1, #0x800
      54:      	bl	0x54 <main+0x54>        @ imm = #-0x4
      58:      	movw	r1, #0xf800
      5c:      	movt	r1, #0xffff
      60:      	str	r1, [sp, #0x6c]
      62:      	movw	r1, #0x1eef
      66:      	str	r1, [sp, #0xe8]
      68:      	movw	r1, #0x3dde
      6c:      	str	r1, [sp, #0xe4]
      6e:      	movw	r1, #0x7bbc
      72:      	str	r1, [sp, #0xa4]
      74:      	movw	r1, #0x9aab
      78:      	str	r1, [sp, #0xa0]
      7a:      	movw	r1, #0x7334
      7e:      	movt	r1, #0x1
      82:      	str	r1, [sp, #0xdc]
      84:      	movw	r1, #0x9223
      88:      	movt	r1, #0x1
      8c:      	str	r1, [sp, #0xd8]
      8e:      	movw	r1, #0xb112
      92:      	movt	r1, #0x1
      96:      	str	r1, [sp, #0xd4]
      98:      	movw	r1, #0xd001
      9c:      	movt	r1, #0x1
      a0:      	str	r1, [sp, #0xd0]
      a2:      	movw	r1, #0xeef0
      a6:      	movt	r1, #0x1
      aa:      	str	r1, [sp, #0xcc]
      ac:      	movw	r1, #0xddf
      b0:      	movt	r1, #0x2
      b4:      	str	r1, [sp, #0xc8]
      b6:      	movw	r1, #0x2cce
      ba:      	movt	r1, #0x2
      be:      	str	r1, [sp, #0xc4]
      c0:      	movw	r1, #0x4bbd
      c4:      	movt	r1, #0x2
      c8:      	str	r1, [sp, #0xc0]
      ca:      	movw	r1, #0x6aac
      ce:      	movt	r1, #0x2
      d2:      	str	r1, [sp, #0xbc]
      d4:      	movw	r1, #0x899b
      d8:      	movt	r1, #0x2
      dc:      	str	r1, [sp, #0xb8]
      de:      	movw	r1, #0xa88a
      e2:      	movt	r1, #0x2
      e6:      	str	r1, [sp, #0xb4]
      e8:      	movw	r1, #0xc779
      ec:      	movt	r1, #0x2
      f0:      	str	r1, [sp, #0xb0]
      f2:      	movw	r1, #0xe668
      f6:      	movt	r1, #0x2
      fa:      	str	r1, [sp, #0xac]
      fc:      	movw	r1, #0x557
     100:      	str	r7, [sp, #0x9c]
     102:      	movw	r7, #0x6224
     106:      	movw	r12, #0x8113
     10a:      	movw	lr, #0xa002
     10e:      	mov.w	r9, #0x0
     112:      	movw	r3, #0x5ccd
     116:      	movw	r0, #0xb99a
     11a:      	movw	r2, #0xd889
     11e:      	movw	r5, #0xf778
     122:      	movt	r1, #0x3
     126:      	movt	r7, #0x3
     12a:      	movt	r12, #0x3
     12e:      	movt	lr, #0x3
     132:      	str	r6, [sp, #0xe0]
     134:      	str	r1, [sp, #0xa8]
     136:      	nop
     138:      	movw	r6, #0x4585
     13c:      	movt	r6, #0x3ce
     140:      	strd	r2, r3, [sp, #148]
     144:      	umull	r1, r2, r8, r6
     148:      	str	r2, [sp, #0x68]
     14a:      	umull	r1, r2, lr, r6
     14e:      	str	r2, [sp, #0x64]
     150:      	umull	r1, r2, r12, r6
     154:      	str	r2, [sp, #0x60]
     156:      	umull	r1, r2, r7, r6
     15a:      	str	r2, [sp, #0x5c]
     15c:      	umull	r1, r2, r10, r6
     160:      	ldr	r1, [sp, #0x9c]
     162:      	str	r2, [sp, #0x58]
     164:      	umull	r1, r2, r1, r6
     168:      	ldr	r1, [sp, #0xa8]
     16a:      	str	r2, [sp, #0x54]
     16c:      	umull	r1, r2, r1, r6
     170:      	ldr	r1, [sp, #0xac]
     172:      	str	r2, [sp, #0x50]
     174:      	umull	r1, r2, r1, r6
     178:      	ldr	r1, [sp, #0xb0]
     17a:      	str	r2, [sp, #0x4c]
     17c:      	umull	r1, r2, r1, r6
     180:      	ldr	r1, [sp, #0xb4]
     182:      	str	r2, [sp, #0x48]
     184:      	umull	r1, r2, r1, r6
     188:      	ldr	r1, [sp, #0xb8]
     18a:      	str	r2, [sp, #0x44]
     18c:      	umull	r1, r2, r1, r6
     190:      	ldr	r1, [sp, #0xbc]
     192:      	str	r2, [sp, #0x40]
     194:      	umull	r1, r2, r1, r6
     198:      	ldr	r1, [sp, #0xc0]
     19a:      	str	r2, [sp, #0x3c]
     19c:      	umull	r1, r2, r1, r6
     1a0:      	ldr	r1, [sp, #0xc4]
     1a2:      	str	r2, [sp, #0x38]
     1a4:      	umull	r1, r2, r1, r6
     1a8:      	ldr	r1, [sp, #0xc8]
     1aa:      	str	r2, [sp, #0x34]
     1ac:      	umull	r1, r2, r1, r6
     1b0:      	ldr	r1, [sp, #0xcc]
     1b2:      	str	r2, [sp, #0x30]
     1b4:      	umull	r1, r2, r1, r6
     1b8:      	ldr	r1, [sp, #0xd0]
     1ba:      	str	r2, [sp, #0x2c]
     1bc:      	umull	r1, r2, r1, r6
     1c0:      	ldr	r1, [sp, #0xd4]
     1c2:      	str	r2, [sp, #0x28]
     1c4:      	umull	r1, r2, r1, r6
     1c8:      	ldr	r1, [sp, #0xd8]
     1ca:      	str	r2, [sp, #0x24]
     1cc:      	umull	r1, r2, r1, r6
     1d0:      	ldr	r1, [sp, #0xdc]
     1d2:      	str	r2, [sp, #0x20]
     1d4:      	umull	r1, r2, r1, r6
     1d8:      	str	r2, [sp, #0x1c]
     1da:      	umull	r1, r2, r11, r6
     1de:      	ldr	r1, [sp, #0xe0]
     1e0:      	str	r2, [sp, #0x18]
     1e2:      	umull	r1, r2, r1, r6
     1e6:      	strd	r0, r5, [sp, #140]
     1ea:      	str	r2, [sp, #0x14]
     1ec:      	umull	r1, r2, r4, r6
     1f0:      	ldr	r1, [sp, #0x90]
     1f2:      	str	r2, [sp, #0x10]
     1f4:      	umull	r1, r2, r1, r6
     1f8:      	ldr	r1, [sp, #0x94]
     1fa:      	strd	r11, r4, [sp, #132]
     1fe:      	str.w	r12, [sp, #0x78]
     202:      	str	r2, [sp, #0xc]
     204:      	umull	r2, r4, r1, r6
     208:      	ldr	r1, [sp, #0xa0]
     20a:      	ldr.w	r12, [sp, #0xa4]
     20e:      	str.w	lr, [sp, #0x80]
     212:      	umull	r2, r0, r0, r6
     216:      	umull	r2, lr, r1, r6
     21a:      	umull	r2, r11, r12, r6
     21e:      	ldr	r2, [sp, #0x98]
     220:      	ldr	r1, [sp, #0xe8]
     222:      	umull	r2, r3, r2, r6
     226:      	ldr	r2, [sp, #0xe4]
     228:      	str.w	r8, [sp, #0x7c]
     22c:      	umull	r5, r8, r2, r6
     230:      	str	r7, [sp, #0x74]
     232:      	str.w	r10, [sp, #0x70]
     236:      	str	r0, [sp, #0x8]
     238:      	umull	r7, r5, r1, r6
     23c:      	umull	r7, r10, r9, r6
     240:      	ldr	r6, [sp, #0x7c]
     242:      	mov	r0, r9
     244:      	ldr.w	r9, [sp, #0x68]
     248:      	str	r2, [sp, #0xe4]
     24a:      	sub.w	r7, r6, r9
     24e:      	add.w	r6, r9, r7, lsr #1
     252:      	mov	r9, r0
     254:      	str	r6, [sp, #0x68]
     256:      	ldr	r6, [sp, #0x80]
     258:      	ldr	r0, [sp, #0x64]
     25a:      	str	r1, [sp, #0xe8]
     25c:      	subs	r7, r6, r0
     25e:      	add.w	r6, r0, r7, lsr #1
     262:      	str	r6, [sp, #0x64]
     264:      	ldr	r6, [sp, #0x78]
     266:      	ldr	r0, [sp, #0x60]
     268:      	subs	r7, r6, r0
     26a:      	add.w	r6, r0, r7, lsr #1
     26e:      	str	r6, [sp, #0x60]
     270:      	ldr	r6, [sp, #0x74]
     272:      	ldr	r0, [sp, #0x5c]
     274:      	subs	r7, r6, r0
     276:      	add.w	r6, r0, r7, lsr #1
     27a:      	str	r6, [sp, #0x5c]
     27c:      	ldr	r6, [sp, #0x70]
     27e:      	ldr	r0, [sp, #0x58]
     280:      	subs	r7, r6, r0
     282:      	add.w	r6, r0, r7, lsr #1
     286:      	str	r6, [sp, #0x58]
     288:      	ldr	r6, [sp, #0x9c]
     28a:      	ldr	r0, [sp, #0x54]
     28c:      	subs	r7, r6, r0
     28e:      	add.w	r6, r0, r7, lsr #1
     292:      	str	r6, [sp, #0x54]
     294:      	ldr	r6, [sp, #0xa8]
     296:      	ldr	r0, [sp, #0x50]
     298:      	subs	r7, r6, r0
     29a:      	add.w	r6, r0, r7, lsr #1
     29e:      	str	r6, [sp, #0x50]
     2a0:      	ldr	r6, [sp, #0xac]
     2a2:      	ldr	r0, [sp, #0x4c]
     2a4:      	subs	r7, r6, r0
     2a6:      	add.w	r6, r0, r7, lsr #1
     2aa:      	str	r6, [sp, #0x4c]
     2ac:      	ldr	r6, [sp, #0xb0]
     2ae:      	ldr	r0, [sp, #0x48]
     2b0:      	subs	r7, r6, r0
     2b2:      	add.w	r6, r0, r7, lsr #1
     2b6:      	str	r6, [sp, #0x48]
     2b8:      	ldr	r6, [sp, #0xb4]
     2ba:      	ldr	r0, [sp, #0x44]
     2bc:      	subs	r7, r6, r0
     2be:      	add.w	r6, r0, r7, lsr #1
     2c2:      	str	r6, [sp, #0x44]
     2c4:      	ldr	r6, [sp, #0xb8]
     2c6:      	ldr	r0, [sp, #0x40]
     2c8:      	subs	r7, r6, r0
     2ca:      	add.w	r0, r0, r7, lsr #1
     2ce:      	str	r0, [sp, #0x40]
     2d0:      	ldr	r6, [sp, #0xbc]
     2d2:      	ldr	r0, [sp, #0x3c]
     2d4:      	subs	r7, r6, r0
     2d6:      	add.w	r0, r0, r7, lsr #1
     2da:      	str	r0, [sp, #0x3c]
     2dc:      	ldr	r6, [sp, #0xc0]
     2de:      	ldr	r0, [sp, #0x38]
     2e0:      	subs	r7, r6, r0
     2e2:      	add.w	r0, r0, r7, lsr #1
     2e6:      	str	r0, [sp, #0x38]
     2e8:      	ldr	r6, [sp, #0xc4]
     2ea:      	ldr	r0, [sp, #0x34]
     2ec:      	subs	r7, r6, r0
     2ee:      	add.w	r0, r0, r7, lsr #1
     2f2:      	str	r0, [sp, #0x34]
     2f4:      	ldr	r6, [sp, #0xc8]
     2f6:      	ldr	r0, [sp, #0x30]
     2f8:      	subs	r7, r6, r0
     2fa:      	add.w	r0, r0, r7, lsr #1
     2fe:      	str	r0, [sp, #0x30]
     300:      	ldr	r6, [sp, #0xcc]
     302:      	ldr	r0, [sp, #0x2c]
     304:      	subs	r7, r6, r0
     306:      	add.w	r0, r0, r7, lsr #1
     30a:      	str	r0, [sp, #0x2c]
     30c:      	ldr	r6, [sp, #0xd0]
     30e:      	ldr	r0, [sp, #0x28]
     310:      	subs	r7, r6, r0
     312:      	add.w	r0, r0, r7, lsr #1
     316:      	str	r0, [sp, #0x28]
     318:      	ldr	r6, [sp, #0xd4]
     31a:      	ldr	r0, [sp, #0x24]
     31c:      	subs	r7, r6, r0
     31e:      	add.w	r0, r0, r7, lsr #1
     322:      	str	r0, [sp, #0x24]
     324:      	ldr	r6, [sp, #0xd8]
     326:      	ldr	r0, [sp, #0x20]
     328:      	subs	r7, r6, r0
     32a:      	add.w	r0, r0, r7, lsr #1
     32e:      	str	r0, [sp, #0x20]
     330:      	ldr	r6, [sp, #0xdc]
     332:      	ldr	r0, [sp, #0x1c]
     334:      	subs	r7, r6, r0
     336:      	add.w	r0, r0, r7, lsr #1
     33a:      	str	r0, [sp, #0x1c]
     33c:      	ldr	r6, [sp, #0x84]
     33e:      	ldr	r0, [sp, #0x18]
     340:      	subs	r7, r6, r0
     342:      	add.w	r0, r0, r7, lsr #1
     346:      	str	r0, [sp, #0x18]
     348:      	ldr	r6, [sp, #0xe0]
     34a:      	ldr	r0, [sp, #0x14]
     34c:      	subs	r7, r6, r0
     34e:      	add.w	r0, r0, r7, lsr #1
     352:      	str	r0, [sp, #0x14]
     354:      	ldr	r6, [sp, #0x88]
     356:      	ldr	r0, [sp, #0x10]
     358:      	subs	r7, r6, r0
     35a:      	add.w	r0, r0, r7, lsr #1
     35e:      	str	r0, [sp, #0x10]
     360:      	ldr	r6, [sp, #0x90]
     362:      	ldr	r0, [sp, #0xc]
     364:      	subs	r7, r6, r0
     366:      	ldr	r6, [sp, #0x94]
     368:      	add.w	r0, r0, r7, lsr #1
     36c:      	subs	r7, r6, r4
     36e:      	str	r0, [sp, #0xc]
     370:      	add.w	r0, r4, r7, lsr #1
     374:      	str	r0, [sp, #0x4]
     376:      	ldr	r4, [sp, #0x8c]
     378:      	ldr	r0, [sp, #0x8]
     37a:      	movw	r6, #0x1eef
     37e:      	subs	r7, r4, r0
     380:      	ldr	r4, [sp, #0xa0]
     382:      	add.w	r0, r0, r7, lsr #1
     386:      	sub.w	r7, r4, lr
     38a:      	ldr	r4, [sp, #0x98]
     38c:      	add.w	lr, lr, r7, lsr #1
     390:      	sub.w	r7, r12, r11
     394:      	add.w	r12, r11, r7, lsr #1
     398:      	subs	r7, r4, r3
     39a:      	add.w	r3, r3, r7, lsr #1
     39e:      	sub.w	r7, r2, r8
     3a2:      	add.w	r2, r8, r7, lsr #1
     3a6:      	subs	r7, r1, r5
     3a8:      	add.w	r5, r5, r7, lsr #1
     3ac:      	sub.w	r7, r9, r10
     3b0:      	add.w	r7, r10, r7, lsr #1
     3b4:      	lsrs	r5, r5, #0x9
     3b6:      	lsrs	r7, r7, #0x9
     3b8:      	mvn	r4, #0x3f0
     3bc:      	movw	r11, #0x3f1
     3c0:      	mla	r10, r7, r4, r9
     3c4:      	mls	r5, r5, r11, r9
     3c8:      	ldr	r7, [sp]
     3ca:      	ldr	r4, [sp, #0x6c]
     3cc:      	lsrs	r2, r2, #0x9
     3ce:      	add	r7, r4
     3d0:      	add	r5, r6
     3d2:      	mls	r2, r2, r11, r9
     3d6:      	str.w	r5, [r7, #0x80c]
     3da:      	lsrs	r3, r3, #0x9
     3dc:      	movw	r5, #0x3dde
     3e0:      	add	r2, r5
     3e2:      	mls	r3, r3, r11, r9
     3e6:      	str.w	r2, [r7, #0x810]
     3ea:      	movw	r2, #0x5ccd
     3ee:      	add	r2, r3
     3f0:      	str.w	r2, [r7, #0x814]
     3f4:      	lsr.w	r2, r12, #0x9
     3f8:      	mls	r2, r2, r11, r9
     3fc:      	lsr.w	r3, lr, #0x9
     400:      	movw	r5, #0x7bbc
     404:      	str	r0, [sp, #0x8]
     406:      	add	r2, r5
     408:      	mls	r3, r3, r11, r9
     40c:      	str.w	r2, [r7, #0x818]
     410:      	movw	r2, #0x9aab
     414:      	ldr	r1, [sp, #0x8]
     416:      	add	r2, r3
     418:      	str.w	r2, [r7, #0x81c]
     41c:      	lsrs	r2, r1, #0x9
     41e:      	ldr	r1, [sp, #0x4]
     420:      	mls	r2, r2, r11, r9
     424:      	lsrs	r1, r1, #0x9
     426:      	movw	r3, #0xb99a
     42a:      	add	r2, r3
     42c:      	mls	r1, r1, r11, r9
     430:      	str.w	r2, [r7, #0x820]
     434:      	movw	r2, #0xd889
     438:      	add	r1, r2
     43a:      	ldr	r2, [sp, #0xc]
     43c:      	str.w	r1, [r7, #0x824]
     440:      	ldr	r1, [sp, #0x10]
     442:      	lsrs	r2, r2, #0x9
     444:      	movw	r3, #0x1667
     448:      	lsrs	r1, r1, #0x9
     44a:      	mls	r2, r2, r11, r9
     44e:      	movt	r3, #0x1
     452:      	mls	r1, r1, r11, r3
     456:      	movw	r3, #0xf778
     45a:      	add	r2, r3
     45c:      	str.w	r2, [r7, #0x828]
     460:      	ldr	r2, [sp, #0x14]
     462:      	add	r1, r9
     464:      	movw	r3, #0x3556
     468:      	str.w	r1, [r7, #0x82c]
     46c:      	ldr	r1, [sp, #0x18]
     46e:      	lsrs	r2, r2, #0x9
     470:      	movt	r3, #0x1
     474:      	mls	r2, r2, r11, r3
     478:      	movw	r3, #0x5445
     47c:      	lsrs	r1, r1, #0x9
     47e:      	movt	r3, #0x1
     482:      	mls	r1, r1, r11, r3
     486:      	add	r2, r9
     488:      	str.w	r2, [r7, #0x830]
     48c:      	ldr	r2, [sp, #0x1c]
     48e:      	add	r1, r9
     490:      	movw	r3, #0x7334
     494:      	str.w	r1, [r7, #0x834]
     498:      	ldr	r1, [sp, #0x20]
     49a:      	lsrs	r2, r2, #0x9
     49c:      	movt	r3, #0x1
     4a0:      	mls	r2, r2, r11, r3
     4a4:      	movw	r3, #0x9223
     4a8:      	lsrs	r1, r1, #0x9
     4aa:      	movt	r3, #0x1
     4ae:      	mls	r1, r1, r11, r3
     4b2:      	add	r2, r9
     4b4:      	str.w	r2, [r7, #0x838]
     4b8:      	ldr	r2, [sp, #0x24]
     4ba:      	add	r1, r9
     4bc:      	movw	r3, #0xb112
     4c0:      	str.w	r1, [r7, #0x83c]
     4c4:      	ldr	r1, [sp, #0x28]
     4c6:      	lsrs	r2, r2, #0x9
     4c8:      	movt	r3, #0x1
     4cc:      	mls	r2, r2, r11, r3
     4d0:      	movw	r3, #0xd001
     4d4:      	lsrs	r1, r1, #0x9
     4d6:      	movt	r3, #0x1
     4da:      	mls	r1, r1, r11, r3
     4de:      	add	r2, r9
     4e0:      	str.w	r2, [r7, #0x840]
     4e4:      	ldr	r2, [sp, #0x2c]
     4e6:      	add	r1, r9
     4e8:      	movw	r3, #0xeef0
     4ec:      	str.w	r1, [r7, #0x844]
     4f0:      	ldr	r1, [sp, #0x30]
     4f2:      	lsrs	r2, r2, #0x9
     4f4:      	movt	r3, #0x1
     4f8:      	mls	r2, r2, r11, r3
     4fc:      	movw	r3, #0xddf
     500:      	lsrs	r1, r1, #0x9
     502:      	movt	r3, #0x2
     506:      	mls	r1, r1, r11, r3
     50a:      	add	r2, r9
     50c:      	str.w	r2, [r7, #0x848]
     510:      	ldr	r2, [sp, #0x34]
     512:      	add	r1, r9
     514:      	movw	r3, #0x2cce
     518:      	str.w	r1, [r7, #0x84c]
     51c:      	ldr	r1, [sp, #0x38]
     51e:      	lsrs	r2, r2, #0x9
     520:      	movt	r3, #0x2
     524:      	mls	r2, r2, r11, r3
     528:      	movw	r3, #0x4bbd
     52c:      	lsrs	r1, r1, #0x9
     52e:      	movt	r3, #0x2
     532:      	mls	r1, r1, r11, r3
     536:      	add	r2, r9
     538:      	str.w	r2, [r7, #0x850]
     53c:      	ldr	r2, [sp, #0x3c]
     53e:      	add	r1, r9
     540:      	movw	r3, #0x6aac
     544:      	str.w	r1, [r7, #0x854]
     548:      	ldr	r1, [sp, #0x40]
     54a:      	lsrs	r2, r2, #0x9
     54c:      	movt	r3, #0x2
     550:      	mls	r2, r2, r11, r3
     554:      	movw	r3, #0x899b
     558:      	lsrs	r1, r1, #0x9
     55a:      	movt	r3, #0x2
     55e:      	mls	r1, r1, r11, r3
     562:      	add	r2, r9
     564:      	str.w	r2, [r7, #0x858]
     568:      	ldr	r2, [sp, #0x44]
     56a:      	add	r1, r9
     56c:      	movw	r3, #0xa88a
     570:      	str.w	r1, [r7, #0x85c]
     574:      	ldr	r1, [sp, #0x48]
     576:      	lsrs	r2, r2, #0x9
     578:      	movt	r3, #0x2
     57c:      	mls	r2, r2, r11, r3
     580:      	movw	r3, #0xc779
     584:      	lsrs	r1, r1, #0x9
     586:      	movt	r3, #0x2
     58a:      	mls	r1, r1, r11, r3
     58e:      	add	r2, r9
     590:      	str.w	r2, [r7, #0x860]
     594:      	ldr	r2, [sp, #0x4c]
     596:      	add	r1, r9
     598:      	movw	r3, #0xe668
     59c:      	str.w	r1, [r7, #0x864]
     5a0:      	ldr	r1, [sp, #0x50]
     5a2:      	lsrs	r2, r2, #0x9
     5a4:      	movt	r3, #0x2
     5a8:      	mls	r2, r2, r11, r3
     5ac:      	movw	r3, #0x557
     5b0:      	lsrs	r1, r1, #0x9
     5b2:      	movt	r3, #0x3
     5b6:      	mls	r1, r1, r11, r3
     5ba:      	add	r2, r9
     5bc:      	str.w	r2, [r7, #0x868]
     5c0:      	ldr	r2, [sp, #0x54]
     5c2:      	add	r1, r9
     5c4:      	movw	r3, #0x2446
     5c8:      	str.w	r1, [r7, #0x86c]
     5cc:      	ldr	r1, [sp, #0x58]
     5ce:      	lsrs	r2, r2, #0x9
     5d0:      	movt	r3, #0x3
     5d4:      	mls	r2, r2, r11, r3
     5d8:      	movw	r3, #0x4335
     5dc:      	lsrs	r1, r1, #0x9
     5de:      	movt	r3, #0x3
     5e2:      	mls	r1, r1, r11, r3
     5e6:      	add	r2, r9
     5e8:      	str.w	r2, [r7, #0x870]
     5ec:      	ldr	r2, [sp, #0x5c]
     5ee:      	add	r1, r9
     5f0:      	movw	r3, #0x6224
     5f4:      	str.w	r1, [r7, #0x874]
     5f8:      	ldr	r1, [sp, #0x60]
     5fa:      	lsrs	r2, r2, #0x9
     5fc:      	movt	r3, #0x3
     600:      	mls	r2, r2, r11, r3
     604:      	movw	r3, #0x8113
     608:      	lsrs	r1, r1, #0x9
     60a:      	movt	r3, #0x3
     60e:      	mls	r1, r1, r11, r3
     612:      	add	r2, r9
     614:      	str.w	r2, [r7, #0x878]
     618:      	ldr	r2, [sp, #0x64]
     61a:      	add	r1, r9
     61c:      	movw	r3, #0xa002
     620:      	str.w	r1, [r7, #0x87c]
     624:      	ldr	r1, [sp, #0x68]
     626:      	lsrs	r2, r2, #0x9
     628:      	movt	r3, #0x3
     62c:      	mls	r2, r2, r11, r3
     630:      	movw	r3, #0xbef1
     634:      	lsrs	r1, r1, #0x9
     636:      	movt	r3, #0x3
     63a:      	mls	r1, r1, r11, r3
     63e:      	ldr	r6, [sp, #0x9c]
     640:      	add	r1, r9
     642:      	str.w	r1, [r7, #0x884]
     646:      	movw	r1, #0xdde0
     64a:      	movt	r1, #0x3
     64e:      	add	r6, r1
     650:      	str	r6, [sp, #0x9c]
     652:      	ldr	r6, [sp, #0xa8]
     654:      	add	r2, r9
     656:      	add	r6, r1
     658:      	str	r6, [sp, #0xa8]
     65a:      	ldr	r6, [sp, #0xac]
     65c:      	adds	r4, #0x80
     65e:      	add	r6, r1
     660:      	str	r6, [sp, #0xac]
     662:      	ldr	r6, [sp, #0xb0]
     664:      	str.w	r10, [r7, #0x808]
     668:      	add	r6, r1
     66a:      	str	r6, [sp, #0xb0]
     66c:      	ldr	r6, [sp, #0xb4]
     66e:      	ldr	r0, [sp, #0x8c]
     670:      	add	r6, r1
     672:      	str	r6, [sp, #0xb4]
     674:      	ldr	r6, [sp, #0xb8]
     676:      	ldr.w	r11, [sp, #0x84]
     67a:      	add	r6, r1
     67c:      	str	r6, [sp, #0xb8]
     67e:      	ldr	r6, [sp, #0xbc]
     680:      	ldr	r5, [sp, #0x90]
     682:      	add	r6, r1
     684:      	str	r6, [sp, #0xbc]
     686:      	ldr	r6, [sp, #0xc0]
     688:      	ldr	r3, [sp, #0x98]
     68a:      	add	r6, r1
     68c:      	str	r6, [sp, #0xc0]
     68e:      	ldr	r6, [sp, #0xc4]
     690:      	str.w	r2, [r7, #0x880]
     694:      	add	r6, r1
     696:      	str	r6, [sp, #0xc4]
     698:      	ldr	r6, [sp, #0xc8]
     69a:      	ldr	r2, [sp, #0x94]
     69c:      	add	r6, r1
     69e:      	str	r6, [sp, #0xc8]
     6a0:      	ldr	r6, [sp, #0xcc]
     6a2:      	ldr.w	r8, [sp, #0x7c]
     6a6:      	add	r6, r1
     6a8:      	str	r6, [sp, #0xcc]
     6aa:      	ldr	r6, [sp, #0xd0]
     6ac:      	str	r4, [sp, #0x6c]
     6ae:      	add	r6, r1
     6b0:      	str	r6, [sp, #0xd0]
     6b2:      	ldr	r6, [sp, #0xd4]
     6b4:      	ldr	r4, [sp, #0x88]
     6b6:      	add	r6, r1
     6b8:      	str	r6, [sp, #0xd4]
     6ba:      	ldr	r6, [sp, #0xd8]
     6bc:      	ldr.w	lr, [sp, #0x80]
     6c0:      	add	r6, r1
     6c2:      	str	r6, [sp, #0xd8]
     6c4:      	ldr	r6, [sp, #0xdc]
     6c6:      	ldr.w	r12, [sp, #0x78]
     6ca:      	add	r6, r1
     6cc:      	str	r6, [sp, #0xdc]
     6ce:      	ldr	r6, [sp, #0xe0]
     6d0:      	ldr	r7, [sp, #0x74]
     6d2:      	add	r6, r1
     6d4:      	str	r6, [sp, #0xe0]
     6d6:      	ldr	r6, [sp, #0xa0]
     6d8:      	ldr.w	r10, [sp, #0x70]
     6dc:      	add	r6, r1
     6de:      	str	r6, [sp, #0xa0]
     6e0:      	ldr	r6, [sp, #0xa4]
     6e2:      	add	r8, r1
     6e4:      	add	r6, r1
     6e6:      	str	r6, [sp, #0xa4]
     6e8:      	ldr	r6, [sp, #0xe4]
     6ea:      	add	r9, r1
     6ec:      	add	r6, r1
     6ee:      	str	r6, [sp, #0xe4]
     6f0:      	ldr	r6, [sp, #0xe8]
     6f2:      	add	lr, r1
     6f4:      	add	r12, r1
     6f6:      	add	r7, r1
     6f8:      	add	r10, r1
     6fa:      	add	r11, r1
     6fc:      	add	r4, r1
     6fe:      	add	r5, r1
     700:      	add	r2, r1
     702:      	add	r0, r1
     704:      	add	r3, r1
     706:      	add	r6, r1
     708:      	str	r6, [sp, #0xe8]
     70a:      	bne.w	0x138 <main+0x138>      @ imm = #-0x5d6
     70e:      	bl	0x70e <main+0x70e>      @ imm = #-0x4
     712:      	ldr	r3, [sp]
     714:      	str	r0, [sp, #0xe8]
     716:      	ldr	r2, [r3]
     718:      	mov	r9, r1
     71a:      	cmp	r2, #0x1
     71c:      	mov	r0, r3
     71e:      	bne.w	0x90c <main+0x90c>      @ imm = #0x1ea
     722:      	mov	r10, r0
     724:      	ldr	lr, [r10, #4]!
     728:      	mov	r8, r0
     72a:      	cmp.w	lr, #0x2
     72e:      	blo	0x7c2 <main+0x7c2>      @ imm = #0x90
     730:      	add.w	r12, r8, #0x8
     734:      	movs	r2, #0x1
     736:      	mov.w	r11, #0x0
     73a:      	mov	r5, r10
     73c:      	ldr.w	r7, [r12, r2, lsl #2]
     740:      	mov	r4, r5
     742:      	mov	r6, r11
     744:      	add.w	r0, r8, r6, lsl #2
     748:      	ldr	r1, [r0, #0x8]
     74a:      	adds	r3, r6, #0x1
     74c:      	cmp	r1, r7
     74e:      	ble	0x78e <main+0x78e>      @ imm = #0x3c
     750:      	cmp	r3, #0x2
     752:      	str	r1, [r0, #0xc]
     754:      	blt	0x786 <main+0x786>      @ imm = #0x2e
     756:      	ldr	r1, [r4]
     758:      	cmp	r1, r7
     75a:      	ble	0x7a0 <main+0x7a0>      @ imm = #0x42
     75c:      	cmp	r6, #0x1
     75e:      	str	r1, [r0, #0x8]
     760:      	beq	0x786 <main+0x786>      @ imm = #0x22
     762:      	ldr	r0, [r4, #-4]
     766:      	cmp	r0, r7
     768:      	ble	0x796 <main+0x796>      @ imm = #0x2a
     76a:      	cmp	r3, #0x4
     76c:      	str	r0, [r4]
     76e:      	blt	0x79e <main+0x79e>      @ imm = #0x2c
     770:      	ldr	r0, [r4, #-8]
     774:      	cmp	r0, r7
     776:      	ble	0x7ba <main+0x7ba>      @ imm = #0x40
     778:      	subs	r6, #0x4
     77a:      	str	r0, [r4, #-4]
     77e:      	adds	r0, r6, #0x1
     780:      	sub.w	r4, r4, #0x10
     784:      	bne	0x744 <main+0x744>      @ imm = #-0x44
     786:      	movs	r6, #0x0
     788:      	cmp	r6, lr
     78a:      	blo	0x7a6 <main+0x7a6>      @ imm = #0x18
     78c:      	b	0x912 <main+0x912>      @ imm = #0x182
     78e:      	mov	r6, r3
     790:      	cmp	r6, lr
     792:      	blo	0x7a6 <main+0x7a6>      @ imm = #0x10
     794:      	b	0x912 <main+0x912>      @ imm = #0x17a
     796:      	subs	r6, #0x1
     798:      	cmp	r6, lr
     79a:      	blo	0x7a6 <main+0x7a6>      @ imm = #0x8
     79c:      	b	0x912 <main+0x912>      @ imm = #0x172
     79e:      	movs	r6, #0x0
     7a0:      	cmp	r6, lr
     7a2:      	bhs.w	0x912 <main+0x912>      @ imm = #0x16c
     7a6:      	adds	r2, #0x1
     7a8:      	add.w	r11, r11, #0x1
     7ac:      	cmp	r2, lr
     7ae:      	add.w	r5, r5, #0x4
     7b2:      	str.w	r7, [r12, r6, lsl #2]
     7b6:      	bne	0x73c <main+0x73c>      @ imm = #-0x7e
     7b8:      	b	0x7c2 <main+0x7c2>      @ imm = #0x6
     7ba:      	subs	r6, #0x2
     7bc:      	cmp	r6, lr
     7be:      	blo	0x7a6 <main+0x7a6>      @ imm = #-0x1c
     7c0:      	b	0x912 <main+0x912>      @ imm = #0x14e
     7c2:      	ldr.w	r0, [r8]
     7c6:      	cbz	r0, 0x7d4 <main+0x7d4>  @ imm = #0xa
     7c8:      	subs.w	r1, r0, #0xffffffff
     7cc:      	it	ne
     7ce:      	movne	r1, r0
     7d0:      	str.w	r1, [r8]
     7d4:      	bl	0x7d4 <main+0x7d4>      @ imm = #-0x4
     7d8:      	ldr.w	r2, [r10]
     7dc:      	cmp	r2, #0x0
     7de:      	beq.w	0x912 <main+0x912>      @ imm = #0x130
     7e2:      	cmp	r2, #0xff
     7e4:      	bls.w	0x912 <main+0x912>      @ imm = #0x12a
     7e8:      	mov	r10, r0
     7ea:      	mov	r5, r1
     7ec:      	ldr.w	r0, [r8, #0x8]
     7f0:      	ldr.w	r1, [r8, #0x404]
     7f4:      	adds	r0, r0, r1
     7f6:      	bvs.w	0x920 <main+0x920>      @ imm = #0x126
     7fa:      	movs	r1, #0x0
     7fc:      	cmp.w	r1, r2, lsr #9
     800:      	beq.w	0x912 <main+0x912>      @ imm = #0x10e
     804:      	ldr.w	r1, [r8, #0x804]
     808:      	adds	r0, r0, r1
     80a:      	bvs.w	0x920 <main+0x920>      @ imm = #0x112
     80e:      	asrs	r1, r0, #0x1f
     810:      	bl	0x810 <main+0x810>      @ imm = #-0x4
     814:      	mov	r6, r0
     816:      	movw	r0, #0x0
     81a:      	movt	r0, #0x0
     81e:      	mov	r1, r6
     820:      	bl	0x820 <main+0x820>      @ imm = #-0x4
     824:      	ldr	r1, [r6]
     826:      	mov	r7, r0
     828:      	cbz	r1, 0x83a <main+0x83a>  @ imm = #0xe
     82a:      	cmp	r1, #0x1
     82c:      	bne	0x836 <main+0x836>      @ imm = #0x6
     82e:      	mov	r0, r6
     830:      	bl	0x830 <main+0x830>      @ imm = #-0x4
     834:      	b	0x83a <main+0x83a>      @ imm = #0x2
     836:      	subs	r0, r1, #0x1
     838:      	str	r0, [r6]
     83a:      	movw	r1, #0x0
     83e:      	movt	r1, #0x0
     842:      	mov	r0, r7
     844:      	bl	0x844 <main+0x844>      @ imm = #-0x4
     848:      	ldr	r1, [r7]
     84a:      	mov	r6, r0
     84c:      	cbz	r1, 0x85e <main+0x85e>  @ imm = #0xe
     84e:      	cmp	r1, #0x1
     850:      	bne	0x85a <main+0x85a>      @ imm = #0x6
     852:      	mov	r0, r7
     854:      	bl	0x854 <main+0x854>      @ imm = #-0x4
     858:      	b	0x85e <main+0x85e>      @ imm = #0x2
     85a:      	subs	r0, r1, #0x1
     85c:      	str	r0, [r7]
     85e:      	ldr	r0, [sp, #0xe8]
     860:      	movs	r2, #0x0
     862:      	subs.w	r0, r10, r0
     866:      	sbcs.w	r1, r5, r9
     86a:      	adc	r2, r2, #0x0
     86e:      	eor	r2, r2, #0x1
     872:      	cmp	r2, #0x1
     874:      	beq	0x920 <main+0x920>      @ imm = #0xa8
     876:      	bl	0x876 <main+0x876>      @ imm = #-0x4
     87a:      	mov	r7, r0
     87c:      	mov	r0, r6
     87e:      	mov	r1, r7
     880:      	bl	0x880 <main+0x880>      @ imm = #-0x4
     884:      	ldr	r1, [r6]
     886:      	mov	r5, r0
     888:      	cbz	r1, 0x89a <main+0x89a>  @ imm = #0xe
     88a:      	cmp	r1, #0x1
     88c:      	bne	0x896 <main+0x896>      @ imm = #0x6
     88e:      	mov	r0, r6
     890:      	bl	0x890 <main+0x890>      @ imm = #-0x4
     894:      	b	0x89a <main+0x89a>      @ imm = #0x2
     896:      	subs	r0, r1, #0x1
     898:      	str	r0, [r6]
     89a:      	ldr	r0, [r7]
     89c:      	cbz	r0, 0x8ae <main+0x8ae>  @ imm = #0xe
     89e:      	cmp	r0, #0x1
     8a0:      	bne	0x8aa <main+0x8aa>      @ imm = #0x6
     8a2:      	mov	r0, r7
     8a4:      	bl	0x8a4 <main+0x8a4>      @ imm = #-0x4
     8a8:      	b	0x8ae <main+0x8ae>      @ imm = #0x2
     8aa:      	subs	r0, #0x1
     8ac:      	str	r0, [r7]
     8ae:      	movw	r0, #0x0
     8b2:      	movt	r0, #0x0
     8b6:      	mov	r1, r5
     8b8:      	bl	0x8b8 <main+0x8b8>      @ imm = #-0x4
     8bc:      	ldr	r1, [r5]
     8be:      	mov	r6, r0
     8c0:      	cbz	r1, 0x8d2 <main+0x8d2>  @ imm = #0xe
     8c2:      	cmp	r1, #0x1
     8c4:      	bne	0x8ce <main+0x8ce>      @ imm = #0x6
     8c6:      	mov	r0, r5
     8c8:      	bl	0x8c8 <main+0x8c8>      @ imm = #-0x4
     8cc:      	b	0x8d2 <main+0x8d2>      @ imm = #0x2
     8ce:      	subs	r0, r1, #0x1
     8d0:      	str	r0, [r5]
     8d2:      	mov	r0, r6
     8d4:      	bl	0x8d4 <main+0x8d4>      @ imm = #-0x4
     8d8:      	ldr	r0, [r6]
     8da:      	cbz	r0, 0x8ec <main+0x8ec>  @ imm = #0xe
     8dc:      	cmp	r0, #0x1
     8de:      	bne	0x8e8 <main+0x8e8>      @ imm = #0x6
     8e0:      	mov	r0, r6
     8e2:      	bl	0x8e2 <main+0x8e2>      @ imm = #-0x4
     8e6:      	b	0x8ec <main+0x8ec>      @ imm = #0x2
     8e8:      	subs	r0, #0x1
     8ea:      	str	r0, [r6]
     8ec:      	ldr.w	r0, [r8]
     8f0:      	cbz	r0, 0x904 <main+0x904>  @ imm = #0x10
     8f2:      	cmp	r0, #0x1
     8f4:      	bne	0x8fe <main+0x8fe>      @ imm = #0x6
     8f6:      	mov	r0, r8
     8f8:      	bl	0x8f8 <main+0x8f8>      @ imm = #-0x4
     8fc:      	b	0x904 <main+0x904>      @ imm = #0x4
     8fe:      	subs	r0, #0x1
     900:      	str.w	r0, [r8]
     904:      	movs	r0, #0x0
     906:      	add	sp, #0xec
     908:      	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
     90c:      	bl	0x90c <main+0x90c>      @ imm = #-0x4
     910:      	b	0x722 <main+0x722>      @ imm = #-0x1f2
     912:      	movw	r0, #0x0
     916:      	movt	r0, #0x0
     91a:      	adds	r0, #0x8
     91c:      	bl	0x91c <main+0x91c>      @ imm = #-0x4
     920:      	movw	r0, #0x0
     924:      	movt	r0, #0x0
     928:      	adds	r0, #0x8
     92a:      	bl	0x92a <main+0x92a>      @ imm = #-0x4
