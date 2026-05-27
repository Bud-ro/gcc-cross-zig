//! SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const cross_config = @import("cross_config.zig");
const CrossConfig = cross_config.CrossConfig;
const Libs = cross_config.Libs;

pub fn addLd(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    libs: Libs,
    config: CrossConfig,
) *std.Build.Step.Compile {
    // ld/config.in keys (binutils 2.42)
    const ld_config_header = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = upstream.path("ld/config.in") },
    }, .{
        .DEFAULT_COMPRESSED_DEBUG_ALGORITHM = .COMPRESS_DEBUG_GABI_ZLIB,
        .DEFAULT_EMIT_GNU_HASH = @as(i64, 0),
        .DEFAULT_EMIT_SYSV_HASH = @as(i64, 1),
        .DEFAULT_FLAG_COMPRESS_DEBUG = null,
        .DEFAULT_LD_ERROR_EXECSTACK = @as(i64, 0),
        .DEFAULT_LD_ERROR_RWX_SEGMENTS = @as(i64, 0),
        .DEFAULT_LD_EXECSTACK = @as(i64, 1),
        .DEFAULT_LD_TEXTREL_CHECK = .textrel_check_none,
        .DEFAULT_LD_TEXTREL_CHECK_WARNING = @as(i64, 0),
        .DEFAULT_LD_WARN_EXECSTACK = @as(i64, 2),
        .DEFAULT_LD_WARN_RWX_SEGMENTS = @as(i64, 1),
        .DEFAULT_LD_Z_MARK_PLT = @as(i64, 0),
        .DEFAULT_LD_Z_RELRO = @as(i64, 0),
        .DEFAULT_LD_Z_SEPARATE_CODE = @as(i64, 0),
        .DEFAULT_NEW_DTAGS = @as(i64, 0),
        .ENABLE_CHECKING = null,
        .ENABLE_LIBCTF = null,
        .ENABLE_NLS = null,
        .EXTRA_SHLIB_EXTENSION = null,
        .GOT_HANDLING_DEFAULT = .GOT_HANDLING_TARGET_DEFAULT,
        .HAVE_CFLOCALECOPYPREFERREDLANGUAGES = null,
        .HAVE_CFPREFERENCESCOPYAPPVALUE = null,
        .HAVE_CLOSE = true,
        .HAVE_DCGETTEXT = null,
        .HAVE_DECL_ASPRINTF = true,
        .HAVE_DECL_ENVIRON = true,
        .HAVE_DECL_GETOPT = true,
        .HAVE_DECL_STPCPY = true,
        .HAVE_DLFCN_H = true,
        .HAVE_ELF_HINTS_H = null,
        .HAVE_FCNTL_H = true,
        .HAVE_GETPAGESIZE = true,
        .HAVE_GETTEXT = null,
        .HAVE_GLOB = true,
        .HAVE_ICONV = null,
        .HAVE_INITFINI_ARRAY = true,
        .HAVE_INTTYPES_H = true,
        .HAVE_JANSSON = null,
        .HAVE_LC_MESSAGES = true,
        .HAVE_LIMITS_H = true,
        .HAVE_LSEEK = true,
        .HAVE_MEMORY_H = true,
        .HAVE_MKSTEMP = true,
        .HAVE_MMAP = true,
        .HAVE_OPEN = true,
        .HAVE_REALPATH = true,
        .HAVE_STDINT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_SYS_FILE_H = true,
        .HAVE_SYS_MMAN_H = true,
        .HAVE_SYS_PARAM_H = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TIME_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_UNISTD_H = true,
        .HAVE_WAITPID = true,
        .HAVE_WINDOWS_H = null,
        .HAVE_ZSTD = null,
        .LT_OBJDIR = ".libs/",
        .PACKAGE = "ld",
        .PACKAGE_BUGREPORT = "",
        .PACKAGE_NAME = "ld",
        .PACKAGE_STRING = b.fmt("ld {}", .{config.binutils_version}),
        .PACKAGE_TARNAME = "ld",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = b.fmt("{}", .{config.binutils_version}),
        .SIZEOF_VOID_P = target.result.ptrBitWidth() / 8,
        .STDC_HEADERS = true,
        .SUPPORT_ERROR_HANDLING_SCRIPT = true,
        .USE_BINARY_FOPEN = null,
        .VERSION = b.fmt("{}", .{config.binutils_version}),
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

    const ld = b.addExecutable(.{
        .name = b.fmt("{s}-ld", .{config.target_triple}),
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(ld);

    ld.root_module.addConfigHeader(ld_config_header);
    ld.root_module.addConfigHeader(libs.bfd_header);
    ld.root_module.addConfigHeader(libs.bfdver_header);
    ld.root_module.addCMacro("HAVE_CONFIG_H", "1");
    ld.root_module.addCMacro("TARGET", b.fmt("\"{s}\"", .{config.target_canonical}));
    ld.root_module.addCMacro("BINDIR", "\"/usr/local/bin\"");
    ld.root_module.addCMacro("TOOLBINDIR", b.fmt("\"/usr/local/{s}/bin\"", .{config.target_triple}));
    ld.root_module.addCMacro("SCRIPTDIR", b.fmt("\"/usr/local/{s}/lib\"", .{config.target_triple}));
    ld.root_module.addCMacro("TARGET_SYSTEM_ROOT", "\"\"");
    ld.root_module.addCMacro("TARGET_SYSTEM_ROOT_RELOCATABLE", "0");
    ld.root_module.addCMacro("ELF_LIST_OPTIONS", "1");
    ld.root_module.addCMacro("ELF_SHLIB_LIST_OPTIONS", "1");
    ld.root_module.addCMacro("ELF_PLT_UNWIND_LIST_OPTIONS", "1");
    ld.root_module.addCMacro("DEFAULT_EMULATION", b.fmt("\"{s}\"", .{config.ld_default_emulation}));

    ld.root_module.linkLibrary(libs.bfd);
    ld.root_module.linkLibrary(libs.libopcodes);
    ld.root_module.linkLibrary(libs.iberty);
    ld.root_module.linkLibrary(libs.libsframe);
    ld.root_module.linkSystemLibrary("z", .{});

    ld.root_module.addIncludePath(upstream.path("ld"));
    ld.root_module.addIncludePath(upstream.path("include"));
    ld.root_module.addIncludePath(upstream.path("bfd"));
    ld.root_module.addIncludePath(config.include_dir); // ldemul-list.h
    ld.root_module.addIncludePath(config.vendor_ld_dir); // emulation file include path

    // Core ld sources (pre-generated ldgram.c and ldlex-wrapper.c ship in tarball)
    ld.root_module.addCSourceFiles(.{
        .root = upstream.path("ld"),
        .files = &.{
            "ldmain.c",
            "ldmisc.c",
            "ldlang.c",
            "ldexp.c",
            "ldfile.c",
            "ldwrite.c",
            "lexsup.c",
            "ldbuildid.c",
            "ldcref.c",
            "ldctor.c",
            "ldemul.c",
            "ldver.c",
            "ldelf.c",
            "ldelfgen.c",
            "mri.c",
            "plugin.c",
            "ldgram.c",
            "ldlex-wrapper.c",
        },
    });

    // Vendored emulation file(s)
    ld.root_module.addCSourceFile(.{
        .file = config.ld_emulation_file,
    });
    for (config.ld_extra_emulation_files) |emul_file| {
        ld.root_module.addCSourceFile(.{
            .file = emul_file,
        });
    }

    return ld;
}
