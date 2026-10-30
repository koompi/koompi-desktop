# The KOOMPI Hyprland profile for archinstall, loaded from config.json's
# profile_config.path. It installs only what the first boot needs to fetch and run
# the desktop's own installer; ./setup install brings everything else, as it does
# for the one-line installer, so an ISO install and a curl install end up the same
# machine and update the same way.
from pathlib import Path
import os
import shutil
from typing import TYPE_CHECKING, override

from archinstall.default_profiles.profile import DisplayServerType, GreeterType, Profile, ProfileType
from archinstall.lib.log import info

if TYPE_CHECKING:
	from archinstall.lib.installer import Installer
	from archinstall.lib.models.users import User

FIRSTBOOT = Path('/usr/share/koompi/firstboot')


class KoompiHyprlandProfile(Profile):
	def __init__(self) -> None:
		super().__init__(
			'KOOMPI Hyprland',
			ProfileType.DesktopEnv,
			support_gfx_driver=True,
			display_server=DisplayServerType.Wayland,
		)

	@property
	@override
	def packages(self) -> list[str]:
		return [
			'hyprland',
			'xdg-desktop-portal-hyprland',
			'qt6-wayland',
			'git',
			'base-devel',
			'sudo',
			'curl',
			'rsync',
			'xdg-user-dirs',
			'amd-ucode',
			'intel-ucode',
			'sof-firmware',
		]

	@property
	@override
	def default_greeter_type(self) -> GreeterType:
		return GreeterType.Sddm

	@override
	def provision(self, install_session: 'Installer', users: list['User']) -> None:
		# The desktop goes on the first account with sudo: ./setup install runs as the
		# user and asks sudo for the system half.
		user = next((u for u in users if u.sudo), users[0] if users else None)
		if user is None:
			info('KOOMPI: no user account, so no desktop to set up on first boot')
			return

		target = Path(install_session.target)
		lib = target / 'usr/local/lib/koompi'
		lib.mkdir(parents=True, exist_ok=True)
		shutil.copy2(FIRSTBOOT / 'firstboot', lib / 'firstboot')
		os.chmod(lib / 'firstboot', 0o755)
		shutil.copy2(FIRSTBOOT / 'koompi-firstboot.service', target / 'etc/systemd/system/koompi-firstboot.service')

		conf = target / 'etc/koompi'
		conf.mkdir(parents=True, exist_ok=True)
		ref = os.environ.get('KOOMPI_REF', 'main')
		repo = os.environ.get('KOOMPI_REPO', 'https://github.com/koompi/koompi-desktop.git')
		(conf / 'firstboot.conf').write_text(f'KOOMPI_USER={user.username}\nKOOMPI_REF={ref}\nKOOMPI_REPO={repo}\n')

		# Wi-Fi joined in the live session, so the first boot is online without asking again
		connections = Path('/etc/NetworkManager/system-connections')
		if connections.is_dir():
			dest = target / 'etc/NetworkManager/system-connections'
			dest.mkdir(parents=True, exist_ok=True)
			for item in connections.iterdir():
				shutil.copy2(item, dest / item.name)
				os.chmod(dest / item.name, 0o600)

		install_session.enable_service('koompi-firstboot.service')
		info(f'KOOMPI: the desktop is set up for {user.username} on first boot (from {repo} {ref})')
