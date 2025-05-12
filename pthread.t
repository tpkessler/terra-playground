-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local base = require("base") -- AbstractBase

local C = terralib.includec("stdio.h")

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

-- With a mutex you can restrict code access to a single thread.
local struct mutex {
    id: thrd.mutex_t
}
base.AbstractBase(mutex)

terra mutex:__init()
    var ret = thrd.mutex_init(&self.id, nil)
end

terra mutex:__dtor()
    var ret = thrd.mutex_destroy(&self.id)
end

for _, method in pairs{"lock", "trylock", "unlock"} do
    local func = thrd["mutex_" .. method]
    mutex.methods[method] = terra(self: &mutex)
        return [func](&self.id)
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
    C = thrd,
    mutex = mutex,
    lock_guard = lock_guard,
    cond = cond,
    hardware_concurrency = boost.hardware_concurrency,
}
