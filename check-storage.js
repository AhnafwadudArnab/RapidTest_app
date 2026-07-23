#!/usr/bin/env node

const { Storage } = require('@google-cloud/storage');

async function initializeStorage() {
  const projectId = 'faculty-purpose-bb50a';
  const bucketName = 'faculty-purpose-bb50a.firebasestorage.app';
  
  try {
    console.log('Initializing Firebase Storage...');
    console.log(`Project: ${projectId}`);
    console.log(`Bucket: ${bucketName}`);
    
    // Create a Storage client using Application Default Credentials
    // The firebase-tools CLI sets these up automatically
    const storage = new Storage({
      projectId: projectId,
    });
    
    // Try to get the bucket
    const bucket = storage.bucket(bucketName);
    const [exists] = await bucket.exists();
    
    if (exists) {
      console.log('✓ Storage bucket exists and is ready!');
      return true;
    } else {
      console.log('✗ Storage bucket does not exist.');
      console.log('\nManual Steps Required:');
      console.log('1. Go to: https://console.firebase.google.com/project/' + projectId + '/storage');
      console.log('2. Click "Get Started"');
      console.log('3. Choose your storage location and click "Create"');
      console.log('\nThen run: npx firebase-tools deploy --only storage');
      return false;
    }
  } catch (error) {
    console.error('Error:', error.message);
    
    if (error.code === 'PERMISSION_DENIED') {
      console.log('\n✗ Storage not yet enabled on this project.');
      console.log('\nTo enable Firebase Storage:');
      console.log('1. Visit: https://console.firebase.google.com/project/' + projectId + '/storage');
      console.log('2. Click the "Get Started" button');
      console.log('3. Select a Cloud Storage location (any location works)');
      console.log('4. Click "Create" to initialize the default bucket');
      console.log('\nAfter enabling, run: npx firebase-tools deploy --only storage');
      return false;
    }
    
    return false;
  }
}

initializeStorage().then(success => {
  process.exit(success ? 0 : 1);
}).catch(err => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
