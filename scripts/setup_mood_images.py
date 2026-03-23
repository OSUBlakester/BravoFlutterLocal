#!/usr/bin/env python3
"""
Script to upload mood images to Google Cloud Storage and create mood_images collection in Firestore.
This script should be run from the project root directory.
"""

import os
import sys
import json
from datetime import datetime, timezone
from pathlib import Path

# Add the existingbackend directory to the Python path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'existingbackend'))

try:
    from google.cloud import storage
    from google.cloud import firestore
except ImportError:
    print("Google Cloud libraries not installed. Install with:")
    print("pip install google-cloud-storage google-cloud-firestore")
    sys.exit(1)

# Configuration
MOOD_IMAGES_DIR = "mood_images"
BUCKET_NAME = "bravo-dev-465400-aac-images"  # Your existing bucket
STORAGE_PATH_PREFIX = "mood_mascot_images"
FIRESTORE_COLLECTION = "mood_images"

# Mapping of mood names to image files
# This maps the mood names from your app to the actual image files
MOOD_IMAGE_MAPPING = {
    # Core moods from your MoodOptions class - UPDATED with correct filenames
    "Happy": "happy.png",
    "Sad": "sad.png", 
    "Excited": "excited.png",
    "Calm": "peaceful.png",  # Using peaceful for calm
    "Angry": "angry.png",
    "Silly": "silly.png",
    "Tired": "tired.png",
    "Bored": "bored.png",
    "Anxious": "anxious.png",
    "Confused": "confused.png",
    "Surprised": "surprised.png",
    "Proud": "proud.png",
    "Worried": "worried.png",
    "Cranky": "cranky.png",
    "Peaceful": "peaceful.png",
    "Playful": "playful.png",
    "Frustrated": "frustrated.png",
    "Curious": "curious.png",
    "Grateful": "grateful.png",
    "Lonely": "lonely.png",
    "Content": "comfortable.png",  # Using comfortable for content
    
    # Additional moods
    "Scared": "scared.png",
    "Nervous": "nervous.png",
    "Hopeful": "hopeful.png",
    "Relaxed": "relaxed.png",
    "Disappointed": "disappointed.png",
    "Loved": "loved.png",
}

def initialize_clients():
    """Initialize Google Cloud clients"""
    try:
        storage_client = storage.Client()
        firestore_client = firestore.Client()
        return storage_client, firestore_client
    except Exception as e:
        print(f"Error initializing Google Cloud clients: {e}")
        print("Make sure you have proper authentication set up:")
        print("1. Service account key file in environment")
        print("2. Or run 'gcloud auth application-default login'")
        sys.exit(1)

def upload_image_to_storage(storage_client, local_path, storage_path):
    """Upload image to Google Cloud Storage"""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(storage_path)
        
        # Determine content type based on file extension
        content_type = 'image/png'
        if local_path.lower().endswith('.jpeg') or local_path.lower().endswith('.jpg'):
            content_type = 'image/jpeg'
        elif local_path.lower().endswith('.gif'):
            content_type = 'image/gif'
        
        # Upload the file
        with open(local_path, 'rb') as f:
            blob.upload_from_file(f, content_type=content_type)
        
        # For uniform bucket-level access, don't try to make_public()
        # The bucket should already be configured for public access
        # Just return the public URL format
        public_url = f"https://storage.googleapis.com/{BUCKET_NAME}/{storage_path}"
        
        print(f"✅ Uploaded successfully: {public_url}")
        return public_url
        
    except Exception as e:
        print(f"Error uploading {local_path} to {storage_path}: {e}")
        return None

def create_mood_document(firestore_client, mood_name, image_url, image_filename):
    """Create a document in the mood_images collection"""
    try:
        # Use lowercase mood name as document ID for consistency
        doc_id = mood_name.lower()
        
        doc_data = {
            "mood_name": mood_name,
            "image_url": image_url,
            "image_filename": image_filename,
            "image_type": "mood_mascot",
            "created_at": datetime.now(timezone.utc),
            "created_by": "admin_script",
            "active": True
        }
        
        # Create the document
        doc_ref = firestore_client.collection(FIRESTORE_COLLECTION).document(doc_id)
        doc_ref.set(doc_data)
        
        print(f"✅ Created Firestore document: {doc_id} -> {mood_name}")
        return True
        
    except Exception as e:
        print(f"❌ Error creating Firestore document for {mood_name}: {e}")
        return False

def main():
    """Main function to upload images and create Firestore collection"""
    print("🚀 Setting up mood images collection...")
    
    # Check if mood_images directory exists
    mood_dir = Path(MOOD_IMAGES_DIR)
    if not mood_dir.exists():
        print(f"❌ Directory {MOOD_IMAGES_DIR} not found!")
        print("Please run this script from the project root directory.")
        sys.exit(1)
    
    # Initialize clients
    storage_client, firestore_client = initialize_clients()
    
    print(f"📁 Found {len(MOOD_IMAGE_MAPPING)} mood mappings to process...")
    
    success_count = 0
    total_count = len(MOOD_IMAGE_MAPPING)
    
    for mood_name, image_filename in MOOD_IMAGE_MAPPING.items():
        print(f"\n📸 Processing {mood_name} -> {image_filename}")
        
        # Check if image file exists
        image_path = mood_dir / image_filename
        if not image_path.exists():
            print(f"⚠️  Image file not found: {image_path}")
            continue
        
        # Upload to Google Cloud Storage
        storage_path = f"{STORAGE_PATH_PREFIX}/{image_filename}"
        print(f"⬆️  Uploading to gs://{BUCKET_NAME}/{storage_path}")
        
        image_url = upload_image_to_storage(storage_client, str(image_path), storage_path)
        if not image_url:
            continue
        
        print(f"✅ Uploaded: {image_url}")
        
        # Create Firestore document
        if create_mood_document(firestore_client, mood_name, image_url, image_filename):
            success_count += 1
    
    print(f"\n🎉 Setup complete!")
    print(f"✅ Successfully processed: {success_count}/{total_count} moods")
    print(f"📊 Collection: {FIRESTORE_COLLECTION}")
    print(f"🪣 Storage path: gs://{BUCKET_NAME}/{STORAGE_PATH_PREFIX}/")
    
    if success_count < total_count:
        print(f"⚠️  {total_count - success_count} moods had issues - check the output above")

if __name__ == "__main__":
    main()