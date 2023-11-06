const std = @import("std");
const bench = @import("bench");
const spsc = @import("spsc");
const testing = std.testing;

test {
    try bench.benchmark(struct {
        const numitems: usize = 100_000;

        pub const min_iterations = 100;

        pub fn spscQueue() !usize {
            const Q = spsc.SPSCQueue(i32);

            const Closure = struct {
                const Self = @This();

                read_count: usize = 0,
                write_done: bool = false,
                q: Q,

                fn producer(self: *Self) !void {
                    for (0..numitems) |_| {
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

            try testing.expectEqual(numitems, c.read_count);
            return c.read_count;
        }

        pub fn arraylist() !usize {
            const Q = std.ArrayList(i32);

            const Closure = struct {
                const Self = @This();

                read_count: usize = 0,
                write_done: bool = false,
                q: Q,
                mu: std.Thread.Mutex = .{},

                fn producer(self: *Self) !void {
                    for (0..numitems) |_| {
                        self.mu.lock();
                        try self.q.append(1);
                        self.mu.unlock();
                    }
                    @atomicStore(bool, &self.write_done, true, .SeqCst);
                }

                fn consumer(self: *Self) !void {
                    while (!@atomicLoad(bool, &self.write_done, .SeqCst)) {
                        self.mu.lock();
                        const ret = self.q.popOrNull();
                        self.mu.unlock();
                        if (ret == null) {
                            try std.Thread.yield();
                        } else {
                            self.read_count += 1;
                        }
                    }
                    while (self.q.items.len > 0) {
                        _ = self.q.pop();
                        self.read_count += 1;
                    }
                }
            };

            var c = Closure{
                .q = Q.init(testing.allocator),
            };
            defer c.q.deinit();

            const thread = try std.Thread.spawn(.{}, Closure.producer, .{&c});
            try c.consumer();
            thread.join();

            try testing.expectEqual(numitems, c.read_count);
            return c.read_count;
        }
    });
}
