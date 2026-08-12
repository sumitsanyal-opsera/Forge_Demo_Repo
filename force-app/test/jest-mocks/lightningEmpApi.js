// Jest mock for lightning/empApi
// Provides subscribe, unsubscribe, and onError as jest.fn() so tests can
// inspect calls and manually invoke registered callbacks.
//
// Usage in tests:
//   import { subscribe, unsubscribe, onError } from 'lightning/empApi';
//   const [channel, replayId, callback] = subscribe.mock.calls[0];
//   callback({ data: { payload: { ... } } });

const subscribe = jest.fn().mockResolvedValue({ id: 'mock-subscription' });
const unsubscribe = jest.fn().mockResolvedValue({});
const onError = jest.fn();

export { subscribe, unsubscribe, onError };
