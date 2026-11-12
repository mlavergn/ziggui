//! Builds SDL3 as a static library from the official release tarball (the `sdl` dependency: plain
//! C sources, no build.zig) for macOS, Windows (MinGW-w64 by default, or MSVC) and Linux, with
//! every subsystem. On Linux the X11, Wayland and audio headers, the generated Wayland protocol
//! sources and the sonames SDL loads at run time come from the `sdl_linux_deps` dependency.
//!
//! Source lists and SDL_build_config.h values ported from castholm/SDL v0.6.1 (MIT, © 2024 Carl Åstholm).

const std = @import("std");
const log = std.log.scoped(.ziggui_sdl_build);

/// What SdlBuild builds SDL3 for.
pub const SdlOptions = struct {
    const Self = @This();
    /// The target SDL3 is compiled for: macOS, Windows or Linux.
    target: std.Build.ResolvedTarget,
    /// The optimization mode SDL3 is compiled with.
    optimize: std.lang.Optimize,
    /// The macOS SDK root (`xcrun --show-sdk-path`); required for an explicit (non-native) macOS target, null lets Zig probe the host's.
    macos_sdk: ?[]const u8 = null,
};

/// What SDL_linux_deps (the `sdl_linux_deps` dependency) provides at the commit build.zig.zon pins,
/// copied from its build.zig, which a build helper outside the root build.zig cannot import.
/// Update these with that pin.
const LinuxDependencies = struct {
    const Self = @This();
    /// The Wayland client library's soname.
    const wayland_client_soname = "libwayland-client.so.0";
    /// The Wayland cursor library's soname.
    const wayland_cursor_soname = "libwayland-cursor.so.0";
    /// The Wayland EGL library's soname.
    const wayland_egl_soname = "libwayland-egl.so.1";
    /// libdecor's soname.
    const libdecor_soname = "libdecor-0.so.0";
    /// The libdecor version its headers are.
    const libdecor_version: std.SemanticVersion = .{ .major = 0, .minor = 2, .patch = 5 };
    /// libxkbcommon's soname.
    const xkbcommon_soname = "libxkbcommon.so.0";
    /// The libxkbcommon version SDL is told to expect: 1.6.0, as castholm/SDL sets it, below the
    /// headers' 1.13.1 because 1.10 and later are not yet widely installed.
    const xkbcommon_version: std.SemanticVersion = .{ .major = 1, .minor = 6, .patch = 0 };
    /// libX11's soname.
    const x11_soname = "libX11.so.6";
    /// libXcursor's soname.
    const xcursor_soname = "libXcursor.so.1";
    /// libXext's soname.
    const xext_soname = "libXext.so.6";
    /// libXfixes' soname.
    const xfixes_soname = "libXfixes.so.3";
    /// libXi's soname.
    const xi_soname = "libXi.so.6";
    /// libXrandr's soname.
    const xrandr_soname = "libXrandr.so.2";
    /// libXss' soname.
    const xss_soname = "libXss.so.1";
    /// libXtst's soname.
    const xtst_soname = "libXtst.so.6";
    /// libdrm's soname.
    const drm_soname = "libdrm.so.2";
    /// libgbm's soname.
    const gbm_soname = "libgbm.so.1";
    /// PipeWire's soname.
    const pipewire_soname = "libpipewire-0.3.so.0";
    /// PulseAudio's soname.
    const pulseaudio_soname = "libpulse.so.0";
    /// ALSA's soname.
    const alsa_soname = "libasound.so.2";
    /// sndio's soname.
    const sndio_soname = "libsndio.so.7";
    /// JACK's soname.
    const jack_soname = "libjack.so.0";
    /// libusb's soname.
    const libusb_soname = "libusb-1.0.so.0";
    /// FriBidi's soname.
    const fribidi_soname = "libfribidi.so.0";
    /// libthai's soname.
    const libthai_soname = "libthai.so.0";
    /// libudev's soname.
    const libudev_soname = "libudev.so.1";
    /// The generated Wayland protocol sources.
    const wayland_sources = [_][]const u8{
        "src/alpha-modifier-v1-protocol.c",
        "src/color-management-v1-protocol.c",
        "src/cursor-shape-v1-protocol.c",
        "src/fractional-scale-v1-protocol.c",
        "src/frog-color-management-v1-protocol.c",
        "src/idle-inhibit-unstable-v1-protocol.c",
        "src/input-timestamps-unstable-v1-protocol.c",
        "src/keyboard-shortcuts-inhibit-unstable-v1-protocol.c",
        "src/pointer-constraints-unstable-v1-protocol.c",
        "src/pointer-gestures-unstable-v1-protocol.c",
        "src/pointer-warp-v1-protocol.c",
        "src/primary-selection-unstable-v1-protocol.c",
        "src/relative-pointer-unstable-v1-protocol.c",
        "src/tablet-v2-protocol.c",
        "src/text-input-unstable-v3-protocol.c",
        "src/viewporter-protocol.c",
        "src/wayland-protocol.c",
        "src/xdg-activation-v1-protocol.c",
        "src/xdg-decoration-unstable-v1-protocol.c",
        "src/xdg-dialog-v1-protocol.c",
        "src/xdg-foreign-unstable-v2-protocol.c",
        "src/xdg-output-unstable-v1-protocol.c",
        "src/xdg-shell-protocol.c",
        "src/xdg-toplevel-icon-v1-protocol.c",
    };
};

