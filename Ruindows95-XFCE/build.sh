#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$(realpath "$0")")"
[[ $EUID == 0 ]] || { echo 'Execute sudo bash build.sh'; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo 'Requer host x86_64.'; exit 1; }
[[ -d /usr/share/archiso/configs/releng ]] || { echo 'Instale archiso no Arch Linux primeiro.'; exit 1; }
# Validate locally prepared sounds before downloading or allocating build space.
python3 verificar-sons.py sons
# Fresh work directory avoids stale images and accidental deletion.
mkdir -p builds out
work=$(mktemp -d "$PWD/builds/build.XXXXXXXX")
cp -a /usr/share/archiso/configs/releng "$work/profile"
p="$work/profile"
# Fetch upstream theme during ISO construction, never during installation.
chicago="$work/Chicago95"
mkdir -p "$chicago"
curl --fail --location --retry 3 https://codeload.github.com/grassmunk/Chicago95/tar.gz/refs/heads/master -o "$work/chicago95.tar.gz"
tar -xzf "$work/chicago95.tar.gz" -C "$chicago" --strip-components=1
cp -a overlay/. "$p/airootfs/"
for sound in startup usb; do
  install -Dm644 "sons/$sound.wav" "$p/airootfs/usr/share/ruindows95/sounds/$sound.wav"
done
python3 configure-splash.py live "$p"
# Prepare a separate, clean installed system. Never clone the live account.
for cmd in pacstrap xz tar sha256sum arch-chroot mount umount; do
  command -v "$cmd" >/dev/null || { echo "Dependência ausente: $cmd"; exit 1; }
done
root="$work/installed-root"
mkdir -p "$root"
mapfile -t installed_pkgs < packages.txt
# Official repositories only, including multilib for Steam; leave host unchanged.
conf="$work/pacman.conf"
cat > "$conf" <<'PACCONF'
[options]
Architecture = auto
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
PACCONF
mapfile -t store_pkgs < packages-store.txt
pacstrap -C "$conf" -K "$root" "${installed_pkgs[@]}" "${store_pkgs[@]}"
install -m644 "$conf" "$root/etc/pacman.conf"
# Install the session sound daemon and both local WAV files into the offline target.
for f in usr/local/bin/ruindows-sounds etc/xdg/autostart/ruindows-sounds.desktop; do
  install -D -m "$(stat -c %a "overlay/$f")" "overlay/$f" "$root/$f"
done
for sound in startup usb; do
  install -Dm644 "sons/$sound.wav" "$root/usr/share/ruindows95/sounds/$sound.wav"
done
arch-chroot "$root" python -c 'import pyudev'
arch-chroot "$root" sh -c 'command -v pw-play && command -v wpctl'
# Confirm the offline target has the LTS kernel, not the regular kernel.
arch-chroot "$root" pacman -Q linux-lts
# Verify all requested utilities and their explicit support packages.
arch-chroot "$root" pacman -Q galculator ristretto vlc vlc-plugins-extra gnome-disk-utility system-config-printer cups cups-pk-helper htop
if arch-chroot "$root" pacman -Q linux >/dev/null 2>&1; then
  echo 'Erro: kernel normal instalado no sistema offline.'; exit 1
fi
test -s "$root/boot/vmlinuz-linux-lts"
test -s "$root/etc/mkinitcpio.d/linux-lts.preset"
# Configure the installed system separately from the live Archiso hooks.
cp -a overlay/usr/share/plymouth/themes/ruindows95 "$root/usr/share/plymouth/themes/"
install -Dm644 overlay/etc/plymouth/plymouthd.conf "$root/etc/plymouth/plymouthd.conf"
python3 configure-splash.py installed "$root"
# The installer regenerates the initramfs after choosing the keyboard.
printf 'KEYMAP=us\n' > "$root/etc/vconsole.conf"

# Install the upstream Python wheel, not an AUR recipe. No Go or makepkg.
# The target directory does not modify system Python's package database.
install -Dm644 bauh-requirements.txt "$root/root/ruindows-bauh-requirements.txt"
# Keep temporary mount local to this subshell and clean it even on failure.
(
  mount --bind "$root" "$root"
  trap 'umount "$root"' EXIT
  arch-chroot "$root" python -m pip install --no-cache-dir --no-deps --only-binary=:all: --require-hashes --target /opt/ruindows-bauh -r /root/ruindows-bauh-requirements.txt
)
python3 patch-bauh.py "$root/opt/ruindows-bauh"
rm -f "$root/root/ruindows-bauh-requirements.txt"
for f in etc/skel/.config/bauh/config.yml etc/skel/.config/bauh/arch.yml etc/bauh/gems.forbidden usr/local/bin/bauh usr/share/applications/ruindows-software-center.desktop; do
  install -D -m "$(stat -c %a "overlay/$f")" "overlay/$f" "$root/$f"
