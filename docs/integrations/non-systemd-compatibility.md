# Third-party integrations and the non-systemd rule

Audit date: 2026-10-14

## Non-negotiable compatibility rule

Ricelin must not infer the active init system from the distribution name. “Arch” does
not imply systemd, and “not Arch” does not imply a non-systemd init. Check the running
init and the facilities actually available in the session. Ricelin's own init/login
manager calls belong in `configs/hypr/scripts/ricelin-sys`; run
`tools/lint-init-calls.sh` and `sh tests/test_ricelin_sys.sh` for changes in this
area.

For third-party projects, distinguish between:
- **Ships a systemd unit**: not automatically fatal if the software supports a fully
  documented, tested direct-launch lifecycle with no unit dependency.
- **Requires systemd for required behavior**: reject from Ricelin's supported set.
- **Porting exception**: Illogical Impulse may be worked on in an isolated profile, but
  it is not considered compatible until its systemd-specific behavior is replaced and
  the integration passes the same checks.

Do not run upstream whole-desktop installers against a live Ricelin setup. A shell
profile is not a package manager; an application or Qt theme must not be represented
as a Quickshell style.

## Repository decisions

| Project | Actual integration class | Decision | Reason / conditions |
|---|---|---|---|
| [P3DROVFX/ii-p3drovfx](https://github.com/P3DROVFX/ii-p3drovfx) | Separate Quickshell shell profile | **Porting exception** | The setup command `install` installs end-4's base dotfiles first, then overlays the fork. The Hyprland startup code includes `systemctl --user` session-target/environment calls, despite the repository carrying Gentoo/OpenRC notes. Keep the profile isolated; replace those calls with Ricelin's session adapter before calling it compatible. |
| [rhythmcreative/hyprland](https://github.com/rhythmcreative/hyprland) | Complete desktop configuration | **Reject as-is** | The installer is aimed at Arch/NixOS, the tree includes systemd user units, and its NixOS path checks and uses the systemd user session. Do not run the installer or import the whole config. A component is only eligible after it is separated and independently audited. |
| [andreumassanet/impasto](https://github.com/andreumassanet/impasto) | Complete Arch desktop setup | **Reject as-is** | The documented installer is Arch-specific, installs packages, writes both home and system files, changes login/desktop behavior, and includes systemd-oriented session handling. Do not run `./setup install` on Ricelin. Treat screenshots and visual ideas as references only unless a component is independently portable. |
| [Bali10050/Darkly](https://github.com/Bali10050/Darkly) | Qt Widgets / KDE application style | **Eligible, optional** | It is not a Quickshell style and will not reskin Ricelin's QML. The upstream manual installer uses privileged installation and removes existing plugin paths; don't run it blindly. Prefer a suitable distro package or a reviewed build/install with a deliberate prefix and matching Qt/KF runtime. No systemd user service is required for the style itself. |
| [liixini/skwd-wall](https://github.com/liixini/skwd-wall) | Wallpaper app plus resident daemon | **Conditional; not supported yet** | The documented installation enables `skwd-walld.service` using `systemctl --user`. The v2 IPC client can spawn `skwd-walld` when its ordinary socket is unavailable, so a no-systemd path may be possible, but daemon lifetime, login persistence and cleanup must be tested without a unit before it is accepted. |
| [yappologistic/Sung](https://github.com/yappologistic/Sung) | Standalone music player / MPRIS application | **Eligible, optional** | The upstream install is per-user and does not require a systemd user service. It can be launched as an ordinary application and exposes media integration through MPRIS. Check the local Qt version first: upstream requests Qt 6.8+, C++20, CMake 3.24+, Ninja, Python, Node.js 20+ and FFmpeg. Integrate it as an app/media provider, not as a shell style. |

## Integration boundaries in Ricelin

Use separate types rather than one generic “theme” list:

- **Shell profile:** Quickshell entry/configuration, with its own directory and verified
  start/stop lifecycle.
- **Wallpaper engine:** application/daemon plus a session lifecycle adapter; no
  systemd-only persistence.
- **Media player:** desktop application with optional MPRIS controls.
- **Qt application style:** app-toolkit styling; independent of QML shell styling.

For each adopted integration record its executable/entry point, package prerequisites,
init/session assumptions, launch and stop commands, health check, cleanup behavior,
license, and whether it is tested on a non-systemd session. Optional components must
not become hard dependencies of the Ricelin shell.

## Pre-merge checklist

1. No distro-name heuristic decides whether systemd exists.
2. No newly added config directly calls `systemctl`, `systemd-inhibit`, `loginctl`,
   or `busctl`; route supported first-party operations through `ricelin-sys`.
3. The component starts and stops from the actual Hyprland session without a systemd
   unit and does not leave duplicate/orphaned background processes.
4. Missing optional binaries fail gracefully; installing the core Ricelin shell never
   requires them.
5. Run `tools/lint-init-calls.sh`, `sh tests/test_ricelin_sys.sh`, the relevant
   integration test, and a headless Quickshell check when QML is involved.
