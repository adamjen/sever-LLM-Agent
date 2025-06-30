const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Mutex = std.Thread.Mutex;

/// Task status enum
pub const TaskStatus = enum {
    pending,
    running,
    completed,
    failed,
};

/// Task priority for scheduling
pub const TaskPriority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,
};

/// Generic result type for async operations
pub fn AsyncResult(comptime T: type) type {
    return union(enum) {
        value: T,
        error_value: anyerror,
    };
}

/// Future/Promise type for async values
pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();
        
        status: TaskStatus = .pending,
        result: ?AsyncResult(T) = null,
        callbacks: ArrayList(fn(*Self) void),
        mutex: Mutex = .{},
        
        pub fn init(allocator: Allocator) Self {
            return Self{
                .callbacks = ArrayList(fn(*Self) void).init(allocator),
            };
        }
        
        pub fn deinit(self: *Self) void {
            self.callbacks.deinit();
        }
        
        /// Complete the future with a value
        pub fn complete(self: *Self, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.status != .pending) return;
            
            self.result = AsyncResult(T){ .value = value };
            self.status = .completed;
            
            // Notify all callbacks
            for (self.callbacks.items) |callback| {
                callback(self);
            }
        }
        
        /// Complete the future with an error
        pub fn completeError(self: *Self, err: anyerror) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.status != .pending) return;
            
            self.result = AsyncResult(T){ .error_value = err };
            self.status = .failed;
            
            // Notify all callbacks
            for (self.callbacks.items) |callback| {
                callback(self);
            }
        }
        
        /// Add a callback to be called when the future completes
        pub fn onComplete(self: *Self, callback: fn(*Self) void) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.status == .completed or self.status == .failed) {
                // Already completed, call immediately
                callback(self);
            } else {
                try self.callbacks.append(callback);
            }
        }
        
        /// Block and wait for the future to complete
        pub fn wait(self: *Self) !T {
            // Simple busy wait - in production, use condition variables
            while (true) {
                self.mutex.lock();
                const status = self.status;
                const result = self.result;
                self.mutex.unlock();
                
                switch (status) {
                    .completed => {
                        return result.?.value;
                    },
                    .failed => {
                        return result.?.error_value;
                    },
                    else => {
                        std.time.sleep(1_000_000); // 1ms
                    },
                }
            }
        }
    };
}

/// Task structure for async execution
pub fn Task(comptime T: type) type {
    return struct {
        const Self = @This();
        
        id: u64,
        priority: TaskPriority = .normal,
        function: fn() anyerror!T,
        future: *Future(T),
        
        pub fn init(id: u64, function: fn() anyerror!T, future: *Future(T)) Self {
            return Self{
                .id = id,
                .function = function,
                .future = future,
            };
        }
        
        pub fn execute(self: *Self) void {
            self.future.status = .running;
            
            if (self.function()) |value| {
                self.future.complete(value);
            } else |err| {
                self.future.completeError(err);
            }
        }
    };
}

/// Thread pool for executing async tasks
pub const ThreadPool = struct {
    allocator: Allocator,
    threads: ArrayList(std.Thread),
    task_queue: ArrayList(*anyopaque),
    queue_mutex: Mutex = .{},
    shutdown: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    
    pub fn init(allocator: Allocator, thread_count: usize) !ThreadPool {
        var pool = ThreadPool{
            .allocator = allocator,
            .threads = ArrayList(std.Thread).init(allocator),
            .task_queue = ArrayList(*anyopaque).init(allocator),
        };
        
        // Create worker threads
        var i: usize = 0;
        while (i < thread_count) : (i += 1) {
            const thread = try std.Thread.spawn(.{}, workerThread, .{&pool});
            try pool.threads.append(thread);
        }
        
        return pool;
    }
    
    pub fn deinit(self: *ThreadPool) void {
        // Signal shutdown
        self.shutdown.store(true, .monotonic);
        
        // Wait for all threads to finish
        for (self.threads.items) |thread| {
            thread.join();
        }
        
        self.threads.deinit();
        self.task_queue.deinit();
    }
    
    fn workerThread(pool: *ThreadPool) void {
        while (!pool.shutdown.load(.monotonic)) {
            // Get task from queue
            pool.queue_mutex.lock();
            const task_ptr = if (pool.task_queue.items.len > 0) 
                pool.task_queue.orderedRemove(0) 
            else 
                null;
            pool.queue_mutex.unlock();
            
            if (task_ptr) |ptr| {
                // Execute task - simplified for now
                // In real implementation, we'd need type erasure handling
                _ = ptr;
            } else {
                std.time.sleep(1_000_000); // 1ms
            }
        }
    }
    
    pub fn submit(self: *ThreadPool, task_ptr: *anyopaque) !void {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();
        
        try self.task_queue.append(task_ptr);
    }
};

