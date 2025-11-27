#!/usr/bin/env python3
import json
import csv
import sys
import os

def json_to_csv(json_file):
    """
    Converts a JSON file to CSV.
    Assumes the JSON is a list of dictionaries.
    """
    if not os.path.exists(json_file):
        print(f"Error: File '{json_file}' not found.")
        return

    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
            
        if not isinstance(data, list):
            print("Error: JSON root must be a list of objects.")
            return
            
        if not data:
            print("Error: JSON file is empty.")
            return

        # Collect all keys from all objects to ensure we have all headers
        headers = set()
        for item in data:
            if isinstance(item, dict):
                headers.update(item.keys())
            else:
                print("Error: JSON list must contain objects.")
                return
        
        headers = sorted(list(headers))
        
        csv_file = os.path.splitext(json_file)[0] + '.csv'
        
        with open(csv_file, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=headers)
            writer.writeheader()
            writer.writerows(data)
            
        print(f"Successfully converted '{json_file}' to '{csv_file}'")
        
    except json.JSONDecodeError:
        print(f"Error: Failed to decode JSON from '{json_file}'")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python json_to_csv.py <json_file>")
    else:
        json_to_csv(sys.argv[1])
