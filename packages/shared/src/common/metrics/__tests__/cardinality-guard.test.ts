import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { checkCardinality, resetCardinalityStateForTests, getCardinalityCount } from '../cardinality-guard.js';

describe('cardinality guard', () => {
  beforeEach(() => {
    resetCardinalityStateForTests();
    jest.spyOn(process.stdout, 'write').mockImplementation(() => true);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('tracks unique label combinations per metric', () => {
    checkCardinality('my_metric', { org: 'org1', status: '200' });
    checkCardinality('my_metric', { org: 'org2', status: '200' });
    checkCardinality('my_metric', { org: 'org1', status: '200' }); // duplicate

    expect(getCardinalityCount('my_metric')).toBe(2);
  });

  it('tracks metrics independently', () => {
    checkCardinality('metric_a', { org: 'org1' });
    checkCardinality('metric_b', { org: 'org1' });

    expect(getCardinalityCount('metric_a')).toBe(1);
    expect(getCardinalityCount('metric_b')).toBe(1);
  });

  it('does not warn when cardinality is below threshold', () => {
    const writeSpy = jest.spyOn(process.stdout, 'write').mockImplementation(() => true);

    for (let i = 0; i < 100; i++) {
      checkCardinality('my_metric', { org: `org${i}` }, { threshold: 500 });
    }

    const warnLogged = (writeSpy.mock.calls as unknown[])
      .map((args) => String((args as [string])[0]))
      .some((s) => s.includes('cardinality'));
    expect(warnLogged).toBe(false);
  });

  it('logs a warning when cardinality exceeds custom threshold', () => {
    const writeSpy = jest.spyOn(process.stdout, 'write').mockImplementation(() => true);

    for (let i = 0; i <= 5; i++) {
      checkCardinality('my_metric', { org: `org${i}` }, { threshold: 4 });
    }

    const warnLogged = (writeSpy.mock.calls as unknown[])
      .map((args) => String((args as [string])[0]))
      .some((s) => s.includes('cardinality') || s.includes('Metric cardinality'));
    expect(warnLogged).toBe(true);
  });

  it('logs a warning when default 500 threshold is exceeded', () => {
    const writeSpy = jest.spyOn(process.stdout, 'write').mockImplementation(() => true);

    for (let i = 0; i <= 501; i++) {
      checkCardinality('big_metric', { org: `org${i}` });
    }

    const warnLogged = (writeSpy.mock.calls as unknown[])
      .map((args) => String((args as [string])[0]))
      .some((s) => s.includes('cardinality') || s.includes('threshold'));
    expect(warnLogged).toBe(true);
  });

  it('returns 0 for unknown metric', () => {
    expect(getCardinalityCount('nonexistent_metric')).toBe(0);
  });
});
