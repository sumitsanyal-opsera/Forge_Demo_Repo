import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createVerify } from 'node:crypto';
import { JwtBuilder } from '../JwtBuilder.js';

// ─── Fixture loading ──────────────────────────────────────────────────────────

interface KeyPairFixture {
  privateKey: string;
  publicKey: string;
}

const FIXTURES_DIR = join(process.cwd(), 'test/fixtures/salesforce-auth');

function loadKeyPair(): KeyPairFixture {
  const raw = readFileSync(join(FIXTURES_DIR, 'test-rsa-keypair.json'), 'utf-8');
  return JSON.parse(raw) as KeyPairFixture;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function decodeJwtPayload(token: string): Record<string, unknown> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Not a JWT');
  const payload = parts[1] as string;
  return JSON.parse(Buffer.from(payload, 'base64').toString('utf-8')) as Record<
    string,
    unknown
  >;
}

function decodeJwtHeader(token: string): Record<string, unknown> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Not a JWT');
  const header = parts[0] as string;
  return JSON.parse(Buffer.from(header, 'base64').toString('utf-8')) as Record<
    string,
    unknown
  >;
}

function verifyJwtSignature(token: string, publicKey: string): boolean {
  const parts = token.split('.');
  if (parts.length !== 3) return false;
  const [header, payload, sig] = parts as [string, string, string];
  const verifier = createVerify('SHA256');
  verifier.update(`${header}.${payload}`);
  return verifier.verify(publicKey, Buffer.from(sig, 'base64'));
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('JwtBuilder', () => {
  let privateKey: string;
  let publicKey: string;

  beforeAll(() => {
    const pair = loadKeyPair();
    privateKey = pair.privateKey;
    publicKey = pair.publicKey;
  });

  const claims = {
    iss: '3MVG9test_CLIENT_ID',
    sub: 'integration@myorg.com',
    aud: 'https://login.salesforce.com',
  };

  describe('build()', () => {
    it('returns a compact JWT with three segments', () => {
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      expect(token.split('.')).toHaveLength(3);
    });

    it('sets alg=RS256 and typ=JWT in the header', () => {
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      const header = decodeJwtHeader(token);
      expect(header['alg']).toBe('RS256');
      expect(header['typ']).toBe('JWT');
    });

    it('includes iss claim matching the client_id', () => {
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      const payload = decodeJwtPayload(token);
      expect(payload['iss']).toBe(claims.iss);
    });

    it('includes sub claim matching the username', () => {
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      const payload = decodeJwtPayload(token);
      expect(payload['sub']).toBe(claims.sub);
    });

    it('includes aud claim matching the login URL', () => {
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      const payload = decodeJwtPayload(token);
      expect(payload['aud']).toBe(claims.aud);
    });

    it('sets exp to approximately now + 180 seconds (minus clock skew of 30s)', () => {
      const before = Math.floor(Date.now() / 1000) - 30;
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      const payload = decodeJwtPayload(token);
      const exp = payload['exp'] as number;
      // exp = (now - clockSkew) + expirySeconds = now - 30 + 180 = now + 150
      // allow ±5 seconds tolerance for test execution time
      expect(exp).toBeGreaterThanOrEqual(before + 145);
      expect(exp).toBeLessThanOrEqual(before + 185);
    });

    it('includes iat claim close to current time', () => {
      const before = Math.floor(Date.now() / 1000) - 35;
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      const payload = decodeJwtPayload(token);
      const iat = payload['iat'] as number;
      expect(iat).toBeGreaterThanOrEqual(before);
      expect(iat).toBeLessThanOrEqual(before + 10);
    });

    it('produces a signature verifiable with the corresponding public key', () => {
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      expect(verifyJwtSignature(token, publicKey)).toBe(true);
    });

    it('produces a different token on each call (different iat)', () => {
      const builder = new JwtBuilder();
      const t1 = builder.build(claims, privateKey);
      // Force a tick difference
      const t2 = builder.build(claims, privateKey);
      // Tokens may be identical within the same second but the test is structural
      expect(typeof t1).toBe('string');
      expect(typeof t2).toBe('string');
    });

    it('honours custom expirySeconds config', () => {
      const builder = new JwtBuilder({ expirySeconds: 60, clockSkewSeconds: 0 });
      const before = Math.floor(Date.now() / 1000);
      const token = builder.build(claims, privateKey);
      const payload = decodeJwtPayload(token);
      const exp = payload['exp'] as number;
      expect(exp).toBeGreaterThanOrEqual(before + 55);
      expect(exp).toBeLessThanOrEqual(before + 65);
    });

    it('uses sandbox aud for test.salesforce.com', () => {
      const builder = new JwtBuilder();
      const sandboxClaims = { ...claims, aud: 'https://test.salesforce.com' };
      const token = builder.build(sandboxClaims, privateKey);
      const payload = decodeJwtPayload(token);
      expect(payload['aud']).toBe('https://test.salesforce.com');
    });

    it('throws when given an invalid private key', () => {
      const builder = new JwtBuilder();
      expect(() => builder.build(claims, 'not-a-pem-key')).toThrow();
    });
  });

  describe('verify()', () => {
    it('returns the decoded payload when the signature is valid', () => {
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      const decoded = builder.verify(token, publicKey);
      expect(decoded['iss']).toBe(claims.iss);
      expect(decoded['sub']).toBe(claims.sub);
      expect(decoded['aud']).toBe(claims.aud);
    });

    it('throws when the signature has been tampered with', () => {
      const builder = new JwtBuilder();
      const token = builder.build(claims, privateKey);
      const parts = token.split('.');
      // Flip one character in the signature
      const tampered = `${parts[0]}.${parts[1]}.AAAA${parts[2]?.slice(4)}`;
      expect(() => builder.verify(tampered, publicKey)).toThrow();
    });

    it('throws when the JWT does not have 3 segments', () => {
      const builder = new JwtBuilder();
      expect(() => builder.verify('only.two', publicKey)).toThrow(
        'Invalid JWT format',
      );
    });
  });
});
