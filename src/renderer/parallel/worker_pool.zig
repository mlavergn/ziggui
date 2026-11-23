//! A small pool of persistent threads that runs one job at a time over a
//! number of tasks: a parallel `for`, with the calling thread working too.

const std = @import("std");
const log = std.log.scoped(.ziggui_worker_pool);
const mod = @import("module.zig");

/// Persistent worker threads that split a job's tasks between them and the
/// thread calling `run`.
///
/// A job is a context and a function called once per task index, `0..count`;
/// threads take the next index from a shared counter until none is left, so
/// a slow task or a slow core never holds the others back. `run` returns once
/// every task finished. Between jobs the threads sleep on a futex and cost
/// nothing.
///
/// One job at a time: `run` is called from one thread (the one that owns the
/// pool), never concurrently. Heap-allocated (`create`): the threads hold its
/// address.
pub const WorkerPool = struct {
    const Self = @This();

    /// The most workers `defaultWorkerCount` picks: past it memory bandwidth,
    /// not cores, bounds work as simple as filling pixels.
    pub const max_default_workers: usize = 16;

    /// The most workers `create` makes, whatever it is asked for: a count
    /// from the environment or a setting never spawns thousands of threads.
    pub const max_workers: usize = 256;

    /// Owns the pool and its thread list.
    allocator: std.mem.Allocator,
    /// The I/O the threads sleep and wake through (its futex).
    io: std.Io,
    /// Room for every thread `create` asked for.
    thread_storage: []std.Thread,
    /// The threads that started, a prefix of `thread_storage`; the calling
    /// thread is the pool's other worker.
    threads: []std.Thread,
    /// Counts jobs; the threads sleep on it until it moves.
    generation: std.atomic.Value(u32) = .init(0),
    /// The spawned threads still in the current job; `run` sleeps on it.
    remaining: std.atomic.Value(u32) = .init(0),
    /// The next task index to hand out.
    next_task: std.atomic.Value(usize) = .init(0),
    /// How many tasks the current job has.
    task_count: usize = 0,
    /// The current job's context, type-erased.
    context: *const anyopaque = undefined,
    /// The current job's function, type-erased.
    ///
    /// - `context`: the job's context.
    /// - `index`: the task's index.
    function: *const fn (context: *const anyopaque, index: usize) void = undefined,
    /// Set by `destroy`: the threads leave instead of working.
    stopping: std.atomic.Value(bool) = .init(false),

    /// Makes a pool of `worker_count` workers: the calling thread and
    /// `worker_count - 1` threads. A thread that cannot start is logged and
    /// left out, so the pool may run with fewer; at 1 (or 0) it spawns none
    /// and `run` works on the calling thread alone; past `max_workers` it
    /// makes `max_workers` (logged).
    ///
    /// - `allocator`: allocator for the pool.
    /// - `io`: the I/O the threads sleep and wake through; only its futex is
    ///   used, so `std.Io.Threaded.global_single_threaded.io()` serves.
    /// - `worker_count`: how many workers, the calling thread included.
    /// - Returns: the pool, owned by the caller (`destroy`); propagates allocation failure.
    pub fn create(allocator: std.mem.Allocator, io: std.Io, worker_count: usize) !*Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        if (worker_count > Self.max_workers) log.warn("{d} workers asked for, {d} made", .{ worker_count, Self.max_workers });
        const wanted = std.math.clamp(worker_count, 1, Self.max_workers) - 1;
        const storage = try allocator.alloc(std.Thread, wanted);
        self.* = .{ .allocator = allocator, .io = io, .thread_storage = storage, .threads = storage[0..0] };
        for (storage, 0..) |*thread, index| {
            thread.* = std.Thread.spawn(.{}, Self.loop, .{self}) catch |err| {
                log.warn("worker thread {d} of {d} not started: {s}", .{ index + 1, wanted, @errorName(err) });
                break;
            };
            self.threads = storage[0 .. index + 1];
        }
        return self;
    }

    /// Stops and joins the threads, then frees the pool.
    ///
    /// - `self`: the pool; invalid afterwards.
    pub fn destroy(self: *Self) void {
        self.stopping.store(true, .release);
        _ = self.generation.fetchAdd(1, .release);
        self.io.futexWake(u32, &self.generation.raw, std.math.maxInt(u32));
        for (self.threads) |thread| thread.join();
        const allocator = self.allocator;
        allocator.free(self.thread_storage);
        allocator.destroy(self);
    }

    /// The default worker count for this machine: its logical CPUs, at most
    /// `max_default_workers`, 1 when the count cannot be read.
    ///
    /// - Returns: the worker count, at least 1.
    pub fn defaultWorkerCount() usize {
        const cpus = std.Thread.getCpuCount() catch |err| blk: {
            log.warn("CPU count unknown, one worker: {s}", .{@errorName(err)});
            break :blk 1;
        };
        return std.math.clamp(cpus, 1, Self.max_default_workers);
    }

    /// How many workers run a job: the threads that started and the caller.
    ///
    /// - `self`: the pool.
    /// - Returns: the worker count, at least 1.
    pub fn workerCount(self: *const Self) usize {
        return self.threads.len + 1;
    }

    /// Runs `function(context, index)` for every `index` in `0..task_count`,
    /// split between the threads and the calling thread, and returns once all
    /// have finished. Tasks run in no particular order and concurrently, so
    /// each must touch only what no other task does. A single task, or a pool
    /// with no threads, runs on the calling thread alone.
    ///
    /// - `self`: the pool.
    /// - `T`: the context's type.
    /// - `context`: what every task reads; it outlives the call.
    /// - `function`: the task, given the context and its index.
    /// - `task_count`: how many tasks.
    pub fn run(
        self: *Self,
        comptime T: type,
        context: *const T,
        comptime function: fn (context: *const T, index: usize) void,
        task_count: usize,
    ) void {
        if (task_count == 0) return;
        if (task_count == 1 or self.threads.len == 0) {
            for (0..task_count) |index| function(context, index);
            return;
        }
        const Trampoline = struct {
            /// Calls `function` with the context's type restored.
            ///
            /// - `erased`: the context.
            /// - `index`: the task's index.
            fn call(erased: *const anyopaque, index: usize) void {
                function(@ptrCast(@alignCast(erased)), index);
            }
        };
        self.context = context;
        self.function = Trampoline.call;
        self.task_count = task_count;
        self.next_task.store(0, .monotonic);
        self.remaining.store(@intCast(self.threads.len), .monotonic);
        // Publishes the job: a thread that sees the new generation sees it all.
        _ = self.generation.fetchAdd(1, .release);
        self.io.futexWake(u32, &self.generation.raw, std.math.maxInt(u32));
        self.work();
        while (true) {
            const left = self.remaining.load(.acquire);
            if (left == 0) break;
            self.io.futexWaitUncancelable(u32, &self.remaining.raw, left);
        }
    }

    /// Takes task indices until none is left, running each.
    ///
    /// - `self`: the pool.
    fn work(self: *Self) void {
        while (true) {
            const index = self.next_task.fetchAdd(1, .monotonic);
            if (index >= self.task_count) return;
            self.function(self.context, index);
        }
    }

    /// A thread's life: sleep until a job is published, work it, report done.
    ///
    /// - `self`: the pool.
    fn loop(self: *Self) void {
        var seen: u32 = 0;
        while (true) {
            var current = self.generation.load(.acquire);
            while (current == seen) {
                self.io.futexWaitUncancelable(u32, &self.generation.raw, seen);
                current = self.generation.load(.acquire);
            }
            seen = current;
            if (self.stopping.load(.acquire)) return;
            self.work();
            if (self.remaining.fetchSub(1, .acq_rel) == 1) self.io.futexWake(u32, &self.remaining.raw, 1);
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// A job that counts how often each task ran.
const CountingJob = struct {
    const Self = @This();

    /// One counter per task.
    counts: []std.atomic.Value(u32),

    /// Counts the task.
    ///
    /// - `self`: the job.
    /// - `index`: the task's index.
    fn task(self: *const Self, index: usize) void {
        _ = self.counts[index].fetchAdd(1, .monotonic);
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "WorkerPool: every task runs once, job after job" {
    const allocator = std.testing.allocator;
    const pool = try mod.WorkerPool.create(allocator, std.testing.io, 4);
    defer pool.destroy();
    var counts: [257]std.atomic.Value(u32) = @splat(.init(0));
    const job: CountingJob = .{ .counts = &counts };
    for (0..50) |_| pool.run(CountingJob, &job, CountingJob.task, counts.len);
    for (&counts) |*count| try std.testing.expectEqual(@as(u32, 50), count.load(.monotonic));
}

test "WorkerPool: one worker runs on the calling thread; no tasks do nothing" {
    const allocator = std.testing.allocator;
    const pool = try mod.WorkerPool.create(allocator, std.testing.io, 1);
    defer pool.destroy();
    try std.testing.expectEqual(@as(usize, 1), pool.workerCount());
    var counts: [3]std.atomic.Value(u32) = @splat(.init(0));
    const job: CountingJob = .{ .counts = &counts };
    pool.run(CountingJob, &job, CountingJob.task, 0);
    pool.run(CountingJob, &job, CountingJob.task, counts.len);
    for (&counts) |*count| try std.testing.expectEqual(@as(u32, 1), count.load(.monotonic));
}

test "WorkerPool: a huge count is held to max_workers" {
    const pool = try mod.WorkerPool.create(std.testing.allocator, std.testing.io, 1 << 30);
    defer pool.destroy();
    try std.testing.expect(pool.workerCount() <= mod.WorkerPool.max_workers);
}

test "WorkerPool: an idle pool stops cleanly" {
    const pool = try mod.WorkerPool.create(std.testing.allocator, std.testing.io, 8);
    pool.destroy();
}

test "WorkerPool: defaultWorkerCount is between 1 and the cap" {
    const count = mod.WorkerPool.defaultWorkerCount();
    try std.testing.expect(count >= 1 and count <= mod.WorkerPool.max_default_workers);
}
