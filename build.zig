const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;

const CMakeConfig = @import("CMakeConfig.zig");

const SdlOption = struct {
    name: []const u8,
    desc: []const u8,
    default: bool,
    // SDL configs affect the public SDL_config.h header file and will
    sdl_configs: []const []const u8,
    // C Macros only apply to the private SDL implementation
    c_macros: []const []const u8 = &.{ },
    sdl_files: []const []const u8 = &.{ },
    system_libs: []const []const u8 = &.{ },
};

fn applyOptions(
    b: *Build,
    lib: *Build.Step.Compile,
    files: *std.ArrayList([]const u8),
    //config_header: *Build.Step.ConfigHeader,
    config_header: *CMakeConfig,
    comptime options: []const SdlOption,
) void {
    inline for (options) |option| {
        const enabled = if (b.option(bool, option.name, option.desc)) |o| o else option.default;
        for (option.c_macros) |name| {
            std.log.info("MACRO {s}={s}", .{name, if (enabled) "1" else "0"});
            lib.defineCMacro(name, if (enabled) "1" else "0");
        }
        for (option.sdl_configs) |config| {
            // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            std.log.info("config {s}={}", .{config, if (enabled) @as(u1, 1) else @as(u1, 0)});
            config_header.values.put(config, .{ .int = if (enabled) 1 else 0 }) catch @panic("OOM");
        }
        if (enabled) {
            files.appendSlice(option.sdl_files) catch @panic("OOM");
            for (option.system_libs) |lib_name| {
                lib.linkSystemLibrary(lib_name);
            }
        }
    }
}

fn resolveHeader(target: std.Target, header: Header) []const u8 {
    return if (haveHeader(target, header, .cpp)) "1" else "0";
}

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const t = target.result;

    // we need to patch/modify files within the sdl dependency so to do that we copy
    // the entire dependency file tree into our own cache and make our modifications
    // there
    // why? for example we need to modify the file src/dynapi/SDL_dynapi.h because
    //      it's included by SDL_internal.h using #include "dynapi/SDL_dynapi.h" so there's
    //      no way to override this include
    const patch_sdl = PatchSdl.create(b);
    const sdl_patched = patch_sdl.getDirectory();

    const lib = b.addStaticLibrary(.{
        .name = "SDL2",
        .target = target,
        .optimize = optimize,
    });
    const sdl_patched_include = sdl_patched.path(b, "include");
    lib.addIncludePath(sdl_patched_include);
    lib.installHeadersDirectory(sdl_patched_include, "", .{});

    lib.addCSourceFile(.{
        .file = b.path("blank.c"),
    });
//    lib.addCSourceFiles(.{
//        .root = sdl_patched,
//        // TODO: figure out which files to add based on an automated tool?
//        .files = &.{ "src/SDL.c" },
//    });
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    // BUG? shouldn't addCSourceFiles should be calling this?
    sdl_patched.addStepDependencies(&lib.step);

    // !!!! TODO !!!
    //Create a step that will test whether a header file exists.


//    lib.defineCMacro("SDL_USE_BUILTIN_OPENGL_DEFINITIONS", "1");
    lib.linkLibC();
//    //var use_pregenerated_config = false;
//    switch (t.os.tag) {
//        .windows => {
////            use_pregenerated_config = true;
////            lib.addCSourceFiles(.{ .files = &windows_src_files });
////            lib.linkSystemLibrary("setupapi");
////            lib.linkSystemLibrary("winmm");
////            lib.linkSystemLibrary("gdi32");
////            lib.linkSystemLibrary("imm32");
////            lib.linkSystemLibrary("version");
////            lib.linkSystemLibrary("oleaut32");
////            lib.linkSystemLibrary("ole32");
//        },
////        .macos => {
////            use_pregenerated_config = true;
////            lib.addCSourceFiles(.{ .files = &darwin_src_files });
////            lib.addCSourceFiles(.{
////                .files = &objective_c_src_files,
////                .flags = &.{"-fobjc-arc"},
////            });
////            lib.linkFramework("OpenGL");
////            lib.linkFramework("Metal");
////            lib.linkFramework("CoreVideo");
////            lib.linkFramework("Cocoa");
////            lib.linkFramework("IOKit");
////            lib.linkFramework("ForceFeedback");
////            lib.linkFramework("Carbon");
////            lib.linkFramework("CoreAudio");
////            lib.linkFramework("AudioToolbox");
////            lib.linkFramework("AVFoundation");
////            lib.linkFramework("Foundation");
////        },
////        .emscripten => {
////            use_pregenerated_config = true;
////            lib.defineCMacro("__EMSCRIPTEN_PTHREADS__ ", "1");
////            lib.defineCMacro("USE_SDL", "2");
////            lib.addCSourceFiles(.{ .files = &emscripten_src_files });
////            if (b.sysroot == null) {
////                @panic("Pass '--sysroot \"$EMSDK/upstream/emscripten\"'");
////            }
////
////            const cache_include = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "cache", "sysroot", "include" }) catch @panic("Out of memory");
////            defer b.allocator.free(cache_include);
////
////            var dir = std.fs.openDirAbsolute(cache_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch @panic("No emscripten cache. Generate it!");
////            dir.close();
////
////            lib.addIncludePath(b.path(cache_include));
////        },
//        else => { },
//    }
//    if (false) {//use_pregenerated_config) {
//        lib.addCSourceFiles(.{ .files = render_driver_sw.sdl_files });
//        lib.addIncludePath(b.path("include"));
//        lib.installHeadersDirectory(b.path("include"), "SDL2", .{});
    //    } else {
    {
        var files = std.ArrayList([]const u8).init(b.allocator);
        defer files.deinit();

        files.appendSlice(&common_src_files) catch @panic("OOM");

//
//        // copy all headers except the pregenerated SDL_config.h and SDL_revision.h
//        // to another directory to avoid including them
//        const write_files = b.addWriteFiles();
//
//        _ = GlobStep.createCopyFiles(b, .{
//            .root = sdl_copy.path(b, "include"),
//            .globs = &.{ "*.h" },
//            .exclude = &.{
//                "SDL_config.h",
//                "SDL_revision.h",
//            },
//            .write_file = write_files,
//        });
//        lib.addIncludePath(write_files.getDirectory());
//        lib.installHeadersDirectory(write_files.getDirectory(), "SDL2", .{});
//
        //const config_header = //b.addConfigHeader(.{
        const config_header = CMakeConfig.create(b, .{
            .style = .{ .cmake = patch_sdl.source.path(b, "include/SDL_config.h.cmake") },
            .include_path = "SDL_config.h",
        });
        config_header.addValues(config_zig_cc);

        const have_linux_input = haveHeader(t, .linux_input, .cpp);

        const have_linux_kd = haveHeader(t, .linux_kd, .cpp);
        const have_linux_keyboard = haveHeader(t, .linux_keyboard, .cpp);
        const have_sys_ioctl = haveHeader(t, .sys_ioctl, .cpp);
        const have_sys_kbio = haveHeader(t, .sys_kbio, .cpp);
        const have_sys_time = haveHeader(t, .sys_time, .cpp);
        const have_dev_wscons_wsconsio = haveHeader(t, .dev_wscons_wsconsio, .cpp);
        const have_dev_wscons_wsksymdef = haveHeader(t, .dev_wscons_wsksymdef, .cpp);
        const have_dev_wscons_wsksymvar = haveHeader(t, .dev_wscons_wsksymvar, .cpp);

        config_header.addValues(.{
            .HAVE_STDINT_H = resolveHeader(t, .stdint),
            .HAVE_SYS_TYPES_H = resolveHeader(t, .sys_types),
            .HAVE_STDIO_H = resolveHeader(t, .stdio),
            .HAVE_STRING_H = resolveHeader(t, .string),
            .HAVE_ALLOCA_H = resolveHeader(t, .alloca),
            .HAVE_CTYPE_H = resolveHeader(t, .ctype),
            .HAVE_FLOAT_H = resolveHeader(t, .float),
            .HAVE_ICONV_H = resolveHeader(t, .iconv),
            .HAVE_INTTYPES_H = resolveHeader(t, .inttypes),
            .HAVE_LIMITS_H = resolveHeader(t, .limits),
            .HAVE_MALLOC_H = resolveHeader(t, .malloc),
            .HAVE_MATH_H = resolveHeader(t, .math),
            .HAVE_MEMORY_H = resolveHeader(t, .{ .custom = "memory.h" }),
            .HAVE_SIGNAL_H = resolveHeader(t, .signal),
            .HAVE_STDARG_H = resolveHeader(t, .stdarg),
            .HAVE_STDDEF_H = resolveHeader(t, .stddef),
            .HAVE_STDLIB_H = resolveHeader(t, .stdlib),
            .HAVE_STRINGS_H = resolveHeader(t, .strings),
            .HAVE_WCHAR_H = resolveHeader(t, .wchar),
            .SDL_HAVE_MACHINE_JOYSTICK_H = resolveHeader(t, .machine_joystick),
            .HAVE_LIBUNWIND_H = resolveHeader(t, .{ .custom = "libunwind.h" }),
            .HAVE_D3D_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_D3D11_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_D3D12_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_DDRAW_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_DSOUND_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_DINPUT_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_XINPUT_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_WINDOWS_GAMING_INPUT_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_DXGI_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_MMDEVICEAPI_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_AUDIOCLIENT_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_TPCSHRD_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_SENSORSAPI_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_ROAPI_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .HAVE_SHELLSCALINGAPI_H = switch (t.os.tag) { .windows => "1", else => "0" },
            .STDC_HEADERS = 1,
            .USE_POSIX_SPAWN = 0,
            .SDL_DEFAULT_ASSERT_LEVEL_CONFIGURED = 0,
            .SDL_DEFAULT_ASSERT_LEVEL = "",
            .SDL_ATOMIC_DISABLED = 0,
            .SDL_AUDIO_DISABLED = 0,
            .SDL_CPUINFO_DISABLED = 0,
            .SDL_EVENTS_DISABLED = 0,
            .SDL_FILE_DISABLED = 0,
            .SDL_JOYSTICK_DISABLED = 0,
            .SDL_HAPTIC_DISABLED = 0,
            .SDL_HIDAPI_DISABLED = 0,
            .SDL_SENSOR_DISABLED = 0,
            .SDL_LOADSO_DISABLED = 0,
            .SDL_RENDER_DISABLED = 0,
            .SDL_THREADS_DISABLED = 0,
            .SDL_TIMERS_DISABLED = 0,
            .SDL_VIDEO_DISABLED = 0,
            .SDL_POWER_DISABLED = 0,
            .SDL_FILESYSTEM_DISABLED = 0,
            .SDL_LOCALE_DISABLED = 0,
            .SDL_MISC_DISABLED = 0,
            .SDL_INPUT_LINUXEV = if (have_linux_input) "1" else "0",
            .SDL_INPUT_LINUXKD = if (
                (t.os.tag == .linux) and
                have_linux_kd and
                have_linux_keyboard and
                have_sys_ioctl
            ) "1" else "0",
            .SDL_INPUT_FBSDKBIO = if (
                (t.os.tag == .freebsd) and
                have_sys_kbio and
                have_sys_ioctl
            ) "1" else "0",
            .SDL_INPUT_WSCONS = if (
                (t.os.tag == .openbsd or t.os.tag == .netbsd) and
                have_sys_time and
                have_dev_wscons_wsconsio and
                have_dev_wscons_wsksymdef and
                have_dev_wscons_wsksymvar
            ) "1" else "0",

            // Options I haven't really looked at yet
            .SDL_LIBUSB_DYNAMIC = 0,
            .SDL_UDEV_DYNAMIC = 0,
            .SDL_THREAD_WINDOWS = 0,
            .SDL_VIDEO_VULKAN = 0,
            .SDL_VIDEO_METAL = 0,
            .SDL_MISC_DUMMY = 0,
            .SDL_LOCALE_DUMMY = 0,
            .SDL_ALTIVEC_BLITTERS = 0,
            .SDL_ARM_SIMD_BLITTERS = 0,
            .SDL_ARM_NEON_BLITTERS = 0,
            .SDL_LIBSAMPLERATE_DYNAMIC = 0,
            .SDL_USE_IME = 0,
            .SDL_IPHONE_KEYBOARD = 0,
            .SDL_IPHONE_LAUNCHSCREEN = 0,
            .SDL_VIDEO_VITA_PIB = 0,
            .SDL_VIDEO_VITA_PVR = 0,
            .SDL_VIDEO_VITA_PVR_OGL = 0,
            .SDL_HAVE_LIBDECOR_GET_MIN_MAX = 0,
            .DYNAPI_NEEDS_DLOPEN = 0,
        });

        addOptions(b, t, config_header, Filesystem, "filesystem_", "SDL_FILESYSTEM_");
        addOptions(b, t, config_header, Thread, "thread_", "SDL_THREAD_");
        addOptions(b, t, config_header, Timer, "timer_", "SDL_TIMER_");
        addOptions(b, t, config_header, Power, "power_", "SDL_POWER_");
        addOptions(b, t, config_header, VideoDriver, "video_driver_", "SDL_VIDEO_DRIVER_");
        addOptions(b, t, config_header, VideoRender, "video_render_", "SDL_VIDEO_RENDER_");
        addOptions(b, t, config_header, VideoOpengl, "video_", "SDL_VIDEO_");
        addOptions(b, t, config_header, AudioDriver, "audio_driver_", "SDL_AUDIO_DRIVER_");
        addOptions(b, t, config_header, Joystick, "joystick_", "SDL_JOYSTICK_");
        addOptions(b, t, config_header, Sensor, "sensor_", "SDL_SENSOR_");
        addOptions(b, t, config_header, Haptic, "haptic_", "SDL_HAPTIC_");
        addOptions(b, t, config_header, Loadso, "loadso_", "SDL_LOADSO_");

        lib.addCSourceFiles(.{
            .root = sdl_patched.path(b, "."),
            .files = files.toOwnedSlice() catch @panic("OOM"),
        });
        lib.root_module.addIncludePath(config_header.getOutput().dirname());
        std.log.info("include_path='{s}'", .{config_header.include_path});
        lib.installHeader(config_header.getOutput(), config_header.include_path);
        //lib.addConfigHeader(config_header);
        //lib.installConfigHeader(config_header);
    }
    {
        const revision_header = b.addConfigHeader(.{
            .style = .{ .cmake = patch_sdl.source.path(b, "include/SDL_revision.h.cmake") },
            .include_path = "SDL_revision.h",
        }, .{ });
        lib.addConfigHeader(revision_header);
        lib.installConfigHeader(revision_header);
    }
    {
        const dynapi_header = b.addConfigHeader(.{
            .style = .blank,
            .include_path = "dynapi/SDL_dynapi.h",
        }, .{ });
        lib.addConfigHeader(dynapi_header);
        lib.installConfigHeader(dynapi_header);
    }

    b.installArtifact(lib);
}

