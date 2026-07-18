import Foundation
import LocalAuthentication

struct BiometricLock {
    func unlock(reason: String = "Unlock your Herdr control room") async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error { throw error }
            return false
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}
