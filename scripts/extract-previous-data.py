#!/usr/bin/env python3
"""Extract previous day's data for a student from archived CSV files."""

import sys
import os
import json
from datetime import datetime, timedelta
import csv

def get_previous_data(student_id: str) -> dict:
    """Get previous day's data for a student."""
    archive_dir = "archive/data"

    if not os.path.exists(archive_dir):
        return {}

    # Get yesterday's date in JST
    # Note: This script runs in JST timezone context
    today = datetime.now()
    yesterday = today - timedelta(days=1)
    yesterday_str = yesterday.strftime('%Y-%m-%d')

    csv_file = os.path.join(archive_dir, f"{yesterday_str}.csv")

    if not os.path.exists(csv_file):
        # Try to find the most recent CSV file
        csv_files = sorted([f for f in os.listdir(archive_dir) if f.endswith('.csv')], reverse=True)
        if csv_files:
            csv_file = os.path.join(archive_dir, csv_files[0])
        else:
            return {}

    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('student_id', '').lower() == student_id.lower():
                    result = {}
                    if row.get('file_size') and row['file_size'] != '':
                        try:
                            result['file_size'] = int(row['file_size'])
                        except ValueError:
                            pass
                    return result
    except Exception:
        pass

    return {}

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("{}")
        sys.exit(0)

    student_id = sys.argv[1]
    data = get_previous_data(student_id)
    print(json.dumps(data))
