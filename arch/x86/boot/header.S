/* SPDX-License-Identifier: GPL-2.0 */
/*
 *    header.S
 *
 *    Copyright (C) 1991, 1992 Linus Torvalds
 *
 *    Based on bootsect.S and setup.S
 *    modified by more people than can be counted
 *
 *    Rewritten as a common file by H. Peter Anvin (Apr 2007)
 *
 * BIG FAT NOTE: We're in real mode using 64k segments.  Therefore segment
 * addresses must be multiplied by 16 to obtain their respective linear
 * addresses. To avoid confusion, linear addresses are written using leading
 * hex while segment addresses are written as segment:offset.
 *
 */

#include <asm/segment.h>
#include <asm/boot.h>
#include <asm/page_types.h>
#include <asm/setup.h>
#include <asm/bootparam.h>
#include "boot.h"
#include "voffset.h" /* 존재하지 않는 파일 Make 시 생성될것으로 추측 */
#include "zoffset.h" /* 존재하지 않는 파일 Make 시 생성될것으로 추측 */

BOOTSEG        = 0x07C0        /* original address of boot-sector */
SYSSEG        = 0x1000        /* historical load address >> 4 */

#ifndef SVGA_MODE
#define SVGA_MODE ASK_VGA
#endif

#ifndef ROOT_RDONLY
#define ROOT_RDONLY 1
#endif

    .code16
    /* ax는 플래그.
     * a
     *     section is allocatable 할당가능함.
     * x
     *    section is executable 실행가능함.
     */
    .section ".bstext", "ax"
    
    /* .global 심볼을 외부 참조가 가능하게 한다 */
    .global bootsect_start
bootsect_start:

#ifdef CONFIG_EFI_STUB
    # "MZ", MS-DOS header 
    /* MS DOS에서 MZ파일의 매직넘버 */
    .byte 0x4d
    .byte 0x5a
#endif

    # Normalize the start address
    /* ( jump CS + $start2 ) == ( ljmp $BOOTSEG, $start2 ) */
    /* jump만 하는 경우 CS 세그먼트 + 오프셋으로 점프가됨. */
    /* ljmp는 세그먼트를 지정 가능. 아래의 코드에서는 BOOTSEG(0x07C0)가 세그먼트로 쓰임. */
    ljmp    $BOOTSEG, $start2

    
start2:
    /* 왼쪽에서 오른쪽으로 읽는다. cs 값을 ax로 */
    movw    %cs, %ax
    movw    %ax, %ds
    movw    %ax, %es
    movw    %ax, %ss
    xorw    %sp, %sp /*0으로 초기화*/
    sti /* 인터럽트 활성화 */
    
    /* 내림차순 정렬 direction 플래그를 0으로 설정, 큰것에서 작은 것순서로 */
    /* cld 명령을 통해 영향을 받는 명령어들이 있음. */
    cld 
    
    /* 메시지의 주소를 si에 넣음. source index의 약자 DI 는 Destination Index 의 약자 */
    /* 문자열 처리 명령에서 si, di 레지스터를 사용하는 것으로 추정. */
    movw    $bugger_off_msg, %si 

msg_loop:
    /* si의 맨앞의 값을 al에 복사한 후 si를 1 증가 시킨다. 
    * 풀어서 쓰면 다음과 같다.
    * mov [si], al     si가 가리키는 값을 al( ax레지스터의 low )로 복사. 아스키는 8bit임.
    * add 1, si        si주소를 1 증가.
    */
    lodsb    
    
    /* and byte */
    andb    %al, %al
    /* zero 플래그는 바로 위 연산 결과가 담겨 있음. */
    /* 앞선 연산의 결과가 0이면 ZERO 플래그가 1로 설정 된다. */
    /* zero 플래그가 1이면 점프 즉 andb al% al% 비교 결과가 0이면 loop를 탈출 한다.*/
    jz    bs_die
    
    /* $는 상수, %는 레지스터 e는 1110 */
    movb    $0xe, %ah
    /* 의미를 파악할 수 없음. bx에 7을 넣는다. */
    movw    $7, %bx

    /* https://wiki.osdev.org/BIOS */
    /* INT 0x10 = Video display functions (including VESA/VBE) */
    /*
    *    INT 0x10, AH = 0xE -- display char
    *   char를 출력하는 의미.
    */
    int    $0x10
    jmp    msg_loop

