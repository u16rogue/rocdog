/// Tests for `RocdogAllocator.zig`

const std = @import("std");
const RocdogAllocator = @import("RocdogAllocator.zig");

const USize = RocdogAllocator.USize;
const proxyAlloc = RocdogAllocator.proxyAlloc;
const proxyFree = RocdogAllocator.proxyFree;
const proxyReAlloc = RocdogAllocator.proxyReAlloc;
const normalize = RocdogAllocator.normalize;

/// Position dependent bytes to fill allocations with and compare them against
const test_bytes = blk: {
    var bytes: [4096]u8 = undefined;
    @setEvalBranchQuota(bytes.len * 2);
    for (&bytes, 0..) |*byte, i| byte.* = @truncate(i + 1);
    break :blk bytes;
};

/// Sizes around the 8 byte header and common size class boundaries
const test_sizes = [_]USize{ 0, 1, 7, 8, 9, 15, 16, 17, 31, 64, 255, 256, 4096 };

test "RocdogAllocator: alloc, normalize, free" {
    const testing = std.testing;

    for (test_sizes) |size| {
        const buffer = try proxyAlloc(testing.allocator, size);
        defer proxyFree(testing.allocator, buffer.ptr);
        @memcpy(buffer, test_bytes[0..size]);

        try testing.expectEqual(size, buffer.len);
        try testing.expectEqual(buffer, normalize(buffer.ptr));
        try testing.expectEqualSlices(u8, test_bytes[0..size], buffer);
    }
}

test "RocdogAllocator: the backing allocator is charged the request plus the header" {
    const testing = std.testing;
    const header_size = 8;

    for (test_sizes) |size| {
        // never fails, it's only here to count the bytes the proxy takes from and gives back to its backing allocator
        var counting = testing.FailingAllocator.init(testing.allocator, .{});

        var ptr = (try proxyAlloc(counting.allocator(), size)).ptr;
        try testing.expectEqual(size + header_size, counting.allocated_bytes - counting.freed_bytes);

        for ([_]USize{ size * 2, size / 2, 0, size }) |new_size| {
            ptr = (proxyReAlloc(counting.allocator(), ptr, new_size) catch |err| {
                proxyFree(counting.allocator(), ptr);
                return err;
            }).ptr;
            try testing.expectEqual(new_size + header_size, counting.allocated_bytes - counting.freed_bytes);
        }

        proxyFree(counting.allocator(), ptr);
        try testing.expectEqual(counting.allocated_bytes, counting.freed_bytes);
    }
}

test "RocdogAllocator: live allocations don't clobber each other" {
    const testing = std.testing;

    var buffers: [test_sizes.len]?[]u8 = @splat(null);
    defer for (buffers) |maybe_buffer| if (maybe_buffer) |buffer| proxyFree(testing.allocator, buffer.ptr);

    for (&buffers, test_sizes) |*buffer, size| {
        buffer.* = try proxyAlloc(testing.allocator, size);
        @memcpy(buffer.*.?, test_bytes[0..size]);
    }

    // free every other one, the survivors must be untouched
    for (&buffers, 0..) |*buffer, i| if (i % 2 == 1) {
        proxyFree(testing.allocator, buffer.*.?.ptr);
        buffer.* = null;
    };

    for (buffers, test_sizes) |maybe_buffer, size| if (maybe_buffer) |buffer| {
        try testing.expectEqual(buffer, normalize(buffer.ptr));
        try testing.expectEqualSlices(u8, test_bytes[0..size], buffer);
    };
}

test "RocdogAllocator: chained reallocs keep contents" {
    const testing = std.testing;

    // only the pointer is kept between steps, like roc does
    var ptr = (try proxyAlloc(testing.allocator, 0)).ptr;
    defer proxyFree(testing.allocator, ptr);

    for ([_]USize{ 32, 0, 8, 9, 8, 16, 4096, 16, 64, 64, 1, 2, 4096 }) |new_size| {
        const old_size = normalize(ptr).len;
        const buffer = try proxyReAlloc(testing.allocator, ptr, new_size);
        ptr = buffer.ptr;

        try testing.expectEqual(new_size, buffer.len);
        try testing.expectEqual(buffer, normalize(ptr));
        const kept = @min(old_size, new_size);
        try testing.expectEqualSlices(u8, test_bytes[0..kept], buffer[0..kept]);

        @memcpy(buffer, test_bytes[0..new_size]); // the whole new block must be writable
    }
}

test "RocdogAllocator: failed realloc leaves the original intact" {
    const testing = std.testing;

    // the first allocation succeeds, then both the in place resize and the fallback allocation fail
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1, .resize_fail_index = 0 });
    const buffer = try proxyAlloc(failing.allocator(), 16);
    defer proxyFree(failing.allocator(), buffer.ptr);
    @memcpy(buffer, test_bytes[0..16]);

    try testing.expectError(error.OutOfMemory, proxyReAlloc(failing.allocator(), buffer.ptr, 4096));
    try testing.expectEqual(buffer, normalize(buffer.ptr));
    try testing.expectEqualSlices(u8, test_bytes[0..16], buffer);
}

test "RocdogAllocator: allocation failures don't leak" {
    // Fails each allocation in turn and never resizes in place, so every realloc here has to move the block
    const run = struct {
        fn run(allocator: std.mem.Allocator) !void {
            const old_buffer = try proxyAlloc(allocator, 8);
            @memcpy(old_buffer, test_bytes[0..8]);

            const buffer = proxyReAlloc(allocator, old_buffer.ptr, 4096) catch |err| {
                proxyFree(allocator, old_buffer.ptr);
                return err;
            };
            defer proxyFree(allocator, buffer.ptr);

            try std.testing.expect(buffer.ptr != old_buffer.ptr);
            try std.testing.expectEqual(buffer, normalize(buffer.ptr));
            try std.testing.expectEqualSlices(u8, test_bytes[0..8], buffer[0..8]);
        }
    }.run;

    try std.testing.checkAllAllocationFailures(std.testing.allocator, run, .{});
}

test "meta.castToUsize: values that fit come out unchanged" {
    const testing = std.testing;

    // narrower than, as wide as and wider than `USize`
    inline for (.{ u8, u16, u31, USize, u33, usize, u64, u128 }) |Value| {
        // the largest value both `Value` and `USize` can hold, anything above it is an assertion failure
        const max_fit: Value = @min(std.math.maxInt(Value), std.math.maxInt(USize));

        for ([_]Value{ 0, 1, max_fit / 2, max_fit - 1, max_fit }) |value| {
            const casted = RocdogAllocator.meta.castToUsize(Value, value);
            try testing.expectEqual(USize, @TypeOf(casted));
            try testing.expectEqual(@as(u128, value), @as(u128, casted));
        }
    }
}