fn addOptions(
    b: *std.Build,
    target: std.Target,
    config_header: *CMakeConfig,
    comptime OptionEnum: type,
    comptime zigbuild_option_prefix: []const u8,
    comptime sdl_option_prefix: []const u8,
) void {
    inline for (std.meta.fields(OptionEnum)) |enum_field| {
        const name = enum_field.name;
        const value: OptionEnum = @enumFromInt(enum_field.value);
        const enabled = if (b.option(
            bool,
            zigbuild_option_prefix ++ name,
            "enable " ++ name,
        )) |o| o else value.getDefault(target);
        //lib.defineCMacro(name, if (enabled) "1" else "0");
        @setEvalBranchQuota(5000);
        const config = sdl_option_prefix ++ comptime toUpper2(
            name.len,
            name[0..name.len],
        );
        // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        std.log.info("config '{s}' = {}", .{config, if (enabled) @as(u1, 1) else @as(u1, 0)});
        config_header.values.put(config, .{ .int = if (enabled) 1 else 0 }) catch @panic("OOM");
        //if (enabled) {
        //    files.appendSlice(option.sdl_files) catch @panic("OOM");
        //    for (option.system_libs) |lib_name| {
        //        lib.linkSystemLibrary(lib_name);
        //    }
        //}
    }
}


fn ToUpper(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Pointer => |info| switch (info.size) {
            //.Slice => return [
            else => @compileError("unsupported pointer size: " ++ @tagName(info.size)),
        },
        else => @compileError("unsupported type: " ++ @typeName(T)),
    }
}
fn toUpper(s: anytype) ToUpper(@TypeOf(s)) {
    @panic("todo");
}
fn toUpper2(comptime len: usize, s: *const [len]u8) [len]u8 {
    var result: [len]u8 = undefined;
    for (&result, s) |*dst, src| {
        dst.* = std.ascii.toUpper(src);
    }
    return result;
}

const PatchSdl = struct {
    step: Build.Step,
    source: LazyPath,
    generated: Build.GeneratedFile,

    pub fn create(
        b: *Build,
    ) *PatchSdl {
        const source = b.dependency("sdl", .{}).path(".");
        const patch = b.allocator.create(PatchSdl) catch @panic("OOM");
        patch.* = .{
            .step = Build.Step.init(.{
                .id = .custom,
                .name = "Copy and patch SDL source",
                .owner = b,
                .makeFn = make,
            }),
            .source = source,
            .generated = .{ .step = &patch.step },
        };
        source.addStepDependencies(&patch.step);
        return patch;
    }

    pub fn getDirectory(self: *PatchSdl) LazyPath {
        return .{ .generated = .{ .file = &self.generated } };
    }

    fn make(step: *Build.Step, prog_node: std.Progress.Node) !void {
        _ = prog_node;
        const b = step.owner;
        const self: *PatchSdl = @fieldParentPtr("step", step);

        var man = b.graph.cache.obtain();
        defer man.deinit();

        // Random bytes to make This step unique. Refresh this with
        // new random bytes when the implementation is modified
        // in a non-backwards-compatible way.
        man.hash.add(@as(u32, 0xA349A2F2));

        const source = self.source.getPath2(b, step);
        man.hash.addBytes(source);

        if (try step.cacheHit(&man)) {
            const digest = man.final();
            self.generated.path = try b.cache_root.join(b.allocator, &.{ "o", &digest });
            std.log.info("cache_dir is '{s}'", .{self.generated.path.?});
            return;
        }

        const digest = man.final();
        const cache_path = "o" ++ std.fs.path.sep_str ++ digest;

        self.generated.path = try b.cache_root.join(b.allocator, &.{ "o", &digest });

        var cache_dir = b.cache_root.handle.makeOpenPath(cache_path, .{}) catch |err| {
            return step.fail("unable to make path '{}{s}': {s}", .{
                b.cache_root, cache_path, @errorName(err),
            });
        };
        defer cache_dir.close();
        // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        std.log.info("cache_dir is '{s}'", .{cache_path});

        const filter: FileFilter = .{
            .kind = .{
                .inclusive = &.{
                    "test",
                },
            },
            .subfilters = std.StaticStringMap(FileFilter).initComptime(.{
                .{ "include", FileFilter{
                    .kind = .{
                        .exclusive = &.{
                            "SDL_config.h",
                            "SDL_config.h.cmake",
                            "SDL_revision.h",
                            "SDL_revision.h.cmake",
                        },
                    },
                }},
                .{ "src", FileFilter{
                    //.kind = .{ .exclusive = &.{ } },
                    .subfilters = std.StaticStringMap(FileFilter).initComptime(.{
                        .{ "dynapi", FileFilter{
                            .kind = .{ .exclusive = &.{
                                "SDL_dynapi.h",
                            }},
                            .subfilters = .{},
                        }},
                    }),
                }},
            }),
        };
        try copyDir(
            step,
            std.fs.cwd(),
            source,
            cache_dir,
            filter,
            0,
        );

        try step.writeManifest(&man);
    }
};

