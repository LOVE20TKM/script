#!/usr/bin/env python3
"""
Export SQL query results to CSV and XLSX.
Supports multiple SELECT statements in one SQL file; each produces separate output.
"""

import argparse
import csv
import re
import sqlite3
import sys
from pathlib import Path

try:
    from openpyxl import Workbook
    HAS_OPENPYXL = True
except ImportError:
    HAS_OPENPYXL = False


def extract_select_statements(sql_content: str) -> list[str]:
    """Extract SELECT statements from SQL, split by semicolon, skip comments."""
    statements = []
    for block in re.split(r';\s*\n', sql_content):
        block = block.strip()
        lines = []
        for line in block.splitlines():
            line_stripped = line.strip()
            if line_stripped.startswith('--') or not line_stripped:
                continue
            lines.append(line)
        stmt = '\n'.join(lines).strip()
        if stmt.upper().startswith('SELECT'):
            statements.append(stmt)
    return statements


def export_to_csv(rows: list, headers: list[str], path: Path):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(headers)
        w.writerows(rows)


def export_to_xlsx(workbook: "Workbook", sheet_name: str, rows: list, headers: list[str]):
    ws = workbook.create_sheet(title=sheet_name[:31])
    ws.append(headers)
    for row in rows:
        ws.append(row)


def main():
    parser = argparse.ArgumentParser(description='Export SQL results to CSV and XLSX')
    parser.add_argument('--db', required=True, help='SQLite database path')
    parser.add_argument('--sql', required=True, help='SQL file path')
    parser.add_argument('--out-dir', required=True, help='Output directory')
    args = parser.parse_args()

    db_path = Path(args.db)
    sql_path = Path(args.sql)
    out_dir = Path(args.out_dir)

    if not db_path.exists():
        print(f'Error: database not found: {db_path}', file=sys.stderr)
        sys.exit(1)
    if not sql_path.exists():
        print(f'Error: SQL file not found: {sql_path}', file=sys.stderr)
        sys.exit(1)

    sql_content = sql_path.read_text(encoding='utf-8')
    statements = extract_select_statements(sql_content)
    if not statements:
        print('Error: no SELECT statement found in SQL file', file=sys.stderr)
        sys.exit(1)

    out_dir.mkdir(parents=True, exist_ok=True)
    base_name = sql_path.stem

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    csv_paths = []
    wb = None
    if HAS_OPENPYXL:
        wb = Workbook()
        wb.remove(wb.active)

    try:
        for i, stmt in enumerate(statements):
            cursor = conn.execute(stmt)
            rows = [list(row) for row in cursor.fetchall()]
            headers = [d[0] for d in cursor.description]

            suffix = f'_{i + 1}' if len(statements) > 1 else ''
            csv_path = out_dir / f'{base_name}{suffix}.csv'
            export_to_csv(rows, headers, csv_path)
            csv_paths.append(csv_path)
            print(f'  CSV: {csv_path}')

            if HAS_OPENPYXL and wb:
                sheet_name = f'Query{i + 1}' if len(statements) > 1 else base_name[:31]
                export_to_xlsx(wb, sheet_name, rows, headers)

        if wb:
            xlsx_path = out_dir / f'{base_name}.xlsx'
            wb.save(xlsx_path)
            print(f'  XLSX: {xlsx_path}')
    finally:
        conn.close()

    if not HAS_OPENPYXL:
        print('  (install openpyxl for XLSX: pip install openpyxl)', file=sys.stderr)


if __name__ == '__main__':
    main()
