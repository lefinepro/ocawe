import { afterAll, afterEach, beforeAll } from "bun:test";
import { setupServer } from "msw/node";

export const server = setupServer();

export function useMswLifecycle(): void {
  beforeAll(() => {
    server.listen({ onUnhandledRequest: "error" });
  });

  afterEach(() => {
    server.resetHandlers();
  });

  afterAll(() => {
    server.close();
  });
}
