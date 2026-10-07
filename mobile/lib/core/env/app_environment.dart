enum AppEnvironment {
  dev,
  staging,
  prod;

  /// Returns [selected], unless `--dart-define=APP_ENV=dev|staging|prod` overrides it.
  static AppEnvironment fromDefine(
      [AppEnvironment selected = AppEnvironment.dev]) {
    const value = String.fromEnvironment('APP_ENV');
    if (value.isEmpty) return selected;
    return AppEnvironment.values.firstWhere(
      (env) => env.name == value,
      orElse: () => selected,
    );
  }
}