const FileFilter = struct {
    kind: union(enum) {
        inclusive: []const []const u8,
        exclusive: []const []const u8,
    } = .{ .exclusive = &.{} },
    subfilters: std.StaticStringMap(FileFilter) = .{},

    pub fn keep(self: FileFilter, name: []const u8) bool {
        if (self.subfilters.has(name))
            return true;

        switch (self.kind) {
            .inclusive => |includes| {
                for (includes) |include| {
                    if (std.mem.eql(u8, include, name)) {
                        return true;
                    }
                }
                return false;
            },
            .exclusive => |excludes| {
                for (excludes) |exclude| {
                    if (std.mem.eql(u8, exclude, name)) {
                        return false;
                    }
                }
                return true;
            },
        }
    }
    pub fn descend(self: FileFilter, name: []const u8) FileFilter {
        return self.subfilters.get(name) orelse .{};
    }
};

fn copyDir(
    step: *std.Build.Step,
    source_parent_dir: std.fs.Dir,
    source_path: []const u8,
    dest: std.fs.Dir,
    filter: FileFilter,
    depth: u32,
) !void {
    var source_dir = try source_parent_dir.openDir(source_path, .{ .iterate = true });
    defer source_dir.close();
    var it = source_dir.iterate();
    while (try it.next()) |entry| {
        if (!filter.keep(entry.name))
            continue;
        switch (entry.kind) {
            .file => try source_dir.copyFile(entry.name, dest, entry.name, .{}),
            .directory => {
                //std.log.info("makedir '{s}'", .{entry.name});
                try dest.makeDir(entry.name);
                //std.log.info("makedir '{s}' success", .{entry.name});
                var dest_subdir = try dest.openDir(entry.name, .{});
                defer dest_subdir.close();
                //std.log.info("{}>>> copydir '{s}'", .{depth, entry.name});
                try copyDir(step, source_dir, entry.name, dest_subdir, filter.descend(entry.name), depth + 1);
                //std.log.info("{}<<< copydir '{s}'", .{depth, entry.name});
            },
            else => |kind| return step.fail("unable to copy {s}: {s}", .{@tagName(kind), entry.name}),
        }
    }
}

const common_src_files = [_][]const u8{
//    "src/SDL.c",
//    "src/SDL_assert.c",
//    "src/SDL_dataqueue.c",
//    "src/SDL_error.c",
//    "src/SDL_guid.c",
//    "src/SDL_hints.c",
//    "src/SDL_list.c",
//    "src/SDL_log.c",
//    "src/SDL_utils.c",
//    "src/atomic/SDL_atomic.c",
//    "src/atomic/SDL_spinlock.c",
//    "src/audio/SDL_audio.c",
//    "src/audio/SDL_audiocvt.c",
//    "src/audio/SDL_audiodev.c",
//    "src/audio/SDL_audiotypecvt.c",
//    "src/audio/SDL_mixer.c",
//    "src/audio/SDL_wave.c",
//    "src/cpuinfo/SDL_cpuinfo.c",
//    //"src/dynapi/SDL_dynapi.c",
//    //"src/events/imKStoUCS.c",
//    "src/events/SDL_clipboardevents.c",
//    "src/events/SDL_displayevents.c",
//    "src/events/SDL_dropevents.c",
//    "src/events/SDL_events.c",
//    "src/events/SDL_gesture.c",
//    "src/events/SDL_keyboard.c",
//    "src/events/SDL_keysym_to_scancode.c",
//    "src/events/SDL_mouse.c",
//    "src/events/SDL_quit.c",
//    "src/events/SDL_scancode_tables.c",
//    "src/events/SDL_touch.c",
//    "src/events/SDL_windowevents.c",
//    "src/file/SDL_rwops.c",
//    //"src/joystick/controller_type.c",
//    //"src/joystick/SDL_gamecontroller.c",
//    //"src/joystick/SDL_joystick.c",
//    //"src/joystick/SDL_steam_virtual_gamepad.c",
//    //"src/haptic/SDL_haptic.c",
//    //"src/hidapi/SDL_hidapi.c",
//    "src/libm/e_atan2.c",
//    "src/libm/e_exp.c",
//    "src/libm/e_fmod.c",
//    "src/libm/e_log.c",
//    "src/libm/e_log10.c",
//    "src/libm/e_pow.c",
//    "src/libm/e_rem_pio2.c",
//    "src/libm/e_sqrt.c",
//    "src/libm/k_cos.c",
//    "src/libm/k_rem_pio2.c",
//    "src/libm/k_sin.c",
//    "src/libm/k_tan.c",
//    "src/libm/s_atan.c",
//    "src/libm/s_copysign.c",
//    "src/libm/s_cos.c",
//    "src/libm/s_fabs.c",
//    "src/libm/s_floor.c",
//    "src/libm/s_scalbn.c",
//    "src/libm/s_sin.c",
//    "src/libm/s_tan.c",
//    "src/locale/SDL_locale.c",
//    "src/misc/SDL_url.c",
//    "src/power/SDL_power.c",
//    //"src/render/SDL_d3dmath.c",
//    //"src/render/SDL_render.c",
//    //"src/render/SDL_yuv_sw.c",
//    //"src/render/direct3d/SDL_render_d3d.c",
//    //"src/render/direct3d/SDL_shaders_d3d.c",
//    //"src/render/direct3d11/SDL_render_d3d11.c",
//    //"src/render/direct3d11/SDL_shaders_d3d11.c",
//    //"src/render/direct3d12/SDL_render_d3d12.c",
//    //"src/render/direct3d12/SDL_shaders_d3d12.c",
//    //"src/render/opengl/SDL_render_gl.c",
//    //"src/render/opengl/SDL_shaders_gl.c",
//    //"src/render/opengles/SDL_render_gles.c",
//    //"src/render/opengles2/SDL_render_gles2.c",
//    //"src/render/opengles2/SDL_shaders_gles2.c",
//    //"src/render/ps2/SDL_render_ps2.c",
//    //"src/render/psp/SDL_render_psp.c",
//    //"src/render/software/SDL_blendfillrect.c",
//    //"src/render/software/SDL_blendline.c",
//    //"src/render/software/SDL_blendpoint.c",
//    //"src/render/software/SDL_drawline.c",
//    //"src/render/software/SDL_drawpoint.c",
//    //"src/render/software/SDL_render_sw.c",
//    //"src/render/software/SDL_rotate.c",
//    //"src/render/software/SDL_triangle.c",
//    //"src/render/vitagxm/SDL_render_vita_gxm.c",
//    //"src/render/vitagxm/SDL_render_vita_gxm_memory.c",
//    //"src/render/vitagxm/SDL_render_vita_gxm_tools.c",
//    //"src/sensor/SDL_sensor.c",
    "src/stdlib/SDL_crc16.c",
    "src/stdlib/SDL_crc32.c",
    "src/stdlib/SDL_getenv.c",
    "src/stdlib/SDL_iconv.c",
    "src/stdlib/SDL_malloc.c",
    "src/stdlib/SDL_mslibc.c",
    "src/stdlib/SDL_qsort.c",
    "src/stdlib/SDL_stdlib.c",
    "src/stdlib/SDL_string.c",
    "src/stdlib/SDL_strtokr.c",
//    "src/thread/SDL_thread.c",
//    "src/timer/SDL_timer.c",
//    //"src/video/SDL_blit.c",
//    //"src/video/SDL_blit_0.c",
//    //"src/video/SDL_blit_1.c",
//    //"src/video/SDL_blit_A.c",
//    //"src/video/SDL_blit_auto.c",
//    //"src/video/SDL_blit_copy.c",
//    //"src/video/SDL_blit_N.c",
//    //"src/video/SDL_blit_slow.c",
//    //"src/video/SDL_bmp.c",
//    //"src/video/SDL_clipboard.c",
//    //"src/video/SDL_egl.c",
//    //"src/video/SDL_fillrect.c",
//    //"src/video/SDL_pixels.c",
//    //"src/video/SDL_rect.c",
//    //"src/video/SDL_RLEaccel.c",
//    //"src/video/SDL_shape.c",
//    //"src/video/SDL_stretch.c",
//    //"src/video/SDL_surface.c",
//    //"src/video/SDL_video.c",
//    //"src/video/SDL_vulkan_utils.c",
//    //"src/video/SDL_yuv.c",
//    //"src/video/yuv2rgb/yuv_rgb_lsx.c",
//    //"src/video/yuv2rgb/yuv_rgb_sse.c",
//    //"src/video/yuv2rgb/yuv_rgb_std.c",
};
//
//const window_src_files = [_][]const u8{
//    "src/core/windows/SDL_windows.c",
//    "src/filesystem/windows/SDL_sysfilesystem.c",
//};

