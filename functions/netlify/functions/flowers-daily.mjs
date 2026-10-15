// Netlify Scheduled Function: цветы месяца (функция сама решает, пора ли).
// Время — UTC: 21:10 UTC = 00:10 по Москве (как таймер jf-flowers-daily в Yandex).
import { scheduledJob } from '../../lib/netlify.js';

export default scheduledJob('assignMonthlyFlowers');

export const config = { schedule: '10 21 * * *' };
