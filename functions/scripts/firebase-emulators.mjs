// Запуск Firebase CLI для эмуляторов.
//
//   node scripts/firebase-emulators.mjs <аргументы firebase CLI>
//
// Что добавляет к обычному `firebase`:
// * увеличенный таймаут загрузки функций: по умолчанию CLI ждёт 10 секунд,
//   а первая загрузка на Windows (с проверкой антивирусом) бывает дольше;
// * `--import <папка>` пропускается, если папки ещё нет (самый первый запуск,
//   сохранённых данных эмулятора пока нет);
// * после `emulators:exec` на Windows закрывается процесс Firestore-эмулятора
//   (Java), который CLI там не завершает, — иначе следующий запуск упрётся
//   в занятый порт.

import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const args = process.argv.slice(2);
const importAt = args.indexOf('--import');
if (importAt !== -1 && !existsSync(args[importAt + 1] ?? '')) {
  args.splice(importAt, 2);
}

// shell: true склеивает аргументы в строку — команду с пробелами
// (`"node --test …"` для emulators:exec) нужно снова взять в кавычки.
const quoted = args.map((a) => (/\s/.test(a) ? `"${a.replaceAll('"', '\\"')}"` : a));

const result = spawnSync('npx', ['firebase', ...quoted], {
  stdio: 'inherit',
  shell: true,
  env: {
    ...process.env,
    FUNCTIONS_DISCOVERY_TIMEOUT: process.env.FUNCTIONS_DISCOVERY_TIMEOUT ?? '60',
  },
});

if (process.platform === 'win32' && args[0] === 'emulators:exec') {
  stopLeftoverFirestoreEmulator();
}
process.exit(result.status ?? 1);

function stopLeftoverFirestoreEmulator() {
  try {
    const configAt = args.indexOf('--config');
    const config = JSON.parse(
      readFileSync(resolve(configAt === -1 ? 'firebase.json' : args[configAt + 1]), 'utf8'),
    );
    const port = config.emulators?.firestore?.port ?? 8080;
    const netstat = execFileSync('netstat', ['-ano', '-p', 'tcp'], { encoding: 'utf8' });
    const pids = new Set(
      netstat
        .split(/\r?\n/)
        .filter((line) => line.includes(`:${port} `) && /LISTEN/i.test(line))
        .map((line) => line.trim().split(/\s+/).at(-1)),
    );
    for (const pid of pids) {
      const commandLine = execFileSync(
        'powershell',
        ['-NoProfile', '-Command', `(Get-CimInstance Win32_Process -Filter 'ProcessId=${pid}').CommandLine`],
        { encoding: 'utf8' },
      );
      // Закрываем только сам эмулятор Firestore, ничего постороннего.
      if (commandLine.includes('cloud-firestore-emulator')) {
        execFileSync('taskkill', ['/PID', pid, '/F'], { stdio: 'ignore' });
      }
    }
  } catch {
    // Уборка — не главное: если не вышло, тесты уже отработали.
  }
}