//const windows_src_files = [_][]const u8{
//    "src/core/windows/SDL_hid.c",
//    "src/core/windows/SDL_immdevice.c",
//    "src/core/windows/SDL_xinput.c",
//    "src/filesystem/windows/SDL_sysfilesystem.c",
//    "src/haptic/windows/SDL_dinputhaptic.c",
//    "src/haptic/windows/SDL_windowshaptic.c",
//    "src/haptic/windows/SDL_xinputhaptic.c",
//    "src/hidapi/windows/hid.c",
//    "src/joystick/windows/SDL_dinputjoystick.c",
//    "src/joystick/windows/SDL_rawinputjoystick.c",
//    // This can be enabled when Zig updates to the next mingw-w64 release,
//    // which will make the headers gain `windows.gaming.input.h`.
//    // Also revert the patch 2c79fd8fd04f1e5045cbe5978943b0aea7593110.
//    //"src/joystick/windows/SDL_windows_gaming_input.c",
//    "src/joystick/windows/SDL_windowsjoystick.c",
//    "src/joystick/windows/SDL_xinputjoystick.c",
//
//    "src/loadso/windows/SDL_sysloadso.c",
//    "src/locale/windows/SDL_syslocale.c",
//    "src/main/windows/SDL_windows_main.c",
//    "src/misc/windows/SDL_sysurl.c",
//    "src/power/windows/SDL_syspower.c",
//    "src/sensor/windows/SDL_windowssensor.c",
//    "src/timer/windows/SDL_systimer.c",
//    "src/video/windows/SDL_windowsclipboard.c",
//    "src/video/windows/SDL_windowsevents.c",
//    "src/video/windows/SDL_windowsframebuffer.c",
//    "src/video/windows/SDL_windowskeyboard.c",
//    "src/video/windows/SDL_windowsmessagebox.c",
//    "src/video/windows/SDL_windowsmodes.c",
//    "src/video/windows/SDL_windowsmouse.c",
//    "src/video/windows/SDL_windowsopengl.c",
//    "src/video/windows/SDL_windowsopengles.c",
//    "src/video/windows/SDL_windowsshape.c",
//    "src/video/windows/SDL_windowsvideo.c",
//    "src/video/windows/SDL_windowsvulkan.c",
//    "src/video/windows/SDL_windowswindow.c",
//
//    "src/thread/windows/SDL_syscond_cv.c",
//    "src/thread/windows/SDL_sysmutex.c",
//    "src/thread/windows/SDL_syssem.c",
//    "src/thread/windows/SDL_systhread.c",
//    "src/thread/windows/SDL_systls.c",
//    "src/thread/generic/SDL_syscond.c",
//
//    "src/render/direct3d/SDL_render_d3d.c",
//    "src/render/direct3d/SDL_shaders_d3d.c",
//    "src/render/direct3d11/SDL_render_d3d11.c",
//    "src/render/direct3d11/SDL_shaders_d3d11.c",
//    "src/render/direct3d12/SDL_render_d3d12.c",
//    "src/render/direct3d12/SDL_shaders_d3d12.c",
//
//    "src/audio/directsound/SDL_directsound.c",
//    "src/audio/wasapi/SDL_wasapi.c",
//    "src/audio/wasapi/SDL_wasapi_win32.c",
//    "src/audio/winmm/SDL_winmm.c",
//    "src/audio/disk/SDL_diskaudio.c",
//
//    "src/render/opengl/SDL_render_gl.c",
//    "src/render/opengl/SDL_shaders_gl.c",
//    "src/render/opengles/SDL_render_gles.c",
//    "src/render/opengles2/SDL_render_gles2.c",
//    "src/render/opengles2/SDL_shaders_gles2.c",
//};
//
//const linux_src_files = [_][]const u8{
//    //"src/core/linux/SDL_dbus.c",
//    //"src/core/linux/SDL_evdev.c",
//    //"src/core/linux/SDL_evdev_capabilities.c",
//    //"src/core/linux/SDL_evdev_kbd.c",
//    //"src/core/linux/SDL_fcitx.c",
//    //"src/core/linux/SDL_ibus.c",
//    //"src/core/linux/SDL_ime.c",
//    //"src/core/linux/SDL_sandbox.c",
//    "src/core/linux/SDL_threadprio.c",
//    //"src/core/linux/SDL_udev.c",
//    "src/core/unix/SDL_poll.c",
//
//    "src/filesystem/unix/SDL_sysfilesystem.c",
//
//    "src/haptic/linux/SDL_syshaptic.c",
//    //"src/hidapi/linux/hid.c",
//
//    "src/loadso/dlopen/SDL_sysloadso.c",
//    "src/joystick/linux/SDL_sysjoystick.c",
//    "src/joystick/dummy/SDL_sysjoystick.c",
//
//    "src/misc/unix/SDL_sysurl.c",
//
//    //"src/power/linux/SDL_syspower.c",
//
//    "src/thread/pthread/SDL_sysmutex.c",
//    "src/thread/pthread/SDL_syssem.c",
//    "src/thread/pthread/SDL_systhread.c",
//    "src/thread/pthread/SDL_systls.c",
//
//    "src/timer/unix/SDL_systimer.c",
//
//    //"src/video/wayland/SDL_waylandclipboard.c",
//    //"src/video/wayland/SDL_waylanddatamanager.c",
//    //"src/video/wayland/SDL_waylanddyn.c",
//    //"src/video/wayland/SDL_waylandevents.c",
//    //"src/video/wayland/SDL_waylandkeyboard.c",
//    //"src/video/wayland/SDL_waylandmessagebox.c",
//    //"src/video/wayland/SDL_waylandmouse.c",
//    //"src/video/wayland/SDL_waylandopengles.c",
//    //"src/video/wayland/SDL_waylandtouch.c",
//    //"src/video/wayland/SDL_waylandvideo.c",
//    //"src/video/wayland/SDL_waylandvulkan.c",
//    //"src/video/wayland/SDL_waylandwindow.c",
//
//    "src/video/x11/SDL_x11clipboard.c",
//    "src/video/x11/SDL_x11dyn.c",
//    "src/video/x11/SDL_x11events.c",
//    "src/video/x11/SDL_x11framebuffer.c",
//    "src/video/x11/SDL_x11keyboard.c",
//    "src/video/x11/SDL_x11messagebox.c",
//    "src/video/x11/SDL_x11modes.c",
//    "src/video/x11/SDL_x11mouse.c",
//    "src/video/x11/SDL_x11opengl.c",
//    "src/video/x11/SDL_x11opengles.c",
//    "src/video/x11/SDL_x11shape.c",
//    "src/video/x11/SDL_x11touch.c",
//    "src/video/x11/SDL_x11video.c",
//    "src/video/x11/SDL_x11vulkan.c",
//    "src/video/x11/SDL_x11window.c",
//    "src/video/x11/SDL_x11xfixes.c",
//    "src/video/x11/SDL_x11xinput2.c",
//    "src/video/x11/edid-parse.c",
//
//    //"src/audio/jack/SDL_jackaudio.c",
//    //"src/audio/pulseaudio/SDL_pulseaudio.c",
//};
//
//const darwin_src_files = [_][]const u8{
//    "src/haptic/darwin/SDL_syshaptic.c",
//    "src/joystick/darwin/SDL_iokitjoystick.c",
//    "src/power/macosx/SDL_syspower.c",
//    "src/timer/unix/SDL_systimer.c",
//    "src/loadso/dlopen/SDL_sysloadso.c",
//    "src/audio/disk/SDL_diskaudio.c",
//    "src/render/opengl/SDL_render_gl.c",
//    "src/render/opengl/SDL_shaders_gl.c",
//    "src/render/opengles/SDL_render_gles.c",
//    "src/render/opengles2/SDL_render_gles2.c",
//    "src/render/opengles2/SDL_shaders_gles2.c",
//    "src/sensor/dummy/SDL_dummysensor.c",
//
//    "src/thread/pthread/SDL_syscond.c",
//    "src/thread/pthread/SDL_sysmutex.c",
//    "src/thread/pthread/SDL_syssem.c",
//    "src/thread/pthread/SDL_systhread.c",
//    "src/thread/pthread/SDL_systls.c",
//};
//
//const objective_c_src_files = [_][]const u8{
//    "src/audio/coreaudio/SDL_coreaudio.m",
//    "src/file/cocoa/SDL_rwopsbundlesupport.m",
//    "src/filesystem/cocoa/SDL_sysfilesystem.m",
//    //"src/hidapi/testgui/mac_support_cocoa.m",
//    // This appears to be for SDL3 only.
//    //"src/joystick/apple/SDL_mfijoystick.m",
//    "src/locale/macosx/SDL_syslocale.m",
//    "src/misc/macosx/SDL_sysurl.m",
//    "src/power/uikit/SDL_syspower.m",
//    "src/render/metal/SDL_render_metal.m",
//    "src/sensor/coremotion/SDL_coremotionsensor.m",
//    "src/video/cocoa/SDL_cocoaclipboard.m",
//    "src/video/cocoa/SDL_cocoaevents.m",
//    "src/video/cocoa/SDL_cocoakeyboard.m",
//    "src/video/cocoa/SDL_cocoamessagebox.m",
//    "src/video/cocoa/SDL_cocoametalview.m",
//    "src/video/cocoa/SDL_cocoamodes.m",
//    "src/video/cocoa/SDL_cocoamouse.m",
//    "src/video/cocoa/SDL_cocoaopengl.m",
//    "src/video/cocoa/SDL_cocoaopengles.m",
//    "src/video/cocoa/SDL_cocoashape.m",
//    "src/video/cocoa/SDL_cocoavideo.m",
//    "src/video/cocoa/SDL_cocoavulkan.m",
//    "src/video/cocoa/SDL_cocoawindow.m",
//    "src/video/uikit/SDL_uikitappdelegate.m",
//    "src/video/uikit/SDL_uikitclipboard.m",
//    "src/video/uikit/SDL_uikitevents.m",
//    "src/video/uikit/SDL_uikitmessagebox.m",
//    "src/video/uikit/SDL_uikitmetalview.m",
//    "src/video/uikit/SDL_uikitmodes.m",
//    "src/video/uikit/SDL_uikitopengles.m",
//    "src/video/uikit/SDL_uikitopenglview.m",
//    "src/video/uikit/SDL_uikitvideo.m",
//    "src/video/uikit/SDL_uikitview.m",
//    "src/video/uikit/SDL_uikitviewcontroller.m",
//    "src/video/uikit/SDL_uikitvulkan.m",
//    "src/video/uikit/SDL_uikitwindow.m",
//};
//
//const ios_src_files = [_][]const u8{
//    "src/hidapi/ios/hid.m",
//    "src/misc/ios/SDL_sysurl.m",
//    "src/joystick/iphoneos/SDL_mfijoystick.m",
//};
//
//const emscripten_src_files = [_][]const u8{
//    "src/audio/emscripten/SDL_emscriptenaudio.c",
//    "src/filesystem/emscripten/SDL_sysfilesystem.c",
//    "src/joystick/emscripten/SDL_sysjoystick.c",
//    "src/locale/emscripten/SDL_syslocale.c",
//    "src/misc/emscripten/SDL_sysurl.c",
//    "src/power/emscripten/SDL_syspower.c",
//    "src/video/emscripten/SDL_emscriptenevents.c",
//    "src/video/emscripten/SDL_emscriptenframebuffer.c",
//    "src/video/emscripten/SDL_emscriptenmouse.c",
//    "src/video/emscripten/SDL_emscriptenopengles.c",
//    "src/video/emscripten/SDL_emscriptenvideo.c",
//
//    "src/timer/unix/SDL_systimer.c",
//    "src/loadso/dlopen/SDL_sysloadso.c",
//    "src/audio/disk/SDL_diskaudio.c",
//    "src/render/opengles2/SDL_render_gles2.c",
//    "src/render/opengles2/SDL_shaders_gles2.c",
//    "src/sensor/dummy/SDL_dummysensor.c",
//
//    "src/thread/pthread/SDL_syscond.c",
//    "src/thread/pthread/SDL_sysmutex.c",
//    "src/thread/pthread/SDL_syssem.c",
//    "src/thread/pthread/SDL_systhread.c",
//    "src/thread/pthread/SDL_systls.c",
//};
//
//const unknown_src_files = [_][]const u8{
//    "src/thread/generic/SDL_syscond.c",
//    "src/thread/generic/SDL_sysmutex.c",
//    "src/thread/generic/SDL_syssem.c",
//    "src/thread/generic/SDL_systhread.c",
//    "src/thread/generic/SDL_systls.c",
//
//    "src/audio/aaudio/SDL_aaudio.c",
//    "src/audio/android/SDL_androidaudio.c",
//    "src/audio/arts/SDL_artsaudio.c",
//    "src/audio/dsp/SDL_dspaudio.c",
//    "src/audio/esd/SDL_esdaudio.c",
//    "src/audio/fusionsound/SDL_fsaudio.c",
//    "src/audio/n3ds/SDL_n3dsaudio.c",
//    "src/audio/nacl/SDL_naclaudio.c",
//    "src/audio/nas/SDL_nasaudio.c",
//    "src/audio/netbsd/SDL_netbsdaudio.c",
//    "src/audio/openslES/SDL_openslES.c",
//    "src/audio/os2/SDL_os2audio.c",
//    "src/audio/paudio/SDL_paudio.c",
//    "src/audio/pipewire/SDL_pipewire.c",
//    "src/audio/ps2/SDL_ps2audio.c",
//    "src/audio/psp/SDL_pspaudio.c",
//    "src/audio/qsa/SDL_qsa_audio.c",
//    "src/audio/sndio/SDL_sndioaudio.c",
//    "src/audio/sun/SDL_sunaudio.c",
//    "src/audio/vita/SDL_vitaaudio.c",
//
//    "src/core/android/SDL_android.c",
//    "src/core/freebsd/SDL_evdev_kbd_freebsd.c",
//    "src/core/openbsd/SDL_wscons_kbd.c",
//    "src/core/openbsd/SDL_wscons_mouse.c",
//    "src/core/os2/SDL_os2.c",
//    "src/core/os2/geniconv/geniconv.c",
//    "src/core/os2/geniconv/os2cp.c",
//    "src/core/os2/geniconv/os2iconv.c",
//    "src/core/os2/geniconv/sys2utf8.c",
//    "src/core/os2/geniconv/test.c",
//    "src/core/unix/SDL_poll.c",
//
//    "src/file/n3ds/SDL_rwopsromfs.c",
//
//    "src/filesystem/android/SDL_sysfilesystem.c",
//    "src/filesystem/dummy/SDL_sysfilesystem.c",
//    "src/filesystem/n3ds/SDL_sysfilesystem.c",
//    "src/filesystem/nacl/SDL_sysfilesystem.c",
//    "src/filesystem/os2/SDL_sysfilesystem.c",
//    "src/filesystem/ps2/SDL_sysfilesystem.c",
//    "src/filesystem/psp/SDL_sysfilesystem.c",
//    "src/filesystem/riscos/SDL_sysfilesystem.c",
//    "src/filesystem/unix/SDL_sysfilesystem.c",
//    "src/filesystem/vita/SDL_sysfilesystem.c",
//
//    "src/haptic/android/SDL_syshaptic.c",
//    "src/haptic/dummy/SDL_syshaptic.c",
//
//    "src/hidapi/libusb/hid.c",
//    "src/hidapi/mac/hid.c",
//
//    "src/joystick/android/SDL_sysjoystick.c",
//    "src/joystick/bsd/SDL_bsdjoystick.c",
//    "src/joystick/dummy/SDL_sysjoystick.c",
//    "src/joystick/n3ds/SDL_sysjoystick.c",
//    "src/joystick/os2/SDL_os2joystick.c",
//    "src/joystick/ps2/SDL_sysjoystick.c",
//    "src/joystick/psp/SDL_sysjoystick.c",
//    "src/joystick/steam/SDL_steamcontroller.c",
//    "src/joystick/vita/SDL_sysjoystick.c",
//
//    "src/loadso/dummy/SDL_sysloadso.c",
//    "src/loadso/os2/SDL_sysloadso.c",
//
//    "src/locale/android/SDL_syslocale.c",
//    "src/locale/dummy/SDL_syslocale.c",
//    "src/locale/n3ds/SDL_syslocale.c",
//    "src/locale/unix/SDL_syslocale.c",
//    "src/locale/vita/SDL_syslocale.c",
//    "src/locale/winrt/SDL_syslocale.c",
//
//    "src/main/android/SDL_android_main.c",
//    "src/main/dummy/SDL_dummy_main.c",
//    "src/main/gdk/SDL_gdk_main.c",
//    "src/main/n3ds/SDL_n3ds_main.c",
//    "src/main/nacl/SDL_nacl_main.c",
//    "src/main/ps2/SDL_ps2_main.c",
//    "src/main/psp/SDL_psp_main.c",
//    "src/main/uikit/SDL_uikit_main.c",
//
//    "src/misc/android/SDL_sysurl.c",
//    "src/misc/dummy/SDL_sysurl.c",
//    "src/misc/riscos/SDL_sysurl.c",
//    "src/misc/unix/SDL_sysurl.c",
//    "src/misc/vita/SDL_sysurl.c",
//
//    "src/power/android/SDL_syspower.c",
//    "src/power/haiku/SDL_syspower.c",
//    "src/power/n3ds/SDL_syspower.c",
//    "src/power/psp/SDL_syspower.c",
//    "src/power/vita/SDL_syspower.c",
//
//    "src/sensor/android/SDL_androidsensor.c",
//    "src/sensor/n3ds/SDL_n3dssensor.c",
//    "src/sensor/vita/SDL_vitasensor.c",
//
//    "src/test/SDL_test_assert.c",
//    "src/test/SDL_test_common.c",
//    "src/test/SDL_test_compare.c",
//    "src/test/SDL_test_crc32.c",
//    "src/test/SDL_test_font.c",
//    "src/test/SDL_test_fuzzer.c",
//    "src/test/SDL_test_harness.c",
//    "src/test/SDL_test_imageBlit.c",
//    "src/test/SDL_test_imageBlitBlend.c",
//    "src/test/SDL_test_imageFace.c",
//    "src/test/SDL_test_imagePrimitives.c",
//    "src/test/SDL_test_imagePrimitivesBlend.c",
//    "src/test/SDL_test_log.c",
//    "src/test/SDL_test_md5.c",
//    "src/test/SDL_test_memory.c",
//    "src/test/SDL_test_random.c",
//
//    "src/thread/n3ds/SDL_syscond.c",
//    "src/thread/n3ds/SDL_sysmutex.c",
//    "src/thread/n3ds/SDL_syssem.c",
//    "src/thread/n3ds/SDL_systhread.c",
//    "src/thread/os2/SDL_sysmutex.c",
//    "src/thread/os2/SDL_syssem.c",
//    "src/thread/os2/SDL_systhread.c",
//    "src/thread/os2/SDL_systls.c",
//    "src/thread/ps2/SDL_syssem.c",
//    "src/thread/ps2/SDL_systhread.c",
//    "src/thread/psp/SDL_syscond.c",
//    "src/thread/psp/SDL_sysmutex.c",
//    "src/thread/psp/SDL_syssem.c",
//    "src/thread/psp/SDL_systhread.c",
//    "src/thread/vita/SDL_syscond.c",
//    "src/thread/vita/SDL_sysmutex.c",
//    "src/thread/vita/SDL_syssem.c",
//    "src/thread/vita/SDL_systhread.c",
//
//    "src/timer/dummy/SDL_systimer.c",
//    "src/timer/haiku/SDL_systimer.c",
//    "src/timer/n3ds/SDL_systimer.c",
//    "src/timer/os2/SDL_systimer.c",
//    "src/timer/ps2/SDL_systimer.c",
//    "src/timer/psp/SDL_systimer.c",
//    "src/timer/vita/SDL_systimer.c",
//
//    "src/video/android/SDL_androidclipboard.c",
//    "src/video/android/SDL_androidevents.c",
//    "src/video/android/SDL_androidgl.c",
//    "src/video/android/SDL_androidkeyboard.c",
//    "src/video/android/SDL_androidmessagebox.c",
//    "src/video/android/SDL_androidmouse.c",
//    "src/video/android/SDL_androidtouch.c",
//    "src/video/android/SDL_androidvideo.c",
//    "src/video/android/SDL_androidvulkan.c",
//    "src/video/android/SDL_androidwindow.c",
//    "src/video/directfb/SDL_DirectFB_WM.c",
//    "src/video/directfb/SDL_DirectFB_dyn.c",
//    "src/video/directfb/SDL_DirectFB_events.c",
//    "src/video/directfb/SDL_DirectFB_modes.c",
//    "src/video/directfb/SDL_DirectFB_mouse.c",
//    "src/video/directfb/SDL_DirectFB_opengl.c",
//    "src/video/directfb/SDL_DirectFB_render.c",
//    "src/video/directfb/SDL_DirectFB_shape.c",
//    "src/video/directfb/SDL_DirectFB_video.c",
//    "src/video/directfb/SDL_DirectFB_vulkan.c",
//    "src/video/directfb/SDL_DirectFB_window.c",
//    "src/video/kmsdrm/SDL_kmsdrmdyn.c",
//    "src/video/kmsdrm/SDL_kmsdrmevents.c",
//    "src/video/kmsdrm/SDL_kmsdrmmouse.c",
//    "src/video/kmsdrm/SDL_kmsdrmopengles.c",
//    "src/video/kmsdrm/SDL_kmsdrmvideo.c",
//    "src/video/kmsdrm/SDL_kmsdrmvulkan.c",
//    "src/video/n3ds/SDL_n3dsevents.c",
//    "src/video/n3ds/SDL_n3dsframebuffer.c",
//    "src/video/n3ds/SDL_n3dsswkb.c",
//    "src/video/n3ds/SDL_n3dstouch.c",
//    "src/video/n3ds/SDL_n3dsvideo.c",
//    "src/video/nacl/SDL_naclevents.c",
//    "src/video/nacl/SDL_naclglue.c",
//    "src/video/nacl/SDL_naclopengles.c",
//    "src/video/nacl/SDL_naclvideo.c",
//    "src/video/nacl/SDL_naclwindow.c",
//    "src/video/offscreen/SDL_offscreenevents.c",
//    "src/video/offscreen/SDL_offscreenframebuffer.c",
//    "src/video/offscreen/SDL_offscreenopengles.c",
//    "src/video/offscreen/SDL_offscreenvideo.c",
//    "src/video/offscreen/SDL_offscreenwindow.c",
//    "src/video/os2/SDL_os2dive.c",
//    "src/video/os2/SDL_os2messagebox.c",
//    "src/video/os2/SDL_os2mouse.c",
//    "src/video/os2/SDL_os2util.c",
//    "src/video/os2/SDL_os2video.c",
//    "src/video/os2/SDL_os2vman.c",
//    "src/video/pandora/SDL_pandora.c",
//    "src/video/pandora/SDL_pandora_events.c",
//    "src/video/ps2/SDL_ps2video.c",
//    "src/video/psp/SDL_pspevents.c",
//    "src/video/psp/SDL_pspgl.c",
//    "src/video/psp/SDL_pspmouse.c",
//    "src/video/psp/SDL_pspvideo.c",
//    "src/video/qnx/gl.c",
//    "src/video/qnx/keyboard.c",
//    "src/video/qnx/video.c",
//    "src/video/raspberry/SDL_rpievents.c",
//    "src/video/raspberry/SDL_rpimouse.c",
//    "src/video/raspberry/SDL_rpiopengles.c",
//    "src/video/raspberry/SDL_rpivideo.c",
//    "src/video/riscos/SDL_riscosevents.c",
//    "src/video/riscos/SDL_riscosframebuffer.c",
//    "src/video/riscos/SDL_riscosmessagebox.c",
//    "src/video/riscos/SDL_riscosmodes.c",
//    "src/video/riscos/SDL_riscosmouse.c",
//    "src/video/riscos/SDL_riscosvideo.c",
//    "src/video/riscos/SDL_riscoswindow.c",
//    "src/video/vita/SDL_vitaframebuffer.c",
//    "src/video/vita/SDL_vitagl_pvr.c",
//    "src/video/vita/SDL_vitagles.c",
//    "src/video/vita/SDL_vitagles_pvr.c",
//    "src/video/vita/SDL_vitakeyboard.c",
//    "src/video/vita/SDL_vitamessagebox.c",
//    "src/video/vita/SDL_vitamouse.c",
//    "src/video/vita/SDL_vitatouch.c",
//    "src/video/vita/SDL_vitavideo.c",
//    "src/video/vivante/SDL_vivanteopengles.c",
//    "src/video/vivante/SDL_vivanteplatform.c",
//    "src/video/vivante/SDL_vivantevideo.c",
//    "src/video/vivante/SDL_vivantevulkan.c",
//
//    "src/render/opengl/SDL_render_gl.c",
//    "src/render/opengl/SDL_shaders_gl.c",
//    "src/render/opengles/SDL_render_gles.c",
//    "src/render/opengles2/SDL_render_gles2.c",
//    "src/render/opengles2/SDL_shaders_gles2.c",
//    "src/render/ps2/SDL_render_ps2.c",
//    "src/render/psp/SDL_render_psp.c",
//    "src/render/vitagxm/SDL_render_vita_gxm.c",
//    "src/render/vitagxm/SDL_render_vita_gxm_memory.c",
//    "src/render/vitagxm/SDL_render_vita_gxm_tools.c",
//};
//
//const static_headers = [_][]const u8{
//    "begin_code.h",
//    "close_code.h",
//    "SDL_assert.h",
//    "SDL_atomic.h",
//    "SDL_audio.h",
//    "SDL_bits.h",
//    "SDL_blendmode.h",
//    "SDL_clipboard.h",
//    "SDL_config_android.h",
//    "SDL_config_emscripten.h",
//    "SDL_config_iphoneos.h",
//    "SDL_config_macosx.h",
//    "SDL_config_minimal.h",
//    "SDL_config_ngage.h",
//    "SDL_config_os2.h",
//    "SDL_config_pandora.h",
//    "SDL_config_windows.h",
//    "SDL_config_wingdk.h",
//    "SDL_config_winrt.h",
//    "SDL_config_xbox.h",
//    "SDL_copying.h",
//    "SDL_cpuinfo.h",
//    "SDL_egl.h",
//    "SDL_endian.h",
//    "SDL_error.h",
//    "SDL_events.h",
//    "SDL_filesystem.h",
//    "SDL_gamecontroller.h",
//    "SDL_gesture.h",
//    "SDL_guid.h",
//    "SDL.h",
//    "SDL_haptic.h",
//    "SDL_hidapi.h",
//    "SDL_hints.h",
//    "SDL_joystick.h",
//    "SDL_keyboard.h",
//    "SDL_keycode.h",
//    "SDL_loadso.h",
//    "SDL_locale.h",
//    "SDL_log.h",
//    "SDL_main.h",
//    "SDL_messagebox.h",
//    "SDL_metal.h",
//    "SDL_misc.h",
//    "SDL_mouse.h",
//    "SDL_mutex.h",
//    "SDL_name.h",
//    "SDL_opengles2_gl2ext.h",
//    "SDL_opengles2_gl2.h",
//    "SDL_opengles2_gl2platform.h",
//    "SDL_opengles2.h",
//    "SDL_opengles2_khrplatform.h",
//    "SDL_opengles.h",
//    "SDL_opengl_glext.h",
//    "SDL_opengl.h",
//    "SDL_pixels.h",
//    "SDL_platform.h",
//    "SDL_power.h",
//    "SDL_quit.h",
//    "SDL_rect.h",
//    "SDL_render.h",
//    "SDL_rwops.h",
//    "SDL_scancode.h",
//    "SDL_sensor.h",
//    "SDL_shape.h",
//    "SDL_stdinc.h",
//    "SDL_surface.h",
//    "SDL_system.h",
//    "SDL_syswm.h",
//    "SDL_test_assert.h",
//    "SDL_test_common.h",
//    "SDL_test_compare.h",
//    "SDL_test_crc32.h",
//    "SDL_test_font.h",
//    "SDL_test_fuzzer.h",
//    "SDL_test.h",
//    "SDL_test_harness.h",
//    "SDL_test_images.h",
//    "SDL_test_log.h",
//    "SDL_test_md5.h",
//    "SDL_test_memory.h",
//    "SDL_test_random.h",
//    "SDL_thread.h",
//    "SDL_timer.h",
//    "SDL_touch.h",
//    "SDL_types.h",
//    "SDL_version.h",
//    "SDL_video.h",
//    "SDL_vulkan.h",
//};
//

