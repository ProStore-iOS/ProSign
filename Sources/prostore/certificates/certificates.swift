import Foundation
import Security
import CryptoKit

public enum CertificateCheckResult {
    case incorrectPassword
    case noMatch
    case success
}

public enum CertificateError: Error {
    case p12ImportFailed(OSStatus)
    case identityExtractionFailed
    case certExtractionFailed
    case noCertsInProvision
    case publicKeyExportFailed(OSStatus)
    case plistExtractionFailed
    case unknown
}

public final class CertificatesManager {
    // SHA256 hex from Data
    private static func sha256Hex(_ d: Data) -> String {
        let digest = SHA256.hash(data: d)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // Export public key bytes for a certificate (SecCertificate -> SecKey -> external representation)
    private static func publicKeyData(from cert: SecCertificate) throws -> Data {
        guard let secKey = SecCertificateCopyKey(cert) else {
            throw CertificateError.certExtractionFailed
        }

        var cfErr: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(secKey, &cfErr) as Data? else {
            if let cfError = cfErr?.takeRetainedValue() {
                // get numeric code from CFError safely
                let code = CFErrorGetCode(cfError)
                throw CertificateError.publicKeyExportFailed(OSStatus(code))
            } else {
                throw CertificateError.publicKeyExportFailed(-1)
            }
        }
        return keyData
    }

    // Extract the <plist>...</plist> portion from a .mobileprovision (PKCS7) blob,
    // parse it to a dictionary and return SecCertificate objects from DeveloperCertificates.
    private static func certificatesFromMobileProvision(_ data: Data) throws -> [SecCertificate] {
        // Find XML plist bounds inside the blob
        let startTag = Data("<plist".utf8)
        let endTag = Data("</plist>".utf8)

        guard let startRange = data.range(of: startTag),
              let endRange = data.range(of: endTag) else {
            throw CertificateError.plistExtractionFailed
        }

        // endRange.upperBound is index after </plist>
        let plistData = data[startRange.lowerBound..<endRange.upperBound]

        // Parse plist
        let parsed = try PropertyListSerialization.propertyList(from: Data(plistData), options: [], format: nil)
        guard let dict = parsed as? [String: Any] else {
            throw CertificateError.plistExtractionFailed
        }

        // Typical key with embedded certs in provisioning profiles:
        // "DeveloperCertificates" -> [Data] (DER blobs)
        var resultCerts: [SecCertificate] = []

        if let devArray = dict["DeveloperCertificates"] as? [Any] {
            for item in devArray {
                if let certData = item as? Data {
                    if let secCert = SecCertificateCreateWithData(nil, certData as CFData) {
                        resultCerts.append(secCert)
                    }
                } else if let base64String = item as? String,
                          let certData = Data(base64Encoded: base64String) {
                    if let secCert = SecCertificateCreateWithData(nil, certData as CFData) {
                        resultCerts.append(secCert)
                    }
                } else {
                    // ignore unknown item types
                    continue
                }
            }
        }

        if resultCerts.isEmpty {
            throw CertificateError.noCertsInProvision
        }

        return resultCerts
    }

    /// Top-level check: returns result
    /// - Parameters:
    ///   - p12Data: contents of .p12
    ///   - password: p12 password
    ///   - mobileProvisionData: contents of .mobileprovision
    public static func check(p12Data: Data, password: String, mobileProvisionData: Data) -> Result<CertificateCheckResult, Error> {
        // 1) try import .p12 (also verifies password)
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var itemsCF: CFArray?
        let importStatus = SecPKCS12Import(p12Data as CFData, options, &itemsCF)

        if importStatus == errSecAuthFailed {
            return .success(.incorrectPassword)
        }

        guard importStatus == errSecSuccess, let items = itemsCF as? [[String: Any]], items.count > 0 else {
            return .failure(CertificateError.p12ImportFailed(importStatus))
        }

        // Grab identity (force-cast is safe because import succeeded and the dictionary contains the identity)
        guard let first = items.first else {
            return .failure(CertificateError.identityExtractionFailed)
        }
        // use force-cast to avoid "conditional downcast ... will always succeed" warnings
        let identity = first[kSecImportItemIdentity as String] as! SecIdentity

        // 2) extract certificate from identity
        var certRef: SecCertificate?
        let certStatus = SecIdentityCopyCertificate(identity, &certRef)
        guard certStatus == errSecSuccess, let p12Cert = certRef else {
            return .failure(CertificateError.certExtractionFailed)
        }

        // 3) get public key bytes and hash
        do {
            let p12PubKeyData = try publicKeyData(from: p12Cert)
            let p12Hash = sha256Hex(p12PubKeyData)

            // 4) parse mobileprovision and check embedded certs (no OpenSSL)
            let embeddedCerts = try certificatesFromMobileProvision(mobileProvisionData)

            for cert in embeddedCerts {
                do {
                    let embPubKeyData = try publicKeyData(from: cert)
                    let embHash = sha256Hex(embPubKeyData)
                    if embHash == p12Hash {
                        return .success(.success)
                    }
                } catch {
                    // ignore this cert and continue
                    continue
                }
            }

            // if none matched
            return .success(.noMatch)
        } catch {
            return .failure(error)
        }
    }
}