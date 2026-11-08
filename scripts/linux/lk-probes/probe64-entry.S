// AArch64 part of probe P3: reached only if ATF switched the CPU to AArch64.
	.text
	movz	w0, #0x0009
	movk	w0, #0x8400, lsl #16	// PSCI SYSTEM_RESET (SMC32 function id, valid from AArch64)
	smc	#0
1:	b	1b
