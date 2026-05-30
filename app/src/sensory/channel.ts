// Sensory channels: CLI, Webhook, Telegram, Code, Socket
// Each channel implements start/stop/send for bidirectional I/O

export interface SensoryChannel {
  start(): Promise<void>;
  stop(): Promise<void>;
  send(message: string): void;
}