//const dynapi_option = SdlOption{
//    .name = "dynapi",
//    .desc = "enable the dynamic SDL api which allows SDL to be swapped out at runtime",
//    .default = false,
//    .sdl_configs = &.{ "SDL_DYNAMIC_API" },
//};
//
//const render_driver_sw = SdlOption{
//    .name = "render_driver_software",
//    .desc = "enable the software render driver",
//    .default = true,
//    .sdl_configs = &.{ },
//    .c_macros = &.{ "SDL_VIDEO_RENDER_SW" },
//    .sdl_files = &.{
//        "src/render/software/SDL_blendfillrect.c",
//        "src/render/software/SDL_blendline.c",
//        "src/render/software/SDL_blendpoint.c",
//        "src/render/software/SDL_drawline.c",
//        "src/render/software/SDL_drawpoint.c",
//        "src/render/software/SDL_render_sw.c",
//        "src/render/software/SDL_rotate.c",
//        "src/render/software/SDL_triangle.c",
//    },
//    .system_libs = &.{ },
//};
//
//const windows_options = [_]SdlOption{
//    dynapi_option,
//};
//
//const linux_options = [_]SdlOption{
//    .{
//        .name = "video_driver_x11",
//        .desc = "enable the x11 video driver",
//        .default = true,
//        .sdl_configs = &.{
//            "SDL_VIDEO_DRIVER_X11",
//            "SDL_VIDEO_DRIVER_X11_SUPPORTS_GENERIC_EVENTS",
//        },
//        .sdl_files = &.{ },
//        .system_libs = &.{ "x11", "xext" },
//    },
//    render_driver_sw,
//    .{
//        .name = "render_driver_ogl",
//        .desc = "enable the opengl render driver",
//        .default = true,
//        .sdl_configs = &.{ "SDL_VIDEO_RENDER_OGL" },
//        .sdl_files = &.{
//            "src/render/opengl/SDL_render_gl.c",
//            "src/render/opengl/SDL_shaders_gl.c",
//        },
//        .system_libs = &.{ },
//    },
//    .{
//        .name = "render_driver_ogl_es",
//        .desc = "enable the opengl es render driver",
//        .default = true,
//        .sdl_configs = &.{ "SDL_VIDEO_RENDER_OGL_ES" },
//        .sdl_files = &.{
//            "src/render/opengles/SDL_render_gles.c",
//        },
//        .system_libs = &.{ },
//    },
//    .{
//        .name = "render_driver_ogl_es2",
//        .desc = "enable the opengl es2 render driver",
//        .default = true,
//        .sdl_configs = &.{ "SDL_VIDEO_RENDER_OGL_ES2" },
//        .sdl_files = &.{
//            "src/render/opengles2/SDL_render_gles2.c",
//            "src/render/opengles2/SDL_shaders_gles2.c",
//        },
//        .system_libs = &.{ },
//    },
//    .{
//        .name = "audio_driver_pulse",
//        .desc = "enable the pulse audio driver",
//        .default = true,
//        .sdl_configs = &.{ "SDL_AUDIO_DRIVER_PULSEAUDIO" },
//        .sdl_files = &.{ "src/audio/pulseaudio/SDL_pulseaudio.c" },
//        .system_libs = &.{ "pulse" },
//    },
//    .{
//        .name = "audio_driver_alsa",
//        .desc = "enable the alsa audio driver",
//        .default = false,
//        .sdl_configs = &.{ "SDL_AUDIO_DRIVER_ALSA" },
//        .sdl_files = &.{ "src/audio/alsa/SDL_alsa_audio.c" },
//        .system_libs = &.{ "alsa" },
//    },
//};

