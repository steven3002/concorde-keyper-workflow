export type TelegramUpdate = {
  readonly update_id: number;
  readonly message?: {
    readonly message_id: number;
    readonly text?: string;
    readonly chat: { readonly id: number; readonly type: string };
    readonly from?: { readonly id: number; readonly username?: string };
  };
};

export class UpdateQueue {
  private queue: TelegramUpdate[] = [];
  private waiters: Array<() => void> = [];

  push(update: TelegramUpdate): void {
    this.queue.push(update);
    const waiting = [...this.waiters];
    this.waiters = [];
    for (const wake of waiting) {
      wake();
    }
  }

  async poll(
    offset: number | undefined,
    timeoutSeconds: number,
    signal?: AbortSignal,
  ): Promise<TelegramUpdate[]> {
    if (offset !== undefined) {
      this.queue = this.queue.filter((u) => u.update_id >= offset);
    }

    if (this.queue.length > 0) {
      return [...this.queue];
    }

    if (timeoutSeconds <= 0 || signal?.aborted) {
      return [];
    }

    await new Promise<void>((resolve) => {
      let timer: NodeJS.Timeout | undefined;

      const finish = () => {
        if (timer !== undefined) clearTimeout(timer);
        signal?.removeEventListener("abort", onAbort);
        const index = this.waiters.indexOf(finish);
        if (index >= 0) this.waiters.splice(index, 1);
        resolve();
      };

      const onAbort = () => finish();

      signal?.addEventListener("abort", onAbort, { once: true });
      timer = setTimeout(finish, timeoutSeconds * 1000);
      this.waiters.push(finish);
    });

    if (offset !== undefined) {
      this.queue = this.queue.filter((u) => u.update_id >= offset);
    }
    return [...this.queue];
  }
}
