//! SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const cross_config = @import("cross_config.zig");
const CrossConfig = cross_config.CrossConfig;
const Libs = cross_config.Libs;

pub fn addTools(
    b: *std.Build,
    binutils_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    libs: Libs,
    config: CrossConfig,
) *std.Build.Step.Compile {
    // binutils/config.in keys (binutils 2.42)
    const binutils_config_header = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = binutils_root.path(b,"binutils/config.in") },
    }, .{
        .DEFAULT_AR_DETERMINISTIC = @as(i64, 0),
        .DEFAULT_FOR_COLORED_DISASSEMBLY = @as(i64, 0),
        .DEFAULT_FOR_FOLLOW_LINKS = @as(i64, 1),
        .DEFAULT_F_FOR_IFUNC_SYMBOLS = @as(i64, 0),
        .DEFAULT_STRINGS_ALL = @as(i64, 1),
        .ENABLE_CHECKING = null,
        .ENABLE_LIBCTF = null,
        .ENABLE_NLS = null,
        .EXECUTABLE_SUFFIX = "\"\"",
        .HAVE_CFLOCALECOPYPREFERREDLANGUAGES = null,
        .HAVE_CFPREFERENCESCOPYAPPVALUE = null,
        .HAVE_DCGETTEXT = null,
        .HAVE_DECL_ASPRINTF = true,
        .HAVE_DECL_ENVIRON = true,
        .HAVE_DECL_GETC_UNLOCKED = true,
        .HAVE_DECL_GETOPT = true,
        .HAVE_DECL_STPCPY = true,
        .HAVE_DECL_STRNLEN = true,
        .HAVE_DLFCN_H = true,
        .HAVE_EXECUTABLE_SUFFIX = null,
        .HAVE_FCNTL_H = true,
        .HAVE_FSEEKO = true,
        .HAVE_FSEEKO64 = if (target.result.isGnuLibC()) true else null,
        .HAVE_GETC_UNLOCKED = true,
        .HAVE_GETPAGESIZE = true,
        .HAVE_GETTEXT = null,
        .HAVE_GOOD_UTIME_H = true,
        .HAVE_ICONV = true,
        .HAVE_INTTYPES_H = true,
        .HAVE_LC_MESSAGES = true,
        .HAVE_LIBDEBUGINFOD = null,
        .HAVE_LIBDEBUGINFOD_FIND_SECTION = null,
        .HAVE_MBSTATE_T = true,
        .HAVE_MEMORY_H = true,
        .HAVE_MKDTEMP = true,
        .HAVE_MKSTEMP = true,
        .HAVE_MMAP = true,
        .HAVE_MSGPACK = null,
        .HAVE_STDINT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_STRUCT_STAT_ST_ATIMENSEC = null,
        .HAVE_STRUCT_STAT_ST_ATIMESPEC_TV_NSEC = null,
        .HAVE_STRUCT_STAT_ST_ATIM_ST__TIM_TV_NSEC = null,
        .HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC = true,
        .HAVE_SYS_FILE_H = true,
        .HAVE_SYS_PARAM_H = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TIME_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_SYS_WAIT_H = true,
        .HAVE_UNISTD_H = true,
        .HAVE_UTIMENSAT = true,
        .HAVE_UTIMES = true,
        .HAVE_WINDOWS_H = null,
        .HAVE_ZSTD = null,
        .ICONV_CONST = null,
        .LT_OBJDIR = ".libs/",
        .PACKAGE = "binutils",
        .PACKAGE_BUGREPORT = "",
        .PACKAGE_NAME = "binutils",
        .PACKAGE_STRING = b.fmt("binutils {}", .{config.binutils_version}),
        .PACKAGE_TARNAME = "binutils",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = b.fmt("{}", .{config.binutils_version}),
        .STDC_HEADERS = true,
        .TARGET = config.target_canonical,
        .TARGET_PREPENDS_UNDERSCORE = @as(i64, 1),
        .TYPEOF_STRUCT_STAT_ST_ATIM_IS_STRUCT_TIMESPEC = true,
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

    // Shared utility sources used by most binutils tools
    const common_files: []const []const u8 = &.{
        "bucomm.c",
        "version.c",
        "filemode.c",
    };

    const ToolDef = struct {
        name: []const u8,
        sources: []const []const u8,
        needs_opcodes: bool = false,
        needs_sframe: bool = false,
        skip_common: bool = false,
        skip_bfd: bool = false,
    };

    const tools: []const ToolDef = &.{
        .{
            .name = "objcopy",
            .sources = &.{ "objcopy.c", "not-strip.c", "rename.c", "rddbg.c", "debug.c", "stabs.c", "rdcoff.c", "wrstabs.c" },
        },
        .{
            .name = "objdump",
            .sources = &.{ "objdump.c", "dwarf.c", "prdbg.c", "demanguse.c", "rddbg.c", "debug.c", "stabs.c", "rdcoff.c", "elfcomm.c" },
            .needs_opcodes = true,
        },
        .{
            .name = "readelf",
            .sources = &.{ "readelf.c", "version.c", "unwind-ia64.c", "dwarf.c", "demanguse.c", "elfcomm.c" },
            .needs_sframe = true,
            .skip_common = true,
            .skip_bfd = true,
        },
        .{
            .name = "ar",
            .sources = &.{ "ar.c", "arsup.c", "arparse.c", "arlex.c", "not-ranlib.c", "binemul.c", "emul_vanilla.c", "rename.c" },
        },
        .{
            .name = "ranlib",
            .sources = &.{ "ar.c", "arsup.c", "arparse.c", "arlex.c", "is-ranlib.c", "binemul.c", "emul_vanilla.c", "rename.c" },
        },
        .{
            .name = "nm",
            .sources = &.{ "nm.c", "demanguse.c" },
        },
        .{
            .name = "strip",
            .sources = &.{ "objcopy.c", "is-strip.c", "rename.c", "rddbg.c", "debug.c", "stabs.c", "rdcoff.c", "wrstabs.c" },
        },
        .{
            .name = "size",
            .sources = &.{"size.c"},
        },
        .{
            .name = "strings",
            .sources = &.{"strings.c"},
        },
        .{
            .name = "addr2line",
            .sources = &.{"addr2line.c"},
        },
        .{
            .name = "c++filt",
            .sources = &.{"cxxfilt.c"},
        },
        .{
            .name = "elfedit",
            .sources = &.{ "elfedit.c", "version.c", "elfcomm.c" },
            .skip_common = true,
            .skip_bfd = true,
        },
    };

    var ar_exe: ?*std.Build.Step.Compile = null;

    for (tools) |tool_def| {
        const exe = b.addExecutable(.{
            .name = b.fmt("{s}-{s}", .{ config.target_triple, tool_def.name }),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        b.installArtifact(exe);

        if (std.mem.eql(u8, tool_def.name, "ar")) {
            ar_exe = exe;
        }

        exe.root_module.addConfigHeader(binutils_config_header);
        exe.root_module.addConfigHeader(libs.bfd_header);
        exe.root_module.addConfigHeader(libs.bfdver_header);
        exe.root_module.addCMacro("HAVE_CONFIG_H", "1");
        exe.root_module.addCMacro("TARGET", b.fmt("\"{s}\"", .{config.target_canonical}));
        exe.root_module.addCMacro("bin_dummy_emulation", "bin_vanilla_emulation");
        exe.root_module.addCMacro("OBJDUMP_PRIVATE_VECTORS", "");

        if (!tool_def.skip_bfd) {
            exe.root_module.linkLibrary(libs.bfd);
            exe.root_module.linkLibrary(libs.libsframe);
        }
        if (tool_def.needs_sframe) {
            exe.root_module.linkLibrary(libs.libsframe);
        }
        if (tool_def.needs_opcodes) {
            exe.root_module.linkLibrary(libs.libopcodes);
        }
        exe.root_module.linkLibrary(libs.iberty);
        exe.root_module.linkSystemLibrary("z", .{});

        exe.root_module.addIncludePath(binutils_root.path(b,"binutils"));
        exe.root_module.addIncludePath(binutils_root.path(b,"include"));
        exe.root_module.addIncludePath(binutils_root.path(b,"bfd"));
        exe.root_module.addIncludePath(config.include_dir);

        // Tool-specific source files
        exe.root_module.addCSourceFiles(.{
            .root = binutils_root.path(b,"binutils"),
            .files = tool_def.sources,
        });

        // Common utility files
        if (!tool_def.skip_common) {
            exe.root_module.addCSourceFiles(.{
                .root = binutils_root.path(b,"binutils"),
                .files = common_files,
            });
        }
    }

    return ar_exe.?;
}
