const std = @import("std");
const builtin = @import("builtin");

const zon = @import("build.zig.zon");
const zigbuildx = @import("zigbuildx");
const zigui_build = @import("zigui");

/// The names, paths, target, and version every build step is declared from.
const Config = struct {
    const Self = @This();

    name: []const u8,
    mod_name: []const u8,
    gallery_name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    module_source_file: std.Build.LazyPath,
    version: std.SemanticVersion,
};

/// What `linkApp` builds the SDL runtime for: zigui's options, unchanged.
pub const AppOptions = zigui_build.AppOptions;

/// Declares the build graph for the ziggui library, gallery, tests, and docs.
///
/// Serves as the entry point the Zig build runner invokes to wire up every
/// build step consumers rely on — `lib`, `test`, and `docs`, plus `gallery`
/// and `run-gallery` when ziggui is the root build — and the standard target,
/// optimize, and test-filter options. The `ziggui` module imports zigui's
/// core, which it re-exports; apps depend on ziggui alone. On macOS it adds
/// the resolved SDK framework path so linking succeeds. Called once per build
/// invocation.
///
/// - `b`: the build graph the steps and options are registered on.
/// - Returns: nothing on success; propagates errors from option parsing, version
///   parsing, and macOS SDK resolution.
pub fn build(b: *std.Build) !void {
    // Pre-flight: ensure any local dependencies are cloned
    zigbuildx.Deps.cloneMissing(b, zon);

    // Build config
    const cfg = Config{
        .name = @tagName(zon.name),
        .mod_name = @tagName(zon.name),
        .gallery_name = @tagName(zon.name) ++ "-gallery",
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .module_source_file = b.path("src/module.zig"),
        .version = try std.SemanticVersion.parse(zon.version),
    };

    // Build options
    const options = b.addOptions();

    const test_filter = b.option([]const u8, "test-filter", "Run unit tests that match filter") orelse "";
    options.addOption([]const u8, "test_filter", test_filter);

    // -------------------------------------------------------------------------
    // Module
    //
    // ziggui re-exports zigui's core beside its own widgets. The zigui
    // dependency is declared with the same arguments `linkApp` uses, so the
    // app runtime and this module share one zigui module (and its types).

    const zigui_dep = b.dependency("zigui", .{
        .target = cfg.target,
        .optimize = cfg.optimize,
    });

    const module = b.addModule(cfg.name, .{
        .root_source_file = cfg.module_source_file,
        .target = cfg.target,
        .optimize = cfg.optimize,
    });
    module.addOptions("config", options);
    module.addImport("zigui", zigui_dep.module("zigui"));

    // -------------------------------------------------------------------------
    // Lib

    const lib = b.addLibrary(.{ .name = cfg.name, .root_module = module, .linkage = .static });

    if (builtin.os.tag == .macos) {
        var xcode = try zigbuildx.Xcode.init(b);
        try xcode.resolve();
        xcode.addFrameworkPath(lib.root_module);
    }

    const lib_install = b.addInstallArtifact(lib, .{});
    const lib_step = b.step("lib", "Build static library");
    lib_step.dependOn(&lib_install.step);
    b.getInstallStep().dependOn(&lib_install.step);

    // -------------------------------------------------------------------------
    // Gallery
    //
    // The component gallery (`gallery/`), drawn by zigui. Its views build and
    // test headless on the `ziggui` module; only the executable links SDL3,
    // through `linkApp`. As zigui does for its showcase, the executable is
    // declared only when ziggui is the root build, so a package depending on
    // ziggui never fetches or builds SDL for it.

    const gallery_module = b.createModule(.{
        .root_source_file = b.path("gallery/module.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
    });
    gallery_module.addImport(cfg.mod_name, module);

    if (b.dep_prefix.len == 0) try addGallery(b, cfg, gallery_module, module);

    // -------------------------------------------------------------------------
    // Tests

    const tests = b.addTest(.{
        .root_module = module,
    });

    const tests_run = b.addRunArtifact(tests);
    // force tests to run on every test run
    tests_run.has_side_effects = true;

    const tests_step = b.step("test", "Run unit tests");
    tests_step.dependOn(&tests_run.step);

    // The gallery's views run headless on zigui's core: no SDL, no window.
    const gallery_tests = b.addTest(.{
        .root_module = gallery_module,
    });

    const gallery_tests_run = b.addRunArtifact(gallery_tests);
    gallery_tests_run.has_side_effects = true;
    tests_step.dependOn(&gallery_tests_run.step);

    // -------------------------------------------------------------------------
    // Docs

    // Autodoc roots a module at `root.zig`, or failing that at the file whose
    // basename matches the artifact name; with `src/module.zig` it can do
    // neither, and the site roots itself at an arbitrary import instead.
    // ZIGSTYLE requires the barrel to be `module.zig`, so docs build from a
    // sibling `root.zig`. It is the same module — the other sources come along.
    const docs_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
    });
    docs_mod.addOptions("config", options);
    docs_mod.addImport("zigui", zigui_dep.module("zigui"));

    const docs_lib = b.addLibrary(.{
        .name = cfg.name,
        .root_module = docs_mod,
        .linkage = .static,
    });

    if (builtin.os.tag == .macos) {
        var docs_xcode = try zigbuildx.Xcode.init(b);
        try docs_xcode.resolve();
        docs_xcode.addFrameworkPath(docs_lib.root_module);
    }

    const docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);
}

