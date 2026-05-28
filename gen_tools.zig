//! Builds GCC's generator host tools (gen*) and runs them to produce the
//! files GCC normally generates at build time (insn-*.cc/h, etc.). This
//! replaces vendoring those generated outputs.
//!
//! The gen* tools are target-independent: only their .md/.opt inputs differ per
//! target, so this module lives in gcc-cross-zig and serves every leaf repo.
//!
//! GCC's own bootstrap ordering is reproduced:
//!   1. genmodes (no generated deps)        -> insn-modes.h, min-insn-modes.cc
//!   2. genconstants (read-md + errors)     -> insn-constants.h
//!   3. shared support lib (needs the two headers above)
//!   4. genconditions -> gencondmd -> insn-conditions.md
//!   5. md-consuming generators             -> insn-*.cc/h, tm-preds.h, ...
//!
//! To avoid build-graph cycles, generated headers are consumed via each
//! captured file's own directory (LazyPath.dirname) rather than a single shared
//! WriteFiles that every step both writes to and reads from.
//! SPDX-License-Identifier: GPL-2.0-or-later

const std = @import("std");
const cross_config = @import("cross_config.zig");
const CrossConfig = cross_config.CrossConfig;

const gen_flags = [_][]const u8{
    "-DIN_GCC",
    "-DCROSS_DIRECTORY_STRUCTURE",
    "-DHAVE_CONFIG_H",
    "-DGENERATOR_FILE",
    "-fno-exceptions",
    "-fno-rtti",
    "-Wno-narrowing",
    "-Wno-error",
    // Clang-only: GCC's wide-int.h memcpy's non-trivially-copyable storage,
    // which g++ accepts silently but Clang flags. Harmless here.
    "-Wno-nontrivial-memaccess",
};

/// Tier-B shared support sources (linked by most md-consuming generators).
/// min-insn-modes.cc is generated, so it is added separately.
const support_srcs = [_][]const u8{
    "rtl.cc",        "read-rtl.cc",  "ggc-none.cc",   "vec.cc",
    "gensupport.cc", "print-rtl.cc", "hash-table.cc", "sort.cc",
    "read-md.cc",    "errors.cc",    "inchash.cc",
};

pub const NamedFile = struct { name: []const u8, file: std.Build.LazyPath };

/// Copy a generated file into the assembled dir and record it for verification.
fn emit(b: *std.Build, wf: *std.Build.Step.WriteFile, list: *std.ArrayList(NamedFile), name: []const u8, lp: std.Build.LazyPath) void {
    _ = wf.addCopyFile(lp, name);
    list.append(b.allocator, .{ .name = name, .file = lp }) catch @panic("OOM");
}

pub const Generated = struct {
    /// Directory holding every generated file cc1 must see (headers + sources).
    dir: std.Build.LazyPath,
    /// gengtype output dir, holding the gt-*.h headers cc1 includes.
    gt_dir: std.Build.LazyPath,
    /// Each generated file paired with its captured LazyPath, for verification
    /// independent of the assembled directory.
    files: []const NamedFile,
};

const Ctx = struct {
    b: *std.Build,
    gcc_root: std.Build.LazyPath,
    gcc_dir: std.Build.LazyPath, // gcc_root/gcc
    bconfig_dir: std.Build.LazyPath,
    /// Generators run on the build machine, so every gen* exe/support lib is
    /// compiled for this (native) target -- never the toolchain's host_target.
    build_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    iberty: *std.Build.Step.Compile,
    config: CrossConfig,
    common_md: std.Build.LazyPath, // gcc/common.md
    target_md: std.Build.LazyPath, // gcc/config/<cpu>/<cpu>.md

    fn addBaseIncludes(c: Ctx, mod: *std.Build.Module) void {
        mod.addIncludePath(c.bconfig_dir);
        mod.addIncludePath(c.config.config_dir); // auto-host.h
        mod.addIncludePath(c.gcc_dir);
        mod.addIncludePath(c.gcc_root.path(c.b, "include"));
        mod.addIncludePath(c.gcc_root.path(c.b, "libcpp/include"));
    }
};

fn buildConfigDir(b: *std.Build) std.Build.LazyPath {
    const wf = b.addWriteFiles();
    _ = wf.add("bconfig.h",
        \\#ifndef GCC_BCONFIG_H
        \\#define GCC_BCONFIG_H
        \\#include "auto-host.h"
        \\#ifdef IN_GCC
        \\# include "ansidecl.h"
        \\#endif
        \\#endif /* GCC_BCONFIG_H */
        \\
    );
    return wf.getDirectory();
}

