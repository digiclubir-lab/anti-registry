import AudioToolbox
import Foundation

/// The iPhone's own sounds, played through AudioServices: no audio files are bundled, and
/// system sounds honour the Ring/Silent switch, exactly as in Apple's Phone and Messages.
/// The numeric IDs are not in the public SDK headers; the values below follow the widely
/// documented system-sound tables and should be confirmed on a device once a build exists
/// (DTMF block 1200–1211, received message 1003, sent message 1004).
enum Sounds {
    /// The dial tone for one keypad key ("0"–"9", "*", "#"), as in the Phone app.
    static func dtmf(_ key: String) {
        let id: SystemSoundID
        switch key {
        case "*": id = 1210
        case "#": id = 1211
        default:
            guard let digit = key.first?.wholeNumberValue else { return }
            id = SystemSoundID(1200 + digit)
        }
        AudioServicesPlaySystemSound(id)
    }

    /// The sound Messages plays when a text is sent.
    static func messageSent() { AudioServicesPlaySystemSound(1004) }

    /// The sound Messages plays when a text arrives while the app is open.
    static func messageReceived() { AudioServicesPlaySystemSound(1003) }
}
