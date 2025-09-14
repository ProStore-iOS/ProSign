import Foundation
import ZsignSwift

struct FileItem {
    var url: URL?
    var name: String { url?.lastPathComponent ?? "" }
}

class SigningManager {
    static func sign(
        appPath: String,
        provisionPath: String,
        p12Path: String,
        p12Password: String,
        entitlementsPath: String,
        removeProvision: Bool,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        Zsign.sign(
            appPath: appPath,
            provisionPath: provisionPath,
            p12Path: p12Path,
            p12Password: p12Password,
            entitlementsPath: entitlementsPath,
            removeProvision: removeProvision,
            completion: completion
        )
    }
}