/// The platform SDL3 is configured for, read from the target.
const Platform = struct {
    const Self = @This();
    /// The target is Windows.
    windows: bool = false,
    /// The target is Linux.
    linux: bool = false,
    /// The target is macOS.
    macos: bool = false,
    /// The Windows target uses the MSVC ABI (MinGW-w64 otherwise).
    msvc: bool = false,
    /// The Linux target uses musl (glibc otherwise).
    musl: bool = false,
    /// The minor version of the Linux target's glibc 2.x, 0 when unknown or not glibc 2.
    glibc_minor: u8 = 0,
    /// The target CPU, for its SIMD features.
    cpu: std.Target.Cpu,

    /// Read the platform from a target.
    ///
    /// - `target`: the resolved target.
    /// - Returns: the platform; every flag is false for an operating system SdlBuild does not support.
    fn init(target: *const std.Target) Self {
        var self = Self{ .cpu = target.cpu };
        switch (target.os.tag) {
            .windows => {
                self.windows = true;
                self.msvc = target.abi == .msvc;
            },
            .linux => {
                self.linux = true;
                self.musl = target.abi.isMusl();
                if (target.os.versionRange().gnuLibCVersion()) |glibc| {
                    if (glibc.major == 2) self.glibc_minor = @min(glibc.minor, 255);
                }
            },
            .macos => self.macos = true,
            else => {},
        }
        return self;
    }

    /// Report whether SdlBuild supports the platform.
    ///
    /// - `self`: the platform.
    /// - Returns: true for macOS, Windows and Linux.
    fn supported(self: *const Self) bool {
        return self.windows or self.linux or self.macos;
    }

    /// Generate `SDL_build_config.h` from the release's CMake template.
    ///
    /// - `self`: the platform.
    /// - `b`: the build graph.
    /// - `source`: the `sdl` dependency.
    /// - Returns: the config header step.
    fn buildConfigHeader(self: *const Self, b: *std.Build, source: *std.Build.Dependency) *std.Build.Step.ConfigHeader {
        return b.addConfigHeader(.{
            .style = .{ .cmake = source.path("include/build_config/SDL_build_config.h.cmake") },
            .include_path = "SDL_build_config.h",
        }, .{
            .SDL_PLATFORM_PRIVATE = false,
            .HAVE_GCC_ATOMICS = true,
            .HAVE_GCC_SYNC_LOCK_TEST_AND_SET = false,
            .SDL_DISABLE_ALLOCA = false,
            .HAVE_FLOAT_H = true,
            .HAVE_STDARG_H = true,
            .HAVE_STDDEF_H = true,
            .HAVE_STDINT_H = true,
            .HAVE_LIBC = true,
            .HAVE_ALLOCA_H = self.linux or self.macos,
            .HAVE_ICONV_H = self.linux or self.macos,
            .HAVE_INTTYPES_H = true,
            .HAVE_LIMITS_H = true,
            .HAVE_MALLOC_H = self.windows or self.linux,
            .HAVE_MATH_H = true,
            .HAVE_MEMORY_H = true,
            .HAVE_SIGNAL_H = true,
            .HAVE_STDIO_H = true,
            .HAVE_STDLIB_H = true,
            .HAVE_STRINGS_H = (self.windows and !self.msvc) or self.linux or self.macos,
            .HAVE_STRING_H = true,
            .HAVE_SYS_TYPES_H = true,
            .HAVE_WCHAR_H = true,
            .HAVE_PTHREAD_NP_H = false,
            .HAVE_DLOPEN = self.linux or self.macos,
            .HAVE_MALLOC = true,
            .HAVE_FDATASYNC = self.linux,
            .HAVE_GETENV = true,
            .HAVE_GETHOSTNAME = self.linux or self.macos,
            .HAVE_SETENV = self.linux or self.macos,
            .HAVE_PUTENV = true,
            .HAVE_UNSETENV = self.linux or self.macos,
            .HAVE_ABS = true,
            .HAVE_BCOPY = self.linux or self.macos,
            .HAVE_MEMSET = true,
            .HAVE_MEMCPY = true,
            .HAVE_MEMMOVE = true,
            .HAVE_MEMCMP = true,
            .HAVE_WCSLEN = true,
            .HAVE_WCSNLEN = true,
            .HAVE_WCSLCPY = (self.linux and self.glibc_minor >= 38) or self.macos,
            .HAVE_WCSLCAT = (self.linux and self.glibc_minor >= 38) or self.macos,
            .HAVE_WCSSTR = true,
            .HAVE_WCSCMP = true,
            .HAVE_WCSNCMP = true,
            .HAVE_WCSTOL = true,
            .HAVE_STRLEN = true,
            .HAVE_STRNLEN = true,
            .HAVE_STRLCPY = (self.linux and (self.glibc_minor >= 38 or self.musl)) or self.macos,
            .HAVE_STRLCAT = (self.linux and (self.glibc_minor >= 38 or self.musl)) or self.macos,
            .HAVE_STRPBRK = true,
            .HAVE__STRREV = self.windows,
            .HAVE_INDEX = self.linux or self.macos,
            .HAVE_RINDEX = self.linux or self.macos,
            .HAVE_STRCHR = true,
            .HAVE_STRRCHR = true,
            .HAVE_STRSTR = true,
            .HAVE_STRNSTR = self.macos,
            .HAVE_STRTOK_R = (self.windows and !self.msvc) or self.linux or self.macos,
            .HAVE_ITOA = self.windows,
            .HAVE__LTOA = self.windows,
            .HAVE__ULTOA = self.windows,
            .HAVE_STRTOL = true,
            .HAVE_STRTOUL = true,
            .HAVE__I64TOA = self.windows,
            .HAVE__UI64TOA = self.windows,
            .HAVE_STRTOLL = true,
            .HAVE_STRTOULL = true,
            .HAVE_STRTOD = true,
            .HAVE_ATOI = true,
            .HAVE_ATOF = true,
            .HAVE_STRCMP = true,
            .HAVE_STRNCMP = true,
            .HAVE_VSSCANF = true,
            .HAVE_VSNPRINTF = true,
            .HAVE_ACOS = true,
            .HAVE_ACOSF = true,
            .HAVE_ASIN = true,
            .HAVE_ASINF = true,
            .HAVE_ATAN = true,
            .HAVE_ATANF = true,
            .HAVE_ATAN2 = true,
            .HAVE_ATAN2F = true,
            .HAVE_CEIL = true,
            .HAVE_CEILF = true,
            .HAVE_COPYSIGN = true,
            .HAVE_COPYSIGNF = true,
            .HAVE__COPYSIGN = self.windows,
            .HAVE_COS = true,
            .HAVE_COSF = true,
            .HAVE_EXP = true,
            .HAVE_EXPF = true,
            .HAVE_FABS = true,
            .HAVE_FABSF = true,
            .HAVE_FLOOR = true,
            .HAVE_FLOORF = true,
            .HAVE_FMOD = true,
            .HAVE_FMODF = true,
            .HAVE_ISINF = true,
            .HAVE_ISINFF = (self.linux and !self.musl),
            .HAVE_ISINF_FLOAT_MACRO = true,
            .HAVE_ISNAN = true,
            .HAVE_ISNANF = (self.linux and !self.musl),
            .HAVE_ISNAN_FLOAT_MACRO = true,
            .HAVE_LOG = true,
            .HAVE_LOGF = true,
            .HAVE_LOG10 = true,
            .HAVE_LOG10F = true,
            .HAVE_LROUND = true,
            .HAVE_LROUNDF = true,
            .HAVE_MODF = true,
            .HAVE_MODFF = true,
            .HAVE_POW = true,
            .HAVE_POWF = true,
            .HAVE_ROUND = true,
            .HAVE_ROUNDF = true,
            .HAVE_SCALBN = true,
            .HAVE_SCALBNF = true,
            .HAVE_SIN = true,
            .HAVE_SINF = true,
            .HAVE_SQRT = true,
            .HAVE_SQRTF = true,
            .HAVE_TAN = true,
            .HAVE_TANF = true,
            .HAVE_TRUNC = true,
            .HAVE_TRUNCF = true,
            .HAVE__FSEEKI64 = self.windows,
            .HAVE_FOPEN64 = (self.windows and !self.msvc) or (self.linux and !self.musl),
            .HAVE_FSEEKO = (self.windows and !self.msvc) or self.linux or self.macos,
            .HAVE_FSEEKO64 = (self.windows and !self.msvc) or (self.linux and !self.musl),
            .HAVE_MEMFD_CREATE = (self.linux and self.glibc_minor >= 27),
            .HAVE_POSIX_FALLOCATE = self.linux,
            .HAVE_SIGACTION = self.linux or self.macos,
            .HAVE_SIGTIMEDWAIT = self.linux,
            .HAVE_SA_SIGACTION = self.linux or self.macos,
            .HAVE_ST_MTIM = self.linux,
            .HAVE_SETJMP = self.linux or self.macos,
            .HAVE_NANOSLEEP = self.linux or self.macos,
            .HAVE_GMTIME_R = self.linux or self.macos,
            .HAVE_LOCALTIME_R = self.linux or self.macos,
            .HAVE_NL_LANGINFO = self.linux or self.macos,
            .HAVE_SYSCONF = self.linux or self.macos,
            .HAVE_SYSCTLBYNAME = self.macos,
            .HAVE_CLOCK_GETTIME = self.linux,
            .HAVE_GETPAGESIZE = self.linux or self.macos,
            .HAVE_ICONV = self.linux,
            .SDL_USE_LIBICONV = false,
            .HAVE_PTHREAD_CONDATTR_SETCLOCK = self.linux or false,
            .HAVE_PTHREAD_SETNAME_NP = self.linux or self.macos,
            .HAVE_PTHREAD_SET_NAME_NP = false,
            .HAVE_SEM_CLOCKWAIT = (self.linux and !self.musl),
            .HAVE_SEM_CLOCKWAIT_NP = false,
            .HAVE_SEM_TIMEDWAIT = self.linux or false,
            .HAVE_GETAUXVAL = self.linux,
            .HAVE_ELF_AUX_INFO = false,
            .HAVE_PPOLL = self.linux,
            .HAVE__EXIT = true,
            .HAVE_GETRESUID = self.linux,
            .HAVE_GETRESGID = self.linux,
            .HAVE_DBUS_DBUS_H = self.linux,
            .HAVE_FCITX = self.linux,
            .HAVE_IBUS_IBUS_H = self.linux,
            .HAVE_INOTIFY_INIT1 = self.linux,
            .HAVE_INOTIFY = self.linux,
            .HAVE_LIBUSB = self.linux,
            .HAVE_O_CLOEXEC = self.linux or self.macos,
            .HAVE_LINUX_INPUT_H = self.linux,
            .HAVE_LIBUDEV_H = self.linux,
            .HAVE_LIBDECOR_H = self.linux,
            .HAVE_LIBURING_H = self.linux,
            .HAVE_FRIBIDI_H = self.linux,
            .SDL_FRIBIDI_DYNAMIC = self.soname(LinuxDependencies.fribidi_soname),
            .HAVE_LIBTHAI_H = self.linux,
            .SDL_LIBTHAI_DYNAMIC = self.soname(LinuxDependencies.libthai_soname),
            .HAVE_DDRAW_H = self.windows,
            .HAVE_DSOUND_H = self.windows,
            .HAVE_DINPUT_H = self.windows,
            .HAVE_XINPUT_H = self.windows,
            .HAVE_WINDOWS_GAMING_INPUT_H = false,
            .HAVE_GAMEINPUT_H = (self.windows and self.msvc),
            .HAVE_DXGI_H = self.windows,
            .HAVE_DXGI1_5_H = self.windows,
            .HAVE_DXGI1_6_H = self.windows,
            .HAVE_MMDEVICEAPI_H = self.windows,
            .HAVE_TPCSHRD_H = self.windows,
            .HAVE_ROAPI_H = (self.windows and !self.msvc),
            .HAVE_SHELLSCALINGAPI_H = self.windows,
            .USE_POSIX_SPAWN = false,
            .HAVE_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR = self.macos,
            .HAVE_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR_NP = (self.linux and self.glibc_minor >= 29) or self.macos,
            .SDL_DISABLE_DLOPEN_NOTES = false,
            .SDL_DEFAULT_ASSERT_LEVEL_CONFIGURED = false,
            .SDL_DEFAULT_ASSERT_LEVEL = null,
            .SDL_AUDIO_DISABLED = false,
            .SDL_VIDEO_DISABLED = false,
            .SDL_GPU_DISABLED = false,
            .SDL_RENDER_DISABLED = false,
            .SDL_CAMERA_DISABLED = false,
            .SDL_JOYSTICK_DISABLED = false,
            .SDL_HAPTIC_DISABLED = false,
            .SDL_HIDAPI_DISABLED = false,
            .SDL_POWER_DISABLED = false,
            .SDL_SENSOR_DISABLED = false,
            .SDL_DIALOG_DISABLED = false,
            .SDL_THREADS_DISABLED = false,
            .SDL_AUDIO_DRIVER_ALSA = self.linux,
            .SDL_AUDIO_DRIVER_ALSA_DYNAMIC = self.soname(LinuxDependencies.alsa_soname),
            .SDL_AUDIO_DRIVER_OPENSLES = false,
            .SDL_AUDIO_DRIVER_AAUDIO = false,
            .SDL_AUDIO_DRIVER_COREAUDIO = self.macos,
            .SDL_AUDIO_DRIVER_DISK = true,
            .SDL_AUDIO_DRIVER_DSOUND = self.windows,
            .SDL_AUDIO_DRIVER_DUMMY = true,
            .SDL_AUDIO_DRIVER_EMSCRIPTEN = false,
            .SDL_AUDIO_DRIVER_HAIKU = false,
            .SDL_AUDIO_DRIVER_JACK = self.linux,
            .SDL_AUDIO_DRIVER_JACK_DYNAMIC = self.soname(LinuxDependencies.jack_soname),
            .SDL_AUDIO_DRIVER_NETBSD = false,
            .SDL_AUDIO_DRIVER_OSS = false,
            .SDL_AUDIO_DRIVER_PIPEWIRE = self.linux,
            .SDL_AUDIO_DRIVER_PIPEWIRE_DYNAMIC = self.soname(LinuxDependencies.pipewire_soname),
            .SDL_AUDIO_DRIVER_PULSEAUDIO = self.linux,
            .SDL_AUDIO_DRIVER_PULSEAUDIO_DYNAMIC = self.soname(LinuxDependencies.pulseaudio_soname),
            .SDL_AUDIO_DRIVER_SNDIO = self.linux,
            .SDL_AUDIO_DRIVER_SNDIO_DYNAMIC = self.soname(LinuxDependencies.sndio_soname),
            .SDL_AUDIO_DRIVER_WASAPI = self.windows,
            .SDL_AUDIO_DRIVER_VITA = false,
            .SDL_AUDIO_DRIVER_PSP = false,
            .SDL_AUDIO_DRIVER_PS2 = false,
            .SDL_AUDIO_DRIVER_N3DS = false,
            .SDL_AUDIO_DRIVER_NGAGE = false,
            .SDL_AUDIO_DRIVER_QNX = false,
            .SDL_AUDIO_DRIVER_PRIVATE = false,
            .SDL_INPUT_LINUXEV = self.linux,
            .SDL_INPUT_LINUXKD = self.linux,
            .SDL_INPUT_FBSDKBIO = false,
            .SDL_INPUT_WSCONS = false,
            .SDL_HAVE_MACHINE_JOYSTICK_H = false,
            .SDL_JOYSTICK_ANDROID = false,
            .SDL_JOYSTICK_DINPUT = self.windows,
            .SDL_JOYSTICK_DUMMY = false,
            .SDL_JOYSTICK_EMSCRIPTEN = false,
            .SDL_JOYSTICK_GAMEINPUT = (self.windows and self.msvc),
            .SDL_JOYSTICK_HAIKU = false,
            .SDL_JOYSTICK_HIDAPI = true,
            .SDL_JOYSTICK_IOKIT = self.macos,
            .SDL_JOYSTICK_LINUX = self.linux,
            .SDL_JOYSTICK_MFI = self.macos,
            .SDL_JOYSTICK_N3DS = false,
            .SDL_JOYSTICK_PS2 = false,
            .SDL_JOYSTICK_PSP = false,
            .SDL_JOYSTICK_RAWINPUT = self.windows,
            .SDL_JOYSTICK_USBHID = false,
            .SDL_JOYSTICK_VIRTUAL = true,
            .SDL_JOYSTICK_VITA = false,
            .SDL_JOYSTICK_WGI = false,
            .SDL_JOYSTICK_XINPUT = self.windows,
            .SDL_JOYSTICK_PRIVATE = false,
            .SDL_HAPTIC_DUMMY = false,
            .SDL_HAPTIC_LINUX = self.linux,
            .SDL_HAPTIC_IOKIT = self.macos,
            .SDL_HAPTIC_DINPUT = self.windows,
            .SDL_HAPTIC_ANDROID = false,
            .SDL_HAPTIC_PRIVATE = false,
            .SDL_LIBUSB_DYNAMIC = self.soname(LinuxDependencies.libusb_soname),
            .SDL_UDEV_DYNAMIC = self.soname(LinuxDependencies.libudev_soname),
            .SDL_PROCESS_DUMMY = false,
            .SDL_PROCESS_POSIX = self.linux or self.macos,
            .SDL_PROCESS_WINDOWS = self.windows,
            .SDL_PROCESS_PRIVATE = false,
            .SDL_SENSOR_ANDROID = false,
            .SDL_SENSOR_COREMOTION = false,
            .SDL_SENSOR_WINDOWS = self.windows,
            .SDL_SENSOR_DUMMY = self.linux or self.macos,
            .SDL_SENSOR_VITA = false,
            .SDL_SENSOR_N3DS = false,
            .SDL_SENSOR_EMSCRIPTEN = false,
            .SDL_SENSOR_PRIVATE = false,
            .SDL_LOADSO_DLOPEN = self.linux or self.macos,
            .SDL_LOADSO_DUMMY = false,
            .SDL_LOADSO_WINDOWS = self.windows,
            .SDL_LOADSO_PRIVATE = false,
            .SDL_THREAD_GENERIC_COND_SUFFIX = self.windows,
            .SDL_THREAD_GENERIC_RWLOCK_SUFFIX = self.windows,
            .SDL_THREAD_PTHREAD = self.linux or self.macos or false,
            .SDL_THREAD_PTHREAD_RECURSIVE_MUTEX = self.linux or self.macos or false,
            .SDL_THREAD_PTHREAD_RECURSIVE_MUTEX_NP = false,
            .SDL_THREAD_WINDOWS = self.windows,
            .SDL_THREAD_VITA = false,
            .SDL_THREAD_PSP = false,
            .SDL_THREAD_PS2 = false,
            .SDL_THREAD_N3DS = false,
            .SDL_THREAD_PRIVATE = false,
            .SDL_TIME_UNIX = self.linux or self.macos,
            .SDL_TIME_WINDOWS = self.windows,
            .SDL_TIME_VITA = false,
            .SDL_TIME_PSP = false,
            .SDL_TIME_PS2 = false,
            .SDL_TIME_N3DS = false,
            .SDL_TIME_NGAGE = false,
            .SDL_TIME_PRIVATE = false,
            .SDL_TIMER_HAIKU = false,
            .SDL_TIMER_UNIX = self.linux or self.macos,
            .SDL_TIMER_WINDOWS = self.windows,
            .SDL_TIMER_VITA = false,
            .SDL_TIMER_PSP = false,
            .SDL_TIMER_PS2 = false,
            .SDL_TIMER_N3DS = false,
            .SDL_TIMER_PRIVATE = false,
            .SDL_VIDEO_DRIVER_ANDROID = false,
            .SDL_VIDEO_DRIVER_COCOA = self.macos,
            .SDL_VIDEO_DRIVER_DUMMY = true,
            .SDL_VIDEO_DRIVER_EMSCRIPTEN = false,
            .SDL_VIDEO_DRIVER_HAIKU = false,
            .SDL_VIDEO_DRIVER_KMSDRM = self.linux,
            .SDL_VIDEO_DRIVER_KMSDRM_DYNAMIC = self.soname(LinuxDependencies.drm_soname),
            .SDL_VIDEO_DRIVER_KMSDRM_DYNAMIC_GBM = self.soname(LinuxDependencies.gbm_soname),
            .SDL_VIDEO_DRIVER_N3DS = false,
            .SDL_VIDEO_DRIVER_NGAGE = false,
            .SDL_VIDEO_DRIVER_OFFSCREEN = true,
            .SDL_VIDEO_DRIVER_PS2 = false,
            .SDL_VIDEO_DRIVER_PSP = false,
            .SDL_VIDEO_DRIVER_RISCOS = false,
            .SDL_VIDEO_DRIVER_ROCKCHIP = false,
            .SDL_VIDEO_DRIVER_RPI = false,
            .SDL_VIDEO_DRIVER_UIKIT = false,
            .SDL_VIDEO_DRIVER_VITA = false,
            .SDL_VIDEO_DRIVER_VIVANTE = false,
            .SDL_VIDEO_DRIVER_VIVANTE_VDK = false,
            .SDL_VIDEO_DRIVER_OPENVR = false,
            .SDL_VIDEO_DRIVER_WAYLAND = self.linux,
            .SDL_VIDEO_DRIVER_WAYLAND_DYNAMIC = self.soname(LinuxDependencies.wayland_client_soname),
            .SDL_VIDEO_DRIVER_WAYLAND_DYNAMIC_CURSOR = self.soname(LinuxDependencies.wayland_cursor_soname),
            .SDL_VIDEO_DRIVER_WAYLAND_DYNAMIC_EGL = self.soname(LinuxDependencies.wayland_egl_soname),
            .SDL_VIDEO_DRIVER_WAYLAND_DYNAMIC_LIBDECOR = self.soname(LinuxDependencies.libdecor_soname),
            .SDL_VIDEO_DRIVER_WAYLAND_DYNAMIC_XKBCOMMON = self.soname(LinuxDependencies.xkbcommon_soname),
            .SDL_VIDEO_DRIVER_WINDOWS = self.windows,
            .SDL_VIDEO_DRIVER_X11 = self.linux,
            .SDL_VIDEO_DRIVER_X11_DYNAMIC = self.soname(LinuxDependencies.x11_soname),
            .SDL_VIDEO_DRIVER_X11_DYNAMIC_XCURSOR = self.soname(LinuxDependencies.xcursor_soname),
            .SDL_VIDEO_DRIVER_X11_DYNAMIC_XEXT = self.soname(LinuxDependencies.xext_soname),
            .SDL_VIDEO_DRIVER_X11_DYNAMIC_XFIXES = self.soname(LinuxDependencies.xfixes_soname),
            .SDL_VIDEO_DRIVER_X11_DYNAMIC_XINPUT2 = self.soname(LinuxDependencies.xi_soname),
            .SDL_VIDEO_DRIVER_X11_DYNAMIC_XRANDR = self.soname(LinuxDependencies.xrandr_soname),
            .SDL_VIDEO_DRIVER_X11_DYNAMIC_XSS = self.soname(LinuxDependencies.xss_soname),
            .SDL_VIDEO_DRIVER_X11_DYNAMIC_XTEST = self.soname(LinuxDependencies.xtst_soname),
            .SDL_VIDEO_DRIVER_X11_HAS_XKBLIB = self.linux,
            .SDL_VIDEO_DRIVER_X11_SUPPORTS_GENERIC_EVENTS = self.linux,
            .SDL_VIDEO_DRIVER_X11_XCURSOR = self.linux,
            .SDL_VIDEO_DRIVER_X11_XDBE = self.linux,
            .SDL_VIDEO_DRIVER_X11_XFIXES = self.linux,
            .SDL_VIDEO_DRIVER_X11_XINPUT2 = self.linux,
            .SDL_VIDEO_DRIVER_X11_XINPUT2_SUPPORTS_MULTITOUCH = self.linux,
            .SDL_VIDEO_DRIVER_X11_XINPUT2_SUPPORTS_SCROLLINFO = self.linux,
            .SDL_VIDEO_DRIVER_X11_XINPUT2_SUPPORTS_GESTURE = self.linux,
            .SDL_VIDEO_DRIVER_X11_XRANDR = self.linux,
            .SDL_VIDEO_DRIVER_X11_XSCRNSAVER = self.linux,
            .SDL_VIDEO_DRIVER_X11_XSHAPE = self.linux,
            .SDL_VIDEO_DRIVER_X11_XSYNC = self.linux,
            .SDL_VIDEO_DRIVER_X11_XTEST = self.linux,
            .SDL_VIDEO_DRIVER_QNX = false,
            .SDL_VIDEO_DRIVER_PRIVATE = false,
            .SDL_VIDEO_RENDER_D3D = self.windows,
            .SDL_VIDEO_RENDER_D3D11 = self.windows,
            .SDL_VIDEO_RENDER_D3D12 = self.windows,
            .SDL_VIDEO_RENDER_GPU = true,
            .SDL_VIDEO_RENDER_METAL = self.macos,
            .SDL_VIDEO_RENDER_VULKAN = true,
            .SDL_VIDEO_RENDER_OGL = true,
            .SDL_VIDEO_RENDER_OGL_ES2 = true,
            .SDL_VIDEO_RENDER_NGAGE = false,
            .SDL_VIDEO_RENDER_PS2 = false,
            .SDL_VIDEO_RENDER_PSP = false,
            .SDL_VIDEO_RENDER_VITA_GXM = false,
            .SDL_VIDEO_RENDER_PRIVATE = false,
            .SDL_VIDEO_OPENGL = true,
            .SDL_VIDEO_OPENGL_ES = self.linux,
            .SDL_VIDEO_OPENGL_ES2 = true,
            .SDL_VIDEO_OPENGL_CGL = self.macos,
            .SDL_VIDEO_OPENGL_GLX = self.linux,
            .SDL_VIDEO_OPENGL_WGL = self.windows,
            .SDL_VIDEO_OPENGL_EGL = true,
            .SDL_VIDEO_STATIC_ANGLE = false,
            .SDL_VIDEO_VULKAN = true,
            .SDL_VIDEO_METAL = self.macos,
            .SDL_GPU_D3D11 = false,
            .SDL_GPU_D3D12 = self.windows,
            .SDL_GPU_VULKAN = true,
            .SDL_GPU_METAL = self.macos,
            .SDL_GPU_PRIVATE = false,
            .SDL_POWER_ANDROID = false,
            .SDL_POWER_LINUX = self.linux,
            .SDL_POWER_WINDOWS = self.windows,
            .SDL_POWER_MACOSX = self.macos,
            .SDL_POWER_UIKIT = false,
            .SDL_POWER_HAIKU = false,
            .SDL_POWER_EMSCRIPTEN = false,
            .SDL_POWER_HARDWIRED = false,
            .SDL_POWER_VITA = false,
            .SDL_POWER_PSP = false,
            .SDL_POWER_N3DS = false,
            .SDL_POWER_PRIVATE = false,
            .SDL_FILESYSTEM_ANDROID = false,
            .SDL_FILESYSTEM_HAIKU = false,
            .SDL_FILESYSTEM_COCOA = self.macos,
            .SDL_FILESYSTEM_DUMMY = false,
            .SDL_FILESYSTEM_RISCOS = false,
            .SDL_FILESYSTEM_UNIX = self.linux,
            .SDL_FILESYSTEM_WINDOWS = self.windows,
            .SDL_FILESYSTEM_EMSCRIPTEN = false,
            .SDL_FILESYSTEM_VITA = false,
            .SDL_FILESYSTEM_PSP = false,
            .SDL_FILESYSTEM_PS2 = false,
            .SDL_FILESYSTEM_N3DS = false,
            .SDL_FILESYSTEM_PRIVATE = false,
            .SDL_STORAGE_STEAM = true,
            .SDL_STORAGE_PRIVATE = false,
            .SDL_FSOPS_POSIX = self.linux or self.macos,
            .SDL_FSOPS_WINDOWS = self.windows,
            .SDL_FSOPS_DUMMY = false,
            .SDL_FSOPS_PRIVATE = false,
            .SDL_CAMERA_DRIVER_DUMMY = true,
            .SDL_CAMERA_DRIVER_V4L2 = self.linux,
            .SDL_CAMERA_DRIVER_COREMEDIA = self.macos,
            .SDL_CAMERA_DRIVER_ANDROID = false,
            .SDL_CAMERA_DRIVER_EMSCRIPTEN = false,
            .SDL_CAMERA_DRIVER_MEDIAFOUNDATION = self.windows,
            .SDL_CAMERA_DRIVER_PIPEWIRE = self.linux,
            .SDL_CAMERA_DRIVER_PIPEWIRE_DYNAMIC = self.soname(LinuxDependencies.pipewire_soname),
            .SDL_CAMERA_DRIVER_VITA = false,
            .SDL_CAMERA_DRIVER_PRIVATE = false,
            .SDL_DIALOG_DUMMY = false,
            .SDL_TRAY_DUMMY = false,
            .SDL_ALTIVEC_BLITTERS = false,
            .DYNAPI_NEEDS_DLOPEN = self.linux or self.macos,
            .SDL_USE_IME = self.linux,
            .SDL_DISABLE_WINDOWS_IME = false,
            .SDL_GDK_TEXTINPUT = false,
            .SDL_IPHONE_KEYBOARD = false,
            .SDL_IPHONE_LAUNCHSCREEN = false,
            .SDL_VIDEO_VITA_PIB = false,
            .SDL_VIDEO_VITA_PVR = false,
            .SDL_VIDEO_VITA_PVR_OGL = false,
            .SDL_EMSCRIPTEN_PERSISTENT_PATH_STRING = null,
            .SDL_XKBCOMMON_VERSION_MAJOR = self.linuxVersion(LinuxDependencies.xkbcommon_version.major),
            .SDL_XKBCOMMON_VERSION_MINOR = self.linuxVersion(LinuxDependencies.xkbcommon_version.minor),
            .SDL_XKBCOMMON_VERSION_PATCH = self.linuxVersion(LinuxDependencies.xkbcommon_version.patch),
            .SDL_LIBDECOR_VERSION_MAJOR = self.linuxVersion(LinuxDependencies.libdecor_version.major),
            .SDL_LIBDECOR_VERSION_MINOR = self.linuxVersion(LinuxDependencies.libdecor_version.minor),
            .SDL_LIBDECOR_VERSION_PATCH = self.linuxVersion(LinuxDependencies.libdecor_version.patch),
            .SDL_DISABLE_SSE = !self.hasX86(.sse),
            .SDL_DISABLE_SSE2 = !self.hasX86(.sse2),
            .SDL_DISABLE_SSE3 = !self.hasX86(.sse3),
            .SDL_DISABLE_SSE4_1 = !self.hasX86(.sse4_1),
            .SDL_DISABLE_SSE4_2 = !self.hasX86(.sse4_2),
            .SDL_DISABLE_AVX = !self.hasX86(.avx),
            .SDL_DISABLE_AVX2 = !self.hasX86(.avx2),
            .SDL_DISABLE_AVX512F = !self.hasX86(.avx512f),
            .SDL_DISABLE_MMX = !self.hasX86(.mmx),
            .SDL_DISABLE_LSX = !self.hasLoongArch(.lsx),
            .SDL_DISABLE_LASX = !self.hasLoongArch(.lasx),
            .SDL_DISABLE_NEON = !self.hasNeon(),
        });
    }

    /// The path, within SDL_linux_deps, of the headers specific to the Linux target's CPU and C library.
    ///
    /// - `self`: the platform.
    /// - Returns: the directory, or null for a CPU SDL_linux_deps has none for.
    fn linuxArchitectureHeaders(self: *const Self) ?[]const u8 {
        return switch (self.cpu.arch) {
            .x86_64 => if (self.musl) "include/x86_64-linux-musl" else "include/x86_64-linux-gnu",
            .aarch64 => if (self.musl) "include/aarch64-linux-musl" else "include/aarch64-linux-gnu",
            else => null,
        };
    }

    /// A Linux library's soname as a C string literal for the config header.
    ///
    /// - `self`: the platform.
    /// - `name`: the soname.
    /// - Returns: the quoted soname on Linux, empty (undefined) elsewhere.
    fn soname(self: *const Self, comptime name: []const u8) []const u8 {
        return if (self.linux) "\"" ++ name ++ "\"" else "";
    }

    /// A Linux library's version component for the config header.
    ///
    /// - `self`: the platform.
    /// - `component`: the version component.
    /// - Returns: the component on Linux, null (undefined) elsewhere.
    fn linuxVersion(self: *const Self, comptime component: usize) ?i64 {
        return if (self.linux) component else null;
    }

    /// Report whether the CPU is x86 with a feature.
    ///
    /// - `self`: the platform.
    /// - `feature`: the x86 feature.
    /// - Returns: true when the target CPU has it.
    fn hasX86(self: *const Self, feature: std.Target.x86.Feature) bool {
        return self.cpu.arch.isX86() and std.Target.x86.featureSetHas(self.cpu.features, feature);
    }

    /// Report whether the CPU is LoongArch with a feature.
    ///
    /// - `self`: the platform.
    /// - `feature`: the LoongArch feature.
    /// - Returns: true when the target CPU has it.
    fn hasLoongArch(self: *const Self, feature: std.Target.loongarch.Feature) bool {
        const loongarch = self.cpu.arch == .loongarch32 or self.cpu.arch == .loongarch64;
        return loongarch and std.Target.loongarch.featureSetHas(self.cpu.features, feature);
    }

    /// Report whether the CPU is ARM or AArch64 with NEON.
    ///
    /// - `self`: the platform.
    /// - Returns: true when the target CPU has NEON.
    fn hasNeon(self: *const Self) bool {
        if (self.cpu.arch.isArm()) return std.Target.arm.featureSetHas(self.cpu.features, .neon);
        if (self.cpu.arch.isAARCH64()) return std.Target.aarch64.featureSetHas(self.cpu.features, .neon);
        return false;
    }
};

