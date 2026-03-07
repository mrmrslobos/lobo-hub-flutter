import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { PurchasesProvider } from './contexts/PurchasesContext';
import { ErrorBoundary } from './components/ErrorBoundary';

const rootElement = document.getElementById('root');
const bootLoader = document.getElementById('boot-loader');

if (!rootElement) {
  throw new Error('Could not find root element to mount to');
}

try {
  const root = ReactDOM.createRoot(rootElement);
  root.render(
    <React.StrictMode>
      <ErrorBoundary>
        <PurchasesProvider>
          <App />
        </PurchasesProvider>
      </ErrorBoundary>
    </React.StrictMode>
  );

  setTimeout(() => {
    if (bootLoader) {
      bootLoader.style.opacity = '0';
      setTimeout(() => bootLoader.remove(), 500);
    }
  }, 300);
} catch (error) {
  console.error('Critical Render Error:', error);
  if (bootLoader) bootLoader.remove();
  rootElement.innerHTML = `
    <div style="padding: 40px; text-align: center; font-family: sans-serif;">
      <h1 style="color: #ef4444;">Initialization Failed</h1>
      <p style="color: #71717a;">${error instanceof Error ? error.message : String(error)}</p>
      <button onclick="location.reload()" style="margin-top: 1rem; padding: 0.5rem 1rem; background: #6366f1; color: white; border: none; border-radius: 8px;">Retry</button>
    </div>
  `;
}


if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((error) => {
      console.warn('Service worker registration failed:', error);
    });
  });
}
