#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(realpath "$0")")"
bash -n build.sh
for f in overlay/usr/local/bin/ruindows-* overlay/etc/skel/ruindows-fastfetch.bash; do [[ $f == */ruindows-sounds ]] || bash -n "$f"; done
sh -n overlay/usr/local/bin/bauh
for pkg in steam flatpak fuse2 python-pip python-pyqt5 lib32-mesa; do grep -Fxq "$pkg" packages-store.txt; done
if grep -Ex 'yay|go|linux-zen|linux|lutris|gamemode|gamescope' packages*.txt; then exit 1; fi
grep -Fxq 'aur: false' overlay/etc/skel/.config/bauh/arch.yml
grep -Fxq 'repositories: true' overlay/etc/skel/.config/bauh/arch.yml
for repo in core extra multilib; do grep -Fxq "[$repo]" build.sh; done
grep -Fxq 'iso_label="RUINDOWS95"' build.sh
grep -Fq 'SigLevel = Required DatabaseOptional' build.sh
grep -Fq -- '--require-hashes' build.sh
for f in overlay/usr/share/backgrounds/ruindows95/wallpaper.png overlay/usr/share/ruindows95/fastfetch-logo.png overlay/etc/skel/.config/fastfetch/images/logo.png; do test -s "$f"; done
printf 'OK: sintaxe, lista de pacotes, configuração da loja, repositórios e arquivos.\n'

for pkg in bluez bluez-utils blueman pciutils usbutils alsa-utils mesa-utils; do grep -Fxq "$pkg" packages.txt; done
for pkg in vulkan-nouveau lib32-vulkan-nouveau vulkan-tools intel-media-driver libva-mesa-driver; do grep -Fxq "$pkg" packages-store.txt; done
for app in ruindows-drivers ruindows-nvidia; do test -x "overlay/usr/local/bin/$app"; grep -Fxq "Exec=$app" "overlay/usr/share/applications/$app.desktop"; done
printf 'OK: integração estática dos drivers.\n'
# Regression test for the exact legacy import pattern reported in the VM.
grep -Fxq python-colorama packages-store.txt
grep -Fq 'python3 patch-bauh.py' build.sh
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bauh/view/core"
cat > "$scratch/bauh/view/core/gems.py" <<'PY'
import pkgutil
def load(name):
    loader = pkgutil.find_loader(name)
    if loader:
        module = loader.load_module()
        return module
PY
python3 patch-bauh.py "$scratch"
python3 patch-bauh.py "$scratch"
python3 - "$scratch/bauh/view/core/gems.py" <<'PY'
import runpy, sys
assert runpy.run_path(sys.argv[1])['load']('json').__name__ == 'json'
PY
grep -Fxq 'Exec=/usr/local/bin/ruindows-install-autostart' overlay/etc/xdg/autostart/ruindows-install.desktop
grep -Fxq 'OnlyShowIn=XFCE;' overlay/etc/xdg/autostart/ruindows-install.desktop
test -x overlay/usr/local/bin/ruindows-install-autostart
# Outside live, the wrapper must exit without opening a terminal.
bash overlay/usr/local/bin/ruindows-install-autostart
printf 'OK: regressão de importação e proteção do autostart fora do live.\n'
# Verify theme assets and boot config transformations without modifying host.
grep -Fxq plymouth packages.txt
python3 - <<'PY'
import tempfile, pathlib, subprocess
p=pathlib.Path('overlay/usr/share/plymouth/themes/ruindows95')
assert len(list(p.glob('frame-*.png'))) == 36
assert all((p/f'frame-{i}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n') for i in range(36))
assert len({f.read_bytes() for f in p.glob('frame-*.png')}) == 36
with tempfile.TemporaryDirectory() as tmp:
    r=pathlib.Path(tmp); (r/'etc/default').mkdir(parents=True)
    (r/'etc/mkinitcpio.conf').write_text('HOOKS=(base systemd autodetect kms keyboard block filesystems fsck)\n')
    (r/'etc/default/grub').write_text('GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"\n')
    for _ in range(2): subprocess.run(['python3','configure-splash.py','installed',tmp],check=True)
    assert 'kms plymouth keyboard' in (r/'etc/mkinitcpio.conf').read_text()
    assert 'loglevel=3 quiet splash' in (r/'etc/default/grub').read_text()
    assert (r/'etc/default/grub').read_text().count('splash') == 1
    live=r/'airootfs/etc/mkinitcpio.conf.d'; live.mkdir(parents=True)
    (live/'archiso.conf').write_text('HOOKS=(base udev kms archiso block filesystems)\n')
    for folder, name, line in [('syslinux','archiso.cfg',' APPEND archisobasedir=arch'),('grub','grub.cfg',' linux /vmlinuz archisosearchuuid=123'),('efiboot','archiso.conf','options archisobasedir=arch')]:
        (r/folder).mkdir(); (r/folder/name).write_text(line+'\n')
    subprocess.run(['python3','configure-splash.py','live',tmp],check=True)
    assert 'kms plymouth archiso' in (live/'archiso.conf').read_text()
    for folder in ('syslinux','grub','efiboot'):
        assert 'quiet splash' in next((r/folder).iterdir()).read_text()
