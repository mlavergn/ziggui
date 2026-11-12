const std = @import("std");
const log = std.log.scoped(.ziggui_build);
const builtin = @import("builtin");

const zon = @import("build.zig.zon");
const zigbuildx = @import("zigbuildx");
const sdl_build = @import("build/sdl_build.zig");

/// The names, paths, target, and version every build step is declared from.
const Config = struct {
    const Self = @This();

    name: []const u8,
    gallery_name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    version: std.SemanticVersion,
};

/// What `linkApp` builds the SDL runtime for.
pub const AppOptions = struct {
    const Self = @This();

    /// The target the app is built for; the one the dependency was declared with.
    target: std.Build.ResolvedTarget,
    /// The optimize mode the app is built with; the one the dependency was declared with.
    optimize: std.lang.Optimize,
    /// The macOS SDK root (`xcrun --show-sdk-path`), needed whenever macOS is
    /// an explicit `-Dtarget`; null lets Zig probe the host's.
    macos_sdk: ?[]const u8 = null,
    /// A prebuilt SDL3 (`include/` and `lib/` inside) instead of building it
    /// from the release.
    sdl3_prefix: ?[]const u8 = null,
};

/// The modules every ziggui build shares: the renderer, the views over it, and
/// the core `ziggui` barrel over both. The app `ziggui` (`linkApp`) reuses the
/// first two, so a type is the same type in either barrel.
const Modules = struct {
    const Self = @This();

    /// The name the renderer module is registered under, for `linkApp`.
    const renderer_name = "ziggui_renderer";
    /// The name the views module is registered under, for `linkApp`.
    const views_name = "ziggui_views";
    /// The name the app barrel is memoized under, so `linkApp` builds it once.
    const app_name = "ziggui_app_barrel";
    /// The name the SDL runtime module is memoized under, beside the app barrel.
    const runtime_name = "ziggui_sdl_runtime";

    /// The options each build graph's app barrel was built with, so a later
    /// `linkApp` call that passes others fails instead of getting a barrel
    /// built for the first call's.
    var app_options: std.AutoHashMapUnmanaged(*std.Build, AppOptions) = .empty;

    renderer: *std.Build.Module,
    views: *std.Build.Module,
    core: *std.Build.Module,

    /// Declare the renderer, views and core `ziggui` modules.
    ///
    /// - `b`: ziggui's build graph.
    /// - `config`: the build's configuration.
    /// - Returns: the three modules.
    fn init(b: *std.Build, config: Config) Self {
        const renderer = b.addModule(Self.renderer_name, .{
            .root_source_file = b.path("src/renderer/module.zig"),
            .target = config.target,
            .optimize = config.optimize,
        });
        Self.addFonts(b, renderer);

        const views = b.addModule(Self.views_name, .{
            .root_source_file = b.path("src/views/module.zig"),
            .target = config.target,
            .optimize = config.optimize,
            .imports = &.{.{ .name = "renderer", .module = renderer }},
        });

        const core = b.addModule(config.name, .{
            .root_source_file = b.path("src/module.zig"),
            .target = config.target,
            .optimize = config.optimize,
            .imports = &.{
                .{ .name = "renderer", .module = renderer },
                .{ .name = "views", .module = views },
            },
        });
        core.addOptions("config", Self.barrelOptions(b, false));

        const self = Self{ .renderer = renderer, .views = views, .core = core };
        return self;
    }

    /// The app `ziggui`: the core barrel plus the SDL runtime, built once per
    /// build graph and memoized there. Panics when `options` builds for
    /// another target or optimize mode than the graph's renderer, or differs
    /// from the options an earlier call built the barrel with.
    ///
    /// - `b`: ziggui's build graph (the dependency's, from `linkApp`).
    /// - `options`: the target, optimize mode, SDK and SDL source.
    /// - Returns: the app `ziggui` module.
    fn app(b: *std.Build, options: AppOptions) *std.Build.Module {
        const renderer = b.modules.get(Self.renderer_name).?;
        const views = b.modules.get(Self.views_name).?;
        Self.expectSameBuild(renderer.resolved_target.?, renderer.optimize.?, options);
        if (b.modules.get(Self.app_name)) |built| {
            // The first call passed the renderer's check too, so target and
            // optimize mode already agree with it.
            const first = Self.app_options.get(b).?;
            Self.expectSamePath("macos_sdk", first.macos_sdk, options.macos_sdk);
            Self.expectSamePath("sdl3_prefix", first.sdl3_prefix, options.sdl3_prefix);
            return built;
        }

        // SDL's headers come in through translate-c (`@cImport` is gone in Zig 0.17).
        const sdl_c = b.addTranslateC(.{
            .root_source_file = b.path("src/sdl/c.h"),
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
        });
        const sdl = b.createModule(.{
            .root_source_file = b.path("src/sdl/module.zig"),
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "renderer", .module = renderer },
                .{ .name = "views", .module = views },
                .{ .name = "sdl_c", .module = sdl_c.createModule() },
            },
        });
        Self.linkSdl(b, sdl, sdl_c, options);
        // cocoa.zig reaches AppKit (the unified title bar, the menu bar, template
        // tray icons) through the Objective-C runtime.
        if (options.target.result.os.tag == .macos) {
            if (options.macos_sdk) |sdk| Self.addMacosSdk(b, sdl, sdk);
            sdl.linkSystemLibrary("objc", .{});
        }

        const barrel = b.createModule(.{
            .root_source_file = b.path("src/module.zig"),
            .target = options.target,
            .optimize = options.optimize,
            .imports = &.{
                .{ .name = "renderer", .module = renderer },
                .{ .name = "views", .module = views },
                .{ .name = "sdl", .module = sdl },
            },
        });
        barrel.addOptions("config", Self.barrelOptions(b, true));
        b.modules.put(b.graph.arena, Self.runtime_name, sdl) catch @panic("oom");
        b.modules.put(b.graph.arena, Self.app_name, barrel) catch @panic("oom");
        Self.app_options.put(b.graph.arena, b, options) catch @panic("oom");
        return barrel;
    }

    /// The SDL runtime module (`src/sdl`) the app `ziggui` imports as `sdl`,
    /// built and linked by `app`, under the same checks and memoization.
    ///
    /// - `b`: ziggui's build graph.
    /// - `options`: the target, optimize mode, SDK and SDL source.
    /// - Returns: the SDL runtime module.
    fn runtime(b: *std.Build, options: AppOptions) *std.Build.Module {
        _ = Self.app(b, options);
        return b.modules.get(Self.runtime_name).?;
    }

    /// Panic unless `options` builds for `target` with `optimize`: one ziggui
    /// build graph builds one renderer, for one target and optimize mode.
    ///
    /// - `target`: the target the dependency was declared with.
    /// - `optimize`: the optimize mode the dependency was declared with.
    /// - `options`: the options `linkApp` was given.
    fn expectSameBuild(target: std.Build.ResolvedTarget, optimize: std.lang.Optimize, options: AppOptions) void {
        const built = &target.result;
        const wanted = &options.target.result;
        const same_target = built.cpu.arch == wanted.cpu.arch and built.os.tag == wanted.os.tag and built.abi == wanted.abi;
        if (same_target and optimize == options.optimize) return;
        std.debug.panic(
            "ziggui linkApp: target {t}-{t}-{t} and optimize {t} differ from the {t}-{t}-{t} and {t} the dependency was declared with; " ++
                "pass b.dependency(\"ziggui\", ...) and every linkApp call the same .target and .optimize",
            .{ wanted.cpu.arch, wanted.os.tag, wanted.abi, options.optimize, built.cpu.arch, built.os.tag, built.abi, optimize },
        );
    }

    /// Panic unless a later `linkApp` call passes the path option the first did.
    ///
    /// - `name`: the option's name, for the message.
    /// - `first`: what the first call passed.
    /// - `later`: what this call passes.
    fn expectSamePath(comptime name: []const u8, first: ?[]const u8, later: ?[]const u8) void {
        const same = if (first != null and later != null) std.mem.eql(u8, first.?, later.?) else first == null and later == null;
        if (same) return;
        std.debug.panic("ziggui linkApp: .{s} = {?s} differs from the {?s} an earlier linkApp call passed; pass every call the same .{s}", .{ name, later, first, name });
    }

    /// Adds the bundled fonts (Inter and JetBrains Mono, OFL; Lucide, ISC; Noto
    /// Emoji, OFL) to a renderer module as the anonymous imports
    /// `text/ttf_font.zig` and `text/font_set.zig` embed.
    ///
    /// - `b`: ziggui's build graph.
    /// - `renderer`: a module rooted at the renderer's barrel.
    fn addFonts(b: *std.Build, renderer: *std.Build.Module) void {
        for ([_][2][]const u8{
            .{ "inter_font", "Inter.ttf" },
            .{ "inter_medium", "Inter-Medium.ttf" },
            .{ "inter_semibold", "Inter-SemiBold.ttf" },
            .{ "inter_bold", "Inter-Bold.ttf" },
            .{ "inter_italic", "Inter-Italic.ttf" },
            .{ "inter_bold_italic", "Inter-BoldItalic.ttf" },
            .{ "mono_regular", "JetBrainsMono-Regular.ttf" },
            .{ "mono_bold", "JetBrainsMono-Bold.ttf" },
            .{ "icon_font", "lucide.ttf" },
            .{ "emoji_font", "NotoEmoji.ttf" },
        }) |font| renderer.addAnonymousImport(font[0], .{ .root_source_file = b.path(b.fmt("assets/fonts/{s}", .{font[1]})) });
    }

    /// The `config` options the barrel reads: the version and whether the SDL
    /// runtime is there.
    ///
    /// - `b`: ziggui's build graph.
    /// - `with_sdl`: whether this is the app barrel.
    /// - Returns: the options step.
    fn barrelOptions(b: *std.Build, with_sdl: bool) *std.Build.Step.Options {
        const options = b.addOptions();
        options.addOption([]const u8, "version", zon.version);
        options.addOption(bool, "with_sdl", with_sdl);
        return options;
    }

    /// Link SDL3 into the runtime: built from the release by default, or a
    /// prebuilt one from `sdl3_prefix`. On the first configure the lazy
    /// dependency may not be fetched yet; the module is left unlinked and the
    /// build reruns once it is there.
    ///
    /// - `b`: ziggui's build graph.
    /// - `sdl`: the runtime module.
    /// - `sdl_c`: the translate-c step for SDL's headers.
    /// - `options`: the target, optimize mode, SDK and SDL source.
    fn linkSdl(b: *std.Build, sdl: *std.Build.Module, sdl_c: *std.Build.Step.TranslateC, options: AppOptions) void {
        if (options.sdl3_prefix) |prefix| {
            sdl.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{prefix}) });
            sdl.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{prefix}) });
            sdl.addRPath(.{ .cwd_relative = b.fmt("{s}/lib", .{prefix}) });
            sdl_c.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{prefix}) });
            // Not through pkg-config, which can find a system SDL3 before the prefix's.
            sdl.linkSystemLibrary("SDL3", .{ .use_pkg_config = .no });
            return;
        }
        const library = sdl_build.SdlBuild.library(b, .{
            .target = options.target,
            .optimize = options.optimize,
            .macos_sdk = options.macos_sdk,
        }) orelse return;
        sdl.linkLibrary(library);
        sdl_c.addIncludePath(library.getEmittedIncludeTree());
    }

    /// Point a module at a macOS SDK's headers, frameworks and libraries,
    /// which Zig does not probe for an explicit macOS target.
    ///
    /// - `b`: ziggui's build graph.
    /// - `module`: the module to point.
    /// - `sdk`: the SDK root.
    fn addMacosSdk(b: *std.Build, module: *std.Build.Module, sdk: []const u8) void {
        module.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{sdk}) });
        module.addSystemFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sdk}) });
        module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/usr/lib", .{sdk}) });
    }
};

