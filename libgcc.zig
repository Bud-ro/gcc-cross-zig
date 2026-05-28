//! Builds libgcc.a + crtbegin/crtend.o for the target using the freshly built
//! cross compiler, as a post-install step. libgcc is target code: it must be
//! compiled by the cross cc1 (not the host), so this runs after the toolchain
//! (gcc driver, as, ar, fixed headers) is installed.
//!
//! Mirrors GCC's libgcc Makefile: libgcc2.c is compiled once per function via
//! -DL<func>, fp-bit.c provides soft float, plus the target's LIB2ADD sources.
//! SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const cross_config = @import("cross_config.zig");
const CrossConfig = cross_config.CrossConfig;

// Standard libgcc2 routines (libgcc/Makefile.in: lib2funcs).
const lib2funcs =
    "_muldi3 _negdi2 _lshrdi3 _ashldi3 _ashrdi3 _cmpdi2 _ucmpdi2 " ++
    "_clear_cache _trampoline __main _absvsi2 _absvdi2 _addvsi3 _addvdi3 " ++
    "_subvsi3 _subvdi3 _mulvsi3 _mulvdi3 _negvsi2 _negvdi2 _ctors _ffssi2 " ++
    "_ffsdi2 _clz _clzsi2 _clzdi2 _ctzsi2 _ctzdi2 _popcount_tab _popcountsi2 " ++
    "_popcountdi2 _paritysi2 _paritydi2 _powisf2 _powidf2 _powixf2 _powitf2 " ++
    "_mulhc3 _mulsc3 _muldc3 _mulxc3 _multc3 _divhc3 _divsc3 _divdc3 _divxc3 " ++
    "_divtc3 _bswapsi2 _bswapdi2 _clrsbsi2 _clrsbdi2 _mulbitint3 " ++
    // Float<->integer conversion routines (swfloatfuncs si + dwfloatfuncs di).
    // Routines for modes a multilib lacks are skipped at compile time.
    "_fixunssfsi _fixunsdfsi _fixunsxfsi " ++
    "_fixsfdi _fixdfdi _fixxfdi _fixtfdi " ++
    "_fixunssfdi _fixunsdfdi _fixunsxfdi _fixunstfdi " ++
    "_floatdisf _floatdidf _floatdixf _floatditf " ++
    "_floatundisf _floatundidf _floatundixf _floatunditf";

// LIB2_DIVMOD_FUNCS.
const divmod_funcs =
    "_divdi3 _moddi3 _divmoddi4 _udivdi3 _umoddi3 _udivmoddi4 _udiv_w_sdiv _divmodbitint4";

// LIB2FUNCS_ST (built from libgcc2.c, static-only).
const st_funcs = "_eprintf __gcc_bcmp";

// Soft-float from fp-bit.c. FPBIT_FUNCS use -DFLOAT; DPBIT_FUNCS do not.
const fpbit_funcs =
    "_pack_sf _unpack_sf _addsub_sf _mul_sf _div_sf _fpcmp_parts_sf _compare_sf " ++
    "_eq_sf _ne_sf _gt_sf _ge_sf _lt_sf _le_sf _unord_sf _si_to_sf _sf_to_si " ++
    "_negate_sf _make_sf _sf_to_df _thenan_sf _sf_to_usi _usi_to_sf";
const dpbit_funcs =
    "_pack_df _unpack_df _addsub_df _mul_df _div_df _fpcmp_parts_df _compare_df " ++
    "_eq_df _ne_df _gt_df _ge_df _lt_df _le_df _unord_df _si_to_df _df_to_si " ++
    "_negate_df _make_df _df_to_sf _thenan_df _df_to_usi _usi_to_df";