const config_zig_cc = .{
    .HAVE_CONST = 1,
    .HAVE_INLINE = 1,
    .HAVE_VOLATILE = 1,
    .HAVE_GCC_ATOMICS = 1,
    .HAVE_GCC_SYNC_LOCK_TEST_AND_SET = 1,
    .HAVE_LIBC = 1,
};

const Filesystem = enum {
    android,
    haiku,
    cocoa,
    dummy,
    riscos,
    unix,
    windows,
    emscripten,
    os2,
    vita,
    psp,
    ps2,
    n3ds,

    pub fn getDefault(self: Filesystem, target: std.Target) bool {
        switch (self) {
            .android => return target.isAndroid(),
            .haiku => return target.os.tag == .haiku,
            .cocoa => return false,
            .dummy => return false,
            .riscos => return false,
            .unix => return target.os.tag == .linux,
            .windows => return target.os.tag == .windows,
            .emscripten => return target.os.tag == .emscripten,
            .os2 => return false,
            .vita => return false,
            .psp => return false,
            .ps2 => return false,
            .n3ds => return false,
        }
    }
};

const Thread = enum {
    generic_cond_suffix,
    pthread,
    pthread_recursive_mutex,
    pthread_recursive_mutex_np,
    os2,
    vita,
    psp,
    ps2,
    n3ds,

    pub fn getDefault(self: Thread, target: std.Target) bool {
        switch (self) {
            .generic_cond_suffix => return false,
            .pthread => return haveHeader(target, .pthread, .cpp),
            .pthread_recursive_mutex => return haveHeader(target, .pthread, .cpp),
            .pthread_recursive_mutex_np => return haveHeader(target, .pthread, .cpp),
            .os2 => return false,
            .vita => return false,
            .psp => return false,
            .ps2 => return false,
            .n3ds => return false,
        }
    }
};

