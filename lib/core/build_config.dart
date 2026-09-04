const seilLegacySharedSshQueue = bool.fromEnvironment(
  'SEIL_LEGACY_SSH_QUEUE',
  defaultValue: false,
);

const seilPerformanceTestLabel = String.fromEnvironment(
  'SEIL_PERFORMANCE_TEST_LABEL',
  defaultValue: '',
);

String get seilAppTitle => seilPerformanceTestLabel.isEmpty
    ? 'Seil'
    : 'Seil $seilPerformanceTestLabel';
