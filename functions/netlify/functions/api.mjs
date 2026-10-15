// Netlify Function: все вызовы приложения — POST /api/<имя функции>.
// Логика — functions/src/netlify.ts, собранная в один файл командой
// npm run build:netlify (scripts/bundle-netlify.mjs).
import { apiHandler } from '../bundle/netlify.cjs';

export default apiHandler;

export const config = { path: '/api/:fn' };