const Timer = enum {
    haiku,
    dummy,
    unix,
    windows,
    os2,
    vita,
    psp,
    ps2,
    n3ds,

    pub fn getDefault(self: Timer, target: std.Target) bool {
        switch (self) {
            .haiku => return target.os.tag == .haiku,
            .dummy => return false,
            .unix => return
                target.isDarwin() or
                (target.os.tag == .linux),
            .windows => return target.os.tag == .windows,
            .os2 => return false,
            .vita => return false,
            .psp => return false,
            .ps2 => return false,
            .n3ds => return false,
        }
    }
};

const Power = enum {
    android,
    linux,
    windows,
    winrt,
    macosx,
    uikit,
    haiku,
    emscripten,
    hardwired,
    vita,
    psp,
    n3ds,

    pub fn getDefault(self: Power, target: std.Target) bool {
        switch (self) {
            .android => return target.isAndroid(),
            .linux => return target.os.tag == .linux,
            .windows => return target.os.tag == .windows,
            .winrt => return false,
            .macosx => return target.isDarwin(),
            .uikit => return target.isDarwin(),
            .haiku => return target.os.tag == .haiku,
            .emscripten => return target.os.tag == .emscripten,
            .hardwired => return false,
            .vita => return false,
            .psp => return false,
            .n3ds => return false,
        }
    }
};

const VideoDriver = enum {
    android,
    emscripten,
    haiku,
    cocoa,
    uikit,
    directfb,
    directfb_dynamic,
    dummy,
    offscreen,
    windows,
    winrt,
    wayland,
    rpi,
    vivante,
    vivante_vdk,
    os2,
    qnx,
    riscos,
    psp,
    ps2,
    kmsdrm,
    kmsdrm_dynamic,
    kmsdrm_dynamic_gbm,
    wayland_qt_touch,
    wayland_dynamic,
    wayland_dynamic_egl,
    wayland_dynamic_cursor,
    wayland_dynamic_xkbcommon,
    wayland_dynamic_libdecor,
    x11,
    x11_dynamic,
    x11_dynamic_xext,
    x11_dynamic_xcursor,
    x11_dynamic_xinput2,
    x11_dynamic_xfixes,
    x11_dynamic_xrandr,
    x11_dynamic_xss,
    x11_xcursor,
    x11_xdbe,
    x11_xinput2,
    x11_xinput2_supports_multitouch,
    x11_xfixes,
    x11_xrandr,
    x11_xscrnsaver,
    x11_xshape,
    x11_supports_generic_events,
    x11_has_xkbkeycodetokeysym,
    vita,
    n3ds,

    pub fn getDefault(self: VideoDriver, target: std.Target) bool {
        switch (self) {
            .android => return target.isAndroid(),
            .emscripten => return target.os.tag == .emscripten,
            .haiku => return target.os.tag == .haiku,
            .cocoa => return target.isDarwin(),
            .uikit => return target.isDarwin(),
            .directfb => return haveHeader(target, .{ .custom = "directfb.h" }, .cpp),
            .directfb_dynamic => return false,
            .dummy => return false,
            .offscreen => return false,
            .windows => return target.os.tag == .windows,
            .winrt => return false,
            .wayland => return target.os.tag == .linux,
            .rpi => return false,
            .vivante => return false,
            .vivante_vdk => return false,
            .os2 => return false,
            .qnx => return false,
            .riscos => return false,
            .psp => return false,
            .ps2 => return false,
            .kmsdrm => return false,
            .kmsdrm_dynamic => return false,
            .kmsdrm_dynamic_gbm => return false,
            .wayland_qt_touch => return target.os.tag == .linux,
            .wayland_dynamic => return target.os.tag == .linux,
            .wayland_dynamic_egl => return target.os.tag == .linux,
            .wayland_dynamic_cursor => return target.os.tag == .linux,
            .wayland_dynamic_xkbcommon => return target.os.tag == .linux,
            .wayland_dynamic_libdecor => return target.os.tag == .linux,
            .x11 => return target.os.tag == .linux,
            .x11_dynamic => return target.os.tag == .linux,
            .x11_dynamic_xext => return target.os.tag == .linux,
            .x11_dynamic_xcursor => return target.os.tag == .linux,
            .x11_dynamic_xinput2 => return target.os.tag == .linux,
            .x11_dynamic_xfixes => return target.os.tag == .linux,
            .x11_dynamic_xrandr => return target.os.tag == .linux,
            .x11_dynamic_xss => return target.os.tag == .linux,
            .x11_xcursor => return target.os.tag == .linux,
            .x11_xdbe => return target.os.tag == .linux,
            .x11_xinput2 => return target.os.tag == .linux,
            .x11_xinput2_supports_multitouch => return target.os.tag == .linux,
            .x11_xfixes => return target.os.tag == .linux,
            .x11_xrandr => return target.os.tag == .linux,
            .x11_xscrnsaver => return target.os.tag == .linux,
            .x11_xshape => return target.os.tag == .linux,
            .x11_supports_generic_events => return target.os.tag == .linux,
            .x11_has_xkbkeycodetokeysym => return target.os.tag == .linux,
            .vita => return false,
            .n3ds => return false,
        }
    }
};