/// The steps built on ziggui's own SDL runtime, the gallery and `test-sdl`,
/// declared only when ziggui is the root build.
const AppSteps = struct {
    const Self = @This();

    /// Reads the SDL options and declares the gallery's steps and `test-sdl`.
    ///
    /// Both build on the SDL runtime, so declaring them fetches SDL; `build`
    /// calls this only when ziggui is the root build. For a target SDL does
    /// not build for (macOS, Windows and Linux only) the steps are left out,
    /// so `lib` and `test` still configure.
    ///
    /// - `b`: the build graph.
    /// - `config`: the build's configuration.
    /// - `filters`: the `-Dtest-filter` filters `test-sdl` passes on.
    /// - Returns: nothing on success; propagates macOS SDK resolution failure.
    fn declare(b: *std.Build, config: Config, filters: []const []const u8) !void {
        const sdl3_prefix = b.option([]const u8, "sdl3-prefix", "SDL3 install prefix (include/ and lib/ inside) instead of building the release");
        // Windows executables are GUI-subsystem by default so launching one opens
        // no console; `-Dwindows-console` keeps it (log output, `--screenshot`).
        const windows_console = b.option(bool, "windows-console", "Build the Windows gallery as a console app (shows log output)") orelse false;
        switch (config.target.result.os.tag) {
            .macos, .windows, .linux => {},
            else => |os| {
                log.info("no gallery or test-sdl for {t}: SDL3 builds for macOS, Windows and Linux only", .{os});
                return;
            },
        }
        // An explicit macOS target needs the SDK spelled out for AppKit and Metal.
        const xcode = try zigbuildx.Xcode.initFor(b, config.target);
        const options = AppOptions{
            .target = config.target,
            .optimize = config.optimize,
            .macos_sdk = if (xcode.loaded) xcode.sdk else null,
            .sdl3_prefix = sdl3_prefix,
        };
        Gallery.declare(b, config, options, windows_console);
        SdlTests.declare(b, config, options, filters);
    }
};