print('OK: 36 quadros distintos e configuração de boot BIOS/UEFI simulada.')
PY

# LTS regression: distinguish installed kernel from official live kernel.
grep -Fxq linux-lts packages.txt
cmp packages.txt overlay/usr/share/ruindows95/packages.txt
RUINDOWS_FULL_LIVE=0 bash select-live-packages.sh packages.txt > "$scratch/live-packages"
RUINDOWS_FULL_LIVE=1 bash select-live-packages.sh packages.txt > "$scratch/full-live-packages"
grep -Fxq linux "$scratch/live-packages"
if grep -Fxq linux-lts "$scratch/live-packages"; then exit 1; fi
grep -Fq 'linux-lts$/linux/' select-live-packages.sh
grep -Fq 'pacman -Q linux-lts' build.sh
grep -Fq 'initramfs-linux-lts.img' overlay/usr/local/bin/ruindows-install
grep -Fq 'nvidia-open-lts nvidia-utils' overlay/usr/local/bin/ruindows-nvidia
printf 'OK: LTS no sistema instalado, kernel oficial no live e NVIDIA LTS.\n'

# V10.6: visual branding only; keep all previous hardware modules and styling.
python3 - <<'PY'
import json
from pathlib import Path
c=json.loads(Path('overlay/etc/skel/.config/fastfetch/config.jsonc').read_text())
assert c['modules'][0] == {'type':'custom','key':'OS','format':'Ruindows95 V10.8.1 LTS x86_64'}
assert c['modules'][1:] == ['host','uptime','packages','display','cpu','cpucache','gpu','memory','swap','disk']
assert c['logo']['width']==35 and c['logo']['height']==18
assert c['display']['color']=={'keys':'#FF1493','title':'#FF1493'}
PY
printf 'OK: nome do OS no Fastfetch, demais módulos e aparência preservados.\n'

# Utilities stay in the installed system and optional full live mode.
for pkg in galculator ristretto vlc vlc-plugins-extra gnome-disk-utility system-config-printer cups cups-pk-helper htop; do
  test "$(grep -Fxc "$pkg" packages.txt)" = 1
  grep -Fxq "$pkg" "$scratch/full-live-packages"
done
cmp packages.txt overlay/usr/share/ruindows95/packages.txt
grep -Fq 'arch-chroot "$root" pacman -Q galculator ristretto vlc vlc-plugins-extra gnome-disk-utility system-config-printer cups cups-pk-helper htop' build.sh
grep -Fxq 'arch-chroot /mnt systemctl enable cups.socket' overlay/usr/local/bin/ruindows-install
printf 'OK: utilitários, suporte multimídia e ativação sob demanda do CUPS.\n'

# V10.7: simulated USB events and WAV validation without using real media.
bash -n preparar-sons.sh
grep -Fxq python-pyudev packages.txt
grep -Fxq 'Exec=/usr/local/bin/ruindows-sounds' overlay/etc/xdg/autostart/ruindows-sounds.desktop
grep -Fq 'python3 verificar-sons.py sons' build.sh
python3 - <<'PY'
import runpy, tempfile, wave, pathlib, subprocess
m = runpy.run_path('overlay/usr/local/bin/ruindows-sounds')
class Attr:
    def __init__(self, code): self.code=code
    def asstring(self, key): return self.code
class Device:
    def __init__(self, name, kind, code):
        self.sys_name=name; self.device_type=kind; self.attributes=Attr(code)
