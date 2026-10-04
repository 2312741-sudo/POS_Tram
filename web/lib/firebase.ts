// lib/firebase.ts
import { initializeApp, getApps } from "firebase/app";
import { getDatabase } from "firebase/database";

import { getAuth } from "firebase/auth";

const firebaseConfig = {
  apiKey: "AIzaSyDjsags-PVvGmO8YXC1UMYfnqOa7jAieCg",
  authDomain: "tramapp-36f53.firebaseapp.com",
  databaseURL: "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "tramapp-36f53",
  storageBucket: "tramapp-36f53.appspot.com",
  messagingSenderId: "727118636553",
  appId: "1:727118636553:web:tramapp",
};

const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApps()[0];
export const db = getDatabase(app);
export const auth = getAuth(app);
export { firebaseConfig };
export default app;
