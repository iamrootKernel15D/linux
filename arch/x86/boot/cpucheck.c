/* -*- linux-c -*- ------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

/*
 * Check for obligatory CPU features and abort if the features are not
 * present.  This code should be compilable as 16-, 32- or 64-bit
 * code, so be very careful with types and inline assembly.
 *
 * This code should not contain any messages; that requires an
 * additional wrapper.
 *
 * As written, this code is not safe for inclusion into the kernel
 * proper (after FPU initialization, in particular).
 */

#ifdef _SETUP
# include "boot.h"
#endif
#include <linux/types.h>
#include <asm/intel-family.h>
#include <asm/processor-flags.h>
#include <asm/required-features.h>
#include <asm/msr-index.h>
#include "string.h"

static u32 err_flags[NCAPINTS];

static const int req_level = CONFIG_X86_MINIMUM_CPU_FAMILY;

static const u32 req_flags[NCAPINTS] =
{
	REQUIRED_MASK0,
	REQUIRED_MASK1,
	0, /* REQUIRED_MASK2 not implemented in this file */
	0, /* REQUIRED_MASK3 not implemented in this file */
	REQUIRED_MASK4,
	0, /* REQUIRED_MASK5 not implemented in this file */
	REQUIRED_MASK6,
	0, /* REQUIRED_MASK7 not implemented in this file */
	0, /* REQUIRED_MASK8 not implemented in this file */
	0, /* REQUIRED_MASK9 not implemented in this file */
	0, /* REQUIRED_MASK10 not implemented in this file */
	0, /* REQUIRED_MASK11 not implemented in this file */
	0, /* REQUIRED_MASK12 not implemented in this file */
	0, /* REQUIRED_MASK13 not implemented in this file */
	0, /* REQUIRED_MASK14 not implemented in this file */
	0, /* REQUIRED_MASK15 not implemented in this file */
	REQUIRED_MASK16,
};

#define A32(a, b, c, d) (((d) << 24)+((c) << 16)+((b) << 8)+(a))

static int is_amd(void)
{
	return cpu_vendor[0] == A32('A', 'u', 't', 'h') &&
	       cpu_vendor[1] == A32('e', 'n', 't', 'i') &&
	       cpu_vendor[2] == A32('c', 'A', 'M', 'D');
}

static int is_centaur(void)
{
	return cpu_vendor[0] == A32('C', 'e', 'n', 't') &&
	       cpu_vendor[1] == A32('a', 'u', 'r', 'H') &&
	       cpu_vendor[2] == A32('a', 'u', 'l', 's');
}

static int is_transmeta(void)
{
	return cpu_vendor[0] == A32('G', 'e', 'n', 'u') &&
	       cpu_vendor[1] == A32('i', 'n', 'e', 'T') &&
	       cpu_vendor[2] == A32('M', 'x', '8', '6');
}

static int is_intel(void)
{
	return cpu_vendor[0] == A32('G', 'e', 'n', 'u') &&
	       cpu_vendor[1] == A32('i', 'n', 'e', 'I') &&
	       cpu_vendor[2] == A32('n', 't', 'e', 'l');
}

/* Returns a bitmask of which words we have error bits in */
static int check_cpuflags(void)
{
	u32 err;
	int i;

	err = 0;
	for (i = 0; i < NCAPINTS; i++) {
        /* 있어야할 cpu플래그가 없으면 (req_flags와 cpu.flag 비트가 다르면) */
		err_flags[i] = req_flags[i] & ~cpu.flags[i];
		if (err_flags[i])
			err |= 1 << i;
	}

	return err;
}

/*
 * Returns -1 on error.
 *
 * *cpu_level is set to the current CPU level; *req_level to the required
 * level.  x86-64 is considered level 64 for this purpose.
 *
 * *err_flags_ptr is set to the flags error array if there are flags missing.
 */