/// Build a standalone generator (no shared support lib): compiles `srcs`
/// directly and links host libiberty. Used for genmodes, genconstants, gencondmd.
fn standaloneTool(
    c: Ctx,
    name: []const u8,
    srcs: []const []const u8,
    gen_srcs: []const std.Build.LazyPath,
    inc_dirs: []const std.Build.LazyPath,
    extra_flags: []const []const u8,
) *std.Build.Step.Compile {
    const flags = std.mem.concat(c.b.allocator, []const u8, &.{ &gen_flags, extra_flags }) catch @panic("OOM");
    const exe = c.b.addExecutable(.{
        .name = name,
        .root_module = c.b.createModule(.{
            .target = c.build_target,
            .optimize = c.optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.link_libcpp = true;
    exe.root_module.addCSourceFiles(.{ .root = c.gcc_dir, .files = srcs, .flags = flags });
    for (gen_srcs) |s| exe.root_module.addCSourceFile(.{ .file = s, .flags = flags });
    c.addBaseIncludes(exe.root_module);
    for (inc_dirs) |d| exe.root_module.addIncludePath(d);
    exe.root_module.linkLibrary(c.iberty);
    return exe;
}

/// Always-present .opt files (language fronts + common), in GCC's gather order.
const fixed_opt_files = [_][]const u8{
    "ada/gcc-interface/lang.opt", "d/lang.opt",            "fortran/lang.opt",
    "go/lang.opt",                "lto/lang.opt",          "m2/lang.opt",
    "rust/lang.opt",              "c-family/c.opt",        "common.opt",
    "params.opt",                 "analyzer/analyzer.opt",
};

/// Run gawk with the given -f scripts over `stdin_list`, capturing stdout.
fn awk(
    c: Ctx,
    scripts: []const []const u8,
    extra_args: []const []const u8,
    stdin_list: std.Build.LazyPath,
    basename: []const u8,
) std.Build.LazyPath {
    const run = c.b.addSystemCommand(&.{"gawk"});
    for (scripts) |s| {
        run.addArg("-f");
        run.addFileArg(c.gcc_dir.path(c.b, s));
    }
    for (extra_args) |a| run.addArg(a);
    run.setStdIn(.{ .lazy_path = stdin_list });
    return run.captureStdOut(.{ .trim_whitespace = .none, .basename = basename });
}

/// Build `optionlist` (opt-gather.awk over all .opt and .opt.urls files) and
/// run the option generators to produce options.h/.cc/-save/-urls.
fn addOptions(c: Ctx, b: *std.Build, final: *std.Build.Step.WriteFile, files: *std.ArrayList(NamedFile)) std.Build.LazyPath {
    const og = c.b.addSystemCommand(&.{ "gawk", "-f" });
    og.addFileArg(c.gcc_dir.path(c.b, "opt-gather.awk"));
    // .opt files, then their .opt.urls counterparts (GCC's gather order).
    for (fixed_opt_files) |f| og.addFileArg(c.gcc_dir.path(c.b, f));
    for (c.config.gcc_target_opt_files) |f| og.addFileArg(c.gcc_dir.path(c.b, f));
    for (fixed_opt_files) |f| og.addFileArg(c.gcc_dir.path(c.b, c.b.fmt("{s}.urls", .{f})));
    for (c.config.gcc_target_opt_files) |f| og.addFileArg(c.gcc_dir.path(c.b, c.b.fmt("{s}.urls", .{f})));
    const optionlist = og.captureStdOut(.{ .trim_whitespace = .none, .basename = "optionlist" });

    const read = [_][]const u8{ "opt-functions.awk", "opt-read.awk" };
    const options_h = awk(c, &(read ++ [_][]const u8{"opth-gen.awk"}), &.{}, optionlist, "options.h");
    emit(b, final, files, "options.h", options_h);
    emit(b, final, files, "options.cc", awk(c, &(read ++ [_][]const u8{"optc-gen.awk"}), &.{ "-v", "header_name=config.h system.h coretypes.h options.h tm.h" }, optionlist, "options.cc"));
    emit(b, final, files, "options-save.cc", awk(c, &(read ++ [_][]const u8{"optc-save-gen.awk"}), &.{ "-v", "header_name=config.h system.h coretypes.h tm.h" }, optionlist, "options-save.cc"));
    emit(b, final, files, "options-urls.cc", awk(c, &(read ++ [_][]const u8{"options-urls-cc-gen.awk"}), &.{ "-v", "header_name=config.h system.h coretypes.h tm.h" }, optionlist, "options-urls.cc"));
    return options_h;
}

/// Build gengtype and run it (two-phase) to produce gtype-desc.h/.cc + gt-*.h.
/// Returns the output directory (holds gtype-desc.h, used as an include path,
/// and gtype-desc.cc / gt-*.h consumed by cc1).
const GengtypeResult = struct { gt_dir: std.Build.LazyPath, version_h: std.Build.LazyPath };

fn addGengtype(
    c: Ctx,
    modes_inc: std.Build.LazyPath,
    modes_inline_inc: std.Build.LazyPath,
    options_h: std.Build.LazyPath,
) GengtypeResult {
    const list_in = c.config.gtyp_input_list orelse @panic("gtyp_input_list required to generate gtype-desc");

    // gengtype includes version.h (from genversion). genversion needs the
    // version macros GCC's Makefile passes; empty datestamp/devphase/revision
    // match a release build (version_string == BASEVER).
    const version_flags = [_][]const u8{
        c.b.fmt("-DBASEVER=\"{s}\"", .{c.config.gcc_version}),
        "-DDATESTAMP=\"\"",
        "-DDEVPHASE=\"\"",
        "-DREVISION=\"\"",
        "-DPKGVERSION=\"(GCC) \"",
        "-DBUGURL=\"<https://gcc.gnu.org/bugs/>\"",
    };
    const genversion = standaloneTool(c, "genversion", &.{ "genversion.cc", "errors.cc" }, &.{}, &.{}, &version_flags);
    const version_h = runCapture(c, genversion, &.{}, "version.h");

    const gengtype = standaloneTool(c, "gengtype", &.{
        "gengtype.cc", "gengtype-lex.cc", "gengtype-parse.cc", "gengtype-state.cc", "errors.cc",
    }, &.{}, &.{ modes_inc, modes_inline_inc, version_h.dirname() }, &.{});

    // gengtype writes its outputs to cwd, so run it inside a captured output dir.
    // The manifest's @GCCSRC@ token is rebased to the patched source root; the
    // bare names auto-host.h and options.h must exist in that cwd.
    const run = c.b.addSystemCommand(&.{
        "sh", "-c",
        \\set -e
        \\GG="$(realpath "$1")"; SRCDIR="$(realpath "$2")"; LISTIN="$3"; GCCSRC="$(realpath "$4")"; AUTOH="$5"; OPTS="$6"; OUT="$7"
        \\mkdir -p "$OUT"
        \\sed "s|@GCCSRC@|$GCCSRC|g" "$LISTIN" > "$OUT/gtyp-input.list"
        \\cp "$AUTOH" "$OUT/auto-host.h"
        \\cp "$OPTS" "$OUT/options.h"
        \\cd "$OUT"
        \\"$GG" -S "$SRCDIR" -I gtyp-input.list -w gtype.state
        \\"$GG" -r gtype.state
        ,
        "_",
    });
    run.addArtifactArg(gengtype); // $1
    run.addDirectoryArg(c.gcc_dir); // $2 srcdir
    run.addFileArg(list_in); // $3
    run.addDirectoryArg(c.gcc_root); // $4 @GCCSRC@ -> source root
    run.addFileArg(c.config.config_dir.path(c.b, "auto-host.h")); // $5
    run.addFileArg(options_h); // $6
    return .{ .gt_dir = run.addOutputDirectoryArg("gtype-out"), .version_h = version_h }; // $7
}

fn runCapture(c: Ctx, tool: *std.Build.Step.Compile, args: []const []const u8, basename: []const u8) std.Build.LazyPath {
    const run = c.b.addRunArtifact(tool);
    for (args) |a| run.addArg(a);
    return run.captureStdOut(.{ .trim_whitespace = .none, .basename = basename });
}

/// Run a generator on (common.md target.md [conditions.md]) capturing stdout.
fn runMd(c: Ctx, tool: *std.Build.Step.Compile, conditions: ?std.Build.LazyPath, basename: []const u8) std.Build.LazyPath {
    const run = c.b.addRunArtifact(tool);
    run.addFileArg(c.common_md);
    run.addFileArg(c.target_md);
    if (conditions) |cond| run.addFileArg(cond);
    return run.captureStdOut(.{ .trim_whitespace = .none, .basename = basename });
}

pub fn addGenerated(
    b: *std.Build,
    gcc_root: std.Build.LazyPath,
    build_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    iberty: *std.Build.Step.Compile,
    libcpp: *std.Build.Step.Compile,
    config: CrossConfig,
) Generated {
    const c = Ctx{
        .b = b,
        .gcc_root = gcc_root,
        .gcc_dir = gcc_root.path(b, "gcc"),
        .bconfig_dir = buildConfigDir(b),
        .build_target = build_target,
        .optimize = optimize,
        .iberty = iberty,
        .config = config,
        .common_md = gcc_root.path(b, "gcc/common.md"),
        .target_md = gcc_root.path(b, b.fmt("gcc/config/{s}/{s}.md", .{ config.target_cpu, config.target_cpu })),
    };

    const final = b.addWriteFiles();
    var files: std.ArrayList(NamedFile) = .empty;

    // Copy patched source headers (e.g. config/<cpu>/<cpu>-opts.h) into the
    // generated dir so the upstream-sourced driver resolves their patched form.
    for (config.gcc_generated_extra_headers) |h| {
        _ = final.addCopyFile(gcc_root.path(b, b.fmt("gcc/{s}", .{h})), h);
    }

    // --- Stage 1: genmodes ---
    const genmodes = standaloneTool(c, "genmodes", &.{ "genmodes.cc", "errors.cc" }, &.{}, &.{}, &.{});
    const modes_h = runCapture(c, genmodes, &.{"-h"}, "insn-modes.h");
    const modes_inline = runCapture(c, genmodes, &.{"-i"}, "insn-modes-inline.h");
    const min_modes_cc = runCapture(c, genmodes, &.{"-m"}, "min-insn-modes.cc");
    const modes_cc = runCapture(c, genmodes, &.{}, "insn-modes.cc");
    emit(b, final, &files, "insn-modes.h", modes_h);
    emit(b, final, &files, "insn-modes-inline.h", modes_inline);
    emit(b, final, &files, "insn-modes.cc", modes_cc);

    // coretypes.h pulls in both insn-modes.h and insn-modes-inline.h; each
    // captured stdout lives in its own dir, so both dirs go on the path.
    const modes_inc = modes_h.dirname();
    const modes_inline_inc = modes_inline.dirname();

    // --- Stage 2: genconstants (read-md + errors; needs the mode headers) ---
    const genconstants = standaloneTool(c, "genconstants", &.{ "genconstants.cc", "read-md.cc", "errors.cc" }, &.{}, &.{ modes_inc, modes_inline_inc }, &.{});
    const constants_h = runMd(c, genconstants, null, "insn-constants.h");
    emit(b, final, &files, "insn-constants.h", constants_h);
    const constants_inc = constants_h.dirname();

    // options.h is generated by AWK over the gathered .opt files; tm.h includes
    // it unconditionally, so it must precede the support lib.
    const options_h = addOptions(c, b, final, &files);
    const options_inc = options_h.dirname();

    // gtype-desc.h (gengtype) is included unconditionally via ggc.h, so it too
    // must precede the support lib. gengtype is self-contained (no rtl.o).
    const gtype = addGengtype(c, modes_inc, modes_inline_inc, options_h);
    const gtype_dir = gtype.gt_dir;
    emit(b, final, &files, "gtype-desc.cc", gtype_dir.path(b, "gtype-desc.cc"));
    emit(b, final, &files, "gtype-desc.h", gtype_dir.path(b, "gtype-desc.h"));
    emit(b, final, &files, "version.h", gtype.version_h);

    const early_incs = [_]std.Build.LazyPath{ modes_inc, modes_inline_inc, constants_inc, options_inc, gtype_dir };

    // --- Stage 3: shared support library (Tier B) ---
    const sup = b.addLibrary(.{
        .linkage = .static,
        .name = "gensupport",
        .root_module = b.createModule(.{ .target = build_target, .optimize = optimize, .link_libc = true }),
    });
    sup.root_module.link_libcpp = true;
    sup.root_module.addCSourceFiles(.{ .root = c.gcc_dir, .files = &support_srcs, .flags = &gen_flags });
    sup.root_module.addCSourceFile(.{ .file = min_modes_cc, .flags = &gen_flags });
    c.addBaseIncludes(sup.root_module);
    for (early_incs) |d| sup.root_module.addIncludePath(d);

    // Helper to build a Tier-B md-consumer tool (links support lib + iberty).
    const tierB = struct {
        fn make(cc: Ctx, support: *std.Build.Step.Compile, incs: []const std.Build.LazyPath, name: []const u8, src: []const u8) *std.Build.Step.Compile {
            const exe = cc.b.addExecutable(.{
                .name = name,
                .root_module = cc.b.createModule(.{ .target = cc.build_target, .optimize = cc.optimize, .link_libc = true }),
            });
            exe.root_module.link_libcpp = true;
            exe.root_module.addCSourceFiles(.{ .root = cc.gcc_dir, .files = &.{src}, .flags = &gen_flags });
            cc.addBaseIncludes(exe.root_module);
            for (incs) |d| exe.root_module.addIncludePath(d);
            exe.root_module.linkLibrary(support);
            exe.root_module.linkLibrary(cc.iberty);
            return exe;
        }
    }.make;

    // --- Stage 4: genpreds (produces tm-preds.h, needed by tm_p.h below) ---
    // genpreds has three outputs (-h tm-preds.h, -c tm-constrs.h, plain insn-preds.cc).
    const genpreds = tierB(c, sup, &early_incs, "genpreds", "genpreds.cc");
    const run_h = b.addRunArtifact(genpreds);
    run_h.addArg("-h");
    run_h.addFileArg(c.common_md);
    run_h.addFileArg(c.target_md);
    const tm_preds_h = run_h.captureStdOut(.{ .trim_whitespace = .none, .basename = "tm-preds.h" });
    emit(b, final, &files, "tm-preds.h", tm_preds_h);
    const run_c = b.addRunArtifact(genpreds);
    run_c.addArg("-c");
    run_c.addFileArg(c.common_md);
    run_c.addFileArg(c.target_md);
    const tm_constrs_h = run_c.captureStdOut(.{ .trim_whitespace = .none, .basename = "tm-constrs.h" });
    emit(b, final, &files, "tm-constrs.h", tm_constrs_h);
    emit(b, final, &files, "insn-preds.cc", runMd(c, genpreds, null, "insn-preds.cc"));

    // tm_p.h: trivial wrapper GCC's mkconfig.sh produces; gencondmd includes it.
    const tmp_wf = b.addWriteFiles();
    _ = tmp_wf.add("tm_p.h", b.fmt(
        \\#ifndef GCC_TM_P_H
        \\#define GCC_TM_P_H
        \\#ifdef IN_GCC
        \\# include "config/{s}/{s}-protos.h"
        \\# include "tm-preds.h"
        \\#endif
        \\#endif /* GCC_TM_P_H */
        \\
    , .{ config.target_cpu, config.target_cpu }));
    const tm_p_inc = tmp_wf.getDirectory();

    // all-tree.def: fixed, target-independent concatenation GCC builds from the
    // language tree.def files. gencondmd pulls it in via tree-core.h (reached
    // through rx-protos.h's tree-typed prototypes in tm_p.h).
    const alltree_wf = b.addWriteFiles();
    _ = alltree_wf.add("all-tree.def",
        \\#include "tree.def"
        \\END_OF_BASE_TREE_CODES
        \\#include "c-family/c-common.def"
        \\#include "ada/gcc-interface/ada-tree.def"
        \\#include "c/c-tree.def"
        \\#include "cp/cp-tree.def"
        \\#include "d/d-tree.def"
        \\#include "m2/m2-tree.def"
        \\#include "objc/objc-tree.def"
        \\
    );
    const alltree_inc = alltree_wf.getDirectory();

    // tree-check.h (gencheck, reads all-tree.def). Also reached via tree.h.
    const gencheck = standaloneTool(c, "gencheck", &.{ "gencheck.cc", "errors.cc" }, &.{}, &(early_incs ++ [_]std.Build.LazyPath{alltree_inc}), &.{});
    const tree_check_h = runCapture(c, gencheck, &.{}, "tree-check.h");
    const tree_check_inc = tree_check_h.dirname();

    // bversion.h: trivial version header GCC's Makefile derives from BASE-VER.
    const ver = std.SemanticVersion.parse(config.gcc_version) catch @panic("bad gcc_version");
    const bversion_wf = b.addWriteFiles();
    _ = bversion_wf.add("bversion.h", b.fmt(
        \\#define BUILDING_GCC_MAJOR {d}
        \\#define BUILDING_GCC_MINOR {d}
        \\#define BUILDING_GCC_PATCHLEVEL {d}
        \\#define BUILDING_GCC_VERSION (BUILDING_GCC_MAJOR * 1000 + BUILDING_GCC_MINOR)
        \\
    , .{ ver.major, ver.minor, ver.patch }));
    const bversion_inc = bversion_wf.getDirectory();

    // --- Stage 5: genconditions -> gencondmd -> insn-conditions.md ---
    const genconditions = tierB(c, sup, &early_incs, "genconditions", "genconditions.cc");
    const condmd_cc = runMd(c, genconditions, null, "gencondmd.cc");
    // gencondmd includes tm_p.h (-> tm-preds.h, rx-protos.h -> tree-core.h).
    const condmd_incs = early_incs ++ [_]std.Build.LazyPath{ tm_p_inc, tm_preds_h.dirname(), tm_constrs_h.dirname(), alltree_inc, tree_check_inc, bversion_inc };
    const gencondmd = standaloneTool(c, "gencondmd", &.{"errors.cc"}, &.{condmd_cc}, &condmd_incs, &.{});
    const conditions_md = runCapture(c, gencondmd, &.{}, "insn-conditions.md");

    // --- Stage 6: md-consumers (common.md target.md insn-conditions.md) ---
    const StdoutGen = struct { name: []const u8, src: []const u8, out: []const u8 };
    const stdout_gens = [_]StdoutGen{
        .{ .name = "genflags", .src = "genflags.cc", .out = "insn-flags.h" },
        .{ .name = "genattr", .src = "genattr.cc", .out = "insn-attr.h" },
        .{ .name = "genattr-common", .src = "genattr-common.cc", .out = "insn-attr-common.h" },
        .{ .name = "gencodes", .src = "gencodes.cc", .out = "insn-codes.h" },
        .{ .name = "genconfig", .src = "genconfig.cc", .out = "insn-config.h" },
        .{ .name = "gentarget-def", .src = "gentarget-def.cc", .out = "insn-target-def.h" },
        .{ .name = "genextract", .src = "genextract.cc", .out = "insn-extract.cc" },
        .{ .name = "genoutput", .src = "genoutput.cc", .out = "insn-output.cc" },
        .{ .name = "genpeep", .src = "genpeep.cc", .out = "insn-peep.cc" },
        .{ .name = "genrecog", .src = "genrecog.cc", .out = "insn-recog.cc" },
        .{ .name = "genenums", .src = "genenums.cc", .out = "insn-enums.cc" },
    };
    for (stdout_gens) |g| {
        const tool = tierB(c, sup, &early_incs, g.name, g.src);
        emit(b, final, &files, g.out, runMd(c, tool, conditions_md, g.out));
    }

    // genautomata: stdout -> insn-automata.cc.
    {
        const tool = tierB(c, sup, &early_incs, "genautomata", "genautomata.cc");
        emit(b, final, &files, "insn-automata.cc", runMd(c, tool, conditions_md, "insn-automata.cc"));
    }

    // Flag-output generators take (common.md target.md insn-conditions.md) then
    // write to prefixed paths. Helper builds the common arg prefix.
    const mdRun = struct {
        fn r(cc: Ctx, tool: *std.Build.Step.Compile, conditions: std.Build.LazyPath) *std.Build.Step.Run {
            const run = cc.b.addRunArtifact(tool);
            run.addFileArg(cc.common_md);
            run.addFileArg(cc.target_md);
            run.addFileArg(conditions);
            return run;
        }
    }.r;

    // genopinit -h insn-opinit.h -c insn-opinit.cc
    {
        const tool = tierB(c, sup, &early_incs, "genopinit", "genopinit.cc");
        const run = mdRun(c, tool, conditions_md);
        emit(b, final, &files, "insn-opinit.h", run.addPrefixedOutputFileArg("-h", "insn-opinit.h"));
        emit(b, final, &files, "insn-opinit.cc", run.addPrefixedOutputFileArg("-c", "insn-opinit.cc"));
    }

    // genattrtab -A insn-attrtab.cc -D insn-dfatab.cc -L insn-latencytab.cc
    {
        const tool = tierB(c, sup, &early_incs, "genattrtab", "genattrtab.cc");
        const run = mdRun(c, tool, conditions_md);
        emit(b, final, &files, "insn-attrtab.cc", run.addPrefixedOutputFileArg("-A", "insn-attrtab.cc"));
        emit(b, final, &files, "insn-dfatab.cc", run.addPrefixedOutputFileArg("-D", "insn-dfatab.cc"));
        emit(b, final, &files, "insn-latencytab.cc", run.addPrefixedOutputFileArg("-L", "insn-latencytab.cc"));
    }

    // genemit -O insn-emit-1.cc ... -O insn-emit-10.cc (10-way split)
    {
        const tool = tierB(c, sup, &early_incs, "genemit", "genemit.cc");
        const run = mdRun(c, tool, conditions_md);
        var i: usize = 1;
        while (i <= 10) : (i += 1) {
            const name = b.fmt("insn-emit-{d}.cc", .{i});
            emit(b, final, &files, name, run.addPrefixedOutputFileArg("-O", name));
        }
    }

    // --- Stage 7: genmatch (from the patched match.pd) ---
    // gencfn-macros produces case-cfn-macros.h (genmatch include) and
    // cfn-operators.pd (included by match.pd at line 58).
    const gencfn = standaloneTool(c, "gencfn-macros", &.{ "gencfn-macros.cc", "errors.cc", "hash-table.cc", "vec.cc", "ggc-none.cc", "sort.cc" }, &.{}, &condmd_incs, &.{});
    const case_cfn_h = runCapture(c, gencfn, &.{"-c"}, "case-cfn-macros.h");
    const cfn_operators_pd = runCapture(c, gencfn, &.{"-o"}, "cfn-operators.pd");

    // genmatch links libcpp + a few support objects (not the full support lib).
    const genmatch = b.addExecutable(.{
        .name = "genmatch",
        .root_module = b.createModule(.{ .target = build_target, .optimize = optimize, .link_libc = true }),
    });
    genmatch.root_module.link_libcpp = true;
    genmatch.root_module.addCSourceFiles(.{ .root = c.gcc_dir, .files = &.{ "genmatch.cc", "errors.cc", "vec.cc", "hash-table.cc", "sort.cc" }, .flags = &gen_flags });
    c.addBaseIncludes(genmatch.root_module);
    for (condmd_incs) |d| genmatch.root_module.addIncludePath(d);
    genmatch.root_module.addIncludePath(case_cfn_h.dirname());
    genmatch.root_module.linkLibrary(libcpp);
    genmatch.root_module.linkLibrary(iberty);

    // genmatch resolves match.pd's `#include "cfn-operators.pd"` via getpwd(),
    // so run it in an output dir that holds cfn-operators.pd.
    const match_pd = c.gcc_dir.path(b, "match.pd");
    const mrun = b.addSystemCommand(&.{
        "sh", "-c",
        \\set -e
        \\GM="$(realpath "$1")"; CFN="$2"; MPD="$(realpath "$3")"; OUT="$4"
        \\mkdir -p "$OUT"; cp "$CFN" "$OUT/cfn-operators.pd"; cd "$OUT"
        \\for v in gimple generic; do
        \\  set -- "$MPD"
        \\  args=""; i=1; while [ $i -le 10 ]; do args="$args $v-match-$i.cc"; i=$((i+1)); done
        \\  "$GM" --$v --header=$v-match-auto.h --include=$v-match-auto.h "$MPD" $args
        \\done
        ,
        "_",
    });
    mrun.addArtifactArg(genmatch);
    mrun.addFileArg(cfn_operators_pd);
    mrun.addFileArg(match_pd);
    const match_out = mrun.addOutputDirectoryArg("match-out");
    inline for (.{ "gimple", "generic" }) |prefix| {
        emit(b, final, &files, prefix ++ "-match-auto.h", match_out.path(b, prefix ++ "-match-auto.h"));
        var i: usize = 1;
        while (i <= 10) : (i += 1) {
            const name = b.fmt("{s}-match-{d}.cc", .{ prefix, i });
            emit(b, final, &files, name, match_out.path(b, name));
        }
    }

    // gengenrtl: genrtl.h (included by rtl.h).
    const gengenrtl = standaloneTool(c, "gengenrtl", &.{ "gengenrtl.cc", "errors.cc" }, &.{}, &.{ modes_inc, modes_inline_inc }, &.{});
    emit(b, final, &files, "genrtl.h", runCapture(c, gengenrtl, &.{}, "genrtl.h"));

    // genhooks: target-hooks-def.h + common/ + c-family/ variants (reads the
    // *.def hook descriptions via #include; just takes the hook-class name).
    const genhooks = standaloneTool(c, "genhooks", &.{ "genhooks.cc", "errors.cc" }, &.{}, &condmd_incs, &.{});
    emit(b, final, &files, "target-hooks-def.h", runCapture(c, genhooks, &.{"Target Hook"}, "target-hooks-def.h"));
    emit(b, final, &files, "common/common-target-hooks-def.h", runCapture(c, genhooks, &.{"Common Target Hook"}, "common-target-hooks-def.h"));
    emit(b, final, &files, "c-family/c-target-hooks-def.h", runCapture(c, genhooks, &.{"C Target Hook"}, "c-target-hooks-def.h"));

    // pass-instances.def via gen-pass-instances.awk over passes.def.
    const passes = b.addSystemCommand(&.{ "gawk", "-f" });
    passes.addFileArg(c.gcc_dir.path(b, "gen-pass-instances.awk"));
    passes.addFileArg(c.gcc_dir.path(b, "passes.def"));
    emit(b, final, &files, "pass-instances.def", passes.captureStdOut(.{ .trim_whitespace = .none, .basename = "pass-instances.def" }));

    // specs.h: language-specs aggregation (LTO only for a C cross-compiler).
    const aux_wf = b.addWriteFiles();
    _ = final.addCopyFile(aux_wf.add("specs.h", "#include \"lto/lang-specs.h\"\n"), "specs.h");
    // omp-device-properties.h: empty (no offload device).
    _ = final.addCopyFile(aux_wf.add("omp-device-properties.h",
        \\const char omp_offload_device_kind[] =
        \\"";
        \\const char omp_offload_device_arch[] =
        \\"";
        \\const char omp_offload_device_isa[] =
        \\"";
        \\
    ), "omp-device-properties.h");
    // plugin-version.h: plugin ABI version struct (from configargs.h + version).
    _ = final.addCopyFile(aux_wf.add("plugin-version.h", b.fmt(
        \\#include "configargs.h"
        \\
        \\#define GCCPLUGIN_VERSION_MAJOR   {[maj]d}
        \\#define GCCPLUGIN_VERSION_MINOR   {[min]d}
        \\#define GCCPLUGIN_VERSION_PATCHLEVEL   {[pat]d}
        \\#define GCCPLUGIN_VERSION  (GCCPLUGIN_VERSION_MAJOR*1000 + GCCPLUGIN_VERSION_MINOR)
        \\
        \\static char basever[] = "{[ver]s}";
        \\static char datestamp[] = "{[date]s}";
        \\static char devphase[] = "";
        \\static char revision[] = "";
        \\
        \\static struct plugin_gcc_version gcc_version = {{basever, datestamp,
        \\        devphase, revision,
        \\        configuration_arguments}};
        \\
    , .{ .maj = ver.major, .min = ver.minor, .pat = ver.patch, .ver = config.gcc_version, .date = config.gcc_datestamp })), "plugin-version.h");
    // cc1-checksum.cc: the executable_checksum cc1 stamps into any PCH it
    // creates and checks on load. It does not affect codegen. Upstream's
    // genchecksum derives it from the linked cc1 objects; we use a fixed value.
    // Caveat: a constant checksum means PCH files are not bound to a specific
    // cc1 build, so PCH created by one cc1 would be accepted by a different
    // one. Acceptable here (this toolchain targets bare-metal firmware and is
    // not expected to produce/consume PCH); revisit with a real genchecksum
    // pass if PCH support is ever needed.
    _ = final.addCopyFile(aux_wf.add("cc1-checksum.cc",
        \\#include "config.h"
        \\#include "system.h"
        \\EXPORTED_CONST unsigned char executable_checksum[16] = { 0 };
        \\
    ), "cc1-checksum.cc");

    // multilib.h via the genmultilib shell script (args from the t-<cpu> fragment).
    const mlib = b.addSystemCommand(&.{"sh"});
    mlib.addFileArg(c.gcc_dir.path(b, "genmultilib"));
    for (config.multilib_genargs) |a| mlib.addArg(a);
    emit(b, final, &files, "multilib.h", mlib.captureStdOut(.{ .trim_whitespace = .none, .basename = "multilib.h" }));

    // Intermediate generated headers cc1/driver also include directly.
    emit(b, final, &files, "all-tree.def", alltree_inc.path(b, "all-tree.def"));
    emit(b, final, &files, "bversion.h", bversion_inc.path(b, "bversion.h"));
    emit(b, final, &files, "tree-check.h", tree_check_h);
    emit(b, final, &files, "tm_p.h", tm_p_inc.path(b, "tm_p.h"));
    emit(b, final, &files, "case-cfn-macros.h", case_cfn_h);

    return .{ .dir = final.getDirectory(), .gt_dir = gtype_dir, .files = files.items };
}

/// Register a `gen-verify` step that diffs each generated file's captured
/// LazyPath against the vendored oracle, proving byte-identical generation.
/// Diffs are per-file (not via the assembled dir) so independent outputs verify
/// even while later stages are still being brought up. If `only` is non-empty,
/// only those names are checked; otherwise every recorded file is.
pub fn addVerify(
    b: *std.Build,
    generated: Generated,
    oracle_dir: std.Build.LazyPath,
    only: []const []const u8,
) void {
    const verify_step = b.step("gen-verify", "Diff build-time generated files against the vendored oracle");
    for (generated.files) |nf| {
        if (only.len != 0) {
            var wanted = false;
            for (only) |o| {
                if (std.mem.eql(u8, o, nf.name)) wanted = true;
            }
            if (!wanted) continue;
        }
        // Normalize embedded source paths before diffing: generators bake the
        // .md/program path into provenance comments and #line directives, which
        // are environment-specific (the vendored oracle even carries a stale
        // machine path). Canonicalize "<dirs>/gcc/" -> "gcc/" and strip the
        // directory from the "gen*" program name so only semantic content is
        // compared.
        const diff = b.addSystemCommand(&.{
            "sh", "-c",
            \\set -e
            \\A=$(mktemp); B=$(mktemp)
            \\sed -E -e 's#[^ "]*/(gcc/)#\1#g' -e 's#[^ ]*/(gen[a-z-]+'\'')#\1#g' "$1" > "$A"
            \\sed -E -e 's#[^ "]*/(gcc/)#\1#g' -e 's#[^ ]*/(gen[a-z-]+'\'')#\1#g' "$2" > "$B"
            \\diff -u "$A" "$B"; rc=$?; rm -f "$A" "$B"; exit $rc
            ,
            "_",
        });
        diff.addFileArg(oracle_dir.path(b, nf.name));
        diff.addFileArg(nf.file);
        verify_step.dependOn(&diff.step);
    }
}
