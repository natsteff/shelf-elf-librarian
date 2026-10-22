#!/usr/bin/env python3
"""Generate app notice and full license from reviewable repository sources."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
core = (root / 'Legal/CORE-TERMS.txt').read_text()
notes = (root / 'Legal/SHELF-ELF-NOTES.txt').read_text()
license_text = (root / 'LICENSE').read_text()
version = re.search(r'^Notice version ([^ •]+)', core, re.M).group(1)
text = core + '\n' + notes
for value in (text, license_text):
    if '\"\"\"#' in value:
        raise SystemExit('Raw Swift delimiter in source text; review before generation.')
p = root / 'Sources/LibraryFiler/LicenseTerms.swift'
s = p.read_text()
a = s.index('enum LicenseTerms {')
b = s.index('struct LicenseTermsView:', a)
prefix = ('enum LicenseTerms {\n    static let version = "' + version + '"\n'
          + '    static let text = #"""\n' + text.rstrip() + '\n"""#\n'
          + '    static let licenseText = #"""\n' + license_text.rstrip() + '\n"""#\n}\n\n')
p.write_text(s[:a] + prefix + s[b:])
(root / 'USAGE-NOTICE.md').write_text('# Shelf Elf Librarian — License & Usage Notice\n\n' + text.rstrip() + '\n\nRead the complete [AGPL-3.0 license](LICENSE).\n')
