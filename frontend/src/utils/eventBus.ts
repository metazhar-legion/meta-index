import { createLogger } from './logging';

// Simple event bus for component communication
type EventCallback = (...args: any[]) => void;

interface EventMap {
  [eventName: string]: EventCallback[];
}

const logger = createLogger('EventBus');

class EventBus {
  private events: EventMap = {};

  // Subscribe to an event
  on(eventName: string, callback: EventCallback) {
    if (!this.events[eventName]) {
      this.events[eventName] = [];
    }
    this.events[eventName].push(callback);

    // Return unsubscribe function
    return () => {
      this.off(eventName, callback);
    };
  }

  // Unsubscribe from an event
  off(eventName: string, callback: EventCallback) {
    if (this.events[eventName]) {
      this.events[eventName] = this.events[eventName].filter(
        (cb) => cb !== callback
      );
    }
  }

  // Emit an event
  emit(eventName: string, ...args: any[]) {
    logger.debug(`Emitting event: ${eventName}`, args.length > 0 ? args[0] : 'No data');
    
    if (this.events[eventName] && this.events[eventName].length > 0) {
      logger.debug(`Found ${this.events[eventName].length} listeners for event: ${eventName}`);
      this.events[eventName].forEach((callback) => {
        try {
          callback(...args);
        } catch (error) {
          logger.error(`Error in event listener for ${eventName}:`, error);
        }
      });
    } else {
      logger.debug(`No listeners found for event: ${eventName}`);
    }
  }
}

// Create a singleton instance
const eventBus = new EventBus();

// Define event names
export const EVENTS = {
  VAULT_TRANSACTION_COMPLETED: 'VAULT_TRANSACTION_COMPLETED',
  WALLET_CONNECTED: 'WALLET_CONNECTED',
};

export default eventBus;
