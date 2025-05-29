-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local concepts = require("concepts")

terraform atomic_store(trg: &T, src: T) where {T: concepts.Integer}
    terralib.cmpxchg(
        trg,
        @trg,
        src,
        {
            success_ordering = "acq_rel",
            failure_ordering = "monotonic"
        }
    )
end

terraform atomic_store(trg: &bool, src: bool)
    return atomic_store([&uint8](trg), [uint8](src))
end

terraform atomic_store(trg: &double, src: double)
    atomic_store([&int64](trg), @[&int64](&src))
end

terraform atomic_store(trg: &float, src: float)
    atomic_store([&int32](trg), @[&int32](&src))
end

terraform atomic_load(src: &T) where {T: concepts.Integer}
    var trg: T = 0
    terralib.cmpxchg(
        &trg,
        trg,
        @src,
        {
            success_ordering = "acq_rel",
            failure_ordering = "monotonic"
        }
    )
    return trg
end

terraform atomic_load(src: &bool)
    return [bool](atomic_load([&uint8](src)))
end

terraform atomic_add(src: &T, inc: T) where {T: concepts.Integer}
    return terralib.atomicrmw("add", src, inc, {ordering = "acq_rel"})
end

terraform atomic_add(src: &T, inc: T) where {T: concepts.Float}
    return terralib.atomicrmw("fadd", src, inc, {ordering = "acq_rel"})
end

terraform atomic_sub(src: &T, inc: T) where {T: concepts.Integer}
    return terralib.atomicrmw("sub", src, inc, {ordering = "acq_rel"})
end

terraform atomic_sub(src: &T, inc: T) where {T: concepts.Float}
    return terralib.atomicrmw("fsub", src, inc, {ordering = "acq_rel"})
end

return {
    store = atomic_store,
    load = atomic_load,
    add = atomic_add,
    sub = atomic_sub,
}
