#!/usr/bin/env python3
"""Preserve original Arch hooks and boot parameters while adding Plymouth."""
import re
import sys
from pathlib import Path

ARGS = 'quiet splash'
def hooks(path):
    text = path.read_text()
    pattern = r'(?m)^([ \t]*HOOKS=\()([^)]*)(\))'
    def change(m):
        names = m[2].split()
        if 'plymouth' not in names:
            if 'kms' in names:
                index = names.index('kms') + 1
            elif 'systemd' in names:
                index = names.index('systemd') + 1
            elif 'udev' in names:
                index = names.index('udev') + 1
            else:
                raise ValueError(f'No supported early boot hook: {path}')
            names.insert(index, 'plymouth')
        return m[1] + ' '.join(names) + m[3]
    text, count = re.subn(pattern, change, text)
    if count != 1:
        raise ValueError(f'Expected exactly one HOOKS array in {path}')
    path.write_text(text)

def arguments(line):
    return line + ''.join(' '+a for a in ARGS.split() if a not in line.split())

def live(profile):
    root = profile / 'airootfs'
    hooks(root / 'etc/mkinitcpio.conf.d/archiso.conf')
    count = 0
    for directory in ('syslinux', 'grub', 'efiboot'):
        for p in (profile / directory).rglob('*'):
            if not p.is_file() or p.suffix not in ('.cfg', '.conf'): continue
            lines = p.read_text().splitlines()
            for i, line in enumerate(lines):
                if re.match(r'^\s*(append|linux|linuxefi|options)\s+', line, re.I) and re.search(r'archiso|archisobasedir', line, re.I):
                    if 'nomodeset' not in line.split():
                        lines[i] = arguments(line)
                        count += 1
            p.write_text('\n'.join(lines)+'\n')
    if not count: raise ValueError('No Archiso kernel boot entries found')
    print(f'Plymouth: {count} live boot entries configured')

def installed(root):
    hooks(root / 'etc/mkinitcpio.conf')
    p = root / 'etc/default/grub'
    text = p.read_text()
    pattern = r'(?m)^(GRUB_CMDLINE_LINUX_DEFAULT=)(["\'])(.*?)\2[ \t]*$'
    text, n = re.subn(pattern, lambda m: m[1]+m[2]+arguments(m[3]).strip()+m[2], text)
    if not n:
        text += '\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n'
    p.write_text(text)

if __name__ == '__main__':
    mode, path = sys.argv[1:]
    {'live': live, 'installed': installed}[mode](Path(path))
