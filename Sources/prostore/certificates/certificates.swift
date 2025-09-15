// Sources/prostore/certificates/certificates.swift
// Put this file under Sources/prostore/certificates/

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
    case unsupportedPlatform
    case opensslError(String)
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
                // Fixed: Remove force casting CFError to NSError
                let nsError = cfError as NSError
                throw CertificateError.publicKeyExportFailed(OSStatus(nsError.code))
            } else {
                throw CertificateError.publicKeyExportFailed(-1)
            }
        }
        return keyData
    }

    // Parse PKCS#7 (DER) from the mobileprovision using OpenSSL functions,
    // convert X509 -> DER -> SecCertificate
    private static func certificatesFromMobileProvision(_ data: Data) throws -> [SecCertificate] {
        var certs: [SecCertificate] = []

        // Create BIO from data
        let bio = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> OpaquePointer? in
            guard let base = ptr.baseAddress else { return nil }
            return BIO_new_mem_buf(UnsafeMutableRawPointer(mutating: base), Int32(data.count))
        }

        guard let bioPtr = bio else {
            throw CertificateError.opensslError("BIO_new_mem_buf failed")
        }
        defer { BIO_free(bioPtr) }

        guard let p7 = d2i_PKCS7_bio(bioPtr, nil) else {
            throw CertificateError.opensslError("d2i_PKCS7_bio failed")
        }
        defer { PKCS7_free(p7) }

        // Get signers (stack of X509). PKCS7_get0_signers often returns an allocated stack pointer.
        guard let signers = PKCS7_get0_signers(p7, nil, 0) else {
            throw CertificateError.noCertsInProvision
        }

        // Fixed: Proper cast for signers to OpaquePointer (assuming signers is UnsafeMutableRawPointer)
        let stackPtr = OpaquePointer(UnsafeMutableRawPointer(signers))  // Tweak this if signers type is different

        // Use OPENSSL_sk_num and OPENSSL_sk_value with proper index types
        let count = Int(OPENSSL_sk_num(stackPtr))
        for i in 0..<count {
            guard let rawVal = OPENSSL_sk_value(stackPtr, Int32(i)) else { continue }
            // rawVal is UnsafeMutableRawPointer; interpret as X509*
            let x509Ptr = rawVal.assumingMemoryBound(to: X509.self)  // X509 should be in scope now

            // convert X509 -> DER
            var derPtr: UnsafeMutablePointer<UInt8>? = nil
            let derLen = i2d_X509(x509Ptr, &derPtr)
            guard derLen > 0, let dptr = derPtr else { continue }
            // wrap into Data
            let derData = Data(bytes: dptr, count: Int(derLen))
            // free OpenSSL buffer produced by i2d_X509
            OPENSSL_free(dptr)

            // create SecCertificate from DER
            if let secCert = SecCertificateCreateWithData(nil, derData as CFData) {
                certs.append(secCert)
            } else {
                // skip if cannot create
                continue
            }
        }

        // Fixed warning: Safer way to cast the free func without unsafeBitCast
        // Use a closure or direct cast if possible; here's a workaround
        OPENSSL_sk_pop_free(stackPtr) { ptr in
            X509_free(OpaquePointer(ptr))
        }

        guard certs.count > 0 else { throw CertificateError.noCertsInProvision }
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

        // Force-cast to SecIdentity (import guarantees this key exists for valid PKCS12)
        guard let first = items.first else {
            return .failure(CertificateError.identityExtractionFailed)
        }
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