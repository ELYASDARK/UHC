importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyAweY8bfv9dhoASuyVEVYspV4_s4bFbjEc",
  authDomain: "uhca-20800.firebaseapp.com",
  projectId: "uhca-20800",
  storageBucket: "uhca-20800.firebasestorage.app",
  messagingSenderId: "705258727806",
  appId: "1:705258727806:web:393febdf287cc1f046eb2f",
  measurementId: "G-H827KGWBWV",
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((message) => {
  console.log("[firebase-messaging-sw.js] Background message:", message);
});
