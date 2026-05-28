//! Shared build logic for GNU Binutils + GCC cross-compiler toolchains.
//! This package provides reusable modules; it does not build anything on its own.
//! See gcc-rl78-zig (or similar target packages) for the actual build entry point.
//! SPDX-License-Identifier: GPL-2.0-or-later

const std = @import("std");

pub const cross_config = @import("cross_config.zig");
pub const binutils_libs = @import("binutils_libs.zig");
pub const binutils_gas = @import("binutils_gas.zig");
pub const binutils_ld = @import("binutils_ld.zig");
pub const binutils_tools = @import("binutils_tools.zig");
pub const gcc_cc1 = @import("gcc_cc1.zig");
pub const gen_tools = @import("gen_tools.zig");
pub const libgcc = @import("libgcc.zig");
pub const zlib = @import("zlib.zig");

pub const CrossConfig = cross_config.CrossConfig;
pub const Libs = cross_config.Libs;

/// Convenience: build the full toolchain from a CrossConfig.
pub fn buildToolchain(
    b: *std.Build,
    binutils_src: *std.Build.Dependency,
    gcc_src: *std.Build.Dependency,
    host_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: CrossConfig,
) void {
    // Resolve binutils source root: use override if provided, else upstream
    const binutils_root = if (config.binutils_source_root_override) |ovr|
        ovr
    else
        binutils_src.path(".");

    // From-source zlib (optional): linked into binutils + cc1 so the toolchain
    // can target a host without a system libz. Built for the host target.
    const zlib_lib: ?*std.Build.Step.Compile = if (config.zlib_src) |dep|
        zlib.addZlib(b, dep.path("."), host_target, optimize)
    else
        null;

    // Build libraries
    const iberty = binutils_libs.addLibiberty(b, binutils_root, host_target, optimize);
    const libsframe = binutils_libs.addLibsframe(b, binutils_root, host_target, optimize, config);
    const bfd_result = binutils_libs.addLibbfd(b, binutils_root, host_target, optimize, iberty, libsframe, config);
    const libopcodes = binutils_libs.addLibopcodes(b, binutils_root, host_target, optimize, bfd_result.bfd_header, config);

    const libs = Libs{
        .iberty = iberty,
        .libsframe = libsframe,
        .bfd = bfd_result.bfd,
        .bfd_header = bfd_result.bfd_header,
        .bfdver_header = bfd_result.bfdver_header,
        .libbfd_config_header = bfd_result.libbfd_config_header,
        .libopcodes = libopcodes,
        .zlib = zlib_lib,
    };

    // Build binutils executables
    const gas = binutils_gas.addGas(b, binutils_root, host_target, optimize, libs, config);
    const ld = binutils_ld.addLd(b, binutils_root, host_target, optimize, libs, config);
    const ar = binutils_tools.addTools(b, binutils_root, host_target, optimize, libs, config);

    const gcc_root = if (config.gcc_source_root_override) |ovr| ovr else gcc_src.path(".");

    // Build-time generation is opt-in per target: a target that supplies the
    // generator inputs (gtyp_input_list) generates everything from source and
    // needs no vendored generated/ dir. Targets without it fall back to the
    // vendored config.generated_dir.
    var gen_dir: ?std.Build.LazyPath = null;
    var gt_dir: ?std.Build.LazyPath = null;
    if (config.gtyp_input_list != null) {
        const host_libcpp = gcc_cc1.addLibcpp(b, gcc_src, host_target, optimize, config);
        const generated = gen_tools.addGenerated(b, gcc_root, host_target, optimize, iberty, host_libcpp, config);
        gen_dir = generated.dir;
        gt_dir = generated.gt_dir;
        // When a vendored dir is still present, register a regression check.
        if (config.generated_dir) |oracle| {
            gen_tools.addVerify(b, generated, oracle, &.{});
        }

        // libgcc (post-install): compile target runtime with the cross compiler.
        // Exposed as `zig build libgcc` since it must run after the install step.
        if (config.libgcc_tm_includes.len != 0) {
            _ = libgcc.addLibgcc(b, gcc_root, generated.dir, config);
        }
    }

    // Build GCC cc1 and driver
    const support_libs = cross_config.SupportLibs{ .zlib = zlib_lib };
    _ = gcc_cc1.addCc1(b, gcc_src, host_target, optimize, iberty, config, gen_dir, gt_dir, support_libs);
    _ = gcc_cc1.addGccDriver(b, gcc_src, host_target, optimize, iberty, config, gen_dir);

    // Build LTO plugin (shared library loaded by the linker)
    const lto_config = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = gcc_root.path(b, "lto-plugin/config.h.in") },
    }, .{
        .HAVE_DLFCN_H = true,
        .HAVE_INTTYPES_H = true,
        .HAVE_MEMORY_H = true,
        .HAVE_STDINT_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_SYS_WAIT_H = true,
        .HAVE_UNISTD_H = true,
        .HAVE_PTHREAD_LOCKING = true,
        .LT_OBJDIR = ".libs/",
        .PACKAGE = "lto-plugin",
        .PACKAGE_BUGREPORT = "",
        .PACKAGE_NAME = "lto-plugin",
        .PACKAGE_STRING = "lto-plugin 0.1",
        .PACKAGE_TARNAME = "lto-plugin",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = "0.1",
        .STDC_HEADERS = true,
        .VERSION = "0.1",
        ._ALL_SOURCE = true,
        ._GNU_SOURCE = true,
        ._POSIX_PTHREAD_SEMANTICS = true,
        ._TANDEM_SOURCE = true,
        .__EXTENSIONS__ = true,
        ._FILE_OFFSET_BITS = null,
        ._LARGE_FILES = null,
        ._MINIX = null,
        ._POSIX_1_SOURCE = null,
        ._POSIX_SOURCE = null,
        ._UINT64_T = null,
        .int64_t = null,
        .uint64_t = null,
    });
    const lto_plugin = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "lto_plugin",
        .root_module = b.createModule(.{
            .target = host_target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    lto_plugin.root_module.addConfigHeader(lto_config);
    lto_plugin.root_module.addCSourceFiles(.{
        .root = gcc_root.path(b, "lto-plugin"),
        .files = &.{"lto-plugin.c"},
        .flags = &.{
            "-DHAVE_CONFIG_H",
            b.fmt("-DBASE_VERSION=\"{s}\"", .{config.gcc_version}),
        },
    });
    lto_plugin.root_module.addIncludePath(gcc_root.path(b, "include"));
    lto_plugin.root_module.addIncludePath(binutils_root.path(b, "include"));
    // Install to libexec/gcc/<target>/<version>/
    const lto_install = b.addInstallArtifact(lto_plugin, .{
        .dest_dir = .{ .override = .{
            .custom = b.fmt("libexec/gcc/{s}/{s}", .{ config.target_canonical, config.gcc_version }),
        } },
    });
    b.getInstallStep().dependOn(&lto_install.step);
    // Also install to lib/gcc/<target>/<version>/ (some drivers look here)
    const lto_install2 = b.addInstallArtifact(lto_plugin, .{
        .dest_dir = .{ .override = .{
            .custom = b.fmt("lib/gcc/{s}/{s}", .{ config.target_canonical, config.gcc_version }),
        } },
    });
    b.getInstallStep().dependOn(&lto_install2.step);

    // Install tooldir layout: <target_canonical>/bin/{as,ld,ar}
    // The GCC driver searches for assembler/linker here via TOOLDIR_BASE_PREFIX.
    const tooldir = b.fmt("{s}/bin", .{config.target_canonical});
    inline for (.{
        .{ gas, "as" },
        .{ ld, "ld" },
        .{ ar, "ar" },
    }) |entry| {
        const install = b.addInstallArtifact(entry[0], .{
            .dest_dir = .{ .override = .{ .custom = tooldir } },
            .dest_sub_path = entry[1],
        });
        b.getInstallStep().dependOn(&install.step);
    }

    const lib_gcc_dir = b.fmt("lib/gcc/{s}/{s}", .{ config.target_canonical, config.gcc_version });

    // Install GCC internal headers (stdarg.h, stddef.h, etc.) to
    // lib/gcc/<target>/<version>/include/ so the driver finds them
    // via -print-file-name=include.
    const include_dir = b.fmt("{s}/include", .{lib_gcc_dir});
    const ginclude_headers = [_][]const u8{
        "stdarg.h",    "stddef.h",      "stdbool.h",     "stdint-gcc.h",
        "stdatomic.h", "stdalign.h",    "stdnoreturn.h", "float.h",
        "iso646.h",    "stdfix.h",      "varargs.h",     "stdckdint.h",
        "tgmath.h",    "stdint-wrap.h",
    };
    for (ginclude_headers) |hdr| {
        const install_hdr = b.addInstallFile(
            gcc_src.path(b.fmt("gcc/ginclude/{s}", .{hdr})),
            b.fmt("{s}/{s}", .{ include_dir, hdr }),
        );
        b.getInstallStep().dependOn(&install_hdr.step);
    }

    // Install glimits.h as limits.h (GCC renames it during install)
    const install_limits = b.addInstallFile(
        gcc_src.path("gcc/glimits.h"),
        b.fmt("{s}/limits.h", .{include_dir}),
    );
    b.getInstallStep().dependOn(&install_limits.step);

    // Install stdint-gcc.h as stdint.h for freestanding (no newlib/libc)
    const install_stdint = b.addInstallFile(
        gcc_src.path("gcc/ginclude/stdint-gcc.h"),
        b.fmt("{s}/stdint.h", .{include_dir}),
    );
    b.getInstallStep().dependOn(&install_stdint.step);
}

pub fn build(b: *std.Build) void {
    _ = b;
}
