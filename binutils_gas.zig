//! SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const cross_config = @import("cross_config.zig");
const CrossConfig = cross_config.CrossConfig;
const Libs = cross_config.Libs;

pub fn addGas(
    b: *std.Build,
    binutils_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    libs: Libs,
    config: CrossConfig,
) *std.Build.Step.Compile {
    // gas/config.in has these #undef entries (binutils 2.42).
    // Values come from the reference cross-build config.h.
    const gas_config_header = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = binutils_root.path(b, "gas/config.in") },
    }, .{
        .AC_APPLE_UNIVERSAL_BUILD = null,
        .AIX_WEAK_SUPPORT = null,
        .BROKEN_ASSERT = null,
        .CROSS_COMPILE = true,
        .DEFAULT_ARCH = null,
        .DEFAULT_COMPRESSED_DEBUG_ALGORITHM = .COMPRESS_DEBUG_GABI_ZLIB,
        .DEFAULT_CRIS_ARCH = null,
        .DEFAULT_EMULATION = "\"\"",
        .DEFAULT_FLAG_COMPRESS_DEBUG = null,
        .DEFAULT_GENERATE_BUILD_NOTES = @as(i64, 0),
        .DEFAULT_GENERATE_ELF_STT_COMMON = @as(i64, 0),
        .DEFAULT_GENERATE_X86_RELAX_RELOCATIONS = @as(i64, 1),
        .DEFAULT_MIPS_FIX_LOONGSON3_LLSC = @as(i64, 0),
        .DEFAULT_RISCV_ARCH_WITH_EXT = null,
        .DEFAULT_RISCV_ATTR = @as(i64, 1),
        .DEFAULT_RISCV_ISA_SPEC = null,
        .DEFAULT_RISCV_PRIV_SPEC = null,
        .DEFAULT_X86_USED_NOTE = @as(i64, 0),
        .EMULATIONS = null,
        .ENABLE_CHECKING = null,
        .ENABLE_NLS = null,
        .HAVE_CFLOCALECOPYPREFERREDLANGUAGES = null,
        .HAVE_CFPREFERENCESCOPYAPPVALUE = null,
        .HAVE_DCGETTEXT = null,
        .HAVE_DECL_ASPRINTF = true,
        .HAVE_DECL_GETOPT = true,
        .HAVE_DECL_MEMPCPY = true,
        .HAVE_DECL_STPCPY = true,
        .HAVE_DLFCN_H = true,
        .HAVE_GETTEXT = null,
        .HAVE_ICONV = null,
        .HAVE_INTTYPES_H = true,
        .HAVE_LC_MESSAGES = true,
        .HAVE_MEMORY_H = true,
        .HAVE_STDINT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_STRSIGNAL = true,
        .HAVE_ST_MTIM_TV_NSEC = true,
        .HAVE_ST_MTIM_TV_SEC = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_TM_GMTOFF = true,
        .HAVE_UNISTD_H = true,
        .HAVE_WINDOWS_H = null,
        .HAVE_ZSTD = null,
        .I386COFF = null,
        .LT_OBJDIR = ".libs/",
        .MIPS_CPU_STRING_DEFAULT = null,
        .MIPS_DEFAULT_64BIT = null,
        .MIPS_DEFAULT_ABI = null,
        .NDS32_DEFAULT_ARCH_NAME = null,
        .NDS32_DEFAULT_AUDIO_EXT = null,
        .NDS32_DEFAULT_DSP_EXT = null,
        .NDS32_DEFAULT_DX_REGS = null,
        .NDS32_DEFAULT_PERF_EXT = null,
        .NDS32_DEFAULT_PERF_EXT2 = null,
        .NDS32_DEFAULT_STRING_EXT = null,
        .NDS32_DEFAULT_ZOL_EXT = null,
        .NDS32_LINUX_TOOLCHAIN = null,
        .NEED_DECLARATION_ENVIRON = null,
        .NEED_DECLARATION_FFS = null,
        .OBJ_MAYBE_AOUT = null,
        .OBJ_MAYBE_COFF = null,
        .OBJ_MAYBE_ECOFF = null,
        .OBJ_MAYBE_ELF = null,
        .OBJ_MAYBE_GENERIC = null,
        .OBJ_MAYBE_SOM = null,
        .PACKAGE = "gas",
        .PACKAGE_BUGREPORT = "",
        .PACKAGE_NAME = "gas",
        .PACKAGE_STRING = b.fmt("gas {}", .{config.binutils_version}),
        .PACKAGE_TARNAME = "gas",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = b.fmt("{}", .{config.binutils_version}),
        .STDC_HEADERS = true,
        .STRICTCOFF = null,
        .TARGET_ALIAS = config.target_triple,
        .TARGET_BYTES_BIG_ENDIAN = @as(i64, 0),
        .TARGET_CANONICAL = config.target_canonical,
        .TARGET_CPU = config.target_cpu,
        .TARGET_OS = config.target_os,
        .TARGET_SOLARIS_COMMENT = null,
        .TARGET_VENDOR = config.target_vendor,
        .TARGET_WITH_CPU = null,
        .USE_BINARY_FOPEN = null,
        .USE_EF_MIPS_ABI_O32 = null,
        .USE_EMULATIONS = null,
        .USING_CGEN = null,
        .VERSION = b.fmt("{}", .{config.binutils_version}),
        .WORDS_BIGENDIAN = if (target.result.cpu.arch.endian() == .big) @as(i64, 1) else null,
        .YYTEXT_POINTER = null,
        ._ALL_SOURCE = true,
        ._FILE_OFFSET_BITS = null,
        ._GNU_SOURCE = true,
        ._LARGE_FILES = null,
        ._MINIX = null,
        ._POSIX_1_SOURCE = null,
        ._POSIX_PTHREAD_SEMANTICS = true,
        ._POSIX_SOURCE = null,
        ._TANDEM_SOURCE = true,
        .__EXTENSIONS__ = true,
    });

    const gas = b.addExecutable(.{
        .name = b.fmt("{s}-as", .{config.target_triple}),
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(gas);

    gas.root_module.addConfigHeader(gas_config_header);
    gas.root_module.addConfigHeader(libs.bfd_header);
    gas.root_module.addConfigHeader(libs.bfdver_header);
    gas.root_module.addCMacro("HAVE_CONFIG_H", "1");
    gas.root_module.addCMacro("CROSS_COMPILE", "1");
    gas.root_module.addCMacro("OBJ_ELF", "1");
    gas.root_module.addCMacro("TE_GENERIC", "1");
    gas.root_module.addCMacro("OBJ_MAYBE_ELF", "1");
    gas.root_module.addCMacro("DEFAULT_ARCH", b.fmt("\"{s}\"", .{config.gas_default_arch}));

    gas.root_module.linkLibrary(libs.bfd);
    gas.root_module.linkLibrary(libs.libopcodes);
    gas.root_module.linkLibrary(libs.iberty);
    gas.root_module.linkLibrary(libs.libsframe);
    gas.root_module.linkSystemLibrary("z", .{});

    gas.root_module.addIncludePath(binutils_root.path(b, "gas"));
    gas.root_module.addIncludePath(binutils_root.path(b, "gas/config"));
    gas.root_module.addIncludePath(binutils_root.path(b, "include"));
    gas.root_module.addIncludePath(binutils_root.path(b, "bfd"));
    gas.root_module.addIncludePath(binutils_root.path(b, "opcodes"));
    gas.root_module.addIncludePath(binutils_root.path(b, "")); // source root for bfd/elf-bfd.h
    gas.root_module.addIncludePath(config.include_dir); // generated headers

    // Core gas sources
    gas.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "gas"),
        .files = &.{
            "as.c",
            "app.c",
            "atof-generic.c",
            "cond.c",
            "compress-debug.c",
            "depend.c",
            "dw2gencfi.c",
            "dwarf2dbg.c",
            "ecoff.c",
            "ehopt.c",
            "expr.c",
            "flonum-copy.c",
            "flonum-konst.c",
            "flonum-mult.c",
            "frags.c",
            "gen-sframe.c",
            "ginsn.c",
            "hash.c",
            "input-file.c",
            "input-scrub.c",
            "listing.c",
            "literal.c",
            "macro.c",
            "messages.c",
            "output-file.c",
            "read.c",
            "remap.c",
            "sb.c",
            "scfi.c",
            "scfidw2gen.c",
            "sframe-opt.c",
            "stabs.c",
            "subsegs.c",
            "symbols.c",
            "write.c",
            "codeview.c",
        },
    });

    // Target-specific sources
    gas.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "gas/config"),
        .files = config.gas_target_srcs,
    });

    return gas;
}
