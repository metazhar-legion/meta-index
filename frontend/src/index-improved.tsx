import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';

// Import both versions for comparison
import App from './App';
import ImprovedApp from './ImprovedApp';
import reportWebVitals from './reportWebVitals';

// Version selector component
const VersionSelector: React.FC = () => {
  const [useImproved, setUseImproved] = React.useState(true);
  
  const AppComponent = useImproved ? ImprovedApp : App;
  
  return (
    <div>
      {/* Version toggle (only in development) */}
      {process.env.NODE_ENV === 'development' && (
        <div
          style={{
            position: 'fixed',
            top: 10,
            right: 10,
            zIndex: 9999,
            background: useImproved ? '#4caf50' : '#ff9800',
            color: 'white',
            padding: '8px 16px',
            borderRadius: '20px',
            fontSize: '14px',
            fontWeight: 'bold',
            cursor: 'pointer',
            boxShadow: '0 2px 8px rgba(0,0,0,0.2)',
            userSelect: 'none',
          }}
          onClick={() => setUseImproved(!useImproved)}
          title="Click to toggle between original and improved versions"
        >
          {useImproved ? '🚀 Enhanced Version' : '📱 Original Version'}
        </div>
      )}
      
      <AppComponent />
    </div>
  );
};

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

// Use environment variable to determine which version to show
const shouldUseImproved = process.env.REACT_APP_USE_IMPROVED !== 'false';

root.render(
  <React.StrictMode>
    {shouldUseImproved ? <VersionSelector /> : <App />}
  </React.StrictMode>
);

// If you want to start measuring performance in your app, pass a function
// to log results (for example: reportWebVitals(console.log))
// or send to an analytics endpoint. Learn more: https://bit.ly/CRA-vitals
reportWebVitals();