import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';
import reportWebVitals from './reportWebVitals';

// Add global error handler to catch and log errors
const originalConsoleError = console.error;
console.error = function(...args) {
  // Call the original console.error
  originalConsoleError.apply(console, args);
  
  // Log with a distinctive prefix for easier identification
  console.log('ERROR_CAPTURE:', ...args);
};

// Add unhandled promise rejection handler
window.addEventListener('unhandledrejection', (event) => {
  console.log('UNHANDLED_PROMISE_REJECTION:', event.reason);
});

// Add global error handler
window.addEventListener('error', (event) => {
  console.log('GLOBAL_ERROR:', event.message, event.filename, event.lineno);
});

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

// Removed StrictMode to avoid double-rendering issues with Web3 providers
root.render(<App />);

// If you want to start measuring performance in your app, pass a function
// to log results (for example: reportWebVitals(console.log))
// or send to an analytics endpoint. Learn more: https://bit.ly/CRA-vitals
reportWebVitals();