/// The gallery executable and its steps.
const Gallery = struct {
    const Self = @This();

    /// Declares the gallery executable and its `gallery` and `run-gallery` steps.
    ///
    /// The executable builds the gallery on the app `ziggui`, which links SDL3.
    /// Neither step is part of the default install.
    ///
    /// - `b`: the build graph.
    /// - `config`: the build's configuration.
    /// - `options`: the app `ziggui`'s target, optimize mode, SDK and SDL source.
    /// - `windows_console`: whether a Windows gallery keeps its console.
    fn declare(b: *std.Build, config: Config, options: AppOptions, windows_console: bool) void {
        const app_module = Modules.app(b, options);

        const gallery_module = b.createModule(.{
            .root_source_file = b.path("gallery/module.zig"),
            .target = config.target,
            .optimize = config.optimize,
            .imports = &.{.{ .name = config.name, .module = app_module }},
        });

        const gallery = b.addExecutable(.{
            .name = config.gallery_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("gallery/main.zig"),
                .target = config.target,
                .optimize = config.optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "gallery", .module = gallery_module },
                    .{ .name = config.name, .module = app_module },
                },
            }),
        });
        // The app icon (assets/icon): on Windows the multi-size .ico is embedded
        // as a resource for Explorer, the title bar and the taskbar.
        if (config.target.result.os.tag == .windows) {
            gallery.root_module.addWin32ResourceFile(.{ .file = b.path("assets/icon/ziggui.rc") });
            if (!windows_console) gallery.subsystem = .windows;
        }

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
};

