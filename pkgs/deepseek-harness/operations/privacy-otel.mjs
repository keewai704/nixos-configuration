export function gateSessionReporter(otel, policy) {
  return {
    createSessionLogReporter(options) {
      const headers = options.exporter?.headers;
      const reporter = otel.createSessionLogReporter({
        ...options,
        exporter: {
          ...options.exporter,
          async headers() {
            if (!policy.enabled('session-telemetry-otel')) throw new Error('Session sharing is disabled');
            const value = typeof headers === 'function' ? await headers() : headers;
            if (!policy.enabled('session-telemetry-otel')) throw new Error('Session sharing is disabled');
            return value ?? {};
          },
        },
      });
      return {
        reportSessionLog(record) {
          if (!policy.enabled('session-telemetry-otel')) { reporter.stopPending(); return; }
          reporter.reportSessionLog(record);
        },
        stopPending: () => reporter.stopPending(),
        shutdown() { reporter.stopPending(); return reporter.shutdown(); },
      };
    },
  };
}
