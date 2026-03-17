# FLOPPINUX Auto Build

![Works - On My Machine](https://img.shields.io/badge/Works-On_My_Machine-2ea44f)
![Project Status - Feature Complete](https://img.shields.io/badge/Project_Status-Feature_Complete-2ea44f)
![100% AI Code](https://img.shields.io/badge/AI_Code-100%25-blue)

[FLOPPINUX v0.3.1](https://github.com/w84death/floppinux/blob/4362fb4c6d5621ae0cf3c09ecf086eff79316519/floppinux.md) Auto Build.

## Design

This project does NOT aim to be a 1:1 replication of the original FLOPPINUX project.

Goals:

- Fit a bootable Linux with userland inside a 1440 KiB drive (targeting 3½-inch floppy diskette)
- Hardware requirements: i486 CPU, 20MiB RAM
- 8250/16550 serial support (for headless machines and CI testing)
- CI/CD w/ GitHub Actions

## Usage

Console on COM1 and TTY2-4 (use Alt-Fn to switch TTY).

## Development Notes

Requirements:

- Bash
- Docker w/ Buildx, either root or rootless
- qemu-system-i386 for end-to-end testing

Building:

```shell
make all
```

Testing:

```shell
./test-boot.sh
```