bs_die:
    # Allow the user to press a key, then reboot
    /* ax 초기화 */
    xorw    %ax, %ax
    
    /* INT 0x16 = keyboard functions */
    /* INT 0x16, AH = 0 -- read keyboard scancode (blocking) */
    int    $0x16
    /* http://www.delorie.com/djgpp/doc/rbinter/ix/19.html */
    /* This interrupt reboots the system without clearing memory or restoring interrupt vectors. */
    int    $0x19

    # int 0x19 should never return.  In case it does anyway,
    # invoke the BIOS reset code...
    ljmp    $0xf000,$0xfff0

#ifdef CONFIG_EFI_STUB
    /* 적재될 메모리의 위치를 지정. */
    .org    0x3c
    #
    # Offset to the PE header.
    #
    /* 4byte */
    .long    pe_header
#endif /* CONFIG_EFI_STUB */

    /* 여기서 부터 데이터 영역임. */
    .section ".bsdata", "a"
bugger_off_msg:
    .ascii    "Use a boot loader.\r\n"
    .ascii    "\n"
    .ascii    "Remove disk and press any key to reboot...\r\n"
    .byte    0

#ifdef CONFIG_EFI_STUB
pe_header:
    .ascii    "PE"
    .word     0

coff_header:
#ifdef CONFIG_X86_32
    .word    0x14c                # i386
#else
    .word    0x8664                # x86-64
#endif
    .word    4                # nr_sections
    .long    0                 # TimeDateStamp
    .long    0                # PointerToSymbolTable
    .long    1                # NumberOfSymbols
    .word    section_table - optional_header    # SizeOfOptionalHeader
#ifdef CONFIG_X86_32
    .word    0x306                # Characteristics.
                        # IMAGE_FILE_32BIT_MACHINE |
                        # IMAGE_FILE_DEBUG_STRIPPED |
                        # IMAGE_FILE_EXECUTABLE_IMAGE |
                        # IMAGE_FILE_LINE_NUMS_STRIPPED
#else
    .word    0x206                # Characteristics
                        # IMAGE_FILE_DEBUG_STRIPPED |
                        # IMAGE_FILE_EXECUTABLE_IMAGE |
                        # IMAGE_FILE_LINE_NUMS_STRIPPED
#endif

optional_header:
#ifdef CONFIG_X86_32
    .word    0x10b                # PE32 format
#else
    .word    0x20b                 # PE32+ format
#endif
    .byte    0x02                # MajorLinkerVersion
    .byte    0x14                # MinorLinkerVersion

    # Filled in by build.c
    .long    0                # SizeOfCode

    .long    0                # SizeOfInitializedData
    .long    0                # SizeOfUninitializedData

    # Filled in by build.c
    .long    0x0000                # AddressOfEntryPoint

    .long    0x0200                # BaseOfCode
#ifdef CONFIG_X86_32
    .long    0                # data
#endif

extra_header_fields:
#ifdef CONFIG_X86_32
    .long    0                # ImageBase
#else
    .quad    0                # ImageBase
#endif
    .long    0x20                # SectionAlignment
    .long    0x20                # FileAlignment
    .word    0                # MajorOperatingSystemVersion
    .word    0                # MinorOperatingSystemVersion
    .word    0                # MajorImageVersion
    .word    0                # MinorImageVersion
    .word    0                # MajorSubsystemVersion
    .word    0                # MinorSubsystemVersion
    .long    0                # Win32VersionValue

    #
    # The size of the bzImage is written in tools/build.c
    #
    .long    0                # SizeOfImage

    .long    0x200                # SizeOfHeaders
    .long    0                # CheckSum
    .word    0xa                # Subsystem (EFI application)
    .word    0                # DllCharacteristics
#ifdef CONFIG_X86_32
    .long    0                # SizeOfStackReserve
    .long    0                # SizeOfStackCommit
    .long    0                # SizeOfHeapReserve
    .long    0                # SizeOfHeapCommit
#else
    .quad    0                # SizeOfStackReserve
    .quad    0                # SizeOfStackCommit
    .quad    0                # SizeOfHeapReserve
    .quad    0                # SizeOfHeapCommit
