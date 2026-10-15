// Netlify Function: все вызовы приложения — POST /api/<имя функции>.
// Логика — functions/src/netlify.ts (собирается в lib/ командой npm run build).
import { apiHandler } from '../../lib/netlify.js';

export default apiHandler;

export const config = { path: '/api/:fn' };
