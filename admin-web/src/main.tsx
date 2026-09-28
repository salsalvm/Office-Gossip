import React from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

function App() {
  return <main><header><div className="brand">👀 OfficeGossip <span>Admin</span></div><div className="avatar">A</div></header><section className="intro"><p className="eyebrow">WORKSPACE CONTROL</p><h1>Community overview</h1><p>Manage company access and keep conversations healthy.</p></section><section className="cards"><article><small>Company requests</small><strong>Review queue</strong><p>Approve or decline requests to add a company.</p><button>Review requests</button></article><article><small>Company directory</small><strong>Bulk import</strong><p>Upload a CSV, review duplicates, then confirm.</p><button>Open companies</button></article><article><small>Community safety</small><strong>Reported posts</strong><p>Review reports and take moderation action.</p><button>Open reports</button></article></section><p className="note">Starter UI only — connect these actions to the authenticated backend.</p></main>;
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