assert m['physical_device'](Device('1-2','usb_device','00'))
assert not m['physical_device'](Device('usb1','usb_device','09'))
assert not m['physical_device'](Device('1-2:1.0','usb_interface','00'))
assert not m['physical_device'](Device('1-3','usb_device','09'))
e=m['USBEvents'](['old'])
assert not e.event('add','old',True)
assert not e.event('add','hub',False)
assert e.event('add','new',True)
assert not e.event('add','new',True)
assert e.event('remove','new')
assert not e.event('remove','new')
assert e.event('remove','old')
assert e.event('add','new',True)
with tempfile.TemporaryDirectory() as tmp:
    for name in ['startup.wav','usb.wav']:
        with wave.open(str(pathlib.Path(tmp)/name),'wb') as w:
            w.setparams((2,2,48000,0,'NONE','not compressed')); w.writeframes(b'\0'*19200)
    subprocess.run(['python3','verificar-sons.py',tmp],check=True)
    (pathlib.Path(tmp)/'usb.wav').unlink()
    assert subprocess.run(['python3','verificar-sons.py',tmp],capture_output=True).returncode != 0
print('OK: detecção USB simulada, exclusão de hubs/interfaces, WAV válido e rejeição de arquivo ausente.')
PY

# Verify the actual included audio assets as well as the simulated inputs.
python3 verificar-sons.py sons
python3 - <<'PY'
import wave
from array import array
for name in ("startup", "usb"):
    with wave.open("sons/"+name+".wav", "rb") as w:
        samples = array("h", w.readframes(w.getnframes()))
        assert any(samples), name+": áudio silencioso"
print("OK: ambos os áudios incorporados, válidos e não silenciosos.")
PY

# V10.8: verify compact live list, offline payload path, and real XZ roundtrip.
bash -n select-live-packages.sh
for pkg in firefox vlc vlc-plugins-extra gnome-disk-utility system-config-printer cups cups-pk-helper; do
  grep -Fxq "$pkg" packages.txt
  if grep -Fxq "$pkg" "$scratch/live-packages"; then exit 1; fi
done
for pkg in linux linux-firmware xfce4-session lightdm xfce4-terminal zenity grub efibootmgr dosfstools e2fsprogs python-pyudev pipewire plymouth fastfetch imagemagick chafa galculator ristretto htop; do
  grep -Fxq "$pkg" "$scratch/live-packages"
done
for f in build.sh overlay/usr/local/bin/ruindows-install overlay/usr/local/bin/ruindows-install-autostart; do
  grep -Fq 'system.tar.xz' "$f"
  if grep -Fq 'system.tar.zst' "$f"; then exit 1; fi
done
grep -Fq 'arch-chroot /mnt mkinitcpio -P' overlay/usr/local/bin/ruindows-install
grep -Fq 'airootfs_image_type="squashfs"' build.sh
mkdir -p "$scratch/src/boot" "$scratch/restored"
printf 'test LTS payload\n' > "$scratch/src/boot/vmlinuz-linux-lts"
chmod 640 "$scratch/src/boot/vmlinuz-linux-lts"
ln "$scratch/src/boot/vmlinuz-linux-lts" "$scratch/src/hardlink"
ln -s boot/vmlinuz-linux-lts "$scratch/src/link"
tar --one-file-system --numeric-owner --acls --xattrs --xattrs-include='*' -C "$scratch/src" -cpf - . | xz -6e -T2 --memlimit-compress=2GiB -c > "$scratch/system.tar.xz"
xz -t "$scratch/system.tar.xz"
(cd "$scratch" && sha256sum system.tar.xz > system.sha256 && sha256sum -c system.sha256)
xz -dc "$scratch/system.tar.xz" | tar --numeric-owner --acls --xattrs --xattrs-include='*' -xpf - -C "$scratch/restored"
cmp "$scratch/src/boot/vmlinuz-linux-lts" "$scratch/restored/boot/vmlinuz-linux-lts"
[[ $(stat -c %a "$scratch/restored/boot/vmlinuz-linux-lts") == 640 ]]
[[ "$scratch/restored/hardlink" -ef "$scratch/restored/boot/vmlinuz-linux-lts" ]]
[[ $(readlink "$scratch/restored/link") == boot/vmlinuz-linux-lts ]]
printf 'OK: live compacto, apps completos na instalação, XZ, SHA256, permissões e links.\n'
