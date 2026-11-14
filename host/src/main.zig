const std = @import("std");
const RocdogAllocator = @import("RocdogAllocator.zig");

var g_alloc_instance: std.heap.DebugAllocator(.{}) = .init;
extern fn roc_main() callconv(.c) void;

fn main() callconv(.c) void {
    defer if (g_alloc_instance.deinit() == .leak) {
        std.log.err("rocdog#std.heap.DebugAllocator detected a leak", .{});
        std.process.exit(2);
    };
    return roc_main();
}

fn rocAlloc(size: usize, alignment: usize) callconv(.c) ?[*]u8 {
    _ = alignment;
    std.debug.assert(size < std.math.maxInt(RocdogAllocator.USize)); // assert truncate value cast can fit
    const buffer = RocdogAllocator.proxyAlloc(g_alloc_instance.allocator(), @truncate(size)) catch |err| {
        std.log.err("platform#rocAlloc: {s}", .{ @errorName(err) });
        return null;
    };
    return @ptrCast(buffer);
}

fn rocFree(_ptr: ?[*]u8, alignment: usize) callconv(.c) void {
    _ = alignment;
    return if (_ptr) |ptr| RocdogAllocator.proxyFree(g_alloc_instance.allocator(), ptr);
}

fn rocReAlloc(_ptr: ?[*]u8, new_size: usize, alignment: usize) callconv(.c) ?[*]u8 {
    _ = alignment;
    std.debug.assert(new_size < std.math.maxInt(RocdogAllocator.USize)); // assert truncate value cast can fit
    if (_ptr) |ptr| {
        const new_buffer = RocdogAllocator.proxyReAlloc(g_alloc_instance.allocator(), ptr, @truncate(new_size)) catch |err| {
            std.log.err("platform#rocReAlloc: {s}", .{ @errorName(err) });
            return null;
        };
        return @ptrCast(new_buffer);
    } else {
        return null;
    }

    unreachable;
}

fn rocDbg(_bytes: ?[*]u8, len: usize) callconv(.c) void {
    const fmt = "platform#debug: ";
    return
        if (_bytes) |bytes| std.log.debug(fmt ++ "{s}", .{ bytes[0..len] })
        else std.log.debug(fmt ++ "<no bytes sent with size of {d}>", .{ len })
    ;
}

fn rocExpectFailed(_bytes: ?[*]u8, len: usize) callconv(.c) void {
    const fmt = "platform#expect: ";
    return
        if (_bytes) |bytes| std.log.debug(fmt ++ "{s}", .{ bytes[0..len] })
        else std.log.debug(fmt ++ "<no bytes sent with size of {d}>", .{ len })
    ;
}

fn rocCrashed(_bytes: ?[*]u8, len: usize) callconv(.c) noreturn {
    const fmt = "platform#crashed: ";
    if (_bytes) |bytes| {
        std.log.debug(fmt ++ "{s}", .{ bytes[0..len] });
    } else {
        std.log.debug(fmt ++ "<nil bytes with size of {d}>", .{ len });
    }
    return std.process.exit(1);
}

comptime {
    for (.{
        .{ &main,            "main"              },
        .{ &rocAlloc,        "roc_alloc"         },
        .{ &rocFree,         "roc_dealloc"       },
        .{ &rocReAlloc,      "roc_realloc"       },
        .{ &rocDbg,          "roc_dbg"           },
        .{ &rocExpectFailed, "roc_expect_failed" },
        .{ &rocCrashed,      "roc_crashed"       },
    }) |value| {
        @export(value[0], .{ .name = value[1], .linkage = .strong, .visibility = .hidden });
    }
}

test {
    _ = .{
        RocdogAllocator,
    };
}
