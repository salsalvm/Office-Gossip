// Vercel serverless entry: serves the compiled Express app (`npm run build` → dist/).
module.exports = require('../dist/app.js').app;
