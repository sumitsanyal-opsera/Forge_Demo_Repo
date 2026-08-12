import { describe, it, expect } from 'vitest';
import { execSync } from 'child_process';
import * as path from 'path';

const REPO_ROOT = path.resolve(__dirname, '../..');
const CLI_PATH = path.join(REPO_ROOT, 'src', 'cli.ts');
const VALID_DIR = path.join(REPO_ROOT, 'test', 'fixtures', 'valid');
const INVALID_DIR = path.join(REPO_ROOT, 'test', 'fixtures', 'invalid');

function runCli(args = ''): { output: string; exitCode: number } {
  const cmd = args
    ? `npx tsx "${CLI_PATH}" "${args}"`
    : `npx tsx "${CLI_PATH}"`;
  try {
    const stdout = execSync(cmd, { cwd: REPO_ROOT, encoding: 'utf-8' });
    return { output: stdout, exitCode: 0 };
  } catch (err: any) {
    return {
      output: String(err.stdout ?? '') + String(err.stderr ?? ''),
      exitCode: typeof err.status === 'number' ? err.status : 1,
    };
  }
}

describe('CLI E2E', () => {
  it('exits 0 and prints "Validation passed" for a directory of valid XML files', () => {
    const { output, exitCode } = runCli(VALID_DIR);
    expect(exitCode).toBe(0);
    expect(output).toContain('Validation passed');
    expect(output).toContain('PASS:');
  });

  it('exits 1 and prints "Validation failed" for a directory containing invalid XML', () => {
    const { output, exitCode } = runCli(INVALID_DIR);
    expect(exitCode).toBe(1);
    expect(output).toContain('Validation failed');
    expect(output).toContain('FAIL:');
    expect(output).toMatch(/Line \d+/);
  });

  it('exits 2 and prints usage when no directory argument is given', () => {
    const { output, exitCode } = runCli();
    expect(exitCode).toBe(2);
    expect(output).toContain('Usage:');
  });
});
