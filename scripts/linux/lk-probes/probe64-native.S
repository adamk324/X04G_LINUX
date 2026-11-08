// LK probe P5: minimal arm64 "Image" for LK's native 64-bit path (bootopt ...,64N2).
// Standard arm64 Image header so LK/ATF treat it like a kernel; code resets via PSCI.
	.text
start:
	b	code			// code0
	.word	0			// code1
	.quad	0			// text_offset
	.quad	end - start		// image_size
	.quad	2			// flags: LE, 4K pages
	.quad	0, 0, 0			// res2..res4
	.word	0x644d5241		// "ARM\x64"
	.word	0			// res5
code:
	movz	w0, #0x0009
	movk	w0, #0x8400, lsl #16	// PSCI SYSTEM_RESET
	smc	#0
1:	b	1b
	.balign	8
end:
