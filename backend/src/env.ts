import dotenv from 'dotenv';

// Not `.env`: Firebase uploads that file as production config on deploy.
dotenv.config({ path: '.env.local' });
