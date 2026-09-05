/// Optional locations selected by the user for local setup checks.
///
/// The setup service reads these paths but never creates, edits, or deletes
/// anything beneath them. Validation and persistence belong to the caller.
class LocalSetupLocations {
  const LocalSetupLocations({
    this.gameDirectory,
    this.replayDirectory,
  });

  final String? gameDirectory;
  final String? replayDirectory;
}