#endif
    .long    0                # LoaderFlags
    .long    0x6                # NumberOfRvaAndSizes

    .quad    0                # ExportTable
    .quad    0                # ImportTable
    .quad    0                # ResourceTable
    .quad    0                # ExceptionTable
    .quad    0                # CertificationTable
    .quad    0                # BaseRelocationTable

    # Section table
section_table:
    #
    # The offset & size fields are filled in by build.c.
    #
    .ascii    ".setup"
    .byte    0
    .byte    0
    .long    0
    .long    0x0                # startup_{32,64}
    .long    0                # Size of initialized data
                        # on disk
    .long    0x0                # startup_{32,64}
    .long    0                # PointerToRelocations
    .long    0                # PointerToLineNumbers
    .word    0                # NumberOfRelocations
    .word    0                # NumberOfLineNumbers
    .long    0x60500020            # Characteristics (section flags)

    #
    # The EFI application loader requires a relocation section
    # because EFI applications must be relocatable. The .reloc
    # offset & size fields are filled in by build.c.
    #
    .ascii    ".reloc"
    .byte    0
    .byte    0
    .long    0
    .long    0
    .long    0                # SizeOfRawData
    .long    0                # PointerToRawData
    .long    0                # PointerToRelocations
    .long    0                # PointerToLineNumbers
    .word    0                # NumberOfRelocations
    .word    0                # NumberOfLineNumbers
    .long    0x42100040            # Characteristics (section flags)

    #
    # The offset & size fields are filled in by build.c.
    #
    .ascii    ".text"
    .byte    0
    .byte    0
    .byte    0
    .long    0
    .long    0x0                # startup_{32,64}
    .long    0                # Size of initialized data
                        # on disk
    .long    0x0                # startup_{32,64}
    .long    0                # PointerToRelocations
    .long    0                # PointerToLineNumbers
    .word    0                # NumberOfRelocations
    .word    0                # NumberOfLineNumbers
    .long    0x60500020            # Characteristics (section flags)

    #
    # The offset & size fields are filled in by build.c.
    #
    .ascii    ".bss"
    .byte    0
    .byte    0
    .byte    0
    .byte    0
    .long    0
    .long    0x0
    .long    0                # Size of initialized data
                        # on disk
    .long    0x0
    .long    0                # PointerToRelocations
    .long    0                # PointerToLineNumbers
    .word    0                # NumberOfRelocations
    .word    0                # NumberOfLineNumbers
    .long    0xc8000080            # Characteristics (section flags)

#endif /* CONFIG_EFI_STUB */

    # Kernel attributes; used by setup.  This is part 1 of the
    # header, from the old boot sector.

    .section ".header", "a"
    .globl    sentinel
                                    /* 손상된 로더를 감지하는 데 사용됩니다. 의미는 아직 모름. */
sentinel:    .byte 0xff, 0xff        /* Used to detect broken loaders */


/* arch\x86\include\uapi\asm\bootparam.h 에 정의된 struct setup_header 구조체. */
    .globl    hdr
hdr:
setup_sects:    .byte 0            /* Filled in by build.c */
root_flags:    .word ROOT_RDONLY
syssize:    .long 0            /* Filled in by build.c */
ram_size:    .word 0            /* Obsolete */
vid_mode:    .word SVGA_MODE
root_dev:    .word 0            /* Filled in by build.c */
boot_flag:    .word 0xAA55

    # offset 512, entry point

    .globl    _start
_start:
        # Explicitly enter this as bytes, or the assembler
        # tries to generate a 3-byte jump here, which causes
        # everything else to push off to the wrong offset.
        .byte    0xeb        # short (2-byte) jump
        .byte    start_of_setup - 1f
1:

    # Part 2 of the header, from the old setup.S

        .ascii    "HdrS"        # header signature
        .word    0x020d        # header version number (>= 0x0105)
                    # or else old loadlin-1.5 will fail)
        .globl realmode_swtch
realmode_swtch:    .word    0, 0        # default_switch, SETUPSEG
start_sys_seg:    .word    SYSSEG        # obsolete and meaningless, but just
                    # in case something decided to "use" it
        .word    kernel_version-512 # pointing to kernel version string
                    # above section of header is compatible
                    # with loadlin-1.5 (header v1.5). Don't
                    # change it.

type_of_loader:    .byte    0        # 0 means ancient bootloader, newer
                    # bootloaders know to change this.
                    # See Documentation/x86/boot.txt for
                    # assigned ids

