-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc") -- SmartBlock, Allocator
local base = require("base") -- AbstractBase
local atomics = require("atomics")

-- SPDX-SnippetBegin
-- SPDX-SnippetCopyrightText 2001-2003
-- SPDX-SnippetCopyrightText 2007-8 Anthony Williams
-- SPDX-SnippetCopyrightText 2011-2012 Vicente J. Botet Escriba
-- SPDX-License-Identifier: BSL-1.0
local boost = terralib.includecstring[[
// Part of the Boost thread library,
// https://github.com/boostorg/thread/blob/48482ff6961e986360047f800b3979f3742453ba/src/pthread/thread.cpp
// Copyright (C) 2001-2003
// Copyright (C) 2007-8 Anthony Williams
// Copyright 2011-2012 Vicente J. Botet Escriba
// Distributed under the Boost Software License, Version 1.0. (See accompanying
// file LICENSES/BSL-1.0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
#define BOOST_HAS_UNISTD_H
#include <unistd.h>
#include <pthread.h>
#ifdef __GLIBC__
#include <sys/sysinfo.h>
#elif defined(__APPLE__) || defined(__FreeBSD__)
#include <sys/types.h>
#include <sys/sysctl.h>
#else
#include <unistd.h>
#endif
unsigned hardware_concurrency()
{
    #if defined(PTW32_VERSION) || defined(__hpux)
            return pthread_num_processors_np();
    #elif defined(__APPLE__) || defined(__FreeBSD__)
            int count;
            size_t size=sizeof(count);
            return sysctlbyname("hw.ncpu",&count,&size,NULL,0)?0:count;
    #elif defined(BOOST_HAS_UNISTD_H) && defined(_SC_NPROCESSORS_ONLN)
            int const count=sysconf(_SC_NPROCESSORS_ONLN);
            return (count>0)?count:0;
    #elif defined(__GLIBC__)
            return get_nprocs();
    #else
            return 0;
    #endif
}
]]
-- SPDX-SnippetEnd

-- Terralib extension for RAII
require("terralibext")

-- For a full documentation of threads in C11, see
-- https://en.cppreference.com/w/c/thread
local thrd = (
    setmetatable(
        terralib.includec("pthread.h"),
        {__index = (
                function(self, name)
                    return (
                        -- Since C doesn't have name spaces, most functions
                        -- and data types are prefixed with "pthread_". When
                        -- using this in terra it can be inconvenient to type
                        --
                        -- thrd.pthread_FOO
                        --
                        -- when trying to access the function FOO. Hence, we
                        -- define our own __index function for the terra wrapper
                        -- of the threads.h header. The rawget() function
                        -- bypasses the __index function as otherwise we'd
                        -- trigger an infinite recursion.
                        rawget(self, "pthread_" .. name)
                        or rawget(self, name)
                    )
                end
            )
        }
    )
)

local uname = io.popen("uname", "r"):read("*a")
if uname == "Linux\n" then
    terralib.linklibrary("libpthread.so.0")
elseif uname == "Darwin\n" then
    terralib.linklibrary("libpthread.dylib")
else
    error("Unsupported platform for multithreading")
end
local sched = terralib.includec("sched.h")

-- A thread has a unique ID that executes a given function with signature FUNC.
-- Its argument is stored as a managed pointer on the (global) heap. This way,
-- threads can be passed to other functions and executed there. The life time
-- of the argument arg is thus not bound to the life time of the local stack.
local FUNC = &opaque -> &opaque
local struct thread {
    id: thrd.pthread_t
    func: FUNC
    arg: alloc.SmartBlock(int8, {copyby = "view"})
}
base.AbstractBase(thread)

terra thread.metamethods.__eq(self: &thread, other: &thread)
    return thrd.equal(self.id, other.id)
end

-- Pause the calling thread for a short period and resume afterwards.
thread.staticmethods.yield = (
    terra()
        return sched.sched_yield()
    end
)

