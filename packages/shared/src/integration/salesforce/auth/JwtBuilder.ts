/**
 * JWT Builder for Salesforce OAuth 2.0 JWT Bearer Flow.
 *
 * Constructs and RS256-signs a JWT assertion with the claims required by
 * Salesforce's token exchange endpoint. Expiry is fixed at 180 seconds per
 * the Salesforce specification (maximum allowed by the platform).
 *
 * Security: the private key is never logged. Pass it only from the key-loading
 * utility and do not interpolate it into any log message.
 */

import { createSign, createVerify } from 'node:crypto';

export interface JwtClaims {
  /** Connected App consumer key (client_id). */
  iss: string;
  /** Salesforce username of the integration user. */
  sub: string;
  /**
   * Token endpoint: 'https://login.salesforce.com' for production,
   * 'https://test.salesforce.com' for sandbox.
   */
  aud: string;
}

export interface JwtBuilderConfig {
  /** JWT TTL in seconds. Salesforce maximum is 180. Default: 180. */
  expirySeconds?: number;
  /**
   * Clock skew tolerance subtracted from `now` when computing `exp`, so
   * requests reach Salesforce before expiry even on slightly skewed clocks.
   * Default: 30 seconds.
   */
  clockSkewSeconds?: number;
}

function base64url(data: string | Buffer): string {
  const buf = typeof data === 'string' ? Buffer.from(data, 'utf8') : data;
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

export class JwtBuilder {
  private readonly expirySeconds: number;
  private readonly clockSkewSeconds: number;

  constructor(config: JwtBuilderConfig = {}) {
    this.expirySeconds = config.expirySeconds ?? 180;
    this.clockSkewSeconds = config.clockSkewSeconds ?? 30;
  }

  /**
   * Builds and signs a JWT assertion for the Salesforce JWT Bearer Flow.
   *
   * @param claims     `iss`, `sub`, `aud` per SF spec.
   * @param privateKey PEM-encoded RSA private key (PKCS#8 or PKCS#1).
   * @returns          Compact JWS string (header.payload.signature).
   */
  build(claims: JwtClaims, privateKey: string): string {
    const now = Math.floor(Date.now() / 1000) - this.clockSkewSeconds;
    const exp = now + this.expirySeconds;

    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const payload = base64url(
      JSON.stringify({
        iss: claims.iss,
        sub: claims.sub,
        aud: claims.aud,
        exp,
        iat: now,
      }),
    );

    const signingInput = `${header}.${payload}`;
    const signer = createSign('SHA256');
    signer.update(signingInput);
    const signature = base64url(signer.sign(privateKey));

    return `${signingInput}.${signature}`;
  }

  /**
   * Verifies a JWT assertion against a public key.
   * For use in tests only — callers never need to verify their own assertions.
   */
  verify(token: string, publicKey: string): Record<string, unknown> {
    const parts = token.split('.');
    if (parts.length !== 3) {
      throw new Error('Invalid JWT format: expected 3 segments.');
    }
    const [header, payload, signature] = parts as [string, string, string];
    const signingInput = `${header}.${payload}`;

    const verifier = createVerify('SHA256');
    verifier.update(signingInput);
    const sigBuffer = Buffer.from(signature, 'base64');
    if (!verifier.verify(publicKey, sigBuffer)) {
      throw new Error('JWT signature verification failed.');
    }

    const decodedPayload = Buffer.from(payload, 'base64').toString('utf8');
    return JSON.parse(decodedPayload) as Record<string, unknown>;
  }
}
