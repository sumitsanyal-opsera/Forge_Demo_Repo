import { describe, it, expect } from 'vitest';
import { execSync } from 'child_process';
import * as path from 'path';

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALID_XML = path.join(REPO_ROOT, 'test-data', 'valid.object-meta.xml');
const INVALID_XML = path.join(REPO_ROOT, 'test-data', 'invalid.object-meta.xml');

function runCli(args: string): { stdout: string; stderr: string; exitCode: number } {
  try {
    const stdout = execSync(`npx tsx src/index.ts ${args}`, {
      cwd: REPO_ROOT,
      stdio: ['ignore', 'pipe', 'pipe'],
    }).toString();
    return { stdout, stderr: '', exitCode: 0 };
  } catch (err: unknown) {
    const e = err as { stdout?: Buffer; stderr?: Buffer; status?: number };
    return {
      stdout: e.stdout?.toString() ?? '',
      stderr: e.stderr?.toString() ?? '',
      exitCode: e.status ?? 1,
    };
  }
}

describe('CLI integration', () => {
  it('exits 0 and prints VALID for a conforming XML file', () => {
    const { stdout, exitCode } = runCli(`"${VALID_XML}"`);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('VALID');
  });

  it('exits 1 and prints INVALID for an XSD-violating XML file', () => {
    const { stdout, exitCode } = runCli(`"${INVALID_XML}"`);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('INVALID');
  });

  it('exits 1 and prints usage message when no arguments provided', () => {
    const { stderr, exitCode } = runCli('');
    expect(exitCode).toBe(1);
    expect(stderr).toContain('Usage');
  });

  it('exits 1 and prints an error for a nonexistent file path', () => {
    const { stderr, exitCode } = runCli('nonexistent-file.xml');
    expect(exitCode).toBe(1);
    expect(stderr).toContain('Error');
  });
});