int check_cpu(int *cpu_level_ptr, int *req_level_ptr, u32 **err_flags_ptr)
{
	int err;

    /* 기본 cpu level은 3 (386)             	*/
    /* memset()는 표준c라이브러리와 있는 기능과 */
	/* 유사한 기능을하나 어셈블리어로 작성됨.	*/
 	/* arch/x86/lib/memset_64.S  				*/
	memset(&cpu.flags, 0, sizeof cpu.flags);
	cpu.level = 3;

    /* EFLAGS에 AC 필드가 존재하면 4(486) */
    /* AC(Align check exception)기능은 486부터 지원함 */
	if (has_eflag(X86_EFLAGS_AC))
		cpu.level = 4;

	/* cpuid 명령을 사용해서 cpu에 대한 정보를 가져와서 구조체에 저장한다. */
	get_cpuflags();

	/* get_cpuflags()에서 정상적인 플래그를 가져왔는지 확인한다. */
	err = check_cpuflags();

    /* test_bit()는 두번째 파라미터에서 첫번째 파라미트의 index의 비트를 가져온다. */	
	if (test_bit(X86_FEATURE_LM, cpu.flags))
		cpu.level = 64;

    /* 만약, 오류라면 cpu종류에 따라서 get_cpuflags()나 check_cpuflags()함수를 다시 실행해 본다.        */
	if (err == 0x01 &&                                              /* err가 1이고                      */
	    !(err_flags[0] &                                            /* err_flag에 값이 0이 아닌값이며   */
	      ~((1 << X86_FEATURE_XMM)|(1 << X86_FEATURE_XMM2))) &&     /* X86_FEATURE_XMM/2기능이 지원하고 */
	    is_amd()) {                                                 /* cpu 벤더가 amd면                 */
		/* If this is an AMD and we're only missing SSE+SSE2, try to
		   turn them on */

		u32 ecx = MSR_K7_HWCR;
		u32 eax, edx;

        /* rdmsr: msr레지스터 읽기       */
        /* MSR(Model Specific Registers) */
        /* parameter:                    */
        /* ecx: 읽을 레지스터 주소       */
        /* edx: 읽은 상위 32비트 값      */
        /* eax: 읽은 하위 32비트 값      */
        /* https://wiki.osdev.org/Model_Specific_Registers */
		asm("rdmsr" : "=a" (eax), "=d" (edx) : "c" (ecx));

        /* 하위 16비트clear */
		eax &= ~(1 << 15);

        /* rdmsr: msr레지스터 쓰기  */
        /* parameter:               */
        /* ecx: 쓸 레지스터 주소    */
        /* edx: 쓴 상위 32비트 값   */
        /* eax: 쓴 하위 32비트 값   */
		asm("wrmsr" : : "a" (eax), "d" (edx), "c" (ecx));

		get_cpuflags();	/* Make sure it really did something */
		err = check_cpuflags();
	} else if (err == 0x01 &&                               /* error가 1이고 */
		   !(err_flags[0] & ~(1 << X86_FEATURE_CX8)) &&     /* err_Flag에 0이 아닌 동시에 CX9기능이 있고, */
		   is_centaur() && cpu.model >= 6) {                /* centaur칩이며  model이 6이상일때 */
		/* If this is a VIA C3, we might have to enable CX8
		   explicitly */

        /* SR_VIA_FCR -> VIA Cyrix defined MSRs*/
		u32 ecx = MSR_VIA_FCR;
		u32 eax, edx;

        /* msr을 백업 */
		asm("rdmsr" : "=a" (eax), "=d" (edx) : "c" (ecx));

        /* 2, 7비트를 1로 만든다. */
		eax |= (1<<1)|(1<<7);

        /* msr을 원래대로 복구 */
		asm("wrmsr" : : "a" (eax), "d" (edx), "c" (ecx));

        /* cpu.flags에X86_FEATURE_CX8을 활성화한다고 표시. */
		set_bit(X86_FEATURE_CX8, cpu.flags);

		err = check_cpuflags();
	} else if (err == 0x01 && is_transmeta()) {     /* err이 1(오류)면서 transmeta칩이라면 */
		/* Transmeta might have masked feature bits in word 0 */

		u32 ecx = 0x80860004;
		u32 eax, edx;
		u32 level = 1;

        /* msr을 백업 */
		asm("rdmsr" : "=a" (eax), "=d" (edx) : "c" (ecx));

        /* msr레지스터의 하위32비트를 1로 채운후 cpuid명령을 내려서 정보를 가지고 온다. */
		asm("wrmsr" : : "a" (~0), "d" (edx), "c" (ecx));
		asm("cpuid"
		    : "+a" (level), "=d" (cpu.flags[0])
		    : : "ecx", "ebx");

        /* msr을 원래대로 복구 */
		asm("wrmsr" : : "a" (eax), "d" (edx), "c" (ecx));

		err = check_cpuflags();
	} else if (err == 0x01 &&                               /* err가 1(오류)                            */
		   !(err_flags[0] & ~(1 << X86_FEATURE_PAE)) &&     /* err_flag가 1이고 PAE기능이 지원되고      */
		   is_intel() && cpu.level == 6 &&                  /* intel cpu이고 model이 6을 동시에 만족하며*/
		   (cpu.model == 9 || cpu.model == 13)) {           /* model이 9 또는 13일때                    */
		/* PAE is disabled on this Pentium M but can be forced */
		if (cmdline_find_option_bool("forcepae")) {
			puts("WARNING: Forcing PAE in CPU flags\n");
            /* PentiumM에서는 PAE가 꺼져있지만 강제로 켤수 있다나(...)       */
            /* 그래서 cpu.flag에 값을 넣어서 X86_FEATURE_PAE를 활성화시킨다. */
			set_bit(X86_FEATURE_PAE, cpu.flags);

			err = check_cpuflags();
		}
		else {
			puts("WARNING: PAE disabled. Use parameter 'forcepae' to enable at your own risk!\n");
		}
	}

    /* 에라타 경고문 처리(하드웨어적인 문제가 있는 시스템일경우) */
	if (!err)
		err = check_knl_erratum();

    /* err값이 있으면 좀 더 디테일(?)한 err_flags값을 리턴한다. */
	if (err_flags_ptr)
		*err_flags_ptr = err ? err_flags : NULL;

    /* 첫번째 인자(cpu_level_ptr)가 NULL이면 cpu.level값을 리턴(call by ref)한다. */
	if (cpu_level_ptr)
		*cpu_level_ptr = cpu.level;

    /* 두번째 인자(req_level_ptr)가 NULL이면 req_level값을 리턴(call by ref)사용한다. */
	if (req_level_ptr)
		*req_level_ptr = req_level;

    /* 시스템의 cpu레벨이 요구되는 레벨보다 낮거나, 오류(err)가 있을경우 -1을 리턴 */
    /* 정상적이라면 0을 리턴한다. */
	return (cpu.level < req_level || err) ? -1 : 0;
}

