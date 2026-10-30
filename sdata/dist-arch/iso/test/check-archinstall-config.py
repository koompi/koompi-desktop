#!/usr/bin/env python3
"""Loads koompi-install's archinstall config through archinstall's own code.

A dev tool, not part of tests/run.sh: it needs archinstall (4.5) and its Python
dependencies (pydantic, pyparted, textual) unpacked somewhere, e.g. from Arch's
packages with `pacman -Sp archinstall python-pyparted python-pydantic python-textual`
and bsdtar. Make the config with `koompi-install --answers A --dry-run DIR`, then

  python3 -I check-archinstall-config.py --site SITE_PACKAGES [--site ...] \
      --firmware uefi|bios --disk-bytes N DIR/config.json DIR/creds.json

with the same firmware and disk size the dry run had. It runs as an ordinary user
and never opens a disk: a sparse image file stands in for the one the config
names, and every archinstall call that would reach hardware is stubbed (device
probing, lsblk, udev, losetup, wipefs, the wipe). What it proves:

1. archinstall's ArchConfigHandler reads CONFIG + CREDS the way
   `archinstall --config --creds --silent` does, and keeps the disk (it silently
   drops a device it cannot find, and encryption without a password)
2. the parsed disk layout serialises back to the same JSON: nothing ignored
3. it equals archinstall's own suggest_single_disk_layout() for the same disk
   (btrfs, default subvolumes, compression), obj_ids aside
4. encryption, the account, hostname, timezone, locale, GRUB and the KOOMPI
   profile parse as meant; archinstall's bootloader-layout check passes
5. archinstall's _setup_partition() lays the partitions onto the image through
   libparted, and they read back where the config put them

Not proven here: mkfs, LUKS, mounting, pacstrap, GRUB itself, firstboot. The QEMU
install test covers those.
"""

import argparse
import asyncio
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROFILE = HERE.parent / 'koompi/airootfs/usr/share/koompi/archinstall/koompi_hyprland.py'
MiB = 1024**2
GiB = 1024**3

failures = 0


def check(ok: bool, what: str) -> None:
	global failures
	print(f'{"PASS" if ok else "FAIL"} {what}')
	if not ok:
		failures += 1


def no_ids(mod: dict) -> dict:
	mod = json.loads(json.dumps(mod))
	for i, part in enumerate(mod['partitions']):
		part['obj_id'] = i
	return mod


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument('--site', action='append', required=True, help='a site-packages dir with archinstall or its dependencies')
	ap.add_argument('--firmware', choices=['uefi', 'bios'], required=True)
	ap.add_argument('--disk-bytes', type=int, required=True)
	ap.add_argument('config', type=Path)
	ap.add_argument('creds', type=Path)
	args = ap.parse_args()

	if os.geteuid() == 0:
		sys.exit('run this as an ordinary user: it must not be able to open a real disk')

	uefi = args.firmware == 'uefi'
	sys.dont_write_bytecode = True  # no __pycache__ next to the repo's profile
	sys.path[:0] = args.site
	sys.modules['systemd'] = None  # type: ignore[assignment]  # archinstall would log to the journal
	tmp = Path(tempfile.mkdtemp(prefix='koompi-aicheck.'))

	try:
		return run(args, uefi, tmp)
	finally:
		shutil.rmtree(tmp, ignore_errors=True)


