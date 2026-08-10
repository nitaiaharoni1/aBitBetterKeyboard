import Foundation

/// Reads the expiry out of a session token **without verifying it**, and that
/// distinction is the whole of this file.
///
/// The app holds no signing secret — that is the point of the design — so it
/// cannot tell a real token from one somebody wrote. It does not need to: the
/// backend checks the signature on every call, and the only question here is
/// "is there any point sending this one", which decides whether a screen says
/// the cloud is set up and whether the app bothers re-attesting. A forged token
/// gets a 401 from the service exactly as an absent one does.
public enum SessionToken {

    public static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let payload = decodeBase64URL(String(parts[1])),
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let expiry = object["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: expiry)
    }

    /// Base64URL, which is not what `Data(base64Encoded:)` reads: JWTs swap
    /// `+/` for `-_` and drop the padding, and a decoder that ignores both
    /// returns nil for most real tokens.
    private static func decodeBase64URL(_ value: String) -> Data? {
        var text = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text.append("=") }
        return Data(base64Encoded: text)
    }
}
