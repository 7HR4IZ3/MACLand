import CryptoKit
import Foundation
import Security

struct TLSIdentityMaterial {
    let identity: sec_identity_t
    let certificatePinning: CertificatePinningMetadata
}

enum TLSIdentityStoreError: LocalizedError, Equatable {
    case missing(label: String)
    case keychain(OSStatus)
    case certificateUnavailable
    case certificateDataUnavailable

    var errorDescription: String? {
        switch self {
        case let .missing(label):
            return "No TLS identity named ‘\(label)’ is installed in the login keychain."
        case let .keychain(status):
            return "The login keychain could not provide the MACLand TLS identity (OSStatus \(status))."
        case .certificateUnavailable:
            return "The installed TLS identity does not contain a certificate."
        case .certificateDataUnavailable:
            return "The installed TLS certificate could not be read for pinning."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .missing(label):
            return "Install a certificate and private key in Keychain Access with the label ‘\(label)’, then restart MACLand Host."
        case .keychain, .certificateUnavailable, .certificateDataUnavailable:
            return "Check that the certificate and private key are present in the login keychain and accessible to MACLand Host."
        }
    }
}

/// Loads a user-provisioned identity instead of generating or accepting an
/// unauthenticated certificate at runtime. This keeps the first LAN transport
/// secure and makes the provisioning boundary explicit for the sandboxed host.
struct KeychainTLSIdentityStore {
    static let defaultLabel = "com.thraize.macland.host.tls"

    let label: String

    init(label: String = KeychainTLSIdentityStore.defaultLabel) {
        self.label = label
    }

    func load() throws -> TLSIdentityMaterial {
        var item: CFTypeRef?
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: label,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw TLSIdentityStoreError.missing(label: label)
            }
            if status == errSecAuthFailed || status == errSecInteractionNotAllowed {
                throw TLSIdentityStoreError.keychain(status)
            }
            throw TLSIdentityStoreError.keychain(status)
        }

        guard let item,
              CFGetTypeID(item) == SecIdentityGetTypeID() else {
            throw TLSIdentityStoreError.keychain(errSecDecode)
        }
        let identity = item as! SecIdentity

        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
              let certificate else {
            throw TLSIdentityStoreError.certificateUnavailable
        }
        let certificateData = SecCertificateCopyData(certificate) as Data
        guard !certificateData.isEmpty else {
            throw TLSIdentityStoreError.certificateDataUnavailable
        }

        let digest = SHA256.hash(data: certificateData)
        let digestString = digest.map { String(format: "%02x", $0) }.joined()
        let pinning = CertificatePinningMetadata(
            certificateSHA256: digestString
        )

        guard let protocolIdentity = sec_identity_create(identity) else {
            throw TLSIdentityStoreError.keychain(errSecDecode)
        }

        return TLSIdentityMaterial(
            identity: protocolIdentity,
            certificatePinning: pinning
        )
    }
}
