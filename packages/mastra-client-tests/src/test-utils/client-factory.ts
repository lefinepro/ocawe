import { MastraClient } from "@mastra/client-js";

export const TEST_BASE_URL = "http://mastra.local";

export function createClient(init?: Record<string, unknown>): any {
  return new MastraClient({ baseUrl: TEST_BASE_URL, ...init } as any);
}