/// The SDL runtime's unit tests, which `zig build test` never builds: it
/// stays headless and never compiles or links SDL.
const SdlTests = struct {
    const Self = @This();

    /// Declares `test-sdl`: one test compile rooted at the SDL runtime module,
    /// built and linked as for an app. For the host's OS and CPU it runs the
    /// tests; for any other `-Dtarget` it only compiles and links them, which
    /// checks that platform's code (`-Dtarget=x86_64-windows`,
    /// `x86_64-linux-gnu`). Not a dependency of `test`.
    ///
    /// - `b`: the build graph.
    /// - `config`: the build's configuration.
    /// - `options`: the app `ziggui`'s target, optimize mode, SDK and SDL source.
    /// - `filters`: the `-Dtest-filter` filters.
    fn declare(b: *std.Build, config: Config, options: AppOptions, filters: []const []const u8) void {
        const tests = b.addTest(.{
            .name = b.fmt("{s}-sdl-test", .{config.name}),
            .root_module = Modules.runtime(b, options),
            .filters = filters,
        });
        const tests_step = b.step("test-sdl", "Run the SDL runtime's unit tests (compile them only for a foreign -Dtarget)");
        const host = &b.graph.host.result;
        const wanted = &config.target.result;
        if (host.os.tag != wanted.os.tag or host.cpu.arch != wanted.cpu.arch) {
            // Asking for the binary makes the compile generate and link it
            // too; with no one asking, it would only analyze.
            _ = tests.getEmittedBin();
            tests_step.dependOn(&tests.step);
            return;
        }
        const tests_run = b.addRunArtifact(tests);
        // force tests to run on every test run
        tests_run.has_side_effects = true;
        tests_step.dependOn(&tests_run.step);
    }
};