/// Global async runtime
pub const AsyncRuntime = struct {
    allocator: Allocator,
    thread_pool: ThreadPool,
    next_task_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    
    pub fn init(allocator: Allocator) !AsyncRuntime {
        const cpu_count = try std.Thread.getCpuCount();
        const thread_count = @max(2, cpu_count);
        
        return AsyncRuntime{
            .allocator = allocator,
            .thread_pool = try ThreadPool.init(allocator, thread_count),
        };
    }
    
    pub fn deinit(self: *AsyncRuntime) void {
        self.thread_pool.deinit();
    }
    
    /// Spawn an async task
    pub fn spawn(self: *AsyncRuntime, comptime T: type, function: fn() anyerror!T) !*Future(T) {
        const future = try self.allocator.create(Future(T));
        future.* = Future(T).init(self.allocator);
        
        const task_id = self.next_task_id.fetchAdd(1, .monotonic);
        const task = try self.allocator.create(Task(T));
        task.* = Task(T).init(task_id, function, future);
        
        // Submit to thread pool
        try self.thread_pool.submit(@ptrCast(task));
        
        return future;
    }
    
    /// Run multiple tasks concurrently and wait for all
    pub fn joinAll(self: *AsyncRuntime, comptime T: type, futures: []*Future(T)) ![]T {
        _ = self;
        var results = try self.allocator.alloc(T, futures.len);
        
        for (futures, 0..) |future, i| {
            results[i] = try future.wait();
        }
        
        return results;
    }
};

/// Channel for communication between async tasks
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();
        
        allocator: Allocator,
        buffer: ArrayList(T),
        capacity: usize,
        mutex: Mutex = .{},
        receivers: ArrayList(*Future(T)),
        closed: bool = false,
        
        pub fn init(allocator: Allocator, capacity: usize) Self {
            return Self{
                .allocator = allocator,
                .buffer = ArrayList(T).init(allocator),
                .capacity = capacity,
                .receivers = ArrayList(*Future(T)).init(allocator),
            };
        }
        
        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
            self.receivers.deinit();
        }
        
        /// Send a value to the channel
        pub fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.closed) return error.ChannelClosed;
            
            // If there's a waiting receiver, deliver directly
            if (self.receivers.items.len > 0) {
                const receiver = self.receivers.orderedRemove(0);
                receiver.complete(value);
                return;
            }
            
            // Otherwise, buffer if there's space
            if (self.buffer.items.len >= self.capacity) {
                return error.ChannelFull;
            }
            
            try self.buffer.append(value);
        }
        
        /// Receive a value from the channel
        pub fn receive(self: *Self) !*Future(T) {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.closed and self.buffer.items.len == 0) {
                return error.ChannelClosed;
            }
            
            // If there's a buffered value, return it immediately
            if (self.buffer.items.len > 0) {
                const value = self.buffer.orderedRemove(0);
                const future = try self.allocator.create(Future(T));
                future.* = Future(T).init(self.allocator);
                future.complete(value);
                return future;
            }
            
            // Otherwise, create a future and wait
            const future = try self.allocator.create(Future(T));
            future.* = Future(T).init(self.allocator);
            try self.receivers.append(future);
            return future;
        }
        
        /// Close the channel
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.closed = true;
            
            // Cancel all waiting receivers
            for (self.receivers.items) |receiver| {
                receiver.completeError(error.ChannelClosed);
            }
            self.receivers.clearRetainingCapacity();
        }
    };
}

/// Select operation for multiple channels
pub fn select(comptime T: type, channels: []Channel(T)) !struct { index: usize, value: T } {
    // Simplified select - in production, use proper synchronization
    while (true) {
        for (channels, 0..) |*channel, i| {
            if (channel.buffer.items.len > 0) {
                channel.mutex.lock();
                if (channel.buffer.items.len > 0) {
                    const value = channel.buffer.orderedRemove(0);
                    channel.mutex.unlock();
                    return .{ .index = i, .value = value };
                }
                channel.mutex.unlock();
            }
        }
        std.time.sleep(1_000_000); // 1ms
    }
}