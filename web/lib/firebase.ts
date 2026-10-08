// lib/firebase.ts
import { initializeApp, getApps } from "firebase/app";
import { getDatabase } from "firebase/database";
import { getFirestore } from "firebase/firestore";

import { getAuth } from "firebase/auth";
import { getFunctions } from "firebase/functions";

const firebaseConfig = {
  apiKey: "AIzaSyBWSS2o1ERO1HBnAyVZwAbzOSWNkkWa7GY",
  authDomain: "tramapp-36f53.firebaseapp.com",
  databaseURL: "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "tramapp-36f53",
  storageBucket: "tramapp-36f53.firebasestorage.app",
  messagingSenderId: "866082811261",
  appId: "1:866082811261:web:bf56985c8e7cedc90ef014",
};

// Kiểm tra tính đồng nhất của cấu hình Firebase khi khởi động
if (firebaseConfig.databaseURL && firebaseConfig.projectId) {
  if (!firebaseConfig.databaseURL.includes(firebaseConfig.projectId)) {
    const errorMsg = `[LỖI CẤU HÌNH FIREBASE] projectId ("${firebaseConfig.projectId}") không khớp với project trong databaseURL ("${firebaseConfig.databaseURL}"). Vui lòng kiểm tra lại cấu hình Firebase!`;
    console.error(errorMsg);
    if (process.env.NODE_ENV !== "production") {
      throw new Error(errorMsg);
    }
  }
}

const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApps()[0];
export const db = getDatabase(app);
export const firestore = getFirestore(app);
export const auth = getAuth(app);
export const functions = getFunctions(app, "asia-southeast1");
export { firebaseConfig };
export default app;

