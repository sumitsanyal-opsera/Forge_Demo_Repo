import { EventEmitter } from 'node:events';
import type { StatusChangeEvent } from './types.js';

/**
 * Typed event bus for connector health status-change notifications.
 * Wraps Node.js EventEmitter with a named, typed API for the health subsystem.
 */
export class EventBus extends EventEmitter {
  onStatusChange(listener: (event: StatusChangeEvent) => void): this {
    return this.on('statusChange', listener);
  }

  offStatusChange(listener: (event: StatusChangeEvent) => void): this {
    return this.off('statusChange', listener);
  }

  emitStatusChange(event: StatusChangeEvent): boolean {
    return this.emit('statusChange', event);
  }
}

/** Singleton EventBus for the health monitoring subsystem. */
export const globalHealthEventBus = new EventBus();
