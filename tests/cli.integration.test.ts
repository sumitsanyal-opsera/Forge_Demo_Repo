import { describe, it, expect } from 'vitest';
import { execSync } from 'child_process';
import * as path from 'path';

const REPO_ROOT = path.resolve(__dirname, '..');
const FIXTURES_DIR = path.join(REPO_ROOT, 'fixtures');

function runCli(args: string[] = []): { stdout: string; stderr: string; exitCode: number } {
  const quotedArgs = args.map((a) => `"${a}"`).join(' ');
  const cmd = `npx tsx "src/cli.ts" ${quotedArgs}`;
  try {
    const stdout = execSync(cmd, { cwd: REPO_ROOT, encoding: 'utf-8' });
    return { stdout, stderr: '', exitCode: 0 };
  } catch (err: unknown) {
    const e = err as { stdout?: string; stderr?: string; status?: number };
    return {
      stdout: String(e.stdout ?? ''),
      stderr: String(e.stderr ?? ''),
      exitCode: typeof e.status === 'number' ? e.status : 1,
    };
  }
}

describe('CLI end-to-end (WO-075)', () => {
  it('exits 0 and prints PASS for valid XML conforming to the XSD', () => {
    const { stdout, exitCode } = runCli([
      path.join(FIXTURES_DIR, 'validAccount.object-meta.xml'),
      path.join(FIXTURES_DIR, 'testMetadata.xsd'),
    ]);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('PASS');
  });

  it('exits 1 and prints FAIL with error lines for invalid XML', () => {
    const { stdout, exitCode } = runCli([
      path.join(FIXTURES_DIR, 'invalidProfile.profile-meta.xml'),
      path.join(FIXTURES_DIR, 'testMetadata.xsd'),
    ]);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('FAIL');
    expect(stdout).toContain('  - ');
  });

  it('exits non-zero and prints usage when no arguments are provided', () => {
    const { stderr, exitCode } = runCli([]);
    expect(exitCode).not.toBe(0);
    expect(stderr).toContain('Usage');
  });

  it('exits 1 and prints an error for a nonexistent XML file', () => {
    const { stderr, exitCode } = runCli([
      '/nonexistent/file.xml',
      path.join(FIXTURES_DIR, 'testMetadata.xsd'),
    ]);
    expect(exitCode).toBe(1);
    expect(stderr).toContain('Error');
  });
});
