import { UrlAllowList, isPrivateIp, DEFAULT_ALLOWED_DOMAINS } from '../UrlAllowList.js';
import type { DnsResolver } from '../UrlAllowList.js';

// ─── Mock DNS resolver ────────────────────────────────────────────────────────

function makeDnsResolver(v4?: string[], v6?: string[]): DnsResolver {
  return {
    resolve4: v4 !== undefined
      ? () => Promise.resolve(v4)
      : () => Promise.reject(new Error('ENOTFOUND')),
    resolve6: v6 !== undefined
      ? () => Promise.resolve(v6)
      : () => Promise.reject(new Error('ENOTFOUND')),
  };
}

function makeAllowList(dnsIpv4?: string[], dnsIpv6?: string[]): UrlAllowList {
  return new UrlAllowList({
    dnsResolver: makeDnsResolver(dnsIpv4 ?? ['104.193.30.10'], dnsIpv6),
  });
}

function makeAllowListNoDns(): UrlAllowList {
  return new UrlAllowList({ enableDnsValidation: false });
}

// ─── isPrivateIp unit tests ───────────────────────────────────────────────────

describe('isPrivateIp', () => {
  it.each([
    '10.0.0.1', '10.255.255.255',
    '172.16.0.1', '172.31.255.255',
    '192.168.0.1', '192.168.255.254',
    '127.0.0.1', '127.0.0.0',
    '169.254.0.1', '169.254.255.254',
    '100.64.0.1', '100.127.255.255',
    '0.0.0.1',
  ])('returns true for private IPv4 %s', (ip) => {
    expect(isPrivateIp(ip)).toBe(true);
  });

  it.each([
    '8.8.8.8', '1.1.1.1', '104.193.30.10', '52.0.0.1',
  ])('returns false for public IPv4 %s', (ip) => {
    expect(isPrivateIp(ip)).toBe(false);
  });

  it.each([
    '::1',
    'fc00::1', 'fd12:3456:789a:1::1',
    'fe80::1', 'fe90::1', 'fea0::1', 'feb0::1',
    '[::1]',
  ])('returns true for private/reserved IPv6 %s', (ip) => {
    expect(isPrivateIp(ip)).toBe(true);
  });

  it.each([
    '2001:db8::1', '2606:4700::1',
  ])('returns false for public IPv6 %s', (ip) => {
    expect(isPrivateIp(ip)).toBe(false);
  });

  it('returns true for IPv4-mapped ::ffff:10.0.0.1', () => {
    expect(isPrivateIp('::ffff:10.0.0.1')).toBe(true);
  });

  it('returns true for IPv4-mapped ::ffff:192.168.1.1', () => {
    expect(isPrivateIp('::ffff:192.168.1.1')).toBe(true);
  });
});

// ─── Domain pattern matching ──────────────────────────────────────────────────

describe('UrlAllowList — domain allow-list matching', () => {
  const list = makeAllowListNoDns();

  it('allows login.salesforce.com', async () => {
    const r = await list.validate('https://login.salesforce.com');
    expect(r.isAllowed).toBe(true);
  });

  it('allows myorg.my.salesforce.com (multi-level subdomain)', async () => {
    const r = await list.validate('https://myorg.my.salesforce.com/services/data/');
    expect(r.isAllowed).toBe(true);
  });

  it('allows myorg.lightning.force.com', async () => {
    const r = await list.validate('https://myorg.lightning.force.com');
    expect(r.isAllowed).toBe(true);
  });

  it('allows site.force.com', async () => {
    const r = await list.validate('https://site.force.com');
    expect(r.isAllowed).toBe(true);
  });

  it('rejects evil.com', async () => {
    const r = await list.validate('https://evil.com');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toContain('evil.com');
  });

  it('rejects salesforce.com.evil.com (suffix attack)', async () => {
    const r = await list.validate('https://salesforce.com.evil.com');
    expect(r.isAllowed).toBe(false);
  });

  it('rejects evils-salesforce.com (prefix attack)', async () => {
    const r = await list.validate('https://evils-salesforce.com');
    expect(r.isAllowed).toBe(false);
  });

  it('rejects internal.corp.local', async () => {
    const r = await list.validate('https://internal.corp.local');
    expect(r.isAllowed).toBe(false);
  });
});