-- Exit thread with given the return value res.
thread.staticmethods.exit = (
    terra()
        return thrd.exit(nil)
    end
)

-- After a new thread is created, it forks from the calling thread. To access
-- results of the forked thread we have to join it with the calling thread.
terra thread:join()
    return thrd.join(self.id, nil)
end

-- This is the heart of the thread module.
-- Given an allocator instance for memory management and a callable and
-- copyable instance (a function pointer, a lambda, a struct instance with
-- an overloaded apply, or a terraform function) and a list of copyable
-- arguments, it generates a terra function with signature FUNC and a datatype
-- that stores the function arguments. It returns a thread instance but not
-- starting the thread.
local submit = macro(function(allocator, func, ...)
    -- terralib.List is a lua list with some usefull methods like map and insert
    local arg = terralib.newlist({...})
    -- The macro runs in lua mode but the arguments are passed from terra.
    -- The terra data is passed as node in the abstract syntax tree. As part of
    -- this, we cannot access the value of the arguments (as it has no meaning
    -- in lua) but their types. We need them to generate our wrapper type for
    -- the C thread.
    local typ = arg:map(function(x) return x:gettype() end)
    -- Symbols are important for metaprogramming of terra functions from lua.
    -- They represent lazy terra variables. From terra code, they behave like
    -- terra variables. But they are also lua variables, so we can put them
    -- in tables or use it to construct types. Terra types (structs) are called
    -- exotypes because they can be constructed outside of terra, that is in
    -- lua.
    local sym = typ:map(function(T) return symbol(T) end)
    local functype = func:gettype()
    typ:insert(1, functype)
    -- tuple is a special struct type whose fields are named _0, _1, ...
    local arg_t = tuple(unpack(typ))
    local funcsym = symbol(functype)

    -- Our thread conforming wrapper around the provided callable.
    local terra pfunc(parg: &opaque)
        var arg = [&arg_t](parg)
        var [funcsym] = arg._0
        -- With escape ... end we can always leave terra and get access again
        -- to lua. Here, we use it for loop unrolling.
        escape
            for i = 1, #sym do
                emit quote var [ sym[i] ] = arg.["_" .. i] end
            end
        end
        [funcsym]([sym])
        return parg
    end

    -- Now that we have the function wrapper pfunc and the wrapper type for
    -- arguments arg_t, we can setup a thread with the given information.
    -- The important part here is that the argument wrapper is allocated by
    -- the provided allocator. The allocated block has to outlive the thread.
    -- This means we cannot use a pointer to stack memory inside the quote.
    return quote
        var a: alloc.SmartBlock(arg_t, {copyby = "view"}) = (
            allocator:new(1, sizeof(arg_t))
        )
        a(0)._0 = func
        escape
            for i = 1, #arg do
                emit quote a(0).["_" .. i] = [ arg[i] ] end
            end
        end
        var t: thread
        t.arg = a
        t.func = pfunc
    in
        t
    end
end)

thread.staticmethods.new = macro(function(allocator, func, ...)
    local arg = {...}
    return quote
        -- This sets up all the wrapper stuff ...
        var t = submit(allocator, func, [arg])
        -- ... and then spawns a thread.
        thrd.create(&t.id, nil, t.func, &t.arg(0))
    in
        t
    end
end)

-- With a mutex you can restrict code access to a single thread.
local struct mutex {
    id: thrd.mutex_t
}
base.AbstractBase(mutex)

terra mutex:__init()
    thrd.mutex_init(&self.id, nil)
end

terra mutex:__dtor()
    thrd.mutex_destroy(&self.id)
end

for _, method in pairs{"lock", "trylock", "unlock"} do
    local func = thrd["mutex_" .. method]
    mutex.methods[method] = terra(self: &mutex)
        return func(&self.id)
    end
end

