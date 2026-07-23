#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const projectId = 'faculty-purpose-bb50a';
const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
const imageDir = 'C:\\Users\\ahana\\Downloads\\update kits';
const maxImageBytes = 500 * 1024;

function initializeFirebase() {
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId,
    });
    return;
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
}

function imageDataUrl(fileName) {
  const filePath = path.join(imageDir, fileName);
  const bytes = fs.readFileSync(filePath);
  if (bytes.length > maxImageBytes) {
    throw new Error(`${fileName} is larger than 500 KB.`);
  }
  return `data:image/jpeg;base64,${bytes.toString('base64')}`;
}

async function deleteCollection(db, collectionPath, batchSize = 100) {
  const collectionRef = db.collection(collectionPath);
  while (true) {
    const snapshot = await collectionRef.limit(batchSize).get();
    if (snapshot.empty) return;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

function sampleRecord({ docRef, result, imageName, kitName, kitId, offsetMinutes }) {
  const timestamp = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - offsetMinutes * 60 * 1000),
  );
  const imageUrl = imageDataUrl(imageName);

  return {
    recordId: docRef.id,
    userId: 'sample-user',
    userName: 'Sample User',
    userEmail: 'sample.user@rptest.com',
    qrCodeValue: kitId,
    kitId,
    testType: kitName,
    isKnownQrKit: true,
    matchedQrKitId: kitId,
    matchedQrCode: kitId,
    matchedKitName: kitName,
    kitCategory: 'Rapid diagnostic test',
    kitSampleType: 'Blood',
    kitManufacturer: 'Rapid Test Kit',
    kitDescription: `${kitName} sample ${result.toLowerCase()} report.`,
    kitQrImageUrl: '',
    kitQrImageName: '',
    selectedResult: result,
    imageUrl,
    imageName,
    imageStoragePath: '',
    reviewStatus: 'Approved',
    adminComment: '',
    reviewedBy: 'Seed Script',
    reviewedAt: timestamp,
    qrParsedData: {
      seeded: true,
      matchedKitName: kitName,
      matchedQrCode: kitId,
    },
    submittedAt: timestamp,
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

async function main() {
  initializeFirebase();
  const db = admin.firestore();

  console.log('Removing existing dataset_records...');
  await deleteCollection(db, 'dataset_records');

  const positiveRef = db.collection('dataset_records').doc();
  const negativeRef = db.collection('dataset_records').doc();
  const batch = db.batch();

  batch.set(
    positiveRef,
    sampleRecord({
      docRef: positiveRef,
      result: 'Positive',
      imageName: '01.jpg',
      kitName: 'Rapid Test Kit Positive Sample',
      kitId: 'SAMPLE-POSITIVE-01',
      offsetMinutes: 10,
    }),
  );
  batch.set(
    negativeRef,
    sampleRecord({
      docRef: negativeRef,
      result: 'Negative',
      imageName: '02.jpg',
      kitName: 'Rapid Test Kit Negative Sample',
      kitId: 'SAMPLE-NEGATIVE-02',
      offsetMinutes: 20,
    }),
  );

  await batch.commit();
  console.log('Added 2 sample records: Positive with 01.jpg, Negative with 02.jpg.');
}

main().catch((error) => {
  console.error('Seed failed:', error.message || error);
  process.exit(1);
});
