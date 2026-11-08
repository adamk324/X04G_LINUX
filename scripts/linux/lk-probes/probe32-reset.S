@ LK probe P1/P2: 32-bit "kernel" that immediately requests PSCI SYSTEM_RESET.
@ A reset within a few seconds of "Booting OKAY" proves LK jumped to the kernel slot.
	.syntax unified
	.arch armv7-a
	.arch_extension sec
	.arm
	.text
start:
	.rept 8
	mov	r0, r0			@ zImage-style NOP sled
	.endr
	b	code
	.word	0x016f2818		@ zImage magic
	.word	0			@ load/start address (position independent)
	.word	end - start		@ end: lets 32-bit loaders find an appended DTB
code:
	movw	r0, #0x0009
	movt	r0, #0x8400		@ PSCI 0.2 SYSTEM_RESET
	smc	#0
1:	b	1b			@ if PSCI returns, hang (watchdog resets ~60 s later)
	.balign	8
end:
