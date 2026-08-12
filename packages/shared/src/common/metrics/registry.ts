import { Registry } from 'prom-client';

let _registry: Registry | undefined;

export function getSharedRegistry(): Registry {
  if (_registry === undefined) {
    _registry = new Registry();
  }
  return _registry;
}

/**
 * Replaces the shared singleton with a fresh registry.
 * Call in Jest beforeEach/afterEach to prevent metric re-registration errors.
 */
export function resetRegistryForTests(): void {
  _registry = new Registry();
}