// ─── IP literal rejection ─────────────────────────────────────────────────────

describe('UrlAllowList — IP literal rejection', () => {
  const list = makeAllowListNoDns();

  it('rejects http://10.0.0.1', async () => {
    const r = await list.validate('http://10.0.0.1');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toMatch(/private|IP literal/i);
  });

  it('rejects http://[::1]', async () => {
    const r = await list.validate('http://[::1]');
    expect(r.isAllowed).toBe(false);
  });

  it('rejects http://192.168.1.1/path', async () => {
    const r = await list.validate('http://192.168.1.1/path');
    expect(r.isAllowed).toBe(false);
  });

  it('rejects public IP literals too (policy: hostname required)', async () => {
    const r = await list.validate('https://8.8.8.8');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toMatch(/IP literal/i);
  });
});

// ─── Malformed URL handling ───────────────────────────────────────────────────

describe('UrlAllowList — malformed URLs', () => {
  const list = makeAllowListNoDns();

  it('rejects empty string', async () => {
    const r = await list.validate('');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toContain('empty');
  });

  it('rejects whitespace-only string', async () => {
    const r = await list.validate('   ');
    expect(r.isAllowed).toBe(false);
  });

  it('rejects string without protocol', async () => {
    const r = await list.validate('login.salesforce.com');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toContain('Malformed');
  });

  it('rejects javascript: protocol', async () => {
    const r = await list.validate('javascript:alert(1)');
    expect(r.isAllowed).toBe(false);
  });

  it('rejects file: protocol', async () => {
    const r = await list.validate('file:///etc/passwd');
    expect(r.isAllowed).toBe(false);
  });

  it('rejects ftp: protocol', async () => {
    const r = await list.validate('ftp://login.salesforce.com');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toContain('Protocol');
  });

  it('rejects data: URI', async () => {
    const r = await list.validate('data:text/html,<script>alert(1)</script>');
    expect(r.isAllowed).toBe(false);
  });
});

// ─── DNS rebinding prevention ─────────────────────────────────────────────────

describe('UrlAllowList — DNS rebinding prevention', () => {
  it('blocks when DNS resolves to private 10.x IP', async () => {
    const list = makeAllowList(['10.0.0.1']);
    const r = await list.validate('https://login.salesforce.com');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toContain('rebinding');
    expect(r.reason).toContain('10.0.0.1');
  });

  it('blocks when DNS resolves to 127.0.0.1', async () => {
    const list = makeAllowList(['127.0.0.1']);
    const r = await list.validate('https://login.salesforce.com');
    expect(r.isAllowed).toBe(false);
  });

  it('blocks when DNS resolves to 192.168.x.x', async () => {
    const list = makeAllowList(['192.168.1.100']);
    const r = await list.validate('https://login.salesforce.com');
    expect(r.isAllowed).toBe(false);
  });

  it('blocks when IPv6 DNS resolves to ::1', async () => {
    const list = makeAllowList(undefined, ['::1']);
    const r = await list.validate('https://login.salesforce.com');
    expect(r.isAllowed).toBe(false);
  });

  it('allows when DNS resolves to a public IP', async () => {
    const list = makeAllowList(['104.193.30.10']);
    const r = await list.validate('https://login.salesforce.com');
    expect(r.isAllowed).toBe(true);
  });

  it('blocks when DNS fails (fail-closed policy)', async () => {
    const failResolver: DnsResolver = {
      resolve4: () => Promise.reject(new Error('ENOTFOUND')),
      resolve6: () => Promise.reject(new Error('ENOTFOUND')),
    };
    const list = new UrlAllowList({ dnsResolver: failResolver });
    const r = await list.validate('https://login.salesforce.com');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toContain('DNS resolution failed');
  });

  it('returns DNS_TIMEOUT reason on timeout', async () => {
    const slowResolver: DnsResolver = {
      resolve4: () => new Promise((resolve) => setTimeout(() => resolve(['1.2.3.4']), 5_000)),
      resolve6: () => Promise.reject(new Error('ENOTFOUND')),
    };
    const list = new UrlAllowList({ dnsResolver: slowResolver, dnsTimeoutMs: 50 });
    const r = await list.validate('https://login.salesforce.com');
    expect(r.isAllowed).toBe(false);
    expect(r.reason).toContain('DNS_TIMEOUT');
  }, 10_000);
});

