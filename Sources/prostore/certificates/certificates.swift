// certificates/certificates.swift
// Put this file under certificates/ in your project

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
    case cmsDecodeFailed(OSStatus)
    case noCertsInProvision
    case publicKeyExportFailed(OSStatus)
}

public final class CertificatesManager {
    /// SHA256 hex from Data
    private static func sha256Hex(_ d: Data) -> String {
        let digest = SHA256.hash(data: d)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Export public key bytes for a certificate (SecCertificate -> SecKey -> external representation)
    private static func publicKeyData(from cert: SecCertificate) throws -> Data {
        guard let secKey = SecCertificateCopyKey(cert) else {
            throw CertificateError.certExtractionFailed
        }
        var cfErr: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(secKey, &cfErr) as Data? else {
            if let err = cfErr?.takeRetainedValue() {
                throw CertificateError.publicKeyExportFailed((err as NSError).code as OSStatus)
            } else {
                throw CertificateError.publicKeyExportFailed(-1)
            }
        }
        return keyData
    }

    /// Parse .mobileprovision CMS/PKCS#7 and return embedded SecCertificate array
    private static func certificatesFromMobileProvision(_ data: Data) throws -> [SecCertificate] {
        var decoder: CMSDecoder? = nil
        var status = CMSDecoderCreate(&decoder)
        guard status == errSecSuccess, let dec = decoder else {
            throw CertificateError.cmsDecodeFailed(status)
        }

        // feed bytes
        _ = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = ptr.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(dec, base, data.count)
        }

        status = CMSDecoderFinalizeMessage(dec)
        guard status == errSecSuccess else {
            throw CertificateError.cmsDecodeFailed(status)
        }

        var certsCF: CFArray? = nil
        status = CMSDecoderCopyAllCerts(dec, &certsCF)
        guard status == errSecSuccess, let certs = certsCF as? [SecCertificate], certs.count > 0 else {
            throw CertificateError.noCertsInProvision
        }

        return certs
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

        guard let first = items.first,
              let identity = first[kSecImportItemIdentity as String] as? SecIdentity else {
            return .failure(CertificateError.identityExtractionFailed)
        }

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

            // 4) parse mobileprovision and check embedded certs
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