/// The `docs` step: the generated API site, rooted as zigstorage roots its own.
const Docs = struct {
    const Self = @This();

    /// Declares the `docs` step.
    ///
    /// Autodoc roots a module at its `root.zig`, or failing that at the file
    /// named for the module, or failing that at whichever of its files comes
    /// first. ZIGSTYLE names every barrel `module.zig`, so the site starts at
    /// `src/root.zig`, which re-exports the barrel (as zigstorage's does). The
    /// barrel re-exports from the `renderer` and `views` modules, whose own
    /// barrels autodoc would miss the same way and resolve `views.View`
    /// against an arbitrary file; so the docs build those two from a staged
    /// copy of their sources with each barrel also saved as `root.zig`. The
    /// site is then patched to list private declarations too
    /// (`zigbuildx.Docs.includePrivate`, as zigstorage does).
    ///
    /// - `b`: ziggui's build graph.
    /// - `config`: the build's configuration.
    /// - Returns: nothing; propagates macOS SDK resolution failure.
    fn declare(b: *std.Build, config: Config) !void {
        const staged = b.addWriteFiles();
        const renderer = b.createModule(.{
            .root_source_file = Self.stage(b, staged, "renderer"),
            .target = config.target,
            .optimize = config.optimize,
        });
        Modules.addFonts(b, renderer);
        const views = b.createModule(.{
            .root_source_file = Self.stage(b, staged, "views"),
            .target = config.target,
            .optimize = config.optimize,
            .imports = &.{.{ .name = "renderer", .module = renderer }},
        });
        const root = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = config.target,
            .optimize = config.optimize,
            .imports = &.{
                .{ .name = "renderer", .module = renderer },
                .{ .name = "views", .module = views },
            },
        });
        root.addOptions("config", Modules.barrelOptions(b, false));

        const library = b.addLibrary(.{ .name = config.name, .root_module = root, .linkage = .static });
        if (builtin.os.tag == .macos) {
            var xcode = try zigbuildx.Xcode.init(b);
            try xcode.resolve();
            xcode.addFrameworkPath(library.root_module);
        }

        const install = b.addInstallDirectory(.{
            .source_dir = zigbuildx.Docs.includePrivate(b, library.getEmittedDocs()),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });
        const step = b.step("docs", "Generate documentation into zig-out/docs");
        step.dependOn(&install.step);
    }

    /// Copies `src/<name>` into `staged` with its barrel also saved as
    /// `<name>/root.zig`, the file autodoc takes as the module's root.
    ///
    /// - `b`: ziggui's build graph.
    /// - `staged`: the docs' staging directory.
    /// - `name`: the module, as `src/` names its directory.
    /// - Returns: the staged `root.zig`.
    fn stage(b: *std.Build, staged: *std.Build.Step.WriteFile, name: []const u8) std.Build.LazyPath {
        _ = staged.addCopyDirectory(b.path(b.fmt("src/{s}", .{name})), name, .{});
        return staged.addCopyFile(b.path(b.fmt("src/{s}/module.zig", .{name})), b.fmt("{s}/root.zig", .{name}));
    }
};