/// Builds SDL3 from source as a static library.
pub const SdlBuild = struct {
    const Self = @This();
    /// The SDL release the `sdl` dependency is.
    const version: std.SemanticVersion = .{ .major = 3, .minor = 4, .patch = 20 };
    /// What `SDL_REVISION` names as the vendor.
    const vendor_info = "ziggui";
    /// The C flags every SDL source compiles with.
    const common_flags = [_][]const u8{
        "-Wall",
        "-Wundef",
        "-Wfloat-conversion",
        "-fno-strict-aliasing",
        "-Wshadow",
        "-Wno-unused-local-typedefs",
        "-Wimplicit-fallthrough",
    };
    /// The C flags on Linux.
    const linux_flags = common_flags ++ [_][]const u8{"-pthread"};
    /// The C and Objective-C flags on macOS.
    const macos_flags = common_flags ++ [_][]const u8{ "-pthread", "-fobjc-arc" };
    /// The public headers the library does not install: the test library's, and the release's
    /// `SDL_revision.h`, which the generated one replaces.
    const excluded_headers = [_][]const u8{
        "SDL_revision.h",
        "SDL_test.h",
        "SDL_test_assert.h",
        "SDL_test_common.h",
        "SDL_test_compare.h",
        "SDL_test_crc32.h",
        "SDL_test_font.h",
        "SDL_test_fuzzer.h",
        "SDL_test_harness.h",
        "SDL_test_log.h",
        "SDL_test_md5.h",
        "SDL_test_memory.h",
    };
    /// The Windows system libraries SDL links.
    const windows_libraries = [_][]const u8{
        "kernel32",
        "user32",
        "gdi32",
        "winmm",
        "imm32",
        "ole32",
        "oleaut32",
        "version",
        "uuid",
        "advapi32",
        "setupapi",
        "shell32",
        "dinput8",
    };
    /// The macOS frameworks SDL links.
    const macos_frameworks = [_][]const u8{
        "CoreMedia",
        "CoreVideo",
        "Cocoa",
        "IOKit",
        "ForceFeedback",
        "Carbon",
        "CoreAudio",
        "AudioToolbox",
        "AVFoundation",
        "Foundation",
        "GameController",
        "Metal",
        "QuartzCore",
    };
    /// The macOS frameworks SDL links weakly, as older systems lack them.
    const macos_weak_frameworks = [_][]const u8{
        "UniformTypeIdentifiers",
        "CoreHaptics",
    };
    /// Every platform's sources.
    const core_sources = [_][]const u8{
        "src/SDL.c",
        "src/SDL_assert.c",
        "src/SDL_error.c",
        "src/SDL_guid.c",
        "src/SDL_hashtable.c",
        "src/SDL_hints.c",
        "src/SDL_list.c",
        "src/SDL_log.c",
        "src/SDL_properties.c",
        "src/SDL_utils.c",
        "src/atomic/SDL_atomic.c",
        "src/atomic/SDL_spinlock.c",
        "src/audio/SDL_audio.c",
        "src/audio/SDL_audiocvt.c",
        "src/audio/SDL_audiodev.c",
        "src/audio/SDL_audioqueue.c",
        "src/audio/SDL_audioresample.c",
        "src/audio/SDL_audiotypecvt.c",
        "src/audio/SDL_mixer.c",
        "src/audio/SDL_wave.c",
        "src/camera/SDL_camera.c",
        "src/core/SDL_core_unsupported.c",
        "src/cpuinfo/SDL_cpuinfo.c",
        "src/dynapi/SDL_dynapi.c",
        "src/events/SDL_categories.c",
        "src/events/SDL_clipboardevents.c",
        "src/events/SDL_displayevents.c",
        "src/events/SDL_dropevents.c",
        "src/events/SDL_events.c",
        "src/events/SDL_eventwatch.c",
        "src/events/SDL_keyboard.c",
        "src/events/SDL_keymap.c",
        "src/events/SDL_keysym_to_keycode.c",
        "src/events/SDL_keysym_to_scancode.c",
        "src/events/SDL_mouse.c",
        "src/events/SDL_pen.c",
        "src/events/SDL_quit.c",
        "src/events/SDL_scancode_tables.c",
        "src/events/SDL_touch.c",
        "src/events/SDL_windowevents.c",
        "src/events/imKStoUCS.c",
        "src/filesystem/SDL_filesystem.c",
        "src/gpu/SDL_gpu.c",
        "src/haptic/SDL_haptic.c",
        "src/hidapi/SDL_hidapi.c",
        "src/io/SDL_asyncio.c",
        "src/io/SDL_iostream.c",
        "src/io/generic/SDL_asyncio_generic.c",
        "src/joystick/SDL_gamepad.c",
        "src/joystick/SDL_joystick.c",
        "src/joystick/SDL_steam_virtual_gamepad.c",
        "src/joystick/controller_type.c",
        "src/locale/SDL_locale.c",
        "src/main/SDL_main_callbacks.c",
        "src/main/SDL_runapp.c",
        "src/misc/SDL_libusb.c",
        "src/misc/SDL_url.c",
        "src/power/SDL_power.c",
        "src/render/SDL_render.c",
        "src/render/SDL_render_unsupported.c",
        "src/render/SDL_yuv_sw.c",
        "src/render/direct3d/SDL_render_d3d.c",
        "src/render/direct3d/SDL_shaders_d3d.c",
        "src/render/direct3d11/SDL_render_d3d11.c",
        "src/render/direct3d11/SDL_shaders_d3d11.c",
        "src/render/direct3d12/SDL_render_d3d12.c",
        "src/render/direct3d12/SDL_shaders_d3d12.c",
        "src/render/gpu/SDL_pipeline_gpu.c",
        "src/render/gpu/SDL_render_gpu.c",
        "src/render/gpu/SDL_shaders_gpu.c",
        "src/render/ngage/SDL_render_ngage.c",
        "src/render/opengl/SDL_render_gl.c",
        "src/render/opengl/SDL_shaders_gl.c",
        "src/render/opengles2/SDL_render_gles2.c",
        "src/render/opengles2/SDL_shaders_gles2.c",
        "src/render/ps2/SDL_render_ps2.c",
        "src/render/psp/SDL_render_psp.c",
        "src/render/software/SDL_blendfillrect.c",
        "src/render/software/SDL_blendline.c",
        "src/render/software/SDL_blendpoint.c",
        "src/render/software/SDL_drawline.c",
        "src/render/software/SDL_drawpoint.c",
        "src/render/software/SDL_render_sw.c",
        "src/render/software/SDL_triangle.c",
        "src/render/vitagxm/SDL_render_vita_gxm.c",
        "src/render/vitagxm/SDL_render_vita_gxm_memory.c",
        "src/render/vitagxm/SDL_render_vita_gxm_tools.c",
        "src/render/vulkan/SDL_render_vulkan.c",
        "src/render/vulkan/SDL_shaders_vulkan.c",
        "src/sensor/SDL_sensor.c",
        "src/stdlib/SDL_crc16.c",
        "src/stdlib/SDL_crc32.c",
        "src/stdlib/SDL_getenv.c",
        "src/stdlib/SDL_iconv.c",
        "src/stdlib/SDL_malloc.c",
        "src/stdlib/SDL_memcpy.c",
        "src/stdlib/SDL_memmove.c",
        "src/stdlib/SDL_memset.c",
        "src/stdlib/SDL_mslibc.c",
        "src/stdlib/SDL_murmur3.c",
        "src/stdlib/SDL_qsort.c",
        "src/stdlib/SDL_random.c",
        "src/stdlib/SDL_stdlib.c",
        "src/stdlib/SDL_string.c",
        "src/stdlib/SDL_strtokr.c",
        "src/storage/SDL_storage.c",
        "src/thread/SDL_thread.c",
        "src/time/SDL_time.c",
        "src/timer/SDL_timer.c",
        "src/video/SDL_RLEaccel.c",
        "src/video/SDL_blit.c",
        "src/video/SDL_blit_0.c",
        "src/video/SDL_blit_1.c",
        "src/video/SDL_blit_A.c",
        "src/video/SDL_blit_N.c",
        "src/video/SDL_blit_auto.c",
        "src/video/SDL_blit_copy.c",
        "src/video/SDL_blit_slow.c",
        "src/video/SDL_bmp.c",
        "src/video/SDL_clipboard.c",
        "src/video/SDL_egl.c",
        "src/video/SDL_fillrect.c",
        "src/video/SDL_pixels.c",
        "src/video/SDL_rect.c",
        "src/video/SDL_rotate.c",
        "src/video/SDL_stb.c",
        "src/video/SDL_stretch.c",
        "src/video/SDL_surface.c",
        "src/video/SDL_video.c",
        "src/video/SDL_video_unsupported.c",
        "src/video/SDL_vulkan_utils.c",
        "src/video/SDL_yuv.c",
        "src/video/yuv2rgb/yuv_rgb_lsx.c",
        "src/video/yuv2rgb/yuv_rgb_sse.c",
        "src/video/yuv2rgb/yuv_rgb_std.c",
        "src/dialog/SDL_dialog.c",
        "src/dialog/SDL_dialog_utils.c",
        "src/process/SDL_process.c",
        "src/tray/SDL_tray_utils.c",
    };
    /// SDL's own libm (from uClibc), which a static SDL links in.
    const libm_sources = [_][]const u8{
        "src/libm/e_atan2.c",
        "src/libm/e_exp.c",
        "src/libm/e_fmod.c",
        "src/libm/e_log.c",
        "src/libm/e_log10.c",
        "src/libm/e_pow.c",
        "src/libm/e_rem_pio2.c",
        "src/libm/e_sqrt.c",
        "src/libm/k_cos.c",
        "src/libm/k_rem_pio2.c",
        "src/libm/k_sin.c",
        "src/libm/k_tan.c",
        "src/libm/s_atan.c",
        "src/libm/s_copysign.c",
        "src/libm/s_cos.c",
        "src/libm/s_fabs.c",
        "src/libm/s_floor.c",
        "src/libm/s_isinf.c",
        "src/libm/s_isinff.c",
        "src/libm/s_isnan.c",
        "src/libm/s_isnanf.c",
        "src/libm/s_modf.c",
        "src/libm/s_scalbn.c",
        "src/libm/s_sin.c",
        "src/libm/s_tan.c",
    };
    /// The dummy, disk, offscreen, storage and Vulkan drivers every desktop platform builds.
    const driver_sources = [_][]const u8{
        "src/audio/dummy/SDL_dummyaudio.c",
        "src/audio/disk/SDL_diskaudio.c",
        "src/camera/dummy/SDL_camera_dummy.c",
        "src/joystick/virtual/SDL_virtualjoystick.c",
        "src/video/dummy/SDL_nullevents.c",
        "src/video/dummy/SDL_nullframebuffer.c",
        "src/video/dummy/SDL_nullvideo.c",
        "src/storage/generic/SDL_genericstorage.c",
        "src/storage/steam/SDL_steamstorage.c",
        "src/video/offscreen/SDL_offscreenevents.c",
        "src/video/offscreen/SDL_offscreenframebuffer.c",
        "src/video/offscreen/SDL_offscreenopengles.c",
        "src/video/offscreen/SDL_offscreenvideo.c",
        "src/video/offscreen/SDL_offscreenvulkan.c",
        "src/video/offscreen/SDL_offscreenwindow.c",
        "src/gpu/vulkan/SDL_gpu_vulkan.c",
        "src/main/generic/SDL_sysmain_callbacks.c",
    };
    /// The HIDAPI joystick and haptic drivers every desktop platform builds.
    const hidapi_sources = [_][]const u8{
        "src/joystick/hidapi/SDL_hidapi_8bitdo.c",
        "src/joystick/hidapi/SDL_hidapi_combined.c",
        "src/joystick/hidapi/SDL_hidapi_flydigi.c",
        "src/joystick/hidapi/SDL_hidapi_gamecube.c",
        "src/joystick/hidapi/SDL_hidapi_gip.c",
        "src/joystick/hidapi/SDL_hidapi_lg4ff.c",
        "src/joystick/hidapi/SDL_hidapi_luna.c",
        "src/joystick/hidapi/SDL_hidapi_ps3.c",
        "src/joystick/hidapi/SDL_hidapi_ps4.c",
        "src/joystick/hidapi/SDL_hidapi_ps5.c",
        "src/joystick/hidapi/SDL_hidapi_rumble.c",
        "src/joystick/hidapi/SDL_hidapi_shield.c",
        "src/joystick/hidapi/SDL_hidapi_sinput.c",
        "src/joystick/hidapi/SDL_hidapi_stadia.c",
        "src/joystick/hidapi/SDL_hidapi_steam.c",
        "src/joystick/hidapi/SDL_hidapi_steam_hori.c",
        "src/joystick/hidapi/SDL_hidapi_steam_triton.c",
        "src/joystick/hidapi/SDL_hidapi_steamdeck.c",
        "src/joystick/hidapi/SDL_hidapi_switch.c",
        "src/joystick/hidapi/SDL_hidapi_switch2.c",
        "src/joystick/hidapi/SDL_hidapi_wii.c",
        "src/joystick/hidapi/SDL_hidapi_xbox360.c",
        "src/joystick/hidapi/SDL_hidapi_xbox360w.c",
        "src/joystick/hidapi/SDL_hidapi_xboxone.c",
        "src/joystick/hidapi/SDL_hidapi_zuiki.c",
        "src/joystick/hidapi/SDL_hidapijoystick.c",
        "src/joystick/hidapi/SDL_report_descriptor.c",
        "src/haptic/hidapi/SDL_hidapihaptic.c",
        "src/haptic/hidapi/SDL_hidapihaptic_lg4ff.c",
    };
    /// The POSIX sources Linux and macOS share.
    const unix_sources = [_][]const u8{
        "src/loadso/dlopen/SDL_sysloadso.c",
        "src/thread/pthread/SDL_systhread.c",
        "src/thread/pthread/SDL_sysmutex.c",
        "src/thread/pthread/SDL_syscond.c",
        "src/thread/pthread/SDL_sysrwlock.c",
        "src/thread/pthread/SDL_systls.c",
        "src/thread/pthread/SDL_syssem.c",
        "src/filesystem/posix/SDL_sysfsops.c",
        "src/time/unix/SDL_systime.c",
        "src/timer/unix/SDL_systimer.c",
        "src/process/posix/SDL_posixprocess.c",
        "src/sensor/dummy/SDL_dummysensor.c",
    };
    /// Windows' own sources.
    const windows_sources = [_][]const u8{
        "src/core/windows/SDL_gameinput.cpp",
        "src/core/windows/SDL_hid.c",
        "src/core/windows/SDL_immdevice.c",
        "src/core/windows/SDL_windows.c",
        "src/core/windows/SDL_xinput.c",
        "src/core/windows/pch.c",
        "src/core/windows/pch_cpp.cpp",
        "src/main/windows/SDL_sysmain_runapp.c",
        "src/io/windows/SDL_asyncio_windows_ioring.c",
        "src/misc/windows/SDL_sysurl.c",
        "src/audio/directsound/SDL_directsound.c",
        "src/audio/wasapi/SDL_wasapi.c",
        "src/video/windows/SDL_windowsclipboard.c",
        "src/video/windows/SDL_windowsevents.c",
        "src/video/windows/SDL_windowsframebuffer.c",
        "src/video/windows/SDL_windowsgameinput.cpp",
        "src/video/windows/SDL_windowskeyboard.c",
        "src/video/windows/SDL_windowsmessagebox.c",
        "src/video/windows/SDL_windowsmodes.c",
        "src/video/windows/SDL_windowsmouse.c",
        "src/video/windows/SDL_windowsopengl.c",
        "src/video/windows/SDL_windowsopengles.c",
        "src/video/windows/SDL_windowsrawinput.c",
        "src/video/windows/SDL_windowsshape.c",
        "src/video/windows/SDL_windowsvideo.c",
        "src/video/windows/SDL_windowsvulkan.c",
        "src/video/windows/SDL_windowswindow.c",
        "src/thread/generic/SDL_syscond.c",
        "src/thread/generic/SDL_sysrwlock.c",
        "src/thread/windows/SDL_syscond_cv.c",
        "src/thread/windows/SDL_sysmutex.c",
        "src/thread/windows/SDL_sysrwlock_srw.c",
        "src/thread/windows/SDL_syssem.c",
        "src/thread/windows/SDL_systhread.c",
        "src/thread/windows/SDL_systls.c",
        "src/sensor/windows/SDL_windowssensor.c",
        "src/power/windows/SDL_syspower.c",
        "src/locale/windows/SDL_syslocale.c",
        "src/filesystem/windows/SDL_sysfilesystem.c",
        "src/filesystem/windows/SDL_sysfsops.c",
        "src/time/windows/SDL_systime.c",
        "src/timer/windows/SDL_systimer.c",
        "src/loadso/windows/SDL_sysloadso.c",
        "src/tray/windows/SDL_tray.c",
        "src/joystick/windows/SDL_dinputjoystick.c",
        "src/joystick/windows/SDL_rawinputjoystick.c",
        "src/joystick/windows/SDL_windows_gaming_input.c",
        "src/joystick/windows/SDL_windowsjoystick.c",
        "src/joystick/windows/SDL_xinputjoystick.c",
        "src/haptic/windows/SDL_dinputhaptic.c",
        "src/haptic/windows/SDL_windowshaptic.c",
        "src/camera/mediafoundation/SDL_camera_mediafoundation.c",
        "src/dialog/windows/SDL_windowsdialog.c",
        "src/process/windows/SDL_windowsprocess.c",
        "src/gpu/d3d12/SDL_gpu_d3d12.c",
    };
    /// The sources only an MSVC build of Windows adds (GameInput).
    const msvc_sources = [_][]const u8{
        "src/joystick/gdk/SDL_gameinputjoystick.cpp",
    };
    /// Linux's own sources (X11, Wayland, KMS/DRM, ALSA, PipeWire and so on).
    const linux_sources = [_][]const u8{
        "src/audio/alsa/SDL_alsa_audio.c",
        "src/audio/jack/SDL_jackaudio.c",
        "src/audio/pipewire/SDL_pipewire.c",
        "src/camera/pipewire/SDL_camera_pipewire.c",
        "src/audio/pulseaudio/SDL_pulseaudio.c",
        "src/audio/sndio/SDL_sndioaudio.c",
        "src/video/x11/SDL_x11clipboard.c",
        "src/video/x11/SDL_x11dyn.c",
        "src/video/x11/SDL_x11events.c",
        "src/video/x11/SDL_x11framebuffer.c",
        "src/video/x11/SDL_x11keyboard.c",
        "src/video/x11/SDL_x11messagebox.c",
        "src/video/x11/SDL_x11modes.c",
        "src/video/x11/SDL_x11mouse.c",
        "src/video/x11/SDL_x11opengl.c",
        "src/video/x11/SDL_x11opengles.c",
        "src/video/x11/SDL_x11pen.c",
        "src/video/x11/SDL_x11settings.c",
        "src/video/x11/SDL_x11shape.c",
        "src/video/x11/SDL_x11toolkit.c",
        "src/video/x11/SDL_x11touch.c",
        "src/video/x11/SDL_x11video.c",
        "src/video/x11/SDL_x11vulkan.c",
        "src/video/x11/SDL_x11window.c",
        "src/video/x11/SDL_x11xfixes.c",
        "src/video/x11/SDL_x11xinput2.c",
        "src/video/x11/SDL_x11xsync.c",
        "src/video/x11/SDL_x11xtest.c",
        "src/video/x11/edid-parse.c",
        "src/video/x11/xsettings-client.c",
        "src/video/kmsdrm/SDL_kmsdrmdyn.c",
        "src/video/kmsdrm/SDL_kmsdrmevents.c",
        "src/video/kmsdrm/SDL_kmsdrmmouse.c",
        "src/video/kmsdrm/SDL_kmsdrmopengles.c",
        "src/video/kmsdrm/SDL_kmsdrmvideo.c",
        "src/video/kmsdrm/SDL_kmsdrmvulkan.c",
        "src/video/wayland/SDL_waylandclipboard.c",
        "src/video/wayland/SDL_waylandcolor.c",
        "src/video/wayland/SDL_waylanddatamanager.c",
        "src/video/wayland/SDL_waylanddyn.c",
        "src/video/wayland/SDL_waylandevents.c",
        "src/video/wayland/SDL_waylandkeyboard.c",
        "src/video/wayland/SDL_waylandmessagebox.c",
        "src/video/wayland/SDL_waylandmouse.c",
        "src/video/wayland/SDL_waylandopengles.c",
        "src/video/wayland/SDL_waylandshmbuffer.c",
        "src/video/wayland/SDL_waylandutil.c",
        "src/video/wayland/SDL_waylandvideo.c",
        "src/video/wayland/SDL_waylandvulkan.c",
        "src/video/wayland/SDL_waylandwindow.c",
        "src/tray/unix/SDL_tray.c",
        "src/core/unix/SDL_appid.c",
        "src/core/unix/SDL_fribidi.c",
        "src/core/unix/SDL_gtk.c",
        "src/core/unix/SDL_libthai.c",
        "src/core/unix/SDL_poll.c",
        "src/camera/v4l2/SDL_camera_v4l2.c",
        "src/haptic/linux/SDL_syshaptic.c",
        "src/core/linux/SDL_dbus.c",
        "src/core/linux/SDL_system_theme.c",
        "src/core/linux/SDL_progressbar.c",
        "src/core/linux/SDL_ime.c",
        "src/core/linux/SDL_ibus.c",
        "src/core/linux/SDL_fcitx.c",
        "src/core/linux/SDL_udev.c",
        "src/core/linux/SDL_evdev.c",
        "src/core/linux/SDL_evdev_kbd.c",
        "src/io/io_uring/SDL_asyncio_liburing.c",
        "src/core/linux/SDL_evdev_capabilities.c",
        "src/core/linux/SDL_threadprio.c",
        "src/joystick/linux/SDL_sysjoystick.c",
        "src/misc/unix/SDL_sysurl.c",
        "src/power/linux/SDL_syspower.c",
        "src/locale/unix/SDL_syslocale.c",
        "src/filesystem/unix/SDL_sysfilesystem.c",
        "src/dialog/unix/SDL_unixdialog.c",
        "src/dialog/unix/SDL_portaldialog.c",
        "src/dialog/unix/SDL_zenitydialog.c",
        "src/dialog/unix/SDL_zenitymessagebox.c",
    };
    /// macOS's own sources (Cocoa, Metal, Core Audio and so on).
    const macos_sources = [_][]const u8{
        "src/camera/coremedia/SDL_camera_coremedia.m",
        "src/misc/macos/SDL_sysurl.m",
        "src/audio/coreaudio/SDL_coreaudio.m",
        "src/joystick/apple/SDL_mfijoystick.m",
        "src/joystick/darwin/SDL_iokitjoystick.c",
        "src/haptic/darwin/SDL_syshaptic.c",
        "src/power/macos/SDL_syspower.c",
        "src/locale/macos/SDL_syslocale.m",
        "src/filesystem/cocoa/SDL_sysfilesystem.m",
        "src/video/cocoa/SDL_cocoaclipboard.m",
        "src/video/cocoa/SDL_cocoaevents.m",
        "src/video/cocoa/SDL_cocoakeyboard.m",
        "src/video/cocoa/SDL_cocoamessagebox.m",
        "src/video/cocoa/SDL_cocoametalview.m",
        "src/video/cocoa/SDL_cocoamodes.m",
        "src/video/cocoa/SDL_cocoamouse.m",
        "src/video/cocoa/SDL_cocoaopengl.m",
        "src/video/cocoa/SDL_cocoaopengles.m",
        "src/video/cocoa/SDL_cocoapen.m",
        "src/video/cocoa/SDL_cocoashape.m",
        "src/video/cocoa/SDL_cocoavideo.m",
        "src/video/cocoa/SDL_cocoavulkan.m",
        "src/video/cocoa/SDL_cocoawindow.m",
        "src/render/metal/SDL_render_metal.m",
        "src/gpu/metal/SDL_gpu_metal.m",
        "src/tray/cocoa/SDL_tray.m",
        "src/dialog/cocoa/SDL_cocoadialog.m",
    };
    /// Build SDL3 as a static library from the `sdl` dependency, or null on the first configure while a lazy dependency is still being fetched (the build then reruns).
    ///
    /// - `b`: the build graph of the package whose build.zig.zon declares `sdl` and `sdl_linux_deps` (ziggui's).
    /// - `options`: target, optimize, SDK.
    /// - Returns: the SDL3 library, with its public headers installed so `sdl_library.getEmittedIncludeTree()` has `SDL3/SDL.h`; null while fetching.
    pub fn library(b: *std.Build, options: SdlOptions) ?*std.Build.Step.Compile {
        const target = &options.target.result;
        const platform = Platform.init(target);
        if (!platform.supported()) {
            log.err("SDL3 builds for macOS, Windows and Linux only, not {t}", .{target.os.tag});
            std.process.exit(1);
        }
        const explicit_macos = platform.macos and !options.target.query.isNative();
        if (explicit_macos and options.macos_sdk == null) {
            log.err("an explicit macOS target needs the SDK root in SdlOptions.macos_sdk (xcrun --show-sdk-path)", .{});
            std.process.exit(1);
        }

        // Ask for every lazy dependency the target needs before returning, so one fetch gets them all.
        const source_or_null = b.dependencyLazy("sdl", .{}) catch null;
        const linux_dependencies = if (platform.linux) (b.dependencyLazy("sdl_linux_deps", .{}) catch null) else null;
        const source = source_or_null orelse return null;
        if (platform.linux and linux_dependencies == null) return null;

        const module = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
        });
        const sdl_library = b.addLibrary(.{
            .linkage = .static,
            .name = "SDL3",
            .root_module = module,
        });

        const build_config = platform.buildConfigHeader(b, source);
        const revision = b.addConfigHeader(.{
            .style = .{ .cmake = source.path("include/build_config/SDL_revision.h.cmake") },
            .include_path = "SDL3/SDL_revision.h",
        }, .{
            .SDL_VENDOR_INFO = vendor_info,
        });

        module.addCMacro("USING_GENERATED_CONFIG_H", "1");
        module.addCMacro("SDL_BUILD_MAJOR_VERSION", std.fmt.comptimePrint("{d}", .{version.major}));
        module.addCMacro("SDL_BUILD_MINOR_VERSION", std.fmt.comptimePrint("{d}", .{version.minor}));
        module.addCMacro("SDL_BUILD_MICRO_VERSION", std.fmt.comptimePrint("{d}", .{version.patch}));
        module.addCMacro("SDL_STATIC_LIB", "1");
        if (platform.msvc) {
            module.addCMacro("_CRT_SECURE_NO_DEPRECATE", "1");
            module.addCMacro("_CRT_NONSTDC_NO_DEPRECATE", "1");
            module.addCMacro("_CRT_SECURE_NO_WARNINGS", "1");
        }

        // The generated headers come first, so they shadow the release's `SDL_revision.h`.
        module.addConfigHeader(build_config);
        module.addConfigHeader(revision);
        module.addIncludePath(source.path("include"));
        module.addIncludePath(source.path("src"));
        module.addSystemIncludePath(source.path("src/video/khronos"));
        if (linux_dependencies) |dependencies| {
            module.addIncludePath(dependencies.path("src"));
            module.addSystemIncludePath(dependencies.path("include"));
            if (platform.linuxArchitectureHeaders()) |headers| module.addSystemIncludePath(dependencies.path(headers));
        }
        if (explicit_macos) Self.addMacosSdk(b, module, options.macos_sdk.?);

        Self.addSources(module, source, linux_dependencies, &platform);
        Self.linkSystem(module, &platform);

        sdl_library.installHeadersDirectory(source.path("include/SDL3"), "SDL3", .{ .exclude_extensions = &excluded_headers });
        sdl_library.installConfigHeader(revision);
        return sdl_library;
    }

    /// Point SDL's compile and link at a macOS SDK, for an explicit macOS target Zig does not probe.
    ///
    /// - `b`: the build graph.
    /// - `module`: SDL's module.
    /// - `sdk`: the SDK root.
    fn addMacosSdk(b: *std.Build, module: *std.Build.Module, sdk: []const u8) void {
        module.addSystemIncludePath(b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "usr/include" })));
        module.addSystemFrameworkPath(b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "System/Library/Frameworks" })));
        module.addLibraryPath(b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "usr/lib" })));
    }

    /// Add the platform's C, C++ and Objective-C sources.
    ///
    /// - `module`: SDL's module.
    /// - `source`: the `sdl` dependency.
    /// - `linux_dependencies`: the `sdl_linux_deps` dependency on Linux, null elsewhere.
    /// - `platform`: the platform.
    fn addSources(module: *std.Build.Module, source: *std.Build.Dependency, linux_dependencies: ?*std.Build.Dependency, platform: *const Platform) void {
        const flags: []const []const u8 = if (platform.macos) &macos_flags else if (platform.linux) &linux_flags else &common_flags;
        const root = source.path(".");
        module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &core_sources });
        module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &libm_sources });
        module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &driver_sources });
        module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &hidapi_sources });
        if (platform.linux or platform.macos) module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &unix_sources });
        if (platform.windows) module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &windows_sources });
        if (platform.msvc) module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &msvc_sources });
        if (platform.linux) module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &linux_sources });
        if (platform.macos) module.addCSourceFiles(.{ .root = root, .flags = flags, .files = &macos_sources });
        if (linux_dependencies) |dependencies| module.addCSourceFiles(.{ .root = dependencies.path("."), .flags = flags, .files = &LinuxDependencies.wayland_sources });
    }

    /// Link the system libraries or frameworks SDL needs, so linking SDL brings them along.
    ///
    /// - `module`: SDL's module.
    /// - `platform`: the platform.
    fn linkSystem(module: *std.Build.Module, platform: *const Platform) void {
        if (platform.windows) {
            for (windows_libraries) |name| module.linkSystemLibrary(name, .{});
            if (platform.msvc) module.linkSystemLibrary("oldnames", .{});
        }
        if (platform.macos) {
            for (macos_frameworks) |name| module.linkFramework(name, .{});
            for (macos_weak_frameworks) |name| module.linkFramework(name, .{ .weak = true });
        }
    }
};
