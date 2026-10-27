"""Entry point: CSV and JSON only. Install the project first with pip install -e ."""
from chajwo_meals.csv_runner import main

if __name__ == '__main__':
    raise SystemExit(main())