-- A lock guard is an abstraction of a mutex. Given a mutex, it locks it after
-- assignment, see __copy, and unlocks the mutex when the lock guard goes out
-- of scope, see __dtor. This means that the mutex is locked for the life time
-- (that is scope) of the lock guard. 
local struct lock_guard {
    mutex: &mutex   
}
base.AbstractBase(lock_guard)

terra lock_guard:__init()
    self.mutex = nil
end

lock_guard.methods.__copy = (
    terra(from: &mutex, to: &lock_guard)
        to.mutex = from
        to.mutex:lock()
    end
)

terra lock_guard:__dtor()
    self.mutex:unlock()
    self.mutex = nil
end

-- Conditions can used to synchronize threads. You can wait until a condition
-- is met and signal one or all waiting threads.
local struct cond {
    id: thrd.cond_t
}
base.AbstractBase(cond)

terra cond:__init()
    thrd.cond_init(&self.id, nil)
end

terra cond:__dtor()
    thrd.cond_destroy(&self.id)
end

-- cond:signal() notifies one waiting thread, broadcast notifies all waiting
-- threads.
for _, method in pairs{"signal", "broadcast"} do
    local func = thrd["cond_" .. method]
    cond.methods[method] = terra(self: &cond)
        return func(&self.id)
    end
end

-- cond:wait() takes a locked mutex and waits until another thread signals
-- the same condition.
terra cond:wait(mtx: &mutex)
    return thrd.cond_wait(&self.id, &mtx.id)
end

local stack = require("stack")
local Alloc = alloc.Allocator
local blockThread = alloc.SmartBlock(thread, {copyby = "view"})
local queueThread = stack.DynamicStack(thread)

-- Queue with thread-safe memory access via mutex
local ThreadsafeQueue = terralib.memoize(function(T)
    local S = stack.DynamicStack(T)
    local struct threadsafe_queue {
        mutex: mutex
        data: S
    }
    base.AbstractBase(threadsafe_queue)

    terra threadsafe_queue:isempty()
        var guard: lock_guard = self.mutex
        return self.data:size() == 0
    end

    terra threadsafe_queue:push(t: T)
        var guard: lock_guard = self.mutex
        self.data:push(t)
    end

    terra threadsafe_queue:try_pop(t: &T)
        self.mutex:lock()
        if self.data:size() == 0 then
            self.mutex:unlock()
            return false
        else
            @t = self.data:pop()
            self.mutex:unlock()
            return true
        end
    end

    threadsafe_queue.staticmethods.new = (
        terra(alloc: Alloc, capacity: int64)
            var q: threadsafe_queue
            q.data = S.new(alloc, capacity)
            return q
        end
    )
    
    return threadsafe_queue
end)

-- A join_threads struct is an abstraction over a block of threads that
-- automatically joins all threads when the threads go out of scope.
local block_thread = alloc.SmartBlock(thread, {copyby = "view"})
local struct join_threads {
    data: block_thread
}

terra join_threads:__dtor()
    for i = 0, self.data:size() do
        self.data(i):join()
    end
end

local queue_thread = ThreadsafeQueue(thread)

-- A thread pool is a collection of actively running threads (until the thread
-- pool goes out of scope) that run submitted jobs concurrently.
local struct threadpool {
    -- Signals the destructor if all threads finished their work.
    -- IMPORTANT: Only access this value with atomics
    done: bool 
    -- When the destructor sets done to true, threads may not all exit at the
    -- same time (as they run concurrently) so we have to wait until all
    -- threads have updated their local value of done and finish. In this case,
    -- they decrement threads_alive by one. Initially, this value was increased
    -- by one in the constructor. Here, we also use the value to wait until
    -- all threads are properly initialized before we return the new thread
    -- pool.
    -- IMPORTANT: Only access this value with atomics
    threads_alive: int64
    -- This value plays a similar role as threads_alive. However, it is not
    -- used in the destructor but in the barrier() method. In this case, it is
    -- a synchronization point for all threads. We wait for all threads to
    -- finish their work before proceeding with our computation.
    -- IMPORTANT: Only access this value with atomics
    threads_working: int64
    -- Thread safe queue with the submitted work to the thread pool. Each work
    -- item is wrapped as a thread instance. These are virtual threads as they
    -- do not actually run on the CPU.
    work_queue: queue_thread
    -- Condition used to signal the addition of a new work item to the work
    -- queue with corresponding mutex.
    work_signal: cond
    work_mutex: mutex
    -- Condition used to signal synchronization at barriers or at shutdown.
    done_signal: cond
    done_mutex: mutex
    -- Array of physical threads running on the CPU
    threads: block_thread
    -- Automic join() of physical threads when the thread pool goes out of scope
    joiner: join_threads
}
base.AbstractBase(threadpool)

