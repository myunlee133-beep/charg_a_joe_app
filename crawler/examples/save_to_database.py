"""Entry point: update the application DB only, without exporting CSV files."""
from chajwo_meals.db_runner import main

if __name__ == '__main__':
    raise SystemExit(main())