# flags, unused bits must be zero (RFU) bit within loadflags
loadflags:
        .byte    LOADED_HIGH    # The kernel is to be loaded high

setup_move_size: .word  0x8000        # size to move, when setup is not
                    # loaded at 0x90000. We will move setup
                    # to 0x90000 then just before jumping
                    # into the kernel. However, only the
                    # loader knows how much data behind
                    # us also needs to be loaded.

code32_start:                # here loaders can put a different
                    # start address for 32-bit code.
        .long    0x100000    # 0x100000 = default for big kernel

ramdisk_image:    .long    0        # address of loaded ramdisk image
                    # Here the loader puts the 32-bit
                    # address where it loaded the image.
                    # This only will be read by the kernel.

ramdisk_size:    .long    0        # its size in bytes

bootsect_kludge:
        .long    0        # obsolete

heap_end_ptr:    .word    _end+STACK_SIZE-512
                    # (Header version 0x0201 or later)
                    # space from here (exclusive) down to
                    # end of setup code can be used by setup
                    # for local heap purposes.

ext_loader_ver:
        .byte    0        # Extended boot loader version
ext_loader_type:
        .byte    0        # Extended boot loader type

cmd_line_ptr:    .long    0        # (Header version 0x0202 or later)
                    # If nonzero, a 32-bit pointer
                    # to the kernel command line.
                    # The command line should be
                    # located between the start of
                    # setup and the end of low
                    # memory (0xa0000), or it may
                    # get overwritten before it
                    # gets read.  If this field is
                    # used, there is no longer
                    # anything magical about the
                    # 0x90000 segment; the setup
                    # can be located anywhere in
                    # low memory 0x10000 or higher.

initrd_addr_max: .long 0x7fffffff
                    # (Header version 0x0203 or later)
                    # The highest safe address for
                    # the contents of an initrd
                    # The current kernel allows up to 4 GB,
                    # but leave it at 2 GB to avoid
                    # possible bootloader bugs.

kernel_alignment:  .long CONFIG_PHYSICAL_ALIGN    #physical addr alignment
                        #required for protected mode
                        #kernel
#ifdef CONFIG_RELOCATABLE
relocatable_kernel:    .byte 1
#else
relocatable_kernel:    .byte 0
#endif
min_alignment:        .byte MIN_KERNEL_ALIGN_LG2    # minimum alignment

xloadflags:
#ifdef CONFIG_X86_64
# define XLF0 XLF_KERNEL_64            /* 64-bit kernel */
#else
# define XLF0 0
#endif

#if defined(CONFIG_RELOCATABLE) && defined(CONFIG_X86_64)
   /* kernel/boot_param/ramdisk could be loaded above 4g */
# define XLF1 XLF_CAN_BE_LOADED_ABOVE_4G
#else
# define XLF1 0
#endif

#ifdef CONFIG_EFI_STUB
# ifdef CONFIG_EFI_MIXED
#  define XLF23 (XLF_EFI_HANDOVER_32|XLF_EFI_HANDOVER_64)
# else
#  ifdef CONFIG_X86_64
#   define XLF23 XLF_EFI_HANDOVER_64        /* 64-bit EFI handover ok */
#  else
#   define XLF23 XLF_EFI_HANDOVER_32        /* 32-bit EFI handover ok */
#  endif
# endif
#else
# define XLF23 0
#endif

#if defined(CONFIG_X86_64) && defined(CONFIG_EFI) && defined(CONFIG_KEXEC_CORE)
# define XLF4 XLF_EFI_KEXEC
#else
# define XLF4 0
#endif

            .word XLF0 | XLF1 | XLF23 | XLF4

cmdline_size:   .long   COMMAND_LINE_SIZE-1     #length of the command line,
                                                #added with boot protocol
                                                #version 2.06

hardware_subarch:    .long 0            # subarchitecture, added with 2.07
                        # default to 0 for normal x86 PC

hardware_subarch_data:    .quad 0

payload_offset:        .long ZO_input_data
payload_length:        .long ZO_z_input_len

setup_data:        .quad 0            # 64-bit physical pointer to
                        # single linked list of
                        # struct setup_data

pref_address:        .quad LOAD_PHYSICAL_ADDR    # preferred load addr

