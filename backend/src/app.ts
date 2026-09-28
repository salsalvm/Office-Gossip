import express from 'express';
import cors from 'cors';

export const app = express();
app.use(cors());
app.use(express.json({ limit: '32kb' }));

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'office-gossip-api' });
});

// Add authenticated routes here. Validate inputs and enforce company membership
// and role checks on the server before accessing data.
