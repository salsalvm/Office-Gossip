// Must stay the first import: app.ts reads process.env when it is loaded.
import './env.js';
import { app } from './app.js';

const port = Number(process.env.PORT ?? 4000);
app.listen(port, () => {
  console.log(`Office Gossip API listening on port ${port}`);
});
