// SPDX-License-Identifier: GPL-2.0
#include <linux/types.h>
#include "bitops.h"

#include <asm/processor-flags.h>
#include <asm/required-features.h>
#include <asm/msr-index.h>
#include "cpuflags.h"

struct cpu_features cpu;
u32 cpu_vendor[3];

static bool loaded_flags;

/* FPU가 시스템상에 존재하는지 확인. */
static int has_fpu(void)
{
	u16 fcw = -1, fsw = -1;
	unsigned long cr0;

	asm volatile("mov %%cr0,%0" : "=r" (cr0));
	if (cr0 & (X86_CR0_EM|X86_CR0_TS)) {
		cr0 &= ~(X86_CR0_EM|X86_CR0_TS);
		asm volatile("mov %0,%%cr0" : : "r" (cr0));
	}

	asm volatile("fninit ; fnstsw %0 ; fnstcw %1"
		     : "+m" (fsw), "+m" (fcw));

	return fsw == 0 && (fcw & 0x103f) == 0x003f;
}

/*
 * For building the 16-bit code we want to explicitly specify 32-bit
 * push/pop operations, rather than just saying 'pushf' or 'popf' and
 * letting the compiler choose. But this is also included from the
 * compressed/ directory where it may be 64-bit code, and thus needs
 * to be 'pushfq' or 'popfq' in that case.
 */
#ifdef __x86_64__
#define PUSHF "pushfq"  /* push eflag */
#define POPF "popfq"    /* pop  elfag */
#else
#define PUSHF "pushfl"
#define POPF "popfl"
#endif

int has_eflag(unsigned long mask)
{
	unsigned long f0, f1;

    /* EFLAG의 값을 스택에 넣은다음, EFLAG를 변수로 추출 */
    /* 이후에 정의된 mask비트를 사용해서 EFLAG의 특정비트를 알아낸다 */
	asm volatile(PUSHF "	\n\t"
		     PUSHF "	\n\t"
		     "pop %0	\n\t"
		     "mov %0,%1	\n\t"
		     "xor %2,%1	\n\t"
		     "push %1	\n\t"
		     POPF "	\n\t"
		     PUSHF "	\n\t"
		     "pop %1	\n\t"
		     POPF
		     : "=&r" (f0), "=&r" (f1)
		     : "ri" (mask));

	return !!((f0^f1) & mask);
}

/* Handle x86_32 PIC using ebx. */
#if defined(__i386__) && defined(__PIC__)
# define EBX_REG "=r"
#else
# define EBX_REG "=b"
#endif

/* x86의"cpuid"명령을 사용하여cpu정보를 알아낸다. */
/* 그러면ax, bx, cx, dx에 정보가 저장되고 그것을 vender배열로 리턴 */
static inline void cpuid_count(u32 id, u32 count,
		u32 *a, u32 *b, u32 *c, u32 *d)
{
    /* cpuid명령 : https://ko.wikipedia.org/wiki/CPUID */
	asm volatile(".ifnc %%ebx,%3 ; movl  %%ebx,%3 ; .endif	\n\t"
		     "cpuid					\n\t"
		     ".ifnc %%ebx,%3 ; xchgl %%ebx,%3 ; .endif	\n\t"
		    : "=a" (*a), "=c" (*c), "=d" (*d), EBX_REG (*b)
		    : "a" (id), "c" (count)
	);
}

/*  두번째 인자가 0임을 유의 */
#define cpuid(id, a, b, c, d) cpuid_count(id, 0, a, b, c, d)

/* "x86의 cpuid명령"을 통해서 cpu에 대한 정보를 가저와서*/
/* "커널의 cpu_features 구조체"에 저장 */
void get_cpuflags(void)
{
	u32 max_intel_level, max_amd_level;
	u32 tfms;
	u32 ignored;

	if (loaded_flags)
		return;
	loaded_flags = true;

	if (has_fpu())
		set_bit(X86_FEATURE_FPU, cpu.flags);

	if (has_eflag(X86_EFLAGS_ID)) {
		cpuid(0x0, &max_intel_level, &cpu_vendor[0], &cpu_vendor[2],
		      &cpu_vendor[1]);

		if (max_intel_level >= 0x00000001 &&
		    max_intel_level <= 0x0000ffff) {
			cpuid(0x1, &tfms, &ignored, &cpu.flags[4],
			      &cpu.flags[0]);
			cpu.level = (tfms >> 8) & 15;
			cpu.family = cpu.level;
			cpu.model = (tfms >> 4) & 15;
			if (cpu.level >= 6)
				cpu.model += ((tfms >> 16) & 0xf) << 4;
		}

		if (max_intel_level >= 0x00000007) {
			cpuid_count(0x00000007, 0, &ignored, &ignored,
					&cpu.flags[16], &ignored);
		}

		cpuid(0x80000000, &max_amd_level, &ignored, &ignored,
		      &ignored);

		if (max_amd_level >= 0x80000001 &&
		    max_amd_level <= 0x8000ffff) {
			cpuid(0x80000001, &ignored, &ignored, &cpu.flags[6],
			      &cpu.flags[1]);
		}
	}
}
