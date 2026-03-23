#!/usr/bin/env python3
"""
Update image URLs in production Firestore to point to prod storage bucket.
Changes: bravo-dev-465400-aac-images -> bravo-prod-465323-aac-images

Usage:
    python3 update_prod_image_urls.py [path/to/service-account.json]
    
Or set GOOGLE_APPLICATION_CREDENTIALS environment variable:
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    python3 update_prod_image_urls.py
"""

import firebase_admin
from firebase_admin import credentials, firestore
import sys
import os

# Initialize Firebase Admin SDK for production
print("🔧 Initializing Firebase Admin SDK for production...")

# Determine service account path
SERVICE_ACCOUNT_PATH = None

if len(sys.argv) > 1:
    # Path provided as command line argument
    SERVICE_ACCOUNT_PATH = sys.argv[1]
    print(f"📄 Using service account from argument: {SERVICE_ACCOUNT_PATH}")
elif os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'):
    # Use environment variable
    SERVICE_ACCOUNT_PATH = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
    print(f"📄 Using service account from GOOGLE_APPLICATION_CREDENTIALS: {SERVICE_ACCOUNT_PATH}")
else:
    print("\n❌ No service account key provided!")
    print("\nUsage options:")
    print("  1. Pass as argument: python3 update_prod_image_urls.py /path/to/key.json")
    print("  2. Set environment variable: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json")
    print("\nThe service account key should be for the bravo-prod-465323 project.")
    sys.exit(1)

try:
    cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred, {
        'projectId': 'bravo-prod-465323'
    })
    print("✅ Firebase initialized for bravo-prod-465323")
except Exception as e:
    print(f"❌ Error initializing Firebase: {e}")
    print(f"\n⚠️  Could not load service account from: {SERVICE_ACCOUNT_PATH}")
    print("Please ensure the file exists and is a valid service account key for bravo-prod-465323")
    sys.exit(1)

db = firestore.client()

# Query all images from aac_images collection
print("\n🔍 Fetching all images from aac_images collection...")
images_ref = db.collection('aac_images')
docs = images_ref.where('source', '==', 'bravo_images').stream()

# Count and update
updated_count = 0
skipped_count = 0
error_count = 0

OLD_BUCKET = 'bravo-dev-465400-aac-images'
NEW_BUCKET = 'bravo-prod-465323-aac-images'

print(f"\n🔄 Updating URLs:")
print(f"   FROM: https://storage.googleapis.com/{OLD_BUCKET}/...")
print(f"   TO:   https://storage.googleapis.com/{NEW_BUCKET}/...")
print()

for doc in docs:
    doc_data = doc.to_dict()
    image_url = doc_data.get('image_url', '')
    
    if OLD_BUCKET in image_url:
        # Update the URL
        new_url = image_url.replace(OLD_BUCKET, NEW_BUCKET)
        
        try:
            # Update Firestore document
            doc.reference.update({
                'image_url': new_url
            })
            updated_count += 1
            
            if updated_count <= 5:  # Show first 5 updates
                print(f"✅ Updated: {doc.id}")
                print(f"   {doc_data.get('concept', 'unknown')}/{doc_data.get('subconcept', 'unknown')}")
            elif updated_count % 50 == 0:  # Progress update every 50
                print(f"   ... {updated_count} images updated so far ...")
                
        except Exception as e:
            error_count += 1
            print(f"❌ Error updating {doc.id}: {e}")
    else:
        skipped_count += 1
        if skipped_count <= 3:
            print(f"⏭️  Skipped (already correct): {doc.id}")

print("\n" + "="*60)
print("📊 Update Summary:")
print(f"   ✅ Updated: {updated_count} images")
print(f"   ⏭️  Skipped: {skipped_count} images (already using correct bucket)")
print(f"   ❌ Errors:  {error_count} images")
print("="*60)

if updated_count > 0:
    print("\n🎉 Image URLs successfully updated in production!")
    print("   The Flutter app should now be able to load images correctly.")
else:
    print("\n⚠️  No images were updated. They may already be pointing to the correct bucket.")

print("\n💡 Next steps:")
print("   1. Clear the app cache on iPad")
print("   2. Restart the app")
print("   3. Test image loading in Tap interface")
