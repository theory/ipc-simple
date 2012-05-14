IPC/Simple version 0.10
=======================

IPC::Simple provides a simple, object-oriented interface over
[IPC::Open3](https://metacpan.org/module/IPC::Open3) in order to abstract away
error handling. All errors simply trigger exceptions. This way, you can just
focus on reading and writing to the handles to your process.

Installation
------------

To install this module, type the following:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Copyright and License
---------------------

Copyright (c) 2012 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
