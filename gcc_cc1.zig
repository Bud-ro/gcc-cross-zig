//! GCC cc1 and driver build.
//! SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const cross_config = @import("cross_config.zig");
const CrossConfig = cross_config.CrossConfig;

// ---------------------------------------------------------------------------
// libdecnumber (decimal floating point library)
// ---------------------------------------------------------------------------
pub fn addLibdecnumber(
    b: *std.Build,
    gcc_src: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: CrossConfig,
) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "decnumber",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const config_path: std.Build.LazyPath = config.libdecnumber_config_dir;

    lib.root_module.addCSourceFiles(.{
        .root = gcc_src.path("libdecnumber"),
        .files = &.{
            "decContext.c",
            "decNumber.c",
            "dpd/decimal32.c",
            "dpd/decimal64.c",
            "dpd/decimal128.c",
        },
        .flags = &.{
            "-DHAVE_CONFIG_H",
        },
    });

    lib.root_module.addIncludePath(config_path);
    lib.root_module.addIncludePath(gcc_src.path("libdecnumber"));
    lib.root_module.addIncludePath(gcc_src.path("libdecnumber/dpd"));

    return lib;
}

// ---------------------------------------------------------------------------
// libcpp (C preprocessor library)
// ---------------------------------------------------------------------------
pub fn addLibcpp(
    b: *std.Build,
    gcc_src: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: CrossConfig,
) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "cpp",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    const config_path: std.Build.LazyPath = config.libcpp_config_dir;

    lib.root_module.addCSourceFiles(.{
        .root = gcc_src.path("libcpp"),
        .files = &.{
            "charset.cc",
            "directives.cc",
            "errors.cc",
            "expr.cc",
            "files.cc",
            "identifiers.cc",
            "init.cc",
            "lex.cc",
            "line-map.cc",
            "macro.cc",
            "mkdeps.cc",
            "pch.cc",
            "symtab.cc",
            "traditional.cc",
        },
        .flags = &.{
            "-DHAVE_CONFIG_H",
            "-Wno-narrowing",
        },
    });

    lib.root_module.addIncludePath(config_path);
    lib.root_module.addIncludePath(gcc_src.path("libcpp"));
    lib.root_module.addIncludePath(gcc_src.path("libcpp/include"));
    lib.root_module.addIncludePath(gcc_src.path("include"));

    return lib;
}

// ---------------------------------------------------------------------------
// libcody (C++ modules protocol library)
// ---------------------------------------------------------------------------
pub fn addLibcody(
    b: *std.Build,
    gcc_src: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: CrossConfig,
) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "cody",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    lib.root_module.addCSourceFiles(.{
        .root = gcc_src.path("libcody"),
        .files = &.{
            "buffer.cc",
            "client.cc",
            "fatal.cc",
            "netclient.cc",
            "netserver.cc",
            "packet.cc",
            "resolver.cc",
            "server.cc",
        },
        .flags = &.{
            "-DHAVE_CONFIG_H",
            "-DSRCDIR=\".\"",
            "-include",
            config.libcody_config.getPath2(b, null),
        },
    });

    lib.root_module.addIncludePath(gcc_src.path("libcody"));

    return lib;
}

