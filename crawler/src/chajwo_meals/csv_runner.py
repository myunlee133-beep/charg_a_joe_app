"""CSV-only standalone runner: no database connection or writes."""
from __future__ import annotations
from .cli import main as _shared_main

def main(argv: list[str] | None = None) -> int:
    return _shared_main(argv, forced_storage='csv')

if __name__ == '__main__':
    raise SystemExit(main())
