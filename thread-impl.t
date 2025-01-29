-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc") -- SmartBlock, Allocator
local base = require("base") -- AbstractBase

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
        var a = [alloc.SmartObject(arg_t)].new(allocator)
        a._0 = func
        escape
            for i = 1, #arg do
                emit quote a.["_" .. i] = [ arg[i] ] end
            end
        end
        var t: thread
        t.arg = __move__(a)
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

return {
    pthread = thrd,
    thread = thread,
    mutex = mutex,
    lock_guard = lock_guard,
    cond = cond,
    submit = submit,
    hardware_concurrency = boost.hardware_concurrency,
}
