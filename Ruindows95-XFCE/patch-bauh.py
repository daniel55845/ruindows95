#!/usr/bin/env python3
"""Adapt the pinned Bauh wheel to Python 3.14's import API."""
import ast
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'bauh/view/core/gems.py'
source = path.read_text(encoding='utf-8')
old = 'pkgutil.find_loader('
old_load = 'module = loader.load_module()'
new = 'importlib.util.find_spec('
new_load = 'module = importlib.import_module(loader.name)'
if old in source and old_load in source:
    if source.count(old) != 1 or source.count(old_load) != 1 or 'import pkgutil\n' not in source:
        raise SystemExit('Bauh: código inesperado; revise o patch.')
    source = source.replace('import pkgutil\n', 'import pkgutil\nimport importlib.util\n', 1)
    source = source.replace(old, new).replace(old_load, new_load)
elif new not in source or new_load not in source:
    raise SystemExit('Bauh: patch não aplicável; revise a versão.')
ast.parse(source)
path.write_text(source, encoding='utf-8')
print('OK: compatibilidade de importação do Bauh.')
