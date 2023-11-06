# spsc_queue

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/maolonglong/spsc_queue/zig.yml?label=ci)](https://github.com/maolonglong/spsc_queue/actions/workflows/zig.yml)
[![Codecov](https://img.shields.io/codecov/c/github/maolonglong/spsc_queue/main?logo=codecov)](https://codecov.io/gh/maolonglong/spsc_queue)

Zig port of boost's `spsc_queue`.

> A wait-free ring buffer provides a mechanism for relaying objects from one single "producer" thread to one single "consumer" thread without any locks. The operations on this data structure are "wait-free" which means that each operation finishes within a constant number of steps. This makes this data structure suitable for use in hard real-time systems or for communication with interrupt/signal handlers.
