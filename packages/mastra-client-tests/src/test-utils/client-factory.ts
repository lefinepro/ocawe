import { MastraClient } from "@mastra/client-js";
import { ensureTestService } from "./test-service";

export async function createClient(init?: Record<string, unknown>): Promise<any> {
  const baseUrl = await ensureTestService();
  return new MastraClient({ baseUrl, ...init } as any);
}
