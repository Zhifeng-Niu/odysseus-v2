#!/usr/bin/env node
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');

// Use tsx to run TypeScript directly
const { spawn } = await import('node:child_process');
const tsxPath = join(root, 'node_modules', '.bin', 'tsx');

const child = spawn(tsxPath, [join(root, 'src', 'main.ts')], {
  stdio: 'inherit',
  env: { ...process.env },
});

child.on('exit', (code) => process.exit(code ?? 0));
process.on('SIGINT', () => child.kill('SIGINT'));
process.on('SIGTERM', () => child.kill('SIGTERM'));
