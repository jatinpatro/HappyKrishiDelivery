let admin;

const STORAGE_BUCKET = 'happykrishidelivery.firebasestorage.app';

function getFirebaseAdmin() {
  if (admin) return admin;
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!serviceAccountJson) {
    console.warn('FIREBASE_SERVICE_ACCOUNT_JSON not set — push notifications disabled');
    return null;
  }
  const firebaseAdmin = require('firebase-admin');
  const serviceAccount = JSON.parse(serviceAccountJson);
  firebaseAdmin.initializeApp({
    credential: firebaseAdmin.credential.cert(serviceAccount),
    storageBucket: STORAGE_BUCKET,
  });
  admin = firebaseAdmin;
  return admin;
}

module.exports = { getFirebaseAdmin, STORAGE_BUCKET };
