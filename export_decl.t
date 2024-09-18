-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

terra addtwo :: {int, int} -> {int}

struct matrixDouble
terra new_double :: {double} -> {&matrixDouble}
terra del_double :: {&matrixDouble} -> {}
terra setone_double :: {&matrixDouble} -> {}

struct matrixFloat
terra new_float :: {float} -> {&matrixFloat}
terra del_float :: {&matrixFloat} -> {}
terra setone_float :: {&matrixFloat} -> {}
