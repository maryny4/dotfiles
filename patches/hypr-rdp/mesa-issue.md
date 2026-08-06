# Черновик issue для gitlab.freedesktop.org/mesa/mesa (подать: New Issue → вставить)

**Title:** radeonsi: segfault in vaEndPicture when VAEncMiscParameterHRD has buffer_size = 0 (H.264 encode, CQP)

**Body (вставить как есть):**

---

## Description

During H.264 encoding with `VA_RC_CQP`, submitting a `VAEncMiscParameterHRD` buffer with
`buffer_size = 0` and `initial_buffer_fullness = 0` makes the driver segfault inside
`vaEndPicture` instead of returning an error. An application that (incorrectly but
harmlessly) derives HRD parameters from its target bitrate — which is naturally 0 in
CQP mode — crashes on every encoded frame.

A driver should reject invalid parameter buffers with a VA_STATUS error; a segfault
takes the whole client process down (in our case an RDP server in a systemd restart
loop).

## Environment

- GPU: AMD Ryzen 9 9900X3D iGPU (Raphael, `radeonsi, raphael_mendocino, ACO`)
- Mesa: 26.1.6-arch1.1 (Arch Linux), libva 2.22
- Kernel: 7.1.5-arch1-2

## Reproduction

Buffer sequence per IDR frame (all on one context, H264High / VAEntrypointEncSlice,
config attrib VA_RC_CQP):

1. `VAEncSequenceParameterBufferType`
2. `VAEncMiscParameterBufferType(VAEncMiscParameterTypeRateControl)` — bits_per_second=0, initial/min/max_qp=20
3. `VAEncMiscParameterBufferType(VAEncMiscParameterTypeHRD)` — **buffer_size=0, initial_buffer_fullness=0** ← trigger
4. `VAEncMiscParameterBufferType(VAEncMiscParameterTypeFrameRate)` — framerate=30
5. packed sequence header, `VAEncPictureParameterBufferType`, `VAEncSliceParameterBufferType`, packed slice header
6. `vaRenderPicture` + `vaEndPicture` → **SIGSEGV**

Bisected: removing only buffer (3) makes encoding work and produce a valid stream;
rate-control and frame-rate buffers are innocent in every combination. ffmpeg's
`h264_vaapi` does not hit this because it never submits HRD parameters without a
target bitrate.

Self-contained reproducer (Rust, ~30 lines of driver-facing calls): the ignored test
`vaapi_encode_probe_cqp_writes_stream_to_disk` in
https://github.com/MuNeNICK/hypr-rdp/pull/30 — run with the HRD skip reverted to
reproduce, as-is to see the working sequence.

## Stack trace

```
#0  0x00007f2f6a8cc0b0 in ?? () from /usr/lib/libgallium-26.1.6-arch1.1.so  (libgallium + 0xcc0b0)
#1  0x00007f2ffd40714c in vaEndPicture () from /usr/lib/libva.so.2
#2..#10 application frames (Rust RDP server)
```

(coredump available; debuginfod did not resolve the gallium frame on this host —
happy to re-run with a debug build or provide the core on request)

## Expected

`vaRenderPicture`/`vaEndPicture` return `VA_STATUS_ERROR_INVALID_PARAMETER` (or the
HRD buffer with zero size is ignored), the client process survives.

---
