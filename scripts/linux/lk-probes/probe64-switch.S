@ LK probes P3/P4/P4b: the zimage64 mode switch in isolation, same header/entry convention as
@ zimage64 (gitlab.com/sleirsgoevy/zimage64 crt.S): word 0 is "b trampoline" in AArch32 and
@ "ands x18, x0, x0" in AArch64; word 1 is an AArch64 branch to the 64-bit code.
@ The AArch32 trampoline asks MediaTek ATF to re-enter at the image start in AArch64
@ (smc 0x82000200, r1 = entry, r2 = DT from LK, r4 = 1 KERNEL_64). The AArch64 code resets
@ the board via PSCI. Fast reset => switch works. ~60 s => switch failed (hang on purpose).
	.syntax unified
	.arch armv7-a
	.arch_extension sec
	.arm
	.text
start:
	.word	0xea000000 + (tramp - start - 8) / 4	@ A32: b tramp | A64: ands x18, x0, x0
	.word	0x14000000 + (a64 - start - 4) / 4	@ A64: b a64
	.quad	0					@ text_offset
	.word	end - start				@ image_size (low)
	.word	0					@ image_size (high)
	.quad	2					@ flags
	.quad	0
	.word	0
	.word	end - start				@ lets 32-bit loaders find an appended DTB
	.quad	0
	.word	0x644d5241				@ "ARM\x64"
	.word	0
tramp:
	.ifndef	SIP_ID_LO
	.set	SIP_ID_LO, 0x0200		@ zimage64 default: smc 0x82000200
	.endif
	.ifndef	SET_R3_ZERO
	.set	SET_R3_ZERO, 0
	.endif
	movw	r0, #SIP_ID_LO
	movt	r0, #0x8200		@ MTK SiP: continue in AArch64
	.if	SET_R3_ZERO
	mov	r3, #0			@ LK passes r3 = 0 (boot_linux -> smc 0x82000115)
	.else
	movw	r3, #0x5678
	movt	r3, #0x1234		@ deliberately non-zero: tests whether ATF ignores r3
	.endif
	sub	r1, pc, #(. + 8 - start)	@ r1 = absolute address of start
	mov	r4, #1			@ KERNEL_64
	smc	#0
1:	b	1b			@ switch refused: hang
	.balign	16
a64:
	.incbin	"probe64-entry.bin"
	.balign	8
end:
