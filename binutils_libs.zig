//! Binutils library builds (libiberty, libsframe, libbfd, libopcodes).
//! Derived from allyourcodebase/binutils (GPL-2.0), adapted for
//! cross-compilation with fixed target vector selection.
//! Copyright (C) Free Software Foundation, Inc. (binutils)
//! Copyright (C) allyourcodebase contributors (build system patterns)
//! SPDX-License-Identifier: GPL-2.0-or-later

const std = @import("std");
const cross_config = @import("cross_config.zig");
const CrossConfig = cross_config.CrossConfig;

// ---------------------------------------------------------------------------
// libiberty
// ---------------------------------------------------------------------------
pub fn addLibiberty(
    b: *std.Build,
    binutils_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const config_header = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = binutils_root.path(b, "libiberty/config.in") },
    }, .{
        .AC_APPLE_UNIVERSAL_BUILD = null,
        .CRAY_STACKSEG_END = null,
        .HAVE_ALLOCA_H = true,
        .HAVE_ASPRINTF = true,
        .HAVE_ATEXIT = true,
        .HAVE_BASENAME = true,
        .HAVE_BCMP = true,
        .HAVE_BCOPY = true,
        .HAVE_BSEARCH = true,
        .HAVE_BZERO = true,
        .HAVE_CALLOC = true,
        .HAVE_CANONICALIZE_FILE_NAME = if (target.result.isGnuLibC()) true else null,
        .HAVE_CLOCK = true,
        .HAVE_DECL_ASPRINTF = true,
        .HAVE_DECL_BASENAME = true,
        .HAVE_DECL_CALLOC = true,
        .HAVE_DECL_FFS = true,
        .HAVE_DECL_GETENV = true,
        .HAVE_DECL_GETOPT = true,
        .HAVE_DECL_MALLOC = true,
        .HAVE_DECL_REALLOC = true,
        .HAVE_DECL_SBRK = true,
        .HAVE_DECL_SNPRINTF = true,
        .HAVE_DECL_STRNLEN = true,
        .HAVE_DECL_STRTOL = true,
        .HAVE_DECL_STRTOLL = true,
        .HAVE_DECL_STRTOUL = true,
        .HAVE_DECL_STRTOULL = true,
        .HAVE_DECL_STRVERSCMP = true,
        .HAVE_DECL_VASPRINTF = true,
        .HAVE_DECL_VSNPRINTF = true,
        .HAVE_DUP3 = true,
        .HAVE_FCNTL_H = true,
        .HAVE_FFS = true,
        .HAVE_FORK = true,
        .HAVE_GETCWD = true,
        .HAVE_GETPAGESIZE = true,
        .HAVE_GETRLIMIT = true,
        .HAVE_GETRUSAGE = true,
        .HAVE_GETSYSINFO = null,
        .HAVE_GETTIMEOFDAY = true,
        .HAVE_INDEX = true,
        .HAVE_INSQUE = true,
        .HAVE_INTPTR_T = true,
        .HAVE_INTTYPES_H = true,
        // .HAVE_LIBGEN_H not in 2.42 config.in
        .HAVE_LIMITS_H = true,
        .HAVE_LONG_LONG = true,
        .HAVE_MACHINE_HAL_SYSINFO_H = null,
        .HAVE_MALLOC_H = true,
        .HAVE_MEMCHR = true,
        .HAVE_MEMCMP = true,
        .HAVE_MEMCPY = true,
        .HAVE_MEMMEM = true,
        .HAVE_MEMMOVE = true,
        .HAVE_MEMORY_H = true,
        // .HAVE_MEMRCHR not in 2.42 config.in
        .HAVE_MEMSET = true,
        .HAVE_MKSTEMPS = true,
        .HAVE_MMAP = null,
        .HAVE_ON_EXIT = if (target.result.isGnuLibC()) true else null,
        .HAVE_PIPE2 = true,
        .HAVE_POSIX_SPAWN = true,
        .HAVE_POSIX_SPAWNP = true,
        .HAVE_PROCESS_H = null,
        .HAVE_PSIGNAL = true,
        .HAVE_PSTAT_GETDYNAMIC = null,
        .HAVE_PSTAT_GETSTATIC = null,
        .HAVE_PUTENV = true,
        .HAVE_RANDOM = true,
        .HAVE_REALPATH = true,
        .HAVE_RENAME = true,
        .HAVE_RINDEX = true,
        .HAVE_SBRK = true,
        .HAVE_SETENV = true,
        .HAVE_SETPROCTITLE = null,
        .HAVE_SETRLIMIT = true,
        .HAVE_SIGSETMASK = if (target.result.isGnuLibC()) true else null,
        .HAVE_SNPRINTF = true,
        .HAVE_SPAWNVE = null,
        .HAVE_SPAWNVPE = null,
        .HAVE_SPAWN_H = true,
        .HAVE_STDINT_H = true,
        .HAVE_STDIO_EXT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STPCPY = true,
        .HAVE_STPNCPY = true,
        .HAVE_STRCASECMP = true,
        .HAVE_STRCHR = true,
        .HAVE_STRDUP = true,
        .HAVE_STRERROR = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_STRNCASECMP = true,
        .HAVE_STRNDUP = true,
        .HAVE_STRNLEN = true,
        .HAVE_STRRCHR = true,
        .HAVE_STRSIGNAL = true,
        .HAVE_STRSTR = true,
        .HAVE_STRTOD = true,
        .HAVE_STRTOL = true,
        .HAVE_STRTOLL = true,
        .HAVE_STRTOUL = true,
        .HAVE_STRTOULL = true,
        .HAVE_STRVERSCMP = true,
        .HAVE_SYSCONF = true,
        .HAVE_SYSCTL = if (target.result.isGnuLibC()) true else null,
        .HAVE_SYSMP = null,
        .HAVE_SYS_ERRLIST = if (target.result.isGnuLibC()) true else null,
        .HAVE_SYS_FILE_H = true,
        .HAVE_SYS_MMAN_H = true,
        .HAVE_SYS_NERR = if (target.result.isGnuLibC()) true else null,
        .HAVE_SYS_PARAM_H = true,
        .HAVE_SYS_PRCTL_H = true,
        .HAVE_SYS_PSTAT_H = null,
        .HAVE_SYS_RESOURCE_H = true,
        .HAVE_SYS_SIGLIST = if (target.result.isGnuLibC()) true else null,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_SYSCTL_H = null,
        .HAVE_SYS_SYSINFO_H = true,
        .HAVE_SYS_SYSMP_H = null,
        .HAVE_SYS_SYSTEMCFG_H = null,
        .HAVE_SYS_TABLE_H = null,
        .HAVE_SYS_TIME_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_SYS_WAIT_H = true,
        .HAVE_TABLE = null,
        .HAVE_TIMES = true,
        .HAVE_TIME_H = true,
        .HAVE_TMPNAM = true,
        .HAVE_UINTPTR_T = true,
        .HAVE_UNISTD_H = true,
        .HAVE_VASPRINTF = true,
        .HAVE_VFORK = true,
        .HAVE_VFORK_H = null,
        .HAVE_VFPRINTF = true,
        .HAVE_VPRINTF = true,
        .HAVE_VSPRINTF = true,
        .HAVE_WAIT3 = true,
        .HAVE_WAIT4 = true,
        .HAVE_WAITPID = true,
        .HAVE_WORKING_FORK = true,
        .HAVE_WORKING_VFORK = true,
        .HAVE_X86_SHA1_HW_SUPPORT = null,
        .HAVE__DOPRNT = null,
        .HAVE__SYSTEM_CONFIGURATION = null,
        .HAVE___FSETLOCKING = true,
        .NEED_DECLARATION_CANONICALIZE_FILE_NAME = if (target.result.isGnuLibC()) null else true,
        .NEED_DECLARATION_ERRNO = null,
        .NO_MINUS_C_MINUS_O = null,
        .PACKAGE_BUGREPORT = "",
        .PACKAGE_NAME = "",
        .PACKAGE_STRING = "",
        .PACKAGE_TARNAME = "",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = "",
        .SIZEOF_INT = target.result.cTypeByteSize(.int),
        .SIZEOF_LONG = target.result.cTypeByteSize(.long),
        .SIZEOF_LONG_LONG = target.result.cTypeByteSize(.longlong),
        .SIZEOF_SIZE_T = target.result.ptrBitWidth() / 8,
        .STACK_DIRECTION = @as(i64, -1),
        .STDC_HEADERS = true,
        .TIME_WITH_SYS_TIME = true,
        .UNSIGNED_64BIT_TYPE = .uint64_t,
        ._ALL_SOURCE = true,
        ._GNU_SOURCE = true,
        ._POSIX_PTHREAD_SEMANTICS = true,
        ._TANDEM_SOURCE = true,
        .__EXTENSIONS__ = true,
        .WORDS_BIGENDIAN = if (target.result.cpu.arch.endian() == .big) @as(i64, 1) else null,
        ._FILE_OFFSET_BITS = null,
        ._LARGE_FILES = null,
        ._MINIX = null,
        ._POSIX_1_SOURCE = null,
        ._POSIX_SOURCE = null,
        .@"const" = null,
        .@"inline" = null,
        .intptr_t = null,
        .pid_t = null,
        .ssize_t = null,
        .uintptr_t = null,
        .vfork = null,
    });

    const iberty = b.addLibrary(.{
        .linkage = .static,
        .name = "iberty",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    iberty.root_module.addConfigHeader(config_header);
    iberty.root_module.addCMacro("HAVE_CONFIG_H", "1");
    iberty.root_module.addCMacro("_GNU_SOURCE", "1");
    iberty.root_module.addIncludePath(binutils_root.path(b, "libiberty"));
    iberty.root_module.addIncludePath(binutils_root.path(b, "include"));
    iberty.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "libiberty"),
        .files = &.{
            "alloca.c",
            "argv.c",
            "bsearch_r.c",
            "concat.c",
            "cp-demangle.c",
            "cp-demint.c",
            "cplus-dem.c",
            "crc32.c",
            "d-demangle.c",
            "dwarfnames.c",
            "dyn-string.c",
            "fdmatch.c",
            "fibheap.c",
            "filedescriptor.c",
            "filename_cmp.c",
            "floatformat.c",
            "fnmatch.c",
            "fopen_unlocked.c",
            "getpwd.c",
            "getruntime.c",
            "hashtab.c",
            "hex.c",
            "lbasename.c",
            "lrealpath.c",
            "make-relative-prefix.c",
            "make-temp-file.c",
            "md5.c",
            "mempcpy.c",
            "objalloc.c",
            "obstack.c",
            "partition.c",
            "pexecute.c",
            "pex-common.c",
            "pex-one.c",
            "pex-unix.c",
            "physmem.c",
            "regex.c",
            "rust-demangle.c",
            "safe-ctype.c",
            "setproctitle.c",
            "sha1.c",
            "simple-object.c",
            "simple-object-coff.c",
            "simple-object-elf.c",
            "simple-object-mach-o.c",
            "simple-object-xcoff.c",
            "sort.c",
            "spaces.c",
            "splay-tree.c",
            "stack-limit.c",
            "strncmp.c",
            "timeval-utils.c",
            "unlink-if-ordinary.c",
            "vfork.c",
            "xasprintf.c",
            "xatexit.c",
            "xexit.c",
            "xmalloc.c",
            "xmemdup.c",
            "xstrdup.c",
            "xstrerror.c",
            "xstrndup.c",
            "xvasprintf.c",
            "vprintf-support.c",
        },
    });

    return iberty;
}

// ---------------------------------------------------------------------------
// libsframe
// ---------------------------------------------------------------------------
pub fn addLibsframe(
    b: *std.Build,
    binutils_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: CrossConfig,
) *std.Build.Step.Compile {
    const config_header = b.addConfigHeader(.{}, .{
        .HAVE_BYTESWAP_H = true,
        .HAVE_DECL_BSWAP_16 = true,
        .HAVE_DECL_BSWAP_32 = true,
        .HAVE_DECL_BSWAP_64 = true,
        .HAVE_DLFCN_H = true,
        .HAVE_ENDIAN_H = true,
        .HAVE_GETPAGESIZE = true,
        .HAVE_INTTYPES_H = true,
        .HAVE_MEMORY_H = true,
        .HAVE_MMAP = true,
        .HAVE_STDINT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_SYS_PARAM_H = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_UNISTD_H = true,
        .LT_OBJDIR = ".libs/",
        .PACKAGE = "libsframe",
        .PACKAGE_BUGREPORT = "",
        .PACKAGE_NAME = "libsframe",
        .PACKAGE_STRING = b.fmt("libsframe {}", .{config.binutils_version}),
        .PACKAGE_TARNAME = "libsframe",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = b.fmt("{}", .{config.binutils_version}),
        .STDC_HEADERS = true,
        .VERSION = b.fmt("{}", .{config.binutils_version}),
    });

    const libsframe = b.addLibrary(.{
        .linkage = .static,
        .name = "sframe",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    libsframe.root_module.addConfigHeader(config_header);
    libsframe.root_module.addIncludePath(binutils_root.path(b, "libsframe"));
    libsframe.root_module.addIncludePath(binutils_root.path(b, "include"));
    libsframe.root_module.addIncludePath(binutils_root.path(b, "libctf"));
    libsframe.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "libsframe"),
        .files = &.{
            "sframe.c",
            "sframe-dump.c",
            "sframe-error.c",
        },
    });

    return libsframe;
}

// ---------------------------------------------------------------------------
// libbfd (configured for rl78-elf)
// ---------------------------------------------------------------------------
pub const BfdResult = struct {
    bfd: *std.Build.Step.Compile,
    bfd_header: *std.Build.Step.ConfigHeader,
    bfdver_header: *std.Build.Step.ConfigHeader,
    libbfd_config_header: *std.Build.Step.ConfigHeader,
};

pub fn addLibbfd(
    b: *std.Build,
    binutils_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    iberty: *std.Build.Step.Compile,
    libsframe: *std.Build.Step.Compile,
    config: CrossConfig,
) BfdResult {
    const libbfd_config_header = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = binutils_root.path(b, "bfd/config.in") },
    }, .{
        .AC_APPLE_UNIVERSAL_BUILD = null,
        .CORE_HEADER = @as(?[]const u8, null),
        .DEFAULT_LD_Z_SEPARATE_CODE = false,
        .ENABLE_CHECKING = null,
        .ENABLE_NLS = null,
        .HAVE_CFLOCALECOPYPREFERREDLANGUAGES = null,
        .HAVE_CFPREFERENCESCOPYAPPVALUE = null,
        .HAVE_DCGETTEXT = null,
        .HAVE_DECL_ASPRINTF = true,
        .HAVE_DECL_BASENAME = target.result.isGnuLibC(),
        .HAVE_DECL_FFS = true,
        .HAVE_DECL_FOPEN64 = target.result.isGnuLibC(),
        .HAVE_DECL_FSEEKO = true,
        .HAVE_DECL_FSEEKO64 = target.result.isGnuLibC(),
        .HAVE_DECL_FTELLO = true,
        .HAVE_DECL_FTELLO64 = target.result.isGnuLibC(),
        .HAVE_DECL_STPCPY = true,
        .HAVE_DECL_STRNLEN = true,
        .HAVE_DECL_VASPRINTF = true,
        .HAVE_DECL____LC_CODEPAGE_FUNC = false,
        .HAVE_DLFCN_H = true,
        .HAVE_FCNTL = true,
        .HAVE_FCNTL_H = true,
        .HAVE_FDOPEN = true,
        .HAVE_FILENO = true,
        .HAVE_FLS = null,
        .HAVE_FOPEN64 = if (target.result.isGnuLibC()) true else null,
        .HAVE_FSEEKO = true,
        .HAVE_FSEEKO64 = if (target.result.isGnuLibC()) true else null,
        .HAVE_FTELLO = true,
        .HAVE_FTELLO64 = if (target.result.isGnuLibC()) true else null,
        .HAVE_GETGID = true,
        .HAVE_GETPAGESIZE = true,
        .HAVE_GETRLIMIT = true,
        .HAVE_GETTEXT = null,
        .HAVE_GETUID = true,
        .HAVE_HIDDEN = true,
        .HAVE_ICONV = null,
        .HAVE_INTTYPES_H = true,
        .HAVE_LWPSTATUS_T = null,
        .HAVE_LWPSTATUS_T_PR_CONTEXT = null,
        .HAVE_LWPSTATUS_T_PR_FPREG = null,
        .HAVE_LWPSTATUS_T_PR_REG = null,
        .HAVE_LWPXSTATUS_T = null,
        .HAVE_MADVISE = true,
        .HAVE_MEMORY_H = true,
        .HAVE_MMAP = true,
        .HAVE_MPROTECT = true,
        .HAVE_PRPSINFO32_T = null,
        .HAVE_PRPSINFO32_T_PR_PID = null,
        .HAVE_PRPSINFO_T = null,
        .HAVE_PRPSINFO_T_PR_PID = null,
        .HAVE_PRSTATUS32_T = null,
        .HAVE_PRSTATUS32_T_PR_WHO = null,
        .HAVE_PRSTATUS_T = null,
        .HAVE_PRSTATUS_T_PR_WHO = null,
        .HAVE_PSINFO32_T = null,
        .HAVE_PSINFO32_T_PR_PID = null,
        .HAVE_PSINFO_T = null,
        .HAVE_PSINFO_T_PR_PID = null,
        .HAVE_PSTATUS32_T = null,
        .HAVE_PSTATUS_T = null,
        .HAVE_PXSTATUS_T = null,
        .HAVE_STDINT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_ST_C_IMPL = null,
        .HAVE_SYSCONF = true,
        .HAVE_SYS_FILE_H = true,
        .HAVE_SYS_PARAM_H = true,
        .HAVE_SYS_PROCFS_H = null,
        .HAVE_SYS_RESOURCE_H = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_UNISTD_H = true,
        .HAVE_WIN32_PSTATUS_T = null,
        .HAVE_WINDOWS_H = null,
        .HAVE_ZSTD = null,
        .LT_OBJDIR = ".libs/",
        .PACKAGE = "bfd",
        .PACKAGE_BUGREPORT = "",
        .PACKAGE_NAME = "bfd",
        .PACKAGE_STRING = b.fmt("bfd {}", .{config.binutils_version}),
        .PACKAGE_TARNAME = "bfd",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = b.fmt("{}", .{config.binutils_version}),
        .SIZEOF_INT = target.result.cTypeByteSize(.int),
        .SIZEOF_LONG = target.result.cTypeByteSize(.long),
        .SIZEOF_LONG_LONG = target.result.cTypeByteSize(.longlong),
        .SIZEOF_OFF_T = @as(i64, 8),
        .SIZEOF_VOID_P = target.result.ptrBitWidth() / 8,
        .STDC_HEADERS = true,
        .TLS = ._Thread_local,
        .TRAD_HEADER = null,
        .USE_64_BIT_ARCHIVE = null,
        .USE_BINARY_FOPEN = null,
        .USE_MINGW64_LEADING_UNDERSCORES = null,
        .USE_MMAP = true,
        .USE_SECUREPLT = true,
        .VERSION = b.fmt("{}", .{config.binutils_version}),
        .WORDS_BIGENDIAN = if (target.result.cpu.arch.endian() == .big) @as(i64, 1) else null,
        ._ALL_SOURCE = true,
        ._FILE_OFFSET_BITS = null,
        ._GNU_SOURCE = true,
        ._LARGE_FILES = null,
        ._MINIX = null,
        ._POSIX_1_SOURCE = null,
        ._POSIX_PTHREAD_SEMANTICS = true,
        ._POSIX_SOURCE = null,
        ._STRUCTURED_PROC = true,
        ._TANDEM_SOURCE = true,
        .__EXTENSIONS__ = true,
    });

    const bfd_header = b.addConfigHeader(.{
        .style = .{ .autoconf_at = binutils_root.path(b, "bfd/bfd-in2.h") },
        .include_path = "bfd.h",
    }, .{
        .supports_plugins = @as(i64, 0),
        .wordsize = target.result.ptrBitWidth(),
        .bfd_default_target_size = target.result.ptrBitWidth(),
        .bfd_file_ptr = "int64_t",
        .bfd_ufile_ptr = "uint64_t",
    });

    const bfdver_header = b.addConfigHeader(.{
        .style = .{ .autoconf_at = binutils_root.path(b, "bfd/version.h") },
        .include_path = "bfdver.h",
    }, .{
        .bfd_version = @as(i64, 242000000),
        .bfd_version_package = "\"(GNU Binutils) \"",
        .bfd_version_string = "\"2.42\"",
        .report_bugs_to = "\"<https://sourceware.org/bugzilla/>\"",
    });

    // Generate elf32-target.h from elfxx-target.h using a build step
    const find_replace_exe = b.addExecutable(.{
        .name = "find-replace",
        .root_module = b.createModule(.{
            .root_source_file = config.find_replace_zig,
            .target = b.graph.host,
            .link_libc = true,
        }),
    });

    const elf32_target_h = runFindReplace(b, find_replace_exe, binutils_root.path(b, "bfd/elfxx-target.h"), "elf32-target.h", "NN", "32");
    const elf64_target_h = runFindReplace(b, find_replace_exe, binutils_root.path(b, "bfd/elfxx-target.h"), "elf64-target.h", "NN", "64");

    const bfd = b.addLibrary(.{
        .linkage = .static,
        .name = "bfd",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    bfd.root_module.addConfigHeader(libbfd_config_header);
    bfd.root_module.addCMacro("HAVE_CONFIG_H", "1");
    bfd.root_module.addCMacro("DEBUGDIR", b.fmt("\"{s}\"", .{b.pathJoin(&.{ b.install_prefix, "lib", "debug" })}));
    bfd.root_module.linkLibrary(iberty);
    bfd.root_module.linkLibrary(libsframe);
    bfd.root_module.addIncludePath(binutils_root.path(b, "bfd"));
    bfd.root_module.addIncludePath(binutils_root.path(b, "include"));
    bfd.root_module.addConfigHeader(bfd_header);
    bfd.root_module.addConfigHeader(bfdver_header);
    bfd.root_module.addIncludePath(config.include_dir); // targmatch.h
    bfd.root_module.addIncludePath(elf32_target_h.dirname());
    bfd.root_module.addIncludePath(elf64_target_h.dirname());

    // Core BFD sources
    bfd.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "bfd"),
        .files = &.{
            "archive.c",
            "bfd.c",
            "bfdio.c",
            "cache.c",
            "coff-bfd.c",
            "compress.c",
            "corefile.c",
            "elf-properties.c",
            "format.c",
            "hash.c",
            "libbfd.c",
            "linker.c",
            "merge.c",
            "opncls.c",
            "reloc.c",
            "section.c",
            "simple.c",
            "stab-syms.c",
            "stabs.c",
            "syms.c",
            "binary.c",
            "ihex.c",
            "srec.c",
            "tekhex.c",
            "verilog.c",
            "archive64.c",
            "bfdwin.c",
        },
    });

    // Target ELF vector sources
    bfd.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "bfd"),
        .files = config.bfd_elf_target_srcs,
    });
    bfd.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "bfd"),
        .files = &.{
            "elf32.c",
            // ELF common
            "elf.c",
            "elflink.c",
            "elf-attrs.c",
            "elf-strtab.c",
            "elf-eh-frame.c",
            "elf-sframe.c",
            "dwarf1.c",
            "dwarf2.c",
        },
    });

    // Generic ELF vectors (elf32_le_vec, elf32_be_vec) and elf64 support
    bfd.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "bfd"),
        .files = &.{
            "elf32-gen.c",
            "elf64.c",
            "elf64-gen.c",
        },
    });

    // Architecture file
    bfd.root_module.addCSourceFile(.{
        .file = binutils_root.path(b, b.fmt("bfd/{s}", .{config.bfd_cpu_arch_src})),
    });
    // Extra architecture files (e.g. cpu-v850_rh850.c for v850)
    for (config.bfd_extra_cpu_arch_srcs) |src| {
        bfd.root_module.addCSourceFile(.{
            .file = binutils_root.path(b, b.fmt("bfd/{s}", .{src})),
        });
    }

    // targets.c and archures.c with vector defines
    for (config.bfd_select_vectors) |vec| {
        bfd.root_module.addCMacro(b.fmt("HAVE_{s}", .{vec}), "1");
    }

    bfd.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "bfd"),
        .files = &.{
            "targets.c",
            "archures.c",
        },
        .flags = &.{
            b.fmt("-DDEFAULT_VECTOR={s}", .{config.bfd_default_vector}),
            b.fmt("-DSELECT_VECS={s}", .{config.bfd_select_vecs_str}),
            b.fmt("-DSELECT_ARCHITECTURES={s}", .{config.bfd_select_archs_str}),
        },
    });

    return .{
        .bfd = bfd,
        .bfd_header = bfd_header,
        .bfdver_header = bfdver_header,
        .libbfd_config_header = libbfd_config_header,
    };
}

// ---------------------------------------------------------------------------
// libopcodes (configured for rl78)
// ---------------------------------------------------------------------------
pub fn addLibopcodes(
    b: *std.Build,
    binutils_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    bfd_header: *std.Build.Step.ConfigHeader,
    config: CrossConfig,
) *std.Build.Step.Compile {
    const config_header = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = binutils_root.path(b, "opcodes/config.in") },
    }, .{
        .ENABLE_CHECKING = null,
        .ENABLE_NLS = null,
        .HAVE_CFLOCALECOPYPREFERREDLANGUAGES = null,
        .HAVE_CFPREFERENCESCOPYAPPVALUE = null,
        .HAVE_DCGETTEXT = null,
        .HAVE_DECL_BASENAME = target.result.isGnuLibC(),
        .HAVE_DECL_STPCPY = true,
        .HAVE_DLFCN_H = true,
        .HAVE_GETTEXT = null,
        .HAVE_ICONV = null,
        .HAVE_INTTYPES_H = true,
        .HAVE_MEMORY_H = true,
        .HAVE_SIGSETJMP = true,
        .HAVE_STDINT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_UNISTD_H = true,
        .LT_OBJDIR = ".libs/",
        .PACKAGE = "opcodes",
        .PACKAGE_BUGREPORT = "",
        .PACKAGE_NAME = "opcodes",
        .PACKAGE_STRING = b.fmt("opcodes {}", .{config.binutils_version}),
        .PACKAGE_TARNAME = "opcodes",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = b.fmt("{}", .{config.binutils_version}),
        .SIZEOF_VOID_P = target.result.ptrBitWidth() / 8,
        .STDC_HEADERS = true,
        .VERSION = b.fmt("{}", .{config.binutils_version}),
        ._ALL_SOURCE = true,
        ._GNU_SOURCE = true,
        ._MINIX = null,
        ._POSIX_1_SOURCE = null,
        ._POSIX_PTHREAD_SEMANTICS = true,
        ._POSIX_SOURCE = null,
        ._TANDEM_SOURCE = true,
        .__EXTENSIONS__ = true,
    });

    const libopcodes = b.addLibrary(.{
        .linkage = .static,
        .name = "opcodes",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    libopcodes.root_module.addConfigHeader(config_header);
    libopcodes.root_module.addCMacro("HAVE_CONFIG_H", "1");
    libopcodes.root_module.addIncludePath(binutils_root.path(b, "opcodes"));
    libopcodes.root_module.addIncludePath(binutils_root.path(b, "bfd"));
    libopcodes.root_module.addIncludePath(binutils_root.path(b, "include"));
    libopcodes.root_module.addConfigHeader(bfd_header);

    // Common opcodes sources
    libopcodes.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "opcodes"),
        .files = &.{ "dis-buf.c", "dis-init.c" },
    });

    // Target-specific opcodes sources
    libopcodes.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "opcodes"),
        .files = config.opcodes_target_srcs,
    });

    // disassemble.c with architecture define(s)
    const arch_flags = b.allocator.alloc([]const u8, 1 + config.opcodes_extra_arch_flags.len) catch @panic("OOM");
    arch_flags[0] = config.opcodes_arch_flag;
    for (config.opcodes_extra_arch_flags, 0..) |flag, i| {
        arch_flags[1 + i] = flag;
    }
    libopcodes.root_module.addCSourceFiles(.{
        .root = binutils_root.path(b, "opcodes"),
        .files = &.{"disassemble.c"},
        .flags = arch_flags,
    });

    return libopcodes;
}

fn runFindReplace(
    b: *std.Build,
    find_replace_exe: *std.Build.Step.Compile,
    input: std.Build.LazyPath,
    output_filename: []const u8,
    needle: []const u8,
    replacement: []const u8,
) std.Build.LazyPath {
    const run = b.addRunArtifact(find_replace_exe);
    run.addFileArg(input);
    const output = run.addOutputFileArg(output_filename);
    run.addArg(needle);
    run.addArg(replacement);
    return output;
}
