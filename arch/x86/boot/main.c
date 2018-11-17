/* -*- linux-c -*- ------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author H. Peter Anvin
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

/*
 * Main module for the real-mode kernel code
 */

#include "boot.h"
#include "string.h"

//메모리 주소를 16의 배수로 설정.
//ex) int a 의 주소값은 0016 or 0032 or 0048 ... 0096 
struct boot_params boot_params __attribute__((aligned(16)));

char *HEAP = _end;
char *heap_end = _end;        /* Default end of heap = no heap */

/*
 * Copy the header into the boot parameter block.  Since this
 * screws up the old-style command line protocol, adjust by
 * filling in the new-style command line pointer instead.
 */
static void copy_boot_params(void)
{
    struct old_cmdline {
        u16 cl_magic;
        u16 cl_offset;
    };
    
    //OLD_CL_ADDRESS = 0x020 == 32
    const struct old_cmdline * const oldcmd =
        (const struct old_cmdline *)OLD_CL_ADDRESS;

    /* boot_params의 크가가 4KB가 아니라면 오류 */
    BUILD_BUG_ON(sizeof boot_params != 4096);
    /* setup_header는 header.S 의                           */
    /* hdr: 라벨에서부터 header 섹션이 끝날때까지의 데이터  */
    /* boot.h : extern struct setup_header hdr;             */
    memcpy(&boot_params.hdr, &hdr, sizeof hdr);

    /* cmd_line_ptr 초기값은 0 이다. */
    if ( !boot_params.hdr.cmd_line_ptr &&
        oldcmd->cl_magic == OLD_CL_MAGIC) {
        /* Old-style command line protocol. */
        u16 cmdline_seg;

        /* Figure out if the command line falls in the region
           of memory that an old kernel would have copied up
           to 0x90000... */
        if (oldcmd->cl_offset < boot_params.hdr.setup_move_size)
            cmdline_seg = ds();
        else
            cmdline_seg = 0x9000;

        boot_params.hdr.cmd_line_ptr =
            (cmdline_seg << 4) + oldcmd->cl_offset;
    }
}

/*
 * Query the keyboard lock status as given by the BIOS, and
 * set the keyboard repeat rate to maximum.  Unclear why the latter
 * is done here; this might be possible to kill off as stale code.
 */
static void keyboard_init(void)
{
    struct biosregs ireg, oreg;
	
    /* 현재 레지스터를 백업해둔다. */
    initregs(&ireg);

	/* int 0x16,2                                   */
	/* 키보드 flags를 얻는다. (read keyboard flags) */
	/*  parameter: 									*/
	/*     ah : 02 									*/
	/* return:                                      */
	/*     al : BIOS keyboard flags 				*/
    ireg.ah = 0x02;        /* Get keyboard status   */
    intcall(0x16, &ireg, &oreg);

	/* int 0x16,3 */
	/* 키보드 반복 주기를 설정한다. (set keyboard typematic rate) 	*/
	/*  parameter: 													*/
	/* ah : 03 														*/
	/* al : 설정 방법을 결정한다. 0은 default, 5는 rate/delay 설정. */
	/* bh : 반복 대기시간 (0=250ms,…, 3=1000ms) 					*/
	/* bl : 키 반복수 0=30, 0x1f=2 									*/
    /* 출저: (iamroot.org/ldocs/linux.html)                         */
    boot_params.kbd_status = oreg.al;
    ireg.ax = 0x0305;    /* Set keyboard repeat rate */
    intcall(0x16, &ireg, NULL);
}

/*
 * Get Intel SpeedStep (IST) information.
 */
static void query_ist(void)
{
    struct biosregs ireg, oreg;

    /* Some older BIOSes apparently crash on this call, so filter
       it from machines too old to have SpeedStep at all. */
    /* IST기능은 x86_64 부터 지원됨 */
    if (cpu.level < 6)
        return;

    /* 0xe980는 기본적인 IST 정보를 얻어오는 것으로 보인다. */
    /* 벤더에게만 제공되는거라 자세한 내용은 알기 어렵다고  */
    /* IST(Interrupt Stack Table)                           */
    /* the ability to automatically switch to a new stack   */
    /* for designated events such as double fault or NMI    */
    initregs(&ireg);
    ireg.ax  = 0xe980;     /* IST Support */
    ireg.edx = 0x47534943;     /* Request value */
    intcall(0x15, &ireg, &oreg);

    boot_params.ist_info.signature  = oreg.eax;
    boot_params.ist_info.command    = oreg.ebx;
    boot_params.ist_info.event      = oreg.ecx;
    boot_params.ist_info.perf_level = oreg.edx;
}

