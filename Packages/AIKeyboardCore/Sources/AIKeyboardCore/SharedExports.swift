/// `AIKeyboardShared` holds the Foundation-only half of this package: the
/// capture channel, the frame fingerprint, the reading record and the end
/// reasons. It exists as a separate target for one reason — the broadcast upload
/// extension needs those types and must never link `AIKeyboardCore`, which pulls
/// SwiftUI and UIKit into a process capped at ~50 MB.
///
/// Re-exported so nothing that already imports `AIKeyboardCore` has to know the
/// split happened.
@_exported import AIKeyboardShared
