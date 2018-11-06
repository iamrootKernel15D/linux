/* -----------------------------------------------------------------------
 *
 *   Copyright 2009-2014 Intel Corporation; author H. Peter Anvin
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2 or (at your
 *   option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * "Glove box" for BIOS calls.  Avoids the constant problems with BIOSes
 * touching registers they shouldn't be.
 */

	.code16
	.section ".inittext","ax"
	.globl	intcall
	.type	intcall, @function
intcall:
	/* Self-modify the INT instruction.  Ugly, but works. */
	cmpb	%al, 3f
	je	1f
	movb	%al, 3f
	jmp	1f		/* Synchronize pipeline */
1:
	/* Save state #1 (-40) */
	pushfl /* push eflags */
	pushw	%fs
	pushw	%gs
    /* PUSHAD  Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI */
	pushal

	/* Copy input state to stack frame #2 (-44) */
	subw	$44, %sp

    /* dx값을 11번 스택에 넣는다 */
	movw	%dx, %si
	movw	%sp, %di
	movw	$11, %cx
    /* http://faydoc.tripod.com/cpu */
    /* MOVSD   Move doubleword at address DS:(E)SI to address ES:(E)DI */
	rep; movsd

	/* Pop full state from the stack #2 (+44) */
	popal           /* 8개  */
	popw	%gs     /* 0.5개*/
	popw	%fs     /* 0.5개*/
	popw	%es     /* 0.5개*/
	popw	%ds     /* 0.5개*/
	popfl           /* 1개  */
                    /* 전체 11개 44바이트복사. 인자로 받은 값으로 현재 레지스터를 세트 */

	/* Actual INT */
	.byte	0xcd		/* INT opcode */
3:	.byte	0

	/* Push full state to the stack */
	pushfl      /* int후 레지스터 정보를 스택에 푸시 #3 (-44) */
	pushw	%ds
	pushw	%es
	pushw	%fs
	pushw	%gs
	pushal

	/* Re-establish C environment invariants */
	cld     /* 오름차순 */
	movzwl	%sp, %esp   /* sp를esp에 복사하되 상위 16비트는 0으로 채운다 */

    /* cs == ds == es */
	movw	%cs, %ax
	movw	%ax, %ds
	movw	%ax, %es

	/* Copy output state from stack frame */
    /* 68(%esp) == *(esp + 68) */
	movw	68(%esp), %di	/* Original %cx == 3rd argument */ /* intcall때 스택(sp)) */
	andw	%di, %di
	jz	4f                  /* sp가 0이였다면 4로 점프 */
	movw	%sp, %si
	movw	$11, %cx
	rep; movsd
4:	addw	$44, %sp        /* #3 (+44) */

	/* Restore state and return #1(+40) */
	popal
	popw	%gs
	popw	%fs
	popfl
	retl
	.size	intcall, .-intcall
