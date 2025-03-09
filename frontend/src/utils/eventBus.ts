// Simple event bus for component communication
type EventCallback = (...args: any[]) => void;

interface EventMap {
  [eventName: string]: EventCallback[];
}

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
    if (this.events[eventName]) {
      this.events[eventName].forEach((callback) => {
        callback(...args);
      });
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
