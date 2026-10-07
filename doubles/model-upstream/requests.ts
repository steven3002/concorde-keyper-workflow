export interface RecordedRequest {
  timestamp: string;
  method: string;
  url: string;
  headers: Record<string, string | string[] | undefined>;
  body: unknown;
}

export class RequestStore {
  private requests: RecordedRequest[] = [];

  record(req: RecordedRequest): void {
    this.requests.push(req);
  }

  list(): RecordedRequest[] {
    return [...this.requests];
  }

  clear(): void {
    this.requests = [];
  }
}