/// Declares the build graph for the ziggui library, gallery, tests, and docs.
///
/// Serves as the entry point the Zig build runner invokes to wire up every
/// build step consumers rely on — `lib`, `test`, and `docs`, plus `gallery`,
/// `run-gallery` and `test-sdl` when ziggui is the root build — and the
/// standard target, optimize, and test-filter options. `test` and the library
/// build on the core `ziggui` and never compile or link SDL; only the gallery
/// executable and `test-sdl` (and an app, through `linkApp`) build and link
/// it. Declaring them fetches the SDL tarball lazily on the first configure.
/// Called once per build invocation.
///
/// - `b`: the build graph the steps and options are registered on.
/// - Returns: nothing on success; propagates errors from version parsing and
///   macOS SDK resolution.
pub fn build(b: *std.Build) !void {
    log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
    const config = Config{
        .name = @tagName(zon.name),
        .gallery_name = @tagName(zon.name) ++ "-gallery",
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .version = try std.SemanticVersion.parse(zon.version),
    };

    const test_filter = b.option([]const u8, "test-filter", "Run unit tests that match filter");

    // -------------------------------------------------------------------------
    // Modules

    const modules = Modules.init(b, config);

    // -------------------------------------------------------------------------
    // Library

    const library = b.addLibrary(.{ .name = config.name, .root_module = modules.core, .linkage = .static });

    if (builtin.os.tag == .macos) {
        var xcode = try zigbuildx.Xcode.init(b);
        try xcode.resolve();
        xcode.addFrameworkPath(library.root_module);
    }

    const library_install = b.addInstallArtifact(library, .{});
    const library_step = b.step("lib", "Build static library");
    library_step.dependOn(&library_install.step);
    b.getInstallStep().dependOn(&library_install.step);

    // -------------------------------------------------------------------------
    // Gallery
    //
    // The component gallery (`gallery/`). Its views build and test on the
    // core `ziggui`; the executable builds them again on the app `ziggui`,
    // which links SDL3. As for any package depending on ziggui, the
    // executable (and `test-sdl`, beside it) is declared only when ziggui is
    // the root build.

    const gallery_module = b.createModule(.{
        .root_source_file = b.path("gallery/module.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{.{ .name = config.name, .module = modules.core }},
    });

    const filters: []const []const u8 = if (test_filter) |filter| b.dupeStrings(&.{filter}) else &.{};
    if (b.dep_prefix.len == 0) try AppSteps.declare(b, config, filters);

    // -------------------------------------------------------------------------
    // Tests
    //
    // One test compile per module: a module's tests run only when it is the
    // test root. None of them links SDL; the SDL runtime's tests are the
    // separate `test-sdl` step (`SdlTests`).

    const tests_step = b.step("test", "Run unit tests");
    for ([_]*std.Build.Module{ modules.renderer, modules.views, modules.core, gallery_module }) |module| {
        const tests = b.addTest(.{ .root_module = module, .filters = filters });
        const tests_run = b.addRunArtifact(tests);
        // force tests to run on every test run
        tests_run.has_side_effects = true;
        tests_step.dependOn(&tests_run.step);
    }

    // -------------------------------------------------------------------------
    // Docs

    try Docs.declare(b, config);
}

/// The app `ziggui` for a package that depends on ziggui: the core barrel
/// plus the SDL runtime as `ziggui.sdl`. An executable imports it as
/// `ziggui`; the package's tests import `ziggui_dep.module("ziggui")`, the core
/// barrel, also as `ziggui`. Both share ziggui's renderer and views modules,
/// so their types agree. SDL3 is fetched lazily and built from the release on
/// first use; on that first configure the runtime is returned unlinked and
/// the build reruns once SDL is there. Repeated calls return the same module,
/// so every call must pass the same options, with the target and optimize
/// mode the dependency was declared with: one dependency builds one renderer.
/// A mismatch (target architecture, OS or ABI, optimize mode, `macos_sdk`,
/// `sdl3_prefix`) panics at configure, naming both values.
///
///     const ziggui_dep = b.dependency("ziggui", .{ .target = target, .optimize = optimize });
///     const ziggui_build = @import("ziggui");
///     exe.root_module.addImport("ziggui", ziggui_build.linkApp(ziggui_dep, .{ .target = target, .optimize = optimize }));
///     tests.root_module.addImport("ziggui", ziggui_dep.module("ziggui"));
///
/// - `dependency`: the ziggui dependency, as `b.dependency("ziggui", ...)` returns it.
/// - `options`: the target, optimize mode, SDK and SDL source; pass the target
///   and optimize mode the dependency was declared with.
/// - Returns: the app `ziggui` module.
pub fn linkApp(dependency: *std.Build.Dependency, options: AppOptions) *std.Build.Module {
    return Modules.app(dependency.builder, options);
}
