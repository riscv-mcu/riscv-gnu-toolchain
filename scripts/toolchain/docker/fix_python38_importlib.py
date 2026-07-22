#!/usr/bin/env python3
"""Fix NuGet python38.lib import library: CryptAcquireContextA incorrectly mapped
to python38.dll instead of ADVAPI32.dll. Regenerate clean import library from
python38.dll's actual exports."""
import pefile
import sys
import os

dll_path = sys.argv[1]
lib_dir = os.path.dirname(dll_path) + '/libs'

pe = pefile.PE(dll_path)
with open('/tmp/python38.def', 'w') as f:
    f.write('LIBRARY python38.dll\nEXPORTS\n')
    for exp in pe.DIRECTORY_ENTRY_EXPORT.symbols:
        if exp.name:
            f.write(exp.name.decode() + '\n')

os.chdir(lib_dir)
os.system('x86_64-w64-mingw32-dlltool -d /tmp/python38.def -l python38_fixed.lib -D python38.dll')
os.rename('python38.lib', 'python38.lib.bak')
os.rename('python38_fixed.lib', 'python38.lib')
os.remove('/tmp/python38.def')
print('Fixed python38.lib import library')