int check_knl_erratum(void)
{
	/*
	 * First check for the affected model/family:
	 */
	if (!is_intel() ||                          /* intel칩이 아니거나 */
	    cpu.family != 6 ||                      /* family가 6이 아니거나 */
	    cpu.model != INTEL_FAM6_XEON_PHI_KNL)   /*  INTEL_FAM6_XEON_PHI_KNL도 아닐경우 */
		return 0;

	/*
	 * This erratum affects the Accessed/Dirty bits, and can
	 * cause stray bits to be set in !Present PTEs.  We have
	 * enough bits in our 64-bit PTEs (which we have on real
	 * 64-bit mode or PAE) to avoid using these troublesome
	 * bits.  But, we do not have enough space in our 32-bit
	 * PTEs.  So, refuse to run on 32-bit non-PAE kernels.
	 */
    /* x86 64비트나 PAE 사용할 경우는 에라타처리가 없다. */
	if (IS_ENABLED(CONFIG_X86_64) || IS_ENABLED(CONFIG_X86_PAE))
		return 0;

	puts("This 32-bit kernel can not run on this Xeon Phi x200\n"
	     "processor due to a processor erratum.  Use a 64-bit\n"
	     "kernel, or enable PAE in this 32-bit kernel.\n\n");

	return -1;
}