/*
 * Tell the BIOS what CPU mode we intend to run in.
 */
static void set_bios_mode(void)
{
#ifdef CONFIG_X86_64
    struct biosregs ireg;

    initregs(&ireg);
    /* int 0x15,ec00                                                                                */
    /* 이 인터럽트는 BIOS에 동작 모드를 알려준다.(Detect Target Operating Mode callback)            */
    /* AMD BIOS and Kernel Developer's Guide의 12.21 Detect Target Operating Mode Callback를 참조   */
    /* parameter:                                                                                   */
    /* bl : operatin mode, 1:Legacy mode target only, 2:long mode target only, 3:mixed mode target  */
    /* return: */
    /* ah, CF가 0이면 성공이다. */
    /* 출저: (iamroot.org/ldocs/linux.html)                         */

    ireg.ax = 0xec00;
    ireg.bx = 2;

    intcall(0x15, &ireg, NULL);
#endif
}

static void init_heap(void)
{
    char *stack_end;

    /* 부트 프로토콜(hdr)의 플래그(loadflags)가 힙설정(CAN_USE_HEAP)이 되어 있다면 heap_end를 구한다. */
    if (boot_params.hdr.loadflags & CAN_USE_HEAP) {
        /* stack_end = &(*(esp -STACK_SIZE)) = esp - STACK_SIZE */
        asm("leal %P1(%%esp),%0"
            : "=r" (stack_end) : "i" (-STACK_SIZE)); /* STACK_SIZE = 16KB */

        /* heap_end(전역변수) = (_end + STACK_SIZE - 512) + 512 */
        /* 512  : 부트섹터의 크기   */
        /* _end : SETUP의 끝        */
        heap_end = (char *)
            ((size_t)boot_params.hdr.heap_end_ptr + 0x200);

        /* heap_size == stack_size == 0x200 == 512 */
        if (heap_end > stack_end){
            heap_end = stack_end;
        }

    } else {
        /* Boot protocol 2.00 only, no heap available */
        puts("WARNING: Ancient bootloader, some functionality "
             "may be limited!\n");
    }
}

/* 기본적으로 바이오스콜을 이용하여 시스템에 대한 정보를 가져오는 역활을 한다. */
/* 보호모드(32비트)모드에 진입한다면, 더이상 바이오스를 사용할 수 없으므로 미리 가져오는것. */
void main(void)
{
    /* First, copy the boot header into the "zeropage" */
    copy_boot_params();

    /* Initialize the early-boot console */
    /* earyprintk를 하는 기능.           */
    /* console=의 옵션대로 지정된 시리얼 포트를 초기화한다. */
    console_init();
    if (cmdline_find_option_bool("debug"))
        puts("early console in setup code\n");

    /* End of heap check */
    init_heap();

    /* Make sure we have all the proper CPU support */
    if (validate_cpu()) {
        puts("Unable to boot - please use a kernel appropriate "
             "for your CPU.\n");
        die();
    }

    /* Tell the BIOS what CPU mode we intend to run in. */
    set_bios_mode();

    /* Detect memory layout */
    detect_memory();

    /* Set keyboard repeat rate (why?) and query the lock flags */
    keyboard_init();

    /* Query Intel SpeedStep (IST) information */
    query_ist();

    /* Query APM information */
#if defined(CONFIG_APM) || defined(CONFIG_APM_MODULE)
    query_apm_bios();
#endif

    /* Query EDD information */
#if defined(CONFIG_EDD) || defined(CONFIG_EDD_MODULE)
    query_edd();
#endif

    /* Set the video mode */
    set_video();

    /* Do the last things and invoke protected mode */
    go_to_protected_mode();
}