-- Synchronize all physical threads in thread pool.
-- The computation only continues after the work queue of the thread pool is
-- empty and no threads are working.
terra threadpool:barrier()
    var guard: lock_guard = self.done_mutex
    -- A thrd.condition does not implement any logic. This always has to be
    -- checked outside of the condition. Furthermore, condition:wait() should
    -- always be checked in a while loop as it is possible for the runtime to
    -- wake up a condition even if the condition to be checked is not satisfied
    -- yet.
    while (
            not self.work_queue:isempty()
            or atomics.load(&self.threads_working) > 0
          ) do
        self.done_signal:wait(&self.done_mutex)
    end
end

terra threadpool:__dtor()
    -- It is crucial to keep the right order in the destructor.
    -- First, we need to wait until all threads have finished their work ...
    self:barrier()
    -- ... before notifying all threads that the thread pool shuts down.
    -- Again, we cannot just set done to true and continue with the destruction
    -- since threads read the new value of done at different times ...
    atomics.store(&self.done, true)
    -- ... so we have to signal all threads that still wait for work from the
    -- work queue that they should continue. At this point, because we called
    -- barrier(), the work queue is empty.
    do
        var guard: lock_guard = self.done_mutex
        while atomics.load(&self.threads_alive) > 0 do
            self.work_signal:broadcast()
        end
    end
    -- Now, all threads have finished their work and are left at the buttom of
    -- the thread worker function. At this point, we join them back into the
    -- main thread.
    self.joiner:__dtor()
    self.threads:__dtor()
    -- FIXME Currently can trigger segfaults
    -- self.work_queue:__dtor()
    self.done_signal:__dtor()
    self.done_mutex:__dtor()
    self.work_signal:__dtor()
    self.work_mutex:__dtor()
end

-- The program already runs concurrently when new work is submitted. Hence,
-- we need to careful when adding it to the thread pool.
-- Firstly, we need to signal that to the physical threads that a new work item
-- is available and, secondly, need to add to the work queue. Note that this
-- access is protected by a mutex as other threads may request new work from it
-- at the same time.
threadpool.methods.submit = macro(function(self, allocator, func, ...)
    local arg = {...}
    return quote
        var t = submit(allocator, func, [arg])
        self.work_signal:signal()
    in
        self.work_queue:push(t)
    end
end)

