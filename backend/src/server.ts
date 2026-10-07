import dotenv from 'dotenv';

// Not `.env`: Firebase uploads that file as production config on deploy.
dotenv.config({ path: '.env.local' });
import { app } from './app.js';

const port = Number(process.env.PORT ?? 4000);
app.listen(port, () => {
  console.log(`Office Gossip API listening on port ${port}`);
});
