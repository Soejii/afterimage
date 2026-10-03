/// Process boundary for the optional notes finder.
///
/// The recorder never depends on a concrete process launcher. Tests can use a
/// fake that records the requested batch folder without starting Python.
abstract interface class FinderPort {
  bool get available;

  Future<void> startBatch(String batchFolder);
}
