#!/usr/bin/env python3
"""
Copy AAC images from one GCP project to another
Usage: python3 copy_images_between_projects.py <source_project> <dest_project>
Example: python3 copy_images_between_projects.py bravo-dev-465400 bravo-test-465400
"""

import sys
from google.cloud import storage

# Project configurations
PROJECTS = {
    'dev': 'bravo-dev-465400',
    'test': 'bravo-test-465400',
    'prod': 'bravo-prod-465323'
}

def copy_images(source_project_id, dest_project_id):
    """Copy all AAC images from source bucket to destination bucket"""
    
    source_bucket_name = f"{source_project_id}-aac-images"
    dest_bucket_name = f"{dest_project_id}-aac-images"
    
    print(f"📋 Copying images")
    print(f"   From: {source_bucket_name} (project: {source_project_id})")
    print(f"   To:   {dest_bucket_name} (project: {dest_project_id})")
    print()
    
    # Initialize storage clients
    source_client = storage.Client(project=source_project_id)
    dest_client = storage.Client(project=dest_project_id)
    
    # Get buckets
    source_bucket = source_client.bucket(source_bucket_name)
    dest_bucket = dest_client.bucket(dest_bucket_name)
    
    # Ensure destination bucket exists
    if not dest_bucket.exists():
        print(f"❌ Destination bucket {dest_bucket_name} does not exist!")
        return
    
    # List all blobs in source bucket
    blobs = list(source_bucket.list_blobs())
    total_blobs = len(blobs)
    
    if total_blobs == 0:
        print("⚠️  No images found in source bucket")
        return
    
    print(f"Found {total_blobs} images to copy...")
    print()
    
    copied = 0
    skipped = 0
    errors = 0
    
    for i, source_blob in enumerate(blobs, 1):
        try:
            # Check if blob already exists in destination
            dest_blob = dest_bucket.blob(source_blob.name)
            
            if dest_blob.exists():
                print(f"[{i}/{total_blobs}] ⏭️  Skipping (already exists): {source_blob.name}")
                skipped += 1
            else:
                # Copy blob
                source_bucket.copy_blob(source_blob, dest_bucket, source_blob.name)
                print(f"[{i}/{total_blobs}] ✅ Copied: {source_blob.name}")
                copied += 1
                
        except Exception as e:
            print(f"[{i}/{total_blobs}] ❌ Error copying {source_blob.name}: {e}")
            errors += 1
    
    print()
    print("=" * 60)
    print(f"✅ Copied:  {copied}")
    print(f"⏭️  Skipped: {skipped}")
    print(f"❌ Errors:  {errors}")
    print(f"📊 Total:   {total_blobs}")
    print("=" * 60)

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 copy_images_between_projects.py <source> <destination>")
        print()
        print("Arguments can be project IDs or shortcuts:")
        print("  Shortcuts: dev, test, prod")
        print("  Project IDs: bravo-dev-465400, bravo-test-465400, bravo-prod-465323")
        print()
        print("Examples:")
        print("  python3 copy_images_between_projects.py dev test")
        print("  python3 copy_images_between_projects.py bravo-dev-465400 bravo-test-465400")
        print("  python3 copy_images_between_projects.py dev prod")
        sys.exit(1)
    
    source_arg = sys.argv[1]
    dest_arg = sys.argv[2]
    
    # Convert shortcuts to project IDs
    source_project = PROJECTS.get(source_arg, source_arg)
    dest_project = PROJECTS.get(dest_arg, dest_arg)
    
    # Confirm with user
    print()
    print("⚠️  About to copy images:")
    print(f"   Source:      {source_project}")
    print(f"   Destination: {dest_project}")
    print()
    
    confirm = input("Proceed? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("❌ Cancelled")
        sys.exit(0)
    
    print()
    copy_images(source_project, dest_project)

if __name__ == "__main__":
    main()
