import AIKeyboardCore
import CryptoKit
import DeviceCheck
import Foundation

/// Proves to the backend that this is a genuine, unmodified build of this app on
/// real Apple hardware, and stores the token that proof buys.
///
/// **This lives in the containing app and nowhere else.** The keyboard and the
/// broadcast extension are separate bundle IDs, so an attestation raised there
/// would name a different app; Apple rate-limits attestation, so a keyboard
/// cannot do it per tap; and a keyboard extension has no network at all until
/// Full Access is granted. They read the token this writes, through the App
/// Group, exactly as they read the one that used to be typed in.
///
/// Everything here fails quietly. There is no screen to put an error on and
/// nothing the user could do about it: an install with no token reports
/// `.cloudNotConfigured` at the moment an AI action is tapped, which is where
/// the sentence belongs.
public enum AppAttestation {

    /// Renew once the token is a third of the way through its life.
    ///
    /// The backend issues ninety days. Refreshing at thirty means a user who
    /// opens the app even occasionally is never near the edge, and the sixty-day
    /// margin is for the user who does not: they keep working until they do.
    static let refreshAfter: TimeInterval = 30 * 24 * 60 * 60

    /// Called at launch. Does nothing at all in the common case.
    public static func refreshIfNeeded(store: SharedStore) async {
        guard needsRefresh(store: store) else { return }
        guard DCAppAttestService.shared.isSupported else { return }
        try? await attest(store: store)
    }

    static func needsRefresh(store: SharedStore) -> Bool {
        let existing = store.cloudSessionToken
        guard !existing.isEmpty, let expiry = SessionToken.expiry(of: existing) else { return true }
        return expiry.timeIntervalSinceNow < (90 * 24 * 60 * 60) - refreshAfter
    }

    static func attest(store: SharedStore) async throws {
        let base = URL(string: BackendTransport.effectiveURL())!
        let service = DCAppAttestService.shared

        let challenge = try await fetchChallenge(base: base)

        // A fresh key every time, rather than reusing one and sending an
        // assertion. Assertions are Apple's cheap path, and they are declined
        // here on purpose: verifying one requires the server to remember that
        // device's public key and signature counter, and the counter is what
        // makes an assertion replay-proof. That is a database, and the whole
        // design turns on not having one. Twelve attestations a device a year
        // is nothing against Apple's limits.
        let keyId = try await service.generateKey()
        let attestation = try await service.attestKey(
            keyId, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))

        var request = URLRequest(url: base.appendingPathComponent("v1/attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyId": keyId,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = body["token"] as? String
        else { return }

        store.cloudSessionToken = token
    }

    private static func fetchChallenge(base: URL) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("v1/challenge"))
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let challenge = body["challenge"] as? String
        else { throw URLError(.cannotParseResponse) }
        return challenge
    }
}