done
arch-chroot "$root" env PYTHONPATH=/opt/ruindows-bauh python -c 'import bauh.app; from bauh.manage import new_manage_panel; from bauh.view.core import gems; from PyQt5 import QtWidgets; import yaml, dateutil, packaging, requests, colorama'
for f in usr/local/bin/ruindows-drivers usr/local/bin/ruindows-nvidia usr/share/applications/ruindows-drivers.desktop usr/share/applications/ruindows-nvidia.desktop; do
  install -D -m "$(stat -c %a "overlay/$f")" "overlay/$f" "$root/$f"
done
# NVIDIA installation is only available in the installed system.
rm -f "$p/airootfs/usr/local/bin/ruindows-nvidia" "$p/airootfs/usr/share/applications/ruindows-nvidia.desktop"
arch-chroot "$root" pacman -Q steam flatpak fuse2 bluez blueman vulkan-nouveau lib32-vulkan-nouveau
(
  mount --bind "$root" "$root"
  trap 'umount "$root"' EXIT
  arch-chroot "$root" flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  arch-chroot "$root" flatpak remotes --system --columns=name | grep -Fx flathub
)
# Store and Steam are installed in the offline target, not duplicated in the live system.
rm -f "$p/airootfs/usr/local/bin/bauh" "$p/airootfs/usr/share/applications/ruindows-software-center.desktop"
rm -rf "$p/airootfs/etc/skel/.config/bauh" "$p/airootfs/etc/bauh"
# Install Fastfetch defaults for every future account (including live).
for dest in "$root" "$p/airootfs"; do
  install -d "$dest/etc/skel/.config/fastfetch"
  install -m 644 overlay/etc/skel/.config/fastfetch/config.jsonc "$dest/etc/skel/.config/fastfetch/"
  install -D -m 644 overlay/etc/skel/.config/fastfetch/images/logo.png "$dest/etc/skel/.config/fastfetch/images/logo.png"
  touch "$dest/etc/skel/.bashrc"
  cat overlay/etc/skel/ruindows-fastfetch.bash >> "$dest/etc/skel/.bashrc"
  rm -f "$dest/etc/skel/ruindows-fastfetch.bash"
done
for dest in "$root" "$p/airootfs"; do
  install -d "$dest/usr/share/themes" "$dest/usr/share/icons" "$dest/usr/share/ruindows-appearance"
  cp -a "$chicago/Theme/Chicago95" "$dest/usr/share/themes/"
  cp -a "$chicago/Icons/." "$dest/usr/share/icons/"
  test -d "$dest/usr/share/icons/Chicago95"
  install -m 644 "$chicago/Extras/Chicago95_Panel_Preferences.tar.bz2" "$dest/usr/share/ruindows-appearance/panel.tar.bz2"
  install -m 644 "$chicago/CREDITS" "$dest/usr/share/ruindows-appearance/CREDITS"
  for f in usr/share/backgrounds/ruindows95/wallpaper.png usr/share/ruindows95/fastfetch-logo.png usr/local/bin/ruindows-wallpaper etc/xdg/autostart/ruindows-wallpaper.desktop etc/lightdm/lightdm-gtk-greeter.conf.d/50-ruindows.conf; do
    install -D -m "$(stat -c %a "overlay/$f")" "overlay/$f" "$dest/$f"
  done
  chmod 755 "$dest/usr/local/bin/ruindows-wallpaper"