-- The heart of the thread pool, the virtual thread, aka worker thread.
-- It constantly waits for new work from the work queue. It is very important
-- that every memory access is properly synchronized or prototected,
-- in particular when requesting new work from the queue (try_pop) or when
-- doing bookkeeping on the number of alive and working thread. A thread
-- is working while executing the corresponding function of a work item.
-- It is alive while executing the while loop. The only way to leave it is via
-- the destructor that sets done = true.
--
-- As mentioned multiple times, the order of checks and of the final work
-- execution is crucial for in a concurrent context.
--
-- The early destructor check provides a shortcut for and early thread exit
-- in case that there is no work or only a few work items submitted to the
-- thread pool. The first block is the counterpart for the corresponding
-- block in the destructor.
--
-- Work distribution has to be handled carefully to guarantee correct
-- bookkeeping of the number of working threads and the size of work queue.
--
-- The barrier check should go last to not provoke an early done_condition
-- resolution. If checked in the very beginning it would happen the
-- threads_working field is 0 without checking the size of the work queue
-- before.
threadpool.staticmethods.worker_thread = (
    terra(parg: &opaque)
        var tp = [&threadpool](parg)
        atomics.add(&tp.threads_alive, 1)
        while true do
            --
            -- Destructor block
            --
            tp.work_mutex:lock()
            -- As noted above, conditions should always be checked in a while
            -- loop as the runtime is allowed to wake up conditions.
            -- This rarely happens but an equivalent check in an if statement
            -- is not considered thread safe.
            while not atomics.load(&tp.done) and tp.work_queue:isempty() do
                tp.work_signal:wait(&tp.work_mutex)
            end
            if atomics.load(&tp.done) then
                break
            end
            --
            -- Work distribution
            --
            var t: thread
            var has_work = tp.work_queue:try_pop(&t)
            tp.work_mutex:unlock()
            if has_work then
                atomics.add(&tp.threads_working, 1)
                t.func(&t.arg(0))
                atomics.sub(&tp.threads_working, 1)
            end
            --
            -- Barrier check
            --
            if atomics.load(&tp.threads_working) == 0 then
               tp.done_signal:signal() 
            end
        end
        -- We can only arrive here via the break statement inside the while
        -- loop. In this case, work_mutex is still locked from the wait()
        -- statement. Hence, we need to 
        tp.work_mutex:unlock()
        atomics.sub(&tp.threads_alive, 1)
        return 0
    end
)

-- Because all virtual threads share a reference to the thread pool, we have
-- to allocate memory in an address space that outlives the new() method, that
-- is we cannot declare
--
-- var tp: threadpool
--
-- inside the function and then initialized the physical thread with a reference
-- to tp. The threads live beyond the scope of this function but the instance
-- of the thread pool does not. The solution is to associate it with an
-- allocator that, since it is passed as an argument to the function, outlives
-- the lifetime of the function.
--
-- SmartObject is a convenience wrapper around a pointer to a given data type
-- that exposes all fields and methods defined on the type so that it can be
-- used almost identically to an instance of the type.
local smart_threadpool = alloc.SmartObject(threadpool)
threadpool.staticmethods.new = (
    terra(alloc: Alloc, nthreads: uint64)
        var tp = smart_threadpool.new(alloc)
        tp.threads_alive = 0
        tp.threads_working = 0
        tp.work_queue = queue_thread.new(alloc, nthreads)
        tp.done = false
        tp.threads = alloc:new(nthreads, sizeof(thread))
        tp.joiner = join_threads {tp.threads}
        -- The point of no return. From this point on, we are running the 
        -- program concurrently.
        for i = 0, nthreads do
            tp.threads(i) = (
                thread.new(
                    alloc,
                    [threadpool.staticmethods.worker_thread],
                    tp.ptr
                )
            )
        end
        -- Ensure that all threads are ready before returning the freshly
        -- initialized thread pool.
        while tp.threads_alive ~= nthreads do thread.yield() end
        return tp
    end
)

local parfor = macro(function(alloc, rn, go)
    -- Use the maximum number of threads available on the host. This includes
    -- virtual cores (Hyperthreading for Intel, SMT for AMD).
    local nthreads = `boost.hardware_concurrency()
    return (
        quote
            -- Wrap everything in a do block to trigger a desctructor call
            -- for the thread pool after the for loop that distributes work.
            -- Note that the actual computation does not happen in the for loop
            -- but anytime between the submission and the barrier inside the
            -- destructor.
            do
                var tp = threadpool.new(alloc, [nthreads])
                for it in rn do
                    tp:submit(alloc, go, it)
                end
            end
        end
    )
end)

return {
    thread = thread,
    join_threads = join_threads,
    mutex = mutex,
    lock_guard = lock_guard,
    cond = cond,
    threadpool = threadpool,
    max_threads = boost.hardware_concurrency,
    parfor = parfor,
}
