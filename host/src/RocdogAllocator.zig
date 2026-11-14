/// This is a proxy/meta allocator specifically for rocdog to implement extra memory processing

const Self = @This();
const std = @import("std");

/// Fixed type to represent `size` for `RocdogAllocator`
pub const USize = u32;

pub const meta = struct {
    /// Truncates a `value` of type `Value` into `USize`. Upcast and downcasts are okay as
    /// long as `value`'s numeric representation fits into `USize` and therefore this function
    /// triggers an assertion for that.
    pub fn castToUsize(comptime Value: type, value: Value) USize {
        std.debug.assert(value < std.math.maxInt(USize)); // assert truncated value stays the same
        return @truncate(value);
    }
};

/// Rocdog attaches this signature to memory allocations modified by the proxy as a signifier (NOT GUARANTEE) that
/// it retains integrity. (TODO: this is terribly worded. fix this.)
const signature_bytes = [_]u8 { 0x42, 0x41, 0x55, 0x00 };

const Metadata = extern struct {
    signature: [signature_bytes.len]u8,
    requested_size: USize,

    const block_size = @sizeOf(@This());
    comptime { if (block_size != 8) @compileError("RocdogAllocator.Metadata is expected to be and must be 8 bytes."); }
};

/// This is a proxy allocator that applies rocdog related modifications into the memory allocation
/// request. The returned memory is the abstracted view of the requested memory, it is expected to be
/// casted into a `[*]u8` dropping its length and is therefore considered okay. Any callee modification should
/// not be visible from the caller and the implementation should guarantee that what the caller requests
/// is what they get.
///
/// ```zig
/// const x: [*]u8 = @ptrCast(try proxyAlloc(allocator, 256)); // safe. RocdogAllocator will track it itself.
/// ```
///
/// This proxy will:
///     * Allocate more than the `size` parameter to embed extra metadata that RocdogAllocator will
///     take advantage of. This metadata will not be included in the returned slice.
///
pub fn proxyAlloc(allocator: std.mem.Allocator, size: USize) std.mem.Allocator.Error![]u8 {
    const actual_size = Metadata.block_size + size;
    const block = try allocator.alloc(u8, actual_size);

    std.mem.bytesAsValue(Metadata, block[0..Metadata.block_size]).* = Metadata {
        .signature = signature_bytes,
        .requested_size = size,
    };

    const caller_requested_block = block[Metadata.block_size..];

    // final check if metadata was properly set
    std.debug.assert(std.mem.eql(
        u8,
        block[0..Metadata.block_size],
        std.mem.asBytes(&Metadata { .signature = signature_bytes, .requested_size = size })
    ));
    std.debug.assert(caller_requested_block.len == size); // caller must get the expected size of memory they requested for

    return caller_requested_block;
}

/// Free an allocated memory by `RocdogAllocator`
/// UNSAFE: passing a `ptr` that wasn't returned by `proxyAlloc` is undefined behavior.
pub fn proxyFree(allocator: std.mem.Allocator, ptr: [*]u8) void {
    const real_base = ptr - Metadata.block_size;
    const pmetadata = std.mem.bytesAsValue(Metadata, real_base[0..Metadata.block_size]);
    const real_size = pmetadata.requested_size + Metadata.block_size;
    std.debug.assert(std.mem.eql(u8, &pmetadata.signature, &signature_bytes));
    allocator.free(real_base[0..real_size]);
}

/// Reallocate an allocated memory `ptr` by `RocdogAllocator` in `new_size` bytes.
/// UNSAFE: passing a `ptr` that wasn't returned by `proxyAlloc` is undefined behavior.
pub fn proxyReAlloc(allocator: std.mem.Allocator, ptr: [*]u8, new_size: USize) std.mem.Allocator.Error![]u8 {
    const pre_real_base = ptr - Metadata.block_size;
    const pre_pmetadata = std.mem.bytesAsValue(Metadata, pre_real_base[0..Metadata.block_size]);
    const pre_real_size = pre_pmetadata.requested_size + Metadata.block_size;
    std.debug.assert(std.mem.eql(u8, &pre_pmetadata.signature, &signature_bytes));

    const new_real_size = Metadata.block_size + new_size;
    const new_block = try allocator.realloc(pre_real_base[0..pre_real_size], new_real_size);

    // Doesn't matter if we got a new address or not our metadata block is at the beginning so it either
    // overwrites the existing block or it just writes the new block into the new address.
    std.mem.bytesAsValue(Metadata, new_block[0..Metadata.block_size]).* = Metadata {
        .signature = signature_bytes,
        .requested_size = new_size,
    };

    const caller_requested_new_block = new_block[Metadata.block_size..];

    // final check if metadata was properly set
    std.debug.assert(std.mem.eql(
        u8,
        new_block[0..Metadata.block_size],
        std.mem.asBytes(&Metadata { .signature = signature_bytes, .requested_size = new_size })
    ));
    std.debug.assert(caller_requested_new_block.len == new_size); // caller must get the expected size of memory they requested for

    return caller_requested_new_block;
}

/// Given a `ptr` normalize it back to a slice containig a pair of `ptr` and `len` by resolving it
/// using RocdogAllocator's metadata. This should only be used with memory allocated through RocdogAllocator.
/// UNSAFE: passing a `ptr` that wasn't returned by `proxyAlloc` is undefined behavior.
pub fn normalize(ptr: [*]u8) []u8 {
    const real_base = ptr - Metadata.block_size;
    const pmetadata = std.mem.bytesAsValue(Metadata, real_base[0..Metadata.block_size]);
    const real_size = pmetadata.requested_size + Metadata.block_size;

    std.debug.assert(std.mem.eql(u8, &pmetadata.signature, &signature_bytes));

    return real_base[Metadata.block_size..real_size];
}

test "RocdogAllocator" {
    // TODO: test proxyReAlloc
    const testing = std.testing;
    const allocator = testing.allocator;

    inline for ([_]u8{ 64, 32, 16, 8, 1, 0 }) |request_size| {
        const buffer = try proxyAlloc(allocator, request_size);
        try testing.expectEqual(buffer.len, request_size);

        if (request_size > 0) for (0..request_size) |i| {
            buffer[i] = @truncate(i + 1);
        };

        const to_lose_len: [*]u8 = @ptrCast(buffer);
        try testing.expectEqual(to_lose_len, buffer.ptr);

        const back_to_slice = normalize(to_lose_len);
        try testing.expectEqual(back_to_slice.ptr, to_lose_len);
        try testing.expectEqual(back_to_slice.len, request_size);
        try testing.expectEqual(back_to_slice.ptr, buffer.ptr);
        try testing.expectEqual(back_to_slice.len, buffer.len);

        if (request_size > 0) for (0..request_size) |i| {
            const n: u8 = @truncate(i + 1);
            try testing.expectEqual(to_lose_len[i],   n);
            try testing.expectEqual(buffer[i],        n);
            try testing.expectEqual(back_to_slice[i], n);
        };

        proxyFree(allocator, to_lose_len);
    }
}