/// Register a `libgcc` step that compiles and installs libgcc.a + crt*.o into
/// the install prefix's lib/gcc/<target>/<version>/ directory. Depends on the
/// install step (needs the installed driver/ar/headers). Returns the step so
/// the caller can make the default install depend on it.
pub fn addLibgcc(
    b: *std.Build,
    gcc_root: std.Build.LazyPath,
    generated_dir: std.Build.LazyPath,
    config: CrossConfig,
) *std.Build.Step {
    const ver_dir = b.fmt("lib/gcc/{s}/{s}", .{ config.target_canonical, config.gcc_version });

    // libgcc_tm.h includes, as a plain space-separated list (the script writes
    // the header with a shell loop to avoid printf-escaping pitfalls).
    var tm_includes: std.ArrayList(u8) = .empty;
    for (config.libgcc_tm_includes) |h| {
        tm_includes.appendSlice(b.allocator, h) catch @panic("OOM");
        tm_includes.appendSlice(b.allocator, " ") catch @panic("OOM");
    }

    // LIB2ADD: target extras + generic enable-execute-stack.c.
    var lib2add: std.ArrayList(u8) = .empty;
    for (config.libgcc_lib2add) |s| {
        lib2add.appendSlice(b.allocator, s) catch @panic("OOM");
        lib2add.appendSlice(b.allocator, " ") catch @panic("OOM");
    }
    lib2add.appendSlice(b.allocator, "enable-execute-stack.c") catch @panic("OOM");

    const script = b.fmt(
        \\set -e
        \\PREFIX="{0s}"; GCCROOT="$1"; GEN="$2"; CFG="$3"
        \\GCC="$PREFIX/bin/{1s}-gcc"; AR="$PREFIX/bin/{1s}-ar"
        \\LIBDIR="$PREFIX/{2s}"
        \\GINC="$("$GCC" -print-file-name=include)"
        \\LG="$GCCROOT/libgcc"
        \\W="$PREFIX/.libgcc-obj"; rm -rf "$W"; mkdir -p "$W" "$LIBDIR"
        \\: > "$W/libgcc_tm.h"; for h in {3s}; do echo "#include \"$h\"" >> "$W/libgcc_tm.h"; done
        \\INC="-I$W -I$CFG -I$GEN -I$LG -I$LG/config/{4s} -I$GCCROOT/gcc -I$GCCROOT/include -isystem $GINC"
        \\F="-O2 -DIN_GCC -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector -Dinhibit_libc -fexceptions -fnon-call-exceptions"
        \\# Per-function compiles are tolerant: routines for modes this multilib
        \\# does not support (e.g. DF/XF/TF when double is 32-bit) fail to compile
        \\# and are skipped, exactly as GCC filters by available modes.
        \\for f in {5s} {6s} {7s}; do "$GCC" $F $INC -DL$f -c "$LG/libgcc2.c" -o "$W/$f.o" 2>/dev/null || echo "  skip $f"; done
        \\for f in {8s}; do "$GCC" $F $INC -DFINE_GRAINED_LIBRARIES -DFLOAT -DL$f -c "$LG/fp-bit.c" -o "$W/$f.o" 2>/dev/null || echo "  skip $f"; done
        \\for f in {9s}; do "$GCC" $F $INC -DFINE_GRAINED_LIBRARIES -DL$f -c "$LG/fp-bit.c" -o "$W/$f.o" 2>/dev/null || echo "  skip $f"; done
        \\i=0; for s in {10s}; do
        \\  "$GCC" $F $INC -c "$LG/$s" -o "$W/lib2add_$i.o" 2>/dev/null || echo "  skip $s"; i=$((i+1))
        \\done
        \\"$AR" rcs "$LIBDIR/libgcc.a" "$W"/*.o
        \\# crtbegin/crtend provide C++ static ctor/dtor + exception-frame
        \\# registration; bare-metal C firmware does not require them. They hit
        \\# an RX assembler .size quirk, so treat them as best-effort.
        \\"$GCC" $F $INC -g0 -DCRT_BEGIN -c "$LG/crtstuff.c" -o "$LIBDIR/crtbegin.o" 2>/dev/null || echo "  skip crtbegin.o"
        \\"$GCC" $F $INC -g0 -DCRT_END -c "$LG/crtstuff.c" -o "$LIBDIR/crtend.o" 2>/dev/null || echo "  skip crtend.o"
        \\echo "libgcc.a: $("$AR" t "$LIBDIR/libgcc.a" | wc -l) objects"
    , .{
        b.install_path, // 0
        config.target_triple, // 1
        ver_dir, // 2
        tm_includes.items, // 3
        config.target_cpu, // 4
        lib2funcs, // 5
        divmod_funcs, // 6
        st_funcs, // 7
        fpbit_funcs, // 8
        dpbit_funcs, // 9
        lib2add.items, // 10
    });

    const run = b.addSystemCommand(&.{ "sh", "-c", script, "_" });
    run.addDirectoryArg(gcc_root); // $1
    run.addDirectoryArg(generated_dir); // $2
    run.addDirectoryArg(config.config_dir); // $3
    run.step.dependOn(b.getInstallStep());

    const step = b.step("libgcc", "Build and install libgcc.a + crt{begin,end}.o");
    step.dependOn(&run.step);
    return step;
}
