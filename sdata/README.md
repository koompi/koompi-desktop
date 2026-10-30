# `sdata/` - setup data

Everything `./setup` reads.

```
lib/            shared bash: logging, run/confirm, manifest, distro detection
install/        the four install steps, plus uninstall
uv/             the Python requirements the shell's helper scripts import
dist-arch/      Arch recipes + the koompi-* PKGBUILDs + the ISO/repo scaffolds
deps-info.md    per-package notes on why each Arch dependency is there
```

KOOMPI Desktop installs on Arch Linux and Arch-based distributions only;
`lib/distro.sh` refuses anything else before a change is made. `dist-arch/`
holds two recipes, and the split matters:

- `install-deps.sh` - what the session cannot start without.
  Break it and the desktop does not come up.
- `install-apps.sh` - the programs KOOMPI has an opinion about, the set
  `variables.lua` is written around.
  Skip it and you keep whatever you already had.

`lib/arch.sh` exists only because both Arch recipes need `arch_install_paru`,
`arch_paru` and `arch_install_pkgbuild`, and neither can source the other: a recipe
does its work at the top level, so sourcing one to borrow a function would run it.

Install AUR packages with `arch_paru`, never a bare `paru -S`. It hands paru
`lib/paru-gpg`, the gpg that bounds a signing-key fetch, so a stalled keyserver
fails the step instead of hanging the install.

## Writing a recipe

Both recipes are **sourced** by `sdata/install/deps.sh` and `sdata/install/apps.sh`,
not executed, so they can use `run`, `step`, `info`, `warn`, `err`, `die`,
`have` and `confirm` from `lib/common.sh`, and can read `REPO_ROOT` and the
`OS_*` variables.

`install-apps.sh` has to work under `--only-apps`, which means the dependency
recipe never ran. Anything it needs from that file it must set up itself.

A recipe must be safe to run twice, and must leave the machine usable if it
gives up half way. `run` already offers retry/skip/abort on a failed command,
so prefer letting a command fail loudly over swallowing its error.

`dist-arch/` also holds the OS-image side of the repo (PKGBUILDs, the archiso
profile, the signed-repo scaffold). That is a separate product from `./setup`;
see [`dist-arch/iso/koompi/`](dist-arch/iso/koompi/) and
[`dist-arch/repo/`](dist-arch/repo/).
