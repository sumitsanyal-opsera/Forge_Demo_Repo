/**
 * SSRF protection URL allow-list.
 *
 * Validates outbound URLs against a configurable domain allow-list and performs
 * DNS rebinding detection by checking that resolved IPs are not in private ranges.
 *
 * Security properties:
 *  - Rejects all URLs not matching the allow-list patterns
 *  - Rejects IPv4/IPv6 literal addresses directly (no DNS lookup needed)
 *  - Resolves hostnames via DNS and blocks any that resolve to RFC 1918 /
 *    RFC 4193 / loopback ranges (DNS rebinding prevention)
 *  - Caches DNS results for 60 s (configurable) to stay within 5 ms per request
 *  - DNS resolver is injectable for unit testing without network calls
 */

import { promises as dns } from 'node:dns';
import { createLogger } from '../../logging/logger.js';

const logger = createLogger('UrlAllowList');

// ─── Public types ─────────────────────────────────────────────────────────────

/** Abstraction over the DNS resolver — inject a mock for tests. */
export interface DnsResolver {
  resolve4(hostname: string): Promise<string[]>;
  resolve6(hostname: string): Promise<string[]>;
}

export interface ValidationResult {
  isAllowed: boolean;
  /** Human-readable reason for rejection (undefined when allowed). */
  reason?: string;
  /** Normalised hostname extracted from the URL. */
  hostname?: string;
}

export interface UrlAllowListConfig {
  /**
   * Domain patterns to allow. Patterns beginning with '*.' are treated as
   * wildcard subdomain matches: '*.salesforce.com' matches any hostname that
   * ends with '.salesforce.com'. Exact patterns match the hostname literally.
   * Defaults to DEFAULT_ALLOWED_DOMAINS (Salesforce-specific list).
   * Can also be set via the SALESFORCE_ALLOWED_DOMAINS env var (comma-separated).
   */
  allowedDomains?: string[];
  /** Injectable DNS resolver. Defaults to Node.js dns.promises. */
  dnsResolver?: DnsResolver;
  /** DNS result TTL in milliseconds. Default: 60 000. */
  cacheTtlMs?: number;
  /**
   * Set to false to skip DNS resolution checks (useful during unit tests that
   * don't want to stub DNS at all). Default: true.
   */
  enableDnsValidation?: boolean;
  /** Timeout for DNS lookups in milliseconds. Default: 3 000. */
  dnsTimeoutMs?: number;
}

// ─── Defaults ─────────────────────────────────────────────────────────────────

/** Salesforce platform domains that are safe targets for outbound requests. */
export const DEFAULT_ALLOWED_DOMAINS = [
  '*.salesforce.com',
  '*.force.com',
  '*.lightning.force.com',
] as const;

// ─── UrlAllowList ─────────────────────────────────────────────────────────────

interface DnsCacheEntry {
  ips: string[];
  expiresAt: number;
}

export class UrlAllowList {
  private readonly patterns: string[];
  private readonly resolver: DnsResolver;
  private readonly cacheTtlMs: number;
  private readonly enableDnsValidation: boolean;
  private readonly dnsTimeoutMs: number;
  private readonly cache = new Map<string, DnsCacheEntry>();

  constructor(config?: UrlAllowListConfig) {
    this.patterns = config?.allowedDomains ?? loadAllowedDomainsFromEnv();
    this.resolver = config?.dnsResolver ?? defaultDnsResolver;
    this.cacheTtlMs = config?.cacheTtlMs ?? 60_000;
    this.enableDnsValidation = config?.enableDnsValidation ?? true;
    this.dnsTimeoutMs = config?.dnsTimeoutMs ?? 3_000;
  }

  /**
   * Validates a URL against the allow-list, then (if enabled) resolves its
   * hostname and ensures none of the resolved IPs are in private ranges.
   *
   * Never throws — all error conditions surface as `{isAllowed: false}`.
   */
  async validate(rawUrl: string): Promise<ValidationResult> {
    // ── 1. Basic presence check ──────────────────────────────────────────────
    if (rawUrl === '' || rawUrl.trim() === '') {
      return { isAllowed: false, reason: 'URL is empty or missing' };
    }

    // ── 2. URL parsing (catches malformed, missing protocol, etc.) ────────────
    let parsed: URL;
    try {
      // new URL() handles double-encoding and normalises IDN hostnames to
      // punycode, defeating unicode-homograph attacks.
      parsed = new URL(rawUrl);
    } catch {
      return {
        isAllowed: false,
        reason: `Malformed URL — cannot parse: ${sanitiseForLog(rawUrl)}`,
      };
    }

    // ── 3. Protocol allow-list ────────────────────────────────────────────────
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
      return {
        isAllowed: false,
        reason: `Protocol '${parsed.protocol}' is not allowed`,
      };
    }

