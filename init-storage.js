const admin = require('firebase-admin');

// Use Application Default Credentials which firebase-tools CLI has set up
const projectId = 'faculty-purpose-bb50a';

// Try using the Firebase Admin SDK to trigger Storage initialization
async function initializeStorage() {
  try {
    console.log('Attempting to initialize Firebase Storage...');
    
    // Initialize Firebase Admin SDK
    const app = admin.initializeApp({
      projectId: projectId,
      storageBucket: 'faculty-purpose-bb50a.firebasestorage.app',
    });
    
    // Get a reference to the storage bucket
    const bucket = admin.storage().bucket();
    
    // Try to list files - if Storage isn't enabled, this will fail
    const [files] = await bucket.getFiles({ maxResults: 1 });
    
    console.log('Success! Firebase Storage is already available.');
    return true;
    
  } catch (error) {
    console.error('Storage initialization error:', error.message);
    
    // Check if it's the "not set up" error
    if (error.message.includes('Firebase Storage') || 
        error.message.includes('has not been set up') ||
        error.code === 'PERMISSION_DENIED') {
      console.log('\nStorage needs to be manually enabled through the Firebase Console.');
      console.log('URL: https://console.firebase.google.com/project/faculty-purpose-bb50a/storage');
      console.log('\nSteps:');
      console.log('1. Go to the URL above');
      console.log('2. Click "Get Started"');
      console.log('3. Choose a Cloud Storage location (any location is fine)');
      console.log('4. Click "Create"');
      console.log('\nAfter enabling, you can deploy the storage rules with:');
      console.log('  npx firebase-tools deploy --only storage');
    }
    
    return false;
  }
}

// Run the initialization
initializeStorage().then(() => {
  process.exit(0);
}).catch(error => {
  console.error('Unexpected error:', error);
  process.exit(1);
});
