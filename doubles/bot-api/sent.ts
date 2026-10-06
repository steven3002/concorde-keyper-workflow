export type SentMessage = {
  readonly messageId: number;
  readonly chatId: string;
  readonly text: string;
  readonly recordedAt: string;
};

export class SentStore {
  private messages: SentMessage[] = [];

  record(chatId: string, text: string): SentMessage {
    const message: SentMessage = {
      messageId: this.messages.length + 1,
      chatId,
      text,
      recordedAt: new Date().toISOString(),
    };
    this.messages.push(message);
    return message;
  }

  list(): readonly SentMessage[] {
    return [...this.messages];
  }

  clear(): void {
    this.messages = [];
  }
}
