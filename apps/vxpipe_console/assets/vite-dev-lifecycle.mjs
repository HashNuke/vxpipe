export async function superviseVite({ createServer, exit, input, signals }) {
  const server = await createServer();

  await server.listen();
  server.printUrls();
  input.resume();

  let finish;
  const done = new Promise((resolve) => {
    finish = resolve;
  });
  let shutdown;

  const stop = () => {
    shutdown ??= (async () => {
      let exitCode = 0;

      try {
        await server.close();
      } catch (_error) {
        exitCode = 1;
      }

      exit(exitCode);
      finish();
    })();

    return shutdown;
  };

  input.once("end", stop);
  input.once("close", stop);
  signals.once("SIGINT", stop);
  signals.once("SIGTERM", stop);

  return { done, stop };
}
