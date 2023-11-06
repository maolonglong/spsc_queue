const std = @import("std");
const math = std.math;
const testing = std.testing;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub fn SPSCQueue(comptime T: type) type {
    return _SPSCQueue(T, null);
}

// Alloc-free (store up to a small number of items on the stack)
pub fn SPSCQueueComptimeSized(comptime T: type, comptime max_size: usize) type {
    return _SPSCQueue(T, max_size);
}

fn _SPSCQueue(comptime T: type, comptime _max_size: ?usize) type {
    return struct {
        const Self = @This();

        write_index: usize = 0,
        _padding1: [std.atomic.cache_line - @sizeOf(usize)]u8 = undefined,
        read_index: usize = 0,

        buffer: if (_max_size) |n| [n + 1]T else []T = undefined,
        allocator: if (_max_size == null) Allocator else void = if (_max_size == null) undefined else {},

        pub usingnamespace if (_max_size == null)
            struct {
                pub fn init(allocator: Allocator, max_size: usize) !Self {
                    if (@sizeOf(T) > 0) {
                        return .{
                            .buffer = try allocator.alloc(T, max_size + 1),
                            .allocator = allocator,
                        };
                    }
                    var self = Self{
                        .buffer = &[_]T{},
                    };
                    self.buffer.len = max_size + 1;
                    return self;
                }

                pub fn deinit(self: *Self) void {
                    if (@sizeOf(T) > 0) {
                        self.allocator.free(self.buffer);
                    }
                }
            }
        else
            struct {};

        /// Pushes object item to the ringbuffer.
        ///
        /// Only one thread is allowed to push data to the spsc_queue.
        /// Object will be pushed to the spsc_queue, unless it is full.
        ///
        /// Return: true, if the push operation is successful.
        ///
        /// Note: thread-safe and wait-free
        pub fn push(self: *Self, item: T) bool {
            const write_index = @atomicLoad(usize, &self.write_index, .Monotonic);
            const next = self.nextIndex(write_index);

            if (next == @atomicLoad(usize, &self.read_index, .Acquire)) {
                return false; // ringbuffer is full
            }

            self.buffer[write_index] = item; // copy
            @atomicStore(usize, &self.write_index, next, .Release);

            return true;
        }

        /// Pops one object from ringbuffer.
        ///
        /// Only one thread is allowed to pop data to the spsc_queue,
        /// if ringbuffer is not empty, object will be discarded.
        ///
        /// Return: item, if the pop operation is successful, null if ringbuffer was empty.
        ///
        /// Note: thread-safe and wait-free
        pub fn pop(self: *Self) ?T {
            const read_index = @atomicLoad(usize, &self.read_index, .Monotonic);

            if (read_index == @atomicLoad(usize, &self.write_index, .Acquire)) {
                return null;
            }

            const item = self.buffer[read_index];
            const next = self.nextIndex(read_index);
            @atomicStore(usize, &self.read_index, next, .Release);

            return item;
        }

        /// Get reference to element in the front of the queue.
        /// Availability of front element can be checked using readAvailable().
        /// Only a consuming thread is allowed to check front element
        /// read_available() > 0. If ringbuffer is empty, it's undefined behaviour to invoke this method.
        ///
        /// Return: reference to the first element in the queue
        ///
        /// Note: thread-safe and wait-free.
        pub fn peek(self: *Self) *T {
            assert(self.readAvailable() > 0);
            const read_index = @atomicLoad(usize, &self.read_index, .Monotonic);
            return &self.buffer[read_index];
        }

        /// Get number of elements that are available for read.
        ///
        /// Return: number of available elements that can be popped from the spsc_queue.
        ///
        /// Note: thread-safe and wait-free, should only be called from the consumer thread.
        pub fn readAvailable(self: *Self) usize {
            const write_index = @atomicLoad(usize, &self.write_index, .Acquire);
            const read_index = @atomicLoad(usize, &self.read_index, .Monotonic);
            if (write_index >= read_index) {
                return write_index - read_index;
            }
            return write_index + self.buffer.len - read_index;
        }

        /// Get write space to write elements.
        ///
        /// Return: number of elements that can be pushed to the spsc_queue.
        ///
        /// Note: thread-safe and wait-free, should only be called from the producer thread.
        pub fn writeAvailable(self: *Self) usize {
            const write_index = @atomicLoad(usize, &self.write_index, .Monotonic);
            const read_index = @atomicLoad(usize, &self.read_index, .Acquire);
            if (write_index < read_index) {
                return read_index - write_index - 1;
            }
            return self.buffer.len - write_index + read_index - 1;
        }

        /// Check if the ringbuffer is empty.
        ///
        /// Return: true, if the ringbuffer is empty, false otherwise.
        ///
        /// Note: Due to the concurrent nature of the ringbuffer the result may be inaccurate.
        pub fn empty(self: *Self) bool {
            return @atomicLoad(usize, &self.write_index, .Monotonic) ==
                @atomicLoad(usize, &self.read_index, .Monotonic);
        }

        /// Reset the ringbuffer.
        ///
        /// Note: not thread-safe.
        pub fn reset(self: *Self) void {
            @atomicStore(usize, &self.write_index, 0, .Monotonic);
            @atomicStore(usize, &self.read_index, 0, .Release);
        }

        inline fn nextIndex(self: *Self, arg: usize) usize {
            var ret: usize = arg + 1;
            if (ret >= self.buffer.len) {
                ret -= self.buffer.len;
            }
            return ret;
        }
    };
}