// ─── DNS cache ────────────────────────────────────────────────────────────────

describe('UrlAllowList — DNS cache', () => {
  it('reuses cached DNS result within TTL', async () => {
    let callCount = 0;
    const resolver: DnsResolver = {
      resolve4: () => { callCount++; return Promise.resolve(['104.193.30.10']); },
      resolve6: () => Promise.reject(new Error('ENOTFOUND')),
    };
    const list = new UrlAllowList({ dnsResolver: resolver, cacheTtlMs: 60_000 });

    await list.validate('https://login.salesforce.com');
    await list.validate('https://login.salesforce.com');
    await list.validate('https://login.salesforce.com');

    expect(callCount).toBe(1); // DNS called only once; subsequent calls use cache
  });

  it('re-resolves after TTL expires', async () => {
    let callCount = 0;
    const resolver: DnsResolver = {
      resolve4: () => { callCount++; return Promise.resolve(['104.193.30.10']); },
      resolve6: () => Promise.reject(new Error('ENOTFOUND')),
    };
    const list = new UrlAllowList({ dnsResolver: resolver, cacheTtlMs: 1 }); // 1ms TTL

    await list.validate('https://login.salesforce.com');
    await new Promise((r) => setTimeout(r, 10)); // wait for TTL to expire
    await list.validate('https://login.salesforce.com');

    expect(callCount).toBe(2);
  });
});

// ─── Custom allow-list configuration ─────────────────────────────────────────

describe('UrlAllowList — custom configuration', () => {
  it('respects custom allowedDomains', async () => {
    const list = new UrlAllowList({
      allowedDomains: ['*.example.internal'],
      enableDnsValidation: false,
    });
    const allowed = await list.validate('https://api.example.internal');
    expect(allowed.isAllowed).toBe(true);

    const blocked = await list.validate('https://login.salesforce.com');
    expect(blocked.isAllowed).toBe(false);
  });

  it('exposes DEFAULT_ALLOWED_DOMAINS constant', () => {
    expect(DEFAULT_ALLOWED_DOMAINS).toContain('*.salesforce.com');
    expect(DEFAULT_ALLOWED_DOMAINS).toContain('*.force.com');
  });
});

// ─── Edge cases ───────────────────────────────────────────────────────────────

describe('UrlAllowList — edge cases', () => {
  const list = makeAllowListNoDns();

  it('rejects URL with embedded credentials (user:pass@evil.com)', async () => {
    const r = await list.validate('https://user:pass@evil.com');
    expect(r.isAllowed).toBe(false);
  });

  it('accepts URL with embedded credentials pointing at allowed domain', async () => {
    // The URL parser normalises user:pass@ — hostname is still salesforce.com
    const r = await list.validate('https://user:token@login.salesforce.com/oauth2/token');
    expect(r.isAllowed).toBe(true);
  });

  it('rejects URLs with query params pointing at disallowed host (query params irrelevant)', async () => {
    // targetUrl itself points to salesforce but just has evil query params — that's OK
    const r = await list.validate('https://login.salesforce.com?returnUrl=https://evil.com');
    expect(r.isAllowed).toBe(true); // hostname is login.salesforce.com → allowed
  });

  it('allows login.salesforce.com with non-standard port', async () => {
    const r = await list.validate('https://login.salesforce.com:8443/oauth');
    expect(r.isAllowed).toBe(true);
  });
});
