#!/usr/bin/env python3
import os
import shutil
import sys

def organize_files(directory):
    """
    Organizes files in the specified directory into subfolders based on their extensions.
    """
    if not os.path.exists(directory):
        print(f"Error: Directory '{directory}' not found.")
        return

    for filename in os.listdir(directory):
        filepath = os.path.join(directory, filename)
        
        # Skip directories
        if os.path.isdir(filepath):
            continue
            
        # Get file extension
        _, extension = os.path.splitext(filename)
        extension = extension.lower().strip('.')
        
        if not extension:
            continue
            
        # Create destination folder
        dest_folder = os.path.join(directory, extension)
        if not os.path.exists(dest_folder):
            os.makedirs(dest_folder)
            
        # Move file
        try:
            shutil.move(filepath, os.path.join(dest_folder, filename))
            print(f"Moved: {filename} -> {extension}/")
        except Exception as e:
            print(f"Error moving {filename}: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python organize_files.py <directory_path>")
    else:
        organize_files(sys.argv[1])