const VideoRender = enum {
    d3d,
    d3d11,
    d3d12,
    ogl,
    ogl_es,
    ogl_es2,
    directfb,
    metal,
    vita_gxm,
    ps2,
    psp,

    pub fn getDefault(self: VideoRender, target: std.Target) bool {
        switch (self) {
            .d3d => return target.os.tag == .windows,
            .d3d11 => return target.os.tag == .windows,
            .d3d12 => return target.os.tag == .windows,
            .ogl, .ogl_es, .ogl_es2  => return (target.os.tag == .windows) or
                target.isDarwin() or
                (target.os.tag == .linux),
            .directfb => return false,
            .metal => return target.isDarwin(),
            .vita_gxm => return false,
            .ps2 => return false,
            .psp => return false,
        }
    }
};

const VideoOpengl = enum {
    opengl,
    opengl_es,
    opengl_es2,
    opengl_bgl,
    opengl_cgl,
    opengl_glx,
    opengl_wgl,
    opengl_egl,
    opengl_osmesa,
    opengl_osmesa_dynamic,

    pub fn getDefault(self: VideoOpengl, target: std.Target) bool {
        _ = target;
        switch (self) {
            .opengl => return false,
            .opengl_es => return false,
            .opengl_es2 => return false,
            .opengl_bgl => return false,
            .opengl_cgl => return false,
            .opengl_glx => return false,
            .opengl_wgl => return false,
            .opengl_egl => return false,
            .opengl_osmesa => return false,
            .opengl_osmesa_dynamic => return false,
        }
    }
};

const AudioDriver = enum {
    alsa,
    alsa_dynamic,
    android,
    opensles,
    aaudio,
    arts,
    arts_dynamic,
    coreaudio,
    disk,
    dsound,
    dummy,
    emscripten,
    esd,
    esd_dynamic,
    fusionsound,
    fusionsound_dynamic,
    haiku,
    jack,
    jack_dynamic,
    nas,
    nas_dynamic,
    netbsd,
    oss,
    paudio,
    pipewire,
    pipewire_dynamic,
    pulseaudio,
    pulseaudio_dynamic,
    qsa,
    sndio,
    sndio_dynamic,
    sunaudio,
    wasapi,
    winmm,
    os2,
    vita,
    psp,
    ps2,
    n3ds,

    pub fn getDefault(self: AudioDriver, target: std.Target) bool {
        switch (self) {
            .alsa => return false,
            .alsa_dynamic => return false,
            .android => return false,
            .opensles => return false,
            .aaudio => return false,
            .arts => return false,
            .arts_dynamic => return false,
            .coreaudio => return false,
            .disk => return false,
            .dsound => return false,
            .dummy => return false,
            .emscripten => return false,
            .esd => return false,
            .esd_dynamic => return false,
            .fusionsound => return false,
            .fusionsound_dynamic => return false,
            .haiku => return false,
            .jack => return false,
            .jack_dynamic => return false,
            .nas => return false,
            .nas_dynamic => return false,
            .netbsd => return false,
            .oss => return false,
            .paudio => return false,
            .pipewire => return false,
            .pipewire_dynamic => return false,
            .pulseaudio => return false,
            .pulseaudio_dynamic => return false,
            .qsa => return false,
            .sndio => return false,
            .sndio_dynamic => return false,
            .sunaudio => return false,
            .wasapi => return target.os.tag == .windows,
            .winmm => return false,
            .os2 => return false,
            .vita => return false,
            .psp => return false,
            .ps2 => return false,
            .n3ds => return false,
        }
    }
};

const Joystick = enum {
    android,
    haiku,
    wgi,
    dinput,
    xinput,
    dummy,
    iokit,
    mfi,
    linux,
    os2,
    usbhid,
    hidapi,
    rawinput,
    emscripten,
    virtual,
    vita,
    psp,
    ps2,
    n3ds,

    pub fn getDefault(self: Joystick, target: std.Target) bool {
        switch (self) {
            .android => return target.isAndroid(),
            .haiku => return target.os.tag == .haiku,
            .wgi => return target.os.tag == .windows,
            .dinput => return target.os.tag == .windows,
            .xinput => return target.os.tag == .windows,
            .dummy => return false,
            .iokit => return target.isDarwin(),
            .mfi => return target.isDarwin(),
            .linux => return target.os.tag == .linux,
            .os2 => return false,
            .usbhid => return haveHeader(target, .usbhid, .cpp),
            .hidapi => return false,
            .rawinput => return false,
            .emscripten => return target.os.tag == .emscripten,
            .virtual => return false,
            .vita => return false,
            .psp => return false,
            .ps2 => return false,
            .n3ds => return false,
        }
    }
};

const Sensor = enum {
    android,
    coremotion,
    windows,
    dummy,
    vita,
    n3ds,

    pub fn getDefault(self: Sensor, target: std.Target) bool {
        switch (self) {
            .android => return target.isAndroid(),
            .coremotion => return false,
            .windows => return target.os.tag == .windows,
            .dummy => return false,
            .vita => return false,
            .n3ds => return false,
        }
    }
};

const Haptic = enum {
    dummy,
    linux,
    iokit,
    dinput,
    xinput,
    android,

    pub fn getDefault(self: Haptic, target: std.Target) bool {
        switch (self) {
            .dummy => return false,
            .linux => return target.os.tag == .linux,
            .iokit => return target.isDarwin(),
            .dinput => return target.os.tag == .windows,
            .xinput => return target.os.tag == .windows,
            .android => return target.isAndroid(),
        }
    }
};

const Loadso = enum {
    dlopen,
    dummy,
    ldg,
    windows,
    os2,

    pub fn getDefault(self: Loadso, target: std.Target) bool {
        switch (self) {
            .dlopen => return (target.os.tag == .linux),
            .dummy => return false,
            .ldg => return false,
            .windows => return target.os.tag == .windows,
            .os2 => return false,
        }
    }
};

const HaveHeaderContext = enum {
    c,
    cpp,
};

const Header = union(enum) {
    // c89
    ctype: void,
    limits: void,
    math: void,
    float: void,
    signal: void,
    stdarg: void,
    stddef: void,
    stdio: void,
    stdlib: void,
    string: void,

    // c99
    stdint: void,
    inttypes: void,
    wchar: void,

    // posix
    iconv: void,
    pthread: void,
    strings: void,
    sys_ioctl: void,
    sys_kbio: void,
    sys_time: void,
    sys_types: void,

    // linux
    linux_input: void,
    linux_kd: void,
    linux_keyboard: void,

    // bsd
    dev_wscons_wsconsio: void,
    dev_wscons_wsksymdef: void,
    dev_wscons_wsksymvar: void,

    // ?
    alloca: void,
    malloc: void,
    machine_joystick: void,
    usbhid: void,

    custom: []const u8,
};

// It should be possible to implement this in Zig's build system
fn haveHeader(target: std.Target, header: Header, context: HaveHeaderContext) bool {
    _ = context;
    switch (header) {
        // c89
        .ctype,
        .limits,
        .math,
        .float,
        .signal,
        .stdarg,
        .stddef,
        .stdio,
        .stdlib,
        .string,
        => return true,

        // c99
        .stdint,
        .inttypes,
        .wchar,
        => return true,

        // posix
        .iconv,
        .pthread,
        .strings,
        .sys_ioctl,
        .sys_kbio,
        .sys_time,
        .sys_types,
        => return true,

        // linux
        .linux_input,
        .linux_kd,
        .linux_keyboard,
        => return switch (target.os.tag) {
            .linux => true,
            else => false,
        },

        // bsd
        .dev_wscons_wsconsio,
        .dev_wscons_wsksymdef,
        .dev_wscons_wsksymvar,
        => return switch (target.os.tag) {
            .openbsd, .netbsd => true,
            else => false,
        },

        // ?
        .alloca => return false,
        .malloc => return switch (target.os.tag) {
            .linux => true,
            else => false,
        },
        .machine_joystick => return false,
        .usbhid => return (target.os.tag == .linux),

        .custom => |path| {
            std.log.warn("TODO: check if header '{s}' actually exists for this target/context", .{path});
            return false;
        },
    }
}
