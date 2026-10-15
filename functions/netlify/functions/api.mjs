// Netlify Function: все вызовы приложения — POST /api/<имя функции>.
// Логика — functions/src/netlify.ts (собирается в lib/ командой npm run build).
import { apiHandler } from '../../lib/netlify.js';

export default apiHandler;

// Регион — Франкфурт (fra): там же Firestore (europe-west3), запросы к базе быстрее.
export const config = { path: '/api/:fn', region: 'fra' };
