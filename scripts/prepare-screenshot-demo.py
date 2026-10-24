#!/usr/bin/env python3
"""Prepare fictional filename-only examples for the isolated test edition."""
import json
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parent.parent
base = Path('/private/tmp/Shelf Elf Demo')
examples = {
    'Music': ['The Paper Lanterns - northern lights.mp3', 'Mira Vale - paper moons.mp3',
              'Cedar Avenue - Into The Blue.mp3', 'Juniper Coast - where we wander.mp3',
              'Atlas Harbor - After The Rain.mp3', 'The Paper Lanterns - quiet streets.mp3'],
    'Video': ['The Clockwork Garden (2026).mkv', 'The Lantern Keeper (2025).mkv',
              'Harbor Stories - s01e01 - A New Tide.mkv', 'Harbor Stories - s01e02 - Letters Home.mkv'],
}
for kind, names in examples.items():
    folder = base / 'Workspace' / kind
    folder.mkdir(parents=True, exist_ok=True)
    for name in names:
        target = folder / name
        if not target.exists():
            target.write_text('Fictional Shelf Elf screenshot fixture; not playable media.\n')
archive = base / 'Demo Settings.json'
subprocess.run([str(repo / '.build/release/SafetyChecks'), '--write-starter-settings', str(archive)], check=True)
data = json.loads(archive.read_text())
for profile in data['profiles']:
    profile['root'] = str(base / 'Library' / ('Video' if profile['kind'] == 'video' else profile['name']))
    Path(profile['root']).mkdir(parents=True, exist_ok=True)
    if profile['kind'] == 'music':
        data['activeProfileID'] = profile['id']
        profile['bucket'] = False
        profile['folderMask'] = '{Artist}/{AlbumOrIndividual}'
archive.write_text(json.dumps(data, indent=2))
print(f'Demo workspace: {base / "Workspace"}')
print(f'Import into Fresh Install Test ONLY: {archive}')