    const hostname = parsed.hostname; // already normalised/lowercased by URL parser

    // ── 4. Reject IPv4 and IPv6 literal addresses immediately ─────────────────
    if (isIpLiteral(hostname)) {
      const reason = isPrivateIp(hostname)
        ? `IP literal is in a private/reserved range: ${hostname}`
        : `IP literal addresses are not permitted (use a hostname): ${hostname}`;
      return { isAllowed: false, reason, hostname };
    }

    // ── 5. Domain allow-list matching ─────────────────────────────────────────
    if (!matchesAnyPattern(hostname, this.patterns)) {
      return {
        isAllowed: false,
        reason: `Hostname '${hostname}' does not match any allowed domain pattern`,
        hostname,
      };
    }

    // ── 6. DNS rebinding check ────────────────────────────────────────────────
    if (this.enableDnsValidation) {
      const dnsResult = await this.validateDns(hostname);
      if (!dnsResult.isAllowed) {
        return dnsResult;
      }
    }

    return { isAllowed: true, hostname };
  }

  // ── DNS validation (with caching) ────────────────────────────────────────────

  private async validateDns(hostname: string): Promise<ValidationResult> {
    // Return cached result if still valid
    const cached = this.cache.get(hostname);
    if (cached !== undefined && cached.expiresAt > Date.now()) {
      return this.checkIpsForPrivateRanges(hostname, cached.ips);
    }

    // Resolve with timeout
    let allIps: string[];
    try {
      allIps = await this.resolveWithTimeout(hostname);
    } catch (err) {
      const isTimeout = err instanceof Error && err.message.includes('DNS timeout');
      logger.warn('DNS resolution failed', { hostname, timeout: isTimeout, error: String(err) });
      if (isTimeout) {
        // Signal to the middleware that it should return 503
        return {
          isAllowed: false,
          reason: `DNS_TIMEOUT:DNS resolution timed out after ${this.dnsTimeoutMs}ms for ${hostname}`,
          hostname,
        };
      }
      // NXDOMAIN or other resolution errors — block the request (fail-closed)
      return {
        isAllowed: false,
        reason: `DNS resolution failed for hostname '${hostname}'`,
        hostname,
      };
    }

    this.cache.set(hostname, { ips: allIps, expiresAt: Date.now() + this.cacheTtlMs });
    return this.checkIpsForPrivateRanges(hostname, allIps);
  }

  private async resolveWithTimeout(hostname: string): Promise<string[]> {
    const timeout = new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error(`DNS timeout for ${hostname}`)), this.dnsTimeoutMs),
    );

    const resolution = (async () => {
      const results = await Promise.allSettled([
        this.resolver.resolve4(hostname),
        this.resolver.resolve6(hostname),
      ]);
      const ips: string[] = [];
      for (const r of results) {
        if (r.status === 'fulfilled') ips.push(...r.value);
      }
      if (ips.length === 0) {
        throw new Error(`No DNS records found for ${hostname}`);
      }
      return ips;
    })();

    return Promise.race([resolution, timeout]);
  }

  private checkIpsForPrivateRanges(hostname: string, ips: string[]): ValidationResult {
    const privateIp = ips.find((ip) => isPrivateIp(ip));
    if (privateIp !== undefined) {
      return {
        isAllowed: false,
        reason: `DNS rebinding attack detected: '${hostname}' resolves to private/reserved IP ${privateIp}`,
        hostname,
      };
    }
    return { isAllowed: true, hostname };
  }
}

// ─── Domain pattern matching ──────────────────────────────────────────────────

function matchesAnyPattern(hostname: string, patterns: string[]): boolean {
  return patterns.some((p) => matchesPattern(hostname, p));
}

function matchesPattern(hostname: string, pattern: string): boolean {
  if (pattern.startsWith('*.')) {
    // e.g. '*.salesforce.com' → suffix = '.salesforce.com'
    const suffix = pattern.slice(1);
    // Require at least one character before the suffix, and ensure the suffix
    // is at a label boundary (i.e., preceded by a dot that belongs to the suffix).
    return hostname.endsWith(suffix) && hostname.length > suffix.length;
  }
  return hostname === pattern;
}

// ─── IP address helpers ───────────────────────────────────────────────────────

/**
 * Returns true if the hostname is an IPv4 or IPv6 literal address rather
 * than a domain name.
 */
