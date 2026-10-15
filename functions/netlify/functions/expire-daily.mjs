// Netlify Scheduled Function: сгорание истёкших абонементов.
// Время — UTC: 21:05 UTC = 00:05 по Москве (как таймер jf-expire-daily в Yandex).
import { scheduledJob } from '../../lib/netlify.js';

export default scheduledJob('expireSubscriptionsDaily');

export const config = { schedule: '5 21 * * *', region: 'fra' };
