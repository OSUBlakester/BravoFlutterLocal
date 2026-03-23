#!/usr/bin/env python3
"""
Copy Firestore collections from one GCP project to another
Automatically updates image_url fields to match destination storage bucket
Usage: python3 copy_firestore_between_projects.py <source_project> <dest_project> [collections] [--clear]
Example: python3 copy_firestore_between_projects.py dev prod aac_images --clear
"""

import sys
from google.cloud import firestore

# Project configurations
PROJECTS = {
    'dev': 'bravo-dev-465400',
    'test': 'bravo-test-465400',
    'prod': 'bravo-prod-465323'
}

# Storage bucket mappings
STORAGE_BUCKETS = {
    'bravo-dev-465400': 'bravo-dev-465400-aac-images',
    'bravo-test-465400': 'bravo-test-465400-aac-images',
    'bravo-prod-465323': 'bravo-prod-465323-aac-images'
}

def update_image_url(doc_data, source_project, dest_project):
    """Update image_url field to point to destination project's storage bucket"""
    
    if 'image_url' not in doc_data:
        return doc_data
    
    image_url = doc_data['image_url']
    source_bucket = STORAGE_BUCKETS.get(source_project)
    dest_bucket = STORAGE_BUCKETS.get(dest_project)
    
    if source_bucket and dest_bucket and source_bucket in image_url:
        updated_url = image_url.replace(source_bucket, dest_bucket)
        doc_data['image_url'] = updated_url
        return doc_data
    
    return doc_data

def clear_collection(db, collection_name, batch_size=500):
    """Delete all documents in a collection"""
    
    print(f"\n🗑️  Clearing collection: {collection_name}")
    
    collection_ref = db.collection(collection_name)
    deleted = 0
    
    while True:
        # Get a batch of documents
        docs = collection_ref.limit(batch_size).stream()
        deleted_in_batch = 0
        
        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
            deleted_in_batch += 1
            deleted += 1
        
        if deleted_in_batch == 0:
            break
        
        batch.commit()
        print(f"   🗑️  Deleted {deleted} documents so far...")
    
    print(f"   ✅ Cleared {deleted} total documents from {collection_name}")
    return deleted

def copy_collection(source_db, dest_db, collection_name, source_project, dest_project, batch_size=500):
    """Copy a Firestore collection from source to destination"""
    
    print(f"\n📁 Copying collection: {collection_name}")
    print(f"   🔄 Updating URLs: {STORAGE_BUCKETS.get(source_project)} → {STORAGE_BUCKETS.get(dest_project)}")
    
    # Get all documents in the source collection
    source_collection = source_db.collection(collection_name)
    docs = source_collection.stream()
    
    copied = 0
    updated = 0
    skipped = 0
    errors = 0
    batch = dest_db.batch()
    batch_count = 0
    
    for doc in docs:
        try:
            # Get the destination document reference
            dest_doc_ref = dest_db.collection(collection_name).document(doc.id)
            
            # Get document data
            doc_data = doc.to_dict()
            
            # Always update URLs to match destination project
            if 'image_url' in doc_data:
                old_url = doc_data['image_url']
                doc_data = update_image_url(doc_data, source_project, dest_project)
                if doc_data['image_url'] != old_url:
                    updated += 1
            
            # Add to batch (overwrite if exists since we're doing a fresh copy)
            batch.set(dest_doc_ref, doc_data)
            batch_count += 1
            copied += 1
            
            # Commit batch every batch_size documents
            if batch_count >= batch_size:
                batch.commit()
                print(f"   ✅ Committed batch of {batch_count} documents (total: {copied}, updated URLs: {updated})")
                batch = dest_db.batch()
                batch_count = 0
                
        except Exception as e:
            print(f"   ❌ Error copying document {doc.id}: {e}")
            errors += 1
    
    # Commit any remaining documents
    if batch_count > 0:
        batch.commit()
        print(f"   ✅ Committed final batch of {batch_count} documents")
    
    print(f"\n   Summary for {collection_name}:")
    print(f"   ✅ Copied:       {copied}")
    print(f"   🔄 URLs Updated: {updated}")
    print(f"   ❌ Errors:       {errors}")
    
    return copied, updated, errors

