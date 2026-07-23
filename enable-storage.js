const { google } = require('googleapis');
const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

const projectNumber = '523938747996';
const projectId = 'faculty-purpose-bb50a';

async function enableStorage() {
  try {
    console.log(`Attempting to enable Storage API for project ${projectId}...`);
    
    // Get the auth from firebase-tools
    // The firebase CLI stores credentials that we can use
    const auth = new google.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/cloud-platform'],
    });
    
    const authClient = await auth.getClient();
    
    // Create the Service Usage API client
    const serviceusage = google.serviceusage({
      version: 'v1',
      auth: authClient
    });
    
    console.log('Enabling firebasestorage.googleapis.com...');
    
    const request = {
      name: `projects/${projectNumber}/services/firebasestorage.googleapis.com`,
    };
    
    const response = await serviceusage.services.enable(request);
    
    console.log('Success! Storage API has been enabled.');
    console.log(JSON.stringify(response.data, null, 2));
    
    return true;
  } catch (error) {
    console.error('Error enabling Storage API:', error.message);
    
    if (error.message.includes('not found') || error.message.includes('404')) {
      console.log('\nTrying alternative method...');
      return enableViaFirebaseTools();
    }
    
    return false;
  }
}

async function enableViaFirebaseTools() {
  try {
    console.log('Using firebase-tools to enable Storage...');
    // This will trigger the interactive prompt which requires manual intervention
    const { stdout, stderr } = await execPromise('npx firebase-tools init storage --project faculty-purpose-bb50a');
    console.log(stdout);
    if (stderr) console.error(stderr);
    return true;
  } catch (error) {
    console.error('Error:', error.message);
    return false;
  }
}

enableStorage().then(success => {
  process.exit(success ? 0 : 1);
});