#
# Getting to provably safe in-place decompression is hard. Worst case
# behaviours need to be analyzed. Here let's take the decompression of
# a gzip-compressed kernel as example, to illustrate it:
#
# The file layout of gzip compressed kernel is:
#
#    magic[2]
#    method[1]
#    flags[1]
#    timestamp[4]
#    extraflags[1]
#    os[1]
#    compressed data blocks[N]
#    crc[4] orig_len[4]
#
# ... resulting in +18 bytes overhead of uncompressed data.
#
# (For more information, please refer to RFC 1951 and RFC 1952.)
#
# Files divided into blocks
# 1 bit (last block flag)
# 2 bits (block type)
#
# 1 block occurs every 32K -1 bytes or when there 50% compression
# has been achieved. The smallest block type encoding is always used.
#
# stored:
#    32 bits length in bytes.
#
# fixed:
#    magic fixed tree.
#    symbols.
#
# dynamic:
#    dynamic tree encoding.
#    symbols.
#
#
# The buffer for decompression in place is the length of the uncompressed
# data, plus a small amount extra to keep the algorithm safe. The
# compressed data is placed at the end of the buffer.  The output pointer
# is placed at the start of the buffer and the input pointer is placed
# where the compressed data starts. Problems will occur when the output
# pointer overruns the input pointer.
#
# The output pointer can only overrun the input pointer if the input
# pointer is moving faster than the output pointer.  A condition only
# triggered by data whose compressed form is larger than the uncompressed
# form.
#
# The worst case at the block level is a growth of the compressed data
# of 5 bytes per 32767 bytes.
#
# The worst case internal to a compressed block is very hard to figure.
# The worst case can at least be bounded by having one bit that represents
# 32764 bytes and then all of the rest of the bytes representing the very
# very last byte.
#
# All of which is enough to compute an amount of extra data that is required
# to be safe.  To avoid problems at the block level allocating 5 extra bytes
# per 32767 bytes of data is sufficient.  To avoid problems internal to a
# block adding an extra 32767 bytes (the worst case uncompressed block size)
# is sufficient, to ensure that in the worst case the decompressed data for
# block will stop the byte before the compressed data for a block begins.
# To avoid problems with the compressed data's meta information an extra 18
# bytes are needed.  Leading to the formula:
#
# extra_bytes = (uncompressed_size >> 12) + 32768 + 18
#
# Adding 8 bytes per 32K is a bit excessive but much easier to calculate.
# Adding 32768 instead of 32767 just makes for round numbers.
#
# Above analysis is for decompressing gzip compressed kernel only. Up to
# now 6 different decompressor are supported all together. And among them
# xz stores data in chunks and has maximum chunk of 64K. Hence safety
# margin should be updated to cover all decompressors so that we don't
# need to deal with each of them separately. Please check
# the description in lib/decompressor_xxx.c for specific information.
#
# extra_bytes = (uncompressed_size >> 12) + 65536 + 128
#
# LZ4 is even worse: data that cannot be further compressed grows by 0.4%,
# or one byte per 256 bytes. OTOH, we can safely get rid of the +128 as
# the size-dependent part now grows so fast.
#
# extra_bytes = (uncompressed_size >> 8) + 65536

#define ZO_z_extra_bytes    ((ZO_z_output_len >> 8) + 65536)
#if ZO_z_output_len > ZO_z_input_len
# define ZO_z_extract_offset    (ZO_z_output_len + ZO_z_extra_bytes - \
                 ZO_z_input_len)
#else
# define ZO_z_extract_offset    ZO_z_extra_bytes
#endif

/*
 * The extract_offset has to be bigger than ZO head section. Otherwise when
 * the head code is running to move ZO to the end of the buffer, it will
 * overwrite the head code itself.
 */
#if (ZO__ehead - ZO_startup_32) > ZO_z_extract_offset
# define ZO_z_min_extract_offset ((ZO__ehead - ZO_startup_32 + 4095) & ~4095)
#else
# define ZO_z_min_extract_offset ((ZO_z_extract_offset + 4095) & ~4095)
#endif

#define ZO_INIT_SIZE    (ZO__end - ZO_startup_32 + ZO_z_min_extract_offset)

#define VO_INIT_SIZE    (VO__end - VO__text)
#if ZO_INIT_SIZE > VO_INIT_SIZE
# define INIT_SIZE ZO_INIT_SIZE
#else
# define INIT_SIZE VO_INIT_SIZE
#endif

