//
// NOTE: currently not buildable against glibc due to
// https://github.com/ziglang/zig/issues/5990 so build
// with -Dtarget=native-linux-musl
//

const std = @import("std");

const OPT_NET_SRCS = [_][]u8{
    "net_single.c",
    "net_multi.c",
    "net_mp_selct.c",
    "net_mp_poll.c",
    "net_mp_fake.c",
    "net_tcp.c",
    "net_bsd_tcp.c",
    "net_bsd_lcl.c",
    "net_sysv_tcp.c",
    "net_sysv_lcl.c",
};

/// Convenience function for spawning a child process, waiting for it to
///  finish, and returning the output.  Caller owns returned strings.
pub fn shell(allocator: *std.mem.Allocator, comptime command_fmt: []const u8, args: anytype) ![]const u8 {

    // Format the command
    const command = try std.fmt.allocPrint(allocator, command_fmt, args);

    // Now we can initialize and start the process running
    const argv = [_][]const u8{
        "/bin/sh",
        "-c",
        command,
    };

    const execArgs = .{
        .allocator = allocator,
        .argv = &argv,
        .max_output_bytes = 500 * 1024,
    };

    const res = std.ChildProcess.exec(execArgs) catch |e| return e;
    errdefer allocator.free(res.stdout);
    defer allocator.free(res.stderr);

    errdefer std.debug.print("{s}\n", .{res.stderr});
    switch (res.term) {
        .Exited => |e| if (e != 0) {
            return error.command_failed;
        },
        .Signal, .Stopped, .Unknown => return error.command_failed,
    }

    return res.stdout;
}

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const gen_y_tab = b.addSystemCommand(&.{ "bison", "-y", "-d" });
    gen_y_tab.addArg("parser.y");

    const gen_parser_c = b.addSystemCommand(&.{ "mv", "y.tab.c", "parser.c" });
    gen_parser_c.step.dependOn(&gen_y_tab.step);

    // ripe to be replaced with an in-zig implementation
    const gen_version_src_h = b.addSystemCommand(&.{ "touch", "version_src.h" });

    const moo = b.addExecutable("moo", null);
    moo.setTarget(target);
    moo.setBuildMode(mode);
    moo.install();
    moo.linkLibC();
    moo.linkSystemLibrary("m");
    moo.linkSystemLibrary("crypt");
    moo.step.dependOn(&gen_parser_c.step);
    moo.step.dependOn(&gen_version_src_h.step);
    moo.addCSourceFiles(&.{
        "ast.c",
        "code_gen.c",
        "db_file.c",
        "db_io.c",
        "db_objects.c",
        "db_properties.c",
        "db_verbs.c",
        "decompile.c",
        "disassemble.c",
        "eval_env.c",
        "eval_vm.c",
        "exceptions.c",
        "execute.c",
        "extensions.c",
        "functions.c",
        "keywords.c",
        "list.c",
        "log.c",
        "malloc.c",
        "match.c",
        "md5.c",
        "name_lookup.c",
        "network.c",
        "net_mplex.c",
        "net_proto.c",
        "numbers.c",
        "objects.c",
        "parse_cmd.c",
        "parser.c",
        "pattern.c",
        "program.c",
        "property.c",
        "quota.c",
        "ref_count.c",
        "regexpr.c",
        "server.c",
        "storage.c",
        "streams.c",
        "str_intern.c",
        "sym_table.c",
        "tasks.c",
        "timers.c",
        "unparse.c",
        "utils.c",
        "verbs.c",
        "version.c",
    }, &.{
        "-Wno-switch",
        "-DWIDER_INTEGERS_NOT_AVAILABLE",
    });

    const run_cmd = moo.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
