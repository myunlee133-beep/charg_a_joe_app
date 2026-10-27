"""Direct source crawler + persistent database write; no Siksha execution."""
from __future__ import annotations
import argparse
import json
import os
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo
from .pipeline import collect, collect_metadata, export, summarize, flatten_entries
from .fixed import fixed_item_rows, load_fixed_catalog
from .sources import SOURCES
from .database import sync_db
from .hours import extract_service_hours


def main(argv: list[str] | None = None, *, forced_storage: str | None = None) -> int:
    parser=argparse.ArgumentParser(description='Chajwo independent SNU meal crawler')
    parser.add_argument('--live',action='store_true',help='Opt in to direct external requests')
    parser.add_argument('--start',default=datetime.now(ZoneInfo('Asia/Seoul')).date().isoformat())
    parser.add_argument('--days',type=int,default=30,help='Calendar days 1..31; defaults to 30')
    parser.add_argument('--sources',nargs='+',default=list(SOURCES),choices=list(SOURCES))
    parser.add_argument('--output',default='outputs/latest',
                        help=('CSV/JSON output directory' if forced_storage != 'db' else argparse.SUPPRESS))
    parser.add_argument('--storage',choices=('csv','db','both'),default='csv',
                        help=('csv: files only; db: database only; both: backwards compatibility'
                              if forced_storage is None else argparse.SUPPRESS))
    parser.add_argument('--write-db',action='store_true',
                        help=('Legacy: save CSV and DB together' if forced_storage is None else argparse.SUPPRESS))
    parser.add_argument('--database-url',default=os.environ.get('DATABASE_URL'),
                        help=('sqlite:///path/to/file.db or postgresql://user:pass@host/db'
                              if forced_storage != 'csv' else argparse.SUPPRESS))
    parser.add_argument('--strict',action='store_true')
    parser.add_argument('--skip-metadata',action='store_true',help='Use registry without official guide/map fetch')
    args=parser.parse_args(argv)
    storage = args.storage
    if forced_storage is not None:
        if storage not in ('csv', forced_storage):
            parser.error(f'This entry point only supports {forced_storage} storage')
        storage = forced_storage
    if args.write_db:
        if forced_storage == 'csv':
            parser.error('CSV-only command cannot use --write-db')
        storage = 'both' if forced_storage is None else storage
    if not args.live:parser.error('Real crawling is disabled unless --live is specified')
    if storage in ('db','both') and not args.database_url:
        parser.error('Use DATABASE_URL or --database-url with --write-db')
    start=date.fromisoformat(args.start)
    rows,errors=collect(start=start,days=args.days,sources=tuple(args.sources),strict=args.strict)
    if args.skip_metadata:
        from .directory import make_directory
        directory=make_directory()
    else:
        directory,meta_errors=collect_metadata()
        errors.extend(meta_errors)
    if storage in ('csv', 'both'):
        report = export(rows,errors,Path(args.output),started=start,days=args.days,
                        sources=tuple(args.sources),restaurant_directory=directory)
    else:
        # DB-only mode does not create an output directory or any CSV/JSON files.
        report = summarize(rows,errors,started=start,days=args.days,
                           sources=tuple(args.sources),restaurant_directory=directory)
    report['storage'] = storage
    if storage in ('db','both'):
        # DB includes unpriced dishes and uncertain raw prices for later review.
        entries = flatten_entries([r for r in rows if not (r['source']=='snuco' and r['restaurant'] in ('버거운버거','공대간이식당'))])
        if 'snuco' in args.sources:
            entries.extend({'entry_kind':'fixed_catalog', **r} for r in fixed_item_rows(load_fixed_catalog()))
        db_report=sync_db(args.database_url, entries=entries, directory=directory,
                          errors=errors, started=start.isoformat(), days=args.days,
                          manifest=report, hour_rows=extract_service_hours(rows))
        report['database_sync']=db_report
        if storage == 'both':
            (Path(args.output)/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    elif storage == 'csv':
        # Export() wrote its initial manifest; update it to include selected storage.
        (Path(args.output)/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return 2 if errors else 0

if __name__=='__main__':raise SystemExit(main())