// ---------------------------------------------------------------------------
// cc1 (C compiler proper)
// ---------------------------------------------------------------------------
pub fn addCc1(
    b: *std.Build,
    gcc_src: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    iberty: *std.Build.Step.Compile,
    config: CrossConfig,
    // When set, generated files come from these build-time dirs instead of the
    // vendored config.generated_dir. gt_dir holds the gt-*.h headers.
    gen_dir: ?std.Build.LazyPath,
    gt_dir: ?std.Build.LazyPath,
) *std.Build.Step.Compile {
    const libdecnumber = addLibdecnumber(b, gcc_src, target, optimize, config);
    const libcpp = addLibcpp(b, gcc_src, target, optimize, config);
    const libcody = addLibcody(b, gcc_src, target, optimize, config);

    const exe = b.addExecutable(.{
        .name = "cc1",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    // Link our support libraries
    exe.root_module.linkLibrary(libdecnumber);
    exe.root_module.linkLibrary(libcpp);
    exe.root_module.linkLibrary(libcody);
    exe.root_module.linkLibrary(iberty);

    // System math/compression libraries
    exe.root_module.linkSystemLibrary("gmp", .{});
    exe.root_module.linkSystemLibrary("mpfr", .{});
    exe.root_module.linkSystemLibrary("mpc", .{});
    exe.root_module.linkSystemLibrary("z", .{});

    // Paths for vendored config and generated files (from consumer repo)
    const config_path: std.Build.LazyPath = config.config_dir;
    const generated_path: std.Build.LazyPath = gen_dir orelse config.generated_dir orelse @panic("no generated_dir and no build-time generation");

    // Resolve GCC source root: use override if provided, else upstream
    const gcc_root = if (config.gcc_source_root_override) |ovr|
        ovr
    else
        gcc_src.path(".");

    // Include paths (order matters!)
    // Build dir (generated/ and config/ dirs)
    exe.root_module.addIncludePath(generated_path);
    if (gt_dir) |d| exe.root_module.addIncludePath(d); // gt-*.h
    exe.root_module.addIncludePath(config_path);
    // Extra include dirs from consumer (patched headers shadow upstream)
    for (config.gcc_extra_include_dirs) |dir| {
        exe.root_module.addIncludePath(dir);
    }
    // gcc source root (possibly patched)
    exe.root_module.addIncludePath(gcc_root.path(b, "gcc"));
    // shared includes
    exe.root_module.addIncludePath(gcc_root.path(b, "include"));
    // libcpp headers
    exe.root_module.addIncludePath(gcc_root.path(b, "libcpp/include"));
    // libcody
    exe.root_module.addIncludePath(gcc_root.path(b, "libcody"));
    // libdecnumber (source headers + config with gstdint.h)
    exe.root_module.addIncludePath(gcc_root.path(b, "libdecnumber"));
    exe.root_module.addIncludePath(gcc_root.path(b, "libdecnumber/dpd"));
    exe.root_module.addIncludePath(config.libdecnumber_config_dir);
    // libbacktrace
    exe.root_module.addIncludePath(gcc_root.path(b, "libbacktrace"));

    // Common C++ flags for GCC source
    const common_flags: []const []const u8 = &.{
        "-DHAVE_CONFIG_H",
        "-DIN_GCC",
        b.fmt("-DTARGET_MACHINE=\"{s}\"", .{config.target_canonical}),
        b.fmt("-DBASEVER=\"{s}\"", .{config.gcc_version}),
        b.fmt("-DDATESTAMP=\"{s}\"", .{config.gcc_datestamp}),
        "-DDEVPHASE=\"\"",
        "-DPKGVERSION=\"(GCC) \"",
        "-DBUGURL=\"<https://gcc.gnu.org/bugs/>\"",
        "-DPREFIX=\"/usr/local\"",
        "-DSTANDARD_EXEC_PREFIX=\"/usr/local/lib/gcc/\"",
        "-DCONFIGURE_SPECS=\"\"",
        b.fmt("-DTARGET_NAME=\"{s}\"", .{config.target_canonical}),
        // Disable warnings that would be errors in GCC's own code
        "-Wno-narrowing",
        "-Wno-format",
        "-Wno-nontrivial-memaccess",
        "-Wno-unknown-warning-option",
        "-fno-exceptions",
        "-fno-rtti",
    };

    // -----------------------------------------------------------------
    // OBJS: Language-independent backend object files (~450 files)
    // From gcc/Makefile.in OBJS = ...
    // -----------------------------------------------------------------
    if (config.gcc_exclude_objs.len == 0) {
        exe.root_module.addCSourceFiles(.{
            .root = gcc_root.path(b, "gcc"),
            .files = &objs_files,
            .flags = common_flags,
        });
    } else {
        const filtered = filterFiles(b, &objs_files, config.gcc_exclude_objs);
        exe.root_module.addCSourceFiles(.{
            .root = gcc_root.path(b, "gcc"),
            .files = filtered,
            .flags = common_flags,
        });
    }

    // -----------------------------------------------------------------
    // Generated files from our vendored directory
    // -----------------------------------------------------------------
    exe.root_module.addCSourceFiles(.{
        .root = generated_path,
        .files = &generated_files,
        .flags = common_flags,
    });

    // -----------------------------------------------------------------
    // OBJS-libcommon: common library objects
    // -----------------------------------------------------------------
    exe.root_module.addCSourceFiles(.{
        .root = gcc_root.path(b, "gcc"),
        .files = &libcommon_files,
        .flags = common_flags,
    });

    // -----------------------------------------------------------------
    // OBJS-libcommon-target: target-dependent common objects
    // -----------------------------------------------------------------
    if (config.gcc_common_out_file.len > 0) {
        exe.root_module.addCSourceFile(.{
            .file = gcc_root.path(b, b.fmt("gcc/{s}", .{config.gcc_common_out_file})),
            .flags = common_flags,
        });
    }
    if (config.gcc_exclude_objs.len == 0) {
        exe.root_module.addCSourceFiles(.{
            .root = gcc_root.path(b, "gcc"),
            .files = &libcommon_target_files,
            .flags = common_flags,
        });
    } else {
        const filtered_common = filterFiles(b, &libcommon_target_files, config.gcc_exclude_objs);
        exe.root_module.addCSourceFiles(.{
            .root = gcc_root.path(b, "gcc"),
            .files = filtered_common,
            .flags = common_flags,
        });
    }

    // -----------------------------------------------------------------
    // ANALYZER_OBJS: static analyzer
    // -----------------------------------------------------------------
    exe.root_module.addCSourceFiles(.{
        .root = gcc_root.path(b, "gcc"),
        .files = &analyzer_files,
        .flags = common_flags,
    });

    // -----------------------------------------------------------------
    // C frontend: C_OBJS
    // c/c-lang.o c-family/stub-objc.o + C_AND_OBJC_OBJS + C_COMMON_OBJS
    // -----------------------------------------------------------------
    const c_frontend_flags: []const []const u8 = &.{
        "-DHAVE_CONFIG_H",
        "-DIN_GCC",
        b.fmt("-DTARGET_MACHINE=\"{s}\"", .{config.target_canonical}),
        b.fmt("-DBASEVER=\"{s}\"", .{config.gcc_version}),
        b.fmt("-DDATESTAMP=\"{s}\"", .{config.gcc_datestamp}),
        "-DDEVPHASE=\"\"",
        "-DPKGVERSION=\"(GCC) \"",
        "-DBUGURL=\"<https://gcc.gnu.org/bugs/>\"",
        "-DPREFIX=\"/usr/local\"",
        "-DSTANDARD_EXEC_PREFIX=\"/usr/local/lib/gcc/\"",
        "-DCONFIGURE_SPECS=\"\"",
        b.fmt("-DTARGET_NAME=\"{s}\"", .{config.target_canonical}),
        "-Wno-narrowing",
        "-Wno-format",
        "-Wno-nontrivial-memaccess",
        "-Wno-unknown-warning-option",
        "-fno-exceptions",
        "-fno-rtti",
        "-DIN_GCC_FRONTEND",
    };

    if (config.gcc_exclude_frontend_srcs.len == 0) {
        exe.root_module.addCSourceFiles(.{
            .root = gcc_root.path(b, "gcc"),
            .files = &c_frontend_files,
            .flags = c_frontend_flags,
        });
    } else {
        const filtered = filterFiles(b, &c_frontend_files, config.gcc_exclude_frontend_srcs);
        exe.root_module.addCSourceFiles(.{
            .root = gcc_root.path(b, "gcc"),
            .files = filtered,
            .flags = c_frontend_flags,
        });
    }

    // Extra frontend source files from consumer
    for (config.gcc_extra_frontend_source_files) |extra| {
        const merged_flags = mergeFlags(b, c_frontend_flags, extra.flags);
        exe.root_module.addCSourceFile(.{
            .file = extra.file,
            .flags = merged_flags,
        });
    }

    // -----------------------------------------------------------------
    // Target-specific files
    // -----------------------------------------------------------------
    if (config.gcc_exclude_target_srcs.len == 0) {
        exe.root_module.addCSourceFiles(.{
            .root = gcc_root.path(b, "gcc"),
            .files = config.gcc_target_srcs,
            .flags = common_flags,
        });
    } else {
        const filtered = filterFiles(b, config.gcc_target_srcs, config.gcc_exclude_target_srcs);
        exe.root_module.addCSourceFiles(.{
            .root = gcc_root.path(b, "gcc"),
            .files = filtered,
            .flags = common_flags,
        });
    }

    // Extra source files from consumer (patched replacements or new files)
    for (config.gcc_extra_source_files) |extra| {
        const merged_flags = mergeFlags(b, common_flags, extra.flags);
        exe.root_module.addCSourceFile(.{
            .file = extra.file,
            .flags = merged_flags,
        });
    }

    // -----------------------------------------------------------------
    // cc1-checksum (from generated)
    // -----------------------------------------------------------------
    exe.root_module.addCSourceFiles(.{
        .root = generated_path,
        .files = &.{"cc1-checksum.cc"},
        .flags = common_flags,
    });

    // -----------------------------------------------------------------
    // main.o -- the cc1 entry point is main() in gcc/main.cc
    // -----------------------------------------------------------------
    exe.root_module.addCSourceFiles(.{
        .root = gcc_root.path(b, "gcc"),
        .files = &.{"main.cc"},
        .flags = common_flags,
    });

    // -----------------------------------------------------------------
    // Backtrace stub (replaces libbacktrace)
    // -----------------------------------------------------------------
    exe.root_module.addCSourceFile(.{
        .file = config.backtrace_stub,
    });

    // Install cc1 into the standard GCC libexec path so the driver finds it
    const cc1_install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{
            .custom = b.fmt("libexec/gcc/{s}/{s}", .{ config.target_canonical, config.gcc_version }),
        } },
    });
    b.getInstallStep().dependOn(&cc1_install.step);

    return exe;
}