done
# Remove build-specific state. The installed machine gets its own identity/keyring.
rm -rf "$root/etc/pacman.d/gnupg"
rm -f "$root/etc/machine-id" "$root/var/lib/dbus/machine-id" "$root/var/lib/systemd/random-seed" "$root/etc/resolv.conf"
touch "$root/etc/machine-id" "$root/etc/resolv.conf"
find "$root/var/cache/pacman/pkg" -mindepth 1 -maxdepth 1 -type f -delete
payload="$p/airootfs/usr/share/ruindows95"
mkdir -p "$payload"
# The installer rebuilds both LTS initramfs images with mkinitcpio -P.
# Avoid shipping the build host's redundant, pre-generated initramfs files.
rm -f "$root/boot/initramfs-linux-lts.img" "$root/boot/initramfs-linux-lts-fallback.img"
# Bounded compression concurrency for older build machines (override: 1-8).
threads=${RUINDOWS_COMPRESSION_THREADS:-2}
[[ $threads =~ ^[1-8]$ ]] || { echo 'RUINDOWS_COMPRESSION_THREADS deve estar entre 1 e 8.'; exit 1; }
# XZ with a bounded memory budget; keep all ownership, ACLs and capabilities in tar.
tar --one-file-system --numeric-owner --acls --xattrs --xattrs-include='*' -C "$root" -cpf - . | xz -6e -T"$threads" --memlimit-compress=2GiB -c > "$payload/system.tar.xz"
xz -t "$payload/system.tar.xz"
(cd "$payload" && sha256sum system.tar.xz > system.sha256)
printf 'Tamanho da raiz offline compactada: '; du -h "$payload/system.tar.xz"
# These tools are needed only in the live installer.
printf '%s\n' arch-install-scripts gptfdisk parted xz zstd >> "$p/packages.x86_64"
# Keep the official Archiso live kernel and its matching boot paths.
# Keep all packages in the installed system, but avoid repeating desktop apps
# in the default live environment. Full live mode is optional.
bash select-live-packages.sh packages.txt > "$work/live-desktop-packages.txt"
cat "$work/live-desktop-packages.txt" >> "$p/packages.x86_64"
sort -u -o "$p/packages.x86_64" "$p/packages.x86_64"
sed -i '/^virtualbox-guest-utils\(-nox\)\?$/d' "$p/packages.x86_64"
# Preserve official BIOS and UEFI boot modes and ISO label handling.
cat >> "$p/profiledef.sh" <<'PROFILE'
iso_name="ruindows95-xfce-offline"
iso_label="RUINDOWS95"
iso_publisher="Ruindows95 community remaster"
iso_application="Ruindows95 XFCE Live"
# Strong compression for live files; standard SquashFS supported by Archiso.
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions["/usr/local/bin/ruindows-sounds"]="0:0:755"
file_permissions["/usr/local/bin/ruindows-drivers"]="0:0:755"
file_permissions["/usr/local/bin/ruindows-install-autostart"]="0:0:755"
file_permissions["/usr/local/bin/ruindows-install"]="0:0:755"
file_permissions["/usr/local/bin/ruindows-wallpaper"]="0:0:755"
file_permissions["/usr/local/bin/ruindows-live-setup"]="0:0:755"
file_permissions["/etc/sudoers.d/90-ruindows-live"]="0:0:440"
PROFILE
s="$p/airootfs/etc/systemd/system"
mkdir -p "$s/graphical.target.wants" "$s/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/graphical.target "$s/default.target"
ln -sfn /usr/lib/systemd/system/lightdm.service "$s/display-manager.service"
ln -sfn ../ruindows-live-setup.service "$s/graphical.target.wants/ruindows-live-setup.service"
ln -sfn /usr/lib/systemd/system/NetworkManager.service "$s/multi-user.target.wants/NetworkManager.service"
# Avoid competing network managers from the official live profile.
find "$s" -type l \( -name 'systemd-networkd.service' -o -name 'iwd.service' -o -name 'dhcpcd.service' -o -name 'systemd-networkd-wait-online.service' \) -delete
# Replace only human-readable boot labels, not identifiers or boot parameters.
for d in syslinux grub efiboot; do
  [[ -d "$p/$d" ]] || continue
  find "$p/$d" -type f \( -name '*.cfg' -o -name '*.conf' \) -exec sed -i 's/Arch Linux install medium/Install Ruindows95/g;s/Arch Linux installation medium/Install Ruindows95/g' {} +
done
# Limit SquashFS worker count as well (profile is a local generated copy).
printf "airootfs_image_tool_options+=('-processors' '%s')\n" "$threads" >> "$p/profiledef.sh"
mkarchiso -v -w "$work/work" -o "$PWD/out" "$p"
ls -lh "$PWD/out/"*.iso
for iso in "$PWD/out/"*.iso; do
  bytes=$(stat -c %s "$iso")
  printf '%s: %s bytes\n' "$(basename "$iso")" "$bytes"
  if ((bytes > 3000000000)); then
    echo 'Acima da meta de 3 GB (decimal); ISO preservada, nenhum pacote instalado removido.'
  fi
done
printf 'Diretório de trabalho: %s\n' "$work"
