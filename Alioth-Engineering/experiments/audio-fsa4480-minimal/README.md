# FSA4480 Single-Point Candidate

## Purpose

This directory stages the first low-risk audio-adjacent candidate for alioth:

- `ACPI\FSA04480`
- matched by `fsa4480.inf`

It is **not** the full internal-audio fix.

It is only a narrow Type-C analog audio switch candidate that may be relevant to later audio routing experiments.

## Why This Candidate Is Different

- exact hardware ID match exists in current diagnostics
- exact INF exists locally
- not part of the previously dangerous broad Kona platform injection path
- not under `Drivers\SOC`
- not under `Drivers\USBFn`

## Current Status

Prepared only.

- not injected
- not imported into the current Windows image
- safe to inspect

## Source

Original source path:

- `sound_code\windows_xiaomi_platforms_full\components\ANYSOC\Hardware\HARDWARE.USB.FSA4480`

## Files

- `fsa4480.inf`
- `fsa4480.sys`
- `fsa4480.cat`

## Candidate Hardware ID

- `ACPI\FSA04480`

## Risk

Low relative risk compared with the broad Kona injections that previously broke boot.

Still, this candidate should only be tested after:

1. preserving the current working baseline
2. documenting rollback
3. explicitly deciding to perform the experiment

## Not Covered

This candidate does **not** prove:

- speakers will work
- microphone will work
- Kona Audio stack is ready

It is only the first exact-match single-point candidate.
