public struct SceneAuditSupportPolicy: Sendable {
    public static let s1 = Self()

    public init() {}

    public func evaluate(
        features: [SceneAuditFeatureObservation],
        diagnostics: [SceneAuditDiagnostic]
    ) -> SceneAuditStatus {
        if diagnostics.contains(where: {
            $0.severity == .error
        }) {
            return .invalid
        }
        if features.contains(where: {
            $0.support == .unsupported
                || $0.support == .unknown
        }) {
            return .unsupported
        }
        if diagnostics.contains(where: {
            $0.severity == .warning
        }) {
            return .degraded
        }
        if features.contains(where: {
            $0.support == .degraded
        }) {
            return .degraded
        }
        return .exact
    }
}