init_size:        .long INIT_SIZE        # kernel initialization size
handover_offset:    .long 0            # Filled in by build.c

# End of setup header #####################################################

    .section ".entrytext", "ax"
start_of_setup:
# Force %es = %ds
    movw    %ds, %ax
    movw    %ax, %es
    cld

# Apparently some ancient versions of LILO invoked the kernel with %ss != %ds,
# which happened to work by accident for the old code.  Recalculate the stack
# pointer if %ss is invalid.  Otherwise leave it alone, LOADLIN sets up the
# stack behind its own code, so we can't blindly put it directly past the heap.

    movw    %ss, %dx
    /*
    * CMP operand 를 비교 (묵시적 마이너스 연산)
    * 첫번째 operand 에서 두번째 operand 값을 뺀다. 결과 = 상태레지스터 operand에 영향 없음.
    */
    cmpw    %ax, %dx    # %ds == %ss?
    movw    %sp, %dx
    /* ds 와 ss과 동일하면 2f로 점프 */
    je    2f        # -> assume %sp is reasonably set

    # Invalid %ss, make up a new stack
    movw    $_end, %dx
    /*
    * TEST(Test)
    * 두 피연산자 사이에 논리적인 AND 연산을 수행하여 플래그 레지스터에 영향을 주지만 결과값은 저장하지 않는다. 
    * OF, CF는 항상 0으로 세트되고 TEST 연산 결과값이 0이면 ZF가 1로세트, 0이 아니면 ZF가 0으로 세트된다.
    */

    testb    $CAN_USE_HEAP, loadflags
    
    /* Jump is zero    ZF=1 */
    jz    1f
    movw    heap_end_ptr, %dx
1:    addw    $STACK_SIZE, %dx
    jnc    2f
    xorw    %dx, %dx    # Prevent wraparound

2:    # Now %dx should point to the end of our stack space    
    /*
    * AND mem(Source), reg(Destination) : reg와 mem을 AND 연산한 후 결과를 reg에 저장
    * 11111111 11111100 && %dx     
    * 현재 DX는 SP임.
    */
    andw    $~3, %dx    # dword align (might as well...)
    
    /* zf=0 이면 점프. 위의 결과가 0이 아니면. */
    jnz    3f
    
    /* (SP)DX가 0이여서 $0xfffc값을 넣어줌 */
    movw    $0xfffc, %dx    # Make sure we're not zero
    
    /* (SP)DX가 0이 아닌 경우. */
3:    movw    %ax, %ss /* 현재 AX는 DS 임. */
    movzwl    %dx, %esp    # Clear upper half of %esp
    sti            # Now we should have a working stack

# We will have entered with %cs = %ds+0x20, normalize %cs so
# it is on par with the other segments.
    
    pushw    %ds
    pushw    $6f
    /* ret는 stack에 있는 데이터를 꺼내서 점프 한다.*/
    /* ljmp ds, $6f */
    lretw 
6:

# Check signature at end of setup
    cmpl    $0x5a5aaa55, setup_sig
    jne    setup_bad

# Zero the bss
    movw    $__bss_start, %di
    movw    $_end+3, %cx
    xorl    %eax, %eax
    
    /* cx - di = cx */
    subw    %di, %cx
    
    /* shr 오른쪽 시프트, shl 왼쪽 시프트 */
    shrw    $2, %cx
    
    /* REP (Repeat String)
     * CX 레지스터를 카운터로 사용해서 문자열 관련 명령을 CX>0인 동안 반복한다.
     * 한번 진행될 때마다 CX 레지스터값이 -1 된다.
     * stol : di가 가리키는 값이 ax를 쓴다.
     */
    rep; stosl /* 4byte 단위로 저장 그래서 위코드에서 우측 시프트 2번 수행 함. */

# Jump to C code (should not return)
    calll    main

# Setup corrupt somehow...
setup_bad:
    movl    $setup_corrupt, %eax
    calll    puts
    # Fall through...

    .globl    die
    .type    die, @function
die:
    /* hlt 다음 외부 인터럽트가 발생할 때까지 중앙 처리 장치 (CPU)를 정지시키는 어셈블리 언어 명령입니다. */
    hlt
    jmp    die

    .size    die, .-die

    .section ".initdata", "a"
setup_corrupt:
    .byte    7
    .string    "No setup signature found...\n"
