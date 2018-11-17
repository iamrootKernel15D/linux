/* ----------------------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

/*
 * The actual transition into protected mode
 */

#include <asm/boot.h>
#include <asm/processor-flags.h>
#include <asm/segment.h>
#include <linux/linkage.h>

	.text
	.code16

/*
 * void protected_mode_jump(u32 entrypoint, u32 bootparams);
 */
/* parameter: eax, edx, ecx ...
GLOBAL(protected_mode_jump)
	movl	%edx, %esi		# Pointer to boot_params table 
                            # 두번째파라미터(&boot_params + ds segment address)를 esi에 저장
	xorl	%ebx, %ebx      # ebx  = 0
	movw	%cs, %bx        # cs   = 0
	shll	$4, %ebx        # ebx  =<< 4
	addl	%ebx, 2f        # ebx += 2:(lable address)
	jmp	1f			        # Short jump to serialize on 386/486 (cr0레지스터 때문에 파이프라인 클리어 헤야함)
1:

	movw	$__BOOT_DS, %cx
	movw	$__BOOT_TSS, %di

    # 32비트(보호)모드로 변경
	movl	%cr0, %edx
	orb	$X86_CR0_PE, %dl	# Protected mode
	movl	%edx, %cr0

    # 하드코딩으로 작성된 long jump 이를 사용하면 GDT의 CS값을 사용하게 된다.
	# Transition to 32-bit mode
	.byte	0x66, 0xea		# ljmpl opcode
2:	.long	in_pm32			# offset
	.word	__BOOT_CS		# segment
ENDPROC(protected_mode_jump)

	.code32
	.section ".text32","ax"
GLOBAL(in_pm32)
	# Set up data segments for flat 32-bit mode
    # 세그먼트를 ds와 같게 해준다.
	movl	%ecx, %ds
	movl	%ecx, %es
	movl	%ecx, %fs
	movl	%ecx, %gs
	movl	%ecx, %ss
	# The 32-bit code sets up its own stack, but this way we do have
	# a valid stack if some debugging hack wants to use it.
    # 32비트 jmp를 기준으로 스택 사용
	addl	%ebx, %esp

	# Set up TR to make Intel VT happy
	ltr	%di

	# Clear registers to allow for future extensions to the
	# 32-bit boot protocol
    # 일반 범용 레지스터를 0으로 초기화
	xorl	%ecx, %ecx
	xorl	%edx, %edx
	xorl	%ebx, %ebx
	xorl	%ebp, %ebp
	xorl	%edi, %edi

	# Set up LDTR to make Intel VT happy
	lldt	%cx

    # arch/x86/boot/compressed/head_64.S
	jmpl	*%eax			# Jump to the 32-bit entrypoint (jmp boot_params.hdr.code33_start)
                            # code32_start: .long    0x100000    # 0x100000 = default for big kernel
ENDPROC(in_pm32)
