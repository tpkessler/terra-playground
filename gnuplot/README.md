gnuplot C interface library
===========================

Overview
--------

The `gnuplot_i` interface library enables developers to create [gnuplots](http://www.gnuplot.info/) directly from their C programs.

The program works by creating a UNIX pipe through which gnuplot commands are sent and then executed. 

The central data structure is the gnuplot control handle, which holds the gnuplot commands as well as technical internal information, such as terminal type, amount of open windows and such. 

The plot can be displayed in its own window or otherwise saved as an image file to disk.

Example of a minimal program structure:

    #include "gnuplot_i.h"

    gnuplot_ctrl *handle = gnuplot_init();
    gnuplot_setterm (handle, "wxt", 600, 400);
    gnuplot_plot_equation (handle, "sin(x)", "Sine wave");
    gnuplot_close (handle);


Provenance
----------

This program was originally developed by Nicolas Devillard (2000) who also placed it in the public domain. 
Other authors have contributed to this library:
* Peter Maresh (2010): compile and run on MS-Windows 7/64 using mingw64.
* Robert Bradley (2004-2006): functional enhancements, see next section.
* longradix (2023): refactoring, error handling, stylistic improvements, documentation updates.


Enhancements
------------

This interface library features the following enhancements from the original program:

* 3D plots, using `gnuplot_splot (handle, x, y, z, n, "title")`.
* Setting z-axis labels with `gnuplot_set_axislabel (handle, "z-axis label", "z")`.
* Production of colour PostScript files with `gnuplot_hardcopy (handle, "graph.ps")`.
* Windows support.
* On OS X, if `DISPLAY` environment variable is not set or `USE_AQUA=1`, then aqua is used instead of x11.
* Plotting of complex structures through the use of callbacks, see `gnuplot_plot_obj_xy` and `gnuplot_splot_obj`.
* Contour plotting with `gnuplot_setstyle (handle, "lines")` and `gnuplot_contour_plot (handle, x, y, z, nx, ny, "title")`.

If you have any questions or comments, these can be sent to robert.bradley@merton.oxon.org, or via the [website](http://www.robert-bradley.co.uk).


Examples
--------

This library comes with the following examples:

* **example.c**: a garden variety of `gnuplot_i` function calls to demonstrate general usage and capabilities.
* **animation.c**: a brief animation of a run-time generated sine wave.
* **sinepng.c**: a demonstration of how `gnuplot_i` can be used to store its output as a file.

Compilation instructions are included in each of these examples.


Documentation
-------------

A tutorial is available in `tutorial.md`.

Documentation of macros, includes, functions and prototypes can be straightforwardly generated using [doxygen](https://www.doxygen.nl) and/or the [doxywizard](https://www.doxygen.nl/manual/doxywizard_usage.html). A Doxyfile is provided for this purpose.


Licensing
---------

This library has been licensed under the GPL, same as all other GNU software, and is therefore less strict than the [gnuplot license](https://spdx.org/licenses/gnuplot.html) itself. 
