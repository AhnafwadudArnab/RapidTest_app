#!/usr/bin/env python3
"""
Script to enable Firebase Storage and initialize a bucket for a Firebase project.
"""

import json
import subprocess
import sys

def run_command(cmd):
    """Run a shell command and return output."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout.strip(), result.stderr.strip(), result.returncode

def get_access_token():
    """Get OAuth access token from Firebase CLI."""
    output, error, code = run_command('npx firebase-tools auth:list --json')
    if code == 0:
        try:
            # Try to extract token from firebase config
            data = json.loads(output)
            return data.get('access_token')
        except:
            pass
    
    # Alternative: try using gcloud
    output, error, code = run_command('gcloud auth application-default print-access-token')
    if code == 0:
        return output
    
    # Alternative: use firebase credential refresh
    output, error, code = run_command('npx firebase-tools --debug auth:export /tmp/firebase-debug.json 2>&1')
    if 'error' not in error.lower():
        try:
            with open('/tmp/firebase-debug.json', 'r') as f:
                data = json.load(f)
                return data.get('access_token')
        except:
            pass
    
    return None

def enable_storage_api(project_id):
    """Enable Cloud Storage API using REST API."""
    print(f"Attempting to enable Storage API for project: {project_id}")
    
    # Try using google-cloud-storage library
    try:
        from google.cloud import storage
        from google.auth.transport import requests
        from google.oauth2 import service_account
        
        # Try to use Application Default Credentials
        import os
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = ''
        
        # Create a client - this will try to use ADC
        try:
            client = storage.Client(project=project_id)
            # List buckets - this would require Storage to be enabled
            buckets = list(client.list_buckets())
            print(f"Storage is already enabled. Found {len(buckets)} buckets.")
            return True
        except Exception as e:
            if "Storage has not been set up" in str(e) or "PERMISSION_DENIED" in str(e):
                print(f"Storage not yet enabled, attempting to enable...")
                # Try to enable using the REST API
                return enable_via_rest_api(project_id)
            else:
                print(f"Error: {e}")
                return False
    except Exception as e:
        print(f"Could not use google-cloud-storage: {e}")
        return False

def enable_via_rest_api(project_id):
    """Enable Storage using REST API."""
    # This requires proper authentication which is complex
    print("Manual steps needed:")
    print(f"1. Go to: https://console.firebase.google.com/project/{project_id}/storage")
    print("2. Click 'Get Started' to enable Firebase Storage")
    print("3. Use the default bucket")
    return False

if __name__ == '__main__':
    project_id = 'faculty-purpose-bb50a'
    
    # Check if we can access Storage
    success = enable_storage_api(project_id)
    
    if not success:
        print("\nCould not enable Storage programmatically.")
        print("Fallback: Using firebase init storage command...")
        
        # Run firebase init storage interactively
        output, error, code = run_command(f'npx firebase-tools init storage --project {project_id}')
        print(output)
        if error:
            print("STDERR:", error)
        sys.exit(code)
    else:
        print("Storage API is enabled!")
        sys.exit(0)
