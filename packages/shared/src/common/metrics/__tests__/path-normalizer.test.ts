import { describe, it, expect } from '@jest/globals';
import { normalizePath, isExcludedPath } from '../path-normalizer.js';

describe('normalizePath', () => {
  it('replaces a UUID segment with :id', () => {
    expect(normalizePath('/api/v1/pipelines/abc12345-1234-1234-1234-abc123456789'))
      .toBe('/api/v1/pipelines/:id');
  });

  it('replaces multiple UUID segments', () => {
    expect(normalizePath('/api/v1/orgs/abc12345-1234-1234-1234-abc123456789/pipelines/def12345-1234-1234-1234-def123456789'))
      .toBe('/api/v1/orgs/:id/pipelines/:id');
  });

  it('replaces nested UUID followed by a path segment', () => {
    expect(normalizePath('/api/v1/pipelines/abc12345-1234-1234-1234-abc123456789/baseline'))
      .toBe('/api/v1/pipelines/:id/baseline');
  });

  it('replaces numeric ID segments', () => {
    expect(normalizePath('/api/v1/orgs/42/runs')).toBe('/api/v1/orgs/:id/runs');
  });

  it('replaces trailing numeric IDs', () => {
    expect(normalizePath('/api/v1/users/12345')).toBe('/api/v1/users/:id');
  });

  it('leaves version segments intact', () => {
    expect(normalizePath('/api/v1/health')).toBe('/api/v1/health');
  });

  it('leaves paths with no IDs unchanged', () => {
    expect(normalizePath('/api/v1/pipelines')).toBe('/api/v1/pipelines');
  });

  it('handles root path', () => {
    expect(normalizePath('/')).toBe('/');
  });
});

describe('isExcludedPath', () => {
  it('excludes /metrics', () => {
    expect(isExcludedPath('/metrics')).toBe(true);
  });

  it('excludes /health', () => {
    expect(isExcludedPath('/health')).toBe(true);
  });

  it('excludes /health/salesforce', () => {
    expect(isExcludedPath('/health/salesforce')).toBe(true);
  });

  it('does not exclude /api/v1/pipelines', () => {
    expect(isExcludedPath('/api/v1/pipelines')).toBe(false);
  });

  it('does not exclude /', () => {
    expect(isExcludedPath('/')).toBe(false);
  });

  it('strips query string before matching', () => {
    expect(isExcludedPath('/metrics?format=text')).toBe(true);
  });
});