function isIpLiteral(hostname: string): boolean {
  // IPv4 — four dot-separated decimal octets
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(hostname)) return true;
  // IPv6 — colons present, or wrapped in brackets (URL parser strips brackets)
  if (hostname.includes(':')) return true;
  // Bracket-enclosed (some parsers keep them)
  if (hostname.startsWith('[') && hostname.endsWith(']')) return true;
  return false;
}

/**
 * Returns true if the IP address (v4 or v6) is in a private, reserved,
 * loopback, or link-local range that should never be a target for
 * server-side outbound requests.
 *
 * Covered ranges:
 *  IPv4: 10/8, 172.16/12, 192.168/16, 127/8, 169.254/16, 100.64/10, 0/8
 *  IPv6: ::1, fc00::/7, fe80::/10, ::ffff:0:0/96 (IPv4-mapped), 2130706433 (127.0.0.1 decimal)
 */
export function isPrivateIp(ip: string): boolean {
  // Strip brackets from IPv6 literals (http://[::1]/...)
  const clean = ip.startsWith('[') ? ip.slice(1, ip.lastIndexOf(']')) : ip;

  if (clean.includes(':')) {
    return isPrivateIpv6(clean);
  }
  // Plain decimal IPv4 integer representation (e.g. http://2130706433 for 127.0.0.1)
  if (/^\d+$/.test(clean)) {
    return isPrivateIpv4FromInt(parseInt(clean, 10));
  }
  return isPrivateIpv4(clean);
}

function isPrivateIpv4(ip: string): boolean {
  const parts = ip.split('.').map(Number);
  if (parts.length !== 4 || parts.some((n) => isNaN(n) || n < 0 || n > 255)) {
    return false;
  }
  const [a = 0, b = 0] = parts;
  if (a === 10) return true;                              // 10.0.0.0/8
  if (a === 172 && b >= 16 && b <= 31) return true;      // 172.16.0.0/12
  if (a === 192 && b === 168) return true;                // 192.168.0.0/16
  if (a === 127) return true;                             // 127.0.0.0/8 loopback
  if (a === 169 && b === 254) return true;                // 169.254.0.0/16 link-local
  if (a === 100 && b >= 64 && b <= 127) return true;     // 100.64.0.0/10 CGNAT
  if (a === 0) return true;                               // 0.0.0.0/8
  return false;
}

function isPrivateIpv4FromInt(n: number): boolean {
  // Reconstruct dotted-decimal from 32-bit integer
  const a = (n >>> 24) & 0xff;
  const b = (n >>> 16) & 0xff;
  return isPrivateIpv4(`${a}.${b}.${(n >>> 8) & 0xff}.${n & 0xff}`);
}

function isPrivateIpv6(ip: string): boolean {
  const lower = ip.toLowerCase().replace(/^::ffff:/, ''); // strip IPv4-mapped prefix for recheck

  // Loopback
  if (lower === '::1' || lower === '0:0:0:0:0:0:0:1') return true;
  // Unique local (fc00::/7 → fc** and fd**)
  if (lower.startsWith('fc') || lower.startsWith('fd')) return true;
  // Link-local (fe80::/10)
  if (lower.startsWith('fe8') || lower.startsWith('fe9') ||
      lower.startsWith('fea') || lower.startsWith('feb')) return true;
  // IPv4-mapped (::ffff:w.x.y.z) — if prefix stripped, check remaining as IPv4
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(lower)) return isPrivateIpv4(lower);
  return false;
}

// ─── Environment configuration ────────────────────────────────────────────────

function loadAllowedDomainsFromEnv(): string[] {
  const raw = process.env['SALESFORCE_ALLOWED_DOMAINS'];
  if (raw !== undefined && raw.trim() !== '') {
    const domains = raw.split(',').map((d) => d.trim()).filter((d) => d.length > 0);
    if (domains.length > 0) return domains;
  }
  return [...DEFAULT_ALLOWED_DOMAINS];
}

// ─── Default DNS resolver (Node.js dns.promises) ─────────────────────────────

const defaultDnsResolver: DnsResolver = {
  resolve4: (hostname) => dns.resolve4(hostname),
  resolve6: (hostname) => dns.resolve6(hostname),
};

// ─── Utility ──────────────────────────────────────────────────────────────────

/** Strips query params and auth info from a URL for safe logging. */
export function sanitiseUrlForLog(rawUrl: string): string {
  try {
    const parsed = new URL(rawUrl);
    parsed.search = '';
    parsed.username = '';
    parsed.password = '';
    return parsed.toString();
  } catch {
    return rawUrl.slice(0, 100);
  }
}

function sanitiseForLog(rawUrl: string): string {
  return rawUrl.slice(0, 200).replace(/[\r\n]/g, '');
}