/// The SDL3-backed app runtime for a package that depends on ziggui.
///
/// Import the result as `ziggui_app` beside `dep.module("ziggui")`. It is
/// zigui's runtime, built on the same zigui module ziggui re-exports, so the
/// two agree on every type; SDL3 is fetched lazily, on first use.
///
///     const ziggui_dep = b.dependency("ziggui", .{ .target = target, .optimize = optimize });
///     const app_mod = @import("ziggui").linkApp(ziggui_dep, .{ .target = target, .optimize = optimize });
///     exe.root_module.addImport("ziggui", ziggui_dep.module("ziggui"));
///     exe.root_module.addImport("ziggui_app", app_mod);
///
/// - `dep`: the ziggui dependency, as `b.dependency("ziggui", ...)` returns it.
/// - `opts`: the target, optimize mode, and SDK the runtime is built for; pass
///   the target and optimize mode the dependency was declared with.
/// - Returns: the runtime module.
pub fn linkApp(dep: *std.Build.Dependency, opts: AppOptions) *std.Build.Module {
    const zigui_dep = dep.builder.dependency("zigui", .{
        .target = opts.target,
        .optimize = opts.optimize,
    });
    return zigui_build.linkApp(zigui_dep, opts);
}

/// Declares the gallery executable and its `gallery` and `run-gallery` steps.
///
/// The executable links SDL3 through `linkApp`'s runtime, so declaring it
/// fetches SDL; `build` calls this only when ziggui is the root build. Neither
/// step is part of the default install.
///
/// - `b`: the build graph.
/// - `cfg`: the build's configuration.
/// - `gallery_module`: the gallery's views (`gallery/module.zig`).
/// - `module`: the `ziggui` module.
/// - Returns: nothing on success; propagates macOS SDK resolution failure.
fn addGallery(
    b: *std.Build,
    cfg: Config,
    gallery_module: *std.Build.Module,
    module: *std.Build.Module,
) !void {
    // An explicit macOS target needs the SDK spelled out for AppKit and Metal.
    const xcode = try zigbuildx.Xcode.initFor(b, cfg.target);
    const zigui_dep = b.dependency("zigui", .{
        .target = cfg.target,
        .optimize = cfg.optimize,
    });
    const app_module = zigui_build.linkApp(zigui_dep, .{
        .target = cfg.target,
        .optimize = cfg.optimize,
        .macos_sdk = if (xcode.loaded) xcode.sdk else null,
    });

    const gallery = b.addExecutable(.{
        .name = cfg.gallery_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("gallery/main.zig"),
            .target = cfg.target,
            .optimize = cfg.optimize,
            .link_libc = true,
        }),
    });
    gallery.root_module.addImport("gallery", gallery_module);
    gallery.root_module.addImport(cfg.mod_name, module);
    gallery.root_module.addImport("ziggui_app", app_module);

    const gallery_install = b.addInstallArtifact(gallery, .{});
    const gallery_step = b.step("gallery", "Build the component gallery");
    gallery_step.dependOn(&gallery_install.step);

    // Support arguments like: `zig build run-gallery -- --dark`
    const gallery_run = b.addRunArtifact(gallery);
    gallery_run.step.dependOn(&gallery_install.step);
    gallery_run.addPassthruArgs();

    const gallery_run_step = b.step("run-gallery", "Run the component gallery");
    gallery_run_step.dependOn(&gallery_run.step);
}
