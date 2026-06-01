import UIKit
import Combine

/// Manages the "transmission" share/AirDrop exchange for Level 28.
///
/// DESIGN (Wave-2b rework): the level no longer shows the answer in plaintext.
/// The terminal shows a SCRAMBLED ciphertext plus a visible shift rule. The only
/// ways to learn the real 6-char plaintext code are:
///   1. SHARE the transmission — the share payload contains the *decoded* code,
///      which the player reads back from wherever they sent it (Notes, Messages,
///      AirDrop to another device, etc). Sharing is what decodes it.
///   2. The Wave-2b accessibility fallback, which posts `.airdropReceived(code:)`
///      carrying the decoded code so the level is still completable hands-free.
///
/// The manager owns the cipher so the share payload and the fallback agree on the
/// exact decoded string for whatever code the scene generated.
final class AirDropManager: DeviceManager {
    static let shared = AirDropManager()

    let supportedMechanics: Set<MechanicType> = [.airdrop]

    private var isActive = false

    /// The decoded plaintext the door accepts. Set by the scene via `prepare(plaintext:shift:)`
    /// so the manager and the scene never disagree about the answer.
    private(set) var plaintextCode: String = ""
    /// The scrambled ciphertext shown on the terminal. The player must NOT be able
    /// to type this in directly — it decodes to `plaintextCode`.
    private(set) var ciphertext: String = ""
    /// Caesar-style shift applied to derive ciphertext from plaintext over the
    /// level's symbol alphabet. Displayed to the player as the visible rule.
    private(set) var shift: Int = 0

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true
        print("AirDropManager: Activated - plaintext: \(plaintextCode) cipher: \(ciphertext) shift: \(shift)")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        print("AirDropManager: Deactivated")
    }

    /// Configure the exchange for a freshly generated puzzle. The scene generates the
    /// plaintext + shift, derives the ciphertext with `Self.encode`, and hands all of
    /// it here so the share payload (and any fallback) carry the SAME decoded answer.
    func prepare(plaintext: String, ciphertext: String, shift: Int) {
        self.plaintextCode = plaintext
        self.ciphertext = ciphertext
        self.shift = shift
    }

    /// Shared symbol alphabet (ambiguity-free: no I/O/0/1). Both the cipher and the
    /// in-game keyboard draw from this so a shifted symbol is always a valid symbol.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// Caesar-shift a string forward over `alphabet`. Used to derive the displayed
    /// ciphertext from the secret plaintext.
    static func encode(_ plaintext: String, shift: Int) -> String {
        shifted(plaintext, by: shift)
    }

    /// Reverse the shift to recover plaintext from ciphertext. This is the operation
    /// the player performs "for free" by sharing — the share payload is pre-decoded.
    static func decode(_ ciphertext: String, shift: Int) -> String {
        shifted(ciphertext, by: -shift)
    }

    private static func shifted(_ text: String, by delta: Int) -> String {
        let n = alphabet.count
        return String(text.compactMap { ch -> Character? in
            guard let idx = alphabet.firstIndex(of: ch) else { return ch }
            let newIdx = ((idx + delta) % n + n) % n
            return alphabet[newIdx]
        })
    }

    /// Validate a typed/received code against the decoded plaintext. Posts the
    /// `.airdropReceived` event on a match so the scene can unlock.
    func validateCode(_ code: String) {
        let isValid = code.uppercased() == plaintextCode.uppercased()
        if isValid {
            DispatchQueue.main.async {
                InputEventBus.shared.post(.airdropReceived(code: code))
            }
        }
    }

    /// Creates a UIActivityViewController whose payload is the DECODED code. Sharing
    /// is the diegetic "decode" step: the player sends the cleartext to themselves
    /// (Notes/Messages/AirDrop) and reads it back to type it in. Without sharing they
    /// only ever see the scrambled ciphertext on the terminal.
    func createShareActivity() -> UIActivityViewController {
        let text = "GLITCHED TRANSMISSION — DECODED CODE: \(plaintextCode)"
        let activity = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        activity.excludedActivityTypes = [.postToFacebook, .postToTwitter, .postToWeibo]
        return activity
    }
}