// ---------------------------------------------------------------------------
// GCC driver (xgcc)
// ---------------------------------------------------------------------------
pub fn addGccDriver(
    b: *std.Build,
    gcc_src: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    iberty: *std.Build.Step.Compile,
    config: CrossConfig,
    gen_dir: ?std.Build.LazyPath,
) *std.Build.Step.Compile {
    const libcpp = addLibcpp(b, gcc_src, target, optimize, config);
    const libcody = addLibcody(b, gcc_src, target, optimize, config);

    const exe = b.addExecutable(.{
        .name = b.fmt("{s}-gcc", .{config.target_triple}),
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    exe.root_module.linkLibrary(iberty);
    exe.root_module.linkLibrary(libcpp);
    exe.root_module.linkLibrary(libcody);

    // Paths (from consumer repo)
    const config_path: std.Build.LazyPath = config.config_dir;
    const generated_path: std.Build.LazyPath = gen_dir orelse config.generated_dir orelse @panic("no generated_dir and no build-time generation");

    exe.root_module.addIncludePath(generated_path);
    exe.root_module.addIncludePath(config_path);
    // Driver does NOT get extra include dirs -- those contain patched headers
    // (tree.h, output.h) that reference cc1-only symbols. The driver only
    // needs the upstream headers.
    exe.root_module.addIncludePath(gcc_src.path("gcc"));
    exe.root_module.addIncludePath(gcc_src.path("include"));
    exe.root_module.addIncludePath(gcc_src.path("libcpp/include"));
    exe.root_module.addIncludePath(gcc_src.path("libcody"));
    exe.root_module.addIncludePath(gcc_src.path("libbacktrace"));
    exe.root_module.addIncludePath(gcc_src.path("libdecnumber"));
    exe.root_module.addIncludePath(gcc_src.path("libdecnumber/dpd"));
    exe.root_module.addIncludePath(config.libdecnumber_config_dir);

    const driver_flags: []const []const u8 = &.{
        "-DHAVE_CONFIG_H",
        "-DIN_GCC",
        b.fmt("-DTARGET_MACHINE=\"{s}\"", .{config.target_canonical}),
        b.fmt("-DBASEVER=\"{s}\"", .{config.gcc_version}),
        b.fmt("-DDATESTAMP=\"{s}\"", .{config.gcc_datestamp}),
        "-DDEVPHASE=\"\"",
        "-DPKGVERSION=\"(GCC) \"",
        "-DBUGURL=\"<https://gcc.gnu.org/bugs/>\"",
        "-DPREFIX=\"/usr/local\"",
        "-DSTANDARD_STARTFILE_PREFIX=\"\"",
        "-DSTANDARD_EXEC_PREFIX=\"/usr/local/lib/gcc/\"",
        "-DSTANDARD_LIBEXEC_PREFIX=\"/usr/local/libexec/gcc/\"",
        b.fmt("-DDEFAULT_TARGET_VERSION=\"{s}\"", .{config.gcc_version}),
        b.fmt("-DDEFAULT_TARGET_MACHINE=\"{s}\"", .{config.target_canonical}),
        b.fmt("-DDEFAULT_REAL_TARGET_MACHINE=\"{s}\"", .{config.target_canonical}),
        "-DTOOLDIR_BASE_PREFIX=\"../../../../\"",
        "-DSTANDARD_BINDIR_PREFIX=\"/usr/local/bin/\"",
        "-DACCEL_DIR_SUFFIX=\"\"",
        "-DCONFIGURE_SPECS=\"\"",
        b.fmt("-DTARGET_NAME=\"{s}\"", .{config.target_canonical}),
        "-Wno-narrowing",
        "-Wno-nontrivial-memaccess",
        "-Wno-unknown-warning-option",
        "-fno-exceptions",
        "-fno-rtti",
    };

    // GCC_OBJS: gcc.o gcc-main.o ggc-none.o gcc-urlifier.o
    exe.root_module.addCSourceFiles(.{
        .root = gcc_src.path("gcc"),
        .files = &.{
            "gcc.cc",
            "gcc-main.cc",
            "ggc-none.cc",
            "gcc-urlifier.cc",
        },
        .flags = driver_flags,
    });

    // Driver also needs some libcommon objects
    exe.root_module.addCSourceFiles(.{
        .root = gcc_src.path("gcc"),
        .files = &libcommon_files,
        .flags = driver_flags,
    });

    // And libcommon-target objects (driver always uses upstream)
    if (config.gcc_common_out_file.len > 0) {
        exe.root_module.addCSourceFile(.{
            .file = gcc_src.path(b.fmt("gcc/{s}", .{config.gcc_common_out_file})),
            .flags = driver_flags,
        });
    }
    // Driver always uses upstream libcommon_target files (no filtering).
    // The patched changes to opts.cc etc. are cc1-only; the driver doesn't
    // need target-specific patches.
    exe.root_module.addCSourceFiles(.{
        .root = gcc_src.path("gcc"),
        .files = &libcommon_target_files,
        .flags = driver_flags,
    });

    // Generated options files
    exe.root_module.addCSourceFiles(.{
        .root = generated_path,
        .files = &.{
            "options.cc",
            "options-urls.cc",
        },
        .flags = driver_flags,
    });

    // c/gccspec.o for the C compiler driver (NOT cppspec.cc which is for cpp)
    exe.root_module.addCSourceFiles(.{
        .root = gcc_src.path("gcc"),
        .files = &.{
            "c/gccspec.cc",
        },
        .flags = driver_flags,
    });

    // Additional files needed by driver (in OBJS-libcommon-target in Makefile
    // but omitted from our shared list to avoid cc1 duplicates)
    exe.root_module.addCSourceFiles(.{
        .root = gcc_src.path("gcc"),
        .files = &.{
            "spellcheck.cc",
        },
        .flags = driver_flags,
    });

    // Note: the driver uses upstream libcommon_target files only.
    // Patched source files (gcc_extra_source_files) are cc1-only.
    // The driver's opts.cc changes are opt-level defaults which
    // don't affect the driver's behavior.

    // Backtrace stub (replaces libbacktrace)
    exe.root_module.addCSourceFile(.{
        .file = config.backtrace_stub,
    });

    b.installArtifact(exe);

    return exe;
}

// =========================================================================
// Helpers
// =========================================================================

/// Return a filtered copy of `files` with any entries present in `excludes` removed.
fn filterFiles(
    b: *std.Build,
    files: []const []const u8,
    excludes: []const []const u8,
) []const []const u8 {
    const gpa = b.allocator;
    var buf = gpa.alloc([]const u8, files.len) catch @panic("OOM");
    var count: usize = 0;
    for (files) |f| {
        var excluded = false;
        for (excludes) |ex| {
            if (std.mem.eql(u8, f, ex)) {
                excluded = true;
                break;
            }
        }
        if (!excluded) {
            buf[count] = f;
            count += 1;
        }
    }
    return buf[0..count];
}

/// Concatenate two flag slices.
fn mergeFlags(
    b: *std.Build,
    base: []const []const u8,
    extra: []const []const u8,
) []const []const u8 {
    if (extra.len == 0) return base;
    const merged = b.allocator.alloc([]const u8, base.len + extra.len) catch @panic("OOM");
    @memcpy(merged[0..base.len], base);
    @memcpy(merged[base.len..], extra);
    return merged;
}

// =========================================================================
// File lists
// =========================================================================

// OBJS from gcc/Makefile.in -- language-independent backend
const objs_files = [_][]const u8{
    "ggc-page.cc",
    "adjust-alignment.cc",
    "alias.cc",
    "alloc-pool.cc",
    "auto-inc-dec.cc",
    "auto-profile.cc",
    "bb-reorder.cc",
    "bitmap.cc",
    "builtins.cc",
    "caller-save.cc",
    "calls.cc",
    "ccmp.cc",
    "cfg.cc",
    "cfganal.cc",
    "cfgbuild.cc",
    "cfgcleanup.cc",
    "cfgexpand.cc",
    "cfghooks.cc",
    "cfgloop.cc",
    "cfgloopanal.cc",
    "cfgloopmanip.cc",
    "cfgrtl.cc",
    "ctfc.cc",
    "ctfout.cc",
    "btfout.cc",
    "symtab.cc",
    "symtab-thunks.cc",
    "symtab-clones.cc",
    "cgraph.cc",
    "cgraphbuild.cc",
    "cgraphunit.cc",
    "cgraphclones.cc",
    "combine.cc",
    "combine-stack-adj.cc",
    "compare-elim.cc",
    "context.cc",
    "convert.cc",
    "coroutine-passes.cc",
    "coverage.cc",
    "cppbuiltin.cc",
    "cppdefault.cc",
    "cprop.cc",
    "cse.cc",
    "cselib.cc",
    "data-streamer.cc",
    "data-streamer-in.cc",
    "data-streamer-out.cc",
    "dbgcnt.cc",
    "dce.cc",
    "ddg.cc",
    "debug.cc",
    "df-core.cc",
    "df-problems.cc",
    "df-scan.cc",
    "dfp.cc",
    "digraph.cc",
    "dojump.cc",
    "dominance.cc",
    "domwalk.cc",
    "double-int.cc",
    "dse.cc",
    "dumpfile.cc",
    "dwarf2asm.cc",
    "dwarf2cfi.cc",
    "dwarf2ctf.cc",
    "dwarf2out.cc",
    "early-remat.cc",
    "emit-rtl.cc",
    "et-forest.cc",
    "except.cc",
    "explow.cc",
    "expmed.cc",
    "expr.cc",
    "fibonacci_heap.cc",
    "file-prefix-map.cc",
    "final.cc",
    "fixed-value.cc",
    "fold-const.cc",
    "fold-const-call.cc",
    "fold-mem-offsets.cc",
    "function.cc",
    "function-abi.cc",
    "function-tests.cc",
    "fwprop.cc",
    "gcc-rich-location.cc",
    "gcc-urlifier.cc",
    "gcse.cc",
    "gcse-common.cc",
    "ggc-common.cc",
    "ggc-tests.cc",
    "gimple.cc",
    "gimple-array-bounds.cc",
    "gimple-builder.cc",
    "gimple-expr.cc",
    "gimple-if-to-switch.cc",
    "gimple-iterator.cc",
    "gimple-fold.cc",
    "gimple-harden-conditionals.cc",
    "gimple-harden-control-flow.cc",
    "gimple-laddress.cc",
    "gimple-loop-interchange.cc",
    "gimple-loop-jam.cc",
    "gimple-loop-versioning.cc",
    "gimple-low.cc",
    "gimple-lower-bitint.cc",
    "gimple-match-exports.cc",
    "gimple-predicate-analysis.cc",
    "gimple-pretty-print.cc",
    "gimple-range.cc",
    "gimple-range-cache.cc",
    "gimple-range-edge.cc",
    "gimple-range-fold.cc",
    "gimple-range-gori.cc",
    "gimple-range-infer.cc",
    "gimple-range-op.cc",
    "gimple-range-phi.cc",
    "gimple-range-trace.cc",
    "gimple-ssa-backprop.cc",
    "gimple-ssa-isolate-paths.cc",
    "gimple-ssa-nonnull-compare.cc",
    "gimple-ssa-sccopy.cc",
    "gimple-ssa-split-paths.cc",
    "gimple-ssa-store-merging.cc",
    "gimple-ssa-strength-reduction.cc",
    "gimple-ssa-sprintf.cc",
    "gimple-ssa-warn-access.cc",
    "gimple-ssa-warn-alloca.cc",
    "gimple-ssa-warn-restrict.cc",
    "gimple-streamer-in.cc",
    "gimple-streamer-out.cc",
    "gimple-walk.cc",
    "gimple-warn-recursion.cc",
    "gimplify.cc",
    "gimplify-me.cc",
    "godump.cc",
    "graph.cc",
    "graphds.cc",
    "graphviz.cc",
    "graphite.cc",
    "graphite-isl-ast-to-gimple.cc",
    "graphite-dependences.cc",
    "graphite-optimize-isl.cc",
    "graphite-poly.cc",
    "graphite-scop-detection.cc",
    "graphite-sese-to-poly.cc",
    "haifa-sched.cc",
    "hash-map-tests.cc",
    "hash-set-tests.cc",
    "hw-doloop.cc",
    "hwint.cc",
    "ifcvt.cc",
    "ree.cc",
    "inchash.cc",
    "incpath.cc",
    "init-regs.cc",
    "internal-fn.cc",
    "ipa-cp.cc",
    "ipa-sra.cc",
    "ipa-devirt.cc",
    "ipa-fnsummary.cc",
    "ipa-polymorphic-call.cc",
    "ipa-split.cc",
    "ipa-inline.cc",
    "ipa-comdats.cc",
    "ipa-free-lang-data.cc",
    "ipa-visibility.cc",
    "ipa-inline-analysis.cc",
    "ipa-inline-transform.cc",
    "ipa-modref.cc",
    "ipa-modref-tree.cc",
    "ipa-predicate.cc",
    "ipa-profile.cc",
    "ipa-prop.cc",
    "ipa-param-manipulation.cc",
    "ipa-pure-const.cc",
    "ipa-icf.cc",
    "ipa-icf-gimple.cc",
    "ipa-reference.cc",
    "ipa-ref.cc",
    "ipa-utils.cc",
    "ipa-strub.cc",
    "ipa.cc",
    "ira.cc",
    "ira-build.cc",
    "ira-costs.cc",
    "ira-conflicts.cc",
    "ira-color.cc",
    "ira-emit.cc",
    "ira-lives.cc",
    "jump.cc",
    "langhooks.cc",
    "lcm.cc",
    "lists.cc",
    "loop-doloop.cc",
    "loop-init.cc",
    "loop-invariant.cc",
    "loop-iv.cc",
    "loop-unroll.cc",
    "lower-subreg.cc",
    "lra.cc",
    "lra-assigns.cc",
    "lra-coalesce.cc",
    "lra-constraints.cc",
    "lra-eliminations.cc",
    "lra-lives.cc",
    "lra-remat.cc",
    "lra-spills.cc",
    "lto-cgraph.cc",
    "lto-streamer.cc",
    "lto-streamer-in.cc",
    "lto-streamer-out.cc",
    "lto-section-in.cc",
    "lto-section-out.cc",
    "lto-opts.cc",
    "lto-compress.cc",
    "mcf.cc",
    "mode-switching.cc",
    "modulo-sched.cc",
    "multiple_target.cc",
    "omp-offload.cc",
    "omp-expand.cc",
    "omp-general.cc",
    "omp-low.cc",
    "omp-oacc-kernels-decompose.cc",
    "omp-oacc-neuter-broadcast.cc",
    "omp-simd-clone.cc",
    "opt-problem.cc",
    "optabs.cc",
    "optabs-libfuncs.cc",
    "optabs-query.cc",
    "optabs-tree.cc",
    "optinfo.cc",
    "optinfo-emit-json.cc",
    "opts-global.cc",
    "ordered-hash-map-tests.cc",
    "passes.cc",
    "plugin.cc",
    "pointer-query.cc",
    "postreload-gcse.cc",
    "postreload.cc",
    "predict.cc",
    "print-rtl.cc",
    "print-rtl-function.cc",
    "print-tree.cc",
    "profile.cc",
    "profile-count.cc",
    "range.cc",
    "range-op.cc",
    "range-op-float.cc",
    "range-op-ptr.cc",
    "read-md.cc",
    "read-rtl.cc",
    "read-rtl-function.cc",
    "real.cc",
    "realmpfr.cc",
    "recog.cc",
    "reg-stack.cc",
    "regcprop.cc",
    "reginfo.cc",
    "regrename.cc",
    "regstat.cc",
    "reload.cc",
    "reload1.cc",
    "reorg.cc",
    "resource.cc",
    "rtl-error.cc",
    "rtl-ssa/accesses.cc",
    "rtl-ssa/blocks.cc",
    "rtl-ssa/changes.cc",
    "rtl-ssa/functions.cc",
    "rtl-ssa/insns.cc",
    "rtl-ssa/movement.cc",
    "rtl-tests.cc",
    "rtl.cc",
    "rtlhash.cc",
    "rtlanal.cc",
    "rtlhooks.cc",
    "rtx-vector-builder.cc",
    "run-rtl-passes.cc",
    "sched-deps.cc",
    "sched-ebb.cc",
    "sched-rgn.cc",
    "sel-sched-ir.cc",
    "sel-sched-dump.cc",
    "sel-sched.cc",
    "selftest-rtl.cc",
    "selftest-run-tests.cc",
    "sese.cc",
    "shrink-wrap.cc",
    "simplify-rtx.cc",
    "sparseset.cc",
    "spellcheck.cc",
    "spellcheck-tree.cc",
    "splay-tree-utils.cc",
    "sreal.cc",
    "stack-ptr-mod.cc",
    "statistics.cc",
    "stmt.cc",
    "stor-layout.cc",
    "store-motion.cc",
    "streamer-hooks.cc",
    "stringpool.cc",
    "substring-locations.cc",
    "target-globals.cc",
    "targhooks.cc",
    "timevar.cc",
    "toplev.cc",
    "tracer.cc",
    "trans-mem.cc",
    "tree-affine.cc",
    "asan.cc",
    "tsan.cc",
    "ubsan.cc",
    "sanopt.cc",
    "sancov.cc",
    "tree-call-cdce.cc",
    "tree-cfg.cc",
    "tree-cfgcleanup.cc",
    "tree-chrec.cc",
    "tree-complex.cc",
    "tree-data-ref.cc",
    "tree-dfa.cc",
    "tree-diagnostic.cc",
    "tree-diagnostic-client-data-hooks.cc",
    "tree-diagnostic-path.cc",
    "tree-dump.cc",
    "tree-eh.cc",
    "tree-emutls.cc",
    "tree-if-conv.cc",
    "tree-inline.cc",
    "tree-into-ssa.cc",
    "tree-iterator.cc",
    "tree-logical-location.cc",
    "tree-loop-distribution.cc",
    "tree-nested.cc",
    "tree-nrv.cc",
    "tree-object-size.cc",
    "tree-outof-ssa.cc",
    "tree-parloops.cc",
    "tree-phinodes.cc",
    "tree-predcom.cc",
    "tree-pretty-print.cc",
    "tree-profile.cc",
    "tree-scalar-evolution.cc",
    "tree-sra.cc",
    "tree-switch-conversion.cc",
    "tree-ssa-address.cc",
    "tree-ssa-alias.cc",
    "tree-ssa-ccp.cc",
    "tree-ssa-coalesce.cc",
    "tree-ssa-copy.cc",
    "tree-ssa-dce.cc",
    "tree-ssa-dom.cc",
    "tree-ssa-dse.cc",
    "tree-ssa-forwprop.cc",
    "tree-ssa-ifcombine.cc",
    "tree-ssa-live.cc",
    "tree-ssa-loop-ch.cc",
    "tree-ssa-loop-im.cc",
    "tree-ssa-loop-ivcanon.cc",
    "tree-ssa-loop-ivopts.cc",
    "tree-ssa-loop-manip.cc",
    "tree-ssa-loop-niter.cc",
    "tree-ssa-loop-prefetch.cc",
    "tree-ssa-loop-split.cc",
    "tree-ssa-loop-unswitch.cc",
    "tree-ssa-loop.cc",
    "tree-ssa-math-opts.cc",
    "tree-ssa-operands.cc",
    "gimple-range-path.cc",
    "tree-ssa-phiopt.cc",
    "tree-ssa-phiprop.cc",
    "tree-ssa-pre.cc",
    "tree-ssa-propagate.cc",
    "tree-ssa-reassoc.cc",
    "tree-ssa-sccvn.cc",
    "tree-ssa-scopedtables.cc",
    "tree-ssa-sink.cc",
    "tree-ssa-strlen.cc",
    "tree-ssa-structalias.cc",
    "tree-ssa-tail-merge.cc",
    "tree-ssa-ter.cc",
    "tree-ssa-threadbackward.cc",
    "tree-ssa-threadedge.cc",
    "tree-ssa-threadupdate.cc",
    "tree-ssa-uncprop.cc",
    "tree-ssa-uninit.cc",
    "tree-ssa.cc",
    "tree-ssanames.cc",
    "tree-stdarg.cc",
    "tree-streamer.cc",
    "tree-streamer-in.cc",
    "tree-streamer-out.cc",
    "tree-tailcall.cc",
    "tree-vect-generic.cc",
    "gimple-isel.cc",
    "tree-vect-patterns.cc",
    "tree-vect-data-refs.cc",
    "tree-vect-stmts.cc",
    "tree-vect-loop.cc",
    "tree-vect-loop-manip.cc",
    "tree-vect-slp.cc",
    "tree-vect-slp-patterns.cc",
    "tree-vectorizer.cc",
    "tree-vector-builder.cc",
    "tree-vrp.cc",
    "tree.cc",
    "tristate.cc",
    "typed-splay-tree.cc",
    "valtrack.cc",
    "value-pointer-equiv.cc",
    "value-query.cc",
    "value-range.cc",
    "value-range-pretty-print.cc",
    "value-range-storage.cc",
    "value-relation.cc",
    "value-prof.cc",
    "var-tracking.cc",
    "varasm.cc",
    "varpool.cc",
    "vec-perm-indices.cc",
    "vmsdbgout.cc",
    "vr-values.cc",
    "vtable-verify.cc",
    "warning-control.cc",
    "web.cc",
    "wide-int.cc",
    "wide-int-print.cc",
    // host_hook_obj for linux
    "config/host-linux.cc",
};

// Generated files (from generated/rl78/)
const generated_files = [_][]const u8{
    // insn-* generated files
    "insn-attrtab.cc",
    "insn-automata.cc",
    "insn-dfatab.cc",
    "insn-emit-1.cc",
    "insn-emit-2.cc",
    "insn-emit-3.cc",
    "insn-emit-4.cc",
    "insn-emit-5.cc",
    "insn-emit-6.cc",
    "insn-emit-7.cc",
    "insn-emit-8.cc",
    "insn-emit-9.cc",
    "insn-emit-10.cc",
    "insn-extract.cc",
    "insn-latencytab.cc",
    "insn-modes.cc",
    "insn-opinit.cc",
    "insn-output.cc",
    "insn-peep.cc",
    "insn-preds.cc",
    "insn-recog.cc",
    "insn-enums.cc",
    // options
    "options.cc",
    "options-save.cc",
    "options-urls.cc",
    // gtype
    "gtype-desc.cc",
    // gimple-match and generic-match
    "gimple-match-1.cc",
    "gimple-match-2.cc",
    "gimple-match-3.cc",
    "gimple-match-4.cc",
    "gimple-match-5.cc",
    "gimple-match-6.cc",
    "gimple-match-7.cc",
    "gimple-match-8.cc",
    "gimple-match-9.cc",
    "gimple-match-10.cc",
    "generic-match-1.cc",
    "generic-match-2.cc",
    "generic-match-3.cc",
    "generic-match-4.cc",
    "generic-match-5.cc",
    "generic-match-6.cc",
    "generic-match-7.cc",
    "generic-match-8.cc",
    "generic-match-9.cc",
    "generic-match-10.cc",
};

// OBJS-libcommon
// Note: ggc-none.cc is excluded because cc1 uses ggc-page.cc instead.
// The driver adds ggc-none.cc separately via GCC_OBJS.
// vec.cc, hash-table.cc, selftest.cc, spellcheck.cc are listed here but
// also in OBJS/libcommon-target -- they must only appear once.
const libcommon_files = [_][]const u8{
    "diagnostic-spec.cc",
    "diagnostic.cc",
    "diagnostic-color.cc",
    "diagnostic-format-json.cc",
    "diagnostic-format-sarif.cc",
    "diagnostic-show-locus.cc",
    "edit-context.cc",
    "pretty-print.cc",
    "intl.cc",
    "json.cc",
    "sbitmap.cc",
    "vec.cc",
    "input.cc",
    "hash-table.cc",
    // ggc-none.cc excluded -- cc1 uses ggc-page.cc; driver adds it via GCC_OBJS
    "memory-block.cc",
    "selftest.cc",
    "selftest-diagnostic.cc",
    "sort.cc",
    "text-art/box-drawing.cc",
    "text-art/canvas.cc",
    "text-art/ruler.cc",
    "text-art/selftests.cc",
    "text-art/style.cc",
    "text-art/styled-string.cc",
    "text-art/table.cc",
    "text-art/theme.cc",
    "text-art/widget.cc",
};

// OBJS-libcommon-target (common_out_file added dynamically via config.gcc_common_out_file)
const libcommon_target_files = [_][]const u8{
    "prefix.cc",
    "opts.cc",
    "opts-common.cc",
    // options.cc is in generated
    // vec.cc is already in libcommon
    "hooks.cc",
    "common/common-targhooks.cc",
    // hash-table.cc is already in libcommon
    "file-find.cc",
    // spellcheck.cc is already in OBJS
    // selftest.cc is already in libcommon
    "opt-suggestions.cc",
    // options-urls.cc is in generated
};

// ANALYZER_OBJS
const analyzer_files = [_][]const u8{
    "analyzer/access-diagram.cc",
    "analyzer/analysis-plan.cc",
    "analyzer/analyzer.cc",
    "analyzer/analyzer-language.cc",
    "analyzer/analyzer-logging.cc",
    "analyzer/analyzer-pass.cc",
    "analyzer/analyzer-selftests.cc",
    "analyzer/bar-chart.cc",
    "analyzer/bounds-checking.cc",
    "analyzer/call-details.cc",
    "analyzer/call-info.cc",
    "analyzer/call-string.cc",
    "analyzer/call-summary.cc",
    "analyzer/checker-event.cc",
    "analyzer/checker-path.cc",
    "analyzer/complexity.cc",
    "analyzer/constraint-manager.cc",
    "analyzer/diagnostic-manager.cc",
    "analyzer/engine.cc",
    "analyzer/feasible-graph.cc",
    "analyzer/function-set.cc",
    "analyzer/infinite-loop.cc",
    "analyzer/infinite-recursion.cc",
    "analyzer/kf.cc",
    "analyzer/kf-analyzer.cc",
    "analyzer/kf-lang-cp.cc",
    "analyzer/known-function-manager.cc",
    "analyzer/pending-diagnostic.cc",
    "analyzer/program-point.cc",
    "analyzer/program-state.cc",
    "analyzer/ranges.cc",
    "analyzer/record-layout.cc",
    "analyzer/region.cc",
    "analyzer/region-model.cc",
    "analyzer/region-model-asm.cc",
    "analyzer/region-model-manager.cc",
    "analyzer/region-model-reachability.cc",
    "analyzer/sm.cc",
    "analyzer/sm-file.cc",
    "analyzer/sm-fd.cc",
    "analyzer/sm-malloc.cc",
    "analyzer/sm-pattern-test.cc",
    "analyzer/sm-sensitive.cc",
    "analyzer/sm-signal.cc",
    "analyzer/sm-taint.cc",
    "analyzer/state-purge.cc",
    "analyzer/store.cc",
    "analyzer/supergraph.cc",
    "analyzer/svalue.cc",
    "analyzer/symbol.cc",
    "analyzer/trimmed-graph.cc",
    "analyzer/varargs.cc",
};

// C frontend files
const c_frontend_files = [_][]const u8{
    // C language
    "c/c-lang.cc",
    "c-family/stub-objc.cc",
    // C_AND_OBJC_OBJS
    "attribs.cc",
    "c/c-errors.cc",
    "c/c-decl.cc",
    "c/c-typeck.cc",
    "c/c-convert.cc",
    "c/c-aux-info.cc",
    "c/c-objc-common.cc",
    "c/c-parser.cc",
    "c/c-fold.cc",
    "c/gimple-parser.cc",
    // C_COMMON_OBJS
    "c-family/c-common.cc",
    "c-family/c-cppbuiltin.cc",
    "c-family/c-dump.cc",
    "c-family/c-format.cc",
    "c-family/c-gimplify.cc",
    "c-family/c-indentation.cc",
    "c-family/c-lex.cc",
    "c-family/c-omp.cc",
    "c-family/c-opts.cc",
    "c-family/c-pch.cc",
    "c-family/c-ppoutput.cc",
    "c-family/c-pragma.cc",
    "c-family/c-pretty-print.cc",
    "c-family/c-semantics.cc",
    "c-family/c-ada-spec.cc",
    "c-family/c-ubsan.cc",
    "c-family/known-headers.cc",
    "c-family/c-attribs.cc",
    "c-family/c-warn.cc",
    "c-family/c-spellcheck.cc",
    // c/gccspec.o
    "c/gccspec.cc",
};