test "zero_size_T" {
    var f = try SPSCQueue(void).init(testing.failing_allocator, 2);
    defer f.deinit();

    try testing.expect(f.empty());
    try testing.expect(f.push({}));
    try testing.expect(f.push({}));
    try testing.expect(!f.push({}));

    try testing.expect(f.pop() == {});
    try testing.expect(f.pop() == {});
    try testing.expect(f.pop() == null);
    try testing.expect(f.empty());

    const T = SPSCQueueComptimeSized(void, 100000000);
    try testing.expectEqual(std.atomic.cache_line + @sizeOf(usize), @sizeOf(T));
}

test "comptime_sized" {
    var f = SPSCQueueComptimeSized(i32, 2){};

    try testing.expect(f.empty());
    try testing.expect(f.push(1));
    try testing.expect(f.push(2));
    try testing.expect(!f.push(3));

    try testing.expect(f.pop() == 1);
    try testing.expect(f.pop() == 2);
    try testing.expect(f.pop() == null);
    try testing.expect(f.empty());
}

test "simple_spsc_queue_test" {
    var f = try SPSCQueue(i32).init(testing.allocator, 64);
    defer f.deinit();

    try testing.expect(f.empty());
    try testing.expect(f.push(1));
    try testing.expect(f.push(2));

    try testing.expect(f.pop() == 1);
    try testing.expect(f.pop() == 2);
    try testing.expect(f.pop() == null);
    try testing.expect(f.empty());
}

fn testAvailable(q: anytype) !void {
    try testing.expectEqual(@as(usize, 16), q.writeAvailable());
    try testing.expectEqual(@as(usize, 0), q.readAvailable());

    for (0..8) |i| {
        try testing.expectEqual(@as(usize, 16) - i, q.writeAvailable());
        try testing.expectEqual(i, q.readAvailable());

        _ = q.push(1);
    }

    while (q.pop() != null) {}

    for (0..16) |i| {
        try testing.expectEqual(@as(usize, 16) - i, q.writeAvailable());
        try testing.expectEqual(i, q.readAvailable());

        _ = q.push(1);
    }

    q.reset();
    try testing.expectEqual(@as(usize, 16), q.writeAvailable());
    try testing.expectEqual(@as(usize, 0), q.readAvailable());
}

test "spsc_queue_avail_test" {
    var q1 = try SPSCQueue(i32).init(testing.allocator, 16);
    defer q1.deinit();
    try testAvailable(&q1);

    var q2 = SPSCQueueComptimeSized(i32, 16){};
    try testAvailable(&q2);
}

test "multi-thread" {
    const iterations: usize = 1000000;

    const Q = SPSCQueue(i32);
    const Closure = struct {
        const Self = @This();

        read_count: usize = 0,
        write_done: bool = false,
        q: Q,

        fn producer(self: *Self) !void {
            for (0..iterations) |_| {
                while (!self.q.push(1)) {
                    try std.Thread.yield();
                }
            }
            @atomicStore(bool, &self.write_done, true, .SeqCst);
        }

        fn consumer(self: *Self) !void {
            while (!@atomicLoad(bool, &self.write_done, .SeqCst)) {
                if (self.q.pop() != null) {
                    self.read_count += 1;
                } else {
                    try std.Thread.yield();
                }
            }
            while (self.q.pop() != null) {
                self.read_count += 1;
            }
        }
    };

    var c = Closure{
        .q = try Q.init(testing.allocator, 1024),
    };
    defer c.q.deinit();

    const thread = try std.Thread.spawn(.{}, Closure.producer, .{&c});
    try c.consumer();
    thread.join();

    try testing.expectEqual(iterations, c.read_count);
}
