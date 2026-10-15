// Netlify Scheduled Function: сгорание истёкших абонементов.
// Время — UTC: 21:05 UTC = 00:05 по Москве (как таймер jf-expire-daily в Yandex).
import { scheduledJob } from '../bundle/netlify.cjs';

export default scheduledJob('expireSubscriptionsDaily');

export const config = { schedule: '5 21 * * *' };