def copy_subcollections(source_db, dest_db, parent_path, doc_id):
    """Recursively copy subcollections of a document"""
    
    source_doc_ref = source_db.document(parent_path).document(doc_id)
    dest_doc_ref = dest_db.document(parent_path).document(doc_id)
    
    # Get all subcollections
    for subcollection in source_doc_ref.collections():
        subcoll_name = subcollection.id
        print(f"      📂 Found subcollection: {parent_path}/{doc_id}/{subcoll_name}")
        
        # Copy subcollection documents
        for subdoc in subcollection.stream():
            try:
                dest_subdoc_ref = dest_doc_ref.collection(subcoll_name).document(subdoc.id)
                
                if not dest_subdoc_ref.get().exists:
                    dest_subdoc_ref.set(subdoc.to_dict())
                    print(f"         ✅ Copied: {subdoc.id}")
                    
                    # Recursively copy any nested subcollections
                    copy_subcollections(source_db, dest_db, f"{parent_path}/{doc_id}/{subcoll_name}", subdoc.id)
                else:
                    print(f"         ⏭️  Skipped: {subdoc.id}")
                    
            except Exception as e:
                print(f"         ❌ Error copying {subdoc.id}: {e}")

def copy_firestore_data(source_project_id, dest_project_id, collections=None, clear_first=False):
    """Copy Firestore collections from source to destination"""
    
    print(f"\n📋 Copying Firestore data")
    print(f"   From: {source_project_id}")
    print(f"   To:   {dest_project_id}")
    
    # Initialize Firestore clients
    source_db = firestore.Client(project=source_project_id)
    dest_db = firestore.Client(project=dest_project_id)
    
    # Default collections to copy
    if not collections:
        collections = ['aac_images']
    
    print(f"   Collections: {', '.join(collections)}")
    print(f"   Clear first: {'Yes' if clear_first else 'No'}")
    print(f"   Update URLs: Always (automatic)")
    print()
    
    total_copied = 0
    total_updated = 0
    total_errors = 0
    total_cleared = 0
    
    for collection_name in collections:
        # Clear destination collection if requested
        if clear_first:
            cleared = clear_collection(dest_db, collection_name)
            total_cleared += cleared
        
        # Copy collection
        copied, updated, errors = copy_collection(
            source_db, dest_db, collection_name, 
            source_project_id, dest_project_id
        )
        total_copied += copied
        total_updated += updated
        total_errors += errors
    
    print("\n" + "=" * 60)
    print("📊 Overall Summary:")
    if clear_first:
        print(f"   🗑️  Total Cleared: {total_cleared}")
    print(f"   ✅ Total Copied:  {total_copied}")
    print(f"   🔄 URLs Updated:  {total_updated}")
    print(f"   ❌ Total Errors:  {total_errors}")
    print("=" * 60)

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 copy_firestore_between_projects.py <source> <destination> [collections...] [--clear]")
        print()
        print("Arguments:")
        print("  source:       Source project (shortcuts: dev, test, prod OR full project ID)")
        print("  destination:  Destination project (shortcuts: dev, test, prod OR full project ID)")
        print("  collections:  Optional list of collections to copy (default: aac_images)")
        print()
        print("Flags:")
        print("  --clear:      Clear destination collection before copying")
        print()
        print("Note: Image URLs are ALWAYS updated to match the destination storage bucket")
        print()
        print("Examples:")
        print("  python3 copy_firestore_between_projects.py dev prod")
        print("  python3 copy_firestore_between_projects.py dev prod --clear")
        print("  python3 copy_firestore_between_projects.py dev prod aac_images --clear")
        sys.exit(1)
    
    # Parse arguments
    args = sys.argv[1:]
    source_arg = args[0]
    dest_arg = args[1]
    
    # Extract flags
    clear_first = '--clear' in args
    
    # Remove flags from args to get collections
    collections_and_flags = args[2:]
    collections = [c for c in collections_and_flags if not c.startswith('--')]
    collections = collections if collections else None
    
    # Convert shortcuts to project IDs
    source_project = PROJECTS.get(source_arg, source_arg)
    dest_project = PROJECTS.get(dest_arg, dest_arg)
    
    # Confirm with user
    print()
    print("⚠️  About to copy Firestore data:")
    print(f"   Source:      {source_project}")
    print(f"   Destination: {dest_project}")
    if collections:
        print(f"   Collections: {', '.join(collections)}")
    else:
        print(f"   Collections: aac_images (default)")
    
    if clear_first:
        print(f"   ⚠️  WILL CLEAR destination collections first!")
    
    source_bucket = STORAGE_BUCKETS.get(source_project, 'unknown')
    dest_bucket = STORAGE_BUCKETS.get(dest_project, 'unknown')
    print(f"   🔄 Will update URLs:")
    print(f"      FROM: {source_bucket}")
    print(f"      TO:   {dest_bucket}")
    
    print()
    confirm = input("Proceed? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("❌ Cancelled")
        sys.exit(0)
    
    copy_firestore_data(source_project, dest_project, collections, clear_first)

if __name__ == "__main__":
    main()
