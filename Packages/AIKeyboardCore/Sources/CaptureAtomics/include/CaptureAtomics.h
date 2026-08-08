//
//  The four atomic operations a cross-process seqlock needs, in the one language
//  on this toolchain that has them.
//
//  Swift cannot express this. `Synchronization.Atomic` is iOS 18 and this package
//  deploys to iOS 17; `swift-atomics` is a third-party dependency this project
//  does not take; `<stdatomic.h>` does not import into Swift at all
//  (`atomic_thread_fence` is not in scope from `import Darwin`); and the
//  `OSAtomic` family that *is* visible from Swift has been deprecated since
//  iOS 10.0 with `<stdatomic.h>` named as its replacement
//  (`libkern/OSAtomicDeprecated.h:66-69`). A seqlock written with plain loads and
//  stores is not a seqlock: arm64 is weakly ordered, so without the fences below
//  a reader can observe the new sequence number and the old body, which is
//  exactly the torn read the sequence number exists to catch.
//
//  Layout, and both ends of the channel agree on it:
//
//      offset 0   uint32  sequence      even = settled, odd = a write in flight
//      offset 4   uint32  padding       keeps the body 8-byte aligned
//      offset 8   body    the page's fixed-layout struct
//
//  The page is the start of an `mmap` mapping, so it is page-aligned and the
//  cast to `_Atomic uint32_t *` is aligned by construction.
//

#ifndef CAPTURE_ATOMICS_H
#define CAPTURE_ATOMICS_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

/// Bytes reserved at the front of a shared page for the sequence number.
#define CAPTURE_SEQ_HEADER_BYTES 8

/// Opens a write. Publishes an odd sequence, so any reader that starts now knows
/// to retry, and returns the value the matching `capture_seq_end_write` needs.
///
/// Single writer by construction: the broadcast extension is the only process
/// that writes `status.bin` and the keyboard the only one that writes
/// `intent.bin`. Two writers on one page would need a lock, not a seqlock.
static inline uint32_t capture_seq_begin_write(void *page) {
    _Atomic uint32_t *sequence = (_Atomic uint32_t *)page;
    uint32_t opened = atomic_load_explicit(sequence, memory_order_relaxed) + 1u;
    atomic_store_explicit(sequence, opened, memory_order_relaxed);
    // Store-store: the odd sequence must be visible before the body changes, or
    // a reader sees a settled sequence over a body already being overwritten.
    atomic_thread_fence(memory_order_release);
    return opened;
}

/// Closes a write. The body stores are fenced before the even sequence, so a
/// reader that sees the new sequence sees the whole body that goes with it.
static inline void capture_seq_end_write(void *page, uint32_t opened) {
    _Atomic uint32_t *sequence = (_Atomic uint32_t *)page;
    atomic_thread_fence(memory_order_release);
    atomic_store_explicit(sequence, opened + 1u, memory_order_relaxed);
}

/// Opens a read. An odd return means a write is in flight and the caller must
/// retry without touching the body.
static inline uint32_t capture_seq_begin_read(const void *page) {
    const _Atomic uint32_t *sequence = (const _Atomic uint32_t *)page;
    uint32_t opened = atomic_load_explicit(sequence, memory_order_relaxed);
    atomic_thread_fence(memory_order_acquire);
    return opened;
}

/// True when the body read between `capture_seq_begin_read` and here was taken
/// from one settled write. False means a write started or finished underneath
/// the read and the bytes are not a snapshot of anything.
static inline bool capture_seq_read_valid(const void *page, uint32_t opened) {
    atomic_thread_fence(memory_order_acquire);
    const _Atomic uint32_t *sequence = (const _Atomic uint32_t *)page;
    uint32_t closed = atomic_load_explicit(sequence, memory_order_relaxed);
    return (opened & 1u) == 0u && closed == opened;
}

#endif /* CAPTURE_ATOMICS_H */
