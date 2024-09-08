const std = @import("std");
const assert = std.debug.assert;
const atomic = std.atomic;
const Condition = std.Thread.Condition;
const Mutex = std.Thread.Mutex;

pub fn ThreadSafeQueue(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        const Fifo = std.fifo.LinearFifo(T, .{ .Static = size });

        fifo: Fifo = Fifo.init(),
        mutex: Mutex = .{},
        not_full: Condition = .{},
        not_empty: Condition = .{},

        pub fn init() Self {
            return .{};
        }

        pub fn deinit(self: *Self) void {
            self.fifo.deinit();
        }

        fn doPopLH(self: *Self) T {
            while (self.isEmptyLH()) {
                self.not_empty.wait(&self.mutex);
            }

            if (self.isFullLH()) {
                // We're about to remove 1 item, making it no longer
                // full.
                self.not_full.signal();
            }

            // This must succeed because we had the lock when we
            // checked for empty.
            return self.fifo.readItem().?;
        }

        /// Pop an item off the queue. Blocks until one is available.
        pub fn pop(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.doPopLH();
        }

        fn doPushLH(self: *Self, item: T) void {
            while (self.isFullLH()) {
                self.not_full.wait(&self.mutex);
            }

            if (self.isEmptyLH()) {
                // We're about to add one item, making it no longer
                // empty.
                self.not_empty.signal();
            }

            self.fifo.writeItemAssumeCapacity(item);
        }

        /// Push an item onto the queue. Blocks until it succeeds.
        pub fn push(self: *Self, item: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.doPushLH(item);
        }

        fn isEmptyLH(self: Self) bool {
            return self.fifo.readableLength() == 0;
        }

        fn isFullLH(self: Self) bool {
            return self.fifo.readableLength() == size;
        }

        /// Non-blocking version of `push`. This returns `true` if the
        /// item was successfully placed in the queue, and `false` if
        /// not.
        pub fn tryPush(self: *Self, item: T) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.isFullLH())
                return false;

            self.doPushLH(item);
            return true;
        }

        /// Non-blocking version of `pop`. This returns `null` when
        /// the queue was empty, and a value when it wasn't.
        pub fn tryPop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.isEmptyLH())
                return null;
            return self.doPopLH();
        }

        /// Returns `true` if the queue is empty and `false` otherwise.
        pub fn isEmpty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.isEmptyLH();
        }

        /// Returns `true` if the queue is full and `false` otherwise.
        pub fn isFull(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.isFullLH();
        }
    };
}