def run(args: argparse.Namespace, uefi: bool, tmp: Path) -> int:
	# --- stubs, before device_handler is imported: it probes every disk on import
	import parted

	parted.getAllDevices = lambda: []

	from archinstall.lib import command, log
	from archinstall.lib.disk import utils as disk_utils
	from archinstall.lib.hardware import SysInfo

	log.logger.path = tmp
	SysInfo.has_uefi = staticmethod(lambda: uefi)
	disk_utils.udev_sync = lambda: None
	disk_utils.get_all_lsblk_info = lambda: []

	class NoCommand:
		"""losetup -a and wipefs: nothing runs."""

		def __init__(self, cmd, *_a, **_k) -> None:
			print(f'  (not run: {cmd})')

		def __str__(self) -> str:
			return ''

	command.SysCommand = NoCommand  # type: ignore[misc]

	assert 'archinstall.lib.disk.device_handler' not in sys.modules
	from archinstall.lib.disk import device_handler as dh_module

	from archinstall.lib.args import ArchConfigHandler
	from archinstall.lib.bootloader.utils import validate_bootloader_layout
	from archinstall.lib.disk import default_layouts
	from archinstall.lib.models.bootloader import Bootloader
	from archinstall.lib.models.device import (
		BDevice,
		DiskLayoutType,
		EncryptionType,
		FilesystemType,
		PartitionGUID,
		PartitionTable,
		_DeviceInfo,
	)
	from archinstall.tui.menu_item import MenuItem

	dh = dh_module.device_handler

	def no_wipe(path: Path) -> None:
		raise RuntimeError(f'the checker must not wipe {path}')

	dh._wipe = no_wipe  # type: ignore[method-assign]

	# --- the image that stands in for the config's disk
	config = json.loads(args.config.read_text())
	device = Path(config['disk_config']['device_modifications'][0]['device'])
	image = tmp / 'disk.img'
	with image.open('wb') as f:
		f.truncate(args.disk_bytes)
	table = PartitionTable.GPT if uefi else PartitionTable.MBR
	pdev = parted.getDevice(str(image))
	info = _DeviceInfo.from_disk(parted.freshDisk(pdev, table.value))
	info.path = device
	bdev = BDevice(parted.freshDisk(pdev, table.value), info, [])
	dh._devices = {device: bdev}
	dh._partition_table = table

	# the profile path names the ISO's copy; the repo's is the same file
	config['profile_config']['profile']['path'] = str(PROFILE)
	config_path = tmp / 'config.json'
	config_path.write_text(json.dumps(config))

	# --- 1. archinstall's own reading of --config and --creds
	sys.argv = ['archinstall', '--config', str(config_path), '--creds', str(args.creds), '--silent', '--dry-run', '--skip-wifi-check']
	try:
		cfg = ArchConfigHandler().config
	except SystemExit as err:
		check(False, f'archinstall refused the config (exit {err.code})')
		return 1

	dc = cfg.disk_config
	check(dc is not None and dc.config_type == DiskLayoutType.Default, 'disk_config is a default_layout')
	if dc is None:
		return 1
	check(len(dc.device_modifications) == 1, f'archinstall found the disk {device}')
	if len(dc.device_modifications) != 1:
		return 1
	mod = dc.device_modifications[0]
	check(mod.wipe and mod.device_path == device, f'the whole of {device} is wiped')

	# --- 2. nothing dropped
	src = config['disk_config']
	check(dc.json() == src, 'the parsed layout serialises back to the same JSON')

	# --- 3. the same as archinstall's own suggestion (its menu, answered yes / compress)
	class Yes:
		def __init__(self, *_a, **_k) -> None:
			pass

		async def show(self) -> 'Yes':
			return self

		def item(self) -> MenuItem:
			return MenuItem.yes()

	async def compress() -> list[str]:
		return ['compress=zstd']

	default_layouts.Confirmation = Yes  # type: ignore[misc,assignment]
	default_layouts.select_mount_options = compress  # type: ignore[assignment]
	suggested = asyncio.run(default_layouts.suggest_single_disk_layout(bdev, FilesystemType.BTRFS))
	same = no_ids(suggested.json()) == no_ids(src['device_modifications'][0])
	check(same, "the layout equals archinstall's suggest_single_disk_layout() for this disk")
	if not same:
		print(json.dumps(no_ids(suggested.json()), indent=1))

	# --- 4. the rest of the config
	parts = mod.partitions
	boot, root = parts[0], parts[1]
	want_flags = ['boot', 'esp'] if uefi else ['boot']
	check([f.description for f in boot.flags] == want_flags and boot.fs_type == FilesystemType.FAT32, f'/boot is FAT32 with {want_flags}')
	check(
		[(str(s.name), str(s.mountpoint)) for s in root.btrfs_subvols]
		== [('@', '/'), ('@home', '/home'), ('@log', '/var/log'), ('@pkg', '/var/cache/pacman/pkg')]
		and root.mount_options == ['compress=zstd'],
		'root is btrfs @ @home @log @pkg, compress=zstd',
	)
	# not checked: has_default_btrfs_vols() is False for any config read from a file
	# (parse_args keeps the name a str, is_default_root() compares it with Path('@')).
	# It only gates btrfs_options (snapshots), which KOOMPI does not set.

	enc = dc.disk_encryption
	if 'disk_encryption' in src:
		ok = enc is not None and enc.encryption_type == EncryptionType.LUKS and enc.partitions == [root] and bool(enc.encryption_password)
		check(ok, 'LUKS on the root partition, with a passphrase')
	else:
		check(enc is None, 'no encryption')

	auth = cfg.auth_config
	users = auth.users if auth else []
	creds = json.loads(args.creds.read_text())
	check(
		len(users) == 1 and users[0].username == creds['users'][0]['username'] and users[0].sudo and (users[0].password.enc_password or '').startswith('$y$'),
		'one sudo account, password hashed with yescrypt',
	)
	check(auth is None or auth.root_enc_password is None, 'no root password')
	check(cfg.hostname == config['hostname'] and cfg.timezone == config['timezone'], 'hostname and timezone')
	loc = cfg.locale_config
	want = config['locale_config']
	check(loc is not None and (loc.kb_layout, loc.sys_lang, loc.sys_enc) == (want['kb_layout'], want['sys_lang'], want['sys_enc']), 'keyboard and locale')
	bl = cfg.bootloader_config
	check(bl is not None and bl.bootloader == Bootloader.Grub and bl.removable, 'GRUB, removable')
	check(validate_bootloader_layout(bl, dc) is None, "archinstall's bootloader-layout check passes")
	prof = cfg.profile_config
	names = [p.name for p in prof.profile.current_selection] if prof and prof.profile else []
	check(bool(prof and prof.profile and prof.profile.name == 'Desktop' and 'KOOMPI Hyprland' in names), 'Desktop / KOOMPI Hyprland profile loads')

	# --- 5. libparted lays it onto the image, as archinstall's partition() does minus the wipe
	pdisk = parted.freshDisk(pdev, table.value)
	for part in parts:
		dh._setup_partition(part, bdev, pdisk, requires_delete=False, arch='x86_64')
	pdisk.commit()

	back = parted.newDisk(parted.getDevice(str(image)))
	sector = pdev.sectorSize
	got = [(p.number, p.geometry.start * sector, p.geometry.length * sector, p.getFlagsAsString()) for p in back.partitions]
	for row in got:
		print(f'  partition {row[0]}: start {row[1]} B, length {row[2]} B, flags [{row[3]}]')
	want_rows = [
		(1, MiB, GiB),
		(2, MiB + GiB, root.length.convert(root.length.unit)._normalize()),
	]
	check(back.type == table.value and [r[:3] for r in got] == want_rows, f'libparted wrote a {table.value} table with both partitions where the config put them')
	check(set(want_flags) <= set(got[0][3].split(', ')) if got else False, '/boot carries its flags on disk')
	if uefi and len(back.partitions) == 2:
		check(back.partitions[1].type_uuid == PartitionGUID.LINUX_ROOT_X86_64.bytes, 'root has the x86-64 root partition type')
	if shutil.which('sfdisk'):
		print(subprocess.run(['sfdisk', '-d', str(image)], capture_output=True, text=True).stdout.rstrip())

	print('PASS: archinstall reads the config' if failures == 0 else f'FAIL: {failures} check(s)')
	return 1 if failures else 0


if __name__ == '__main__':
	sys.exit(main())
