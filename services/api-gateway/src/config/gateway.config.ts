export interface GatewayConfig {
  bodySizeLimitBytes: number;
  rateLimitWindowMs: number;
  rateLimitMaxRequests: number;
  bruteForceWindowMs: number;
  bruteForceMaxFailures: number;
  bruteForceLockoutMs: number;
  corsAllowedOrigin: string;
  wafEnabled: boolean;
}

export const defaultGatewayConfig: GatewayConfig = {
  bodySizeLimitBytes: 1 * 1024 * 1024, // 1MB
  rateLimitWindowMs: 60 * 1000,         // 1 minute
  rateLimitMaxRequests: 100,
  bruteForceWindowMs: 15 * 60 * 1000,  // 15 minutes
  bruteForceMaxFailures: 5,
  bruteForceLockoutMs: 30 * 60 * 1000, // 30 minutes
  corsAllowedOrigin: process.env['OPSERA_DASHBOARD_ORIGIN'] ?? 'https://app.opsera.io',
  wafEnabled: process.env['WAF_ENABLED'] !== 'false',
};

export function loadGatewayConfig(overrides: Partial<GatewayConfig> = {}): GatewayConfig {
  return { ...defaultGatewayConfig, ...overrides };
}
